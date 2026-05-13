import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'album_detail_view.dart';
import 'artist_detail_view.dart';
import 'detail_error_state.dart';
import 'empty_search_state.dart';
import 'result_section.dart';
import 'result_tile.dart';
import 'search_header.dart';
import 'section_title.dart';
import 'shell_scaffold.dart';

class SearchCenter extends StatelessWidget {
  const SearchCenter({
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
                    ? DetailErrorState(
                        message: detailError!,
                        onBack: onBackToResults,
                      )
                    : albumDetail != null
                        ? AlbumDetailView(
                            detail: albumDetail!,
                            resolvingItemId: resolvingItemId,
                            failedItemId: failedItemId,
                            onBack: onBackToResults,
                            onPlay: onPlay,
                            onQueue: onQueue,
                            onPrefetch: onPrefetch,
                          )
                        : artistDetail != null
                            ? ArtistDetailView(
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
                                    ? const EmptySearchState()
                                    : ListView(
                                        children: [
                                          if (topPlayable != null) ...[
                                            const SectionTitle(
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
                                            const SectionTitle(
                                                'Finding top playable match'),
                                            const LinearProgressIndicator(
                                                minHeight: 2),
                                            const SizedBox(height: 14),
                                          ],
                                          if (results.isNotEmpty) ...[
                                            for (final section
                                                in groupedResults(
                                                    results)) ...[
                                              SectionTitle(section.label),
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
