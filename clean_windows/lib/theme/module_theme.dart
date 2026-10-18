import 'package:flutter/material.dart';

import 'app_theme.dart';

class ModulePalette {
  const ModulePalette(this.accent, this.background, this.end);
  final Color accent;
  final Color background;
  final Color end;

  static ModulePalette forIndex(int index) => switch (index) {
    2 => const ModulePalette(
      Color(0xFF2563EB),
      Color(0xFFE7F0FC),
      Color(0xFFF3F7FE),
    ),
    3 => const ModulePalette(
      Color(0xFF7C3AED),
      Color(0xFFEFE7FA),
      Color(0xFFF8F4FE),
    ),
    4 => const ModulePalette(
      Color(0xFF008574),
      Color(0xFFE0F2EA),
      Color(0xFFF1FAF5),
    ),
    5 => const ModulePalette(
      Color(0xFF4668D8),
      Color(0xFFE8EEFA),
      Color(0xFFF4F7FD),
    ),
    6 => const ModulePalette(
      Color(0xFFA96112),
      Color(0xFFF8ECD7),
      Color(0xFFFEF9EF),
    ),
    7 => const ModulePalette(
      Color(0xFF7050B4),
      Color(0xFFEDE6F6),
      Color(0xFFF8F4FD),
    ),
    8 => const ModulePalette(
      Color(0xFF087C93),
      Color(0xFFDFF0F3),
      Color(0xFFF0F9FB),
    ),
    9 => const ModulePalette(
      Color(0xFF367D4E),
      Color(0xFFE3F0E1),
      Color(0xFFF3F9F0),
    ),
    _ => const ModulePalette(
      Color(0xFF52647C),
      Color(0xFFE5EBF3),
      Color(0xFFF3F6FA),
    ),
  };

  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [background, end],
  );
}

/// Native scrolling remains enabled, including menus and horizontal lists.
class CleanScrollBehavior extends MaterialScrollBehavior {
  const CleanScrollBehavior();
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

class ModuleSurface extends StatelessWidget {
  const ModuleSurface({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = ModulePalette.forIndex(index);
    final base = Theme.of(context);
    final accent = palette.accent;
    final line = Color.lerp(accent, Colors.white, .68)!;
    final soft = Color.lerp(accent, Colors.white, .93)!;
    final scheme = base.colorScheme.copyWith(
      primary: accent,
      onPrimary: Colors.white,
      primaryContainer: soft,
      secondary: accent,
      surface: Color.lerp(palette.end, Colors.white, .8),
      outlineVariant: line,
    );
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    Color foreground(Set<WidgetState> states) =>
        states.contains(WidgetState.disabled) ? AppColors.textTertiary : accent;
    Color overlay(Set<WidgetState> states) => accent.withValues(
      alpha: states.contains(WidgetState.pressed) ? .14 : .07,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    final theme = base.copyWith(
      colorScheme: scheme,
      hoverColor: accent.withValues(alpha: .05),
      focusColor: accent.withValues(alpha: .1),
      splashColor: accent.withValues(alpha: .12),
      iconTheme: base.iconTheme.copyWith(color: accent),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: (base.elevatedButtonTheme.style ?? const ButtonStyle()).copyWith(
          animationDuration: duration,
          shape: WidgetStatePropertyAll(shape),
          minimumSize: const WidgetStatePropertyAll(Size(40, 42)),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return Color.lerp(palette.background, Colors.white, .35);
            }
            return states.contains(WidgetState.pressed)
                ? Color.lerp(accent, Colors.black, .12)
                : accent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppColors.textTertiary
                : Colors.white,
          ),
          overlayColor: WidgetStatePropertyAll(
            Colors.white.withValues(alpha: .12),
          ),
          elevation: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.hovered) &&
                    !states.contains(WidgetState.disabled)
                ? 3
                : 0,
          ),
          shadowColor: WidgetStatePropertyAll(accent.withValues(alpha: .25)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: (base.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
          animationDuration: duration,
          shape: WidgetStatePropertyAll(shape),
          minimumSize: const WidgetStatePropertyAll(Size(40, 42)),
          foregroundColor: WidgetStateProperty.resolveWith(foreground),
          backgroundColor: WidgetStatePropertyAll(
            Colors.white.withValues(alpha: .65),
          ),
          overlayColor: WidgetStateProperty.resolveWith(overlay),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              width: 1.6,
              color: states.contains(WidgetState.focused) ? accent : line,
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: (base.textButtonTheme.style ?? const ButtonStyle()).copyWith(
          animationDuration: duration,
          foregroundColor: WidgetStateProperty.resolveWith(foreground),
          overlayColor: WidgetStateProperty.resolveWith(overlay),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          animationDuration: duration,
          foregroundColor: WidgetStateProperty.resolveWith(foreground),
          overlayColor: WidgetStateProperty.resolveWith(overlay),
          shape: WidgetStatePropertyAll(shape),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              width: 1.6,
              color: states.contains(WidgetState.focused) ? accent : line,
            ),
          ),
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: Colors.white.withValues(alpha: .88),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: line, width: 1.6),
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: Colors.white.withValues(alpha: .85),
        prefixIconColor: accent,
        suffixIconColor: accent,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: line, width: 1.6),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 2),
        ),
      ),
      checkboxTheme: base.checkboxTheme.copyWith(
        side: BorderSide(color: line, width: 1.6),
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? accent : Colors.white,
        ),
      ),
      switchTheme: base.switchTheme.copyWith(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : AppColors.textTertiary.withValues(alpha: .35),
        ),
      ),
      progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
        color: accent,
        linearTrackColor: soft,
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: line, width: 1.6),
        ),
      ),
      expansionTileTheme: base.expansionTileTheme.copyWith(
        expansionAnimationStyle: AnimationStyle(
          duration: duration,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
    return Theme(
      data: theme,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: palette.gradient),
        child: child,
      ),
    );
  }
}
