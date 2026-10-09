// Shared per-shot UI used by both the single-shot scanner and bulk scan --
// kept in one place so the two flows can't drift apart the way the OCR/
// matching logic once did between them.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../data/card_matcher.dart';
import '../../data/models/card_set.dart';
import '../../data/models/trek_card.dart';
import '../card_detail/card_detail_screen.dart';

/// Brief square that flashes where a focus tap landed -- green if the camera
/// accepted the focus/exposure point, amber if the device rejected it (so a
/// tap that visibly "does nothing" can be told apart from a tap that wasn't
/// registered at all).
class FocusReticle extends StatelessWidget {
  final Offset center;
  final bool ok;
  const FocusReticle({super.key, required this.center, required this.ok});

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

/// Small play/pause-styled control for toggling auto-scan -- shared between
/// the camera page and the per-card result pages, so "pause" works from
/// wherever you happen to be looking when you want to stop.
class AutoToggleButton extends StatelessWidget {
  final bool autoEnabled;
  final VoidCallback onToggle;
  final Color? color;
  const AutoToggleButton({super.key, required this.autoEnabled, required this.onToggle, this.color});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(autoEnabled ? Icons.pause_circle_filled : Icons.play_circle_fill, color: color),
      tooltip: autoEnabled ? 'Pause auto-scan' : 'Start auto-scan (every few seconds)',
      onPressed: onToggle,
    );
  }
}

/// Row shown on the per-card result pages (added/no-match/error) when auto-
/// scan is available -- lets you stop the loop without going back to the
/// camera page first.
class AutoStatusRow extends StatelessWidget {
  final bool autoEnabled;
  final VoidCallback onToggle;
  const AutoStatusRow({super.key, required this.autoEnabled, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AutoToggleButton(autoEnabled: autoEnabled, onToggle: onToggle, color: Theme.of(context).colorScheme.primary),
          Text(
            autoEnabled ? 'Auto-scanning -- next shot coming up' : 'Auto-scan paused',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class CapturingView extends StatelessWidget {
  final CameraController? controller;
  final bool torchOn;
  final Key previewKey;
  final VoidCallback onCapture;
  final VoidCallback onToggleTorch;
  final VoidCallback onCancel;
  final void Function(TapUpDetails) onTapToFocus;
  final Offset? focusIndicatorPos;
  final bool focusIndicatorOk;
  final GestureScaleStartCallback onScaleStart;
  final GestureScaleUpdateCallback onScaleUpdate;
  final double currentZoom;
  // Null hides the auto-scan control entirely -- only bulk scan passes this.
  final bool? autoEnabled;
  final VoidCallback? onToggleAuto;
  const CapturingView({
    super.key,
    required this.controller,
    required this.torchOn,
    required this.previewKey,
    required this.onCapture,
    required this.onToggleTorch,
    required this.onCancel,
    required this.onTapToFocus,
    required this.focusIndicatorPos,
    required this.focusIndicatorOk,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.currentZoom,
    this.autoEnabled,
    this.onToggleAuto,
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
                    onScaleStart: onScaleStart,
                    onScaleUpdate: onScaleUpdate,
                    child: CameraPreview(c),
                  ),
                  if (focusIndicatorPos != null)
                    FocusReticle(center: focusIndicatorPos!, ok: focusIndicatorOk),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        '${currentZoom.toStringAsFixed(1)}x',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
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
            if (autoEnabled != null && onToggleAuto != null)
              AutoToggleButton(autoEnabled: autoEnabled!, onToggle: onToggleAuto!),
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

/// Shows exactly what OCR read and how the border was sampled -- lets you
/// tell whether a bad match is due to no text being read, the wrong text
/// being read, or a border misdetection, instead of guessing blindly.
class ScanDiagnostics extends StatelessWidget {
  final CardMatchResult result;
  final String? borderDebug;
  const ScanDiagnostics({super.key, required this.result, this.borderDebug});

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

class MessageView extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDone;
  final CardMatchResult? result;
  final String? borderDebug;
  final bool? autoEnabled;
  final VoidCallback? onToggleAuto;
  const MessageView({
    super.key,
    required this.icon,
    required this.message,
    required this.onRetry,
    required this.onDone,
    this.result,
    this.borderDebug,
    this.autoEnabled,
    this.onToggleAuto,
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
            const SizedBox(height: 16),
            if (autoEnabled != null && onToggleAuto != null)
              AutoStatusRow(autoEnabled: autoEnabled!, onToggle: onToggleAuto!),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.camera_alt), label: const Text('Try Again')),
            const SizedBox(height: 8),
            TextButton(onPressed: onDone, child: const Text('Done')),
            if (result != null) ScanDiagnostics(result: result!, borderDebug: borderDebug),
          ],
        ),
      ),
    );
  }
}

class AddedView extends StatelessWidget {
  final TrekCard card;
  final CardSet? set;
  final int quantity;
  final VoidCallback onScanAgain;
  final VoidCallback onDone;
  final CardMatchResult? result;
  final String? borderDebug;
  final bool? autoEnabled;
  final VoidCallback? onToggleAuto;
  const AddedView({
    super.key,
    required this.card,
    required this.set,
    required this.quantity,
    required this.onScanAgain,
    required this.onDone,
    this.result,
    this.borderDebug,
    this.autoEnabled,
    this.onToggleAuto,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
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
            const SizedBox(height: 16),
            if (autoEnabled != null && onToggleAuto != null)
              AutoStatusRow(autoEnabled: autoEnabled!, onToggle: onToggleAuto!),
            const SizedBox(height: 8),
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
            // Available on a confident auto-pick too, not just errors/
            // ambiguous matches -- lets you spot-check border/year
            // detection (e.g. while verifying a detection fix) without
            // needing a scan to go wrong first.
            if (result != null) ScanDiagnostics(result: result!, borderDebug: borderDebug),
          ],
        ),
      ),
    );
  }
}

class ResultsView extends StatelessWidget {
  final String matchedName;
  final int? detectedYear;
  final String? detectedBorderColor;
  final List<CardMatchCandidate> candidates;
  final VoidCallback onScanAgain;
  final void Function(TrekCard card, CardSet? set) onPick;
  final VoidCallback onDone;
  final CardMatchResult? result;
  final String? borderDebug;
  const ResultsView({
    super.key,
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
                    if (c.contradicted)
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
        if (result != null) ScanDiagnostics(result: result!, borderDebug: borderDebug),
      ],
    );
  }
}
