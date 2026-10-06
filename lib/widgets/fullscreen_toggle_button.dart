import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../config/theme.dart';

/// Floating & reusable Fullscreen Toggle Button for Desktop platforms (Windows, macOS, Linux).
/// Automatically hides on Mobile / Web platforms.
class FullscreenToggleButton extends StatefulWidget {
  final EdgeInsets? padding;
  final bool compact;

  const FullscreenToggleButton({
    super.key,
    this.padding,
    this.compact = false,
  });

  @override
  State<FullscreenToggleButton> createState() => _FullscreenToggleButtonState();
}

class _FullscreenToggleButtonState extends State<FullscreenToggleButton>
    with WindowListener {
  bool _isFullScreen = false;
  bool _isHovered = false;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      windowManager.addListener(this);
      _checkFullscreenState();
    }
  }

  @override
  void dispose() {
    if (_isDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _checkFullscreenState() async {
    try {
      final isFull = await windowManager.isFullScreen();
      if (mounted) {
        setState(() {
          _isFullScreen = isFull;
        });
      }
    } catch (_) {}
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _isFullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _isFullScreen = false);
  }

  bool _isToggling = false;

  Future<void> _toggleFullscreen() async {
    if (!_isDesktop || _isToggling) return;
    _isToggling = true;
    try {
      final isFull = await windowManager.isFullScreen();
      if (isFull) {
        // Exiting fullscreen mode
        await windowManager.setFullScreen(false);
        // Explicitly restore standard window decorations
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);

        // Ensure window has normal, visible, centered bounds (preventing 0x0 collapse on Windows)
        await windowManager.setSize(const Size(1280, 720));
        await windowManager.center();

        // Reactivate window and bring to foreground so mouse & keyboard clicks are immediately responsive
        await windowManager.show();
        await windowManager.focus();
      } else {
        // Entering fullscreen mode
        await windowManager.setFullScreen(true);
      }

      final currentFull = await windowManager.isFullScreen();
      if (mounted) {
        setState(() {
          _isFullScreen = currentFull;
        });
      }
    } catch (e) {
      debugPrint('Error toggling fullscreen: $e');
    } finally {
      _isToggling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) {
      return const SizedBox.shrink();
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.f11): _toggleFullscreen,
      },
      child: Focus(
        autofocus: false,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _isHovered ? 1.0 : 0.75,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _toggleFullscreen,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: widget.padding ??
                      (widget.compact
                          ? const EdgeInsets.all(8)
                          : const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6)),
                  decoration: BoxDecoration(
                    color: _isHovered
                        ? PusakaTheme.slate800.withValues(alpha: 0.9)
                        : PusakaTheme.slate900.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isHovered
                          ? PusakaTheme.indigo500.withValues(alpha: 0.6)
                          : PusakaTheme.slate700.withValues(alpha: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isFullScreen
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        color: _isFullScreen
                            ? PusakaTheme.amber400
                            : PusakaTheme.indigo400,
                        size: 20,
                      ),
                      if (!widget.compact) ...[
                        const SizedBox(width: 6),
                        Text(
                          _isFullScreen ? 'Keluar Fullscreen' : 'Fullscreen',
                          style: TextStyle(
                            color: _isFullScreen
                                ? PusakaTheme.amber400
                                : PusakaTheme.slate300,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: PusakaTheme.slate800,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: PusakaTheme.slate700,
                              width: 0.8,
                            ),
                          ),
                          child: const Text(
                            'F11',
                            style: TextStyle(
                              color: PusakaTheme.slate400,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
