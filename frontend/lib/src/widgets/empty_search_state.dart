import 'package:flutter/material.dart';

import '../theme.dart';

class EmptySearchState extends StatelessWidget {
  const EmptySearchState();

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
