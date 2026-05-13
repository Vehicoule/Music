import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/player_controller.dart';
import '../audio/resolve_prefetcher.dart';
import '../core/core_client.dart';
import '../models.dart';
import '../native/native_core.dart';
import '../resolver/yt_dlp_engine.dart';
import '../theme.dart';
import '../widgets/album_detail_view.dart';
import '../widgets/artist_detail_view.dart';
import '../widgets/detail_error_state.dart';
import '../widgets/diagnostics_panel.dart';
import '../widgets/empty_search_state.dart';
import '../widgets/library_panel.dart';
import '../widgets/now_playing_panel.dart';
import '../widgets/player_dock.dart';
import '../widgets/queue_center.dart';
import '../widgets/result_section.dart';
import '../widgets/result_tile.dart';
import '../widgets/search_center.dart';
import '../widgets/search_header.dart';
import '../widgets/section_title.dart';
import '../widgets/shell_scaffold.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.coreClient,
    required this.playerController,
    this.nativeCore,
  });

  final CoreClient coreClient;
  final PlayerController playerController;
  final NativeCore? nativeCore;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const expectedApiVersion = '0.3.0';

  final searchController = TextEditingController();
  List<DiscoverItem> results = [];
  DiscoverItem? topPlayable;
  List<Playlist> playlists = [];
  List<Favorite> favorites = [];
  List<PlaybackItem> history = [];
  bool loading = false;
  bool playableLoading = false;
  bool libraryLoading = false;
  String? searchError;
  String? playbackMessage;
  String? runtimeWarning;
  String? libraryError;
  String? detailError;
  String? resolvingItemId;
  String? failedItemId;
  String lastQuery = '';
  String selectedScope = 'all';
  LibrarySection selectedSection = LibrarySection.search;
  AlbumDetail? albumDetail;
  ArtistDetail? artistDetail;
  bool detailLoading = false;
  List<String> nativeDiagnostics = const [];
  int _searchToken = 0;
  TrackResolver? __resolver;
  TrackResolver get _resolver {
    __resolver ??= YtDlpEngine(nativeCore: widget.nativeCore!);
    return __resolver!;
  }

  bool get _hasResolver => widget.nativeCore != null;
  late final ResolvePrefetcher resolvePrefetcher;

  @override
  void initState() {
    super.initState();
    resolvePrefetcher = ResolvePrefetcher(resolve: widget.coreClient.resolve);
    unawaited(_loadNativeCoreHealth());
    unawaited(_loadRuntimeDebug());
    unawaited(_loadLibrary());
    final audioRuntimeWarning = widget.playerController.checkAudioRuntime();
    if (audioRuntimeWarning != null) {
      runtimeWarning = audioRuntimeWarning;
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = searchController.text.trim();
    if (query.isEmpty) {
      return;
    }
    setState(() {
      loading = true;
      playableLoading = false;
      searchError = null;
      playbackMessage = null;
      topPlayable = null;
      albumDetail = null;
      artistDetail = null;
      lastQuery = query;
      selectedSection = LibrarySection.search;
    });
    final token = ++_searchToken;
    try {
      final response =
          await widget.coreClient.discover(query, scope: selectedScope);
      setState(() => results = response.items);
      unawaited(resolvePrefetcher.prefetchTop(response.items));
      if (response.mode == 'metadata') {
        unawaited(_loadPlayableMatch(query, token));
      }
    } catch (exception) {
      setState(() => searchError = _friendlyError(exception));
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _loadPlayableMatch(String query, int token) async {
    setState(() => playableLoading = true);
    try {
      if (_hasResolver) {
        final tracks = await _resolver.search(query);
        if (!mounted || token != _searchToken) {
          return;
        }
        final items = tracks
            .map((track) => _ytdlpTrackToDiscoverItem(track))
            .toList();
        setState(() {
          topPlayable = items.isEmpty ? null : items.first;
        });
      } else {
        final response = await widget.coreClient.discoverPlayable(query);
        if (!mounted || token != _searchToken) {
          return;
        }
        setState(() {
          topPlayable = response.items.isEmpty ? null : response.items.first;
        });
      }
    } catch (_) {
      if (!mounted || token != _searchToken) {
        return;
      }
      setState(() => topPlayable = null);
    } finally {
      if (mounted && token == _searchToken) {
        setState(() => playableLoading = false);
      }
    }
  }

  Future<void> _loadRuntimeDebug() async {
    try {
      final runtime = await widget.coreClient.runtimeDebug();
      if (!mounted) {
        return;
      }
      if (runtime.apiVersion != expectedApiVersion) {
        setState(() {
          runtimeWarning =
              'Native core version mismatch (got ${runtime.apiVersion}, expected $expectedApiVersion).';
        });
      } else if (!runtime.ytdlpAvailable) {
        setState(() {
          runtimeWarning =
              'yt-dlp is not available, so playback resolution will fail.';
        });
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        runtimeWarning =
            'Native core diagnostics are missing. Check Rust build output.';
      });
    }
  }

  Future<void> _loadNativeCoreHealth() async {
    final health = await widget.coreClient.nativeHealth();
    final dbHealth = await widget.coreClient.nativeDbHealth();
    if (!mounted) {
      return;
    }
    setState(() {
      nativeDiagnostics = [
        health.diagnosticLabel,
        'Rust platform: ${health.platform ?? 'unknown'}',
        ...dbHealth.diagnosticLabels,
      ];
    });
  }

  Future<void> _loadLibrary() async {
    setState(() {
      libraryLoading = true;
      libraryError = null;
    });
    try {
      final loadedPlaylists = await widget.coreClient.playlists();
      final loadedFavorites = await widget.coreClient.favorites();
      final loadedHistory = await widget.coreClient.history();
      if (!mounted) {
        return;
      }
      setState(() {
        playlists = loadedPlaylists;
        favorites = loadedFavorites;
        history = loadedHistory;
      });
    } catch (exception) {
      if (!mounted) {
        return;
      }
      setState(() => libraryError = _friendlyError(exception));
    } finally {
      if (mounted) {
        setState(() => libraryLoading = false);
      }
    }
  }

  Future<void> _playResult(DiscoverItem item) async {
    final track = item.track;
    if (track == null || !item.isPlayable) {
      return;
    }
    setState(() {
      resolvingItemId = item.id;
      failedItemId = null;
      playbackMessage = null;
    });
    final source = item.source;
    try {
      if (source != null) {
        await widget.playerController
            .playItem(PlaybackItem.fromTrack(track, source));
      } else if (resolvePrefetcher.candidatesFor(item) != null) {
        await widget.playerController
            .playWithCandidates(track, resolvePrefetcher.candidatesFor(item)!);
      } else if (_hasResolver) {
        final source = await _resolver.resolve(track.sourceUrl ?? '');
        await widget.playerController
            .playItem(PlaybackItem.fromTrack(track, source));
      } else {
        // Fallback to deprecated RustCoreClient.resolve path
        await widget.playerController
            .resolveAndPlay(track, sourceUrl: track.sourceUrl);
      }
      if (widget.playerController.error != null) {
        setState(() {
          failedItemId = item.id;
          playbackMessage = widget.playerController.error;
        });
      }
    } catch (exception) {
      setState(() {
        failedItemId = item.id;
        playbackMessage = friendlyPlaybackError(exception);
      });
    } finally {
      if (mounted) {
        setState(() => resolvingItemId = null);
      }
    }
  }

  Future<void> _queueResult(DiscoverItem item) async {
    final track = item.track;
    if (track == null || !item.isPlayable) {
      return;
    }
    setState(() {
      resolvingItemId = item.id;
      failedItemId = null;
      playbackMessage = null;
    });
    final source = item.source;
    try {
      if (source != null) {
        widget.playerController.enqueue(PlaybackItem.fromTrack(track, source));
      } else if (resolvePrefetcher.candidatesFor(item) != null) {
        widget.playerController.enqueue(
          PlaybackItem.fromTrack(
              track, resolvePrefetcher.candidatesFor(item)!.first),
        );
      } else if (_hasResolver) {
        final source = await _resolver.resolve(track.sourceUrl ?? '');
        widget.playerController
            .enqueue(PlaybackItem.fromTrack(track, source));
      } else {
        // Fallback to deprecated RustCoreClient.resolve path
        await widget.playerController
            .resolveAndEnqueue(track, sourceUrl: track.sourceUrl);
      }
      if (widget.playerController.error != null) {
        setState(() {
          failedItemId = item.id;
          playbackMessage = widget.playerController.error;
        });
      }
    } catch (exception) {
      setState(() {
        failedItemId = item.id;
        playbackMessage = friendlyPlaybackError(exception);
      });
    } finally {
      if (mounted) {
        setState(() => resolvingItemId = null);
      }
    }
  }

  Future<void> _favoriteCurrent() async {
    final current = widget.playerController.current;
    if (current == null) {
      return;
    }
    await widget.coreClient.favorite(current);
    await _loadLibrary();
  }

  Future<void> _openResult(DiscoverItem item) async {
    if (item.kind == 'album') {
      final browseId = item.albumResult?.browseId;
      if (browseId == null || browseId.isEmpty) {
        return;
      }
      setState(() {
        detailLoading = true;
        detailError = null;
        albumDetail = null;
        artistDetail = null;
      });
      try {
        final detail = await widget.coreClient.albumDetail(browseId);
        if (!mounted) {
          return;
        }
        setState(() => albumDetail = detail);
        unawaited(resolvePrefetcher.prefetchTop(detail.tracks));
      } catch (exception) {
        if (mounted) {
          setState(() => detailError = _friendlyError(exception));
        }
      } finally {
        if (mounted) {
          setState(() => detailLoading = false);
        }
      }
      return;
    }
    if (item.kind == 'artist') {
      final browseId = item.artistResult?.browseId;
      if (browseId == null || browseId.isEmpty) {
        return;
      }
      setState(() {
        detailLoading = true;
        detailError = null;
        albumDetail = null;
        artistDetail = null;
      });
      try {
        final detail = await widget.coreClient.artistDetail(browseId);
        if (!mounted) {
          return;
        }
        setState(() => artistDetail = detail);
        unawaited(
          resolvePrefetcher.prefetchTop([
            for (final section in detail.sections) ...section.items,
          ]),
        );
      } catch (exception) {
        if (mounted) {
          setState(() => detailError = _friendlyError(exception));
        }
      } finally {
        if (mounted) {
          setState(() => detailLoading = false);
        }
      }
    }
  }

  void _backToResults() {
    setState(() {
      albumDetail = null;
      artistDetail = null;
      detailError = null;
      detailLoading = false;
    });
  }

  DiscoverItem _ytdlpTrackToDiscoverItem(Map<String, dynamic> track) {
    final id = track['id'] as String? ?? '';
    final title = track['title'] as String? ?? '';
    final url = track['url'] as String? ?? '';
    final webpageUrl = track['webpage_url'] as String? ?? url;
    final uploader = track['uploader'] as String? ?? '';
    final duration = (track['duration_seconds'] as num?)?.toDouble();
    final thumbnail = track['thumbnail'] as String?;

    return DiscoverItem(
      id: 'youtube:$id',
      mode: 'stream',
      kind: 'song',
      label: 'YouTube Music',
      track: TrackMetadata(
        id: 'youtube:$id',
        title: title,
        artists: uploader.isNotEmpty
            ? [ArtistMetadata(name: uploader)]
            : [const ArtistMetadata(name: 'YouTube')],
        lengthMs: duration != null ? (duration * 1000).round() : null,
        artworkUrl: thumbnail,
        sourceProvider: 'youtube',
        sourceId: id,
        sourceUrl: webpageUrl,
        sourceKind: 'song',
        source: 'youtube',
      ),
    );
  }

  Future<void> _testAudioEngine() async {
    setState(() {
      failedItemId = null;
      playbackMessage = null;
    });
    try {
      await widget.playerController.testAudioEngine();
    } catch (exception) {
      setState(() => playbackMessage = friendlyPlaybackError(exception));
    }
  }

  Future<void> _saveQueue() async {
    final queue = widget.playerController.queue;
    if (queue.isEmpty) {
      return;
    }
    await widget.coreClient.createPlaylist(
      'Queue ${DateTime.now().toLocal().toIso8601String().substring(0, 16)}',
      queue,
    );
    await _loadLibrary();
  }

  String _friendlyError(Object exception) {
    final message = exception.toString();
    if (message.contains('Connection refused')) {
      return 'Native core is unreachable. Check that streambox_core.dll is built.';
    }
    if (message.contains('HTTP 500')) {
      return 'The backend failed that request. Check the server log and retry.';
    }
    if (message.contains('NotImplementedError')) {
      return 'Audio backend is not initialized. Run Test audio engine.';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.playerController,
      builder: (context, _) {
        final controller = widget.playerController;
        final playbackError = playbackMessage ?? controller.error;
        return ShellScaffold(
          selectedSection: selectedSection,
          queueCount: controller.queue.length,
          onSectionSelected: (section) {
            setState(() => selectedSection = section);
          },
          center: _centerForSection(playbackError),
          nowPlayingPanel: NowPlayingPanel(
            current: controller.current,
            queue: controller.queue,
            playbackError: playbackError,
            diagnostics: [
              ...nativeDiagnostics,
              ...controller.playbackDiagnostics,
            ],
          ),
          playerDock: PlayerDock(
            current: controller.current,
            playing: controller.playing,
            position: controller.position,
            duration: controller.duration,
            queueCount: controller.queue.length,
            shuffle: controller.shuffle,
            repeat: controller.repeat,
            playbackError: playbackError,
            onPlayPause: () => unawaited(controller.togglePlay()),
            onPrevious: () => unawaited(controller.skipPrevious()),
            onNext: () => unawaited(controller.skipNext()),
            onSeek: (value) => unawaited(controller.seek(value)),
            onShuffle: controller.toggleShuffle,
            onRepeat: controller.toggleRepeat,
            onFavorite: () => unawaited(_favoriteCurrent()),
            onSaveQueue: () => unawaited(_saveQueue()),
          ),
        );
      },
    );
  }

  Widget _centerForSection(String? playbackError) {
    switch (selectedSection) {
      case LibrarySection.search:
        return SearchCenter(
          controller: searchController,
          loading: loading,
          playableLoading: playableLoading,
          resolvingItemId: resolvingItemId,
          failedItemId: failedItemId,
          results: results,
          topPlayable: topPlayable,
          searchError: searchError,
          runtimeWarning: runtimeWarning,
          lastQuery: lastQuery,
          onSearch: _search,
          selectedScope: selectedScope,
          onScopeChanged: (scope) {
            setState(() => selectedScope = scope);
            if (searchController.text.trim().isNotEmpty) {
              unawaited(_search());
            }
          },
          onTestAudio: _testAudioEngine,
          onPlay: _playResult,
          onQueue: _queueResult,
          onOpen: _openResult,
          onPrefetch: resolvePrefetcher.prefetch,
          albumDetail: albumDetail,
          artistDetail: artistDetail,
          detailLoading: detailLoading,
          detailError: detailError,
          onBackToResults: _backToResults,
        );
      case LibrarySection.queue:
        return QueueCenter(queue: widget.playerController.queue);
      case LibrarySection.playlists:
      case LibrarySection.favorites:
      case LibrarySection.recent:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (libraryError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InlineMessage(
                  icon: Icons.cloud_off,
                  message: libraryError!,
                  destructive: false,
                ),
              ),
            Expanded(
              child: LibraryPanel(
                playlists: playlists,
                favorites: favorites,
                history: history,
                loading: libraryLoading,
              ),
            ),
          ],
        );
      case LibrarySection.diagnostics:
        return FloatingPanel(
          child: DiagnosticsPanel(
            diagnostics: [
              ...nativeDiagnostics,
              ...widget.playerController.playbackDiagnostics,
            ],
          ),
        );
    }
  }
}
