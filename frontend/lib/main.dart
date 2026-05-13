import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'src/audio/player_controller.dart';
import 'src/core/core_client.dart';
import 'src/core/rust_core_client.dart';
import 'src/desktop_window.dart';
import 'src/native/native_core.dart';
import 'src/screens/home_screen.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await initializeDesktopWindow();

  final nativeCore = FfiNativeCore();
  final coreClient = RustCoreClient(
    nativeCore: nativeCore,
  );

  runApp(StreamboxApp(
    coreClient: coreClient,
    nativeCore: nativeCore,
  ));
}

class StreamboxApp extends StatefulWidget {
  const StreamboxApp({
    super.key,
    required this.coreClient,
    required this.nativeCore,
  });

  final CoreClient coreClient;
  final NativeCore nativeCore;

  @override
  State<StreamboxApp> createState() => _StreamboxAppState();
}

class _StreamboxAppState extends State<StreamboxApp> {
  late final PlayerController playerController;

  @override
  void initState() {
    super.initState();
    playerController = PlayerController(coreClient: widget.coreClient);
  }

  @override
  void dispose() {
    playerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Streambox',
      debugShowCheckedModeBanner: false,
      theme: StreamboxTheme.light(),
      home: HomeScreen(
        coreClient: widget.coreClient,
        playerController: playerController,
        nativeCore: widget.nativeCore,
      ),
    );
  }
}
