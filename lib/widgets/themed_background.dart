import 'package:flutter/material.dart';

import '../theme.dart';
import 'borg_background.dart';
import 'federation_background.dart';
import 'klingon_background.dart';
import 'romulan_background.dart';

/// Picks the painted background matching the active [AppThemeStyle]. Only
/// used while dark mode is active -- light mode has no painted backdrop.
class ThemedBackground extends StatelessWidget {
  final AppThemeStyle style;
  final Widget child;
  const ThemedBackground({super.key, required this.style, required this.child});

  @override
  Widget build(BuildContext context) {
    return switch (style) {
      AppThemeStyle.borg => BorgBackground(child: child),
      AppThemeStyle.federation => FederationBackground(child: child),
      AppThemeStyle.klingon => KlingonBackground(child: child),
      AppThemeStyle.romulan => RomulanBackground(child: child),
    };
  }
}
