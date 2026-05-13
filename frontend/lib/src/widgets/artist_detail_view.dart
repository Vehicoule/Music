import 'package:flutter/material.dart';

import '../models.dart';
import 'detail_hero.dart';
import 'result_tile.dart';
import 'section_title.dart';

class ArtistDetailView extends StatelessWidget {
  const ArtistDetailView({
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
        DetailHero(
          title: detail.name,
          subtitle: 'Artist',
          artworkUrl: detail.artworkUrl,
          icon: Icons.person,
          onBack: onBack,
        ),
        const SizedBox(height: 18),
        for (final section in detail.sections) ...[
          SectionTitle(section.label),
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
