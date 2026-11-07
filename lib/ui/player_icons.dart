import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'player_icon_legacy.dart';

/// The IDs of the shared Music Assistant icon set (music-assistant/shared-icons 0.4.0), bundled as `assets/player_icons/<id>.svg`. Its contract: IDs are never renamed or removed, and an unknown ID shows as [fallbackPlayerIcon].
const playerIconIds = {
  'homepod-mini',
  'sonos',
  'mac',
  'apple-tv',
  'google-nest',
  'voice-pe',
  'wiim',
  'speaker',
  'speakers',
  'soundbar',
  'receiver',
  'radio',
  'tv',
  'monitor',
  'laptop',
  'smartphone',
  'tablet',
  'headphones',
  'bluetooth',
  'airplay',
  'cast',
  'car',
  'music',
  'vinyl',
  'mic',
  'volume',
  'living-room',
  'bedroom',
  'bathroom',
  'toilet',
  'kitchen',
  'office',
  'hallway',
  'garden',
  'outdoor',
  'sun',
  'home',
  'building',
};

const fallbackPlayerIcon = 'speaker';

/// The icon ID of the set that [id] stands for. Older servers send Material Design Icons names (`mdi-television`, or `mdi:television`) and early picker names, which the set's legacy map translates; anything else unknown shows as a speaker.
String playerIconId(String id) {
  if (playerIconIds.contains(id)) return id;
  final legacy = legacyPlayerIcons[id.replaceFirst(RegExp('^mdi:'), 'mdi-')];
  return legacy ?? fallbackPlayerIcon;
}

/// The icon of a Music Assistant player, drawn from the shared icon set in [color] (the icon colour of the theme when null).
class PlayerIcon extends StatelessWidget {
  const PlayerIcon(this.id, {super.key, this.size = 24, this.color});

  /// The `icon` of the player.
  final String id;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/player_icons/${playerIconId(id)}.svg',
    width: size,
    height: size,
    // The artwork paints with currentColor only, so tinting it takes the colour of the icon.
    colorFilter: ColorFilter.mode(
      color ?? IconTheme.of(context).color ?? Colors.white,
      BlendMode.srcIn,
    ),
  );
}
