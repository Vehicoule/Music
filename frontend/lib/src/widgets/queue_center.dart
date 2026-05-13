import 'package:flutter/material.dart';

import '../models.dart';
import 'shell_scaffold.dart';

class QueueCenter extends StatelessWidget {
  const QueueCenter({required this.queue});

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
