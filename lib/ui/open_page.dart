import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Opens the page at [path]. Pages open in the navigator of the tabs, under every route pushed over the router's pages, such as the player and the menus; so those close first, or the page would open out of sight.
void openPage(BuildContext context, String path) {
  final router = GoRouter.of(context);
  Navigator.of(
    context,
    rootNavigator: true,
  ).popUntil((route) => route.settings is Page);
  router.push(path);
}
