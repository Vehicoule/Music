import 'package:flutter/material.dart';

import '../theme.dart';

class SearchHeader extends StatelessWidget {
  const SearchHeader({
    super.key,
    required this.controller,
    required this.loading,
    required this.status,
    required this.lastQuery,
    required this.onSearch,
    required this.onTestAudio,
    required this.selectedScope,
    required this.onScopeChanged,
    this.searchError,
    this.runtimeWarning,
  });

  final TextEditingController controller;
  final bool loading;
  final String status;
  final String lastQuery;
  final VoidCallback onSearch;
  final VoidCallback onTestAudio;
  final String selectedScope;
  final ValueChanged<String> onScopeChanged;
  final String? searchError;
  final String? runtimeWarning;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search songs, artists, albums, or paste a URL',
                  isDense: true,
                ),
                onSubmitted: (_) => onSearch(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: loading ? null : onSearch,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward),
              label: const Text('Search'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final scope in _scopes)
              ChoiceChip(
                selected: selectedScope == scope.id,
                avatar: Icon(scope.icon, size: 16),
                label: Text(scope.label),
                onSelected: loading
                    ? null
                    : (_) {
                        onScopeChanged(scope.id);
                      },
              ),
            _StatusChip(icon: Icons.flash_on, label: status),
            if (lastQuery.isNotEmpty)
              _StatusChip(icon: Icons.history, label: lastQuery),
            ActionChip(
              avatar: const Icon(Icons.hearing, size: 16),
              label: const Text('Test audio engine'),
              onPressed: onTestAudio,
            ),
          ],
        ),
        if (searchError != null) ...[
          const SizedBox(height: 10),
          InlineMessage(icon: Icons.search_off, message: searchError!),
        ],
        if (runtimeWarning != null) ...[
          const SizedBox(height: 10),
          InlineMessage(
            icon: Icons.sync_problem,
            message: runtimeWarning!,
            destructive: false,
          ),
        ],
      ],
    );
  }
}

class _Scope {
  const _Scope(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}

const _scopes = [
  _Scope('all', 'All', Icons.search),
  _Scope('songs', 'Songs', Icons.music_note),
  _Scope('albums', 'Albums', Icons.album),
  _Scope('artists', 'Artists', Icons.person),
  _Scope('videos', 'Videos', Icons.slow_motion_video),
];

class InlineMessage extends StatelessWidget {
  const InlineMessage({
    super.key,
    required this.icon,
    required this.message,
    this.destructive = true,
  });

  final IconData icon;
  final String message;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? StreamboxTheme.warning : StreamboxTheme.muted;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StreamboxTheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
