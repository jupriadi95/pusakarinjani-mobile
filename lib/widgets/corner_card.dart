import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/peserta.dart';

/// Corner Card — displays athlete info for Sudut Merah or Sudut Biru.
/// Used in operator and monitor screens.
class CornerCard extends StatelessWidget {
  final Peserta? atlit;
  final bool isRed;
  final Widget? actionArea; // For KP buttons or score buttons
  final Widget? scoreDisplay; // For large score display in monitor

  const CornerCard({
    super.key,
    this.atlit,
    this.isRed = false,
    this.actionArea,
    this.scoreDisplay,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = isRed ? PusakaTheme.rose600 : PusakaTheme.blue600;
    final accentLight = isRed ? PusakaTheme.rose400 : PusakaTheme.blue400;
    final bgTint = isRed
        ? PusakaTheme.rose950.withValues(alpha: 0.3)
        : PusakaTheme.blue950.withValues(alpha: 0.3);
    final borderColor = isRed
        ? PusakaTheme.red900.withValues(alpha: 0.5)
        : PusakaTheme.blue900.withValues(alpha: 0.5);
    final cornerLabel = isRed ? 'Sudut Merah' : 'Sudut Biru';
    final atletLabel = isRed ? 'PESERTA 2' : 'PESERTA 1';

    return Container(
      decoration: BoxDecoration(
        color: PusakaTheme.slate900.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(PusakaTheme.radius2xl),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Corner Header
          Container(
            padding: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: borderColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentColor,
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      cornerLabel,
                      style: TextStyle(
                        color: accentLight,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isRed ? PusakaTheme.rose950 : PusakaTheme.blue950),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color:
                          (isRed ? PusakaTheme.rose800 : PusakaTheme.blue800),
                    ),
                  ),
                  child: Text(
                    atletLabel,
                    style: TextStyle(
                      color: accentLight,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Athlete Info Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgTint,
              borderRadius: BorderRadius.circular(PusakaTheme.radiusLg),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  atlit?.namaLengkap ?? 'Belum Ditentukan',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (atlit?.kontingen != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    atlit!.kontingen!,
                    style: TextStyle(
                      color: accentLight.withValues(alpha: 0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Score Display (for monitor)
          if (scoreDisplay != null) ...[
            const SizedBox(height: 12),
            scoreDisplay!,
          ],

          // Action Area (KP buttons or score buttons)
          if (actionArea != null) ...[
            const SizedBox(height: 12),
            actionArea!,
          ],
        ],
      ),
    );
  }
}
