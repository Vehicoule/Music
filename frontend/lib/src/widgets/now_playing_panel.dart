import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'diagnostics_panel.dart';
import 'glass_pane.dart';

class NowPlayingPanel extends StatelessWidget {
  const NowPlayingPanel({
    super.key,
    required this.current,
    required this.queue,
    required this.playbackError,
    required this.diagnostics,
  });

  final PlaybackItem? current;
  final List<PlaybackItem> queue;
  final String? playbackError;
  final List<String> diagnostics;

  @override
  Widget build(BuildContext context) {
    final track = current?.track;
    final artwork = track?.artworkUrl ?? track?.album?.artworkUrl;
    return GlassPane(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Now playing',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 14),
          _HeroArtwork(url: artwork),
          const SizedBox(height: 14),
          Text(
            track?.title ?? 'Nothing playing',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            track?.artistLabel ?? 'Choose a song from search.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: StreamboxTheme.muted,
                ),
          ),
          if (playbackError != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: StreamboxTheme.peach.withValues(alpha: 0.52),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: StreamboxTheme.warning.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                playbackError!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: StreamboxTheme.warning,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'Up next',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: queue.isEmpty
                ? Text(
                    'Queue is empty.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: StreamboxTheme.muted,
                        ),
                  )
                : ListView.builder(
                    itemCount: queue.take(6).length,
                    itemBuilder: (context, index) {
                      final item = queue[index].track;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.music_note, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          DiagnosticsPanel(diagnostics: diagnostics),
        ],
      ),
    );
  }
}

class _HeroArtwork extends StatelessWidget {
  const _HeroArtwork({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth < 260 ? constraints.maxWidth : 260.0;
        return Center(
          child: SizedBox.square(
            dimension: side,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      StreamboxTheme.peach,
                      StreamboxTheme.sage,
                      StreamboxTheme.lavender,
                    ],
                  ),
                  border: Border.all(color: StreamboxTheme.outline),
                ),
                child: url == null
                    ? const Center(child: Icon(Icons.music_note, size: 56))
                    : Image.network(
                        url!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.music_note, size: 56)),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
