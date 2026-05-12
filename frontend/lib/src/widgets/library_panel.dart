import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'glass_pane.dart';

class LibraryPanel extends StatelessWidget {
  const LibraryPanel({
    super.key,
    required this.playlists,
    required this.favorites,
    required this.history,
    required this.loading,
  });

  final List<Playlist> playlists;
  final List<Favorite> favorites;
  final List<PlaybackItem> history;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GlassPane(
      padding: const EdgeInsets.all(18),
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _LibrarySection(
                  title: 'Playlists',
                  empty: 'Save the queue to create a playlist.',
                  children: [
                    for (final playlist in playlists.take(6))
                      _LibraryRow(
                        icon: Icons.library_music,
                        title: playlist.name,
                        subtitle: '${playlist.tracks.length} tracks',
                      ),
                  ],
                ),
                _LibrarySection(
                  title: 'Favorites',
                  empty: 'Favorite the current track to keep it here.',
                  children: [
                    for (final favorite in favorites.take(6))
                      _LibraryRow(
                        icon: Icons.favorite_border,
                        title: favorite.item.track.title,
                        subtitle: favorite.item.track.artistLabel,
                      ),
                  ],
                ),
                _LibrarySection(
                  title: 'Recent',
                  empty: 'Played tracks will appear here.',
                  children: [
                    for (final item in history.take(8))
                      _LibraryRow(
                        icon: Icons.history,
                        title: item.track.title,
                        subtitle: item.track.artistLabel,
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _LibrarySection extends StatelessWidget {
  const _LibrarySection({
    required this.title,
    required this.empty,
    required this.children,
  });

  final String title;
  final String empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          if (children.isEmpty)
            Text(
              empty,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: StreamboxTheme.muted,
                  ),
            )
          else
            ...children,
        ],
      ),
    );
  }
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StreamboxTheme.outline),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: StreamboxTheme.muted,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
