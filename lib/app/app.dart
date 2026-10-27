import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/cast/music_assistant_page.dart';
import '../features/collection/album_page.dart';
import '../features/collection/artist_page.dart';
import '../features/collection/playlist_page.dart';
import '../features/home/home_page.dart';
import '../features/library/library_page.dart';
import '../features/login/login_page.dart';
import '../features/now_playing/now_playing.dart';
import '../features/search/search_page.dart';
import '../features/settings/downloads_settings_page.dart';
import '../features/settings/experience_settings_page.dart';
import '../features/settings/playback_settings_page.dart';
import '../features/settings/settings_page.dart';
import '../ui/messages.dart';
import '../ui/theme.dart';
import 'providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final signedIn = ValueNotifier(ref.read(credentialsProvider) != null);
  ref.listen(credentialsProvider, (_, next) => signedIn.value = next != null);
  ref.onDispose(signedIn.dispose);

  return GoRouter(
    initialLocation: '/home',
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
    return MaterialApp.router(
      title: 'Puffer',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      scaffoldMessengerKey: messengerKey,
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
