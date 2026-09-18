import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

enum InkArtKind { box, drawer, lost, search, trash, done, star }

/// Boş ekranlardaki küçük çizimler: mürekkep çizgisi, bir parça kiremit ve
/// kağıt tonları. Görsel dosyası yok; her şey burada çiziliyor.
class InkArt extends StatelessWidget {
  const InkArt(this.kind, {super.key, this.size = 128});

  final InkArtKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    return SizedBox(
      width: size,
      height: size * 0.82,
      child: CustomPaint(painter: _InkArtPainter(kind, tones)),
    );
  }
}

class _InkArtPainter extends CustomPainter {
  const _InkArtPainter(this.kind, this.t);

  final InkArtKind kind;
  final Tones t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..color = t.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, w / 64)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final paper = Paint()..color = t.surface;
    final shade = Paint()..color = t.raised;
    final accent = Paint()..color = t.accent;

    // Zemin gölgesi: her çizim bir masanın üstünde duruyor.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.93), width: w * 0.78, height: h * 0.09),
      Paint()..color = t.line,
    );

    switch (kind) {
      case InkArtKind.box:
        // Açık bir koli: gövde, iki kapak ve içinden çıkan bir fiş kartı.
        final body = Rect.fromLTWH(w * 0.2, h * 0.42, w * 0.6, h * 0.46);
        final card = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.36, h * 0.16, w * 0.3, h * 0.36), const Radius.circular(4));
        canvas.save();
        canvas.rotate(-0.08);
        canvas.translate(-w * 0.02, h * 0.04);
        canvas.drawRRect(card, paper);
        canvas.drawRRect(card, stroke);
        canvas.drawLine(Offset(card.left + 6, card.top + h * 0.1), Offset(card.right - 6, card.top + h * 0.1),
            Paint()
              ..color = t.accent
              ..strokeWidth = stroke.strokeWidth * 0.8);
        canvas.restore();
        canvas.drawRect(body, shade);
        canvas.drawRect(body, stroke);
        final left = Path()
          ..moveTo(body.left, body.top)
          ..lineTo(body.left - w * 0.1, body.top - h * 0.14)
          ..lineTo(body.left + w * 0.22, body.top - h * 0.14)
          ..lineTo(body.left + w * 0.3, body.top);
        final right = Path()
          ..moveTo(body.right, body.top)
          ..lineTo(body.right + w * 0.1, body.top - h * 0.14)
          ..lineTo(body.right - w * 0.22, body.top - h * 0.14)
          ..lineTo(body.right - w * 0.3, body.top);
        canvas.drawPath(left, paper);
        canvas.drawPath(left, stroke);
        canvas.drawPath(right, paper);
        canvas.drawPath(right, stroke);
        canvas.drawLine(Offset(w * 0.4, body.top + h * 0.2), Offset(w * 0.6, body.top + h * 0.2), stroke);
        _sparkle(canvas, Offset(w * 0.82, h * 0.2), w * 0.05, accent);
      case InkArtKind.drawer:
        final tray = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.16, h * 0.48, w * 0.68, h * 0.38), const Radius.circular(8));
        final c1 = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.26, h * 0.2, w * 0.4, h * 0.42), const Radius.circular(5));
        canvas.save();
        canvas.translate(w * 0.5, h * 0.4);
        canvas.rotate(0.12);
        canvas.translate(-w * 0.5, -h * 0.4);
        canvas.drawRRect(c1.shift(Offset(w * 0.08, 0)), shade);
        canvas.drawRRect(c1.shift(Offset(w * 0.08, 0)), stroke);
        canvas.restore();
        canvas.drawRRect(c1, paper);
        canvas.drawRRect(c1, stroke);
        canvas.drawRRect(tray, shade);
        canvas.drawRRect(tray, stroke);
        final handle = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(w * 0.5, h * 0.67), width: w * 0.18, height: h * 0.06), const Radius.circular(6));
        canvas.drawRRect(handle, accent);
      case InkArtKind.lost:
      case InkArtKind.search:
        final c = Offset(w * 0.44, h * 0.44);
        final r = h * 0.26;
        canvas.drawCircle(c, r, paper);
        canvas.drawCircle(c, r, stroke);
        final handle = Paint()
          ..color = t.ink
          ..strokeWidth = stroke.strokeWidth * 2.4
          ..strokeCap = StrokeCap.round;
        final a = c + Offset(r * 0.72, r * 0.72);
        canvas.drawLine(a, a + Offset(r * 0.7, r * 0.7), handle);
        if (kind == InkArtKind.lost) {
          final q = TextPainter(
            text: TextSpan(
              text: '?',
              style: TextStyle(fontFamily: kDisplayFont, fontSize: r * 1.2, fontWeight: FontWeight.w700, color: t.accent),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          q.paint(canvas, c - Offset(q.width / 2, q.height / 2));
        } else {
          canvas.drawLine(c + Offset(-r * 0.5, -r * 0.15), c + Offset(r * 0.35, -r * 0.15), stroke);
          canvas.drawLine(c + Offset(-r * 0.5, r * 0.2), c + Offset(r * 0.15, r * 0.2), stroke);
          _sparkle(canvas, Offset(w * 0.8, h * 0.18), w * 0.045, accent);
        }
      case InkArtKind.trash:
        final bin = Path()
          ..moveTo(w * 0.3, h * 0.34)
          ..lineTo(w * 0.34, h * 0.86)
          ..lineTo(w * 0.66, h * 0.86)
          ..lineTo(w * 0.7, h * 0.34)
          ..close();
        canvas.drawPath(bin, shade);
        canvas.drawPath(bin, stroke);
        canvas.drawLine(Offset(w * 0.24, h * 0.3), Offset(w * 0.76, h * 0.3), stroke);
        canvas.drawLine(Offset(w * 0.43, h * 0.24), Offset(w * 0.57, h * 0.24), stroke);
        for (final x in [0.42, 0.5, 0.58]) {
          canvas.drawLine(Offset(w * x, h * 0.44), Offset(w * x, h * 0.76), stroke);
        }
        _sparkle(canvas, Offset(w * 0.82, h * 0.22), w * 0.04, accent);
      case InkArtKind.star:
        // Üstünde yıldız olan bir fiş kartı: sık kullanılanlar.
        final card = RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.22, h * 0.24, w * 0.56, h * 0.58), const Radius.circular(7));
        canvas.save();
        canvas.translate(w * 0.5, h * 0.5);
        canvas.rotate(-0.06);
        canvas.translate(-w * 0.5, -h * 0.5);
        canvas.drawRRect(card, paper);
        canvas.drawRRect(card, stroke);
        canvas.drawLine(Offset(w * 0.22, h * 0.4), Offset(w * 0.78, h * 0.4), stroke);
        canvas.restore();
        _star(canvas, Offset(w * 0.5, h * 0.58), w * 0.17, accent);
        _sparkle(canvas, Offset(w * 0.82, h * 0.2), w * 0.04, accent);
      case InkArtKind.done:
        final c = Offset(w * 0.5, h * 0.46);
        final r = h * 0.3;
        canvas.drawCircle(c, r, Paint()..color = t.accent.withValues(alpha: 0.16));
        canvas.drawCircle(c, r, stroke);
        final tick = Path()
          ..moveTo(c.dx - r * 0.42, c.dy + r * 0.02)
          ..lineTo(c.dx - r * 0.1, c.dy + r * 0.32)
          ..lineTo(c.dx + r * 0.46, c.dy - r * 0.3);
        canvas.drawPath(
          tick,
          Paint()
            ..color = t.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke.strokeWidth * 1.8
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
        _sparkle(canvas, Offset(w * 0.18, h * 0.2), w * 0.035, accent);
        _sparkle(canvas, Offset(w * 0.84, h * 0.72), w * 0.03, accent);
    }
  }

  /// Beş köşeli yıldız.
  void _star(Canvas canvas, Offset c, double r, Paint paint) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final rr = i.isEven ? r : r * 0.44;
      final point = c + Offset(rr * math.cos(angle), rr * math.sin(angle));
      i == 0 ? p.moveTo(point.dx, point.dy) : p.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(p..close(), paint);
  }

  /// Dört köşeli küçük parıltı.
  void _sparkle(Canvas canvas, Offset c, double r, Paint paint) {
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(_InkArtPainter old) => old.kind != kind || old.t != t;
}

/// Boş durum: çizim, serif başlık, kısa açıklama ve isteğe bağlı eylem.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.art,
    required this.title,
    this.body,
    this.action,
    this.artSize = 128,
  });

  final InkArtKind art;
  final String title;
  final String? body;
  final Widget? action;
  final double artSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkArt(art, size: artSize),
              const SizedBox(height: 18),
              Text(title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
              if (body != null) ...[
                const SizedBox(height: 8),
                Text(body!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: Tones.of(context).muted, height: 1.45)),
              ],
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}
