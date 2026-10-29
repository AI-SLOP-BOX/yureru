import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/presentation/i18n.dart';

void main() {
  test('ambient and lyric settings are translated for every app language', () {
    for (final language in AppLanguage.values.where(
      (language) => language != AppLanguage.system,
    )) {
      for (final key in [
        'volume',
        'immersive',
        'exit_immersive',
        'ambient_strength',
        'ambient_spread',
        'ambient_depth',
        'ambient_softness',
        'ambient_frame_rate',
        'ambient_fps_auto',
        'ambient_frame_rate_desc',
        'sleep_custom_duration',
        'sleep_hours_label',
        'sleep_minutes_label',
        'lyrics_timing',
        'image_display_priority',
        'image_display_priority_desc',
        'image_priority_by_screen',
        'image_priority_artwork',
        'image_priority_thumbnail',
        'image_priority_home',
        'image_priority_playlists',
        'image_priority_albums',
        'playlist_image_priority',
        'image_priority_default',
        'save',
      ]) {
        final value = translate(key, language.name);
        expect(value, isNot(key));
        if (language != AppLanguage.ja &&
            !(key == 'save' && language == AppLanguage.zhHans) &&
            !(key == 'volume' &&
                (language == AppLanguage.zhHans ||
                    language == AppLanguage.zhHant))) {
          final japanese = switch (key) {
            'volume' => '音量',
            'immersive' => '没入モード',
            'exit_immersive' => '没入モードを閉じる',
            'ambient_strength' => '光の強さ',
            'ambient_spread' => '光の広がり',
            'ambient_depth' => '奥行き・傾き',
            'ambient_softness' => 'ぼかし',
            'ambient_frame_rate' => '更新頻度',
            'ambient_frame_rate_desc' => '高いほど滑らかですが、負荷も上がります',
            'lyrics_timing' => '歌詞のタイミング（秒）',
            'image_display_priority' => '画像の表示優先度',
            'image_display_priority_desc' => 'ホーム・プレイリスト・アルバムごとに優先する画像を選びます',
            'image_priority_by_screen' => '画面ごと',
            'image_priority_artwork' => 'ジャケット',
            'image_priority_thumbnail' => 'サムネイル',
            'image_priority_home' => 'ホーム',
            'image_priority_playlists' => 'プレイリスト',
            'image_priority_albums' => 'アルバム',
            'playlist_image_priority' => 'このプレイリストの画像優先度',
            'image_priority_default' => '設定の既定値',
            _ => '保存',
          };
          expect(value, isNot(japanese));
        }
      }
    }
  });

  test('main app surfaces do not fall back to Japanese', () {
    const keys = [
      'scroll_horizontally',
      'sidebar_width',
      'queue_empty',
      'nothing_playing',
      'playlist_empty_detail',
      'add_from_library',
      'delete_playlist',
      'image_mode',
      'video_mode',
      'lyrics_not_found',
      'creator_not_set',
      'title_video',
      'temporary_playback',
      'name_input',
      'add_collaborator',
    ];
    for (final language in AppLanguage.values.where(
      (language) =>
          language != AppLanguage.system && language != AppLanguage.ja,
    )) {
      for (final key in keys) {
        expect(
          translate(key, language.name),
          isNot(translate(key, 'ja')),
          reason: '${language.name}: $key',
        );
      }
    }
  });
}
