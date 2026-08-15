import 'dart:math';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/event.dart';
import '../models/gelanggang.dart';

/// Standby Screen — displayed when waiting for a match to begin.
/// Port of Nuxt's standbyScreen.vue with animated floating particles.
class StandbyScreen extends StatelessWidget {
  final Event? eventInfo;
  final Gelanggang? gelanggangInfo;

  const StandbyScreen({
    super.key,
    this.eventInfo,
    this.gelanggangInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(gradient: PusakaTheme.backgroundGradient),
      child: Stack(
        children: [
          // Ambient glow
          Positioned(
            top: MediaQuery.of(context).size.height * 0.3,
            left: MediaQuery.of(context).size.width * 0.3,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: PusakaTheme.indigo600.withValues(alpha: 0.15),
              ),
            ),
          ),

          // Floating particles
          ...List.generate(8, (i) => _FloatingParticle(index: i)),

          // Top Header
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: PusakaTheme.emerald400,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'IPSI DIGITAL MONITOR DISPLAY',
                        style: TextStyle(
                          color: PusakaTheme.slate300,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: PusakaTheme.indigo950.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: PusakaTheme.indigo700.withValues(alpha: 0.8),
                      ),
                    ),
                    child: Text(
                      'GELANGGANG ${gelanggangInfo?.kodeGelanggang ?? '-'}',
                      style: const TextStyle(
                        color: PusakaTheme.indigo300,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Center Hero Card
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: PusakaTheme.slate900.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(PusakaTheme.radius3xl),
                border: Border.all(
                  color: PusakaTheme.slate800.withValues(alpha: 0.8),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Emblem
                  _BouncingEmblem(),

                  const SizedBox(height: 24),

                  // Event Name
                  Text(
                    eventInfo?.namaEvent ?? 'KEJUARAAN PENCAK SILAT DIGITAL',
                    style: const TextStyle(
                      color: PusakaTheme.amber400,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  // Main Title
                  const Text(
                    'MOHON\nMENUNGGU',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 12),

                  Text(
                    'Pertandingan pada Gelanggang ${gelanggangInfo?.kodeGelanggang ?? '-'} akan segera dimulai',
                    style: const TextStyle(
                      color: PusakaTheme.slate300,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 20),

                  // Animated pulse bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 6,
                      width: 200,
                      child: LinearProgressIndicator(
                        backgroundColor: PusakaTheme.slate800,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            PusakaTheme.indigo500),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  const Text(
                    'STANDBY ARENA • REALTIME BROADCAST ACTIVE',
                    style: TextStyle(
                      color: PusakaTheme.slate400,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Footer
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Sistem Scoreboard Digital IPSI © 2026',
                      style: TextStyle(
                        color: PusakaTheme.slate400,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: PusakaTheme.emerald400,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'STATUS ARENA: READY',
                          style: TextStyle(
                            color: PusakaTheme.emerald400,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouncing emblem icon animation
class _BouncingEmblem extends StatefulWidget {
  @override
  State<_BouncingEmblem> createState() => _BouncingEmblemState();
}

class _BouncingEmblemState extends State<_BouncingEmblem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
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
        return Transform.translate(
          offset: Offset(0, -6 * _controller.value),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [PusakaTheme.indigo600, PusakaTheme.amber500],
              ),
              boxShadow: [
                BoxShadow(
                  color: PusakaTheme.indigo500.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(2),
            child: Container(
              decoration: BoxDecoration(
                color: PusakaTheme.slate950,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.shield,
                color: PusakaTheme.amber400,
                size: 28,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Floating animated particle for background effect
class _FloatingParticle extends StatefulWidget {
  final int index;
  const _FloatingParticle({required this.index});

  @override
  State<_FloatingParticle> createState() => _FloatingParticleState();
}

class _FloatingParticleState extends State<_FloatingParticle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late double _leftPercent;
  late double _size;
  late Duration _duration;

  @override
  void initState() {
    super.initState();
    final rng = Random(widget.index);
    _leftPercent = rng.nextDouble();
    _size = 15.0 + rng.nextDouble() * 80;
    _duration = Duration(seconds: 12 + rng.nextInt(20));

    _controller = AnimationController(
      vsync: this,
      duration: _duration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        final y = screenSize.height * (1 - progress * 1.5);
        return Positioned(
          left: screenSize.width * _leftPercent,
          top: y,
          child: Opacity(
            opacity: (0.8 - progress * 0.8).clamp(0.0, 0.8),
            child: Transform.rotate(
              angle: progress * 12.56, // 4π rotation
              child: Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: PusakaTheme.indigo500.withValues(alpha: 0.15),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
