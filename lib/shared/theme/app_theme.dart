import 'package:flutter/material.dart';

/// CyberNeurova mobile theme — aligned with the **official brand assets**
/// (`official icons/cyberneurova-brand/`): the teal synapse mark `#2FE0C7`
/// on the midnight-navy app-icon background `#0B1221`, with a teal→violet
/// glow (the launcher icon's gradient).
///
/// Theme history:
///  - 2026-06-01: dark theme (pure black + peach #E0846B).
///  - 2026-06-xx: mirrored the web chat-app's violet/indigo OKLCH palette.
///  - 2026-06-24: re-skinned to the official brand — **teal accent on navy**.
///    The violet is kept only as the second stop of the brand gradient, to
///    match the logo's teal→violet glow. Color is token-driven here so the
///    whole app re-skins from this one file.
class AppTheme {
  AppTheme._();

  // ─── Dark palette (brand: teal #2FE0C7 on navy #0B1221) ────────────────────

  /// Brand navy base — the official app-icon background `#0B1221`.
  static const Color _bg = Color(0xFF0B1221);

  /// Cards / popovers / sheets — one navy step above the base.
  static const Color _surface = Color(0xFF121C30);

  /// Elevated surface — chips, secondary buttons, menus.
  static const Color _surfaceElevated = Color(0xFF1B2742);

  /// Muted — input fields / chat-input background (a touch below the base
  /// so a filled field reads as recessed on the navy).
  static const Color _muted = Color(0xFF0F1828);

  /// Border — navy-tinted, clearly visible on the base (not a flat gray).
  static const Color _border = Color(0xFF253250);

  /// Foreground — cool near-white body text (sits on navy, not pure white
  /// so it doesn't vibrate).
  static const Color _onSurface = Color(0xFFEAF1FC);

  /// Secondary text — cool slate.
  static const Color _onSurfaceMuted = Color(0xFF94A3C2);

  /// Tertiary text / hints.
  static const Color _onSurfaceDim = Color(0xFF63718F);

  /// Brand accent — the teal synapse mark `#2FE0C7`. Used for the primary
  /// CTA fill, active states, links, focus rings, the streaming cursor.
  static const Color _accent = Color(0xFF2FE0C7);

  /// Accent hover/pressed — a brighter teal.
  static const Color _accentHover = Color(0xFF4DEAD6);

  /// Text/icons ON the teal accent — teal is a light color, so its
  /// foreground must be a deep navy-teal for AA contrast (white-on-teal
  /// fails). This replaces the old `Colors.white` on the violet buttons.
  static const Color _onAccent = Color(0xFF052B25);

  /// Brand gradient second stop — the violet glow from the launcher icon.
  /// Only used inside [brandGradient]; not a standalone UI color.
  static const Color _accentAlt = Color(0xFF8B6FE6);

  /// Destructive — red that reads on navy.
  static const Color _error = Color(0xFFFF6B6B);

  // ─── Public accessors ─────────────────────────────────────────────────────
  static const Color background = _bg;
  static const Color surface = _surface;
  static const Color surfaceElevated = _surfaceElevated;
  static const Color accent = _accent;
  static const Color accentHover = _accentHover;
  static const Color onAccent = _onAccent;
  static const Color accentAlt = _accentAlt;
  static const Color border = _border;
  static const Color foreground = _onSurface;
  static const Color muted = _onSurfaceMuted;
  static const Color dim = _onSurfaceDim;
  static const Color error = _error;

  /// Brand gradient — the logo's teal→violet glow.
  /// `linear-gradient(135deg, #2FE0C7, #8B6FE6)`.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_accent, _accentAlt],
  );

  // ─── Radius scale ─────────────────────────────────────────────────────────

  /// Corner-radius scale — the single source of truth for rounding.
  ///
  /// Brand rule (docs/REDESIGN.md): core surfaces live in the 14–18 band;
  /// the Xs/Sm steps cover small inner elements and the Xl step covers the
  /// composer pill and bottom sheets. The component themes below apply these
  /// defaults app-wide, so call sites should only hardcode a radius when it
  /// is intentionally outside the scale (2–4px indicator bars and drag
  /// handles, `999` full pills, the 4px chat-bubble tail).
  static const double radiusXs = 8; // badges, tags, chip interiors
  static const double radiusSm = 12; // small controls, snackbars, inline banners
  static const double radiusMd = 14; // cards, buttons, input fields, menus
  static const double radiusLg = 18; // large cards, dialogs, user bubble
  static const double radiusXl = 24; // composer pill, bottom sheets, FAB-ish pills

  // ── Font families ─────────────────────────────────────────────────────────
  //
  // These are BUNDLED (see pubspec `fonts:`), not fetched from the Google
  // Fonts CDN. The runtime fetch cost a network round-trip on first launch,
  // made the splash wordmark re-layout mid-animation on a slow connection,
  // and failed outright offline. Family names must match pubspec exactly.

  /// UI sans. Variable font — one file, every weight.
  static const String fontSans = 'Inter';

  /// Display serif for the wordmark and greeting.
  static const String fontSerif = 'Instrument Serif';

  /// Monospace for the terminal, code blocks and any aligned output. A shell
  /// is unreadable in a proportional face.
  static const String fontMono = 'JetBrains Mono';

  /// Drop-in replacement for the old `GoogleFonts.inter(...)` — same named
  /// params, but resolves to the bundled family with no network involved.
  static TextStyle sans({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
    TextDecoration? decoration,
    List<Shadow>? shadows,
  }) =>
      TextStyle(
        fontFamily: fontSans,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
        fontStyle: fontStyle,
        decoration: decoration,
        shadows: shadows,
      );

  /// Monospace text style for terminal/code surfaces.
  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
  }) =>
      TextStyle(
        fontFamily: fontMono,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
      );

  /// Serif font for the wordmark + display headings (the lowercase
  /// "cyberneurova" lockup uses a clean sans; we keep Instrument Serif for
  /// the in-app greeting display).
  static TextStyle serifDisplay({
    double size = 28,
    FontWeight weight = FontWeight.w400,
    Color color = _onSurface,
    double letterSpacing = -0.3,
  }) =>
      TextStyle(
        fontFamily: fontSerif,
        
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  // Built ONCE (lazy) and cached — NOT a getter. As a getter this rebuilt the
  // whole ThemeData (re-resolving GoogleFonts) on every MaterialApp frame, so an
  // Appearance switch churned fonts/layout for seconds and text flickered. As a
  // static final it's a stable object: switching just swaps dark↔light.
  static final ThemeData dark = ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          onPrimary: _onAccent,
          primaryContainer: _accentHover,
          onPrimaryContainer: _onAccent,
          secondary: _accentAlt,
          surface: _bg,
          surfaceContainer: _surface,
          surfaceContainerHigh: _surfaceElevated,
          surfaceContainerHighest: _muted,
          outline: _border,
          outlineVariant: _border,
          onSurface: _onSurface,
          onSurfaceVariant: _onSurfaceMuted,
          error: _error,
          onError: _onAccent,
          errorContainer: Color(0xFF3D1515),
          onErrorContainer: Color(0xFFFFBABA),
        ),
        scaffoldBackgroundColor: _bg,
        canvasColor: _bg,
        textTheme: ThemeData(brightness: Brightness.dark)
            .textTheme
            .apply(fontFamily: fontSans)
            .apply(
          bodyColor: _onSurface,
          displayColor: _onSurface,
        ),

        // AppBar — minimal, flat, transparent for drawer overlays.
        appBarTheme: AppBarTheme(
          backgroundColor: _bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: _onSurface, size: 22),
          titleTextStyle: sans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _onSurface,
            letterSpacing: -0.2,
          ),
        ),

        // Curved on the trailing edge — the app's drawer silhouette.
        //
        // This was `BorderRadius.zero`, which forced EVERY drawer square and
        // silently overrode the rounded shape the drawers themselves ask for.
        // A theme default that contradicts the widget is the hardest kind of
        // styling bug to find, so the default now matches the intent.
        drawerTheme: const DrawerThemeData(
          backgroundColor: _bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(32),
              bottomRight: Radius.circular(32),
            ),
          ),
        ),

        listTileTheme: ListTileThemeData(
          iconColor: _onSurfaceMuted,
          textColor: _onSurface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          dense: false,
          horizontalTitleGap: 14,
          titleTextStyle: sans(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: _onSurface,
          ),
          subtitleTextStyle: sans(
            fontSize: 13,
            color: _onSurfaceMuted,
          ),
        ),

        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: _bg,
          surfaceTintColor: Colors.transparent,
          modalBackgroundColor: _bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
          ),
        ),

        // Cards — navy surfaces with a visible navy-tinted border, on the
        // shared radius scale (radiusMd base; hero callouts use radiusLg).
        cardTheme: CardThemeData(
          color: _surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            side: const BorderSide(color: _border),
          ),
        ),

        // Input fields — recessed muted fill, teal focus ring.
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _muted,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            borderSide: const BorderSide(color: _border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            borderSide: const BorderSide(color: _border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            borderSide: const BorderSide(color: _accent, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            borderSide: const BorderSide(color: _error),
          ),
          hintStyle: sans(color: _onSurfaceDim, fontSize: 15),
          labelStyle: sans(color: _onSurfaceMuted, fontSize: 14),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),

        // Buttons — primary CTAs use the brand teal with DEEP navy text
        // (teal is light; dark-on-teal meets AA, white-on-teal does not).
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: _onAccent,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
            textStyle: sans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: _onAccent,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
            textStyle: sans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            elevation: 0,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _onSurface,
            side: const BorderSide(color: _border),
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
            textStyle: sans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: _accent,
            textStyle: sans(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),

        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: _accent,
          foregroundColor: _onAccent,
          elevation: 0,
          extendedTextStyle: sans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),

        dialogTheme: DialogThemeData(
          backgroundColor: _surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
            side: const BorderSide(color: _border),
          ),
          titleTextStyle: sans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _onSurface,
          ),
          contentTextStyle: sans(
            fontSize: 14,
            color: _onSurfaceMuted,
            height: 1.5,
          ),
        ),

        snackBarTheme: SnackBarThemeData(
          backgroundColor: _surfaceElevated,
          contentTextStyle: sans(
            color: _onSurface,
            fontSize: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          behavior: SnackBarBehavior.floating,
        ),

        dividerTheme: const DividerThemeData(
          color: _border,
          thickness: 0.5,
          space: 0.5,
        ),

        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: _accent,
        ),

        // Popup menus — elevated navy surface, same rounded language as cards.
        popupMenuTheme: PopupMenuThemeData(
          color: _surfaceElevated,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            side: const BorderSide(color: _border),
          ),
        ),
      );

  // ─── Light palette ────────────────────────────────────────────────────────
  // Soft warm-gray canvas (not pure white). Brand accent deepens to a teal
  // that holds AA contrast on light surfaces; foreground uses navy ink.

  /// Soft cool-gray canvas ≈ #ECEEF2
  static const Color _lightBg = Color(0xFFECEEF2);
  /// `--card` / sheets — one notch LIGHTER than bg ≈ #F5F6F9
  static const Color _lightSurface = Color(0xFFF5F6F9);
  /// `--secondary` — buttons/chips ≈ #FAFBFD
  static const Color _lightSurfaceElevated = Color(0xFFFAFBFD);
  /// `--muted` — input fields ≈ #E2E5EC
  static const Color _lightMuted = Color(0xFFE2E5EC);
  /// `--border` ≈ #D2D7E0
  static const Color _lightBorder = Color(0xFFD2D7E0);
  /// `--foreground` — navy ink ≈ #0B1221 (brand navy as text on light)
  static const Color _lightOnSurface = Color(0xFF0B1221);
  /// `--muted-foreground` ≈ #566076
  static const Color _lightOnSurfaceMuted = Color(0xFF566076);
  /// Tertiary text ≈ #88909F
  static const Color _lightOnSurfaceDim = Color(0xFF88909F);
  /// Deep teal accent for light surfaces (brand teal is too light to read
  /// as a button on white) ≈ #0E9C86, AA-safe with white text.
  static const Color _lightAccent = Color(0xFF0E9C86);
  static const Color _lightAccentHover = Color(0xFF12B89E);
  static const Color _lightAccentAlt = Color(0xFF6E58D8);
  static const Color _lightError = Color(0xFFD93B3B);

  // Cached for the same reason as [dark] — see the note above.
  static final ThemeData light = ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: _lightAccent,
          onPrimary: Colors.white,
          primaryContainer: _lightAccentHover,
          secondary: _lightAccentAlt,
          surface: _lightBg,
          surfaceContainer: _lightSurface,
          surfaceContainerHigh: _lightSurfaceElevated,
          surfaceContainerHighest: _lightMuted,
          outline: _lightBorder,
          outlineVariant: _lightBorder,
          onSurface: _lightOnSurface,
          onSurfaceVariant: _lightOnSurfaceMuted,
          error: _lightError,
          errorContainer: Color(0xFFFDECEC),
          onErrorContainer: Color(0xFF7A1818),
        ),
        scaffoldBackgroundColor: _lightBg,
        canvasColor: _lightBg,
        textTheme: ThemeData(brightness: Brightness.light)
            .textTheme
            .apply(fontFamily: fontSans)
            .apply(
          bodyColor: _lightOnSurface,
          displayColor: _lightOnSurface,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: _lightBg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: _lightOnSurface, size: 22),
          titleTextStyle: sans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _lightOnSurface,
            letterSpacing: -0.2,
          ),
        ),
        // Curved on the trailing edge — the app's drawer silhouette.
        //
        // This was `BorderRadius.zero`, which forced EVERY drawer square and
        // silently overrode the rounded shape the drawers themselves ask for.
        // A theme default that contradicts the widget is the hardest kind of
        // styling bug to find, so the default now matches the intent.
        drawerTheme: const DrawerThemeData(
          backgroundColor: _lightBg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(32),
              bottomRight: Radius.circular(32),
            ),
          ),
        ),
        listTileTheme: ListTileThemeData(
          iconColor: _lightOnSurfaceMuted,
          textColor: _lightOnSurface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          horizontalTitleGap: 14,
          titleTextStyle: sans(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: _lightOnSurface,
          ),
          subtitleTextStyle: sans(
            fontSize: 13,
            color: _lightOnSurfaceMuted,
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: _lightBg,
          surfaceTintColor: Colors.transparent,
          modalBackgroundColor: _lightBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
          ),
        ),
        cardTheme: CardThemeData(
          color: _lightSurface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            side: const BorderSide(color: _lightBorder),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _lightMuted,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            borderSide: const BorderSide(color: _lightBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            borderSide: const BorderSide(color: _lightBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            borderSide: const BorderSide(color: _lightAccent, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            borderSide: const BorderSide(color: _lightError),
          ),
          hintStyle: sans(color: _lightOnSurfaceDim, fontSize: 15),
          labelStyle: sans(color: _lightOnSurfaceMuted, fontSize: 14),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _lightAccent,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
            textStyle: sans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _lightAccent,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
            textStyle: sans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            elevation: 0,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _lightOnSurface,
            side: const BorderSide(color: _lightBorder),
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
            textStyle: sans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: _lightAccent,
            textStyle: sans(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: _lightAccent,
          foregroundColor: Colors.white,
          elevation: 0,
          extendedTextStyle: sans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: _lightSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
            side: const BorderSide(color: _lightBorder),
          ),
          titleTextStyle: sans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _lightOnSurface,
          ),
          contentTextStyle: sans(
            fontSize: 14,
            color: _lightOnSurfaceMuted,
            height: 1.5,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: _lightSurfaceElevated,
          contentTextStyle: sans(
            color: _lightOnSurface,
            fontSize: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        dividerTheme: const DividerThemeData(
          color: _lightBorder,
          thickness: 0.5,
          space: 0.5,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: _lightAccent,
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: _lightSurfaceElevated,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            side: const BorderSide(color: _lightBorder),
          ),
        ),
      );
}
