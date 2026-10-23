import 'package:flutter/material.dart';

import 'app_theme.dart';

class ModulePalette {
  const ModulePalette(this.accent, this.background, this.end);
  final Color accent;
  final Color background;
  final Color end;

  static ModulePalette forIndex(int index) => switch (index) {
    2 => const ModulePalette(
      Color(0xFF3E6582),
      Color(0xFFEDF2F5),
      Color(0xFFF5F8F9),
    ),
    3 => const ModulePalette(
      Color(0xFF59677E),
      Color(0xFFF0F1F5),
      Color(0xFFF7F8FA),
    ),
    4 => const ModulePalette(
      Color(0xFF276D65),
      Color(0xFFEDF3F1),
      Color(0xFFF5F9F7),
    ),
    5 => const ModulePalette(
      Color(0xFF4B6680),
      Color(0xFFEEF2F5),
      Color(0xFFF6F8FA),
    ),
    6 => const ModulePalette(
      Color(0xFF826A43),
      Color(0xFFF3F1ED),
      Color(0xFFFAF9F6),
    ),
    7 => const ModulePalette(
      Color(0xFF68627C),
      Color(0xFFF1EFF4),
      Color(0xFFF9F7FA),
    ),
    8 => const ModulePalette(
      Color(0xFF246B70),
      Color(0xFFEDF3F3),
      Color(0xFFF6F9F9),
    ),
    9 => const ModulePalette(
      Color(0xFF46715D),
      Color(0xFFEFF3EF),
      Color(0xFFF7FAF7),
    ),
    _ => const ModulePalette(
      Color(0xFF526775),
      AppColors.bg,
      AppColors.surface,
    ),
  };

  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [background, end],
  );
}

/// Each list owns its controller; the overview opts out of visible scrollbars.
class CleanScrollBehavior extends MaterialScrollBehavior {
  const CleanScrollBehavior({this.showScrollbars = true});
  final bool showScrollbars;
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => showScrollbars
      ? Scrollbar(
          controller: details.controller,
          thumbVisibility: true,
          interactive: true,
          child: child,
        )
      : child;
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
    final line = Color.lerp(accent, Colors.white, .8)!;
    final soft = Color.lerp(accent, Colors.white, .93)!;
    final scheme = base.colorScheme.copyWith(
      primary: accent,
      onPrimary: Colors.white,
      primaryContainer: soft,
      onPrimaryContainer: AppColors.textPrimary,
      secondary: accent,
      surface: Colors.white,
      outlineVariant: line,
    );
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 140);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    Color foreground(Set<WidgetState> states) =>
        states.contains(WidgetState.disabled) ? AppColors.textTertiary : accent;
    Color overlay(Set<WidgetState> states) => accent.withValues(
      alpha: states.contains(WidgetState.pressed) ? .12 : .06,
    );
    BorderSide controlBorder(Set<WidgetState> states) => BorderSide(
      width: states.contains(WidgetState.focused) ? 2 : 1.2,
      color: states.contains(WidgetState.focused) ? accent : Colors.transparent,
    );
    final theme = base.copyWith(
      colorScheme: scheme,
      hoverColor: accent.withValues(alpha: .04),
      focusColor: accent.withValues(alpha: .12),
      splashColor: accent.withValues(alpha: .1),
      iconTheme: base.iconTheme.copyWith(color: accent),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: (base.elevatedButtonTheme.style ?? const ButtonStyle()).copyWith(
          animationDuration: duration,
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? const Color(0xFFE5EBED)
                : accent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppColors.textTertiary
                : Colors.white,
          ),
          overlayColor: WidgetStatePropertyAll(
            Colors.white.withValues(alpha: .12),
          ),
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: (base.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
          animationDuration: duration,
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? const Color(0xFFE5EBED)
                : accent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppColors.textTertiary
                : Colors.white,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: (base.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
          animationDuration: duration,
          backgroundColor: WidgetStatePropertyAll(soft),
          foregroundColor: WidgetStateProperty.resolveWith(foreground),
          overlayColor: WidgetStateProperty.resolveWith(overlay),
          side: WidgetStateProperty.resolveWith(controlBorder),
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
        style: (base.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
          animationDuration: duration,
          foregroundColor: WidgetStateProperty.resolveWith(foreground),
          overlayColor: WidgetStateProperty.resolveWith(overlay),
          shape: WidgetStatePropertyAll(shape),
          side: WidgetStateProperty.resolveWith(controlBorder),
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: line, width: 1.2),
        ),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        selectedTileColor: soft,
        selectedColor: AppColors.textPrimary,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        prefixIconColor: accent,
        suffixIconColor: accent,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: line, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent, width: 2),
        ),
      ),
      checkboxTheme: base.checkboxTheme.copyWith(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? accent : Colors.white,
        ),
      ),
      switchTheme: base.switchTheme.copyWith(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : const Color(0xFF8A9AA3),
        ),
      ),
      progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
        color: accent,
        linearTrackColor: soft,
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: line),
        ),
      ),
      expansionTileTheme: base.expansionTileTheme.copyWith(
        expansionAnimationStyle: AnimationStyle(
          duration: duration,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
    return Theme(
      data: theme,
      child: PrimaryScrollController.none(
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: palette.gradient),
          child: child,
        ),
      ),
    );
  }
}
