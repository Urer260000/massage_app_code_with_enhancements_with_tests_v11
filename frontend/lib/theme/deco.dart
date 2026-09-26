import 'dart:math' as math;

import 'package:flutter/material.dart';

/// the20sspa design system: Roaring Twenties Art Deco — ink black, gold and cream.
class Deco {
  static const ink = Color(0xFF0E0D0B);
  static const panel = Color(0xFF17150F);
  static const panelHigh = Color(0xFF221E16);
  static const gold = Color(0xFFD4AF6A);
  static const goldBright = Color(0xFFF0DCA6);
  static const goldDeep = Color(0xFF9C7C3E);
  static const cream = Color(0xFFF3EBDD);
  static const muted = Color(0xFFA39A88);
  static const danger = Color(0xFFE59384);

  static const display = 'Limelight';
  static const elegant = 'PoiretOne';
  static const body = 'JosefinSans';

  static const goldGradient = LinearGradient(
    colors: [goldDeep, goldBright, gold],
    stops: [0, 0.55, 1],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Small, wide-tracked uppercase label (menus, captions, buttons).
  static TextStyle label({double size = 12, Color color = gold}) => TextStyle(
        fontFamily: body,
        fontSize: size,
        letterSpacing: 2.4,
        color: color,
        fontVariations: const [FontVariation('wght', 600)],
      );

  static TextStyle heading({double size = 26, Color color = cream}) =>
      TextStyle(fontFamily: elegant, fontSize: size, color: color, height: 1.15);

  static TextStyle price({double size = 22}) =>
      TextStyle(fontFamily: display, fontSize: size, color: goldBright);
}

ThemeData buildDecoTheme() {
  const scheme = ColorScheme.dark(
    primary: Deco.gold,
    onPrimary: Deco.ink,
    secondary: Deco.goldBright,
    onSecondary: Deco.ink,
    surface: Deco.panel,
    onSurface: Deco.cream,
    error: Deco.danger,
    onError: Deco.ink,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: Deco.body,
    scaffoldBackgroundColor: Deco.ink,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Deco.cream,
      displayColor: Deco.cream,
      fontFamily: Deco.body,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Deco.ink,
      foregroundColor: Deco.gold,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Deco.panelHigh,
      contentTextStyle: const TextStyle(fontFamily: Deco.body, color: Deco.goldBright, fontSize: 15),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Deco.gold),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Deco.gold),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Deco.gold,
      selectionColor: Color(0x55D4AF6A),
      selectionHandleColor: Deco.gold,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Deco.panel,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Deco.gold.withValues(alpha: 0.16),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => Deco.label(
          size: 11,
          color: states.contains(WidgetState.selected) ? Deco.gold : Deco.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? Deco.gold : Deco.muted,
        ),
      ),
    ),
  );
}

/// Text field decoration in the deco style.
InputDecoration decoInput(String label, IconData icon) {
  const edge = BorderRadius.zero;
  return InputDecoration(
    labelText: label,
    labelStyle: Deco.label(color: Deco.muted),
    floatingLabelStyle: Deco.label(),
    prefixIcon: Icon(icon, color: Deco.goldDeep, size: 20),
    filled: true,
    fillColor: Deco.ink,
    errorStyle: const TextStyle(fontFamily: Deco.body, color: Deco.danger),
    enabledBorder: const OutlineInputBorder(
      borderRadius: edge,
      borderSide: BorderSide(color: Color(0x669C7C3E)),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: edge,
      borderSide: BorderSide(color: Deco.gold, width: 1.4),
    ),
    errorBorder: const OutlineInputBorder(
      borderRadius: edge,
      borderSide: BorderSide(color: Deco.danger),
    ),
    focusedErrorBorder: const OutlineInputBorder(
      borderRadius: edge,
      borderSide: BorderSide(color: Deco.danger, width: 1.4),
    ),
  );
}

/// Primary call-to-action: a gold-leaf gradient bar.
class GoldButton extends StatelessWidget {
  const GoldButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: onPressed == null && !loading ? 0.45 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: Deco.goldGradient,
          boxShadow: [
            BoxShadow(
              color: Deco.gold.withValues(alpha: 0.28),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            splashColor: Deco.ink.withValues(alpha: 0.15),
            child: SizedBox(
              height: 54,
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Deco.ink),
                      )
                    : Text(label, style: Deco.label(size: 14, color: Deco.ink)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary action: thin gold outline.
class GoldOutlineButton extends StatelessWidget {
  const GoldOutlineButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Deco.gold,
        side: const BorderSide(color: Deco.gold),
        shape: const RoundedRectangleBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: Deco.label(size: 12),
      ),
      child: Text(label),
    );
  }
}

/// Line — diamond — line.
class DecoDivider extends StatelessWidget {
  const DecoDivider({super.key, this.width});
  final double? width;

  @override
  Widget build(BuildContext context) {
    Widget line(bool reverse) => Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: reverse
                    ? const [Deco.gold, Color(0x00D4AF6A)]
                    : const [Color(0x00D4AF6A), Deco.gold],
              ),
            ),
          ),
        );
    return SizedBox(
      width: width,
      child: Row(
        children: [
          line(false),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(width: 7, height: 7, color: Deco.gold),
            ),
          ),
          line(true),
        ],
      ),
    );
  }
}

/// Uppercase section heading with deco rules either side.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(text, style: Deco.label(size: 12)),
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, color: Deco.goldDeep.withValues(alpha: 0.5))),
      ],
    );
  }
}

/// Panel with chamfered corners and a double gold rule.
class DecoFrame extends StatelessWidget {
  const DecoFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.highlight = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FramePainter(highlight: highlight),
      child: Padding(padding: padding, child: child),
    );
  }
}

Path _chamfer(Rect r, double c) => Path()
  ..moveTo(r.left + c, r.top)
  ..lineTo(r.right - c, r.top)
  ..lineTo(r.right, r.top + c)
  ..lineTo(r.right, r.bottom - c)
  ..lineTo(r.right - c, r.bottom)
  ..lineTo(r.left + c, r.bottom)
  ..lineTo(r.left, r.bottom - c)
  ..lineTo(r.left, r.top + c)
  ..close();

class _FramePainter extends CustomPainter {
  _FramePainter({required this.highlight});
  final bool highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.6);
    final outer = _chamfer(rect, 14);
    canvas.drawPath(
      outer,
      Paint()
        ..shader = const LinearGradient(
          colors: [Deco.panelHigh, Deco.panel],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(rect),
    );
    canvas.drawPath(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = highlight ? 1.6 : 1.1
        ..color = highlight ? Deco.gold : Deco.goldDeep.withValues(alpha: 0.85),
    );
    canvas.drawPath(
      _chamfer(rect.deflate(5), 11),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = Deco.gold.withValues(alpha: highlight ? 0.6 : 0.28),
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.highlight != highlight;
}

/// Faint radiating sunburst used behind headers.
class SunburstPainter extends CustomPainter {
  SunburstPainter({this.origin = const Alignment(0, 1.05), this.opacity = 0.16, this.rays = 30});
  final Alignment origin;
  final double opacity;
  final int rays;

  @override
  void paint(Canvas canvas, Size size) {
    final o = origin.alongSize(size);
    final length = size.longestSide * 1.6;
    final downward = origin.y < 0;
    final ray = Paint()
      ..color = Deco.gold.withValues(alpha: opacity)
      ..strokeWidth = 1;
    for (var i = 0; i <= rays; i++) {
      final a = (downward ? 0 : math.pi) + math.pi * i / rays;
      canvas.drawLine(o, o + Offset(math.cos(a), math.sin(a)) * length, ray);
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Deco.gold.withValues(alpha: opacity * 1.3);
    for (var k = 1; k <= 5; k++) {
      canvas.drawCircle(o, size.shortestSide * 0.22 * k, ring);
    }
  }

  @override
  bool shouldRepaint(SunburstPainter old) => false;
}

/// the20sspa fan emblem.
class FanEmblem extends StatelessWidget {
  const FanEmblem({super.key, this.size = 88});
  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size * 0.72, child: CustomPaint(painter: _FanPainter()));
}

class _FanPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.86);
    final r = size.width * 0.48;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, size.width / 60)
      ..color = Deco.gold;
    final fine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, size.width / 110)
      ..color = Deco.gold.withValues(alpha: 0.8);

    canvas.drawArc(Rect.fromCircle(center: c, radius: r), math.pi, math.pi, false, outline);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.8), math.pi, math.pi, false, fine);

    final sun = Rect.fromCircle(center: c, radius: r * 0.34);
    canvas.drawArc(sun, math.pi, math.pi, true, Paint()..shader = Deco.goldGradient.createShader(sun));

    const n = 13;
    for (var i = 1; i < n; i++) {
      final a = math.pi + math.pi * i / n;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * r * 0.42, c + dir * r * 0.72, fine);
    }
    canvas.drawLine(Offset(c.dx - r * 1.05, c.dy), Offset(c.dx + r * 1.05, c.dy), outline);
  }

  @override
  bool shouldRepaint(_FanPainter old) => false;
}

/// Gold-leaf text.
class GoldText extends StatelessWidget {
  const GoldText(this.text, {super.key, required this.style, this.textAlign});
  final String text;
  final TextStyle style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => Deco.goldGradient.createShader(bounds),
      child: Text(text, style: style.copyWith(color: Colors.white), textAlign: textAlign),
    );
  }
}

/// Full logo lock-up: emblem, wordmark and tagline.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 96, this.tagline = true});
  final double size;
  final bool tagline;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FanEmblem(size: size),
        SizedBox(height: size * 0.12),
        GoldText(
          'the20sspa',
          style: TextStyle(fontFamily: Deco.display, fontSize: size * 0.44, letterSpacing: 1.2),
        ),
        if (tagline) ...[
          const SizedBox(height: 10),
          const DecoDivider(width: 200),
          const SizedBox(height: 10),
          Text('A ROARING TWENTIES DAY SPA', style: Deco.label(size: 11, color: Deco.muted)),
        ],
      ],
    );
  }
}

const monthAbbr = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
const weekdayAbbr = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

IconData serviceIcon(String id) {
  if (id.startsWith('hot-stone')) return Icons.local_fire_department_outlined;
  if (id.startsWith('deep-tissue')) return Icons.front_hand_outlined;
  if (id.startsWith('sports')) return Icons.directions_run;
  return Icons.spa_outlined;
}

/// Round gold medallion around an icon.
class Medallion extends StatelessWidget {
  const Medallion({super.key, required this.icon, this.size = 52});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Deco.gold, width: 1.2),
        gradient: RadialGradient(colors: [Deco.gold.withValues(alpha: 0.18), Deco.ink]),
      ),
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Deco.gold.withValues(alpha: 0.35), width: 0.8),
        ),
        child: Icon(icon, color: Deco.goldBright, size: size * 0.42),
      ),
    );
  }
}
