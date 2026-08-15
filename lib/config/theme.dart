import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Pusaka App Theme — Dark IPSI Digital Console Theme
/// Consistent with the Nuxt web app's dark gradient design system.
class PusakaTheme {
  PusakaTheme._();

  // ── Color Palette ──
  static const Color slate950 = Color(0xFF020617);
  static const Color slate900 = Color(0xFF0F172A);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate300 = Color(0xFFCBD5E1);

  static const Color indigo950 = Color(0xFF1E1B4B);
  static const Color indigo700 = Color(0xFF4338CA);
  static const Color indigo600 = Color(0xFF4F46E5);
  static const Color indigo500 = Color(0xFF6366F1);
  static const Color indigo400 = Color(0xFF818CF8);
  static const Color indigo300 = Color(0xFFA5B4FC);

  static const Color amber400 = Color(0xFFFBBF24);
  static const Color amber500 = Color(0xFFF59E0B);

  static const Color emerald400 = Color(0xFF34D399);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald950 = Color(0xFF022C22);

  static const Color rose400 = Color(0xFFFB7185);
  static const Color rose500 = Color(0xFFF43F5E);
  static const Color rose600 = Color(0xFFE11D48);
  static const Color rose800 = Color(0xFF9F1239);
  static const Color rose950 = Color(0xFF4C0519);

  static const Color red600 = Color(0xFFDC2626);
  static const Color red900 = Color(0xFF7F1D1D);

  static const Color blue400 = Color(0xFF60A5FA);
  static const Color blue500 = Color(0xFF3B82F6);
  static const Color blue600 = Color(0xFF2563EB);
  static const Color blue800 = Color(0xFF1E40AF);
  static const Color blue900 = Color(0xFF1E3A5F);
  static const Color blue950 = Color(0xFF172554);

  static const Color teal500 = Color(0xFF14B8A6);
  static const Color teal600 = Color(0xFF0D9488);

  static const Color purple500 = Color(0xFF8B5CF6);
  static const Color purple600 = Color(0xFF7C3AED);
  static const Color purple950 = Color(0xFF3B0764);

  // ── Gradients ──
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [slate950, slate900, indigo950],
  );

  static const LinearGradient emeraldGradient = LinearGradient(
    colors: [emerald600, teal600],
  );

  static const LinearGradient roseGradient = LinearGradient(
    colors: [rose600, red600],
  );

  static const LinearGradient indigoGradient = LinearGradient(
    colors: [indigo600, blue600],
  );

  static const LinearGradient amberGradient = LinearGradient(
    colors: [amber500, Color(0xFFCA8A04)],
  );

  // ── Border Radius ──
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;
  static const double radius2xl = 24.0;
  static const double radius3xl = 28.0;

  // ── Card Decoration ──
  static BoxDecoration cardDecoration({
    Color borderColor = const Color(0x33334155),
    double borderRadius = radius2xl,
  }) {
    return BoxDecoration(
      color: slate900.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: borderColor, width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  /// Red corner card decoration
  static BoxDecoration redCornerDecoration() {
    return cardDecoration(borderColor: red900.withValues(alpha: 0.5));
  }

  /// Blue corner card decoration
  static BoxDecoration blueCornerDecoration() {
    return cardDecoration(borderColor: blue900.withValues(alpha: 0.5));
  }

  // ── ThemeData ──
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: slate950,
      primaryColor: indigo600,
      colorScheme: const ColorScheme.dark(
        primary: indigo600,
        secondary: amber400,
        surface: slate900,
        error: rose600,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(
        ThemeData.dark().textTheme,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: indigo600,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: slate950,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: slate700),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: slate700),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: indigo500),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: const TextStyle(color: slate400, fontSize: 12),
      ),
    );
  }
}
