import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'src/api_client.dart';
import 'src/audio/player_controller.dart';
import 'src/desktop_window.dart';
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

  runApp(StreamboxApp(apiClient: ApiClient(baseUrl: apiBaseUrl)));
}

class StreamboxApp extends StatefulWidget {
  const StreamboxApp({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<StreamboxApp> createState() => _StreamboxAppState();
}

class _StreamboxAppState extends State<StreamboxApp> {
  late final PlayerController playerController;

  @override
  void initState() {
    super.initState();
    playerController = PlayerController(apiClient: widget.apiClient);
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
        apiClient: widget.apiClient,
        playerController: playerController,
      ),
    );
  }
}
