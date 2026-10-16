import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/domain/creator_names.dart';

void main() {
  test('keeps a solo credit as one name', () {
    expect(splitCreatorNames('作者A'), ['作者A']);
  });

  test('splits common collaboration separators', () {
    expect(splitCreatorNames('作者A feat. 作者B、作者C'), ['作者A', '作者B', '作者C']);
    expect(splitCreatorNames('Author A & Author B'), ['Author A', 'Author B']);
  });

  test('formats co-creator separators with a middle dot', () {
    expect(formatCreatorNames('作者A、作者B'), '作者A・作者B');
    expect(formatCreatorNames('作者A / 作者B'), '作者A・作者B');
    expect(splitCreatorNames('作者A・作者B'), ['作者A', '作者B']);
  });
}
