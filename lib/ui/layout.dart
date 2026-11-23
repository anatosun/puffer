import 'package:flutter/widgets.dart';

/// The width from which the app shows a sidebar and a player bar in place of the tab bar and the mini player: a desktop window or a tablet in landscape.
const wideLayoutWidth = 900.0;

bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= wideLayoutWidth;

/// The height under which a window lying on its side counts as short: tabs move to a rail and the player puts its controls beside the artwork.
const shortLayoutHeight = 600.0;

/// Whether the window is wider than tall and shorter than [shortLayoutHeight], and not wide enough for the sidebar.
bool isShortLandscape(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return isShortLandscapeSize(size);
}

bool isShortLandscapeSize(Size size) =>
    size.width < wideLayoutWidth &&
    size.width > size.height &&
    size.height < shortLayoutHeight;
