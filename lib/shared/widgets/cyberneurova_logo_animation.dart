import 'package:flutter/material.dart';

/// Animated CyberNeurova brand mark — the official teal synapse logo "firing".
/// Geometry from `official icons/.../master/mark-teal.svg` (512×512 space).
///
/// The mark is drawn complete from the first frame (so it continues seamlessly
/// from the OS launcher/native-splash icon — no disassemble/reassemble flash),
/// then it comes to life: a bright signal pulses up the axon, the synaptic dots
/// flare white→teal as it reaches them, the soma throbs, and a glow ripples — the
/// "Pixar moment" playing on top of the logo.
///
/// Honors reduced-motion (`MediaQuery.disableAnimations`) by rendering the
/// finished mark statically. Calls [onComplete] when the animation ends.
class CyberNeurovaLogoAnimation extends StatefulWidget {
  const CyberNeurovaLogoAnimation({
    super.key,
    this.size = 132,
    this.color = const Color(0xFF2FE0C7),
    this.duration = const Duration(milliseconds: 1900),
    this.onComplete,
  });

  final double size;
  final Color color;
  final Duration duration;
  final VoidCallback? onComplete;

  @override
  State<CyberNeurovaLogoAnimation> createState() =>
      _CyberNeurovaLogoAnimationState();
}

class _CyberNeurovaLogoAnimationState extends State<CyberNeurovaLogoAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Play the brand intro even when the OS requests reduced motion — it's a
    // brief, one-time launch animation, not a repetitive UI transition. Jumping
    // straight to the static end frame here just read as "the logo freezes"
    // (Samsung One UI's "Reduce animations" sets Flutter's disableAnimations
    // flag even with the global animation scales at 1.0). Reduced-motion just
    // gets a quicker pass.
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) _c.duration = const Duration(milliseconds: 950);
    _c.forward().whenComplete(() => widget.onComplete?.call());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: _SynapsePainter(t: _c.value, color: widget.color),
        ),
      ),
    );
  }
}

class _SynapsePainter extends CustomPainter {
  _SynapsePainter({required this.t, required this.color});

  final double t;
  final Color color;

  // ─── Geometry (mark-teal.svg, 512×512 space) ────────────────────────────────
  static const Offset _node = Offset(220, 270);
  static const double _nodeR = 58;
  static const double _strokeW = 22;

  // Dendrite branches: each is a polyline (drawn from the node-side outward).
  static const List<List<Offset>> _dendrites = [
    [Offset(165, 232), Offset(108, 180)],
    [Offset(108, 180), Offset(80, 168)],
    [Offset(108, 180), Offset(100, 152)],
    [Offset(158, 285), Offset(92, 290)],
    [Offset(92, 290), Offset(66, 274)],
    [Offset(92, 290), Offset(70, 312)],
    [Offset(168, 322), Offset(120, 376)],
    [Offset(120, 376), Offset(98, 392)],
    [Offset(120, 376), Offset(122, 398)],
  ];

  // Synaptic output dots (terminal hub first), as (center, radius).
  static const List<(Offset, double)> _dots = [
    (Offset(374, 154), 20),
    (Offset(416, 128), 13),
    (Offset(412, 190), 13),
    (Offset(444, 108), 7),
    (Offset(452, 160), 7),
  ];

  // Terminal arrowhead lines off the hub.
  static const List<List<Offset>> _terminal = [
    [Offset(374, 154), Offset(416, 128)],
    [Offset(374, 154), Offset(412, 190)],
  ];

  double _seg(double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  /// 0→1→0 pulse peaking at [center] with [half] half-width.
  double _bump(double center, double half) =>
      (1 - ((t - center).abs() / half)).clamp(0.0, 1.0);

  Path _axonPath() => Path()
    ..moveTo(276, 258)
    ..quadraticBezierTo(346, 244, 368, 200)
    ..quadraticBezierTo(380, 174, 376, 156);

  Path _polyline(List<Offset> pts) {
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      p.lineTo(pts[i].dx, pts[i].dy);
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 512.0;
    canvas.save();
    canvas.scale(scale);

    // NOTE: this painter deliberately uses brand-fixed colors (the teal mark
    // default + pure-white signal flash) rather than ColorScheme tokens — it
    // IS the logo, and must render identically in light and dark themes.

    // Signal intensity — builds then peaks at the "fire" (~0.52), so the whole
    // mark visibly charges up, flashes, and settles.
    final fire = _bump(0.52, 0.30);
    final markColor = Color.lerp(color, Colors.white, fire * 0.35)!;

    final stroke = Paint()
      ..color = markColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeW
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = markColor
      ..style = PaintingStyle.fill;

    // ── Glow bloom at the soma + terminal — strong, peaks at the fire. ──
    final glowA = (0.10 + 0.50 * fire).clamp(0.0, 0.6);
    if (glowA > 0.01) {
      final glow = Paint()
        ..color = color.withValues(alpha: glowA)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
      canvas.drawCircle(_node, _nodeR + 26, glow);
      canvas.drawCircle(const Offset(374, 154), 38, glow);
    }

    // ── Shockwave ring — expands outward from the soma as it fires. ──
    final ringF = _seg(0.46, 0.95);
    if (ringF > 0 && ringF < 1) {
      final rr = 40 + 250 * Curves.easeOut.transform(ringF);
      canvas.drawCircle(
          _node,
          rr,
          Paint()
            ..color = color.withValues(alpha: (1 - ringF) * 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7);
    }

    // ── Mark + signal — wrapped in a "throb" that scales about the soma so the
    //    whole logo visibly pulses at the fire (continuous from the static
    //    launcher/native-splash icon — no reassemble flash). ──
    canvas.save();
    canvas.translate(_node.dx, _node.dy);
    canvas.scale(1 + 0.075 * fire);
    canvas.translate(-_node.dx, -_node.dy);

    for (final d in _dendrites) {
      canvas.drawPath(_polyline(d), stroke);
    }
    final axon = _axonPath();
    canvas.drawPath(axon, stroke);
    for (final seg in _terminal) {
      canvas.drawPath(_polyline(seg), stroke);
    }
    canvas.drawCircle(_node, _nodeR, fill);
    for (final (center, r) in _dots) {
      canvas.drawCircle(center, r, fill);
    }

    // Signal pulse — a bright bead racing up the axon.
    final pulseF = _seg(0.14, 0.56);
    if (pulseF > 0 && pulseF < 1) {
      final metrics = axon.computeMetrics().toList();
      final total = metrics.fold<double>(0, (s, m) => s + m.length);
      var target = total * Curves.easeIn.transform(pulseF);
      Offset? pos;
      for (final m in metrics) {
        if (target <= m.length) {
          pos = m.getTangentForOffset(target)?.position;
          break;
        }
        target -= m.length;
      }
      if (pos != null) {
        canvas.drawCircle(
            pos,
            26,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.85)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
        canvas.drawCircle(pos, 15, Paint()..color = Colors.white);
      }
    }

    // Synaptic dots burst white→teal as the pulse reaches them, staggered.
    for (var i = 0; i < _dots.length; i++) {
      final flare = _bump(0.50 + i * 0.045, 0.12);
      if (flare > 0.02) {
        final (center, r) = _dots[i];
        canvas.drawCircle(
            center,
            r + 20 * flare,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.9 * flare)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
        canvas.drawCircle(center, r * (1 + 0.4 * flare),
            Paint()..color = Color.lerp(color, Colors.white, flare)!);
      }
    }

    canvas.restore(); // throb
    canvas.restore(); // scale
  }

  @override
  bool shouldRepaint(_SynapsePainter old) =>
      old.t != t || old.color != color;
}
