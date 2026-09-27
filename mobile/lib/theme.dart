import 'package:flutter/material.dart';

/// Design tokens: deep teal primary, saffron accent, warm paper neutrals, ink text.
class PColors {
  static const teal = Color(0xFF0F766E);
  static const tealBright = Color(0xFF2DD4BF);
  static const tealDeep = Color(0xFF0B3B3C);
  static const saffron = Color(0xFFF59E0B);
  static const ink = Color(0xFF111827);
  static const paper = Color(0xFFF6F5F1);
  static const night = Color(0xFF0D1214);

  static const heroGradient = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [Color(0xFF0F766E), Color(0xFF0B4F4C), Color(0xFF0B3B3C)],
  );

  /// Soft per-objective accents (background, foreground) for badges and create cards.
  static (Color, Color) objective(String type, bool dark) => switch (type) {
    'educational' => dark ? (const Color(0xFF12343A), const Color(0xFF7EE0D2)) : (const Color(0xFFE0F2EF), teal),
    'news' =>
      dark ? (const Color(0xFF1E2A44), const Color(0xFF9DB8FF)) : (const Color(0xFFE6ECFB), const Color(0xFF3056C8)),
    'promo' =>
      dark ? (const Color(0xFF3A2A12), const Color(0xFFFFC66B)) : (const Color(0xFFFDF1DC), const Color(0xFFB45F06)),
    'sales' =>
      dark ? (const Color(0xFF3A1A22), const Color(0xFFFF9FB2)) : (const Color(0xFFFCE7EC), const Color(0xFFBE123C)),
    _ => dark ? (const Color(0xFF2A2140), const Color(0xFFC4B5FD)) : (const Color(0xFFEFEAFD), const Color(0xFF6D28D9)),
  };
}

/// Horizontal padding that keeps content in a readable, centered column on wide screens while the scroll
/// area stays full width.
EdgeInsets pagePadding(BuildContext context, {double top = 8, double bottom = 110, double maxWidth = 880}) {
  final w = MediaQuery.sizeOf(context).width;
  final side = w > maxWidth + 48 ? (w - maxWidth) / 2 : (w >= 600 ? 24.0 : 16.0);
  return EdgeInsets.fromLTRB(side, top, side, bottom);
}

/// Number of grid columns for cards at the current width.
int gridColumns(BuildContext context, {double minTile = 300}) {
  final w = MediaQuery.sizeOf(context).width - pagePadding(context).horizontal;
  return (w / minTile).floor().clamp(1, 4);
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: PColors.teal,
        brightness: brightness,
        primary: dark ? PColors.tealBright : PColors.teal,
        onPrimary: dark ? PColors.night : Colors.white,
        secondary: PColors.saffron,
        surface: dark ? PColors.night : PColors.paper,
        onSurface: dark ? const Color(0xFFE8EDEC) : PColors.ink,
      ).copyWith(
        onSurfaceVariant: dark ? const Color(0xFF9AA8A7) : const Color(0xFF5B6470),
        surfaceContainerLowest: dark ? const Color(0xFF0A0E10) : Colors.white,
        surfaceContainerLow: dark ? const Color(0xFF151C1F) : Colors.white,
        surfaceContainer: dark ? const Color(0xFF182125) : Colors.white,
        surfaceContainerHigh: dark ? const Color(0xFF1C272B) : const Color(0xFFF0EFEA),
        surfaceContainerHighest: dark ? const Color(0xFF223036) : const Color(0xFFE9E8E2),
        outlineVariant: dark ? const Color(0xFF26333A) : const Color(0xFFE5E3DC),
        primaryContainer: dark ? const Color(0xFF12343A) : const Color(0xFFD9F1ED),
        onPrimaryContainer: dark ? const Color(0xFF9FEBDF) : const Color(0xFF0B4F4C),
      );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Vazirmatn', brightness: brightness);
  final t = base.textTheme;
  final radius = BorderRadius.circular(14);

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
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
      headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.3, height: 1.4),
      headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w900, height: 1.45),
      titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.5),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.5),
      titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.5),
      bodyLarge: t.bodyLarge?.copyWith(height: 1.75),
      bodyMedium: t.bodyMedium?.copyWith(height: 1.75),
      bodySmall: t.bodySmall?.copyWith(height: 1.65, color: scheme.onSurfaceVariant),
      labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 16,
      titleTextStyle: t.titleLarge?.copyWith(
        fontWeight: FontWeight.w900,
        color: scheme.onSurface,
        fontFamily: 'Vazirmatn',
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: .8)),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w800, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: radius),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: scheme.surfaceContainerLow,
      selectedColor: scheme.primaryContainer,
      labelStyle: TextStyle(fontFamily: 'Vazirmatn', color: scheme.onSurface, fontSize: 13),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: dark ? PColors.tealBright : PColors.ink,
      foregroundColor: dark ? PColors.night : Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: 440,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: PColors.ink.withValues(alpha: .92), borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontFamily: 'Vazirmatn', color: Colors.white, fontSize: 12),
    ),
  );
}

/// Floating bottom navigation used inside a project. Same on every screen size (centered on wide screens).
class FloatingNav extends StatelessWidget {
  const FloatingNav({super.key, required this.items, required this.index, required this.onTap});
  final List<(IconData, IconData, String)> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          // Opaque: taps on the bar's padding must never fall through to the page content behind it.
          child: Listener(
            behavior: HitTestBehavior.opaque,
            child: RepaintBoundary(
              child: Container(
                height: 66,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF182125) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: scheme.outlineVariant),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? .35 : .08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
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
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gradient header card.
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.title, required this.subtitle, this.trailing, this.child});
  final String title, subtitle;
  final Widget? trailing;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
    decoration: BoxDecoration(gradient: PColors.heroGradient, borderRadius: BorderRadius.circular(24)),
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
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      height: 1.45,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: .82), height: 1.6)),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
        if (child != null) ...[const SizedBox(height: 16), child!],
      ],
    ),
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
