import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/border_detector.dart';
import '../../data/card_matcher.dart';
import '../../data/image_prep.dart';
import '../../data/models/card_set.dart';
import '../../data/models/trek_card.dart';
import '../../data/rotated_capture.dart';
import '../../state/providers.dart';
import 'scan_widgets.dart';
import 'set_filter_sheet.dart';

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

/// Bulk scan -- the exact same single-shot capture/OCR/match pipeline as
/// ScannerScreen (same per-card result page, same "almost always perfect
/// hit" accuracy that comes from a fresh, fully-focused photo each time),
/// with one addition: an auto-scan loop that re-fires that single-shot flow
/// every few seconds (configurable in Settings, see autoScanIntervalProvider)
/// instead of waiting for a shutter tap each time.
class ContinuousScanScreen extends ConsumerStatefulWidget {
  const ContinuousScanScreen({super.key});

  @override
  ConsumerState<ContinuousScanScreen> createState() => _ContinuousScanScreenState();
}

class _ContinuousScanScreenState extends ConsumerState<ContinuousScanScreen> {
  _ScanState _state = _ScanState.idle;
  String? _errorMessage;
  CardMatchResult? _result;
  String? _borderDebug;

  TrekCard? _addedCard;
  CardSet? _addedSet;
  int _addedQuantity = 0;
  int _addedThisSession = 0;

  CameraController? _cameraController;
  bool _torchOn = false;
  final _previewKey = GlobalKey();

  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.5;
  double _zoomAtGestureStart = 1.5;

  Offset? _focusIndicatorPos;
  bool _focusIndicatorOk = true;
  Timer? _focusIndicatorTimer;

  // Off by default -- same as single-shot's "Scan Another": the first shot
  // after opening this screen is always a deliberate tap, so the rig/card
  // is framed before anything starts firing on its own.
  bool _autoEnabled = false;
  Timer? _autoTimer;

  // null = "All Sets" -- matching runs against every card in the database.
  // Set to scope matching to just one edition, which also resolves
  // reprint-year/border ambiguity for free since a name usually appears at
  // most once within a single set.
  String? _setFilterId;
  String? _setFilterName;

  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // bulk scanning runs hands-off for minutes at a time; don't let the screen sleep mid-session
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _cameraController?.dispose();
    _recognizer.close();
    _focusIndicatorTimer?.cancel();
    _autoTimer?.cancel();
    super.dispose();
  }

  void _cancelAutoTimer() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  /// Schedules the next automatic shot, [autoScanIntervalProvider] seconds
  /// from now. Called both right after a result page appears (so it
  /// auto-advances) and when auto-scan is switched on while already sitting
  /// on the camera preview. Reads the current setting at call time rather
  /// than watching it, so a change in Settings takes effect on the next
  /// scheduled shot, not retroactively mid-countdown.
  void _scheduleNextAuto() {
    _cancelAutoTimer();
    if (!_autoEnabled) return;
    final interval = Duration(seconds: ref.read(autoScanIntervalProvider));
    _autoTimer = Timer(interval, () {
      if (!mounted || !_autoEnabled) return;
      switch (_state) {
        case _ScanState.capturing:
          _capture();
        case _ScanState.added:
        case _ScanState.noMatch:
        case _ScanState.error:
          _openCamera(autoCapture: true);
        case _ScanState.idle:
        case _ScanState.processing:
        case _ScanState.results:
          // Idle/processing shouldn't have a timer pending here; results
          // (multiple candidates) needs a manual pick, so auto-scan is
          // never scheduled while it's showing -- see _processPhoto.
          break;
      }
    });
  }

  void _toggleAuto() {
    setState(() => _autoEnabled = !_autoEnabled);
    if (_autoEnabled) {
      _scheduleNextAuto();
    } else {
      _cancelAutoTimer();
    }
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
      _addedThisSession++;
    });
    _scheduleNextAuto();
  }

  /// Opens a live in-app camera preview instead of handing off to the
  /// system camera app -- see scanner_screen.dart for the full reasoning.
  ///
  /// [autoCapture] skips the manual shutter tap: used for both "Scan
  /// Another" and every auto-scan-driven reopen, where the framing is
  /// already established and only the card itself needs swapping.
  Future<void> _openCamera({bool autoCapture = false}) async {
    setState(() {
      _state = _ScanState.capturing;
      _errorMessage = null;
    });
    try {
      final cameras = await availableCameras();
      final back = _pickBackCamera(cameras);
      // max, not veryHigh -- see scanner_screen.dart: this is still one
      // deliberate shot at a time, just fired automatically, so the same
      // higher-detail capture that makes the single-shot scanner's hit
      // rate so good applies here too.
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
        // copyright/year text sits.
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
        // card before snapping. If the user cancels or fires the shutter
        // manually during this wait, _cameraController is already null by
        // the time it elapses, so this backs off instead of double-capturing.
        await Future.delayed(const Duration(milliseconds: 900));
        if (!mounted || _cameraController == null) return;
        await _capture();
      } else if (_autoEnabled) {
        _scheduleNextAuto();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ScanState.error;
        _errorMessage = 'Could not start the camera: $e';
      });
    }
  }

  /// "Scan Another" -- see _openCamera's autoCapture doc.
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
  // as the system Camera app.
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
    _cancelAutoTimer();
    final controller = _cameraController;
    _cameraController = null;
    controller?.dispose();
    setState(() => _state = _ScanState.idle);
  }

  Future<void> _capture() async {
    _cancelAutoTimer();
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
      final setFilterId = _setFilterId;
      final names = setFilterId == null
          ? await ref.read(distinctCardNamesProvider.future)
          : await ref.read(namesInSetProvider(setFilterId).future);
      final result = await matchCardFromOcr(
        recognized: recognized,
        rotatedRecognized: rotatedRecognized,
        repo: ref.read(cardRepositoryProvider),
        names: names,
        detectedBorderColor: borderSample.color,
        cornerLuminance: borderSample.cornerLuminance,
        restrictToSetId: setFilterId,
      );

      if (!mounted) return;
      if (!result.hasText) {
        setState(() {
          _state = _ScanState.error;
          _errorMessage = 'Could not read any text on that photo. Try a closer, well-lit shot of the card.';
          _result = result;
        });
        _scheduleNextAuto();
        return;
      }
      if (result.candidates.isEmpty) {
        setState(() {
          _state = _ScanState.noMatch;
          _result = result;
        });
        _scheduleNextAuto();
        return;
      }
      if (result.autoPick != null) {
        _result = result;
        await _addCard(result.autoPick!.card, result.autoPick!.set);
        return;
      }
      // Multiple candidates -- needs a manual pick, so auto-scan (if on)
      // just waits here rather than scheduling anything.
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
      _scheduleNextAuto();
    } finally {
      await _deleteQuietly(path);
      if (grayPath != null && grayPath != path) await _deleteQuietly(grayPath);
    }
  }

  void _backToIdle() {
    _cancelAutoTimer();
    setState(() => _state = _ScanState.idle);
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final autoScanInterval = ref.watch(autoScanIntervalProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bulk Scan'),
        actions: [
          if (_addedThisSession > 0)
            Center(child: Padding(padding: const EdgeInsets.only(right: 8), child: Text('$_addedThisSession added'))),
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            tooltip: _setFilterName ?? 'All Sets',
            onPressed: _pickSetFilter,
          ),
        ],
        bottom: _setFilterName != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('Scoped to "$_setFilterName"', style: Theme.of(context).textTheme.bodySmall),
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: switch (_state) {
            _ScanState.idle => _BulkIdleView(onScan: _openCamera, intervalSeconds: autoScanInterval),
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
                autoEnabled: _autoEnabled,
                onToggleAuto: _toggleAuto,
                autoIntervalSeconds: autoScanInterval,
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
                autoEnabled: _autoEnabled,
                onToggleAuto: _toggleAuto,
                autoIntervalSeconds: autoScanInterval,
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
                autoEnabled: _autoEnabled,
                onToggleAuto: _toggleAuto,
                autoIntervalSeconds: autoScanInterval,
              ),
            _ScanState.added => AddedView(
                card: _addedCard!,
                set: _addedSet,
                quantity: _addedQuantity,
                onScanAgain: _scanAnother,
                onDone: _backToIdle,
                result: _result,
                borderDebug: _borderDebug,
                autoEnabled: _autoEnabled,
                onToggleAuto: _toggleAuto,
                autoIntervalSeconds: autoScanInterval,
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
      ),
    );
  }
}

class _BulkIdleView extends StatelessWidget {
  final VoidCallback onScan;
  final int intervalSeconds;
  const _BulkIdleView({required this.onScan, required this.intervalSeconds});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.view_carousel_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          const Text('Scan through a stack of cards one at a time.', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Same scan as the single photo screen -- frame the first card and '
            'take the photo, then turn on auto-scan (the play button next to '
            'the shutter) to keep going automatically every ${intervalSeconds}s '
            '(change that in Settings). Pause it any time from there or from '
            'the result screen.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: onScan, icon: const Icon(Icons.camera_alt), label: const Text('Take Photo')),
        ],
      ),
    );
  }
}
