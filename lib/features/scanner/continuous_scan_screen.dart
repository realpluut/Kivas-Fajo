import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/border_detector.dart';
import '../../data/card_matcher.dart';
import '../../data/models/card_set.dart';
import '../../data/models/trek_card.dart';
import '../../state/providers.dart';
import 'set_filter_sheet.dart';

const _tickInterval = Duration(seconds: 3);

// Not using num.clamp() anywhere in this file -- it returns num, not double,
// which the camera controller's setters require.
double _clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

Future<void> _deleteQuietly(String path) async {
  try {
    await File(path).delete();
  } catch (_) {
    // Best-effort cleanup of a temp capture file; not worth surfacing.
  }
}

/// Live "webcam-style" bulk scanner: keeps the camera open and, every few
/// seconds, captures a frame, OCRs it, and -- if it's a confident, new match
/// -- adds it to the collection automatically. Meant for running through a
/// stack or binder page of cards without tapping anything between cards.
class ContinuousScanScreen extends ConsumerStatefulWidget {
  const ContinuousScanScreen({super.key});

  @override
  ConsumerState<ContinuousScanScreen> createState() => _ContinuousScanScreenState();
}

class _ContinuousScanScreenState extends ConsumerState<ContinuousScanScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  Timer? _timer;
  final _previewKey = GlobalKey();
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final _audioPlayer = AudioPlayer();

  // Fire-and-forget audio feedback -- a short high beep for "added", a
  // lower double-blip for "needs your attention" (multiple printings
  // found), so you can keep feeding cards without watching the screen.
  void _beep(String asset) {
    _audioPlayer.play(AssetSource(asset));
  }

  bool _busy = false;
  String? _initError;
  String _status = 'Point the camera at a card.';
  String? _lastAddedCardId;
  final List<TrekCard> _addedThisSession = [];

  // Set while an ambiguous match is awaiting a manual pick -- capturing
  // pauses (see _tick) so the picker doesn't get replaced mid-decision by
  // the next tick's result, and resumes once the user picks or skips.
  String? _ambiguousMatchedName;
  List<CardMatchCandidate>? _ambiguousCandidates;
  // The frame that produced the ambiguous match, frozen on screen in place of
  // the live preview -- the live feed keeps moving in real time, so leaving
  // it running while a decision from seconds ago is pending made the picker
  // look like it was asking about whatever card happened to be in frame now.
  String? _ambiguousImagePath;

  // On by default: consistent light helps both OCR and border-color
  // detection, which ambient lighting has repeatedly thrown off. Left
  // toggleable in case it glares off a reflective tray/sleeve.
  bool _torchOn = true;

  // veryHigh is the default -- enough resolution for the tiny sideways
  // copyright/year text -- with max available for even more detail at the
  // cost of slower capture/processing per tick.
  ResolutionPreset _resolutionPreset = ResolutionPreset.veryHigh;

  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.1; // the existing "10% zoom in by default" from before manual control was added
  double _zoomAtGestureStart = 1.1;

  double _minExposure = 0.0;
  double _maxExposure = 0.0;
  double _exposureOffset = 0.0;

  // null = "All Sets" -- matching runs against every card in the database,
  // same as before this filter existed. Set to scope matching to just one
  // edition, which also resolves reprint-year/border ambiguity for free
  // since a name usually appears at most once within a single set.
  String? _setFilterId;
  String? _setFilterName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable(); // bulk scanning runs hands-off for minutes at a time; don't let the screen sleep mid-session
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      final controller = CameraController(back, _resolutionPreset, enableAudio: false);
      await controller.initialize();

      if (_torchOn) {
        try {
          await controller.setFlashMode(FlashMode.torch);
        } catch (_) {
          // Some devices/cameras don't support a torch; scanning still works without it.
        }
      }

      try {
        _minZoom = await controller.getMinZoomLevel();
        _maxZoom = await controller.getMaxZoomLevel();
        _currentZoom = _clampD(_currentZoom, _minZoom, _maxZoom);
        await controller.setZoomLevel(_currentZoom);
      } catch (_) {
        // Zoom control not supported on this device; scanning still works at 1x.
      }

      try {
        _minExposure = await controller.getMinExposureOffset();
        _maxExposure = await controller.getMaxExposureOffset();
        if (_exposureOffset != 0) {
          await controller.setExposureOffset(_clampD(_exposureOffset, _minExposure, _maxExposure));
        }
      } catch (_) {
        // Exposure compensation not supported on this device.
      }

      try {
        // Default center-weighted autofocus sharpens the card's main art/
        // title, not the tiny sideways copyright/year text that sits near
        // the card's right edge -- bias the focus point there instead.
        // Coordinates are normalized (0,0 = top-left, 1,1 = bottom-right of
        // the preview), not exact since how much of the frame the card
        // fills varies, but this consistently favors the right-hand strip
        // over dead-center.
        await controller.setFocusMode(FocusMode.auto);
        await controller.setFocusPoint(const Offset(0.85, 0.5));
      } catch (_) {
        // Focus point control not supported on this device.
      }

      if (!mounted) return;
      setState(() => _controller = controller);
      _timer = Timer.periodic(_tickInterval, (_) => _tick());
    } catch (e) {
      if (!mounted) return;
      setState(() => _initError = 'Could not start the camera: $e');
    }
  }

  /// Switching resolution means a new CameraController -- it's fixed at
  /// construction time, not a live setting.
  Future<void> _setResolution(ResolutionPreset preset) async {
    if (preset == _resolutionPreset) return;
    _timer?.cancel();
    final old = _controller;
    setState(() {
      _controller = null;
      _resolutionPreset = preset;
    });
    await old?.dispose();
    await _init();
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) return;
    final newState = !_torchOn;
    try {
      await controller.setFlashMode(newState ? FlashMode.torch : FlashMode.off);
      setState(() => _torchOn = newState);
    } catch (_) {
      // Device/camera doesn't support a torch -- leave state as it was.
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _zoomAtGestureStart = _currentZoom;
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails details) async {
    final controller = _controller;
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

  // Lets you tap the card in the live preview to force a refocus there, the
  // same as the system Camera app -- the fixed focus point set at startup is
  // a reasonable default but doesn't always lock onto the card on every
  // device/lens.
  Future<void> _onTapToFocus(TapUpDetails details) async {
    final controller = _controller;
    final box = _previewKey.currentContext?.findRenderObject() as RenderBox?;
    if (controller == null || box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    final normalized = Offset(
      (local.dx / box.size.width).clamp(0.0, 1.0),
      (local.dy / box.size.height).clamp(0.0, 1.0),
    );
    try {
      await controller.setFocusPoint(normalized);
      await controller.setExposurePoint(normalized);
    } catch (_) {
      // Focus/exposure point control not supported on this device.
    }
  }

  Future<void> _onExposureChanged(double value) async {
    setState(() => _exposureOffset = value);
    try {
      await _controller?.setExposureOffset(value);
    } catch (_) {
      // Ignore -- slider still reflects the requested value.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _timer?.cancel();
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _init();
    }
  }

  Future<void> _tick() async {
    final controller = _controller;
    if (_busy || controller == null || !controller.value.isInitialized) return;
    _busy = true;
    XFile? file;
    var keepFile = false;
    try {
      file = await controller.takePicture();
      final recognized = await _recognizer.processImage(InputImage.fromFilePath(file.path));
      final borderSample = await sampleBorder(file.path);
      final setFilterId = _setFilterId;
      final names = setFilterId == null
          ? await ref.read(distinctCardNamesProvider.future)
          : await ref.read(namesInSetProvider(setFilterId).future);
      final result = await matchCardFromOcr(
        recognized: recognized,
        repo: ref.read(cardRepositoryProvider),
        names: names,
        detectedBorderColor: borderSample.color,
        cornerLuminance: borderSample.cornerLuminance,
        restrictToSetId: setFilterId,
      );

      if (!mounted) return;

      if (!result.hasText) {
        _lastAddedCardId = null;
        setState(() => _status = 'No text seen -- hold steadier or move closer.');
      } else if (result.autoPick == null) {
        _lastAddedCardId = null;
        if (result.candidates.isEmpty) {
          final signals = 'year: ${result.detectedYear ?? "none"}, border: ${result.detectedBorderColor ?? "none"} '
              '(corners: ${result.cornerLuminance.map((l) => l.round()).join(", ")})';
          final scopeNote = _setFilterName != null
              ? ' Scoped to "$_setFilterName" -- switch to All Sets if this card is from elsewhere.'
              : '';
          setState(() => _status = 'No match for what was read. [$signals]$scopeNote');
        } else {
          // Pause capturing and let the user pick right here instead of
          // forcing a switch to the single-shot scanner. Freeze on this
          // frame (see _ambiguousImagePath) rather than leaving the live
          // preview running while the decision is pending.
          _timer?.cancel();
          keepFile = true;
          _beep('sounds/beep_multi.wav');
          setState(() {
            _ambiguousMatchedName = result.matchedName;
            _ambiguousCandidates = result.candidates;
            _ambiguousImagePath = file!.path;
            _status = 'Ambiguous match (${result.matchedName}) -- pick the right printing below.';
          });
        }
      } else {
        final pick = result.autoPick!;
        if (pick.card.id == _lastAddedCardId) {
          setState(() => _status = 'Still showing "${pick.card.name}" -- already added.');
        } else {
          final updated = await ref.read(collectionRepositoryProvider).incrementOwned(pick.card.id);
          ref.read(collectionRevisionProvider.notifier).state++;
          _lastAddedCardId = pick.card.id;
          if (!mounted) return;
          _beep('sounds/beep_success.wav');
          setState(() {
            _addedThisSession.insert(0, pick.card);
            _status = 'Added "${pick.card.name}" -- now own ${updated.quantity}.';
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Scan error: $e');
    } finally {
      final path = file?.path;
      if (path != null && !keepFile) {
        await _deleteQuietly(path);
      }
      _busy = false;
    }
  }

  void _resumeCapturing() {
    final oldImagePath = _ambiguousImagePath;
    setState(() {
      _ambiguousMatchedName = null;
      _ambiguousCandidates = null;
      _ambiguousImagePath = null;
    });
    if (oldImagePath != null) {
      _deleteQuietly(oldImagePath);
    }
    // cancel() stops a timer but leaves the (now-dead) reference assigned --
    // ??= would see it as non-null and skip creating a replacement, which
    // silently killed the auto-scan loop the first time this ran.
    _timer?.cancel();
    _timer = Timer.periodic(_tickInterval, (_) => _tick());
  }

  Future<void> _pickAmbiguous(TrekCard card, CardSet? set) async {
    final updated = await ref.read(collectionRepositoryProvider).incrementOwned(card.id);
    ref.read(collectionRevisionProvider.notifier).state++;
    _lastAddedCardId = card.id; // don't immediately re-prompt if this same card is still in frame
    if (!mounted) return;
    _beep('sounds/beep_success.wav');
    setState(() {
      _addedThisSession.insert(0, card);
      _status = 'Added "${card.name}" -- now own ${updated.quantity}.';
    });
    _resumeCapturing();
  }

  void _dismissAmbiguous() {
    setState(() => _status = 'Skipped. Point the camera at a card.');
    _resumeCapturing();
  }

  Future<void> _pickSetFilter() async {
    final result = await showModalBottomSheet<SetFilterChoice>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SetFilterSheet(currentSetId: _setFilterId),
    );
    if (result == null || !mounted) return;
    setState(() {
      _setFilterId = result.id;
      _setFilterName = result.name;
      _status = result.id == null
          ? 'Scanning against all sets. Point the camera at a card.'
          : 'Scoped to "${result.name}". Point the camera at a card.';
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _timer?.cancel();
    _controller?.dispose();
    _recognizer.close();
    _audioPlayer.dispose();
    final pendingImagePath = _ambiguousImagePath;
    if (pendingImagePath != null) _deleteQuietly(pendingImagePath);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bulk Scan')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(_initError!, textAlign: TextAlign.center)),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final maxLabel = _resolutionPreset == ResolutionPreset.max ? 'MAX' : 'VHQ';

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_ambiguousImagePath != null)
            // Frozen on the frame that produced this ambiguous match --
            // the live preview would keep moving to whatever card is
            // physically in front of the camera right now, which isn't
            // necessarily the card this decision is about.
            Image.file(File(_ambiguousImagePath!), fit: BoxFit.cover)
          else
            GestureDetector(
              key: _previewKey,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onTapUp: _onTapToFocus,
              child: CameraPreview(controller),
            ),
          SafeArea(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: Colors.black54,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      Text('${_addedThisSession.length} added', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      Text('${_currentZoom.toStringAsFixed(1)}x', style: const TextStyle(color: Colors.white)),
                      IconButton(
                        icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off, color: Colors.white),
                        tooltip: _torchOn ? 'Turn off flashlight' : 'Turn on flashlight',
                        onPressed: _toggleTorch,
                      ),
                      IconButton(
                        icon: Text(maxLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                        tooltip: _resolutionPreset == ResolutionPreset.max
                            ? 'Max resolution (tap for Very High -- faster)'
                            : 'Very High resolution (tap for Max -- slower, more detail)',
                        onPressed: () => _setResolution(
                          _resolutionPreset == ResolutionPreset.max ? ResolutionPreset.veryHigh : ResolutionPreset.max,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: _pickSetFilter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    color: Colors.black45,
                    child: Row(
                      children: [
                        const Icon(Icons.filter_alt_outlined, color: Colors.white70, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _setFilterName ?? 'All Sets',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 18),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                if (_ambiguousCandidates != null)
                  _AmbiguousPicker(
                    matchedName: _ambiguousMatchedName ?? '',
                    candidates: _ambiguousCandidates!,
                    onPick: _pickAmbiguous,
                    onSkip: _dismissAmbiguous,
                  )
                else
                  Container(
                    width: double.infinity,
                    color: Colors.black54,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_status, style: const TextStyle(color: Colors.white)),
                        if (_maxExposure > _minExposure) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.brightness_low, color: Colors.white70, size: 18),
                              Expanded(
                                child: Slider(
                                  value: _clampD(_exposureOffset, _minExposure, _maxExposure),
                                  min: _minExposure,
                                  max: _maxExposure,
                                  onChanged: _onExposureChanged,
                                ),
                              ),
                              const Icon(Icons.brightness_high, color: Colors.white70, size: 18),
                            ],
                          ),
                        ],
                        if (_addedThisSession.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 56,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _addedThisSession.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 6),
                              itemBuilder: (context, i) {
                                final card = _addedThisSession[i];
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: card.imageUrl != null
                                      ? CachedNetworkImage(imageUrl: card.imageUrl!, width: 40, fit: BoxFit.cover)
                                      : Container(width: 40, color: Colors.white24),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lets you pick the right printing directly over the live camera feed when
/// bulk scanning can't auto-resolve one -- no need to leave bulk scan mode
/// for the single-shot picker.
class _AmbiguousPicker extends StatelessWidget {
  final String matchedName;
  final List<CardMatchCandidate> candidates;
  final void Function(TrekCard card, CardSet? set) onPick;
  final VoidCallback onSkip;
  const _AmbiguousPicker({
    required this.matchedName,
    required this.candidates,
    required this.onPick,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
      color: Colors.black87,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Which printing is "$matchedName"?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: onSkip,
                child: const Text('Skip'),
              ),
            ],
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: candidates.length,
              itemBuilder: (context, i) {
                final c = candidates[i];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  child: ListTile(
                    dense: true,
                    leading: SizedBox(
                      width: 32,
                      height: 44,
                      child: c.card.imageUrl != null
                          ? CachedNetworkImage(imageUrl: c.card.imageUrl!, fit: BoxFit.cover)
                          : const Icon(Icons.image_not_supported),
                    ),
                    title: Text(c.card.name, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      '${c.set?.name ?? c.card.setId}'
                      '${c.set?.year != null ? " (${c.set!.year})" : ""}'
                      '${c.set?.borderColor != null ? " · ${c.set!.borderColor} border" : ""}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (c.borderContradicted)
                          const Icon(Icons.cancel, color: Colors.red, size: 18)
                        else if (c.confidence > 0)
                          Icon(Icons.check_circle, color: c.confidence == 2 ? Colors.green : Colors.amber, size: 18),
                        IconButton(
                          icon: const Icon(Icons.add_circle),
                          tooltip: 'Add to collection',
                          onPressed: () => onPick(c.card, c.set),
                        ),
                      ],
                    ),
                    // No onTap here -- a ListTile.onTap plus a nested
                    // trailing IconButton.onPressed can both fire from one
                    // tap near the button, so the IconButton is the row's
                    // only tap target for adding a card.
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
