import 'dart:async';
import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Timer Widget — Countdown timer for match rounds.
/// Port of Nuxt's timer.vue component.
class TimerWidget extends StatefulWidget {
  final int initialSeconds;
  final bool countdownMode;
  final bool autoStart;
  final bool hideControls;
  final VoidCallback? onFinished;

  const TimerWidget({
    super.key,
    this.initialSeconds = 120,
    this.countdownMode = true,
    this.autoStart = true,
    this.hideControls = true,
    this.onFinished,
  });

  @override
  State<TimerWidget> createState() => TimerWidgetState();
}

class TimerWidgetState extends State<TimerWidget> {
  late int _seconds;
  bool _isActive = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _seconds = widget.initialSeconds;
    if (widget.autoStart) {
      start();
    }
  }

  String get formattedTime {
    final mins = (_seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  void start() {
    if (_isActive) return;
    setState(() => _isActive = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        if (widget.countdownMode) {
          if (_seconds > 0) {
            _seconds--;
          } else {
            pause();
            widget.onFinished?.call();
          }
        } else {
          _seconds++;
        }
      });
    });
  }

  void pause() {
    _isActive = false;
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() {});
  }

  void reset() {
    pause();
    setState(() => _seconds = widget.initialSeconds);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Digital Timer Display
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: PusakaTheme.slate950.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(PusakaTheme.radiusLg),
            border: Border.all(
              color: PusakaTheme.slate800.withValues(alpha: 0.8),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isActive)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: PusakaTheme.emerald400,
                    boxShadow: [
                      BoxShadow(
                        color: PusakaTheme.emerald400.withValues(alpha: 0.6),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              Text(
                formattedTime,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  letterSpacing: 4,
                  color: PusakaTheme.amber400,
                  shadows: [
                    Shadow(
                      color: PusakaTheme.amber400.withValues(alpha: 0.5),
                      blurRadius: 15,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Manual Controls (hidden by default on monitor)
        if (!widget.hideControls) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isActive)
                _ControlButton(
                  label: 'Mulai',
                  color: PusakaTheme.emerald600,
                  onTap: start,
                )
              else
                _ControlButton(
                  label: 'Jeda',
                  color: PusakaTheme.amber500,
                  onTap: pause,
                ),
              const SizedBox(width: 8),
              _ControlButton(
                label: 'Reset',
                color: PusakaTheme.slate700,
                onTap: reset,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
