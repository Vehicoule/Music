import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../audio/player_controller.dart';
import '../audio/resolve_prefetcher.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/diagnostics_panel.dart';
import '../widgets/library_panel.dart';
import '../widgets/now_playing_panel.dart';
import '../widgets/player_dock.dart';
import '../widgets/result_tile.dart';
import '../widgets/search_header.dart';
import '../widgets/shell_scaffold.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.apiClient,
    required this.playerController,
  });

  final ApiClient apiClient;
  final PlayerController playerController;

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
  int _searchToken = 0;
  late final ResolvePrefetcher resolvePrefetcher;

  @override
  void initState() {
    super.initState();
    resolvePrefetcher = ResolvePrefetcher(resolve: widget.apiClient.resolve);
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
          await widget.apiClient.discover(query, scope: selectedScope);
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
      final response = await widget.apiClient.discoverPlayable(query);
      if (!mounted || token != _searchToken) {
        return;
      }
      setState(() {
        topPlayable = response.items.isEmpty ? null : response.items.first;
      });
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
      final runtime = await widget.apiClient.runtimeDebug();
      if (!mounted) {
        return;
      }
      if (runtime.apiVersion != expectedApiVersion) {
        setState(() {
          runtimeWarning =
              'Backend looks stale (${runtime.apiVersion}). Restart FastAPI.';
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
            'Backend diagnostics are missing. Restart FastAPI if search fails.';
      });
    }
  }

  Future<void> _loadLibrary() async {
    setState(() {
      libraryLoading = true;
      libraryError = null;
    });
    try {
      final loadedPlaylists = await widget.apiClient.playlists();
      final loadedFavorites = await widget.apiClient.favorites();
      final loadedHistory = await widget.apiClient.history();
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
      } else {
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
      } else {
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
    await widget.apiClient.favorite(current);
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
        final detail = await widget.apiClient.albumDetail(browseId);
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
        final detail = await widget.apiClient.artistDetail(browseId);
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
    await widget.apiClient.createPlaylist(
      'Queue ${DateTime.now().toLocal().toIso8601String().substring(0, 16)}',
      queue,
    );
    await _loadLibrary();
  }

  String _friendlyError(Object exception) {
    final message = exception.toString();
    if (message.contains('Connection refused')) {
      return 'Backend is not running. Start FastAPI and try again.';
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
            diagnostics: controller.playbackDiagnostics,
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
        return _SearchCenter(
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
        return _QueueCenter(queue: widget.playerController.queue);
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
            diagnostics: widget.playerController.playbackDiagnostics,
          ),
        );
    }
  }
}

class _SearchCenter extends StatelessWidget {
  const _SearchCenter({
    required this.controller,
    required this.loading,
    required this.playableLoading,
    required this.resolvingItemId,
    required this.failedItemId,
    required this.results,
    required this.topPlayable,
    required this.onSearch,
    required this.selectedScope,
    required this.onScopeChanged,
    required this.onTestAudio,
    required this.onPlay,
    required this.onQueue,
    required this.onOpen,
    required this.onPrefetch,
    required this.albumDetail,
    required this.artistDetail,
    required this.detailLoading,
    required this.onBackToResults,
    this.searchError,
    this.runtimeWarning,
    this.detailError,
    this.lastQuery = '',
  });

  final TextEditingController controller;
  final bool loading;
  final bool playableLoading;
  final String? resolvingItemId;
  final String? failedItemId;
  final List<DiscoverItem> results;
  final DiscoverItem? topPlayable;
  final String? searchError;
  final String? runtimeWarning;
  final String lastQuery;
  final VoidCallback onSearch;
  final String selectedScope;
  final ValueChanged<String> onScopeChanged;
  final VoidCallback onTestAudio;
  final ValueChanged<DiscoverItem> onPlay;
  final ValueChanged<DiscoverItem> onQueue;
  final ValueChanged<DiscoverItem> onOpen;
  final ValueChanged<DiscoverItem> onPrefetch;
  final AlbumDetail? albumDetail;
  final ArtistDetail? artistDetail;
  final bool detailLoading;
  final String? detailError;
  final VoidCallback onBackToResults;

  @override
  Widget build(BuildContext context) {
    final status = loading
        ? 'Searching sources...'
        : playableLoading
            ? 'Finding playable match'
            : '${results.length} results';
    return FloatingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShellSectionHeader(
            title: 'Search',
            subtitle: 'Find songs through YouTube Music, then stream on play.',
          ),
          const SizedBox(height: 18),
          SearchHeader(
            controller: controller,
            loading: loading,
            status: status,
            lastQuery: lastQuery,
            searchError: searchError,
            runtimeWarning: runtimeWarning,
            onSearch: onSearch,
            selectedScope: selectedScope,
            onScopeChanged: onScopeChanged,
            onTestAudio: onTestAudio,
          ),
          const SizedBox(height: 18),
          Expanded(
            child: detailLoading
                ? const Center(child: CircularProgressIndicator())
                : detailError != null
                    ? _DetailErrorState(
                        message: detailError!,
                        onBack: onBackToResults,
                      )
                    : albumDetail != null
                        ? _AlbumDetailView(
                            detail: albumDetail!,
                            resolvingItemId: resolvingItemId,
                            failedItemId: failedItemId,
                            onBack: onBackToResults,
                            onPlay: onPlay,
                            onQueue: onQueue,
                            onPrefetch: onPrefetch,
                          )
                        : artistDetail != null
                            ? _ArtistDetailView(
                                detail: artistDetail!,
                                resolvingItemId: resolvingItemId,
                                failedItemId: failedItemId,
                                onBack: onBackToResults,
                                onPlay: onPlay,
                                onQueue: onQueue,
                                onOpen: onOpen,
                                onPrefetch: onPrefetch,
                              )
                            : loading && results.isEmpty
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : results.isEmpty &&
                                        topPlayable == null &&
                                        !playableLoading
                                    ? const _EmptySearchState()
                                    : ListView(
                                        children: [
                                          if (topPlayable != null) ...[
                                            const _SectionTitle(
                                                'Top playable match'),
                                            ResultTile(
                                              item: topPlayable!,
                                              resolving: resolvingItemId ==
                                                  topPlayable!.id,
                                              failed: failedItemId ==
                                                  topPlayable!.id,
                                              topMatch: true,
                                              onPlay: () =>
                                                  onPlay(topPlayable!),
                                              onQueue: () =>
                                                  onQueue(topPlayable!),
                                              onPrefetch: () =>
                                                  onPrefetch(topPlayable!),
                                            ),
                                            const SizedBox(height: 10),
                                          ] else if (playableLoading) ...[
                                            const _SectionTitle(
                                                'Finding top playable match'),
                                            const LinearProgressIndicator(
                                                minHeight: 2),
                                            const SizedBox(height: 14),
                                          ],
                                          if (results.isNotEmpty) ...[
                                            for (final section
                                                in _groupedResults(
                                                    results)) ...[
                                              _SectionTitle(section.label),
                                              for (final item in section.items)
                                                ResultTile(
                                                  item: item,
                                                  resolving: resolvingItemId ==
                                                      item.id,
                                                  failed:
                                                      failedItemId == item.id,
                                                  onPlay: () => onPlay(item),
                                                  onQueue: () => onQueue(item),
                                                  onOpen: () => onOpen(item),
                                                  onPrefetch: () =>
                                                      onPrefetch(item),
                                                ),
                                              const SizedBox(height: 6),
                                            ],
                                          ],
                                        ],
                                      ),
          ),
        ],
      ),
    );
  }
}

class _ResultSection {
  const _ResultSection(this.label, this.items);

  final String label;
  final List<DiscoverItem> items;
}

List<_ResultSection> _groupedResults(List<DiscoverItem> results) {
  final order = [
    ('Songs', 'song'),
    ('Albums', 'album'),
    ('Artists', 'artist'),
    ('Videos', 'video'),
    ('Metadata', 'metadata'),
  ];
  final sections = <_ResultSection>[];
  for (final (label, kind) in order) {
    final items = results.where((item) => item.kind == kind).toList();
    if (items.isNotEmpty) {
      sections.add(_ResultSection(label, items));
    }
  }
  final remaining = results
      .where((item) => !order.any((entry) => entry.$2 == item.kind))
      .toList();
  if (remaining.isNotEmpty) {
    sections.add(_ResultSection('Results', remaining));
  }
  return sections;
}

class _AlbumDetailView extends StatelessWidget {
  const _AlbumDetailView({
    required this.detail,
    required this.resolvingItemId,
    required this.failedItemId,
    required this.onBack,
    required this.onPlay,
    required this.onQueue,
    required this.onPrefetch,
  });

  final AlbumDetail detail;
  final String? resolvingItemId;
  final String? failedItemId;
  final VoidCallback onBack;
  final ValueChanged<DiscoverItem> onPlay;
  final ValueChanged<DiscoverItem> onQueue;
  final ValueChanged<DiscoverItem> onPrefetch;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _DetailHero(
          title: detail.title,
          subtitle: [
            detail.artistLabel,
            if (detail.year != null && detail.year!.isNotEmpty) detail.year!,
          ].join(' - '),
          artworkUrl: detail.artworkUrl,
          icon: Icons.album,
          onBack: onBack,
        ),
        const SizedBox(height: 18),
        const _SectionTitle('Tracks'),
        for (final item in detail.tracks)
          ResultTile(
            item: item,
            resolving: resolvingItemId == item.id,
            failed: failedItemId == item.id,
            onPlay: () => onPlay(item),
            onQueue: () => onQueue(item),
            onPrefetch: () => onPrefetch(item),
          ),
      ],
    );
  }
}

class _ArtistDetailView extends StatelessWidget {
  const _ArtistDetailView({
    required this.detail,
    required this.resolvingItemId,
    required this.failedItemId,
    required this.onBack,
    required this.onPlay,
    required this.onQueue,
    required this.onOpen,
    required this.onPrefetch,
  });

  final ArtistDetail detail;
  final String? resolvingItemId;
  final String? failedItemId;
  final VoidCallback onBack;
  final ValueChanged<DiscoverItem> onPlay;
  final ValueChanged<DiscoverItem> onQueue;
  final ValueChanged<DiscoverItem> onOpen;
  final ValueChanged<DiscoverItem> onPrefetch;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _DetailHero(
          title: detail.name,
          subtitle: 'Artist',
          artworkUrl: detail.artworkUrl,
          icon: Icons.person,
          onBack: onBack,
        ),
        const SizedBox(height: 18),
        for (final section in detail.sections) ...[
          _SectionTitle(section.label),
          for (final item in section.items)
            ResultTile(
              item: item,
              resolving: resolvingItemId == item.id,
              failed: failedItemId == item.id,
              onPlay: () => onPlay(item),
              onQueue: () => onQueue(item),
              onOpen: () => onOpen(item),
              onPrefetch: () => onPrefetch(item),
            ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _DetailHero extends StatelessWidget {
  const _DetailHero({
    required this.title,
    required this.subtitle,
    required this.artworkUrl,
    required this.icon,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final String? artworkUrl;
  final IconData icon;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Back to results',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
        ),
        const SizedBox(width: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox.square(
            dimension: 116,
            child: artworkUrl == null
                ? ColoredBox(
                    color: StreamboxTheme.sage.withValues(alpha: 0.75),
                    child: Icon(icon, size: 42),
                  )
                : Image.network(
                    artworkUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => ColoredBox(
                      color: StreamboxTheme.sage.withValues(alpha: 0.75),
                      child: Icon(icon, size: 42),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: StreamboxTheme.muted,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailErrorState extends StatelessWidget {
  const _DetailErrorState({required this.message, required this.onBack});

  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to results'),
          ),
        ],
      ),
    );
  }
}

class _QueueCenter extends StatelessWidget {
  const _QueueCenter({required this.queue});

  final List<PlaybackItem> queue;

  @override
  Widget build(BuildContext context) {
    return FloatingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShellSectionHeader(
            title: 'Queue',
            subtitle: '${queue.length} tracks ready to play.',
          ),
          const SizedBox(height: 18),
          Expanded(
            child: queue.isEmpty
                ? const Center(child: Text('Queue is empty.'))
                : ListView.builder(
                    itemCount: queue.length,
                    itemBuilder: (context, index) {
                      final track = queue[index].track;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Text(
                              '${index + 1}'.padLeft(2, '0'),
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    track.artistLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: const Color(0xffe2f3ea),
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Icon(Icons.search, size: 36),
            ),
            const SizedBox(height: 14),
            Text(
              'Search a song or paste a stream URL.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Results use structured YouTube Music metadata when available.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
