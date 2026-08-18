import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/peserta.dart';

/// KP Button — Dewan Pertandingan penalty/bonus control buttons.
/// Actions: Binaan (0), Teguran (-1), Pembinaan (-5), Jatuhan (+3), Reset Babak
class KpButton extends StatelessWidget {
  final Peserta? atlit;
  final bool isRed; // true for red corner, false for blue
  final int binaanCount;
  final int teguranCount;
  final int pembinaanCount;
  final bool isDsq;
  final Future<void> Function(String aksi)? onAction;

  const KpButton({
    super.key,
    this.atlit,
    this.isRed = false,
    this.binaanCount = 0,
    this.teguranCount = 0,
    this.pembinaanCount = 0,
    this.isDsq = false,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isRed ? PusakaTheme.rose800 : PusakaTheme.blue800;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // KP Counter Indicators Banner
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: PusakaTheme.slate950,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDsq ? PusakaTheme.rose500 : borderColor.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildCounterPill('Binaan', binaanCount, 2, PusakaTheme.amber400),
              _buildCounterPill('Teguran', teguranCount, 2, PusakaTheme.orange400),
              _buildCounterPill('Pembinaan', pembinaanCount, 2, PusakaTheme.rose400),
              if (isDsq)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: PusakaTheme.rose600,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'DSQ',
                    style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
                  ),
                ),
            ],
          ),
        ),

        // Action Buttons Grid
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 2.3,
          children: [
            _KpActionButton(
              label: 'Binaan (0)',
              icon: Icons.pan_tool_alt,
              borderColor: borderColor,
              badgeColor: PusakaTheme.amber400,
              badgeText: 'FSM',
              enabled: atlit?.documentId != null && !isDsq,
              onTap: () => onAction?.call('binaan'),
            ),
            _KpActionButton(
              label: 'Teguran (-1)',
              icon: Icons.warning_amber_rounded,
              borderColor: borderColor,
              badgeColor: PusakaTheme.orange400,
              badgeText: '-1',
              enabled: atlit?.documentId != null && !isDsq,
              onTap: () => onAction?.call('teguran'),
            ),
            _KpActionButton(
              label: 'Pembinaan (-5)',
              icon: Icons.gavel,
              borderColor: borderColor,
              badgeColor: PusakaTheme.rose400,
              badgeText: '-5',
              enabled: atlit?.documentId != null && !isDsq,
              onTap: () => onAction?.call('pembinaan'),
            ),
            _KpActionButton(
              label: 'Jatuhan (+3)',
              icon: Icons.sports_martial_arts,
              borderColor: borderColor,
              badgeColor: PusakaTheme.emerald400,
              badgeText: '+3',
              isPositive: true,
              enabled: atlit?.documentId != null && !isDsq,
              onTap: () => onAction?.call('jatuhan'),
            ),
          ],
        ),

        const SizedBox(height: 6),

        // Reset Babak Action Button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: atlit?.documentId != null ? () => onAction?.call('reset_babak') : null,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 6),
              side: BorderSide(color: PusakaTheme.slate700.withValues(alpha: 0.6)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.restart_alt, size: 13, color: PusakaTheme.slate400),
            label: const Text(
              'Reset Counter Babak',
              style: TextStyle(color: PusakaTheme.slate400, fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCounterPill(String label, int current, int max, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(color: PusakaTheme.slate400, fontSize: 9, fontWeight: FontWeight.w600),
        ),
        Text(
          '$current/$max',
          style: TextStyle(
            color: current > 0 ? color : PusakaTheme.slate500,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _KpActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color borderColor;
  final Color badgeColor;
  final String badgeText;
  final bool isPositive;
  final bool enabled;
  final VoidCallback? onTap;

  const _KpActionButton({
    required this.label,
    required this.icon,
    required this.borderColor,
    required this.badgeColor,
    required this.badgeText,
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: isPositive ? PusakaTheme.emerald400 : PusakaTheme.slate300,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: isPositive ? PusakaTheme.emerald400 : PusakaTheme.slate200,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
