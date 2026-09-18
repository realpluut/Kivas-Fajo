import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/backup_service.dart';
import '../../data/release_notes.dart';
import '../../state/providers.dart';
import '../../theme.dart';
import '../about/manual_screen.dart';
import '../about/release_notes_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ref.read(backupServiceProvider).buildExportFile();
      await Share.shareXFiles([XFile(file.path)], subject: 'Kivas Fajo collection backup');
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Could not export: $e')));
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open the file picker: $e')));
      return;
    }
    final path = picked?.files.single.path;
    if (path == null || !context.mounted) return;

    // Overwrites any existing entry for a card the backup also covers --
    // worth a confirmation before it silently clobbers current tracking.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import collection'),
        content: const Text(
          'This restores owned/wanted status and quantities from the backup file. '
          'Any card the backup also covers will be overwritten with the backup\'s values.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Import')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref.read(backupServiceProvider).importFromFile(File(path));
      ref.read(collectionRevisionProvider.notifier).state++;
      final skippedNote = result.skipped > 0 ? ', skipped ${result.skipped} not in this build\'s catalog' : '';
      messenger.showSnackBar(SnackBar(content: Text('Restored ${result.imported} cards$skippedNote.')));
    } on BackupFormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not import: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final modeController = ref.read(themeModeProvider.notifier);
    final themeStyle = ref.watch(appThemeStyleProvider);
    final styleController = ref.read(appThemeStyleProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Theme', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: (m) => m == null ? null : modeController.setThemeMode(m),
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(title: Text('System default'), value: ThemeMode.system),
                RadioListTile<ThemeMode>(title: Text('Light'), value: ThemeMode.light),
                RadioListTile<ThemeMode>(title: Text('Dark'), value: ThemeMode.dark),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Dark theme style', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Applies whenever dark mode is active.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          RadioGroup<AppThemeStyle>(
            groupValue: themeStyle,
            onChanged: (s) => s == null ? null : styleController.setStyle(s),
            child: Column(
              children: AppThemeStyle.values
                  .map((s) => RadioListTile<AppThemeStyle>(
                        title: Text(s.label),
                        subtitle: Text(s.description),
                        value: s,
                      ))
                  .toList(),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Backup', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Export collection'),
            subtitle: const Text('Save a backup file -- keep it somewhere safe before reinstalling or switching phones.'),
            onTap: () => _export(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.file_open_outlined),
            title: const Text('Import collection'),
            subtitle: const Text('Restore owned/wanted status and quantities from a backup file.'),
            onTap: () => _import(context, ref),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Help', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Field Manual'),
            subtitle: const Text('How to use every screen in the app.'),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManualScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.new_releases_outlined),
            title: const Text('What\'s changed'),
            subtitle: const Text('Version history and release notes.'),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReleaseNotesScreen()));
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Text(
              'Version $kAppVersionLabel',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}
