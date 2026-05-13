import 'dart:io';
import '../native/native_core.dart';
import 'newpipe_engine.dart';
import 'track_resolver.dart';
import 'yt_dlp_engine.dart';

TrackResolver createResolver(NativeCore nativeCore) {
  if (Platform.isAndroid) {
    return NewPipeEngine();
  }
  return YtDlpEngine(nativeCore: nativeCore);
}
