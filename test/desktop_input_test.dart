import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/ui/widgets/tiles.dart';

void main() {
  testWidgets('a right click opens the menu of a row', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SecondaryTap(
            onTap: () => opened++,
            child: const ListTile(title: Text('Song')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Song'), buttons: kSecondaryButton);
    expect(opened, 1);
    await tester.tap(find.text('Song'));
    expect(opened, 1);
  });

  testWidgets('the play button shows while the mouse is over the cover', (
    tester,
  ) async {
    var played = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: HoverPlay(
              tooltip: 'Play',
              onPlay: () async => played++,
              child: const SizedBox.square(dimension: 150),
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(HoverPlay)));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(played, 1);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  });

  Future<List<String>> dropAfterDrag(
    WidgetTester tester,
    PointerDeviceKind kind,
  ) async {
    final dropped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Column(
            children: [
              SongsDraggable(
                songs: DraggedSongs('Song', () async => const []),
                child: const SizedBox(height: 60, child: Text('Song')),
              ),
              const SizedBox(height: 100),
              DragTarget<DraggedSongs>(
                onAcceptWithDetails: (d) => dropped.add(d.data.label),
                builder: (_, _, _) =>
                    const SizedBox(height: 60, child: Text('Playlist')),
              ),
            ],
          ),
        ),
      ),
    );
    final from = tester.getCenter(find.text('Song'));
    final to = tester.getCenter(find.text('Playlist'));
    final pointer = await tester.createGesture(kind: kind);
    if (kind == PointerDeviceKind.mouse) {
      await pointer.addPointer(location: Offset.zero);
      await pointer.moveTo(from);
      await tester.pump();
    }
    await pointer.down(from);
    await tester.pump();
    for (var i = 1; i <= 10; i++) {
      await pointer.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump();
    }
    await pointer.up();
    await tester.pump();
    return dropped;
  }

  testWidgets('the mouse drags songs onto a playlist', (tester) async {
    expect(await dropAfterDrag(tester, PointerDeviceKind.mouse), ['Song']);
  });

  testWidgets('a finger scrolls instead of dragging songs', (tester) async {
    expect(await dropAfterDrag(tester, PointerDeviceKind.touch), isEmpty);
  });
}
