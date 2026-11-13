import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/core/screen_awake.dart';

void main() {
  test('the screen stays on until the last hold is released', () {
    final sent = <bool>[];
    final awake = ScreenAwake((on) async => sent.add(on));
    awake.hold();
    awake.hold();
    awake.release();
    expect(awake.on, isTrue);
    awake.release();
    expect(awake.on, isFalse);
    expect(sent, [true, false]);
  });

  test('a release without a hold sends nothing', () {
    final sent = <bool>[];
    ScreenAwake((on) async => sent.add(on)).release();
    expect(sent, isEmpty);
  });
}
