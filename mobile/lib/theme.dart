import 'package:flutter/material.dart';

/// Design tokens — "night studio": near-black canvas, layered charcoal cards, and one vivid
/// violet → pink → orange gradient (the creator/Instagram energy) for everything that matters.
class PColors {
  static const violet = Color(0xFF8B5CF6);
  static const pink = Color(0xFFEC4899);
  static const orange = Color(0xFFF97316);
  static const lilac = Color(0xFFC4B5FD);

  static const canvas = Color(0xFF0B0B10);
  static const card = Color(0xFF15151D);
  static const raised = Color(0xFF1D1D28);
  static const line = Color(0xFF2A2A38);
  static const text = Color(0xFFF5F5F8);
  static const muted = Color(0xFF9B9BB0);
  static const backdrop = Color(0xFF050507);

  // Older names kept so every screen maps onto the new palette.
  static const teal = violet;
  static const tealBright = lilac;
  static const tealDeep = Color(0xFF2E1065);
  static const saffron = orange;
  static const ink = canvas;
  static const paper = canvas;
  static const night = canvas;

  static const heroGradient = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [violet, pink, orange],
    stops: [0, .55, 1],
  );

  static const accentGradient = LinearGradient(
    begin: AlignmentDirectional.centerStart,
    end: AlignmentDirectional.centerEnd,
    colors: [violet, pink],
  );

  /// Per-objective accents (background, foreground) for badges and create cards.
  static (Color, Color) objective(String type, [bool dark = true]) => switch (type) {
    'educational' => (const Color(0xFF1F1B3D), const Color(0xFFA5B4FC)),
    'news' => (const Color(0xFF0E2A33), const Color(0xFF67E8F9)),
    'promo' => (const Color(0xFF33200F), const Color(0xFFFDBA74)),
    'sales' => (const Color(0xFF361427), const Color(0xFFF9A8D4)),
    _ => (const Color(0xFF1E2A12), const Color(0xFFBEF264)),
  };
}

/// Page padding for the phone column.
EdgeInsets pagePadding(BuildContext context, {double top = 8, double bottom = 120, double maxWidth = 880}) {
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
  final scheme = ColorScheme.fromSeed(seedColor: PColors.violet, brightness: Brightness.dark).copyWith(
    primary: PColors.lilac,
    onPrimary: const Color(0xFF1A0B3D),
    secondary: PColors.pink,
    onSecondary: Colors.white,
    tertiary: PColors.orange,
    surface: PColors.canvas,
    onSurface: PColors.text,
    onSurfaceVariant: PColors.muted,
    surfaceContainerLowest: const Color(0xFF08080C),
    surfaceContainerLow: PColors.card,
    surfaceContainer: PColors.card,
    surfaceContainerHigh: PColors.raised,
    surfaceContainerHighest: const Color(0xFF262633),
    outline: const Color(0xFF3A3A4C),
    outlineVariant: PColors.line,
    primaryContainer: const Color(0xFF2A1F4D),
    onPrimaryContainer: const Color(0xFFDDD6FE),
    secondaryContainer: const Color(0xFF3A1430),
    onSecondaryContainer: const Color(0xFFFBCFE8),
    error: const Color(0xFFFB7185),
    errorContainer: const Color(0xFF3B1219),
    onErrorContainer: const Color(0xFFFECDD3),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Vazirmatn', brightness: Brightness.dark);
  final t = base.textTheme;
  final radius = BorderRadius.circular(16);

  return base.copyWith(
    scaffoldBackgroundColor: PColors.canvas,
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
      headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w900, height: 1.35, color: PColors.text),
      headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w900, height: 1.4, color: PColors.text),
      titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w900, height: 1.45),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.5),
      titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.5),
      bodyLarge: t.bodyLarge?.copyWith(height: 1.75),
      bodyMedium: t.bodyMedium?.copyWith(height: 1.75, color: const Color(0xFFE4E4EC)),
      bodySmall: t.bodySmall?.copyWith(height: 1.65, color: PColors.muted),
      labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w800),
      labelMedium: t.labelMedium?.copyWith(color: PColors.muted, fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: PColors.canvas,
      foregroundColor: PColors.text,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 16,
      titleTextStyle: t.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: PColors.text, fontFamily: 'Vazirmatn'),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: PColors.card,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
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
      fillColor: PColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      hintStyle: const TextStyle(color: Color(0xFF6E6E84)),
      labelStyle: const TextStyle(color: PColors.muted),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: PColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: PColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: PColors.violet, width: 1.8),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PColors.violet,
        foregroundColor: Colors.white,
        disabledBackgroundColor: PColors.raised,
        disabledForegroundColor: const Color(0xFF6E6E84),
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w900, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: PColors.text,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        side: const BorderSide(color: Color(0xFF3A3A4C)),
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: PColors.lilac,
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w800),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: const BorderSide(color: PColors.line),
      backgroundColor: PColors.card,
      selectedColor: const Color(0xFF2A1F4D),
      labelStyle: const TextStyle(fontFamily: 'Vazirmatn', color: PColors.text, fontSize: 13),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: PColors.card,
        selectedBackgroundColor: const Color(0xFF2A1F4D),
        selectedForegroundColor: const Color(0xFFDDD6FE),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        side: const BorderSide(color: PColors.line),
      ),
    ),
    sliderTheme: const SliderThemeData(activeTrackColor: PColors.violet, thumbColor: PColors.pink),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? PColors.violet : PColors.raised,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: PColors.lilac),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: PColors.violet,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: StadiumBorder(),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: PColors.card,
      showDragHandle: true,
      dragHandleColor: Color(0xFF3A3A4C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: PColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: PColors.raised,
      contentTextStyle: const TextStyle(fontFamily: 'Vazirmatn', color: PColors.text),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: PColors.line),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: PColors.raised, borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontFamily: 'Vazirmatn', color: PColors.text, fontSize: 12),
    ),
  );
}

/// Floating dark pill navigation; the selected tab gets a glowing gradient icon bubble.
class FloatingNav extends StatelessWidget {
  const FloatingNav({super.key, required this.items, required this.index, required this.onTap});
  final List<(IconData, IconData, String)> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => SafeArea(
    minimum: const EdgeInsets.fromLTRB(14, 0, 14, 14),
    // Opaque: taps on the bar's padding must never fall through to the page content behind it.
    child: Listener(
      behavior: HitTestBehavior.opaque,
      child: RepaintBoundary(
        child: Container(
          height: 70,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xF2181822),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: PColors.line),
            boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 30, offset: Offset(0, 12))],
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: selected ? 44 : 34,
            height: 30,
            decoration: BoxDecoration(
              gradient: selected ? PColors.accentGradient : null,
              borderRadius: BorderRadius.circular(12),
              boxShadow: selected
                  ? const [BoxShadow(color: Color(0x668B5CF6), blurRadius: 14, offset: Offset(0, 4))]
                  : null,
            ),
            child: Icon(icon, size: 20, color: selected ? Colors.white : PColors.muted),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w500,
              color: selected ? PColors.text : PColors.muted,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Big gradient card with soft light blobs.
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.title, required this.subtitle, this.trailing, this.child});
  final String title, subtitle;
  final Widget? trailing;
  final Widget? child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: Container(
      decoration: const BoxDecoration(gradient: PColors.heroGradient),
      child: Stack(
        children: [
          PositionedDirectional(
            top: -40,
            end: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .12)),
            ),
          ),
          PositionedDirectional(
            bottom: -50,
            start: -20,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: .10)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
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
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                              height: 1.4,
                            ),
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: .88), height: 1.6)),
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
          ),
        ],
      ),
    ),
  );
}

/// Icon in a small gradient tile, used for headers of tiles and empty states.
class GradientIcon extends StatelessWidget {
  const GradientIcon(this.icon, {super.key, this.size = 44});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(gradient: PColors.heroGradient, borderRadius: BorderRadius.circular(size * .32)),
    child: Icon(icon, color: Colors.white, size: size * .5),
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
