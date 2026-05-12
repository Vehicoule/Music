import 'package:flutter/material.dart';

import '../theme.dart';
import 'glass_pane.dart';
import 'library_section.dart';
import 'sidebar.dart';

export 'library_section.dart';

class ShellScaffold extends StatelessWidget {
  const ShellScaffold({
    super.key,
    required this.selectedSection,
    required this.queueCount,
    required this.onSectionSelected,
    required this.center,
    required this.nowPlayingPanel,
    required this.playerDock,
  });

  final LibrarySection selectedSection;
  final int queueCount;
  final ValueChanged<LibrarySection> onSectionSelected;
  final Widget center;
  final Widget nowPlayingPanel;
  final Widget playerDock;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xfffbf5ed),
              Color(0xffedf7ef),
              Color(0xfff5effa),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showSidebar = constraints.maxWidth >= 760;
              final showNowPlaying = constraints.maxWidth >= 720;
              return Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showSidebar) ...[
                            SizedBox(
                              width: 214,
                              child: Sidebar(
                                selected: selectedSection,
                                queueCount: queueCount,
                                onSelected: onSectionSelected,
                              ),
                            ),
                            const SizedBox(width: 14),
                          ],
                          Expanded(child: center),
                          if (showNowPlaying) ...[
                            const SizedBox(width: 14),
                            SizedBox(
                              width: constraints.maxWidth >= 1180 ? 340 : 300,
                              child: nowPlayingPanel,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: playerDock,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class ShellSectionHeader extends StatelessWidget {
  const ShellSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: StreamboxTheme.text,
                    ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: StreamboxTheme.muted,
                      ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class FloatingPanel extends StatelessWidget {
  const FloatingPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return GlassPane(
      padding: padding,
      color: Colors.white.withValues(alpha: 0.62),
      child: child,
    );
  }
}
