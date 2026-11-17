import 'package:flutter/widgets.dart';

/// The width from which the app shows a sidebar and a player bar in place of the tab bar and the mini player: a desktop window or a tablet in landscape.
const wideLayoutWidth = 900.0;

bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= wideLayoutWidth;
