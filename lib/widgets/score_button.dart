import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Score Button — Touch-optimized scoring buttons for juri.
/// Port of Nuxt's formnilai.vue component.
class ScoreButton extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final List<Color> gradientColors;
  final bool enabled;
  final VoidCallback? onTap;

  const ScoreButton({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.gradientColors,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: gradientColors,
            ),
            borderRadius: BorderRadius.circular(PusakaTheme.radiusLg),
            border: Border.all(
              color: gradientColors.first.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: gradientColors.first.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Badge +value
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    '+$value',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),

              // Center content
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 28, color: Colors.white),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
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

/// Standard scoring buttons configuration
class ScoreButtons {
  static const pukulan = (
    label: 'PUKULAN',
    value: 1,
    icon: Icons.sports_mma,
    colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
  );

  static const tendangan = (
    label: 'TENDANGAN',
    value: 2,
    icon: Icons.sports_martial_arts,
    colors: [Color(0xFF10B981), Color(0xFF0D9488)],
  );

  static const jatuhan = (
    label: 'JATUHAN',
    value: 3,
    icon: Icons.arrow_circle_down,
    colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
  );

  /// Returns the standard scoring buttons in order.
  /// For red corner, the order is reversed for right-thumb ergonomics.
  static List<
      ({String label, int value, IconData icon, List<Color> colors})> getButtons(
      {bool reversed = false}) {
    final buttons = [pukulan, tendangan, jatuhan];
    if (reversed) return buttons.reversed.toList();
    return buttons;
  }
}
