import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../data/subsonic/models.dart';

/// The folder that holds the songs, under the root of the library folder.
const musicFolder = 'Music';

/// The folder that holds the playlist files, under the root of the library folder.
const playlistsFolder = 'Playlists';

/// The iTunes library at the root of the library folder, which DJ software such as Rekordbox, Traktor and Serato reads.
const itunesLibraryFile = 'iTunes Library.xml';

/// The list of playlist files Puffer wrote, so a later write removes the ones whose playlist is gone without touching files a person put there.
const _writtenList = '.puffer-playlists.json';

/// [name] made safe as one folder or file name on Linux, Android, iOS, macOS and Windows, which a person may copy the folder to: no separators or reserved characters, no leading dot that would hide it, no trailing dot or space, no reserved Windows device name, and at most 180 bytes of UTF-8, below the 255 bytes of most file systems.
String safeName(String name) {
  var s = name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'), '_')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (s.startsWith('.')) s = '_${s.substring(1)}';
  if (s.isEmpty) s = '_';
  if (RegExp(
    r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$',
    caseSensitive: false,
  ).hasMatch(s)) {
    s = '${s}_';
  }
  while (utf8.encode(s).length > 180) {
    s = String.fromCharCodes(s.runes.take(s.runes.length - 1));
  }
  return s.trimRight();
}

/// The album artist as the server credits it, every artist named: what the iTunes library shows.
String _albumArtist(Track track) {
  final display = track.json['displayAlbumArtist'];
  if (display is String && display.isNotEmpty) return display;
  return _firstAlbumArtist(track);
}

/// The artist a track is filed under: the first album artist, so the songs of a compilation stay in one folder and an album by several artists goes with the first of them rather than into a folder of its own.
String _firstAlbumArtist(Track track) {
  final albumArtists = track.json['albumArtists'];
  if (albumArtists is List && albumArtists.isNotEmpty) {
    final first = albumArtists.first;
    if (first is Map && first['name'] is String && first['name'] != '') {
      return first['name'] as String;
    }
  }
  final display = track.json['displayAlbumArtist'];
  if (display is String && display.isNotEmpty) return display;
  return track.artist ?? 'Unknown artist';
}

/// The path of [track] under the library folder, with `/` separators: `Music/Artist/Album/01 Title.flac`, and `2-01 Title.flac` from the second disc on.
String libraryPath(Track track, String extension) {
  final number = track.trackNumber;
  final disc = track.discNumber > 1 ? '${track.discNumber}-' : '';
  final prefix = number == null
      ? ''
      : '$disc${number.toString().padLeft(2, '0')} ';
  return [
    musicFolder,
    safeName(_firstAlbumArtist(track)),
    safeName(track.album ?? 'Unknown album'),
    safeName('$prefix${track.title}.$extension'),
  ].join('/');
}

/// [path] with ` (2)`, ` (3)` and so on before its extension, for two songs that would take the same name.
String numberedPath(String path, int n) {
  if (n < 2) return path;
  final ext = p.posix.extension(path);
  return '${path.substring(0, path.length - ext.length)} ($n)$ext';
}

/// A song of the library folder: its metadata, where its file is, and its size.
typedef FolderTrack = ({Track track, String path, int size, DateTime added});

/// An extended M3U playlist of [tracks], each named by the absolute path of its file.
String m3u8(String name, List<FolderTrack> tracks) {
  final out = StringBuffer('#EXTM3U\n#PLAYLIST:${_oneLine(name)}\n');
  for (final t in tracks) {
    final artist = t.track.artist;
    final title = artist == null ? t.track.title : '$artist - ${t.track.title}';
    out
      ..write('#EXTINF:${t.track.duration.inSeconds},${_oneLine(title)}\n')
      ..write('${t.path}\n');
  }
  return out.toString();
}

String _oneLine(String s) => s.replaceAll(RegExp(r'[\r\n]+'), ' ');

/// An iTunes library, in the property-list format of the "iTunes Library.xml" that iTunes and Music export, listing [tracks] and [playlists] under the folder [root]. Playlists name their songs by track ID, a number this file gives each song.
String itunesLibrary({
  required String root,
  required List<FolderTrack> tracks,
  required List<({Playlist playlist, List<String> trackIds})> playlists,
  required String version,
}) {
  final ids = <String, int>{};
  for (final t in tracks) {
    ids[t.track.id] = ids.length + 1;
  }
  final out = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
    )
    ..writeln('<plist version="1.0">')
    ..writeln('<dict>');
  void key(String k, String type, Object value, [String indent = '\t']) =>
      out.writeln('$indent<key>$k</key><$type>${_xml('$value')}</$type>');
  key('Major Version', 'integer', 1);
  key('Minor Version', 'integer', 1);
  key('Application Version', 'string', version);
  key('Features', 'integer', 5);
  key('Show Content Ratings', 'true', '');
  key('Music Folder', 'string', _location('$root${p.separator}'));
  key('Library Persistent ID', 'string', _persistentId('library:$root'));
  out
    ..writeln('\t<key>Tracks</key>')
    ..writeln('\t<dict>');
  for (final t in tracks) {
    final track = t.track;
    final id = ids[track.id]!;
    const i = '\t\t\t';
    out
      ..writeln('\t\t<key>$id</key>')
      ..writeln('\t\t<dict>');
    key('Track ID', 'integer', id, i);
    key('Name', 'string', track.title, i);
    if (track.artist != null) key('Artist', 'string', track.artist!, i);
    key('Album Artist', 'string', _albumArtist(track), i);
    if (track.album != null) key('Album', 'string', track.album!, i);
    final genre = track.json['genre'];
    if (genre is String) key('Genre', 'string', genre, i);
    key('Kind', 'string', _kind(p.extension(t.path)), i);
    key('Size', 'integer', t.size, i);
    key('Total Time', 'integer', track.duration.inMilliseconds, i);
    key('Disc Number', 'integer', track.discNumber, i);
    if (track.trackNumber != null) {
      key('Track Number', 'integer', track.trackNumber!, i);
    }
    if (track.year != null) key('Year', 'integer', track.year!, i);
    if (track.bitRate != null) key('Bit Rate', 'integer', track.bitRate!, i);
    key('Date Added', 'date', _date(t.added), i);
    if (track.rating > 0) key('Rating', 'integer', track.rating * 20, i);
    if (track.starred) key('Loved', 'true', '', i);
    key('Persistent ID', 'string', _persistentId('track:${track.id}'), i);
    key('Track Type', 'string', 'File', i);
    key('Location', 'string', _location(t.path), i);
    out.writeln('\t\t</dict>');
  }
  out
    ..writeln('\t</dict>')
    ..writeln('\t<key>Playlists</key>')
    ..writeln('\t<array>');
  void playlist(
    String name,
    String persistentId,
    int playlistId,
    Iterable<int> items, {
    bool master = false,
  }) {
    const i = '\t\t\t';
    out.writeln('\t\t<dict>');
    if (master) {
      key('Master', 'true', '', i);
      key('Visible', 'false', '', i);
    }
    key('Name', 'string', name, i);
    key('Playlist ID', 'integer', playlistId, i);
    key('Playlist Persistent ID', 'string', persistentId, i);
    key('All Items', 'true', '', i);
    out
      ..writeln('$i<key>Playlist Items</key>')
      ..writeln('$i<array>');
    for (final item in items) {
      out.writeln(
        '$i\t<dict><key>Track ID</key><integer>$item</integer></dict>',
      );
    }
    out
      ..writeln('$i</array>')
      ..writeln('\t\t</dict>');
  }

  // The library itself comes first, as iTunes writes it; programs that import playlists skip it.
  playlist(
    'Library',
    _persistentId('master:$root'),
    1,
    ids.values,
    master: true,
  );
  var playlistId = 2;
  for (final entry in playlists) {
    playlist(
      entry.playlist.name,
      _persistentId('playlist:${entry.playlist.id}'),
      playlistId++,
      [for (final id in entry.trackIds) ?ids[id]],
    );
  }
  out
    ..writeln('\t</array>')
    ..writeln('</dict>')
    ..writeln('</plist>');
  return out.toString();
}

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    // XML 1.0 has no place for most control characters.
    .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'), '');

/// A file location as iTunes writes it: `file://localhost/` and the percent-encoded path.
String _location(String path) {
  final uri = Uri.file(path, windows: Platform.isWindows).toString();
  return uri.replaceFirst('file://', 'file://localhost');
}

/// Sixteen hex digits that stay the same for the same [seed], so programs that import the library again recognise its songs and playlists.
String _persistentId(String seed) =>
    md5.convert(utf8.encode(seed)).toString().substring(0, 16).toUpperCase();

String _date(DateTime t) =>
    '${t.toUtc().toIso8601String().split('.').first.replaceAll(RegExp(r'Z$'), '')}Z';

String _kind(String extension) => switch (extension.toLowerCase()) {
  '.mp3' => 'MPEG audio file',
  '.m4a' || '.aac' || '.alac' => 'AAC audio file',
  '.flac' => 'FLAC audio file',
  '.ogg' || '.oga' => 'Ogg Vorbis audio file',
  '.opus' => 'Opus audio file',
  '.wav' => 'WAV audio file',
  '.aif' || '.aiff' => 'AIFF audio file',
  _ => 'Audio file',
};

/// Writes the playlist files of the library folder [root]: one M3U8 file per playlist in [playlistsFolder], and the iTunes library at the root. Removes the playlist files of an earlier write whose playlist is gone, and only those. Each file is written whole to a temporary name first, so a program that reads it never sees half of it.
Future<void> writePlaylistFiles({
  required String root,
  required List<FolderTrack> tracks,
  required List<({Playlist playlist, List<String> trackIds})> playlists,
  required String version,
}) async {
  final folder = Directory(p.join(root, playlistsFolder));
  final listFile = File(p.join(folder.path, _writtenList));
  final before = <String>{};
  if (await listFile.exists()) {
    try {
      before.addAll((jsonDecode(await listFile.readAsString()) as List).cast());
    } on FormatException {
      // A damaged list only means stale files stay behind.
    }
  }
  final byId = {for (final t in tracks) t.track.id: t};
  // Names compare without case, since two names that differ only in case are one file on some file systems.
  final taken = <String>{};
  final written = <String>[];
  for (final entry in playlists) {
    final base = '${safeName(entry.playlist.name)}.m3u8';
    var name = base;
    for (var n = 2; !taken.add(name.toLowerCase()); n++) {
      name = numberedPath(base, n);
    }
    written.add(name);
    final items = [for (final id in entry.trackIds) ?byId[id]];
    await folder.create(recursive: true);
    await _writeWhole(
      File(p.join(folder.path, name)),
      m3u8(entry.playlist.name, items),
    );
  }
  for (final stale in before) {
    if (taken.contains(stale.toLowerCase())) continue;
    final file = File(p.join(folder.path, stale));
    if (await file.exists()) await file.delete();
  }
  if (written.isEmpty) {
    if (await listFile.exists()) await listFile.delete();
    if (await folder.exists() && await folder.list().isEmpty) {
      await folder.delete();
    }
  } else {
    await _writeWhole(listFile, jsonEncode(written..sort()));
  }
  final library = File(p.join(root, itunesLibraryFile));
  if (tracks.isEmpty) {
    if (await library.exists()) await library.delete();
  } else {
    await Directory(root).create(recursive: true);
    await _writeWhole(
      library,
      itunesLibrary(
        root: root,
        tracks: tracks,
        playlists: playlists,
        version: version,
      ),
    );
  }
}

Future<void> _writeWhole(File file, String content) async {
  final temp = File('${file.path}.part');
  await temp.writeAsString(content, flush: true);
  await temp.rename(file.path);
}

/// Deletes the empty folders from the folder of [file] up to [root], left behind once their last song is removed. [root] itself stays.
Future<void> pruneEmptyFolders(String file, String root) async {
  var dir = Directory(p.dirname(file));
  while (p.isWithin(root, dir.path)) {
    if (!await dir.exists()) {
      dir = dir.parent;
      continue;
    }
    if (!await dir.list().isEmpty) return;
    await dir.delete();
    dir = dir.parent;
  }
}

/// Moves [from] to [to], copying when they are on different file systems, where a rename fails.
Future<void> moveFile(String from, String to) async {
  await Directory(p.dirname(to)).create(recursive: true);
  try {
    await File(from).rename(to);
  } on FileSystemException {
    await File(from).copy(to);
    await File(from).delete();
  }
}
