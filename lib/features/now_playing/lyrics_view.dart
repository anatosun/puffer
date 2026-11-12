import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/playback_providers.dart';
import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../playback/playback_controller.dart';

/// The lyrics of a song. Null while they load or when there are none.
final lyricsProvider = FutureProvider.autoDispose.family<Lyrics?, String>((
  ref,
  id,
) async {
  ref.watch(isOfflineProvider);
  return ref.watch(repositoryProvider)?.lyrics(id);
});

/// Lyrics over the artwork. Timed lyrics follow the song and keep the line sung in the middle; plain lyrics scroll by hand.
class LyricsPanel extends ConsumerWidget {
  const LyricsPanel({super.key, required this.np, this.radius = 10});

  final NowPlaying np;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = np.track?.id;
    final lyrics = id == null ? null : ref.watch(lyricsProvider(id));
    final Widget body = switch (lyrics) {
      null => const _Message('No lyrics'),
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      AsyncData(value: final l?) => _Lines(np: np, lyrics: l),
      _ => const _Message('No lyrics for this song'),
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.72),
        child: body,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      text,
      style: const TextStyle(color: Colors.white70, fontSize: 16),
    ),
  );
}

class _Lines extends ConsumerStatefulWidget {
  const _Lines({required this.np, required this.lyrics});

  final NowPlaying np;
  final Lyrics lyrics;

  @override
  ConsumerState<_Lines> createState() => _LinesState();
}

class _LinesState extends ConsumerState<_Lines> {
  late List<LyricLine> _lines = widget.lyrics.lines;
  late List<GlobalKey> _keys = [for (final _ in _lines) GlobalKey()];
  int? _shown;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_Lines old) {
    super.didUpdateWidget(old);
    if (old.lyrics.json != widget.lyrics.json) {
      _lines = widget.lyrics.lines;
      _keys = [for (final _ in _lines) GlobalKey()];
      _shown = null;
    }
  }

  void _follow(int? current) {
    if (current == null || current == _shown) return;
    _shown = current;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final line = _keys[current].currentContext?.findRenderObject();
      if (!mounted || line == null || !_scroll.hasClients) return;
      // Only this list scrolls. Scrollable.ensureVisible would also move the page of the player, down to the queue.
      final target = RenderAbstractViewport.of(line)
          .getOffsetToReveal(line, 0.4)
          .offset;
      _scroll.animateTo(
        target.clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(positionClockProvider);
    final synced = widget.lyrics.synced;
    final current = synced
        ? currentLyricLine(_lines, widget.np.positionNow())
        : null;
    _follow(current);
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 56),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, line) in _lines.indexed)
              Padding(
                key: _keys[i],
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: TextStyle(
                    fontSize: synced && i == current ? 22 : 18,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    color: !synced || i == current
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.5),
                  ),
                  child: Text(line.text.isEmpty ? '♪' : line.text),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
