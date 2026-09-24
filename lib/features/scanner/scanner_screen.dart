import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../data/border_detector.dart';
import '../../data/card_matcher.dart';
import '../../data/models/card_set.dart';
import '../../data/models/trek_card.dart';
import '../../data/rotated_capture.dart';
import '../../state/providers.dart';
import '../card_detail/card_detail_screen.dart';
import 'continuous_scan_screen.dart';

enum _ScanState { idle, capturing, processing, results, added, noMatch, error }

Future<void> _deleteQuietly(String path) async {
  try {
    await File(path).delete();
  } catch (_) {
    // Best-effort cleanup of a temp capture file; not worth surfacing.
  }
}

/// Picks the back camera to scan with, preferring the ultra-wide lens when
/// the device has one. Card scanning is a macro-range task -- the card is
/// held close enough to fill the frame -- and the standard wide lens' much
/// longer minimum focus distance can't rack focus that close on some
/// devices. The system Camera app handles this by auto-switching to the
/// ultra-wide lens for "macro mode", but that's driven by an internal
/// Apple multi-camera device this plugin doesn't expose (it only lists the
/// physical lenses individually) -- so pick the ultra-wide lens ourselves
/// instead. Falls back to whatever back camera is available (e.g. on
/// Android, where lensType isn't populated the same way and this simply
/// never matches).
CameraDescription _pickBackCamera(List<CameraDescription> cameras) {
  final backCameras = cameras.where((c) => c.lensDirection == CameraLensDirection.back).toList();
  if (backCameras.isEmpty) return cameras.first;
  return backCameras.firstWhere(
    (c) => c.lensType == CameraLensType.ultraWide,
    orElse: () => backCameras.first,
  );
}

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  _ScanState _state = _ScanState.idle;
  String? _errorMessage;
  CardMatchResult? _result;
  String? _borderDebug;

  TrekCard? _addedCard;
  CardSet? _addedSet;
  int _addedQuantity = 0;

  CameraController? _cameraController;
  bool _torchOn = true;
  final _previewKey = GlobalKey();

  // Visual confirmation that a focus tap was registered and whether the
  // underlying camera call actually succeeded -- without this there's no way
  // to tell "nothing happened because the tap didn't register" apart from
  // "the tap worked but the device rejected the focus/exposure call".
  Offset? _focusIndicatorPos;
  bool _focusIndicatorOk = true;
  Timer? _focusIndicatorTimer;

  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void dispose() {
    _cameraController?.dispose();
    _recognizer.close();
    _focusIndicatorTimer?.cancel();
    super.dispose();
  }

  /// Marks [card] owned (quantity +1) and shows the confirmation view.
  Future<void> _addCard(TrekCard card, CardSet? set) async {
    final updated = await ref.read(collectionRepositoryProvider).incrementOwned(card.id);
    ref.read(collectionRevisionProvider.notifier).state++;
    if (!mounted) return;
    setState(() {
      _state = _ScanState.added;
      _addedCard = card;
      _addedSet = set;
      _addedQuantity = updated.quantity;
    });
  }

  /// Opens a live in-app camera preview instead of handing off to the
  /// system camera app -- that external hand-off is what put an "is this
  /// OK?" confirm/retake screen between the shutter and actually reading
  /// the card. Owning the capture ourselves means tapping the shutter goes
  /// straight into analysis.
  Future<void> _openCamera() async {
    setState(() {
      _state = _ScanState.capturing;
      _errorMessage = null;
    });
    try {
      final cameras = await availableCameras();
      final back = _pickBackCamera(cameras);
      // veryHigh, not max -- this is a single deliberate shot, not bulk
      // scanning, so a slower max-res capture isn't worth the wait here.
      final controller = CameraController(back, ResolutionPreset.veryHigh, enableAudio: false);
      await controller.initialize();

      if (_torchOn) {
        try {
          await controller.setFlashMode(FlashMode.torch);
        } catch (_) {
          // Some devices/cameras don't support a torch; scanning still works without it.
        }
      }
      try {
        // Bias focus toward the card's right edge, where the tiny sideways
        // copyright/year text sits -- see continuous_scan_screen.dart for
        // the same reasoning.
        await controller.setFocusMode(FocusMode.auto);
        await controller.setFocusPoint(const Offset(0.85, 0.5));
      } catch (_) {
        // Focus point control not supported on this device.
      }

      if (!mounted) return;
      setState(() => _cameraController = controller);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ScanState.error;
        _errorMessage = 'Could not start the camera: $e';
      });
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _cameraController;
    if (controller == null) return;
    final next = !_torchOn;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _torchOn = next);
    } catch (_) {
      // Device/camera doesn't support a torch -- leave state as it was.
    }
  }

  // Lets you tap the card in the preview to force a refocus there, the same
  // as the system Camera app -- the auto focus point set at startup is a
  // reasonable default, but doesn't always lock onto the card on every
  // device/lens.
  Future<void> _onTapToFocus(TapUpDetails details) async {
    final controller = _cameraController;
    final box = _previewKey.currentContext?.findRenderObject() as RenderBox?;
    if (controller == null || box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    final normalized = Offset(
      (local.dx / box.size.width).clamp(0.0, 1.0),
      (local.dy / box.size.height).clamp(0.0, 1.0),
    );

    _focusIndicatorTimer?.cancel();
    var ok = true;
    try {
      await controller.setFocusPoint(normalized);
      await controller.setExposurePoint(normalized);
    } catch (_) {
      // Focus/exposure point control not supported on this device.
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _focusIndicatorPos = local;
      _focusIndicatorOk = ok;
    });
    _focusIndicatorTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _focusIndicatorPos = null);
    });
  }

  void _cancelCapture() {
    final controller = _cameraController;
    _cameraController = null;
    controller?.dispose();
    setState(() => _state = _ScanState.idle);
  }

  Future<void> _capture() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() => _state = _ScanState.processing);
    // Free the camera hardware while OCR/matching runs -- this is a single
    // shot, not a live feed, so there's nothing left to preview.
    _cameraController = null;
    XFile file;
    try {
      file = await controller.takePicture();
    } finally {
      await controller.dispose();
    }
    await _processPhoto(file.path);
  }

  Future<void> _processPhoto(String path) async {
    try {
      final recognized = await _recognizer.processImage(InputImage.fromFilePath(path));
      final rotatedRecognized = await recognizeRotatedForYear(path, _recognizer);
      final borderSample = await sampleBorder(path);
      _borderDebug = borderSample.debug;
      final names = await ref.read(distinctCardNamesProvider.future);
      final result = await matchCardFromOcr(
        recognized: recognized,
        rotatedRecognized: rotatedRecognized,
        repo: ref.read(cardRepositoryProvider),
        names: names,
        detectedBorderColor: borderSample.color,
        cornerLuminance: borderSample.cornerLuminance,
      );

      if (!mounted) return;
      if (!result.hasText) {
        setState(() {
          _state = _ScanState.error;
          _errorMessage = 'Could not read any text on that photo. Try a closer, well-lit shot of the card.';
          _result = result;
        });
        return;
      }
      if (result.candidates.isEmpty) {
        setState(() {
          _state = _ScanState.noMatch;
          _result = result;
        });
        return;
      }
      if (result.autoPick != null) {
        await _addCard(result.autoPick!.card, result.autoPick!.set);
        return;
      }
      setState(() {
        _state = _ScanState.results;
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ScanState.error;
        _errorMessage = 'Something went wrong reading that photo: $e';
      });
    } finally {
      await _deleteQuietly(path);
    }
  }

  void _openBulkScan() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ContinuousScanScreen()));
  }

  // The Scan tab stays mounted in the background to preserve its state
  // across tab switches (see HomeShell's IndexedStack), so once a scan
  // finishes there was previously no way back to the idle screen -- and
  // thus no way to reach "Bulk Scan (live)" -- without this.
  void _backToIdle() {
    setState(() => _state = _ScanState.idle);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: switch (_state) {
          _ScanState.idle => _IdleView(onScan: _openCamera, onBulkScan: _openBulkScan),
          _ScanState.capturing => _CapturingView(
              controller: _cameraController,
              torchOn: _torchOn,
              previewKey: _previewKey,
              onCapture: _capture,
              onToggleTorch: _toggleTorch,
              onCancel: _cancelCapture,
              onTapToFocus: _onTapToFocus,
              focusIndicatorPos: _focusIndicatorPos,
              focusIndicatorOk: _focusIndicatorOk,
            ),
          _ScanState.processing => const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Reading card...'),
                ],
              ),
            ),
          _ScanState.error => _MessageView(
              icon: Icons.error_outline,
              message: _errorMessage ?? 'Something went wrong.',
              onRetry: _openCamera,
              onDone: _backToIdle,
              result: _result,
              borderDebug: _borderDebug,
            ),
          _ScanState.noMatch => _MessageView(
              icon: Icons.search_off,
              message: 'No card name matched what was read from the photo.'
                  '${_result?.detectedYear != null ? ' (detected year: ${_result!.detectedYear})' : ''}'
                  '${_result?.detectedBorderColor != null ? ' (detected border: ${_result!.detectedBorderColor})' : ''}'
                  ' Try a closer, well-lit photo of the title.',
              onRetry: _openCamera,
              onDone: _backToIdle,
              result: _result,
              borderDebug: _borderDebug,
            ),
          _ScanState.added => _AddedView(
              card: _addedCard!,
              set: _addedSet,
              quantity: _addedQuantity,
              onScanAgain: _openCamera,
              onDone: _backToIdle,
            ),
          _ScanState.results => _ResultsView(
              matchedName: _result?.matchedName ?? '',
              detectedYear: _result?.detectedYear,
              detectedBorderColor: _result?.detectedBorderColor,
              candidates: _result?.candidates ?? const [],
              onScanAgain: _openCamera,
              onPick: _addCard,
              onDone: _backToIdle,
              result: _result,
              borderDebug: _borderDebug,
            ),
        },
      ),
    );
  }
}

class _IdleView extends StatelessWidget {
  final VoidCallback onScan;
  final VoidCallback onBulkScan;
  const _IdleView({required this.onScan, required this.onBulkScan});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          const Text('Scan a physical card to add it to your collection.', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text(
            "Fit the card's title and the small copyright line in frame -- "
            "the year printed there helps pick the right edition. Tap the "
            "card in the preview if it looks out of focus. If there's only "
            "one clear match it's added automatically; otherwise you'll be "
            'asked which printing it is.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: onScan, icon: const Icon(Icons.camera_alt), label: const Text('Take Photo')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onBulkScan,
            icon: const Icon(Icons.view_carousel),
            label: const Text('Bulk Scan (live)'),
          ),
          const SizedBox(height: 4),
          const Text(
            'Keeps the camera open and adds a card automatically every few '
            "seconds as you swap them in front of it -- great for going "
            'through a stack or binder page.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CapturingView extends StatelessWidget {
  final CameraController? controller;
  final bool torchOn;
  final Key previewKey;
  final VoidCallback onCapture;
  final VoidCallback onToggleTorch;
  final VoidCallback onCancel;
  final void Function(TapUpDetails) onTapToFocus;
  final Offset? focusIndicatorPos;
  final bool focusIndicatorOk;
  const _CapturingView({
    required this.controller,
    required this.torchOn,
    required this.previewKey,
    required this.onCapture,
    required this.onToggleTorch,
    required this.onCancel,
    required this.onTapToFocus,
    required this.focusIndicatorPos,
    required this.focusIndicatorOk,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: c.value.aspectRatio,
              child: Stack(
                children: [
                  GestureDetector(
                    key: previewKey,
                    onTapUp: onTapToFocus,
                    child: CameraPreview(c),
                  ),
                  if (focusIndicatorPos != null)
                    _FocusReticle(center: focusIndicatorPos!, ok: focusIndicatorOk),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(torchOn ? Icons.flash_on : Icons.flash_off),
              tooltip: torchOn ? 'Turn off flashlight' : 'Turn on flashlight',
              onPressed: onToggleTorch,
            ),
            const SizedBox(width: 24),
            IconButton(
              icon: const Icon(Icons.camera_alt, size: 36),
              tooltip: 'Capture',
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.all(18),
              ),
              onPressed: onCapture,
            ),
            const SizedBox(width: 24),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
              onPressed: onCancel,
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Brief square that flashes where a focus tap landed -- green if the camera
/// accepted the focus/exposure point, amber if the device rejected it (so a
/// tap that visibly "does nothing" can be told apart from a tap that wasn't
/// registered at all).
class _FocusReticle extends StatelessWidget {
  final Offset center;
  final bool ok;
  const _FocusReticle({required this.center, required this.ok});

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    return Positioned(
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            border: Border.all(color: ok ? Colors.greenAccent : Colors.amber, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDone;
  final CardMatchResult? result;
  final String? borderDebug;
  const _MessageView({
    required this.icon,
    required this.message,
    required this.onRetry,
    required this.onDone,
    this.result,
    this.borderDebug,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.camera_alt), label: const Text('Try Again')),
            const SizedBox(height: 8),
            TextButton(onPressed: onDone, child: const Text('Done')),
            if (result != null) _ScanDiagnostics(result: result!, borderDebug: borderDebug),
          ],
        ),
      ),
    );
  }
}

/// Shows exactly what OCR read and how the border was sampled -- lets you
/// tell whether a bad match is due to no text being read, the wrong text
/// being read, or a border misdetection, instead of guessing blindly.
class _ScanDiagnostics extends StatelessWidget {
  final CardMatchResult result;
  final String? borderDebug;
  const _ScanDiagnostics({required this.result, this.borderDebug});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ExpansionTile(
        title: const Text('Scan details'),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Corner luminance (0=black, 255=white): '
              '${result.cornerLuminance.map((l) => l.round()).join(', ')}\n'
              'Detected border: ${result.detectedBorderColor ?? "none"}\n'
              'Border detection path: ${borderDebug ?? "unknown"}\n'
              'Detected year: ${result.detectedYear ?? "none"}\n'
              'Raw OCR text:\n${result.rawText.isEmpty ? "(nothing read)" : result.rawText}\n\n'
              'Rotated-strip OCR text (for the year):\n'
              '${result.rotatedRawText == null ? "(no rotated pass)" : result.rotatedRawText!.isEmpty ? "(nothing read)" : result.rotatedRawText}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddedView extends StatelessWidget {
  final TrekCard card;
  final CardSet? set;
  final int quantity;
  final VoidCallback onScanAgain;
  final VoidCallback onDone;
  const _AddedView({
    required this.card,
    required this.set,
    required this.quantity,
    required this.onScanAgain,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 56, color: Colors.green),
          const SizedBox(height: 16),
          if (card.imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(imageUrl: card.imageUrl!, width: 120),
            ),
          const SizedBox(height: 16),
          Text(card.name, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          if (set != null) Text(set!.name, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text('You now own $quantity', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: onScanAgain, icon: const Icon(Icons.camera_alt), label: const Text('Scan Another')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => CardDetailScreen(cardId: card.id)));
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('View Card'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onDone, child: const Text('Done')),
        ],
      ),
    );
  }
}

class _ResultsView extends StatelessWidget {
  final String matchedName;
  final int? detectedYear;
  final String? detectedBorderColor;
  final List<CardMatchCandidate> candidates;
  final VoidCallback onScanAgain;
  final void Function(TrekCard card, CardSet? set) onPick;
  final VoidCallback onDone;
  final CardMatchResult? result;
  final String? borderDebug;
  const _ResultsView({
    required this.matchedName,
    required this.detectedYear,
    required this.detectedBorderColor,
    required this.candidates,
    required this.onScanAgain,
    required this.onPick,
    required this.onDone,
    this.borderDebug,
    this.result,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Matched: $matchedName', style: Theme.of(context).textTheme.titleMedium),
        if (detectedYear != null || detectedBorderColor != null)
          Text(
            [
              if (detectedYear != null) 'year: $detectedYear',
              if (detectedBorderColor != null) 'border: $detectedBorderColor',
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 8),
        const Text("Which printing is this? Tap + to add it, or the row to look at it first."),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: candidates.length,
            itemBuilder: (context, i) {
              final c = candidates[i];
              // A ListTile.onTap plus a nested trailing IconButton.onPressed
              // can both fire from one tap near the button -- that's exactly
              // what turned a single scan into two increments. "View" and
              // "add" are now on two separate, non-overlapping tap targets
              // instead of stacked on the same row.
              return Card(
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => CardDetailScreen(cardId: c.card.id)));
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 40,
                                height: 56,
                                child: c.card.imageUrl != null
                                    ? CachedNetworkImage(imageUrl: c.card.imageUrl!, fit: BoxFit.cover)
                                    : const Icon(Icons.image_not_supported),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(c.card.name),
                                    Text(
                                      '${c.set?.name ?? c.card.setId}'
                                      '${c.set?.year != null ? " (${c.set!.year})" : ""}'
                                      '${c.set?.borderColor != null ? " · ${c.set!.borderColor} border" : ""}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (c.borderContradicted)
                      const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.cancel, color: Colors.red, size: 20))
                    else if (c.confidence > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.check_circle, color: c.confidence == 2 ? Colors.green : Colors.amber, size: 20),
                      ),
                    IconButton(
                      icon: const Icon(Icons.add_circle),
                      tooltip: 'Add to collection',
                      onPressed: () => onPick(c.card, c.set),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: onScanAgain, icon: const Icon(Icons.camera_alt), label: const Text('Scan Another')),
        const SizedBox(height: 4),
        TextButton(onPressed: onDone, child: const Text('Done')),
        if (result != null) _ScanDiagnostics(result: result!, borderDebug: borderDebug),
      ],
    );
  }
}
