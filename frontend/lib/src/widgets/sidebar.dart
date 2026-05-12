import 'package:flutter/material.dart';

import '../theme.dart';
import 'glass_pane.dart';
import 'library_section.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.selected,
    required this.queueCount,
    required this.onSelected,
  });

  final LibrarySection selected;
  final int queueCount;
  final ValueChanged<LibrarySection> onSelected;

  @override
  Widget build(BuildContext context) {
    return GlassPane(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: StreamboxTheme.mint.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.graphic_eq, color: Color(0xff15362f)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Streambox',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          for (final section in LibrarySection.values)
            _SidebarButton(
              section: section,
              selected: selected == section,
              queueCount: section == LibrarySection.queue ? queueCount : null,
              onTap: () => onSelected(section),
            ),
          const Spacer(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: StreamboxTheme.lavender.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: StreamboxTheme.outline),
            ),
            child: Text(
              'YouTube Music source search with local playlists and queue.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: StreamboxTheme.muted,
                    height: 1.25,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.section,
    required this.selected,
    required this.onTap,
    this.queueCount,
  });

  final LibrarySection section;
  final bool selected;
  final VoidCallback onTap;
  final int? queueCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? Colors.white.withValues(alpha: 0.72)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(section.icon, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (queueCount != null)
                  Text(
                    queueCount.toString(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: StreamboxTheme.muted,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
