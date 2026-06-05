import 'package:flutter/material.dart';

class MlynqOnboardingIllustration extends StatelessWidget {
  const MlynqOnboardingIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 260,
      width: double.infinity,
      child: CustomPaint(
        painter: _OnboardingIllustrationPainter(),
      ),
    );
  }
}

class MlynqDeskIllustration extends StatelessWidget {
  final Color baseColor;
  const MlynqDeskIllustration({super.key, required this.baseColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      width: 150,
      child: CustomPaint(
        painter: _DeskIllustrationPainter(baseColor),
      ),
    );
  }
}

class _OnboardingIllustrationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);

    // Draw background soft halo circle
    final haloPaint = Paint()
      ..color = const Color(0xFFDCEAF5).withOpacity(0.5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(center.dx, center.dy + 10), 100, haloPaint);

    // Desk Base Line / Shadow
    final floorPaint = Paint()
      ..color = const Color(0xFFC5D9EB)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(w * 0.15, h * 0.85), Offset(w * 0.85, h * 0.85), floorPaint);

    // Table
    final tablePaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;
    final tableBorderPaint = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final tableRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.2, h * 0.55, w * 0.6, 12),
      const Radius.circular(4),
    );
    canvas.drawRRect(tableRect, tablePaint);
    canvas.drawRRect(tableRect, tableBorderPaint);

    // Table legs
    final legPaint = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    
    // Left Leg
    canvas.drawLine(Offset(w * 0.25, h * 0.6), Offset(w * 0.25, h * 0.85), legPaint);
    // Right Leg
    canvas.drawLine(Offset(w * 0.75, h * 0.6), Offset(w * 0.75, h * 0.85), legPaint);
    // Middle bracing leg
    canvas.drawLine(Offset(w * 0.45, h * 0.6), Offset(w * 0.45, h * 0.85), legPaint);

    // Laptop
    final laptopPaint = Paint()
      ..color = const Color(0xFF5F85A2)
      ..style = PaintingStyle.fill;
    final laptopBorderPaint = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Laptop Screen
    final screenPath = Path()
      ..moveTo(w * 0.45, h * 0.55)
      ..lineTo(w * 0.47, h * 0.44)
      ..lineTo(w * 0.57, h * 0.44)
      ..lineTo(w * 0.55, h * 0.55)
      ..close();
    canvas.drawPath(screenPath, laptopPaint);
    canvas.drawPath(screenPath, laptopBorderPaint);

    // Laptop Keyboard Base
    canvas.drawLine(Offset(w * 0.43, h * 0.55), Offset(w * 0.57, h * 0.55), laptopBorderPaint);

    // Coffee Mug
    final mugPaint = Paint()
      ..color = const Color(0xFFFAD19B)
      ..style = PaintingStyle.fill;
    final mugBorderPaint = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    
    final mugRect = Rect.fromLTWH(w * 0.28, h * 0.5, 12, 14);
    canvas.drawRect(mugRect, mugPaint);
    canvas.drawRect(mugRect, mugBorderPaint);
    // Mug handle
    canvas.drawArc(Rect.fromLTWH(w * 0.26, h * 0.52, 6, 8), 1.5, 3.14, false, mugBorderPaint);
    // Steam
    final steamPaint = Paint()
      ..color = const Color(0xFF111111).withOpacity(0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawArc(Rect.fromLTWH(w * 0.29, h * 0.45, 4, 8), 3.14, 1.5, false, steamPaint);

    // Person (Simplistic Cartoon Minimalist Outline)
    final bodyPaint = Paint()
      ..color = const Color(0xFFD97D55) // Salmon shirt
      ..style = PaintingStyle.fill;
    final bodyBorder = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    // Head (Circle)
    canvas.drawCircle(Offset(center.dx, h * 0.28), 16, Paint()..color = const Color(0xFFFBE4D5)); // Skin
    canvas.drawCircle(Offset(center.dx, h * 0.28), 16, bodyBorder);
    
    // Hair
    final hairPaint = Paint()..color = const Color(0xFF111111);
    canvas.drawArc(Rect.fromLTWH(center.dx - 17, h * 0.28 - 18, 34, 20), 3.14, 3.14, true, hairPaint);

    // Body/Torso
    final torsoPath = Path()
      ..moveTo(center.dx - 22, h * 0.55)
      ..lineTo(center.dx - 22, h * 0.38)
      ..quadraticBezierTo(center.dx, h * 0.35, center.dx + 22, h * 0.38)
      ..lineTo(center.dx + 22, h * 0.55)
      ..close();
    canvas.drawPath(torsoPath, bodyPaint);
    canvas.drawPath(torsoPath, bodyBorder);

    // Legs
    final legsPaint = Paint()
      ..color = const Color(0xFF5F85A2)
      ..style = PaintingStyle.fill;
    
    final legsPath = Path()
      ..moveTo(center.dx - 18, h * 0.55)
      ..lineTo(center.dx - 15, h * 0.76)
      ..lineTo(center.dx - 5, h * 0.76)
      ..lineTo(center.dx - 2, h * 0.55)
      ..close();
    canvas.drawPath(legsPath, legsPaint);
    canvas.drawPath(legsPath, bodyBorder);

    final leg2Path = Path()
      ..moveTo(center.dx + 2, h * 0.55)
      ..lineTo(center.dx + 5, h * 0.76)
      ..lineTo(center.dx + 15, h * 0.76)
      ..lineTo(center.dx + 18, h * 0.55)
      ..close();
    canvas.drawPath(leg2Path, legsPaint);
    canvas.drawPath(leg2Path, bodyBorder);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DeskIllustrationPainter extends CustomPainter {
  final Color baseColor;
  _DeskIllustrationPainter(this.baseColor);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);

    final deskShadow = Paint()
      ..color = const Color(0xFF111111).withOpacity(0.08)
      ..style = PaintingStyle.fill;
    canvas.drawOval(Rect.fromLTWH(w * 0.1, h * 0.75, w * 0.8, 12), deskShadow);

    // Table
    final tablePaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final tableRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.15, h * 0.5, w * 0.7, 8),
      const Radius.circular(3),
    );
    canvas.drawRRect(tableRect, tablePaint);
    canvas.drawRRect(tableRect, borderPaint);

    // Table legs
    canvas.drawLine(Offset(w * 0.22, h * 0.54), Offset(w * 0.22, h * 0.78), borderPaint);
    canvas.drawLine(Offset(w * 0.78, h * 0.54), Offset(w * 0.78, h * 0.78), borderPaint);

    // Person working (Minimal)
    final headPaint = Paint()..color = const Color(0xFFFBE4D5);
    canvas.drawCircle(Offset(center.dx + 12, h * 0.24), 10, headPaint);
    canvas.drawCircle(Offset(center.dx + 12, h * 0.24), 10, borderPaint);

    // Hair
    canvas.drawArc(Rect.fromLTWH(center.dx + 1, h * 0.24 - 11, 22, 12), 3.14, 3.14, true, Paint()..color = const Color(0xFF111111));

    // Torso
    final torso = Path()
      ..moveTo(center.dx - 2, h * 0.5)
      ..lineTo(center.dx - 2, h * 0.32)
      ..quadraticBezierTo(center.dx + 12, h * 0.28, center.dx + 22, h * 0.34)
      ..lineTo(center.dx + 20, h * 0.5)
      ..close();
    canvas.drawPath(torso, Paint()..color = baseColor);
    canvas.drawPath(torso, borderPaint);

    // Small Laptop
    final laptopPath = Path()
      ..moveTo(center.dx - 18, h * 0.5)
      ..lineTo(center.dx - 22, h * 0.38)
      ..lineTo(center.dx - 8, h * 0.38)
      ..lineTo(center.dx - 10, h * 0.5)
      ..close();
    canvas.drawPath(laptopPath, Paint()..color = const Color(0xFFEBF3FC));
    canvas.drawPath(laptopPath, borderPaint);
    canvas.drawLine(Offset(center.dx - 24, h * 0.5), Offset(center.dx - 8, h * 0.5), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
