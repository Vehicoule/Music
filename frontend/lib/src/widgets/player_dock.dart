import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'glass_pane.dart';

class PlayerDock extends StatelessWidget {
  const PlayerDock({
    super.key,
    required this.current,
    required this.playing,
    required this.position,
    required this.duration,
    required this.queueCount,
    required this.shuffle,
    required this.repeat,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onSeek,
    required this.onShuffle,
    required this.onRepeat,
    required this.onFavorite,
    required this.onSaveQueue,
    this.playbackError,
  });

  final PlaybackItem? current;
  final bool playing;
  final Duration position;
  final Duration duration;
  final int queueCount;
  final bool shuffle;
  final bool repeat;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onShuffle;
  final VoidCallback onRepeat;
  final VoidCallback onFavorite;
  final VoidCallback onSaveQueue;
  final String? playbackError;

  @override
  Widget build(BuildContext context) {
    final track = current?.track;
    final artwork = track?.artworkUrl ?? track?.album?.artworkUrl;
    final effectiveDuration =
        duration.inMilliseconds <= 0 ? const Duration(seconds: 1) : duration;
    final effectivePosition =
        position > effectiveDuration ? effectiveDuration : position;

    return GlassPane(
      radius: 26,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      color: Colors.white.withValues(alpha: 0.72),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(_format(effectivePosition),
                  style: Theme.of(context).textTheme.labelSmall),
              Expanded(
                child: Slider(
                  value: effectivePosition.inMilliseconds.toDouble(),
                  max: effectiveDuration.inMilliseconds.toDouble(),
                  onChanged: track == null
                      ? null
                      : (value) {
                          onSeek(Duration(milliseconds: value.round()));
                        },
                ),
              ),
              Text(_format(effectiveDuration),
                  style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
          Row(
            children: [
              _DockArtwork(url: artwork),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track?.title ?? 'Nothing playing',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track?.artistLabel ?? 'Search or paste a stream URL',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: StreamboxTheme.muted,
                          ),
                    ),
                    if (playbackError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        playbackError!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: StreamboxTheme.warning,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _QueuePill(count: queueCount),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Previous',
                onPressed: onPrevious,
                icon: const Icon(Icons.skip_previous),
              ),
              IconButton.filled(
                tooltip: playing ? 'Pause' : 'Play',
                onPressed: track == null ? null : onPlayPause,
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              ),
              IconButton(
                tooltip: 'Next',
                onPressed: onNext,
                icon: const Icon(Icons.skip_next),
              ),
              IconButton(
                tooltip: 'Shuffle',
                isSelected: shuffle,
                onPressed: onShuffle,
                icon: const Icon(Icons.shuffle),
              ),
              IconButton(
                tooltip: 'Repeat',
                isSelected: repeat,
                onPressed: onRepeat,
                icon: const Icon(Icons.repeat),
              ),
              IconButton(
                tooltip: 'Favorite',
                onPressed: track == null ? null : onFavorite,
                icon: const Icon(Icons.favorite_border),
              ),
              IconButton(
                tooltip: 'Save queue',
                onPressed: queueCount == 0 ? null : onSaveQueue,
                icon: const Icon(Icons.playlist_add_check),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString();
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _DockArtwork extends StatelessWidget {
  const _DockArtwork({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox.square(
        dimension: 58,
        child: url == null
            ? ColoredBox(
                color: StreamboxTheme.peach.withValues(alpha: 0.78),
                child: const Icon(Icons.music_note),
              )
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: StreamboxTheme.peach.withValues(alpha: 0.78),
                  child: const Icon(Icons.music_note),
                ),
              ),
      ),
    );
  }
}

class _QueuePill extends StatelessWidget {
  const _QueuePill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 84),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: StreamboxTheme.sage.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StreamboxTheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.queue_music, size: 16),
          const SizedBox(width: 6),
          Text(
            '$count queued',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}
