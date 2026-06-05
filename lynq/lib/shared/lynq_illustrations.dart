import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
//  Lynq Illustrations — Flat-vector CustomPaint art
//  Matches the reference design style: minimal outlines,
//  warm skin tones, soft backgrounds, flat shapes.
// ─────────────────────────────────────────────────────────────

/// Person working at desk with laptop — used on event/announcement cards
class LynqWorkingIllustration extends StatelessWidget {
  final Color shirtColor;
  final Color deskColor;
  final bool isDark;

  const LynqWorkingIllustration({
    super.key,
    this.shirtColor = const Color(0xFFD97D55),
    this.deskColor = const Color(0xFFFFFFFF),
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: CustomPaint(
        painter: _WorkingPainter(
          shirtColor: shirtColor,
          deskColor: deskColor,
          isDark: isDark,
        ),
      ),
    );
  }
}

class _WorkingPainter extends CustomPainter {
  final Color shirtColor;
  final Color deskColor;
  final bool isDark;

  _WorkingPainter({
    required this.shirtColor,
    required this.deskColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final outlineColor = isDark ? const Color(0xFFE0E0E0) : const Color(0xFF1A1A1A);
    final skinColor = const Color(0xFFFBD5B5);

    // Ground shadow ellipse
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.88), width: w * 0.65, height: h * 0.06),
      Paint()..color = outlineColor.withOpacity(0.07),
    );

    // ── Desk ──
    final deskFill = Paint()..color = deskColor.withOpacity(isDark ? 0.2 : 1.0);
    final deskStroke = Paint()
      ..color = outlineColor.withOpacity(0.5)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    final deskRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.10, h * 0.52, w * 0.80, h * 0.07),
      const Radius.circular(3),
    );
    canvas.drawRRect(deskRect, deskFill);
    canvas.drawRRect(deskRect, deskStroke);

    // Desk legs
    final legPaint = Paint()
      ..color = outlineColor.withOpacity(0.4)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(w * 0.18, h * 0.59), Offset(w * 0.18, h * 0.86), legPaint);
    canvas.drawLine(Offset(w * 0.82, h * 0.59), Offset(w * 0.82, h * 0.86), legPaint);
    // Cross brace
    canvas.drawLine(Offset(w * 0.18, h * 0.74), Offset(w * 0.82, h * 0.74), legPaint..strokeWidth = 1.2);

    // ── Coffee mug ──
    final mugFill = Paint()..color = const Color(0xFFFAD19B);
    final mugStroke = Paint()
      ..color = outlineColor.withOpacity(0.45)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final mugRect = Rect.fromLTWH(w * 0.20, h * 0.44, w * 0.08, h * 0.09);
    canvas.drawRRect(
      RRect.fromRectAndRadius(mugRect, const Radius.circular(2)),
      mugFill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(mugRect, const Radius.circular(2)),
      mugStroke,
    );
    // Mug handle arc
    canvas.drawArc(
      Rect.fromLTWH(w * 0.16, h * 0.47, w * 0.06, h * 0.05),
      1.4, 3.2, false, mugStroke,
    );
    // Steam
    final steamPaint = Paint()
      ..color = outlineColor.withOpacity(0.25)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawArc(Rect.fromLTWH(w * 0.22, h * 0.37, w * 0.025, h * 0.06), 3.14, 1.8, false, steamPaint);
    canvas.drawArc(Rect.fromLTWH(w * 0.26, h * 0.36, w * 0.025, h * 0.06), 3.14, 1.8, false, steamPaint);

    // ── Laptop screen ──
    final screenFill = Paint()..color = const Color(0xFFB8D4E8).withOpacity(isDark ? 0.7 : 1.0);
    final screenStroke = Paint()
      ..color = outlineColor.withOpacity(0.5)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final screenPath = Path()
      ..moveTo(w * 0.40, h * 0.52)
      ..lineTo(w * 0.43, h * 0.36)
      ..lineTo(w * 0.72, h * 0.36)
      ..lineTo(w * 0.69, h * 0.52)
      ..close();
    canvas.drawPath(screenPath, screenFill);
    canvas.drawPath(screenPath, screenStroke);
    // Laptop base
    canvas.drawLine(Offset(w * 0.37, h * 0.52), Offset(w * 0.72, h * 0.52), screenStroke);
    // Screen UI lines (decoration)
    final uiLinePaint = Paint()
      ..color = outlineColor.withOpacity(0.15)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 3; i++) {
      final y = h * (0.40 + i * 0.035);
      canvas.drawLine(Offset(w * 0.47, y), Offset(w * 0.68, y), uiLinePaint);
    }

    // ── Person body ──
    // Torso (shirt)
    final torsoFill = Paint()..color = shirtColor;
    final torsoStroke = Paint()
      ..color = outlineColor.withOpacity(0.6)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    final torsoPath = Path()
      ..moveTo(w * 0.44, h * 0.52)
      ..lineTo(w * 0.40, h * 0.34)
      ..quadraticBezierTo(w * 0.50, h * 0.30, w * 0.62, h * 0.34)
      ..lineTo(w * 0.58, h * 0.52)
      ..close();
    canvas.drawPath(torsoPath, torsoFill);
    canvas.drawPath(torsoPath, torsoStroke);

    // Arms
    final armPath = Path()
      ..moveTo(w * 0.40, h * 0.38)
      ..quadraticBezierTo(w * 0.33, h * 0.45, w * 0.37, h * 0.52);
    canvas.drawPath(armPath, torsoStroke..strokeWidth = 6.0);
    final armPath2 = Path()
      ..moveTo(w * 0.62, h * 0.38)
      ..quadraticBezierTo(w * 0.69, h * 0.44, w * 0.64, h * 0.52);
    canvas.drawPath(armPath2, torsoStroke..strokeWidth = 6.0);

    // Hands
    canvas.drawCircle(Offset(w * 0.37, h * 0.525), w * 0.025, Paint()..color = skinColor);
    canvas.drawCircle(Offset(w * 0.64, h * 0.525), w * 0.025, Paint()..color = skinColor);

    // Head
    canvas.drawCircle(
      Offset(w * 0.51, h * 0.22),
      w * 0.10,
      Paint()..color = skinColor,
    );
    canvas.drawCircle(
      Offset(w * 0.51, h * 0.22),
      w * 0.10,
      torsoStroke..strokeWidth = 2.0,
    );

    // Hair
    final hairPaint = Paint()..color = const Color(0xFF2B1C12);
    canvas.drawArc(
      Rect.fromCenter(center: Offset(w * 0.51, h * 0.22), width: w * 0.22, height: w * 0.22),
      3.14, 3.14, true, hairPaint,
    );
    // Hair side strands
    canvas.drawArc(
      Rect.fromLTWH(w * 0.40, h * 0.20, w * 0.05, h * 0.08),
      1.5, 1.5, false, hairPaint..style = PaintingStyle.fill,
    );
    canvas.drawArc(
      Rect.fromLTWH(w * 0.55, h * 0.20, w * 0.05, h * 0.08),
      1.7, 1.5, false, hairPaint,
    );

    // Eyes
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.47, h * 0.225), width: 5, height: 3.5),
        Paint()..color = const Color(0xFF2B1C12));
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.55, h * 0.225), width: 5, height: 3.5),
        Paint()..color = const Color(0xFF2B1C12));

    // Smile
    canvas.drawArc(
      Rect.fromCenter(center: Offset(w * 0.51, h * 0.25), width: w * 0.07, height: h * 0.03),
      0, 3.14, false,
      Paint()
        ..color = const Color(0xFF2B1C12).withOpacity(0.6)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _WorkingPainter old) =>
      old.shirtColor != shirtColor || old.isDark != isDark;
}

// ─────────────────────────────────────────────────────────────

/// Person giving a presentation — used for empty states / splash
class LynqPresentationIllustration extends StatelessWidget {
  final Color shirtColor;
  final bool isDark;

  const LynqPresentationIllustration({
    super.key,
    this.shirtColor = const Color(0xFF6FA4AF),
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PresentationPainter(shirtColor: shirtColor, isDark: isDark),
      child: const SizedBox.expand(),
    );
  }
}

class _PresentationPainter extends CustomPainter {
  final Color shirtColor;
  final bool isDark;
  _PresentationPainter({required this.shirtColor, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final outline = isDark ? const Color(0xFFDDDDDD) : const Color(0xFF1A1A1A);
    final skin = const Color(0xFFFBD5B5);

    // Soft background halo
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.45),
      w * 0.45,
      Paint()..color = shirtColor.withOpacity(0.10),
    );

    // Ground shadow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.90), width: w * 0.55, height: h * 0.05),
      Paint()..color = outline.withOpacity(0.07),
    );

    // Board / presentation screen
    final boardFill = Paint()..color = const Color(0xFFE8EEF4);
    final boardStroke = Paint()
      ..color = outline.withOpacity(0.45)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.55, h * 0.10, w * 0.38, h * 0.42), const Radius.circular(6)),
      boardFill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.55, h * 0.10, w * 0.38, h * 0.42), const Radius.circular(6)),
      boardStroke,
    );
    // Board lines
    final linePaint = Paint()
      ..color = outline.withOpacity(0.2)
      ..strokeWidth = 1.0;
    for (int i = 0; i < 4; i++) {
      canvas.drawLine(Offset(w * 0.60, h * (0.18 + i * 0.07)), Offset(w * 0.88, h * (0.18 + i * 0.07)), linePaint);
    }
    // Board stand
    canvas.drawLine(Offset(w * 0.74, h * 0.52), Offset(w * 0.74, h * 0.65), boardStroke);
    canvas.drawLine(Offset(w * 0.65, h * 0.65), Offset(w * 0.83, h * 0.65), boardStroke);

    // Person legs (pants)
    final pantsFill = Paint()..color = const Color(0xFF5F7FA8);
    final pantsStroke = Paint()
      ..color = outline.withOpacity(0.5)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    for (int leg = 0; leg < 2; leg++) {
      final dx = leg == 0 ? 0.0 : w * 0.08;
      final legPath = Path()
        ..moveTo(w * 0.24 + dx, h * 0.57)
        ..lineTo(w * 0.21 + dx, h * 0.85)
        ..lineTo(w * 0.30 + dx, h * 0.85)
        ..lineTo(w * 0.33 + dx, h * 0.57)
        ..close();
      canvas.drawPath(legPath, pantsFill);
      canvas.drawPath(legPath, pantsStroke);
    }

    // Feet / shoes
    for (int f = 0; f < 2; f++) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(w * (f == 0 ? 0.25 : 0.34), h * 0.87), width: w * 0.10, height: h * 0.04),
        Paint()..color = const Color(0xFF333333),
      );
    }

    // Torso
    final torsoFill = Paint()..color = shirtColor;
    final torsoStroke = Paint()
      ..color = outline.withOpacity(0.5)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    final torsoPath = Path()
      ..moveTo(w * 0.17, h * 0.57)
      ..lineTo(w * 0.17, h * 0.35)
      ..quadraticBezierTo(w * 0.29, h * 0.31, w * 0.41, h * 0.35)
      ..lineTo(w * 0.41, h * 0.57)
      ..close();
    canvas.drawPath(torsoPath, torsoFill);
    canvas.drawPath(torsoPath, torsoStroke);

    // Raised arm (pointing at board)
    final armPath = Path()
      ..moveTo(w * 0.41, h * 0.40)
      ..quadraticBezierTo(w * 0.52, h * 0.35, w * 0.57, h * 0.28);
    canvas.drawPath(armPath, torsoStroke..strokeWidth = 7.0);
    canvas.drawCircle(Offset(w * 0.57, h * 0.27), w * 0.025, Paint()..color = skin);

    // Other arm (down)
    final arm2 = Path()
      ..moveTo(w * 0.17, h * 0.42)
      ..quadraticBezierTo(w * 0.10, h * 0.50, w * 0.12, h * 0.56);
    canvas.drawPath(arm2, torsoStroke..strokeWidth = 7.0);

    // Head
    canvas.drawCircle(Offset(w * 0.29, h * 0.22), w * 0.10, Paint()..color = skin);
    canvas.drawCircle(Offset(w * 0.29, h * 0.22), w * 0.10, torsoStroke..strokeWidth = 2.0);
    // Hair
    canvas.drawArc(
      Rect.fromCenter(center: Offset(w * 0.29, h * 0.22), width: w * 0.21, height: w * 0.21),
      3.14, 3.14, true,
      Paint()..color = const Color(0xFF2B1C12),
    );
    // Eyes
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.25, h * 0.225), width: 5, height: 3.5),
        Paint()..color = const Color(0xFF2B1C12));
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.33, h * 0.225), width: 5, height: 3.5),
        Paint()..color = const Color(0xFF2B1C12));
  }

  @override
  bool shouldRepaint(covariant _PresentationPainter old) => old.shirtColor != shirtColor;
}

// ─────────────────────────────────────────────────────────────

/// Two people collaborating at a table — used for members/team sections
class LynqTeamIllustration extends StatelessWidget {
  final Color person1Color;
  final Color person2Color;
  final bool isDark;

  const LynqTeamIllustration({
    super.key,
    this.person1Color = const Color(0xFFD97D55),
    this.person2Color = const Color(0xFF6FA4AF),
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TeamPainter(p1: person1Color, p2: person2Color, isDark: isDark),
      child: const SizedBox.expand(),
    );
  }
}

class _TeamPainter extends CustomPainter {
  final Color p1, p2;
  final bool isDark;
  _TeamPainter({required this.p1, required this.p2, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final outline = isDark ? const Color(0xFFDDDDDD) : const Color(0xFF1A1A1A);
    final skin = const Color(0xFFFBD5B5);
    final stroke2 = Paint()
      ..color = outline.withOpacity(0.5)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.90), width: w * 0.75, height: h * 0.05),
      Paint()..color = outline.withOpacity(0.07),
    );

    // Table
    final tableFill = Paint()..color = const Color(0xFFFFFFFF).withOpacity(isDark ? 0.15 : 1.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.20, h * 0.50, w * 0.60, h * 0.07), const Radius.circular(4)),
      tableFill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.20, h * 0.50, w * 0.60, h * 0.07), const Radius.circular(4)),
      stroke2,
    );
    // Table legs
    canvas.drawLine(Offset(w * 0.27, h * 0.57), Offset(w * 0.27, h * 0.82), stroke2);
    canvas.drawLine(Offset(w * 0.73, h * 0.57), Offset(w * 0.73, h * 0.82), stroke2);

    // Person 1 (left)
    _drawPerson(canvas, Offset(w * 0.22, h * 0.50), p1, skin, outline, w, h, flipped: false);
    // Person 2 (right)
    _drawPerson(canvas, Offset(w * 0.78, h * 0.50), p2, skin, outline, w, h, flipped: true);

    // Shared paper/tablet on table
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.40, h * 0.43, w * 0.20, h * 0.08), const Radius.circular(3)),
      Paint()..color = const Color(0xFFE8EEF4),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.40, h * 0.43, w * 0.20, h * 0.08), const Radius.circular(3)),
      stroke2,
    );
  }

  void _drawPerson(Canvas canvas, Offset anchor, Color shirt, Color skin, Color outline, double w, double h, {required bool flipped}) {
    final dir = flipped ? -1.0 : 1.0;
    final stroke = Paint()
      ..color = outline.withOpacity(0.5)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Head
    canvas.drawCircle(
      Offset(anchor.dx, h * 0.28),
      w * 0.085,
      Paint()..color = skin,
    );
    canvas.drawCircle(Offset(anchor.dx, h * 0.28), w * 0.085, stroke);

    // Hair
    canvas.drawArc(
      Rect.fromCenter(center: Offset(anchor.dx, h * 0.28), width: w * 0.18, height: w * 0.18),
      3.14, 3.14, true,
      Paint()..color = const Color(0xFF2B1C12),
    );

    // Eye
    canvas.drawOval(
      Rect.fromCenter(center: Offset(anchor.dx + dir * w * 0.025, h * 0.283), width: 4, height: 3),
      Paint()..color = const Color(0xFF2B1C12),
    );

    // Torso
    final tx = anchor.dx;
    final torso = Path()
      ..moveTo(tx - w * 0.09, h * 0.50)
      ..lineTo(tx - w * 0.07, h * 0.36)
      ..quadraticBezierTo(tx, h * 0.33, tx + w * 0.07, h * 0.36)
      ..lineTo(tx + w * 0.09, h * 0.50)
      ..close();
    canvas.drawPath(torso, Paint()..color = shirt);
    canvas.drawPath(torso, stroke);

    // Arm reaching toward center
    final armPath = Path()
      ..moveTo(tx + dir * w * 0.09, h * 0.40)
      ..quadraticBezierTo(tx + dir * w * 0.17, h * 0.46, tx + dir * w * 0.19, h * 0.51);
    canvas.drawPath(armPath, stroke..strokeWidth = 6.0);
  }

  @override
  bool shouldRepaint(covariant _TeamPainter old) => old.p1 != p1 || old.p2 != p2;
}
