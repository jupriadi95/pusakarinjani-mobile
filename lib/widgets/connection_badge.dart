import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Connection Badge — shows WebSocket connection status.
/// Equivalent to the connection badge in Nuxt juri/monitor pages.
class ConnectionBadge extends StatelessWidget {
  final bool isConnected;
  final bool compact;

  const ConnectionBadge({
    super.key,
    required this.isConnected,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: isConnected
            ? PusakaTheme.emerald950.withValues(alpha: 0.8)
            : PusakaTheme.rose950.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isConnected
              ? PusakaTheme.emerald400.withValues(alpha: 0.5)
              : PusakaTheme.rose400.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated pulse dot
          _PulseDot(isConnected: isConnected),
          const SizedBox(width: 6),
          Text(
            isConnected
                ? (compact ? 'LIVE' : 'REALTIME CONNECTED')
                : 'DISCONNECTED',
            style: TextStyle(
              color: isConnected
                  ? PusakaTheme.emerald400
                  : PusakaTheme.rose400,
              fontSize: compact ? 9 : 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final bool isConnected;
  const _PulseDot({required this.isConnected});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.isConnected) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isConnected && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isConnected && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.isConnected
                ? PusakaTheme.emerald400
                    .withValues(alpha: 0.6 + (_controller.value * 0.4))
                : PusakaTheme.rose500,
            boxShadow: widget.isConnected
                ? [
                    BoxShadow(
                      color: PusakaTheme.emerald400
                          .withValues(alpha: _controller.value * 0.6),
                      blurRadius: 6,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}
