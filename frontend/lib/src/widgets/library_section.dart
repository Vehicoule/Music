import 'package:flutter/material.dart';

enum LibrarySection {
  search('Search', Icons.search),
  queue('Queue', Icons.queue_music),
  playlists('Playlists', Icons.library_music),
  favorites('Favorites', Icons.favorite_border),
  recent('Recent', Icons.history),
  diagnostics('Diagnostics', Icons.tune);

  const LibrarySection(this.label, this.icon);

  final String label;
  final IconData icon;
}
