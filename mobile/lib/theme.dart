import 'package:flutter/material.dart';

/// Design tokens after the "Postly" reference: deep forest-green navigation, white workspace with hairline
/// grey borders, one green action color, mint for "today", and soft tinted labels (orange draft, green
/// design, lavender campaign).
class PColors {
  static const forest = Color(0xFF0C4A36); // navigation bar, like the reference sidebar
  static const forestActive = Color(0xFF16664A);
  static const green = Color(0xFF12764D); // primary buttons
  static const greenDark = Color(0xFF0B5A3A);
  static const mint = Color(0xFFE6F7EF);
  static const mintStrong = Color(0xFFCDEFDF);

  static const page = Color(0xFFF6F7F7);
  static const card = Colors.white;
  static const line = Color(0xFFE6E8EB);
  static const text = Color(0xFF101828);
  static const muted = Color(0xFF667085);
  static const backdrop = Color(0xFFE4E8E6);

  // Older names used by some screens.
  static const teal = green;
  static const tealBright = Color(0xFF7FE0B5);
  static const tealDeep = forest;
  static const violet = green;

  /// Mint wash of the reference's "today" cell.
  static const heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFD9F5E8), Color(0xFFF1FBF6)],
  );

  static const accentGradient = LinearGradient(colors: [green, greenDark]);

  /// Soft tinted labels (background, foreground) per content objective.
  static (Color, Color) objective(String type, [bool dark = false]) => switch (type) {
    'educational' => (const Color(0xFFE6F7EF), const Color(0xFF11774D)),
    'news' => (const Color(0xFFEAF1FE), const Color(0xFF2458D6)),
    'promo' => (const Color(0xFFFFF4E0), const Color(0xFFD97706)),
    'sales' => (const Color(0xFFF1ECFE), const Color(0xFF6D3FD9)),
    _ => (const Color(0xFFFFEDF3), const Color(0xFFD1316B)),
  };
}

/// Page padding for the phone column.
EdgeInsets pagePadding(BuildContext context, {double top = 12, double bottom = 110, double maxWidth = 880}) {
  final w = MediaQuery.sizeOf(context).width;
  final side = w > maxWidth + 48 ? (w - maxWidth) / 2 : 16.0;
  return EdgeInsets.fromLTRB(side, top, side, bottom);
}

/// Number of grid columns for cards at the current width.
int gridColumns(BuildContext context, {double minTile = 300}) {
  final w = MediaQuery.sizeOf(context).width - pagePadding(context).horizontal;
  return (w / minTile).floor().clamp(1, 4);
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: PColors.green).copyWith(
    primary: PColors.green,
    onPrimary: Colors.white,
    secondary: PColors.forest,
    onSecondary: Colors.white,
    tertiary: const Color(0xFFD97706),
    surface: PColors.page,
    onSurface: PColors.text,
    onSurfaceVariant: PColors.muted,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: Colors.white,
    surfaceContainerHigh: const Color(0xFFF2F4F5),
    surfaceContainerHighest: const Color(0xFFEBEEF0),
    outline: const Color(0xFFD0D5DD),
    outlineVariant: PColors.line,
    primaryContainer: PColors.mint,
    onPrimaryContainer: PColors.greenDark,
    secondaryContainer: const Color(0xFFF2F4F5),
    onSecondaryContainer: PColors.text,
    error: const Color(0xFFD92D20),
    errorContainer: const Color(0xFFFEECEB),
    onErrorContainer: const Color(0xFFB42318),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Vazirmatn');
  final t = base.textTheme;
  final radius = BorderRadius.circular(12);

  return base.copyWith(
    scaffoldBackgroundColor: PColors.page,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: SoftPageTransitionsBuilder(),
        TargetPlatform.iOS: SoftPageTransitionsBuilder(),
        TargetPlatform.macOS: SoftPageTransitionsBuilder(),
        TargetPlatform.windows: SoftPageTransitionsBuilder(),
        TargetPlatform.linux: SoftPageTransitionsBuilder(),
        TargetPlatform.fuchsia: SoftPageTransitionsBuilder(),
      },
    ),
    textTheme: t.copyWith(
      headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.4, color: PColors.text),
      headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.45, color: PColors.text),
      titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.5),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.5),
      titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.5),
      bodyLarge: t.bodyLarge?.copyWith(height: 1.75),
      bodyMedium: t.bodyMedium?.copyWith(height: 1.75, color: const Color(0xFF344054)),
      bodySmall: t.bodySmall?.copyWith(height: 1.65, color: PColors.muted),
      labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      labelMedium: t.labelMedium?.copyWith(color: PColors.muted, fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: PColors.text,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 16,
      shape: const Border(bottom: BorderSide(color: PColors.line)),
      titleTextStyle: t.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: PColors.text,
        fontFamily: 'Vazirmatn',
        fontSize: 18,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: PColors.line),
      ),
    ),
    dividerTheme: const DividerThemeData(color: PColors.line, space: 1),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
      iconColor: PColors.muted,
    ),
    iconTheme: const IconThemeData(color: PColors.text),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: const TextStyle(color: Color(0xFF98A2B3)),
      labelStyle: const TextStyle(color: PColors.muted),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: PColors.green, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PColors.green,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFEBEEF0),
        disabledForegroundColor: const Color(0xFF98A2B3),
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: PColors.text,
        backgroundColor: Colors.white,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: radius),
        side: const BorderSide(color: Color(0xFFD0D5DD)),
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: PColors.green,
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w700),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: PColors.text)),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: const BorderSide(color: PColors.line),
      backgroundColor: Colors.white,
      selectedColor: PColors.mint,
      labelStyle: const TextStyle(fontFamily: 'Vazirmatn', color: PColors.text, fontSize: 13),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: const Color(0xFFF2F4F5),
        selectedBackgroundColor: Colors.white,
        selectedForegroundColor: PColors.text,
        foregroundColor: PColors.muted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: PColors.line),
      ),
    ),
    sliderTheme: const SliderThemeData(activeTrackColor: PColors.green, thumbColor: PColors.green),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: PColors.green),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: PColors.green,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: PColors.forest,
      contentTextStyle: const TextStyle(fontFamily: 'Vazirmatn', color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: PColors.forest, borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontFamily: 'Vazirmatn', color: Colors.white, fontSize: 12),
    ),
  );
}

/// Bottom navigation in the reference's forest-green sidebar colors; the active tab is a lighter green pill.
class FloatingNav extends StatelessWidget {
  const FloatingNav({super.key, required this.items, required this.index, required this.onTap});
  final List<(IconData, IconData, String)> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => Listener(
    // Opaque: taps on the bar's padding must never fall through to the page content behind it.
    behavior: HitTestBehavior.opaque,
    child: Container(
      decoration: const BoxDecoration(
        color: PColors.forest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 6),
        child: SizedBox(
          height: 66,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _NavItem(
                      icon: i == index ? items[i].$2 : items[i].$1,
                      label: items[i].$3,
                      selected: i == index,
                      onTap: () => onTap(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: selected ? PColors.forestActive : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 21, color: selected ? Colors.white : Colors.white.withValues(alpha: .62)),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : Colors.white.withValues(alpha: .62),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// "Today" card: the mint wash and green accents of the reference's current-day cell.
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.title, required this.subtitle, this.trailing, this.child});
  final String title, subtitle;
  final Widget? trailing;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: PColors.heroGradient,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: PColors.mintStrong),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: PColors.text,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      height: 1.45,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: PColors.muted, height: 1.6)),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
        if (child != null) ...[const SizedBox(height: 12), child!],
      ],
    ),
  );
}

/// Icon in a soft mint tile (the reference's quiet icon style).
class GradientIcon extends StatelessWidget {
  const GradientIcon(this.icon, {super.key, this.size = 44});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: PColors.mint, borderRadius: BorderRadius.circular(size * .28)),
    child: Icon(icon, color: PColors.green, size: size * .5),
  );
}

/// Quick slide only (no fade): opacity over a full page is expensive in the web renderer and looked like
/// slow motion. A transform-only slide stays cheap. Direction-aware for RTL.
class SoftPageTransitionsBuilder extends PageTransitionsBuilder {
  const SoftPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 160);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 130);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return SlideTransition(
      position: Tween(
        begin: Offset(rtl ? -1 : 1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
      child: child,
    );
  }
}

/// Keeps every tab alive (scroll position, loaded data); switching is instant and only the visible tab
/// ticks and paints.
class FadeIndexedStack extends StatelessWidget {
  const FadeIndexedStack({super.key, required this.index, required this.children});
  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => IndexedStack(
    index: index,
    children: [
      for (var i = 0; i < children.length; i++)
        TickerMode(
          enabled: i == index,
          child: RepaintBoundary(child: children[i]),
        ),
    ],
  );
}
