import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/downloads/library_folder.dart';

void main() {
  test('names are safe on every file system a folder may be copied to', () {
    expect(safeName('AC/DC'), 'AC_DC');
    expect(safeName('What? Why: "Now"'), 'What_ Why_ _Now_');
    expect(safeName('.hidden'), '_hidden');
    expect(safeName('Ends with dots...'), 'Ends with dots');
    expect(safeName('   '), '_');
    expect(safeName('CON'), 'CON_');
    expect(safeName('nul.flac'), 'nul.flac_');
    final long = safeName('é' * 200);
    expect(long.runes.length, 90);
  });

  test('songs are filed under Music by first album artist, album, disc and '
      'number', () {
    const song = Track({
      'id': 't',
      'title': 'Song',
      'artist': 'Guest',
      'displayAlbumArtist': 'Various Artists',
      'album': 'Hits',
      'track': 3,
    });
    expect(
      libraryPath(song, 'flac'),
      'Music/Various Artists/Hits/03 Song.flac',
    );
    const second = Track({
      'id': 't',
      'title': 'B',
      'artist': 'X',
      'album': 'A',
      'track': 1,
      'discNumber': 2,
    });
    expect(libraryPath(second, 'mp3'), 'Music/X/A/2-01 B.mp3');
    const bare = Track({'id': 't', 'title': 'Loose'});
    expect(
      libraryPath(bare, 'opus'),
      'Music/Unknown artist/Unknown album/Loose.opus',
    );
    // An album by several artists goes with the first of them.
    const shared = Track({
      'id': 't',
      'title': 'Kedah',
      'artist': 'Alexey Union • Darknezz',
      'displayAlbumArtist': 'Alexey Union • Darknezz',
      'albumArtists': [
        {'id': 'a', 'name': 'Alexey Union'},
        {'id': 'd', 'name': 'Darknezz'},
      ],
      'album': 'Kedah',
      'track': 1,
    });
    expect(
      libraryPath(shared, 'opus'),
      'Music/Alexey Union/Kedah/01 Kedah.opus',
    );
    expect(numberedPath('X/A/01 B.mp3', 2), 'X/A/01 B (2).mp3');
  });

  FolderTrack folderTrack(String root, Track track) => (
    track: track,
    path: p.joinAll([root, ...libraryPath(track, 'flac').split('/')]),
    size: 1000,
    added: DateTime.utc(2026, 1, 2, 3, 4, 5),
  );

  test('a playlist file names its songs by absolute path', () {
    const root = '/music';
    final t = folderTrack(
      root,
      const Track({
        'id': 't',
        'title': 'Song',
        'artist': 'X',
        'album': 'A',
        'track': 1,
        'duration': 200,
      }),
    );
    expect(
      m3u8('Mix', [t]),
      '#EXTM3U\n#PLAYLIST:Mix\n#EXTINF:200,X - Song\n/music/Music/X/A/01 Song.flac\n',
    );
  });

  test('the iTunes library lists songs with their location and playlists by '
      'track ID', () {
    const root = '/music';
    final a = folderTrack(
      root,
      const Track({
        'id': 'a',
        'title': 'Rock & Roll',
        'artist': 'X',
        'album': 'A',
        'track': 1,
        'duration': 61,
      }),
    );
    final b = folderTrack(
      root,
      const Track({'id': 'b', 'title': 'Two', 'artist': 'X', 'album': 'A'}),
    );
    final xml = itunesLibrary(
      root: root,
      tracks: [a, b],
      playlists: [
        (
          playlist: const Playlist({'id': 'p', 'name': 'Mine'}),
          trackIds: ['b', 'a', 'gone'],
        ),
      ],
      version: '0.1.36',
    );
    expect(xml, contains('<key>Name</key><string>Rock &amp; Roll</string>'));
    expect(xml, contains('<key>Total Time</key><integer>61000</integer>'));
    expect(
      xml,
      contains(
        'file://localhost/music/Music/X/A/01%20Rock%20&amp;%20Roll.flac',
      ),
    );
    expect(xml, contains('<key>Date Added</key><date>2026-01-02T03:04:05Z'));
    // The playlist after the library, with b (ID 2) then a (ID 1); a song without a file is left out.
    final mine = xml.substring(xml.indexOf('<string>Mine</string>'));
    expect(
      RegExp(r'<key>Track ID</key><integer>(\d+)</integer>')
          .allMatches(mine)
          .map((m) => m[1]),
      ['2', '1'],
    );
  });

  test('writing again removes the playlist files of gone playlists and '
      'nothing else', () async {
    final root = (await Directory.systemTemp.createTemp('folder')).path;
    addTearDown(() => Directory(root).delete(recursive: true));
    final t = folderTrack(
      root,
      const Track({'id': 't', 'title': 'S', 'artist': 'X', 'album': 'A'}),
    );
    final mine = File(p.join(root, 'Playlists', 'Mine.m3u8'));
    final own = File(p.join(root, 'Playlists', 'Kept.m3u8'));
    await writePlaylistFiles(
      root: root,
      tracks: [t],
      playlists: [
        (
          playlist: const Playlist({'id': 'p', 'name': 'Mine'}),
          trackIds: ['t'],
        ),
        // Two playlists with one name get two files.
        (playlist: const Playlist({'id': 'q', 'name': 'mine'}), trackIds: []),
      ],
      version: '',
    );
    expect(await mine.exists(), isTrue);
    expect(
      await File(p.join(root, 'Playlists', 'mine (2).m3u8')).exists(),
      isTrue,
    );
    expect(await File(p.join(root, itunesLibraryFile)).exists(), isTrue);
    await own.writeAsString('a person made this');

    await writePlaylistFiles(
      root: root,
      tracks: const [],
      playlists: const [],
      version: '',
    );
    expect(await mine.exists(), isFalse);
    expect(await own.exists(), isTrue);
    expect(await File(p.join(root, itunesLibraryFile)).exists(), isFalse);
  });

  test('empty folders go up to the root, which stays', () async {
    final root = (await Directory.systemTemp.createTemp('folder')).path;
    addTearDown(() => Directory(root).delete(recursive: true));
    final file = p.join(root, 'X', 'A', '01 S.flac');
    await Directory(p.dirname(file)).create(recursive: true);
    await File(p.join(root, 'X', 'other.flac')).writeAsString('');
    await pruneEmptyFolders(file, root);
    expect(await Directory(p.join(root, 'X', 'A')).exists(), isFalse);
    expect(await Directory(p.join(root, 'X')).exists(), isTrue);
    await File(p.join(root, 'X', 'other.flac')).delete();
    await pruneEmptyFolders(p.join(root, 'X', 'other.flac'), root);
    expect(await Directory(p.join(root, 'X')).exists(), isFalse);
    expect(await Directory(root).exists(), isTrue);
  });
}
