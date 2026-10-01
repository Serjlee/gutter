import 'package:flutter/material.dart';

/// One set of colors: the app's look, dark or light.
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.panel,
    required this.panelAlt,
    required this.toolbar,
    required this.border,
    required this.hover,
    required this.selection,
    required this.text,
    required this.textDim,
    required this.textFaint,
    required this.accent,
    required this.danger,
    required this.warning,
    required this.success,
    required this.diffAddBg,
    required this.diffAddText,
    required this.diffDelBg,
    required this.diffDelText,
    required this.diffHunkBg,
    required this.diffSelected,
    required this.localBranch,
    required this.remoteBranch,
    required this.tag,
    required this.pillText,
    required this.headRing,
    required this.trunk,
    required this.trunkRing,
    required this.scrollbarThumb,
    required this.lanes,
  });

  final Brightness brightness;
  final Color background;
  final Color panel;
  final Color panelAlt;
  final Color toolbar;
  final Color border;
  final Color hover;
  final Color selection;
  final Color text;
  final Color textDim;
  final Color textFaint;
  final Color accent;
  final Color danger;
  final Color warning;
  final Color success;
  final Color diffAddBg;
  final Color diffAddText;
  final Color diffDelBg;
  final Color diffDelText;
  final Color diffHunkBg;
  final Color diffSelected;
  final Color localBranch;
  final Color remoteBranch;
  final Color tag;

  /// Text on ref labels.
  final Color pillText;

  /// Ring around the checked-out commit's node.
  final Color headRing;

  /// main/master remotes: their label border and scroll mark.
  final Color trunk;

  /// Ring around a main/master remote's node.
  final Color trunkRing;
  final Color scrollbarThumb;

  /// Graph lane colors.
  final List<Color> lanes;

  bool get isDark => brightness == Brightness.dark;

  /// GitKraken-like dark.
  static const dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF1B1D23),
    panel: Color(0xFF22252C),
    panelAlt: Color(0xFF282C34),
    toolbar: Color(0xFF2B2F38),
    border: Color(0xFF363B45),
    hover: Color(0xFF2F343E),
    selection: Color(0xFF34404F),
    text: Color(0xFFD7DAE0),
    textDim: Color(0xFF8B93A1),
    textFaint: Color(0xFF5E6573),
    accent: Color(0xFF15A0BF),
    danger: Color(0xFFE5534B),
    warning: Color(0xFFE0A33A),
    success: Color(0xFF57AB5A),
    diffAddBg: Color(0xFF1E3A2A),
    diffAddText: Color(0xFF8CD69B),
    diffDelBg: Color(0xFF45232A),
    diffDelText: Color(0xFFF0959B),
    diffHunkBg: Color(0xFF263041),
    diffSelected: Color(0xFF3B4E6E),
    localBranch: Color(0xFF15A0BF),
    remoteBranch: Color(0xFF7C62D6),
    tag: Color(0xFFD4A13A),
    pillText: Color(0xFFFFFFFF),
    headRing: Color(0xD9FFFFFF),
    trunk: Color(0xFFD5D9E0),
    trunkRing: Color(0xFFB8BDC7),
    scrollbarThumb: Color(0x2EFFFFFF),
    lanes: [
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
    ],
  );

  /// GitHub-like light; lanes darkened where pale on white.
  static const light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFFFFFFF),
    panel: Color(0xFFF6F8FA),
    panelAlt: Color(0xFFEEF1F4),
    toolbar: Color(0xFFF0F2F5),
    border: Color(0xFFD0D7DE),
    hover: Color(0xFFEAEEF2),
    selection: Color(0xFFD5E5F5),
    text: Color(0xFF1F2328),
    textDim: Color(0xFF59636E),
    textFaint: Color(0xFF8C959F),
    accent: Color(0xFF0A7E9E),
    danger: Color(0xFFCF222E),
    warning: Color(0xFF9A6700),
    success: Color(0xFF1A7F37),
    diffAddBg: Color(0xFFDAFBE1),
    diffAddText: Color(0xFF116329),
    diffDelBg: Color(0xFFFFEBE9),
    diffDelText: Color(0xFF82071E),
    diffHunkBg: Color(0xFFDDF4FF),
    diffSelected: Color(0xFFB6E3FF),
    localBranch: Color(0xFF0A7E9E),
    remoteBranch: Color(0xFF6639BA),
    tag: Color(0xFF9A6700),
    pillText: Color(0xFF1F2328),
    headRing: Color(0xD91F2328),
    trunk: Color(0xFF6E7781),
    trunkRing: Color(0xFF8C959F),
    scrollbarThumb: Color(0x40000000),
    lanes: [
      Color(0xFF1393B4),
      Color(0xFF0969DA),
      Color(0xFF8E00C2),
      Color(0xFFC517B6),
      Color(0xFFD90171),
      Color(0xFFCD0101),
      Color(0xFFE5532A),
      Color(0xFFB88A00),
      Color(0xFF4C9A1A),
      Color(0xFF1A9E78),
    ],
  );
}

/// The active palette's colors, used throughout the app. Switching
/// [current] takes effect as widgets rebuild (the app rebuilds them all).
abstract final class AppColors {
  static AppPalette current = AppPalette.dark;

  static Color get background => current.background;
  static Color get panel => current.panel;
  static Color get panelAlt => current.panelAlt;
  static Color get toolbar => current.toolbar;
  static Color get border => current.border;
  static Color get hover => current.hover;
  static Color get selection => current.selection;
  static Color get text => current.text;
  static Color get textDim => current.textDim;
  static Color get textFaint => current.textFaint;
  static Color get accent => current.accent;
  static Color get danger => current.danger;
  static Color get warning => current.warning;
  static Color get success => current.success;
  static Color get diffAddBg => current.diffAddBg;
  static Color get diffAddText => current.diffAddText;
  static Color get diffDelBg => current.diffDelBg;
  static Color get diffDelText => current.diffDelText;
  static Color get diffHunkBg => current.diffHunkBg;
  static Color get diffSelected => current.diffSelected;
  static Color get localBranch => current.localBranch;
  static Color get remoteBranch => current.remoteBranch;
  static Color get tag => current.tag;
  static Color get pillText => current.pillText;
  static Color get headRing => current.headRing;
  static Color get trunk => current.trunk;
  static Color get trunkRing => current.trunkRing;
  static Color get scrollbarThumb => current.scrollbarThumb;

  static List<Color> get lanes => current.lanes;

  static Color lane(int i) => lanes[i % lanes.length];
}

const monoFont = 'monospace';
const monoFallback = ['Menlo', 'DejaVu Sans Mono', 'Consolas', 'Courier New'];

TextStyle monoStyle({double size = 12.5, Color? color}) => TextStyle(
  fontFamily: monoFont,
  fontFamilyFallback: monoFallback,
  fontSize: size,
  color: color ?? AppColors.text,
  height: 1.35,
);

/// The app's theme in the active palette ([AppColors.current]).
ThemeData buildTheme() {
  final dark = AppColors.current.isDark;
  final base = ThemeData(
    brightness: AppColors.current.brightness,
    useMaterial3: true,
    colorScheme: dark
        ? ColorScheme.dark(
            primary: AppColors.accent,
            secondary: AppColors.accent,
            surface: AppColors.panel,
            error: AppColors.danger,
          )
        : ColorScheme.light(
            primary: AppColors.accent,
            secondary: AppColors.accent,
            // Text on the accent (selected segments): it's dark here.
            onSecondary: Colors.white,
            surface: AppColors.panel,
            onSurface: AppColors.text,
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
    dividerTheme: DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
      textStyle: TextStyle(fontSize: 12, color: AppColors.text),
      decoration: BoxDecoration(
        color: AppColors.toolbar,
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.panelAlt,
      textStyle: TextStyle(fontSize: 13, color: AppColors.text),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.panelAlt),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
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
      thumbColor: WidgetStatePropertyAll(AppColors.scrollbarThumb),
      thickness: const WidgetStatePropertyAll(8),
      radius: const Radius.circular(4),
    ),
    snackBarTheme: SnackBarThemeData(
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
