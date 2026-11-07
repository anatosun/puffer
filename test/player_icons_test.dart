import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/ui/player_icons.dart';

void main() {
  test('player icons follow the shared Music Assistant icon set', () {
    expect(playerIconId('kitchen'), 'kitchen');
    expect(playerIconId('sonos'), 'sonos');
    expect(playerIconId('homepod-mini'), 'homepod-mini');
    // Names of servers before the shared icon set, through its legacy map.
    expect(playerIconId('mdi-television'), 'tv');
    expect(playerIconId('mdi:television'), 'tv');
    expect(playerIconId('apple-homepod-mini'), 'homepod-mini');
    // Unknown IDs show as a speaker, as the set asks.
    expect(playerIconId('something-new'), 'speaker');
  });

  test(
    'every icon of the set is bundled, and the list matches its manifest',
    () {
      final manifest = jsonDecode(
        File('assets/player_icons/manifest.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(playerIconIds, {...manifest['icons'] as List});
      expect(fallbackPlayerIcon, manifest['fallback']);
      for (final id in playerIconIds) {
        expect(
          File('assets/player_icons/$id.svg').existsSync(),
          isTrue,
          reason: '$id.svg is bundled',
        );
      }
    },
  );

  testWidgets('a player icon draws from the bundled SVG', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: PlayerIcon('sonos', color: Colors.red)),
      ),
    );
    final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(
      (svg.bytesLoader as SvgAssetLoader).assetName,
      'assets/player_icons/sonos.svg',
    );
    expect(tester.getSize(find.byType(PlayerIcon)), const Size(24, 24));
  });
}
