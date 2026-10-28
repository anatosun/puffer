import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/cast/music_assistant_page.dart';
import '../features/collection/album_page.dart';
import '../features/collection/artist_page.dart';
import '../features/collection/playlist_page.dart';
import '../features/home/home_page.dart';
import '../features/library/album_lists.dart';
import '../features/library/library_page.dart';
import '../features/login/login_page.dart';
import '../features/now_playing/now_playing.dart';
import '../features/now_playing/speaker_bar.dart';
import '../features/search/search_page.dart';
import '../features/settings/downloads_settings_page.dart';
import '../features/settings/experience_settings_page.dart';
import '../features/settings/playback_settings_page.dart';
import '../features/settings/settings_page.dart';
import '../ui/messages.dart';
import '../ui/theme.dart';
import 'experience.dart';
import 'providers.dart';
import 'sendspin_providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final signedIn = ValueNotifier(ref.read(credentialsProvider) != null);
  ref.listen(credentialsProvider, (_, next) => signedIn.value = next != null);
  ref.onDispose(signedIn.dispose);

  return GoRouter(
    initialLocation: ref.read(startTabProvider).path,
    refreshListenable: signedIn,
    redirect: (context, state) {
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn.value) return atLogin ? null : '/login';
      return atLogin ? '/home' : null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
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
        );
      },
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.location, required this.child});

  final String location;
  final Widget child;

  static const _tabs = ['/home', '/library', '/search'];

  @override
  Widget build(BuildContext context) {
    // Settings open from the library, so the library tab stays selected.
    final index = location.startsWith('/settings')
        ? 1
        : _tabs.indexWhere(location.startsWith);
    return Scaffold(
      body: child,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SpeakerBar(),
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: index < 0 ? 0 : index,
            onDestinationSelected: (i) => context.go(_tabs[i]),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: 'Library',
              ),
              NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
            ],
          ),
        ],
      ),
    );
  }
}
