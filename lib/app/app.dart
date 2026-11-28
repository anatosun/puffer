import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/car_preview/car_preview_page.dart';
import '../features/cast/music_assistant_page.dart';
import '../features/collection/album_page.dart';
import '../features/collection/artist_page.dart';
import '../features/collection/playlist_page.dart';
import '../features/home/home_page.dart';
import '../features/library/album_lists.dart';
import '../features/library/library_page.dart';
import '../features/library/transfers_page.dart';
import '../features/login/login_page.dart';
import '../features/login/music_assistant_setup_page.dart';
import '../features/login/preferences_setup_page.dart';
import '../features/now_playing/now_playing.dart';
import '../features/now_playing/now_playing_below.dart';
import '../features/now_playing/player_bar.dart';
import '../features/now_playing/speaker_bar.dart';
import '../features/now_playing/waveform.dart';
import '../features/search/search_page.dart';
import '../features/settings/about_page.dart';
import '../features/settings/downloads_settings_page.dart';
import '../features/settings/experience_settings_page.dart';
import '../features/settings/playback_settings_page.dart';
import '../features/settings/server_settings_page.dart';
import '../features/settings/settings_page.dart';
import '../ui/interface_scale.dart';
import '../ui/layout.dart';
import '../ui/messages.dart';
import '../ui/on_screen_keyboard.dart';
import '../ui/sheets.dart';
import '../ui/theme.dart';
import '../ui/widgets/launch_gate.dart';
import 'experience.dart';
import 'playback_providers.dart';
import 'providers.dart';
import 'shortcuts.dart';
import 'sidebar.dart';
import 'sendspin_providers.dart';
import 'setup.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final signedIn = ValueNotifier(ref.read(credentialsProvider) != null);
  ref.listen(credentialsProvider, (_, next) => signedIn.value = next != null);
  ref.onDispose(signedIn.dispose);

  return GoRouter(
    initialLocation: carPreviewEnabled
        ? '/car-preview'
        : ref.read(effectiveStartTabProvider).path,
    refreshListenable: signedIn,
    redirect: (context, state) {
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn.value) return atLogin ? null : '/login';
      if (!atLogin) return null;
      // Right after the first sign-in, the setup offers Music Assistant and then its options, each once.
      return nextSetupPage(ref.read);
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(
        path: '/setup/music-assistant',
        builder: (_, _) => const MusicAssistantSetupPage(),
      ),
      GoRoute(
        path: '/setup/preferences',
        builder: (_, _) => const PreferencesSetupPage(),
      ),
      if (carPreviewEnabled)
        GoRoute(
          path: '/car-preview',
          builder: (_, _) => const CarPreviewPage(),
        ),
      ShellRoute(
        builder: (context, state, child) =>
            _Shell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (_, _) => const NoTransitionPage(child: HomePage()),
          ),
          GoRoute(
            path: '/library',
            pageBuilder: (_, _) => const NoTransitionPage(child: LibraryPage()),
          ),
          GoRoute(
            path: '/home/:shelf',
            builder: (_, s) =>
                ShelfPage(HomeShelf.values.byName(s.pathParameters['shelf']!)),
          ),
          GoRoute(
            path: '/genre/:name',
            builder: (_, s) {
              final name = s.pathParameters['name']!;
              return AlbumQueryPage(
                title: name,
                query: albumQuery('byGenre', genre: name),
              );
            },
          ),
          GoRoute(
            path: '/years/:from/:to',
            builder: (_, s) {
              final from = int.parse(s.pathParameters['from']!),
                  to = int.parse(s.pathParameters['to']!);
              return AlbumQueryPage(
                title: from < 1950 ? 'Before 1950' : '${from}s',
                query: albumQuery('byYear', fromYear: from, toYear: to),
              );
            },
          ),
          GoRoute(
            path: '/library/downloaded',
            builder: (_, _) => const LibraryPage(downloaded: true),
          ),
          GoRoute(
            path: '/library/downloaded/progress',
            builder: (_, _) => const TransfersPage(),
          ),
          GoRoute(
            path: '/library/downloaded/:section',
            builder: (_, s) => LibrarySectionPage(
              LibrarySection.values.byName(s.pathParameters['section']!),
              downloaded: true,
            ),
          ),
          GoRoute(
            path: '/library/:section',
            builder: (_, s) => LibrarySectionPage(
              LibrarySection.values.byName(s.pathParameters['section']!),
            ),
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (_, _) => const NoTransitionPage(child: SearchPage()),
          ),
          GoRoute(
            path: '/album/:id',
            builder: (_, s) => AlbumPage(s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/artist/:id',
            builder: (_, s) => ArtistPage(s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/playlist/:id',
            builder: (_, s) => PlaylistPage(s.pathParameters['id']!),
          ),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
          GoRoute(
            path: '/settings/server',
            builder: (_, _) => const ServerSettingsPage(),
          ),
          GoRoute(
            path: '/settings/server/connection',
            builder: (_, _) => const ConnectionSettingsPage(),
          ),
          GoRoute(
            path: '/settings/experience',
            builder: (_, _) => const ExperienceSettingsPage(),
          ),
          GoRoute(
            path: '/settings/playback',
            builder: (_, _) => const PlaybackSettingsPage(),
          ),
          GoRoute(
            path: '/settings/music-assistant',
            builder: (_, _) => const MusicAssistantPage(),
          ),
          GoRoute(
            path: '/settings/about',
            builder: (_, _) => const AboutPage(),
          ),
          GoRoute(
            path: '/settings/downloads',
            builder: (_, _) => const DownloadsSettingsPage(),
          ),
        ],
      ),
    ],
  );
});

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(playbackProvider);
    ref.watch(queuePersistenceProvider);
    ref.watch(sendspinServiceProvider);
    ref.watch(followSpeakerProvider);
    ref.watch(maRestProvider);
    ref.watch(maEagerReconnectProvider);
    ref.watch(remoteMediaSessionProvider);
    ref.watch(maCrossfadeProvider);
    ref.watch(endlessRadioRunnerProvider);
    ref.watch(maScrobbleRunnerProvider);
    ref.watch(playbackReportRunnerProvider);
    ref.watch(scrobbleFlushProvider);
    ref.watch(sleepTimerRunnerProvider);
    ref.watch(playingWaveformProvider);
    // Once per session: downloaded playlists pick up changes, and automatic downloads follow the starred items.
    ref.watch(startupSyncProvider);
    final accent = ref.watch(accentProvider);
    return DynamicColorBuilder(
      builder: (light, dark) {
        final wallpaper = accent == AccentColour.wallpaper;
        return MaterialApp.router(
          title: 'Puffer',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(
            Brightness.light,
            seed: wallpaper ? light?.primary ?? accent.color : accent.color,
          ),
          darkTheme: buildTheme(
            Brightness.dark,
            seed: wallpaper ? dark?.primary ?? accent.color : accent.color,
          ),
          themeMode: ref.watch(themeModeProvider),
          routerConfig: ref.watch(routerProvider),
          scaffoldMessengerKey: messengerKey,
          // On a cold start, the launch animation plays over the first screen during the first setup, and afterwards when the person turned it on. The gate reads it once, so the setting applies at the next start.
          builder: (context, child) => InterfaceScale(
            scale: ref.watch(interfaceSizeProvider).scale,
            child: LaunchGate(
              enabled: ref.read(playLaunchAnimationProvider),
              child: PointerRecorder(
                child: KeyboardShortcuts(
                  child: OnScreenKeyboardHost(
                    enabled:
                        onScreenKeyboardAvailable &&
                        ref.watch(onScreenKeyboardProvider),
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The navigation bar with the tabs the person chose, or in a wide window the sidebar and the player bar. Pages outside every tab, such as an album, keep the tab they were opened from selected.
class _Shell extends ConsumerStatefulWidget {
  const _Shell({required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  ConsumerState<_Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<_Shell> {
  MainTab? _last;

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(visibleTabsProvider);
    final tab = tabFor(widget.location, tabs) ?? _last;
    _last = tab;
    final index = tab == null ? 0 : tabs.indexOf(tab).clamp(0, tabs.length);
    if (isWide(context)) {
      return Scaffold(
        body: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Sidebar(location: widget.location, selected: tab),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        const SpeakerBar(),
                        Expanded(child: widget.child),
                      ],
                    ),
                  ),
                  if (ref.watch(queuePanelProvider) &&
                      ref.watch(nowPlayingProvider).value != null) ...[
                    const VerticalDivider(width: 1),
                    const QueuePanel(),
                  ],
                ],
              ),
            ),
            const PlayerBar(),
          ],
        ),
      );
    }
    if (isShortLandscape(context)) {
      // A short screen lying on its side, such as a Raspberry Pi panel of 800 × 480 or a phone turned over: the tabs move to a rail on the left, which gives the pages the height of the tab bar.
      return Scaffold(
        body: Row(
          children: [
            _TabRail(
              tabs: tabs,
              index: index,
              onSelected: (i) => context.go(tabs[i].path),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: widget.child),
          ],
        ),
        bottomNavigationBar: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [SpeakerBar(), MiniPlayer()],
        ),
      );
    }
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SpeakerBar(),
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => context.go(tabs[i].path),
            destinations: [
              for (final t in tabs)
                NavigationDestination(
                  icon: Icon(t.icon),
                  selectedIcon: Icon(t.selectedIcon),
                  label: t.label,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The tabs in a rail at the left edge, which scrolls when they do not fit the height.
class _TabRail extends StatelessWidget {
  const _TabRail({
    required this.tabs,
    required this.index,
    required this.onSelected,
  });

  final List<MainTab> tabs;
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: box.maxHeight),
        child: IntrinsicHeight(
          child: NavigationRail(
            selectedIndex: index,
            onDestinationSelected: onSelected,
            labelType: NavigationRailLabelType.all,
            groupAlignment: 0,
            destinations: [
              for (final t in tabs)
                NavigationRailDestination(
                  icon: Icon(t.icon),
                  selectedIcon: Icon(t.selectedIcon),
                  label: Text(t.label),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Binds [keyBindings] for the whole app, the player and dialogs included. It sits above the navigator, so it reaches screens through the navigator of the router.
class KeyboardShortcuts extends ConsumerWidget {
  const KeyboardShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    BuildContext? navigator() =>
        ref.read(routerProvider).routerDelegate.navigatorKey.currentContext;

    bool isNowPlayingOpen() {
      final context = navigator();
      if (context == null) return false;
      var open = false;
      // Reads the top route without popping it.
      Navigator.of(context).popUntil((route) {
        open = route.settings.name == nowPlayingRouteName;
        return true;
      });
      return open;
    }

    void run(KeyAction action) => runPlayback(
      () => performKeyAction(
        ref,
        action,
        openNowPlaying: () {
          if (navigator() case final context?) openNowPlaying(context);
        },
        isNowPlayingOpen: isNowPlayingOpen,
        showHelp: () {
          if (navigator() case final context?) {
            showDialog<void>(
              context: context,
              builder: (_) => const _ShortcutsDialog(),
            );
          }
        },
      ),
    );

    return Focus(
      // Keeps the keyboard focus inside the app, so the shortcuts work before anything is clicked.
      autofocus: true,
      onKeyEvent: (_, event) {
        for (final MapEntry(key: keys, value: action) in keyBindings.entries) {
          if (!keys.accepts(event, HardwareKeyboard.instance)) continue;
          // A text field keeps the keys it edits with, which then reach it unhandled.
          if (isTextEditingKey(keys) && _typing()) {
            return KeyEventResult.ignored;
          }
          run(action);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }

  /// Whether a text field has the keyboard focus.
  static bool _typing() =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>() !=
      null;
}

/// Lists the keyboard shortcuts.
class _ShortcutsDialog extends StatelessWidget {
  const _ShortcutsDialog();

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Keyboard shortcuts'),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in KeyAction.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(action.label)),
                    Text(
                      action.keys,
                      style: TextStyle(
                        color: context.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'The media keys of the keyboard play, pause and skip while Puffer has focus.',
              style: TextStyle(color: context.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
