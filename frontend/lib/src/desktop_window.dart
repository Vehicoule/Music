import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:window_manager/window_manager.dart';

Future<void> initializeDesktopWindow() async {
  if (kIsWeb || !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    return;
  }

  try {
    await acrylic.Window.initialize();
    await acrylic.Window.setEffect(
      effect: Platform.isWindows
          ? acrylic.WindowEffect.acrylic
          : Platform.isMacOS
              ? acrylic.WindowEffect.sidebar
              : acrylic.WindowEffect.transparent,
      color: const Color(0xddf7f1ea),
    );
  } catch (_) {
    // Native window effects are cosmetic. Keep the app usable when unavailable.
  }

  try {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 820),
      minimumSize: Size(980, 680),
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.normal,
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  } catch (_) {
    // Tests and some platforms may not expose a desktop window channel.
  }
}
