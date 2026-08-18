import 'package:flutter/material.dart';

/// Score Button — Large circular touch-optimized scoring button for juri (Pukulan +1, Tendangan +2).
/// Ergonomic circular button designed for fast finger tapping in landscape mode.
class ScoreButton extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final List<Color> gradientColors;
  final bool enabled;
  final double size;
  final VoidCallback? onTap;

  const ScoreButton({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.gradientColors,
    this.enabled = true,
    this.size = 96.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.55),
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: gradientColors.first.withValues(alpha: 0.5),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // +Value Badge (Top Center)
              Positioned(
                top: 7,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 1.0,
                    ),
                  ),
                  child: Text(
                    '+$value',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),

              // Center Content (Icon + Label)
              Positioned(
                bottom: 10,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 30, color: Colors.white),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Standard scoring buttons configuration (Pukulan & Tendangan only)
class ScoreButtons {
  static const pukulan = (
    label: 'PUKULAN',
    value: 1,
    jenis: 'pukulan',
    icon: Icons.sports_mma,
    colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
  );

  static const tendangan = (
    label: 'TENDANGAN',
    value: 2,
    jenis: 'tendangan',
    icon: Icons.sports_martial_arts,
    colors: [Color(0xFF10B981), Color(0xFF0D9488)],
  );
}
