import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streambox/src/audio/resolve_prefetcher.dart';
import 'package:streambox/src/audio/player_controller.dart';
import 'package:streambox/src/models.dart';
import 'package:streambox/src/widgets/diagnostics_panel.dart';
import 'package:streambox/src/widgets/library_panel.dart';
import 'package:streambox/src/widgets/now_playing_panel.dart';
import 'package:streambox/src/widgets/player_dock.dart';
import 'package:streambox/src/widgets/result_tile.dart';
import 'package:streambox/src/widgets/shell_scaffold.dart';

void main() {
  test('track metadata formats artist labels', () {
    const track = TrackMetadata(
      id: 'recording-1',
      title: 'Song',
      artists: [
        ArtistMetadata(name: 'Artist One'),
        ArtistMetadata(name: 'Artist Two'),
      ],
    );

    expect(track.artistLabel, 'Artist One, Artist Two');
  });

  test('discover item parses playable source results', () {
    final item = DiscoverItem.fromJson({
      'id': 'result-1',
      'mode': 'url',
      'label': 'yt-dlp',
      'track': {
        'id': 'url:https://example.test',
        'title': 'Resolved stream',
        'artists': [
          {'name': 'Stream URL'},
        ],
      },
      'source': {
        'adapter': 'yt_dlp',
        'url': 'https://cdn.example.test/audio.m4a',
        'title': 'Resolved stream',
        'is_live': false,
      },
    });

    expect(item.isPlayable, isTrue);
    expect(item.source?.adapter, 'yt_dlp');
    expect(item.track?.title, 'Resolved stream');
  });

  test('discover item parses typed album and artist results', () {
    final response = DiscoverResponse.fromJson({
      'query': 'gims',
      'mode': 'stream',
      'scope': 'all',
      'items': [
        {
          'id': 'album-1',
          'mode': 'stream',
          'kind': 'album',
          'label': 'YouTube Music',
          'album_result': {
            'title': 'Subliminal',
            'artists': [
              {'name': 'GIMS'},
            ],
            'browse_id': 'MPREb_album',
            'playlist_id': 'OLAK5uy_album',
            'year': '2013',
            'artwork_url': 'https://img.example/album.jpg',
          },
        },
        {
          'id': 'artist-1',
          'mode': 'stream',
          'kind': 'artist',
          'label': 'YouTube Music',
          'artist_result': {
            'name': 'GIMS',
            'browse_id': 'UC-gims',
            'artwork_url': 'https://img.example/artist.jpg',
          },
        },
      ],
      'warnings': [],
    });

    expect(response.scope, 'all');
    expect(response.items[0].kind, 'album');
    expect(response.items[0].isPlayable, isFalse);
    expect(response.items[0].albumResult?.artistLabel, 'GIMS');
    expect(response.items[1].kind, 'artist');
    expect(response.items[1].artistResult?.name, 'GIMS');
  });

  test('album and artist details parse typed sections', () {
    final album = AlbumDetail.fromJson({
      'title': 'Subliminal',
      'artists': [
        {'name': 'GIMS'},
      ],
      'browse_id': 'MPREb_album',
      'artwork_url': 'https://img.example/album.jpg',
      'tracks': [
        {
          'id': 'song-1',
          'mode': 'stream',
          'kind': 'song',
          'track': {
            'id': 'ytmusic:56BRFlaxsGw',
            'title': 'Bella',
            'artists': [
              {'name': 'GIMS'},
            ],
            'source_url': 'https://music.youtube.com/watch?v=56BRFlaxsGw',
          },
        }
      ],
    });
    final artist = ArtistDetail.fromJson({
      'name': 'GIMS',
      'artwork_url': 'https://img.example/artist.jpg',
      'sections': [
        {
          'label': 'Top songs',
          'items': [
            {
              'id': 'song-1',
              'mode': 'stream',
              'kind': 'song',
              'track': {
                'id': 'ytmusic:56BRFlaxsGw',
                'title': 'Bella',
                'artists': [
                  {'name': 'GIMS'},
                ],
              },
            }
          ],
        }
      ],
    });

    expect(album.title, 'Subliminal');
    expect(album.tracks.first.track?.title, 'Bella');
    expect(artist.sections.first.label, 'Top songs');
    expect(artist.sections.first.items.first.track?.title, 'Bella');
  });

  test('track metadata parses popularity and match reasons', () {
    final track = TrackMetadata.fromJson({
      'id': 'recording-1',
      'title': 'Song',
      'artists': [
        {'name': 'Artist'},
      ],
      'listen_count': 1000,
      'listener_count': 100,
      'popularity_score': 2000.0,
      'match_reasons': ['popular', 'fuzzy'],
      'confidence_score': 94.0,
      'rank_reason': 'source match',
      'source_url': 'https://www.youtube.com/watch?v=abc',
      'artwork_url': 'https://i.ytimg.com/vi/abc/hqdefault.jpg',
      'source_kind': 'song',
      'parse_source': 'structured',
    });

    expect(track.listenCount, 1000);
    expect(track.matchReasons, contains('popular'));
    expect(track.matchReasons, contains('fuzzy'));
    expect(track.confidenceScore, 94.0);
    expect(track.rankReason, 'source match');
    expect(track.sourceUrl, 'https://www.youtube.com/watch?v=abc');
    expect(track.artworkUrl, 'https://i.ytimg.com/vi/abc/hqdefault.jpg');
    expect(track.sourceKind, 'song');
    expect(track.parseSource, 'structured');
  });

  test('runtime debug parses backend diagnostics', () {
    final runtime = RuntimeDebug.fromJson({
      'api_version': '0.3.0',
      'ytdlp_available': true,
      'ytdlp_path': 'yt-dlp',
    });

    expect(runtime.apiVersion, '0.3.0');
    expect(runtime.ytdlpAvailable, isTrue);
  });

  test('not implemented playback errors get an audio backend message', () {
    final message = friendlyPlaybackError(UnimplementedError());

    expect(message, contains('Audio backend is not initialized'));
  });

  testWidgets('material icons are available for player controls',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Icon(Icons.play_arrow),
        ),
      ),
    );

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('shell renders sidebar, search, now playing, and player dock',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ShellScaffold(
          selectedSection: LibrarySection.search,
          queueCount: 2,
          onSectionSelected: (_) {},
          center: const Text('Search center'),
          nowPlayingPanel: const Text('Now playing panel'),
          playerDock: const Text('Player dock'),
        ),
      ),
    );

    expect(find.text('Streambox'), findsOneWidget);
    expect(find.text('Search'), findsWidgets);
    expect(find.text('Queue'), findsWidgets);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Search center'), findsOneWidget);
    expect(find.text('Now playing panel'), findsOneWidget);
    expect(find.text('Player dock'), findsOneWidget);
  });

  testWidgets('result tile renders artwork, metadata, and actions',
      (tester) async {
    final item = DiscoverItem(
      id: 'source-1',
      mode: 'stream',
      label: 'YouTube Music',
      track: _track(
        title: 'Bella',
        artist: 'GIMS',
        lengthMs: 225000,
        artworkUrl: 'https://img.example/bella.jpg',
      ),
      source: const SourceCandidate(
        adapter: 'yt_dlp',
        url: 'https://stream.example/audio',
        title: 'Bella',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResultTile(
            item: item,
            resolving: false,
            failed: false,
            onPlay: () {},
            onQueue: () {},
          ),
        ),
      ),
    );

    expect(find.text('Bella'), findsOneWidget);
    expect(find.textContaining('GIMS'), findsOneWidget);
    expect(find.text('YouTube Music'), findsOneWidget);
    expect(find.text('Playable'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.byTooltip('Add to queue'), findsOneWidget);
  });

  testWidgets(
      'result tile renders album and artist results without play buttons',
      (tester) async {
    final album = DiscoverItem(
      id: 'album-1',
      mode: 'stream',
      kind: 'album',
      label: 'YouTube Music',
      albumResult: const AlbumSearchResult(
        title: 'Subliminal',
        artists: [ArtistMetadata(name: 'GIMS')],
        artworkUrl: 'https://img.example/album.jpg',
      ),
    );
    final artist = DiscoverItem(
      id: 'artist-1',
      mode: 'stream',
      kind: 'artist',
      label: 'YouTube Music',
      artistResult: const ArtistSearchResult(
        name: 'GIMS',
        artworkUrl: 'https://img.example/artist.jpg',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ResultTile(
                item: album,
                resolving: false,
                failed: false,
                onPlay: () {},
                onQueue: () {},
              ),
              ResultTile(
                item: artist,
                resolving: false,
                failed: false,
                onPlay: () {},
                onQueue: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Subliminal'), findsOneWidget);
    expect(find.text('GIMS'), findsWidgets);
    expect(find.text('Album'), findsOneWidget);
    expect(find.text('Artist'), findsWidgets);
    expect(find.byTooltip('Play'), findsNothing);
    expect(find.byTooltip('Add to queue'), findsNothing);
  });

  testWidgets('result tile opens album and artist rows instead of playing',
      (tester) async {
    var opened = 0;
    var played = 0;
    final album = DiscoverItem(
      id: 'album-1',
      mode: 'stream',
      kind: 'album',
      label: 'YouTube Music',
      albumResult: const AlbumSearchResult(title: 'Subliminal'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResultTile(
            item: album,
            resolving: false,
            failed: false,
            onPlay: () => played++,
            onQueue: () {},
            onOpen: () => opened++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Subliminal'));
    await tester.pumpAndSettle();

    expect(opened, 1);
    expect(played, 0);
    expect(find.byTooltip('Open'), findsOneWidget);
  });

  test('resolve prefetcher stores candidates for top playable results',
      () async {
    final calls = <String>[];
    final prefetcher = ResolvePrefetcher(
      resolve: (track, {sourceUrl}) async {
        calls.add(track.title);
        return ResolveResponse(
          candidates: [
            SourceCandidate(
              adapter: 'yt_dlp',
              url: 'https://stream.example/${track.title}',
              title: track.title,
            )
          ],
          warnings: const [],
        );
      },
    );
    final items = [
      DiscoverItem(
        id: 'song-1',
        mode: 'stream',
        kind: 'song',
        track: _track(title: 'Bella', artist: 'GIMS'),
      ),
      DiscoverItem(
        id: 'album-1',
        mode: 'stream',
        kind: 'album',
        albumResult: const AlbumSearchResult(title: 'Subliminal'),
      ),
      DiscoverItem(
        id: 'song-2',
        mode: 'stream',
        kind: 'song',
        track: _track(title: 'Hello', artist: 'Adele'),
      ),
    ];

    await prefetcher.prefetchTop(items);

    expect(calls, ['Bella', 'Hello']);
    expect(prefetcher.candidatesFor(items.first)?.first.url,
        'https://stream.example/Bella');
  });

  testWidgets('player dock renders current track and empty state',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              PlayerDock(
                current: null,
                playing: false,
                position: Duration.zero,
                duration: Duration.zero,
                queueCount: 0,
                shuffle: false,
                repeat: false,
                onPlayPause: () {},
                onPrevious: () {},
                onNext: () {},
                onSeek: (_) {},
                onShuffle: () {},
                onRepeat: () {},
                onFavorite: () {},
                onSaveQueue: () {},
              ),
              PlayerDock(
                current: PlaybackItem.fromTrack(
                  _track(title: 'Around the World', artist: 'Daft Punk'),
                  const SourceCandidate(
                    adapter: 'yt_dlp',
                    url: 'https://stream.example/audio',
                    title: 'Around the World',
                  ),
                ),
                playing: true,
                position: const Duration(minutes: 2, seconds: 25),
                duration: const Duration(minutes: 7, seconds: 9),
                queueCount: 3,
                shuffle: false,
                repeat: false,
                onPlayPause: () {},
                onPrevious: () {},
                onNext: () {},
                onSeek: (_) {},
                onShuffle: () {},
                onRepeat: () {},
                onFavorite: () {},
                onSaveQueue: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Nothing playing'), findsOneWidget);
    expect(find.text('Around the World'), findsOneWidget);
    expect(find.text('Daft Punk'), findsOneWidget);
    expect(find.text('3 queued'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
  });

  testWidgets('library panel renders playlists, favorites, and recent tracks',
      (tester) async {
    final item = PlaybackItem.fromTrack(
      _track(title: 'Hello', artist: 'Adele'),
      const SourceCandidate(
        adapter: 'yt_dlp',
        url: 'https://stream.example/audio',
        title: 'Hello',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryPanel(
            playlists: [
              Playlist(
                id: 'playlist-1',
                name: 'Evening',
                description: '',
                tracks: [item],
              ),
            ],
            favorites: [Favorite(id: 'favorite-1', item: item)],
            history: [item],
            loading: false,
          ),
        ),
      ),
    );

    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('Evening'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Hello'), findsWidgets);
  });

  testWidgets('diagnostics panel shows Rust DB health success details',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DiagnosticsPanel(
            diagnostics: [
              'Rust core availability: available (streambox-core 0.1.0)',
              'Rust platform: linux-x64',
              'DB path: /tmp/streambox.sqlite3',
              'Schema version: 3',
              'User version: 3',
              'Foreign keys enabled: yes',
            ],
          ),
        ),
      ),
    );

    expect(find.text('DB path: /tmp/streambox.sqlite3'), findsNothing);

    await tester.tap(find.text('Diagnostics'));
    await tester.pumpAndSettle();

    expect(
      find.text('Rust core availability: available (streambox-core 0.1.0)'),
      findsOneWidget,
    );
    expect(find.text('Rust platform: linux-x64'), findsOneWidget);
    expect(find.text('DB path: /tmp/streambox.sqlite3'), findsOneWidget);
    expect(find.text('Schema version: 3'), findsOneWidget);
    expect(find.text('User version: 3'), findsOneWidget);
    expect(find.text('Foreign keys enabled: yes'), findsOneWidget);
  });

  testWidgets('diagnostics panel shows Rust DB health unavailable errors',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DiagnosticsPanel(
            diagnostics: [
              'Rust core availability: unavailable (missing native library)',
              'Rust platform: unknown',
              'Rust DB health unavailable: missing native library',
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Diagnostics'));
    await tester.pumpAndSettle();

    expect(
      find.text('Rust core availability: unavailable (missing native library)'),
      findsOneWidget,
    );
    expect(find.text('Rust platform: unknown'), findsOneWidget);
    expect(
      find.text('Rust DB health unavailable: missing native library'),
      findsOneWidget,
    );
  });

  testWidgets('now playing panel keeps playback errors local', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NowPlayingPanel(
            current: PlaybackItem.fromTrack(
              _track(title: 'Bella', artist: 'GIMS'),
              const SourceCandidate(
                adapter: 'yt_dlp',
                url: 'https://stream.example/audio',
                title: 'Bella',
              ),
            ),
            queue: const [],
            playbackError: 'Audio backend is not initialized.',
            diagnostics: const ['raw resolver output'],
          ),
        ),
      ),
    );

    expect(find.text('Bella'), findsOneWidget);
    expect(find.text('Audio backend is not initialized.'), findsOneWidget);
    expect(find.text('raw resolver output'), findsNothing);

    await tester.tap(find.text('Diagnostics'));
    await tester.pumpAndSettle();

    expect(find.text('raw resolver output'), findsOneWidget);
  });
}

TrackMetadata _track({
  required String title,
  required String artist,
  int? lengthMs,
  String? artworkUrl,
}) {
  return TrackMetadata(
    id: '$artist-$title',
    title: title,
    artists: [ArtistMetadata(name: artist)],
    lengthMs: lengthMs,
    artworkUrl: artworkUrl,
    sourceProvider: 'ytmusic',
    sourceKind: 'song',
  );
}
