import 'package:flutter/material.dart';

/// The closest Material icon for each ID of the shared Music Assistant icon set (music-assistant/shared-icons). Brands without a Material icon show as a speaker.
const _icons = <String, IconData>{
  'homepod-mini': Icons.speaker,
  'sonos': Icons.speaker,
  'google-nest': Icons.speaker,
  'wiim': Icons.speaker,
  'speaker': Icons.speaker,
  'speakers': Icons.speaker_group,
  'soundbar': Icons.surround_sound,
  'mac': Icons.desktop_mac,
  'apple-tv': Icons.tv,
  'tv': Icons.tv,
  'monitor': Icons.monitor,
  'laptop': Icons.laptop,
  'smartphone': Icons.smartphone,
  'tablet': Icons.tablet,
  'voice-pe': Icons.mic,
  'mic': Icons.mic,
  'radio': Icons.radio,
  'headphones': Icons.headphones,
  'bluetooth': Icons.bluetooth_audio,
  'airplay': Icons.airplay,
  'cast': Icons.cast,
  'car': Icons.directions_car,
  'music': Icons.music_note,
  'vinyl': Icons.album,
  'volume': Icons.volume_up,
  'living-room': Icons.weekend,
  'bedroom': Icons.bed,
  'bathroom': Icons.bathtub,
  'toilet': Icons.wc,
  'kitchen': Icons.kitchen,
  'office': Icons.work,
  'hallway': Icons.door_front_door,
  'garden': Icons.yard,
  'outdoor': Icons.deck,
  'sun': Icons.wb_sunny,
  'home': Icons.home,
  'building': Icons.apartment,
  // Names that servers before the shared icon set sent.
  'speaker-multiple': Icons.speaker_group,
  'cast-variant': Icons.cast,
  'television': Icons.tv,
  'apple-airplay': Icons.airplay,
};

/// The icon of a Music Assistant player from its [id] in the shared icon set. Older servers send Material Design Icons names with an `mdi-` or `mdi:` prefix; unknown IDs show as a speaker, as the icon set asks.
IconData playerIcon(String id) {
  final name = id.replaceFirst(RegExp('^mdi[-:]'), '');
  return _icons[name] ?? Icons.speaker;
}
