import 'translations/ja.dart';
import 'translations/en.dart';
import 'translations/zh_hans.dart';
import 'translations/zh_hant.dart';
import 'translations/ko.dart';
import 'translations/es.dart';
import 'translations/pt.dart';
import 'translations/fr.dart';
import 'translations/de.dart';
import 'translations/ar.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Translation dictionaries assembled from per-locale files.
const Map<String, Map<String, String>> _kTranslations = {
  'ja': {...jaBase, ...jaFeature, ...jaScreen, ...jaExtra, ...jaLibrary},
  'en': {...enBase, ...enFeature, ...enScreen, ...enExtra, ...enLibrary},
  'zhHans': {
    ...zhHansBase,
    ...zhHansFeature,
    ...zhHansScreen,
    ...zhHansExtra,
    ...zhHansLibrary,
  },
  'zhHant': {
    ...zhHantBase,
    ...zhHantFeature,
    ...zhHantScreen,
    ...zhHantExtra,
    ...zhHantLibrary,
  },
  'ko': {...koBase, ...koFeature, ...koScreen, ...koExtra, ...koLibrary},
  'es': {...esBase, ...esFeature, ...esScreen, ...esExtra, ...esLibrary},
  'pt': {...ptBase, ...ptFeature, ...ptScreen, ...ptExtra, ...ptLibrary},
  'fr': {...frBase, ...frFeature, ...frScreen, ...frExtra, ...frLibrary},
  'de': {...deBase, ...deFeature, ...deScreen, ...deExtra, ...deLibrary},
  'ar': {...arBase, ...arFeature, ...arScreen, ...arExtra, ...arLibrary},
};

/// 10 Major Global Languages + System Default
enum AppLanguage {
  system('システム標準 (System)', null),
  ja('日本語', Locale('ja', 'JP')),
  en('English', Locale('en', 'US')),
  zhHans('简体中文', Locale('zh', 'CN')),
  zhHant('繁體中文', Locale('zh', 'TW')),
  ko('한국어', Locale('ko', 'KR')),
  es('Español', Locale('es', 'ES')),
  pt('Português', Locale('pt', 'BR')),
  fr('Français', Locale('fr', 'FR')),
  de('Deutsch', Locale('de', 'DE')),
  ar('العربية', Locale('ar', 'SA'));

  final String label;
  final Locale? locale;
  const AppLanguage(this.label, this.locale);

  static AppLanguage fromCode(String? code) {
    if (code == null || code.isEmpty || code == 'system') {
      return AppLanguage.system;
    }
    for (final l in AppLanguage.values) {
      if (l.name == code) return l;
    }
    return AppLanguage.system;
  }
}

/// Dictionary of translations for all 10 languages

/// Strings added for the ambient-light controls and media metadata editor.

/// Labels used by the main browsing and playback surfaces.

/// Lookup function with safe fallback
String translate(String key, String langCode) {
  final langDict = _kTranslations[langCode] ?? _kTranslations['ja']!;
  return langDict[key] ?? _kTranslations['ja']?[key] ?? key;
}

/// Strings adapter for backward compatibility
class AppStrings {
  final String activeCode;
  const AppStrings(this.activeCode);

  String tr(String key) => translate(key, activeCode);

  // General & Navigation
  String get appTitle => tr('app_title');
  String get library => tr('library');
  String get allVideos => tr('all_videos');
  String get playlists => tr('playlists');
  String get settings => tr('settings');
  String get newPlaylist => tr('new_playlist');
  String get play => tr('play');
  String get pause => tr('pause');
  String get playing => tr('playing');
  String get paused => tr('paused');
  String get preview => tr('preview');
  String get queue => tr('queue');
  String get clearQueue => tr('clear_queue');
  String get restartTrack => tr('restart_track');
  String get shuffle => tr('shuffle');
  String get repeat => tr('repeat');
  String get prevVideo => tr('prev_video');
  String get nextVideo => tr('next_video');
  String get mute => tr('mute');
  String get unmute => tr('unmute');
  String get fullscreen => tr('fullscreen');
  String get untitled => tr('untitled');

  // Mode Toggles
  String get modeMedia => tr('mode_media');
  String get modeImage => tr('mode_image');

  // Search & Hints
  String get searchPlaceholder => tr('search_hint');
  String get filterPlaceholder => tr('filter_hint');
  String get globalSearch => tr('global_search');
  String get notFound => tr('not_found');
  String get showSidebar => tr('show_sidebar');
  String get hideSidebar => tr('hide_sidebar');
  String get showQueue => tr('show_queue');
  String get hideQueue => tr('hide_queue');
  String get queueWidthTooltip => tr('queue_width');

  // Home Screen
  String get homeGreeting => tr('home_greeting');
  String get recentVideos => tr('recent_videos');
  String get quickPicks => tr('quick_picks');
  String get emptyLibraryHint => tr('empty_library');
  String get emptyPlaylistHint => tr('empty_playlist');

  // Library / Settings
  String get libraryManagement => tr('library_management');
  String get languageSettings => tr('language_settings');
  String get importVideo => tr('import_video');
  String get importVideoDesc => tr('import_video_desc');
  String get importFolder => tr('import_folder');
  String get importFolderDesc => tr('import_folder_desc');
  String get importFolderReferenced => tr('import_folder_referenced');
  String get importFolderReferencedDesc => tr('import_folder_referenced_desc');
  String get importedMedia => tr('imported_media');
  String get storage => tr('storage');
}

class LanguageNotifier extends StateNotifier<AppLanguage> {
  static const _kLangKey = 'yureru_app_language_v2';

  LanguageNotifier() : super(AppLanguage.system) {
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getString(_kLangKey);
      state = AppLanguage.fromCode(saved);
    } catch (_) {}
  }

  Future<void> setLanguage(AppLanguage lang) async {
    state = lang;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kLangKey, lang.name);
    } catch (_) {}
  }
}

final languageProvider = StateNotifierProvider<LanguageNotifier, AppLanguage>((
  _,
) {
  return LanguageNotifier();
});

/// Resolves the effective language code ('ja', 'en', 'ko', 'zhHans', 'zhHant', 'es', 'pt', 'fr', 'de', 'ar')
/// based on user selection or OS platform locale.
final activeLanguageCodeProvider = Provider<String>((ref) {
  final setting = ref.watch(languageProvider);
  if (setting != AppLanguage.system) {
    return setting.name;
  }
  // OS System default resolution
  final platformLocale = ui.PlatformDispatcher.instance.locale;
  final code = platformLocale.languageCode.toLowerCase();
  final script = platformLocale.scriptCode?.toLowerCase() ?? '';
  final country = platformLocale.countryCode?.toUpperCase() ?? '';

  if (code == 'zh') {
    if (script == 'hant' ||
        country == 'TW' ||
        country == 'HK' ||
        country == 'MO') {
      return 'zhHant';
    }
    return 'zhHans';
  }

  if (_kTranslations.containsKey(code)) {
    return code;
  }
  return 'en'; // Default fallback
});

/// Whether the active language requires Right-to-Left (RTL) layout (e.g. Arabic)
final isRtlProvider = Provider<bool>((ref) {
  final code = ref.watch(activeLanguageCodeProvider);
  return code == 'ar';
});

/// Active Locale object for date/number formatting
final activeLocaleProvider = Provider<Locale>((ref) {
  final code = ref.watch(activeLanguageCodeProvider);
  switch (code) {
    case 'ja':
      return const Locale('ja', 'JP');
    case 'zhHans':
      return const Locale('zh', 'CN');
    case 'zhHant':
      return const Locale('zh', 'TW');
    case 'ko':
      return const Locale('ko', 'KR');
    case 'es':
      return const Locale('es', 'ES');
    case 'pt':
      return const Locale('pt', 'BR');
    case 'fr':
      return const Locale('fr', 'FR');
    case 'de':
      return const Locale('de', 'DE');
    case 'ar':
      return const Locale('ar', 'SA');
    default:
      return const Locale('en', 'US');
  }
});

/// Localized video count with natural plural forms
String formatVideoCount(int count, String langCode) {
  switch (langCode) {
    case 'ja':
      return '$count本の動画';
    case 'zhHans':
      return '$count 个视频';
    case 'zhHant':
      return '$count 部影片';
    case 'ko':
      return '동영상 $count개';
    case 'es':
      return count == 1 ? '1 video' : '$count videos';
    case 'pt':
      return count == 1 ? '1 vídeo' : '$count vídeos';
    case 'fr':
      return count <= 1 ? '$count vidéo' : '$count vidéos';
    case 'de':
      return count == 1 ? '1 Video' : '$count Videos';
    case 'ar':
      if (count == 1) return 'فيديو واحد';
      if (count == 2) return 'فيديوهان';
      if (count >= 3 && count <= 10) return '$count فيديوهات';
      return '$count فيديو';
    default:
      return count == 1 ? '1 video' : '$count videos';
  }
}

/// Localized track count for music-library surfaces.
String formatTrackCount(int count, String langCode) {
  switch (langCode) {
    case 'ja':
      return '$count曲';
    case 'zhHans':
    case 'zhHant':
      return '$count 首歌曲';
    case 'ko':
      return '곡 $count개';
    case 'es':
      return count == 1 ? '1 canción' : '$count canciones';
    case 'pt':
      return count == 1 ? '1 faixa' : '$count faixas';
    case 'fr':
      return count <= 1 ? '$count morceau' : '$count morceaux';
    case 'de':
      return count == 1 ? '1 Titel' : '$count Titel';
    case 'ar':
      if (count == 1) return 'مقطع واحد';
      if (count == 2) return 'مقطعان';
      return '$count مقاطع';
    default:
      return count == 1 ? '1 track' : '$count tracks';
  }
}

/// Localized playlist count with natural plural forms
String formatPlaylistCount(int count, String langCode) {
  switch (langCode) {
    case 'ja':
      return '$count個のプレイリスト';
    case 'zhHans':
      return '$count 个播放列表';
    case 'zhHant':
      return '$count 個播放清單';
    case 'ko':
      return '재생목록 $count개';
    case 'es':
      return count == 1 ? '1 lista' : '$count listas';
    case 'pt':
      return count == 1 ? '1 playlist' : '$count playlists';
    case 'fr':
      return count <= 1 ? '$count playlist' : '$count playlists';
    case 'de':
      return count == 1 ? '1 Playlist' : '$count Playlists';
    case 'ar':
      if (count == 1) return 'قائمة واحدة';
      if (count == 2) return 'قائمتان';
      if (count >= 3 && count <= 10) return '$count قوائم';
      return '$count قائمة';
    default:
      return count == 1 ? '1 playlist' : '$count playlists';
  }
}

final stringsProvider = Provider<AppStrings>((ref) {
  final code = ref.watch(activeLanguageCodeProvider);
  return AppStrings(code);
});

/// Easy extension on WidgetRef: ref.tr('key')
extension I18nRefExtension on WidgetRef {
  String tr(String key) {
    final code = watch(activeLanguageCodeProvider);
    return translate(key, code);
  }

  String videosCount(int count) {
    final code = watch(activeLanguageCodeProvider);
    return formatVideoCount(count, code);
  }

  String tracksCount(int count) {
    final code = watch(activeLanguageCodeProvider);
    return formatTrackCount(count, code);
  }

  String playlistsCount(int count) {
    final code = watch(activeLanguageCodeProvider);
    return formatPlaylistCount(count, code);
  }
}

/// Easy extension on String: 'key'.tr(ref)
extension I18nStringExtension on String {
  String tr(WidgetRef ref) => ref.tr(this);
}
