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
  final bool? isLargeDisplay;

  const StandbyScreen({
    super.key,
    this.eventInfo,
    this.gelanggangInfo,
    this.isLargeDisplay,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final bool isLarge = isLargeDisplay ?? (screenSize.width >= 1000);

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(gradient: PusakaTheme.backgroundGradient),
      child: Stack(
        children: [
          // Ambient glow 1 (Center-Left)
          Positioned(
            top: screenSize.height * 0.25,
            left: screenSize.width * 0.25,
            child: Container(
              width: isLarge ? 650 : 400,
              height: isLarge ? 650 : 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: PusakaTheme.indigo600.withValues(alpha: isLarge ? 0.20 : 0.15),
              ),
            ),
          ),

          // Ambient glow 2 (Bottom-Right for large monitor display)
          if (isLarge)
            Positioned(
              bottom: 40,
              right: 60,
              child: Container(
                width: 450,
                height: 450,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: PusakaTheme.amber500.withValues(alpha: 0.10),
                ),
              ),
            ),

          // Floating particles
          ...List.generate(isLarge ? 12 : 8, (i) => _FloatingParticle(index: i)),

          // Top Header
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isLarge ? 32 : 20,
                vertical: isLarge ? 20 : 16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: isLarge ? 14 : 10,
                        height: isLarge ? 14 : 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: PusakaTheme.emerald400,
                        ),
                      ),
                      SizedBox(width: isLarge ? 14 : 10),
                      Text(
                        'IPSI DIGITAL MONITOR DISPLAY',
                        style: TextStyle(
                          color: PusakaTheme.slate300,
                          fontSize: isLarge ? 14 : 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: isLarge ? 3 : 2,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isLarge ? 20 : 14,
                      vertical: isLarge ? 8 : 6,
                    ),
                    decoration: BoxDecoration(
                      color: PusakaTheme.indigo950.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: PusakaTheme.indigo700.withValues(alpha: 0.8),
                      ),
                    ),
                    child: Text(
                      'GELANGGANG ${gelanggangInfo?.kodeGelanggang ?? '-'}',
                      style: TextStyle(
                        color: PusakaTheme.indigo300,
                        fontSize: isLarge ? 15 : 11,
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
            child: SingleChildScrollView(
              child: Container(
                constraints: BoxConstraints(maxWidth: isLarge ? 780 : 500),
                margin: EdgeInsets.symmetric(
                  horizontal: isLarge ? 32 : 24,
                  vertical: 16,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: isLarge ? 48 : 32,
                  vertical: isLarge ? 36 : 28,
                ),
                decoration: BoxDecoration(
                  color: PusakaTheme.slate900.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(
                    isLarge ? 32 : PusakaTheme.radius3xl,
                  ),
                  border: Border.all(
                    color: PusakaTheme.slate800.withValues(alpha: 0.9),
                    width: isLarge ? 1.5 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: isLarge ? 50 : 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Bouncing IPSI Logo Emblem
                    _BouncingEmblem(isLarge: isLarge),

                    SizedBox(height: isLarge ? 24 : 20),

                    // Event Name
                    Text(
                      eventInfo?.namaEvent?.toUpperCase() ??
                          'KEJUARAAN PENCAK SILAT DIGITAL',
                      style: TextStyle(
                        color: PusakaTheme.amber400,
                        fontSize: isLarge ? 17 : 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: isLarge ? 2.5 : 2,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    SizedBox(height: isLarge ? 10 : 8),

                    // Main Title
                    Text(
                      'MOHON\nMENUNGGU',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isLarge ? 52 : 36,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                        letterSpacing: isLarge ? -0.8 : -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    SizedBox(height: isLarge ? 14 : 10),

                    Text(
                      'Pertandingan pada Gelanggang ${gelanggangInfo?.kodeGelanggang ?? '-'} akan segera dimulai',
                      style: TextStyle(
                        color: PusakaTheme.slate300,
                        fontSize: isLarge ? 17 : 13,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    SizedBox(height: isLarge ? 24 : 18),

                    // Animated pulse bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: isLarge ? 8 : 6,
                        width: isLarge ? 300 : 200,
                        child: LinearProgressIndicator(
                          backgroundColor: PusakaTheme.slate800,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            PusakaTheme.indigo500,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: isLarge ? 18 : 14),

                    Text(
                      'STANDBY ARENA • REALTIME BROADCAST ACTIVE',
                      style: TextStyle(
                        color: PusakaTheme.slate400,
                        fontSize: isLarge ? 12 : 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: isLarge ? 2.0 : 1.5,
                      ),
                    ),
                  ],
                ),
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
                padding: EdgeInsets.symmetric(
                  horizontal: isLarge ? 32 : 20,
                  vertical: isLarge ? 20 : 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Sistem Scoreboard Digital IPSI © 2026',
                      style: TextStyle(
                        color: PusakaTheme.slate400,
                        fontSize: isLarge ? 13 : 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: isLarge ? 9 : 6,
                          height: isLarge ? 9 : 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: PusakaTheme.emerald400,
                          ),
                        ),
                        SizedBox(width: isLarge ? 8 : 6),
                        Text(
                          'STATUS ARENA: READY',
                          style: TextStyle(
                            color: PusakaTheme.emerald400,
                            fontSize: isLarge ? 13 : 10,
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

/// Bouncing emblem icon animation with IPSI logo
class _BouncingEmblem extends StatefulWidget {
  final bool isLarge;
  const _BouncingEmblem({this.isLarge = false});

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
    final double size = widget.isLarge ? 115.0 : 72.0;
    final double radius = widget.isLarge ? 32.0 : 22.0;
    final double innerRadius = widget.isLarge ? 30.0 : 20.0;
    final double padding = widget.isLarge ? 14.0 : 8.0;
    final double bounce = widget.isLarge ? -8.0 : -6.0;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, bounce * _controller.value),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [PusakaTheme.indigo600, PusakaTheme.amber500],
              ),
              boxShadow: [
                BoxShadow(
                  color: PusakaTheme.indigo500.withValues(alpha: 0.35),
                  blurRadius: widget.isLarge ? 24 : 18,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            padding: const EdgeInsets.all(2.5),
            child: Container(
              decoration: BoxDecoration(
                color: PusakaTheme.slate950,
                borderRadius: BorderRadius.circular(innerRadius),
              ),
              padding: EdgeInsets.all(padding),
              child: Image.asset(
                'assets/img/logo_ipsi.webp',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.sports_kabaddi,
                  color: PusakaTheme.amber400,
                  size: widget.isLarge ? 48 : 32,
                ),
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final screenHeight = MediaQuery.of(context).size.height;
        final screenWidth = MediaQuery.of(context).size.width;
        final progress = _controller.value;
        final top = screenHeight * (1.0 - progress);
        final left = screenWidth * _leftPercent + sin(progress * 2 * pi) * 20;
        final opacity = sin(progress * pi) * 0.25;

        return Positioned(
          top: top,
          left: left,
          child: Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: PusakaTheme.indigo500.withValues(alpha: opacity),
            ),
          ),
        );
      },
    );
  }
}
