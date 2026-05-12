import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../core/core_client.dart';
import '../models.dart';

class PlayerController extends ChangeNotifier {
  PlayerController({required this.coreClient}) {
    _subscriptions.add(player.stream.playing.listen((value) {
      playing = value;
      notifyListeners();
    }));
    _subscriptions.add(player.stream.position.listen((value) {
      position = value;
      notifyListeners();
    }));
    _subscriptions.add(player.stream.duration.listen((value) {
      duration = value;
      notifyListeners();
    }));
    _subscriptions.add(player.stream.completed.listen((completed) {
      if (completed) {
        skipNext();
      }
    }));
    _subscriptions.add(player.stream.error.listen((value) {
      final message = friendlyPlaybackError(value);
      error = message;
      playbackDiagnostics = [
        ...playbackDiagnostics,
        'player.stream.error: $message'
      ];
      notifyListeners();
    }));
  }

  final CoreClient coreClient;
  final Player player = Player();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  List<PlaybackItem> queue = [];
  PlaybackItem? current;
  bool playing = false;
  bool shuffle = false;
  bool repeat = false;
  bool resolving = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  String? error;
  List<String> playbackDiagnostics = [];

  Future<void> resolveAndPlay(TrackMetadata track, {String? sourceUrl}) async {
    error = null;
    resolving = true;
    notifyListeners();
    try {
      final result = await coreClient.resolve(track, sourceUrl: sourceUrl);
      if (result.candidates.isEmpty) {
        final detail = result.warningMessage;
        throw PlayerException(
          detail.isEmpty ? 'No playable stream was found.' : detail,
        );
      }
      await playWithCandidates(track, result.candidates);
    } catch (exception) {
      error = friendlyPlaybackError(exception);
      notifyListeners();
    } finally {
      resolving = false;
      notifyListeners();
    }
  }

  Future<void> playItem(PlaybackItem item) async {
    final source = item.source;
    if (source == null) {
      error = 'This queue item has no playable source.';
      notifyListeners();
      throw const PlayerException('This queue item has no playable source.');
    }
    try {
      await player.open(Media(source.url, httpHeaders: source.headers),
          play: true);
      current = item;
      if (!queue.any((queued) => queued.id == item.id)) {
        queue = [item, ...queue];
      }
      error = null;
      unawaited(coreClient.addHistory(item));
      notifyListeners();
    } catch (exception, stackTrace) {
      final message = friendlyPlaybackError(exception);
      error = message;
      playbackDiagnostics = [
        ...playbackDiagnostics,
        'open failed: ${source.title} (${source.adapter}) -> $message',
        stackTrace.toString().split('\n').take(4).join('\n'),
      ];
      notifyListeners();
      throw PlayerException(message);
    }
  }

  Future<void> playWithCandidates(
    TrackMetadata track,
    List<SourceCandidate> candidates,
  ) async {
    Object? lastError;
    for (final candidate in candidates) {
      try {
        await playItem(PlaybackItem.fromTrack(track, candidate));
        error = null;
        notifyListeners();
        return;
      } catch (exception) {
        lastError = exception;
        playbackDiagnostics = [
          ...playbackDiagnostics,
          'candidate failed: ${candidate.title} (${candidate.adapter}) -> $exception',
        ];
      }
    }
    throw PlayerException(
      lastError == null
          ? 'No playable stream was found.'
          : 'All stream candidates failed. Last error: $lastError',
    );
  }

  void enqueue(PlaybackItem item) {
    queue = [...queue, item];
    notifyListeners();
  }

  Future<void> testAudioEngine() async {
    const track = TrackMetadata(
      id: 'diagnostic-audio-engine',
      title: 'Audio engine test',
      artists: [ArtistMetadata(name: 'Streambox diagnostics')],
      source: 'diagnostic',
    );
    const source = SourceCandidate(
      adapter: 'direct_url',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
      title: 'Direct MP3 audio test',
      mimeType: 'audio/mpeg',
    );
    await playItem(PlaybackItem.fromTrack(track, source));
  }

  String? checkAudioRuntime() {
    if (!Platform.isWindows) {
      return null;
    }
    final cwd = File(Platform.resolvedExecutable).parent;
    final candidates = [
      File('${cwd.path}${Platform.pathSeparator}libmpv-2.dll'),
      File(
          '${cwd.path}${Platform.pathSeparator}media_kit_libs_windows_audio_plugin.dll'),
    ];
    final missing = candidates.where((file) => !file.existsSync()).map((file) {
      return file.uri.pathSegments.last;
    }).toList();
    if (missing.isEmpty) {
      return null;
    }
    return 'Windows audio backend files are missing from the app folder: ${missing.join(', ')}.';
  }

  Future<void> resolveAndEnqueue(TrackMetadata track,
      {String? sourceUrl}) async {
    error = null;
    resolving = true;
    notifyListeners();
    try {
      final result = await coreClient.resolve(track, sourceUrl: sourceUrl);
      if (result.candidates.isEmpty) {
        final detail = result.warningMessage;
        throw PlayerException(
          detail.isEmpty ? 'No playable stream was found.' : detail,
        );
      }
      enqueue(PlaybackItem.fromTrack(track, result.candidates.first));
    } catch (exception) {
      error = friendlyPlaybackError(exception);
      notifyListeners();
    } finally {
      resolving = false;
      notifyListeners();
    }
  }

  Future<void> togglePlay() async {
    if (playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> seek(Duration value) async {
    await player.seek(value);
  }

  Future<void> skipNext() async {
    if (queue.isEmpty) {
      if (repeat && current != null) {
        await playItem(current!);
      }
      return;
    }
    final currentIndex = current == null
        ? -1
        : queue.indexWhere((item) => item.id == current!.id);
    final nextIndex = currentIndex + 1;
    if (nextIndex >= 0 && nextIndex < queue.length) {
      await playItem(queue[nextIndex]);
    } else if (repeat && queue.isNotEmpty) {
      await playItem(queue.first);
    }
  }

  Future<void> skipPrevious() async {
    if (queue.isEmpty || current == null) {
      return;
    }
    final currentIndex = queue.indexWhere((item) => item.id == current!.id);
    final previousIndex = currentIndex - 1;
    if (previousIndex >= 0) {
      await playItem(queue[previousIndex]);
    }
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    if (shuffle) {
      queue = [...queue]..shuffle();
    }
    notifyListeners();
  }

  void toggleRepeat() {
    repeat = !repeat;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(player.dispose());
    super.dispose();
  }
}

String friendlyPlaybackError(Object exception) {
  final text = exception.toString();
  if (exception is UnimplementedError ||
      text.contains('NotImplementedError') ||
      text.contains('UnimplementedError')) {
    return 'Audio backend is not initialized or native libmpv files are missing. Rebuild/restart the Windows app, then run Test audio engine.';
  }
  return text;
}

class PlayerException implements Exception {
  const PlayerException(this.message);

  final String message;

  @override
  String toString() => message;
}
