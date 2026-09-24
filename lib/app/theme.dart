import 'package:flutter/material.dart';

/// Colors used throughout the app (dark, GitKraken-like).
abstract final class AppColors {
  static const background = Color(0xFF1B1D23);
  static const panel = Color(0xFF22252C);
  static const panelAlt = Color(0xFF282C34);
  static const toolbar = Color(0xFF2B2F38);
  static const border = Color(0xFF363B45);
  static const hover = Color(0xFF2F343E);
  static const selection = Color(0xFF34404F);
  static const text = Color(0xFFD7DAE0);
  static const textDim = Color(0xFF8B93A1);
  static const textFaint = Color(0xFF5E6573);
  static const accent = Color(0xFF15A0BF);
  static const danger = Color(0xFFE5534B);
  static const warning = Color(0xFFE0A33A);
  static const success = Color(0xFF57AB5A);

  static const diffAddBg = Color(0xFF1E3A2A);
  static const diffAddText = Color(0xFF8CD69B);
  static const diffDelBg = Color(0xFF45232A);
  static const diffDelText = Color(0xFFF0959B);
  static const diffHunkBg = Color(0xFF263041);
  static const diffSelected = Color(0xFF3B4E6E);

  static const localBranch = Color(0xFF15A0BF);
  static const remoteBranch = Color(0xFF7C62D6);
  static const tag = Color(0xFFD4A13A);

  /// Lane palette.
  static const lanes = [
    Color(0xFF15A0BF),
    Color(0xFF0669F7),
    Color(0xFF8E00C2),
    Color(0xFFC517B6),
    Color(0xFFD90171),
    Color(0xFFCD0101),
    Color(0xFFF25D2E),
    Color(0xFFF2CA33),
    Color(0xFF7BD938),
    Color(0xFF2ECE9D),
  ];

  static Color lane(int i) => lanes[i % lanes.length];
}

const monoFont = 'monospace';
const monoFallback = ['Menlo', 'DejaVu Sans Mono', 'Consolas', 'Courier New'];

TextStyle monoStyle({double size = 12.5, Color color = AppColors.text}) =>
    TextStyle(
      fontFamily: monoFont,
      fontFamilyFallback: monoFallback,
      fontSize: size,
      color: color,
      height: 1.35,
    );

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.accent,
      surface: AppColors.panel,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.background,
    visualDensity: VisualDensity.compact,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    dividerColor: AppColors.border,
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
      textStyle: TextStyle(fontSize: 12, color: AppColors.text),
      decoration: BoxDecoration(
        color: AppColors.toolbar,
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.panelAlt,
      textStyle: TextStyle(fontSize: 13, color: AppColors.text),
    ),
    menuTheme: const MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.panelAlt),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: AppColors.background,
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.accent),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.18)),
      thickness: const WidgetStatePropertyAll(8),
      radius: const Radius.circular(4),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.panelAlt,
      contentTextStyle: TextStyle(color: AppColors.text, fontSize: 12.5),
      actionTextColor: AppColors.accent,
      closeIconColor: AppColors.textDim,
      behavior: SnackBarBehavior.floating,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
  );
}
