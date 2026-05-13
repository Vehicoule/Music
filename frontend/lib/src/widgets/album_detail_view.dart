import 'package:flutter/material.dart';

import '../models.dart';
import 'detail_hero.dart';
import 'result_tile.dart';
import 'section_title.dart';

class AlbumDetailView extends StatelessWidget {
  const AlbumDetailView({
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
        DetailHero(
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
        const SectionTitle('Tracks'),
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
