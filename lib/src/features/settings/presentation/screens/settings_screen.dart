import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/theme_mode_provider.dart';

/// Settings.
///
/// The appearance section is fully functional in Phase 0 on purpose: it is the
/// first vertical slice through every foundation layer — a Riverpod notifier
/// reading and writing Hive, rebuilding a Material 3 themed UI. If this screen
/// works, the plumbing works.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(label: 'Appearance', theme: theme),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('System'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Dark'),
                ),
              ],
              selected: {themeMode},
              onSelectionChanged: (selection) => ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(selection.first),
            ),
          ),

          const Divider(),
          _SectionHeader(label: 'Privacy', theme: theme),
          const ListTile(
            leading: Icon(Icons.phonelink_lock_outlined),
            title: Text('Everything stays on this device'),
            subtitle: Text(
              'Scanning, text recognition and the assistant all run offline. '
              'DocuAI has no account, no server and no analytics.',
            ),
            isThreeLine: true,
          ),

          const Divider(),
          _SectionHeader(label: 'About', theme: theme),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text(AppConstants.appName),
            subtitle: Text(AppConstants.appTagline),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.theme});

  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
