import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'src/api_client.dart';
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

  const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
  const useRustLocalLibrary = bool.fromEnvironment(
    'USE_RUST_LOCAL_LIBRARY',
    defaultValue: false,
  );

  final apiClient = ApiClient(baseUrl: apiBaseUrl);
  final nativeCore = FfiNativeCore();
  final coreClient = HybridCoreClient(
    apiClient: apiClient,
    nativeCore: nativeCore,
    rustCoreClient: RustCoreClient(
      nativeCore: nativeCore,
      fallbackApiClient: apiClient,
    ),
    routingConfig: const CoreClientRoutingConfig(
      useRustLocalLibrary: useRustLocalLibrary,
    ),
  );

  runApp(StreamboxApp(coreClient: coreClient));
}

class StreamboxApp extends StatefulWidget {
  const StreamboxApp({super.key, required this.coreClient});

  final CoreClient coreClient;

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
      ),
    );
  }
}
