import 'package:flutter/material.dart';

import '../theme.dart';

class DetailHero extends StatelessWidget {
  const DetailHero({
    required this.title,
    required this.subtitle,
    required this.artworkUrl,
    required this.icon,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final String? artworkUrl;
  final IconData icon;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Back to results',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
        ),
        const SizedBox(width: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox.square(
            dimension: 116,
            child: artworkUrl == null
                ? ColoredBox(
                    color: StreamboxTheme.sage.withValues(alpha: 0.75),
                    child: Icon(icon, size: 42),
                  )
                : Image.network(
                    artworkUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => ColoredBox(
                      color: StreamboxTheme.sage.withValues(alpha: 0.75),
                      child: Icon(icon, size: 42),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: StreamboxTheme.muted,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
