import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme.dart';
import 'home_screen.dart';
import 'settings_library_screen.dart';

/// Settings page (center-pane body; shell owns chrome).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        const PageHeader(title: '設定'),
        _SettingsGroup(
          title: 'ライブラリとストレージ',
          children: [
            ListTile(
              leading: const Icon(Icons.folder_copy_rounded),
              title: const Text('ライブラリ管理・インポート'),
              subtitle: const Text('動画やフォルダの取り込み、参照フォルダ管理、ストレージ容量'),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => SettingsScreenActions.openLibraryManagement(context),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: const Text('動画タイトル・投稿者を編集'),
              subtitle: const Text('ライブラリ内の動画情報を変更します'),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => SettingsScreenActions.openMediaEditor(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SettingsGroup(
          title: 'アプリについて',
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('yureru について'),
              subtitle: FutureBuilder<PackageInfo>(
                future: SettingsScreenActions.packageInfo,
                builder: (context, snapshot) {
                  final info = snapshot.data;
                  if (info == null) return const Text('バージョン情報を読み込み中…');
                  return Text('バージョン ${info.version} • オープンソース');
                },
              ),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => SettingsScreenActions.openAbout(context),
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? kTextSub : Colors.black54,
                letterSpacing: 0.3,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// Opens settings sub-screens; kept next to the settings page.
class SettingsScreenActions {
  static final Future<PackageInfo> packageInfo = PackageInfo.fromPlatform();

  static void openLibraryManagement(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LibraryManagementScreen()));
  }

  static void openMediaEditor(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ImportedMediaScreen()));
  }

  static Future<void> openAbout(BuildContext context) async {
    final info = await packageInfo;
    if (!context.mounted) return;
    showAboutDialog(
      context: context,
      applicationName: info.appName,
      applicationVersion: '${info.version} (${info.buildNumber})',
    );
  }
}
