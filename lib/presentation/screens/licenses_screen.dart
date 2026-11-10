import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n.dart';

class LicensesScreen extends ConsumerWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(ref.tr('open_source_licenses'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _LicenseEntry(
            title: 'Yureru',
            license: 'MIT',
            details: ref.tr('license_yureru_details'),
          ),
          const SizedBox(height: 12),
          _LicenseEntry(
            title: 'Flutter packages',
            license: ref.tr('license_varies'),
            details: ref.tr('license_flutter_details'),
            action: TextButton.icon(
              onPressed: () =>
                  showLicensePage(context: context, applicationName: 'Yureru'),
              icon: const Icon(Icons.list_alt),
              label: Text(ref.tr('license_view_all_packages')),
            ),
          ),
          const SizedBox(height: 12),
          _LicenseEntry(
            title: 'quickjs_engine / QuickJS-NG',
            license: 'MIT',
            details: ref.tr('license_extension_runtime_details'),
            action: const SelectableText(
              'https://pub.dev/packages/quickjs_engine\n'
              'https://github.com/quickjs-ng/quickjs',
            ),
          ),
          const SizedBox(height: 12),
          _LicenseEntry(
            title: 'ffmpeg_kit_flutter_new_full',
            license: 'LGPL-3.0',
            details: ref.tr('license_ffmpeg_pip_details'),
            action: const SelectableText(
              'https://pub.dev/packages/ffmpeg_kit_flutter_new_full\n'
              'https://github.com/sk3llo/ffmpeg_kit_flutter',
            ),
          ),
          const SizedBox(height: 12),
          _LicenseEntry(
            title: 'media_kit / mpv / FFmpeg',
            license: ref.tr('license_varies_by_platform'),
            details: ref.tr('license_media_engine_details'),
            action: const SelectableText(
              'https://github.com/media-kit/media-kit\n'
              'https://github.com/media-kit/libmpv-darwin-build\n'
              'https://ffmpeg.org/legal.html',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            ref.tr('license_native_notice'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _LicenseEntry extends StatelessWidget {
  const _LicenseEntry({
    required this.title,
    required this.license,
    required this.details,
    this.action,
  });

  final String title;
  final String license;
  final String details;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(license, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(details),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    ),
  );
}
