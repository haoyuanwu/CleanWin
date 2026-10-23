import 'package:flutter/material.dart';

/// Shared mineral palette. The overview keeps its own dark orbital surfaces.
class AppColors {
  static const primary = Color(0xFF246B70);
  static const primaryDark = Color(0xFF174E53);
  static const primarySoft = Color(0xFFE1EFF0);
  static const accent = Color(0xFF516B83);
  static const success = Color(0xFF28755C);
  static const successSoft = Color(0xFFE4F1E9);
  static const warning = Color(0xFF986423);
  static const warningSoft = Color(0xFFF7EDDC);
  static const danger = Color(0xFFB64850);
  static const dangerSoft = Color(0xFFF8E8E9);
  static const bg = Color(0xFFF0F3F4);
  static const surface = Color(0xFFF8FAFA);
  static const glass = Color(0xF2FFFFFF);
  static const glassBorder = Color(0xFFE0E7E9);
  static const textPrimary = Color(0xFF172D38);
  static const textSecondary = Color(0xFF536774);
  static const textTertiary = Color(0xFF647783);
  static const border = Color(0xFFD9E2E5);
  static const sidebar = Color(0xFF152B36);
  static const sidebarText = Color(0xFFBCCBD0);
  static const sidebarActive = Color(0xFFA6D8D6);
  static const gradientMain = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, accent],
  );
}

class AppTheme {
  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          onPrimary: Colors.white,
          secondary: AppColors.accent,
          surface: Colors.white,
          error: AppColors.danger,
        ).copyWith(
          onSurface: AppColors.textPrimary,
          onSurfaceVariant: AppColors.textSecondary,
          outline: const Color(0xFF85989F),
          outlineVariant: AppColors.border,
          primaryContainer: AppColors.primarySoft,
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      fontFamily: 'Segoe UI',
    );
    const label = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      fontFamily: 'Segoe UI',
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    final primaryButton = ElevatedButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: AppColors.primary,
      disabledForegroundColor: AppColors.textTertiary,
      disabledBackgroundColor: const Color(0xFFE5EBED),
      minimumSize: const Size(40, 40),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      elevation: 0,
      shape: shape,
      textStyle: label,
      animationDuration: const Duration(milliseconds: 140),
    );
    OutlineInputBorder inputBorder(Color color, [double width = 1.2]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: width),
        );
    return base.copyWith(
      hoverColor: AppColors.primary.withValues(alpha: .05),
      focusColor: AppColors.primary.withValues(alpha: .12),
      textTheme: base.textTheme
          .apply(
            bodyColor: AppColors.textPrimary,
            displayColor: AppColors.textPrimary,
          )
          .copyWith(
            titleLarge: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -.5,
            ),
            titleMedium: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            titleSmall: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            bodyLarge: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.textPrimary,
            ),
            bodyMedium: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
            bodySmall: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.textTertiary,
            ),
            labelLarge: label,
          )
          .apply(fontFamily: 'Segoe UI'),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        space: 1,
        thickness: .8,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: primaryButton),
      filledButtonTheme: FilledButtonThemeData(style: primaryButton),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              disabledForegroundColor: AppColors.textTertiary,
              backgroundColor: AppColors.primarySoft,
              minimumSize: const Size(40, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              side: BorderSide.none,
              shape: shape,
              textStyle: label,
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => BorderSide(
                  color: states.contains(WidgetState.focused)
                      ? AppColors.primary
                      : Colors.transparent,
                  width: states.contains(WidgetState.focused) ? 2 : 1.2,
                ),
              ),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(40, 40),
          shape: shape,
          textStyle: label,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppColors.textTertiary
                : AppColors.textSecondary,
          ),
          minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
          shape: WidgetStatePropertyAll(shape),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.focused)
                  ? AppColors.primary
                  : Colors.transparent,
              width: states.contains(WidgetState.focused) ? 2 : 1.2,
            ),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        selectedColor: AppColors.textPrimary,
        selectedTileColor: AppColors.primarySoft.withValues(alpha: .6),
        minVerticalPadding: 10,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : Colors.white,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: const BorderSide(color: Color(0xFF85989F), width: 1.4),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : const Color(0xFF8A9AA3),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
        border: inputBorder(AppColors.border),
        enabledBorder: inputBorder(AppColors.border),
        focusedBorder: inputBorder(AppColors.primary, 2),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primarySoft,
        labelStyle: const TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: AppColors.sidebar.withValues(alpha: .15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.sidebar,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.border),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: 'Segoe UI',
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'Segoe UI',
          fontSize: 13,
          height: 1.6,
          color: AppColors.textSecondary,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.primarySoft,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.dragged)
              ? 8
              : 6,
        ),
        radius: const Radius.circular(8),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => AppColors.textSecondary.withValues(
            alpha: states.contains(WidgetState.dragged)
                ? .75
                : states.contains(WidgetState.hovered)
                ? .55
                : .32,
          ),
        ),
        crossAxisMargin: 3,
        mainAxisMargin: 8,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        decoration: BoxDecoration(
          color: AppColors.sidebar,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
