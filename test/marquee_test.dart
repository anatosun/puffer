import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/ui/widgets/marquee.dart';

void main() {
  Widget line(String text) => ProviderScope(
    child: MaterialApp(
      home: Material(
        child: Center(child: SizedBox(width: 200, child: MarqueeText(text))),
      ),
    ),
  );

  testWidgets('text that fits stays still', (tester) async {
    await tester.pumpWidget(line('Short'));
    expect(find.text('Short'), findsOneWidget);
    await tester.pump(MarqueeText.pause * 2);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a long line scrolls after a pause and comes back to the start', (
    tester,
  ) async {
    const text = 'A very long title that does not fit in two hundred pixels';
    await tester.pumpWidget(line(text));
    final start = tester.getTopLeft(find.text(text).first).dx;
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pump(MarqueeText.pause);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(find.text(text).first).dx, lessThan(start));

    // At the end of the pass the text stands where it began, and rests again.
    while (tester.hasRunningAnimations) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(tester.getTopLeft(find.text(text).first).dx, start);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
