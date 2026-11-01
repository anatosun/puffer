import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/ui/widgets/artwork.dart';

void main() {
  testWidgets(
    'the background cross-fades back and forth faster than its fade',
    (tester) async {
      // A transparent 1×1 PNG.
      final png = MemoryImage(
        Uint8List.fromList(const [
          137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, //
          0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73,
          68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1, 13, 10, 45, 180, 0, 0,
          0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
        ]),
      );
      Widget at(String id) => MaterialApp(
        home: SizedBox.square(
          dimension: 200,
          child: BlurredArtwork(image: png, id: id),
        ),
      );
      // As when playback keeps losing the song and finding it again: A, B, A, B, each before the last fade ends, which leaves two fading copies of A.
      for (final id in ['a', 'b', 'a', 'b', 'a']) {
        await tester.pumpWidget(at(id));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.takeException(), isNull);
    },
  );
}
