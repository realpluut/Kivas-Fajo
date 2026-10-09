import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../data/border_detector.dart';
import '../../data/card_matcher.dart';
import '../../data/image_prep.dart';
import '../../data/models/card_set.dart';
import '../../data/models/trek_card.dart';
import '../../data/rotated_capture.dart';
import '../../state/providers.dart';
import 'continuous_scan_screen.dart';
import 'scan_widgets.dart';

enum _ScanState { idle, capturing, processing, results, added, noMatch, error }

Future<void> _deleteQuietly(String path) async {
  try {
    await File(path).delete();
  } catch (_) {
    // Best-effort cleanup of a temp capture file; not worth surfacing.
  }
}

// Not using num.clamp() anywhere in this file -- it returns num, not double,
// which the camera controller's setters require.
double _clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

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
  // Off by default -- the flash tends to blow out glare on glossy card
  // stock right where the title/copyright text sits, hurting OCR more than
  // the extra light helps it. Still toggleable for a genuinely dark room.
  bool _torchOn = false;
  final _previewKey = GlobalKey();

  // The ultra-wide lens (see _pickBackCamera) has a much wider field of view
  // than the standard lens it replaced, which can shrink the card -- and
  // especially its tiny copyright/year text -- too small in frame to read.
  // 1.5x by default brings the card closer to filling the frame out of the
  // gate; pinch-to-zoom still lets you adjust further, same as bulk scan.
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.5;
  double _zoomAtGestureStart = 1.5;

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
  ///
  /// [autoCapture] skips the manual shutter tap entirely: used for "Scan
  /// Another" specifically, where the camera's framing/position is already
  /// established from the previous card (typically a fixed rig/tray, not
  /// hand-held) and only the card itself needs swapping -- not the very
  /// first "Take Photo" from idle, where that framing hasn't happened yet.
  Future<void> _openCamera({bool autoCapture = false}) async {
    setState(() {
      _state = _ScanState.capturing;
      _errorMessage = null;
    });
    try {
      final cameras = await availableCameras();
      final back = _pickBackCamera(cameras);
      // max, not veryHigh: veryHigh maps to a flat 1920x1080 video preset
      // (~2MP) on iOS, while max uses the camera's actual highest-resolution
      // photo format -- the same ballpark the system Camera app captures at.
      // That gap in detail is exactly what made the tiny copyright/year
      // text unreadable even when nothing else was wrong. This is a single
      // deliberate shot, not bulk scanning, so the slower capture is worth it.
      final controller = CameraController(back, ResolutionPreset.max, enableAudio: false);
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

      try {
        _minZoom = await controller.getMinZoomLevel();
        _maxZoom = await controller.getMaxZoomLevel();
        _currentZoom = _clampD(_currentZoom, _minZoom, _maxZoom);
        await controller.setZoomLevel(_currentZoom);
      } catch (_) {
        // Zoom control not supported on this device; scanning still works at 1x.
      }

      if (!mounted) return;
      setState(() => _cameraController = controller);

      if (autoCapture) {
        // Give autofocus/exposure a moment to settle on the newly-placed
        // card before snapping -- right after initialize() the lens is
        // often still racking focus from wherever it last was. If the
        // user cancels or fires the shutter manually during this wait,
        // _cameraController is already null by the time it elapses, so
        // this backs off instead of double-capturing.
        await Future.delayed(const Duration(milliseconds: 900));
        if (!mounted || _cameraController == null) return;
        await _capture();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ScanState.error;
        _errorMessage = 'Could not start the camera: $e';
      });
    }
  }

  /// "Scan Another" specifically -- see _openCamera's autoCapture doc.
  Future<void> _scanAnother() => _openCamera(autoCapture: true);

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

  void _onScaleStart(ScaleStartDetails details) {
    _zoomAtGestureStart = _currentZoom;
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails details) async {
    final controller = _cameraController;
    if (controller == null || _minZoom >= _maxZoom) return;
    final newZoom = _clampD(_zoomAtGestureStart * details.scale, _minZoom, _maxZoom);
    if ((newZoom - _currentZoom).abs() < 0.01) return;
    setState(() => _currentZoom = newZoom);
    try {
      await controller.setZoomLevel(newZoom);
    } catch (_) {
      // Ignore transient zoom errors -- the next pinch update will retry.
    }
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
    String? grayPath;
    try {
      // Grayscale copy for OCR only -- border detection below still reads
      // the original color photo (see image_prep.dart).
      grayPath = await grayscaleCopy(path);
      final recognized = await _recognizer.processImage(InputImage.fromFilePath(grayPath));
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
        _result = result;
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
      if (grayPath != null && grayPath != path) await _deleteQuietly(grayPath);
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
          _ScanState.capturing => CapturingView(
              controller: _cameraController,
              torchOn: _torchOn,
              previewKey: _previewKey,
              onCapture: _capture,
              onToggleTorch: _toggleTorch,
              onCancel: _cancelCapture,
              onTapToFocus: _onTapToFocus,
              focusIndicatorPos: _focusIndicatorPos,
              focusIndicatorOk: _focusIndicatorOk,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              currentZoom: _currentZoom,
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
          _ScanState.error => MessageView(
              icon: Icons.error_outline,
              message: _errorMessage ?? 'Something went wrong.',
              onRetry: _openCamera,
              onDone: _backToIdle,
              result: _result,
              borderDebug: _borderDebug,
            ),
          _ScanState.noMatch => MessageView(
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
          _ScanState.added => AddedView(
              card: _addedCard!,
              set: _addedSet,
              quantity: _addedQuantity,
              onScanAgain: _scanAnother,
              onDone: _backToIdle,
              result: _result,
              borderDebug: _borderDebug,
            ),
          _ScanState.results => ResultsView(
              matchedName: _result?.matchedName ?? '',
              detectedYear: _result?.detectedYear,
              detectedBorderColor: _result?.detectedBorderColor,
              candidates: _result?.candidates ?? const [],
              onScanAgain: _scanAnother,
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

