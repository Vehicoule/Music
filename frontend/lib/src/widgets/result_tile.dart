import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

class ResultTile extends StatelessWidget {
  const ResultTile({
    super.key,
    required this.item,
    required this.resolving,
    required this.failed,
    required this.onPlay,
    required this.onQueue,
    this.onOpen,
    this.onPrefetch,
    this.topMatch = false,
  });

  final DiscoverItem item;
  final bool resolving;
  final bool failed;
  final VoidCallback onPlay;
  final VoidCallback onQueue;
  final VoidCallback? onOpen;
  final VoidCallback? onPrefetch;
  final bool topMatch;

  @override
  Widget build(BuildContext context) {
    final playable = item.isPlayable;
    final openable = !playable && onOpen != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        onEnter: (_) => onPrefetch?.call(),
        child: Material(
          color: Colors.white.withValues(alpha: topMatch ? 0.74 : 0.48),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: resolving
                ? null
                : playable
                    ? onPlay
                    : onOpen,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: topMatch
                      ? StreamboxTheme.mint.withValues(alpha: 0.9)
                      : StreamboxTheme.outline,
                ),
              ),
              child: Row(
                children: [
                  _Artwork(
                    url: item.artworkUrl,
                    playable: playable,
                    kind: item.kind,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: StreamboxTheme.text,
                                  ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.displaySubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: StreamboxTheme.muted,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _Badge(label: _sourceLabel),
                  const SizedBox(width: 6),
                  _Badge(label: _statusLabel),
                  if (openable) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Open',
                      onPressed: onOpen,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                  if (playable) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Add to queue',
                      onPressed: resolving ? null : onQueue,
                      icon: const Icon(Icons.playlist_add),
                    ),
                    IconButton.filled(
                      tooltip:
                          item.source != null ? 'Play' : 'Resolve and play',
                      onPressed: resolving ? null : onPlay,
                      icon: resolving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _statusLabel {
    if (resolving) {
      return 'Resolving';
    }
    if (failed) {
      return 'Failed';
    }
    if (item.kind == 'album') {
      return 'Album';
    }
    if (item.kind == 'artist') {
      return 'Artist';
    }
    if (item.kind == 'video') {
      return item.isPlayable ? 'Playable' : 'Video';
    }
    return item.isPlayable || topMatch ? 'Playable' : 'Metadata';
  }

  String get _sourceLabel {
    final label = item.label;
    if (label == 'YouTube Music' ||
        label == 'YouTube video' ||
        label == 'MusicBrainz') {
      return label!;
    }
    final track = item.track;
    if (track == null) {
      return label ?? 'YouTube Music';
    }
    switch (track.sourceProvider ?? track.source) {
      case 'ytmusic':
        return track.sourceKind == 'video' ? 'YouTube video' : 'YouTube Music';
      case 'youtube':
        return 'YouTube video';
      default:
        return track.source == 'musicbrainz' ? 'MusicBrainz' : track.source;
    }
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.url,
    required this.playable,
    required this.kind,
  });

  final String? url;
  final bool playable;
  final String kind;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox.square(
        dimension: 56,
        child: url == null
            ? ColoredBox(
                color: StreamboxTheme.sage.withValues(alpha: 0.75),
                child: Icon(_fallbackIcon),
              )
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: StreamboxTheme.sage.withValues(alpha: 0.75),
                  child: Icon(_fallbackIcon),
                ),
              ),
      ),
    );
  }

  IconData get _fallbackIcon {
    if (playable) {
      return Icons.play_circle;
    }
    if (kind == 'artist') {
      return Icons.person;
    }
    return Icons.album;
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: StreamboxTheme.outline),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: StreamboxTheme.text,
            ),
      ),
    );
  }
}
