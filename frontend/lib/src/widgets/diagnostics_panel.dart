import 'package:flutter/material.dart';

import '../theme.dart';

class DiagnosticsPanel extends StatelessWidget {
  const DiagnosticsPanel({
    super.key,
    required this.diagnostics,
  });

  final List<String> diagnostics;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Text(
        'Diagnostics',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
      children: [
        if (diagnostics.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'No playback diagnostics yet.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: StreamboxTheme.muted,
                  ),
            ),
          )
        else
          for (final item in diagnostics.take(8))
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  item,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: StreamboxTheme.muted,
                    fontFeatures: const [],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
