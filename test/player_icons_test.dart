import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/ui/player_icons.dart';

void main() {
  test('player icons follow the shared Music Assistant icon set', () {
    expect(playerIcon('kitchen'), Icons.kitchen);
    expect(playerIcon('speakers'), Icons.speaker_group);
    expect(playerIcon('sonos'), Icons.speaker);
    expect(playerIcon('mdi-television'), Icons.tv);
    expect(playerIcon('mdi:cast-variant'), Icons.cast);
    expect(playerIcon('something-new'), Icons.speaker);
  });
}
