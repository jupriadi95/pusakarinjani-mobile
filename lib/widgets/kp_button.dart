import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/peserta.dart';

/// KP Button — Operator's penalty/bonus control buttons.
/// Port of Nuxt's kpButton.vue component.
/// Buttons: Binaan (-1), Teguran (-2), Peringatan (-3), Jatuhan (+4)
class KpButton extends StatelessWidget {
  final Peserta? atlit;
  final bool isRed; // true for red corner, false for blue
  final Future<void> Function(int nilai)? onPushNilai;

  const KpButton({
    super.key,
    this.atlit,
    this.isRed = false,
    this.onPushNilai,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor =
        isRed ? PusakaTheme.rose800 : PusakaTheme.blue800;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 6,
      mainAxisSpacing: 6,
      childAspectRatio: 2.2,
      children: [
        _KpActionButton(
          label: 'Binaan',
          icon: Icons.pan_tool_alt,
          nilai: -1,
          borderColor: borderColor,
          enabled: atlit?.documentId != null,
          onTap: () => onPushNilai?.call(-1),
        ),
        _KpActionButton(
          label: 'Teguran',
          icon: Icons.warning_amber_rounded,
          nilai: -2,
          borderColor: borderColor,
          enabled: atlit?.documentId != null,
          onTap: () => onPushNilai?.call(-2),
        ),
        _KpActionButton(
          label: 'Peringatan',
          icon: Icons.back_hand,
          nilai: -3,
          borderColor: borderColor,
          enabled: atlit?.documentId != null,
          onTap: () => onPushNilai?.call(-3),
        ),
        _KpActionButton(
          label: 'Jatuhan',
          icon: Icons.sports_martial_arts,
          nilai: 4,
          borderColor: borderColor,
          isPositive: true,
          enabled: atlit?.documentId != null,
          onTap: () => onPushNilai?.call(4),
        ),
      ],
    );
  }
}

class _KpActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final int nilai;
  final Color borderColor;
  final bool isPositive;
  final bool enabled;
  final VoidCallback? onTap;

  const _KpActionButton({
    required this.label,
    required this.icon,
    required this.nilai,
    required this.borderColor,
    this.isPositive = false,
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
            color: PusakaTheme.slate900,
            borderRadius: BorderRadius.circular(PusakaTheme.radiusMd),
            border: Border.all(color: borderColor.withValues(alpha: 0.5)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: isPositive ? PusakaTheme.emerald400 : PusakaTheme.slate400,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: isPositive ? PusakaTheme.emerald400 : PusakaTheme.slate300,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
