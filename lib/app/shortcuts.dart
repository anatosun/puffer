import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../playback/playback_controller.dart';
import 'app.dart';
import 'playback_providers.dart';

/// What a keyboard shortcut does, with the keys the shortcut list shows for it.
enum KeyAction {
  playPause('Play or pause', 'Space'),
  next('Next track', 'Ctrl + →'),
  previous('Previous track', 'Ctrl + ←'),
  seekForward('Forward 10 seconds', '→'),
  seekBack('Back 10 seconds', '←'),
  volumeUp('Volume up', 'Ctrl + ↑'),
  volumeDown('Volume down', 'Ctrl + ↓'),
  shuffle('Shuffle', 'Ctrl + S'),
  repeat('Repeat', 'Ctrl + R'),
  nowPlaying('Open or close the player', 'Ctrl + P'),
  home('Home', 'Ctrl + 1'),
  library('Library', 'Ctrl + 2'),
  search('Search', 'Ctrl + 3 or Ctrl + F'),
  back('Back', 'Esc or Alt + ←'),
  help('Keyboard shortcuts', 'Ctrl + /');

  const KeyAction(this.label, this.keys);

  final String label;
  final String keys;
}

/// The keys of every action. Letters always need Ctrl, so typing in a text field never triggers a shortcut, and [isTextEditingKey] leaves Space and the arrow keys to a text field that has the focus. The media keys of a keyboard work while the window has focus.
const keyBindings = <ShortcutActivator, KeyAction>{
  SingleActivator(LogicalKeyboardKey.space): KeyAction.playPause,
  SingleActivator(LogicalKeyboardKey.mediaPlayPause): KeyAction.playPause,
  SingleActivator(LogicalKeyboardKey.mediaPlay): KeyAction.playPause,
  SingleActivator(LogicalKeyboardKey.mediaPause): KeyAction.playPause,
  SingleActivator(LogicalKeyboardKey.arrowRight, control: true): KeyAction.next,
  SingleActivator(LogicalKeyboardKey.mediaTrackNext): KeyAction.next,
  SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
      KeyAction.previous,
  SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): KeyAction.previous,
  SingleActivator(LogicalKeyboardKey.arrowRight): KeyAction.seekForward,
  SingleActivator(LogicalKeyboardKey.arrowLeft): KeyAction.seekBack,
  SingleActivator(LogicalKeyboardKey.arrowUp, control: true):
      KeyAction.volumeUp,
  SingleActivator(LogicalKeyboardKey.arrowDown, control: true):
      KeyAction.volumeDown,
  SingleActivator(LogicalKeyboardKey.keyS, control: true): KeyAction.shuffle,
  SingleActivator(LogicalKeyboardKey.keyR, control: true): KeyAction.repeat,
  SingleActivator(LogicalKeyboardKey.keyP, control: true): KeyAction.nowPlaying,
  SingleActivator(LogicalKeyboardKey.digit1, control: true): KeyAction.home,
  SingleActivator(LogicalKeyboardKey.digit2, control: true): KeyAction.library,
  SingleActivator(LogicalKeyboardKey.digit3, control: true): KeyAction.search,
  SingleActivator(LogicalKeyboardKey.keyF, control: true): KeyAction.search,
  SingleActivator(LogicalKeyboardKey.escape): KeyAction.back,
  SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): KeyAction.back,
  SingleActivator(LogicalKeyboardKey.slash, control: true): KeyAction.help,
};

/// Whether [activator] uses a key that text fields edit with: Space and the arrow keys, alone or with Ctrl or Alt. Those shortcuts pause while a text field has the focus.
bool isTextEditingKey(ShortcutActivator activator) =>
    activator is SingleActivator &&
    _textEditingKeys.contains(activator.trigger);

final _textEditingKeys = {
  LogicalKeyboardKey.space,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
};

const _seekStep = Duration(seconds: 10);
const _volumeStep = 5;

/// Runs [action] on what is playing and on the router. The player and the shortcut list are screens, so the app passes [openNowPlaying], [isNowPlayingOpen] and [showHelp].
Future<void> performKeyAction(
  WidgetRef ref,
  KeyAction action, {
  required void Function() openNowPlaying,
  required bool Function() isNowPlayingOpen,
  required void Function() showHelp,
}) async {
  final controller = ref.read(playbackControllerProvider);
  final np = controller.current;
  final router = ref.read(routerProvider);
  switch (action) {
    case KeyAction.playPause:
      if (np == null) return;
      await (np.playing ? controller.pause() : controller.play());
    case KeyAction.next:
      await controller.next();
    case KeyAction.previous:
      await controller.previous();
    case KeyAction.seekForward || KeyAction.seekBack:
      if (np == null) return;
      final step = action == KeyAction.seekForward ? _seekStep : -_seekStep;
      var target = np.positionNow() + step;
      if (target < Duration.zero) target = Duration.zero;
      if (np.duration > Duration.zero && target > np.duration) {
        target = np.duration;
      }
      await controller.seek(target);
    case KeyAction.volumeUp || KeyAction.volumeDown:
      // Only Music Assistant players report a volume; this device follows the volume of the system.
      final volume = np?.volume;
      if (volume == null) return;
      final step = action == KeyAction.volumeUp ? _volumeStep : -_volumeStep;
      await controller.setVolume((volume + step).clamp(0, 100));
    case KeyAction.shuffle:
      if (np == null) return;
      await controller.setShuffle(!np.shuffle);
    case KeyAction.repeat:
      if (np == null) return;
      await controller.setRepeat(switch (np.repeat) {
        Repeat.off => Repeat.all,
        Repeat.all => Repeat.one,
        Repeat.one => Repeat.off,
      });
    case KeyAction.nowPlaying:
      if (isNowPlayingOpen()) {
        await router.routerDelegate.popRoute();
      } else if (np != null) {
        openNowPlaying();
      }
    case KeyAction.home:
      router.go('/home');
    case KeyAction.library:
      router.go('/library');
    case KeyAction.search:
      router.go('/search');
    case KeyAction.back:
      // The same as the back button of Android: closes a dialog, the player or a page.
      await router.routerDelegate.popRoute();
    case KeyAction.help:
      showHelp();
  }
}
