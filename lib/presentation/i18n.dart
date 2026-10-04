import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 10 Major Global Languages + System Default
enum AppLanguage {
  system('システム標準 (System)', null),
  ja('🇯🇵 日本語', Locale('ja', 'JP')),
  en('🇺🇸 English', Locale('en', 'US')),
  zhHans('🇨🇳 简体中文', Locale('zh', 'CN')),
  zhHant('🇹🇼 繁體中文', Locale('zh', 'TW')),
  ko('🇰🇷 한국어', Locale('ko', 'KR')),
  es('🇪🇸 Español', Locale('es', 'ES')),
  pt('🇧🇷 Português', Locale('pt', 'BR')),
  fr('🇫🇷 Français', Locale('fr', 'FR')),
  de('🇩🇪 Deutsch', Locale('de', 'DE')),
  ar('🇸🇦 العربية', Locale('ar', 'SA'));

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
const Map<String, Map<String, String>> _kTranslations = {
  // 1. 日本語
  'ja': {
    'app_title': 'yureru',
    'library': 'ライブラリ',
    'all_videos': 'すべての動画',
    'playlists': 'プレイリスト',
    'settings': '設定',
    'new_playlist': '新規プレイリスト',
    'play': '再生',
    'pause': '一時停止',
    'playing': '再生中',
    'paused': '一時停止中',
    'preview': 'プレビュー',
    'queue': '再生キュー',
    'clear_queue': 'キューをクリア',
    'restart_track': '最初から再生',
    'shuffle': 'シャッフル',
    'repeat': 'リピート',
    'prev_video': '前の動画',
    'next_video': '次の動画',
    'mute': 'ミュート',
    'unmute': 'ミュート解除',
    'fullscreen': 'フルスクリーン',
    'untitled': '無題',
    'mode_media': 'メディア',
    'mode_image': '画像',
    'search_hint': '曲、動画、プレイリストを検索...',
    'filter_hint': 'この一覧を絞り込む...',
    'global_search': '全体検索',
    'not_found': '見つかりませんでした',
    'show_sidebar': 'サイドバーを表示',
    'hide_sidebar': 'サイドバーを隠す',
    'show_queue': '再生キューを表示',
    'hide_queue': '再生キューを隠す',
    'queue_width': 'キューの幅',
    'home_greeting': 'おかえりなさい',
    'recent_videos': '最近の動画',
    'quick_picks': 'クイック再生',
    'empty_library': '動画が見つかりません。設定からインポートしてください。',
    'empty_playlist': 'プレイリストはサイドバーの＋から作成できます',
    'library_management': 'ライブラリ管理',
    'language_settings': '言語設定 (Language)',
    'import_video': '動画をインポート',
    'import_video_desc': '動画ファイルを選んでアプリ保存領域にコピーします',
    'import_folder': 'フォルダからインポート',
    'import_folder_desc': 'フォルダの中の動画をまとめて取り込みます',
    'import_folder_referenced': 'フォルダを参照追加',
    'import_folder_referenced_desc': '動画をコピーせず、元のフォルダを参照して取り込みます（PC推奨）',
    'imported_media': 'インポート済みメディア',
    'storage': 'ストレージ',
  },
  // 2. English
  'en': {
    'app_title': 'yureru',
    'library': 'Library',
    'all_videos': 'All Videos',
    'playlists': 'Playlists',
    'settings': 'Settings',
    'new_playlist': 'New Playlist',
    'play': 'Play',
    'pause': 'Pause',
    'playing': 'Now Playing',
    'paused': 'Paused',
    'preview': 'Preview',
    'queue': 'Play Queue',
    'clear_queue': 'Clear Queue',
    'restart_track': 'Play from start',
    'shuffle': 'Shuffle',
    'repeat': 'Repeat',
    'prev_video': 'Previous',
    'next_video': 'Next',
    'mute': 'Mute',
    'unmute': 'Unmute',
    'fullscreen': 'Fullscreen',
    'untitled': 'Untitled',
    'mode_media': 'Media',
    'mode_image': 'Song / Art',
    'search_hint': 'Search songs, videos, playlists...',
    'filter_hint': 'Filter this list...',
    'global_search': 'Search',
    'not_found': 'No results found',
    'show_sidebar': 'Show Sidebar',
    'hide_sidebar': 'Hide Sidebar',
    'show_queue': 'Show Queue',
    'hide_queue': 'Hide Queue',
    'queue_width': 'Queue width',
    'home_greeting': 'Welcome Back',
    'recent_videos': 'Recent Videos',
    'quick_picks': 'Quick Picks',
    'empty_library': 'No videos found. Import from settings.',
    'empty_playlist': 'Create playlists with the + button in the sidebar',
    'library_management': 'Library Management',
    'language_settings': 'Language Settings',
    'import_video': 'Import Videos',
    'import_video_desc': 'Copy video files into app storage',
    'import_folder': 'Import Folder',
    'import_folder_desc': 'Batch import all videos inside a folder',
    'import_folder_referenced': 'Link Folder (No Copy)',
    'import_folder_referenced_desc': 'Reference files directly without copying (Recommended for PC)',
    'imported_media': 'Imported Media',
    'storage': 'Storage',
  },
  // 3. 简体中文
  'zhHans': {
    'app_title': 'yureru',
    'library': '媒体库',
    'all_videos': '所有视频',
    'playlists': '播放列表',
    'settings': '设置',
    'new_playlist': '新建播放列表',
    'play': '播放',
    'pause': '暂停',
    'playing': '正在播放',
    'paused': '已暂停',
    'preview': '预览',
    'queue': '播放队列',
    'clear_queue': '清空队列',
    'restart_track': '从头播放',
    'shuffle': '随机播放',
    'repeat': '单曲/循环',
    'prev_video': '上一个视频',
    'next_video': '下一个视频',
    'mute': '静音',
    'unmute': '取消静音',
    'fullscreen': '全屏',
    'untitled': '无标题',
    'mode_media': '视频',
    'mode_image': '歌曲 / 封面',
    'search_hint': '搜索歌曲、视频、播放列表...',
    'filter_hint': '筛选此列表...',
    'global_search': '全局搜索',
    'not_found': '未找到匹配结果',
    'show_sidebar': '显示侧边栏',
    'hide_sidebar': '隐藏侧边栏',
    'show_queue': '显示播放队列',
    'hide_queue': '隐藏播放队列',
    'queue_width': '队列宽度',
    'home_greeting': '欢迎回来',
    'recent_videos': '最近添加',
    'quick_picks': '快速播放',
    'empty_library': '未找到视频，请在设置中导入。',
    'empty_playlist': '可在侧边栏通过 ＋ 创建播放列表',
    'library_management': '媒体库管理',
    'language_settings': '语言设置 (Language)',
    'import_video': '导入视频',
    'import_video_desc': '选择视频文件并复制到应用存储中',
    'import_folder': '从文件夹导入',
    'import_folder_desc': '批量导入文件夹中的所有视频',
    'import_folder_referenced': '引用文件夹（免复制）',
    'import_folder_referenced_desc': '不复制文件，直接引用原路径（推荐桌面端）',
    'imported_media': '已导入媒体',
    'storage': '存储空间',
  },
  // 4. 繁體中文
  'zhHant': {
    'app_title': 'yureru',
    'library': '媒體庫',
    'all_videos': '所有影片',
    'playlists': '播放清單',
    'settings': '設定',
    'new_playlist': '新增播放清單',
    'play': '播放',
    'pause': '暫停',
    'playing': '正在播放',
    'paused': '已暫停',
    'preview': '預覽',
    'queue': '播放佇列',
    'clear_queue': '清除佇列',
    'restart_track': '從頭播放',
    'shuffle': '隨機播放',
    'repeat': '循環播放',
    'prev_video': '上一部影片',
    'next_video': '下一部影片',
    'mute': '靜音',
    'unmute': '取消靜音',
    'fullscreen': '全螢幕',
    'untitled': '無標題',
    'mode_media': '影片',
    'mode_image': '歌曲 / 封面',
    'search_hint': '搜尋歌曲、影片、播放清單...',
    'filter_hint': '在此清單中篩選...',
    'global_search': '全域搜尋',
    'not_found': '找不到相符結果',
    'show_sidebar': '顯示側邊欄',
    'hide_sidebar': '隱藏側邊欄',
    'show_queue': '顯示播放佇列',
    'hide_queue': '隱藏播放佇列',
    'queue_width': '佇列寬度',
    'home_greeting': '歡迎回來',
    'recent_videos': '最近新增的影片',
    'quick_picks': '快速播放',
    'empty_library': '找不到任何影片，請至設定中匯入。',
    'empty_playlist': '可透過側邊欄的 ＋ 新增播放清單',
    'library_management': '媒體庫管理',
    'language_settings': '語言設定 (Language)',
    'import_video': '匯入影片',
    'import_video_desc': '選取影片檔案並複製至應用程式儲存區',
    'import_folder': '從資料夾匯入',
    'import_folder_desc': '整批匯入資料夾內的所有影片',
    'import_folder_referenced': '以參照方式加入資料夾',
    'import_folder_referenced_desc': '不複製檔案，直接參照原始路徑（PC推薦）',
    'imported_media': '已匯入的媒體',
    'storage': '儲存空間',
  },
  // 5. 한국어
  'ko': {
    'app_title': 'yureru',
    'library': '보관함',
    'all_videos': '모든 동영상',
    'playlists': '재생목록',
    'settings': '설정',
    'new_playlist': '새 재생목록',
    'play': '재생',
    'pause': '일시중지',
    'playing': '재생 중',
    'paused': '일시중지됨',
    'preview': '미리보기',
    'queue': '재생 대기열',
    'clear_queue': '대기열 지우기',
    'restart_track': '처음부터 재생',
    'shuffle': '임의 재생',
    'repeat': '반복',
    'prev_video': '이전 동영상',
    'next_video': '다음 동영상',
    'mute': '음소거',
    'unmute': '음소거 해제',
    'fullscreen': '전체 화면',
    'untitled': '제목 없음',
    'mode_media': '동영상',
    'mode_image': '노래 / 아트',
    'search_hint': '노래, 동영상, 재생목록 검색...',
    'filter_hint': '이 목록 필터링...',
    'global_search': '전체 검색',
    'not_found': '결과를 찾을 수 없습니다',
    'show_sidebar': '사이드바 표시',
    'hide_sidebar': '사이드바 숨기기',
    'show_queue': '재생 대기열 표시',
    'hide_queue': '재생 대기열 숨기기',
    'queue_width': '대기열 너비',
    'home_greeting': '다시 오신 것을 환영합니다',
    'recent_videos': '최근 동영상',
    'quick_picks': '빠른 재생',
    'empty_library': '동영상이 없습니다. 설정에서 가져오세요.',
    'empty_playlist': '사이드바의 + 버튼으로 재생목록을 만들 수 있습니다',
    'library_management': '보관함 관리',
    'language_settings': '언어 설정 (Language)',
    'import_video': '동영상 가져오기',
    'import_video_desc': '동영상 파일을 앱 저장소에 복사합니다',
    'import_folder': '폴더에서 가져오기',
    'import_folder_desc': '폴더 안의 모든 동영상을 한 번에 가져옵니다',
    'import_folder_referenced': '폴더 참조 추가',
    'import_folder_referenced_desc': '파일을 복사하지 않고 원본 위치를 참조합니다 (PC 권장)',
    'imported_media': '가져온 미디어',
    'storage': '저장소',
  },
  // 6. Español
  'es': {
    'app_title': 'yureru',
    'library': 'Biblioteca',
    'all_videos': 'Todos los videos',
    'playlists': 'Listas de reproducción',
    'settings': 'Ajustes',
    'new_playlist': 'Nueva lista',
    'play': 'Reproducir',
    'pause': 'Pausar',
    'playing': 'Reproduciendo',
    'paused': 'En pausa',
    'preview': 'Vista previa',
    'queue': 'Cola de reproducción',
    'clear_queue': 'Borrar cola',
    'restart_track': 'Desde el principio',
    'shuffle': 'Aleatorio',
    'repeat': 'Repetir',
    'prev_video': 'Anterior',
    'next_video': 'Siguiente',
    'mute': 'Silenciar',
    'unmute': 'Activar sonido',
    'fullscreen': 'Pantalla completa',
    'untitled': 'Sin título',
    'mode_media': 'Video',
    'mode_image': 'Canción / Portada',
    'search_hint': 'Buscar canciones, videos, listas...',
    'filter_hint': 'Filtrar esta lista...',
    'global_search': 'Buscar',
    'not_found': 'No se encontraron resultados',
    'show_sidebar': 'Mostrar barra lateral',
    'hide_sidebar': 'Ocultar barra lateral',
    'show_queue': 'Mostrar cola',
    'hide_queue': 'Ocultar cola',
    'queue_width': 'Ancho de la cola',
    'home_greeting': 'Bienvenido de nuevo',
    'recent_videos': 'Videos recientes',
    'quick_picks': 'Selección rápida',
    'empty_library': 'No hay videos. Importa desde los ajustes.',
    'empty_playlist': 'Crea listas con el botón ＋ en la barra lateral',
    'library_management': 'Gestión de biblioteca',
    'language_settings': 'Idioma (Language)',
    'import_video': 'Importar videos',
    'import_video_desc': 'Copiar archivos de video al almacenamiento de la app',
    'import_folder': 'Importar carpeta',
    'import_folder_desc': 'Importar todos los videos de una carpeta',
    'import_folder_referenced': 'Vincular carpeta (Sin copiar)',
    'import_folder_referenced_desc': 'Hacer referencia a los archivos sin copiarlos (Recomendado para PC)',
    'imported_media': 'Archivos importados',
    'storage': 'Almacenamiento',
  },
  // 7. Português
  'pt': {
    'app_title': 'yureru',
    'library': 'Biblioteca',
    'all_videos': 'Todos os vídeos',
    'playlists': 'Playlists',
    'settings': 'Configurações',
    'new_playlist': 'Nova playlist',
    'play': 'Tocar',
    'pause': 'Pausar',
    'playing': 'Tocando agora',
    'paused': 'Pausado',
    'preview': 'Pré-visualização',
    'queue': 'Fila de reprodução',
    'clear_queue': 'Limpar fila',
    'restart_track': 'Tocar do início',
    'shuffle': 'Ordem aleatória',
    'repeat': 'Repetir',
    'prev_video': 'Anterior',
    'next_video': 'Próximo',
    'mute': 'Mudo',
    'unmute': 'Ativar som',
    'fullscreen': 'Tela cheia',
    'untitled': 'Sem título',
    'mode_media': 'Vídeo',
    'mode_image': 'Música / Capa',
    'search_hint': 'Buscar músicas, vídeos, playlists...',
    'filter_hint': 'Filtrar esta lista...',
    'global_search': 'Buscar',
    'not_found': 'Nenhum resultado encontrado',
    'show_sidebar': 'Mostrar barra lateral',
    'hide_sidebar': 'Ocultar barra lateral',
    'show_queue': 'Mostrar fila',
    'hide_queue': 'Ocultar fila',
    'queue_width': 'Largura da fila',
    'home_greeting': 'Bem-vindo de volta',
    'recent_videos': 'Vídeos recentes',
    'quick_picks': 'Tocar rápido',
    'empty_library': 'Nenhum vídeo encontrado. Importe nas configurações.',
    'empty_playlist': 'Crie playlists com o botão ＋ na barra lateral',
    'library_management': 'Gerenciar biblioteca',
    'language_settings': 'Idioma (Language)',
    'import_video': 'Importar vídeos',
    'import_video_desc': 'Copiar arquivos de vídeo para o armazenamento do app',
    'import_folder': 'Importar pasta',
    'import_folder_desc': 'Importar todos os vídeos dentro de uma pasta',
    'import_folder_referenced': 'Vincular pasta (Sem copiar)',
    'import_folder_referenced_desc': 'Referenciar arquivos diretamente sem copiar (Recomendado para PC)',
    'imported_media': 'Mídias importadas',
    'storage': 'Armazenamento',
  },
  // 8. Français
  'fr': {
    'app_title': 'yureru',
    'library': 'Bibliothèque',
    'all_videos': 'Toutes les vidéos',
    'playlists': 'Playlists',
    'settings': 'Paramètres',
    'new_playlist': 'Nouvelle playlist',
    'play': 'Lire',
    'pause': 'Pause',
    'playing': 'Lecture en cours',
    'paused': 'En pause',
    'preview': 'Aperçu',
    'queue': 'File d\'attente',
    'clear_queue': 'Vider la file',
    'restart_track': 'Recommencer',
    'shuffle': 'Aléatoire',
    'repeat': 'Répéter',
    'prev_video': 'Précédente',
    'next_video': 'Suivante',
    'mute': 'Muet',
    'unmute': 'Activer le son',
    'fullscreen': 'Plein écran',
    'untitled': 'Sans titre',
    'mode_media': 'Vidéo',
    'mode_image': 'Titre / Jaquette',
    'search_hint': 'Rechercher titres, vidéos, playlists...',
    'filter_hint': 'Filtrer cette liste...',
    'global_search': 'Recherche',
    'not_found': 'Aucun résultat trouvé',
    'show_sidebar': 'Afficher le volet',
    'hide_sidebar': 'Masquer le volet',
    'show_queue': 'Afficher la file',
    'hide_queue': 'Masquer la file',
    'queue_width': 'Largeur de la file',
    'home_greeting': 'Bon retour',
    'recent_videos': 'Vidéos récentes',
    'quick_picks': 'Sélection rapide',
    'empty_library': 'Aucune vidéo trouvée. Importez-en depuis les paramètres.',
    'empty_playlist': 'Créez des playlists avec le bouton ＋ du volet',
    'library_management': 'Gestion de la bibliothèque',
    'language_settings': 'Langue (Language)',
    'import_video': 'Importer des vidéos',
    'import_video_desc': 'Copier les fichiers vidéo dans l\'espace de stockage de l\'application',
    'import_folder': 'Importer un dossier',
    'import_folder_desc': 'Importer toutes les vidéos d\'un dossier',
    'import_folder_referenced': 'Lier un dossier (Sans copie)',
    'import_folder_referenced_desc': 'Référencer les fichiers sans les copier (Recommandé sur PC)',
    'imported_media': 'Médias importés',
    'storage': 'Stockage',
  },
  // 9. Deutsch
  'de': {
    'app_title': 'yureru',
    'library': 'Mediathek',
    'all_videos': 'Alle Videos',
    'playlists': 'Playlists',
    'settings': 'Einstellungen',
    'new_playlist': 'Neue Playlist',
    'play': 'Wiedergabe',
    'pause': 'Pause',
    'playing': 'Wird abgespielt',
    'paused': 'Pausiert',
    'preview': 'Vorschau',
    'queue': 'Warteschlange',
    'clear_queue': 'Warteschlange leeren',
    'restart_track': 'Von vorne abspielen',
    'shuffle': 'Zufallswiedergabe',
    'repeat': 'Wiederholen',
    'prev_video': 'Vorheriges Video',
    'next_video': 'Nächstes Video',
    'mute': 'Stummschalten',
    'unmute': 'Ton einschalten',
    'fullscreen': 'Vollbild',
    'untitled': 'Ohne Titel',
    'mode_media': 'Video',
    'mode_image': 'Titel / Cover',
    'search_hint': 'Titel, Videos, Playlists suchen...',
    'filter_hint': 'Diese Liste filtern...',
    'global_search': 'Suchen',
    'not_found': 'Keine Treffer gefunden',
    'show_sidebar': 'Seitenleiste einblenden',
    'hide_sidebar': 'Seitenleiste ausblenden',
    'show_queue': 'Warteschlange anzeigen',
    'hide_queue': 'Warteschlange verbergen',
    'queue_width': 'Breite der Warteschlange',
    'home_greeting': 'Willkommen zurück',
    'recent_videos': 'Zuletzt hinzugefügt',
    'quick_picks': 'Schnellstart',
    'empty_library': 'Keine Videos gefunden. Bitte in den Einstellungen importieren.',
    'empty_playlist': 'Playlists können über das ＋ in der Seitenleiste erstellt werden',
    'library_management': 'Mediathek verwalten',
    'language_settings': 'Sprache (Language)',
    'import_video': 'Videos importieren',
    'import_video_desc': 'Videodateien in den App-Speicher kopieren',
    'import_folder': 'Ordner importieren',
    'import_folder_desc': 'Alle Videos eines Ordners gesammelt hinzufügen',
    'import_folder_referenced': 'Ordner verknüpfen (Keine Kopie)',
    'import_folder_referenced_desc': 'Dateien direkt referenzieren (Für PC empfohlen)',
    'imported_media': 'Importierte Medien',
    'storage': 'Speicherplatz',
  },
  // 10. العربية
  'ar': {
    'app_title': 'yureru',
    'library': 'المكتبة',
    'all_videos': 'جميع الفيديوهات',
    'playlists': 'قوائم التشغيل',
    'settings': 'الإعدادات',
    'new_playlist': 'قائمة تشغيل جديدة',
    'play': 'تشغيل',
    'pause': 'إيقاف مؤقت',
    'playing': 'قيد التشغيل',
    'paused': 'متوقف مؤقتاً',
    'preview': 'معاينة',
    'queue': 'قائمة الانتظار',
    'clear_queue': 'مسح القائمة',
    'restart_track': 'التشغيل من البداية',
    'shuffle': 'تشغيل عشوائي',
    'repeat': 'تكرار',
    'prev_video': 'السابق',
    'next_video': 'التالي',
    'mute': 'كتم الصوت',
    'unmute': 'إلغاء الكتم',
    'fullscreen': 'ملء الشاشة',
    'untitled': 'بدون عنوان',
    'mode_media': 'فيديو',
    'mode_image': 'أغنية / غلاف',
    'search_hint': 'البحث عن الأغاني، الفيديوهات، القوائم...',
    'filter_hint': 'تصفية هذه القائمة...',
    'global_search': 'بحث',
    'not_found': 'لم يتم العثور على نتائج',
    'show_sidebar': 'إظهار الشريط الجانبي',
    'hide_sidebar': 'إخفاء الشريط الجانبي',
    'show_queue': 'إظهار قائمة الانتظار',
    'hide_queue': 'إخفاء قائمة الانتظار',
    'queue_width': 'عرض قائمة الانتظار',
    'home_greeting': 'مرحباً بعودتك',
    'recent_videos': 'الفيديوهات الحديثة',
    'quick_picks': 'تشغيل سريع',
    'empty_library': 'لم يتم العثور على فيديوهات. قم بالاستيراد من الإعدادات.',
    'empty_playlist': 'يمكن إنشاء قوائم التشغيل من زر ＋ في الشريط الجانبي',
    'library_management': 'إدارة المكتبة',
    'language_settings': 'إعدادات اللغة (Language)',
    'import_video': 'استيراد فيديوهات',
    'import_video_desc': 'نسخ ملفات الفيديو إلى وحدة تخزين التطبيق',
    'import_folder': 'استيراد مجلد',
    'import_folder_desc': 'استيراد جميع الفيديوهات داخل مجلد بالكامل',
    'import_folder_referenced': 'ربط مجلد (بدون نسخ)',
    'import_folder_referenced_desc': 'الإشارة إلى الملفات مباشرة دون نسخها (موصى به للكمبيوتر)',
    'imported_media': 'الوسائط المستوردة',
    'storage': 'التخزين',
  },
};

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

final languageProvider =
    StateNotifierProvider<LanguageNotifier, AppLanguage>((_) {
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
    if (script == 'hant' || country == 'TW' || country == 'HK' || country == 'MO') {
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
    case 'ja': return const Locale('ja', 'JP');
    case 'zhHans': return const Locale('zh', 'CN');
    case 'zhHant': return const Locale('zh', 'TW');
    case 'ko': return const Locale('ko', 'KR');
    case 'es': return const Locale('es', 'ES');
    case 'pt': return const Locale('pt', 'BR');
    case 'fr': return const Locale('fr', 'FR');
    case 'de': return const Locale('de', 'DE');
    case 'ar': return const Locale('ar', 'SA');
    default: return const Locale('en', 'US');
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

  String playlistsCount(int count) {
    final code = watch(activeLanguageCodeProvider);
    return formatPlaylistCount(count, code);
  }
}

/// Easy extension on String: 'key'.tr(ref)
extension I18nStringExtension on String {
  String tr(WidgetRef ref) => ref.tr(this);
}
