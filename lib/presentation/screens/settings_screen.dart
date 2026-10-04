import 'package:flutter/material.dart';

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
          ],
        ),
        const SizedBox(height: 12),
        _SettingsGroup(
          title: '再生設定',
          children: [
            ListTile(
              leading: const Icon(Icons.play_circle_outline_rounded),
              title: const Text('再生と操作'),
              subtitle: const Text('再生速度・自動連続再生・ループ設定'),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => SettingsScreenActions.openPlaybackInfo(context),
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
              subtitle: const Text('バージョン 0.1.0 (MVP) • オープンソース'),
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
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
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
  static void openLibraryManagement(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const LibraryManagementScreen()));
  }



  static void openAbout(BuildContext context) {
    showAboutDialog(context: context, applicationName: 'yureru', applicationVersion: '0.1.0 MVP');
  }

  static void openPlaybackInfo(BuildContext context) {
    showDialog(
        context: context,
        builder: (_) => const AlertDialog(
            title: Text('再生'),
            content: Text('再生設定は準備中です。再生速度は下のバーの「1x」ボタンから変更できます。')));
  }
}

