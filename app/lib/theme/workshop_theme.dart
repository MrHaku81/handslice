import 'package:flutter/material.dart';

// Design "Werkstatt" (Variante A). Zentrale Tokens, nicht in den Widgets
// verstreut. Siehe docs/architecture.md Abschnitt "UI-Stack: Flutter".
class WorkshopTokens {
  WorkshopTokens._();

  // Flaechen
  static const Color background = Color(0xFF111317);
  static const Color surface = Color(0xFF1B1F25);
  static const Color border = Color(0xFF2E343D);

  // Text
  static const Color text = Color(0xFFE8EAED);
  static const Color textMuted = Color(0xFF9AA3AE);

  // Akzent
  static const Color accent = Color(0xFFFF8A1F);
  static const Color onAccent = Color(0xFF111317);

  // Radien + Tap-Target
  static const double radiusSmall = 6;
  static const double radiusMedium = 8;
  static const double minTapTarget = 44;

  // Fokus-Ring (sichtbar fuer D-Pad / Tab)
  static BoxDecoration focusRing() => BoxDecoration(
        border: Border.all(color: accent, width: 2),
        borderRadius: BorderRadius.circular(radiusMedium),
      );
}

ThemeData buildWorkshopTheme() {
  final base = ThemeData.dark(useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: WorkshopTokens.background,
    canvasColor: WorkshopTokens.background,
    colorScheme: const ColorScheme.dark(
      brightness: Brightness.dark,
      surface: WorkshopTokens.surface,
      onSurface: WorkshopTokens.text,
      primary: WorkshopTokens.accent,
      onPrimary: WorkshopTokens.onAccent,
      secondary: WorkshopTokens.accent,
      onSecondary: WorkshopTokens.onAccent,
      error: Color(0xFFFF6B6B),
      onError: WorkshopTokens.onAccent,
    ),
    textTheme: _buildTextTheme(base.textTheme).apply(fontFamily: 'IBMPlexSans'),
    cardTheme: CardThemeData(
      color: WorkshopTokens.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: WorkshopTokens.border),
        borderRadius: BorderRadius.circular(WorkshopTokens.radiusMedium),
      ),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: WorkshopTokens.background,
      foregroundColor: WorkshopTokens.text,
      elevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: WorkshopTokens.surface,
      indicatorColor: WorkshopTokens.accent.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontFamily: 'IBMPlexSans',
          fontSize: 12,
          fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          color: selected ? WorkshopTokens.accent : WorkshopTokens.textMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? WorkshopTokens.accent : WorkshopTokens.textMuted,
          size: 24,
        );
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: WorkshopTokens.accent,
        foregroundColor: WorkshopTokens.onAccent,
        minimumSize: const Size(WorkshopTokens.minTapTarget * 2, WorkshopTokens.minTapTarget),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WorkshopTokens.radiusMedium),
        ),
        textStyle: const TextStyle(
          fontFamily: 'IBMPlexSans',
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: WorkshopTokens.text,
        side: const BorderSide(color: WorkshopTokens.border),
        minimumSize: const Size(WorkshopTokens.minTapTarget * 2, WorkshopTokens.minTapTarget),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WorkshopTokens.radiusMedium),
        ),
        textStyle: const TextStyle(
          fontFamily: 'IBMPlexSans',
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: WorkshopTokens.accent,
        minimumSize: const Size(WorkshopTokens.minTapTarget, WorkshopTokens.minTapTarget),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: WorkshopTokens.border,
      thickness: 1,
      space: 1,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? WorkshopTokens.onAccent : WorkshopTokens.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? WorkshopTokens.accent : WorkshopTokens.border),
      trackOutlineColor: WidgetStateProperty.all(WorkshopTokens.border),
    ),
    // Globaler Fokus-Highlight. Jedes bedienbare Widget bekommt den Ring,
    // ohne dass einzelne Widgets ihn selbst setzen muessen.
    focusColor: WorkshopTokens.accent.withValues(alpha: 0.18),
    highlightColor: WorkshopTokens.accent.withValues(alpha: 0.10),
    splashColor: WorkshopTokens.accent.withValues(alpha: 0.10),
  );
}

TextTheme _buildTextTheme(TextTheme base) {
  const sans = 'IBMPlexSans';
  return base.copyWith(
    displayLarge: base.displayLarge?.copyWith(fontFamily: sans, color: WorkshopTokens.text),
    headlineMedium: base.headlineMedium?.copyWith(
      fontFamily: sans,
      color: WorkshopTokens.text,
      fontWeight: FontWeight.w700,
      fontSize: 24,
    ),
    titleLarge: base.titleLarge?.copyWith(
      fontFamily: sans,
      color: WorkshopTokens.text,
      fontWeight: FontWeight.w500,
      fontSize: 18,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontFamily: sans,
      color: WorkshopTokens.text,
      fontWeight: FontWeight.w500,
      fontSize: 16,
    ),
    bodyLarge: base.bodyLarge?.copyWith(fontFamily: sans, color: WorkshopTokens.text, fontSize: 15),
    bodyMedium: base.bodyMedium?.copyWith(fontFamily: sans, color: WorkshopTokens.text, fontSize: 14),
    bodySmall: base.bodySmall?.copyWith(fontFamily: sans, color: WorkshopTokens.textMuted, fontSize: 12),
    labelLarge: base.labelLarge?.copyWith(
      fontFamily: sans,
      color: WorkshopTokens.text,
      fontWeight: FontWeight.w500,
      fontSize: 14,
    ),
  );
}

// Mono-Variante nur fuer Zahlen/Werte. Nicht ins TextTheme eingebrannt;
// explizit beim Benutzen durch monoStyle(context) holen.
TextStyle monoStyle(BuildContext context, {double fontSize = 14, FontWeight? fontWeight, Color? color}) {
  return TextStyle(
    fontFamily: 'IBMPlexMono',
    fontSize: fontSize,
    fontWeight: fontWeight ?? FontWeight.w400,
    color: color ?? WorkshopTokens.text,
    height: 1.25,
  );
}

// Fokus-sichtbarer Wrapper. Zieht einen Rahmen um das Kind, wenn das
// umgebende Focus-Node Fokus hat. Spart Boilerplate in jedem Widget.
class FocusVisible extends StatelessWidget {
  const FocusVisible({super.key, required this.child, this.padding = const EdgeInsets.all(2)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        final focused = Focus.of(context).hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: padding,
          decoration: BoxDecoration(
            border: Border.all(
              color: focused ? WorkshopTokens.accent : Colors.transparent,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(WorkshopTokens.radiusMedium),
          ),
          child: child,
        );
      },
    );
  }
}
