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
        'ambient_frame_rate_desc',
        'lyrics_timing',
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
