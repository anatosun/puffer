import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/ui/widgets/playing_bars.dart';

void main() {
  List<double> heights(WidgetTester tester) => [
    for (final e in find.byType(Container).evaluate())
      tester.getSize(find.byWidget(e.widget)).height,
  ];

  Widget bars({required bool playing, bool shown = true}) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: TickerMode(
        enabled: shown,
        child: PlayingBars(playing: playing, color: Colors.white),
      ),
    ),
  );

  testWidgets('the bars move while the song plays and the bars show', (
    tester,
  ) async {
    await tester.pumpWidget(bars(playing: true));
    final before = heights(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(heights(tester), isNot(before));

    // Under another page the bars stop, and no timer is left to wake the app.
    await tester.pumpWidget(bars(playing: true, shown: false));
    expect(tester.binding.hasScheduledFrame, isFalse);
    final covered = heights(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(heights(tester), covered);
  });

  testWidgets('paused bars rest', (tester) async {
    await tester.pumpWidget(bars(playing: false));
    final before = heights(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(heights(tester), before);
  });
}
