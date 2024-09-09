import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class ImageWithLines extends StatelessWidget {
  final ui.Image? image;
  final double pitch;
  final double yaw;
  final double roll;
  final double base_pitch;
  final double base_yaw;
  final double base_roll;
  final double tolerance;
  final double? x;
  final double? y;
  final double size;
  final double light;
  final double weight;

  ImageWithLines({
    required this.image,
    required this.pitch,
    required this.yaw,
    required this.roll,
    required this.base_pitch,
    required this.base_yaw,
    required this.base_roll,
    required this.tolerance,
    this.x,
    this.y,
    this.size = 150,
    this.light = 1.0,
    this.weight = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter:
          LinePainter(image, pitch, yaw, roll, x, y, size, light, weight),
      painter: TolerancePainter(base_pitch, base_yaw, base_roll, tolerance, x,
          y, size, light, weight),
      size: Size(224, 224),
    );
  }
}

class LinePainter extends CustomPainter {
  final ui.Image? image;
  final double pitch;
  final double yaw;
  final double roll;
  final double? x; // x-coordinate of the axis
  final double? y; // y-coordinate of the axis
  final double size; // size of the axis
  final double light; // light intensity
  final double weight; // weight of the axis

  LinePainter(this.image, this.pitch, this.yaw, this.roll, this.x, this.y,
      this.size, this.light, this.weight);

  @override
  void paint(Canvas canvas, Size size) {
    /// Paints the canvas with the axis.
    ///
    /// This method is responsible for painting the axis on the given [canvas] with the specified [size].
    /// It is called by the Flutter framework to draw the axis on the screen.
    ///
    /// Parameters:
    /// - [canvas]: The canvas on which to paint the axis.
    /// - [size]: The size of the canvas.
    ///
    /// Returns:
    /// This method does not return anything.
    print('Painting axis');

    double pitchRad = pitch * pi / 180;
    double yawRad = -yaw * pi / 180;
    double rollRad = roll * pi / 180;

    double centerX = x ?? size.width / 2;
    double centerY = y ?? size.height / 2;

    double x1 = this.size * (cos(yawRad) * cos(rollRad)) + centerX;
    double y1 = this.size *
            (cos(pitchRad) * sin(rollRad) +
                sin(pitchRad) * sin(yawRad) * cos(rollRad)) +
        centerY;

    double x2 = -this.size * (-sin(rollRad) * cos(yawRad)) + centerX;
    double y2 = -this.size *
            (cos(rollRad) * cos(pitchRad) -
                sin(pitchRad) * sin(yawRad) * sin(rollRad)) +
        centerY;

    double x3 = this.size * (sin(yawRad)) + centerX;
    double y3 = this.size * (-sin(pitchRad) * cos(yawRad)) + centerY;

    final paint1 = Paint()
      ..color = Colors.red.withOpacity(light)
      ..strokeWidth = weight;

    final paint2 = Paint()
      ..color = Colors.green.withOpacity(light)
      ..strokeWidth = weight;

    final paint3 = Paint()
      ..color = Colors.blue.withOpacity(light)
      ..strokeWidth = weight;

    canvas.drawLine(Offset(centerX, centerY), Offset(x1, y1), paint1);
    canvas.drawLine(Offset(centerX, centerY), Offset(x2, y2), paint2);
    canvas.drawLine(Offset(centerX, centerY), Offset(x3, y3), paint3);
  }

  @override
  bool shouldRepaint(covariant LinePainter oldDelegate) {
    return oldDelegate.pitch != pitch ||
        oldDelegate.yaw != yaw ||
        oldDelegate.roll != roll;
  }
}

class TolerancePainter extends CustomPainter {
  final double pitch;
  final double yaw;
  final double roll;
  final double tolerance;
  final double? x;
  final double? y;
  final double size;
  final double light;
  final double weight;

  TolerancePainter(this.pitch, this.yaw, this.roll, this.tolerance, this.x,
      this.y, this.size, this.light, this.weight);

  @override
  void paint(Canvas canvas, Size size) {
    print('Painting tolerance axis');

    double pitchRad = pitch * pi / 180;
    double yawRad = -yaw * pi / 180;
    double rollRad = roll * pi / 180;

    double centerX = x ?? size.width / 2;
    double centerY = y ?? size.height / 2;

    // Draw tolerance lines for ± tolerance range

    if (tolerance == 0) {
      double x1 = this.size * (cos(yawRad) * cos(rollRad)) + centerX;
      double y1 = this.size *
              (cos(pitchRad) * sin(rollRad) +
                  sin(pitchRad) * sin(yawRad) * cos(rollRad)) +
          centerY;
      double x2 = -this.size * (-sin(rollRad) * cos(yawRad)) + centerX;
      double y2 = -this.size *
              (cos(rollRad) * cos(pitchRad) -
                  sin(pitchRad) * sin(yawRad) * sin(rollRad)) +
          centerY;
      double x3 = this.size * (sin(yawRad)) + centerX;
      double y3 = this.size * (-sin(pitchRad) * cos(yawRad)) + centerY;

      final paint1 = Paint()
        ..color = Colors.red.withOpacity(light * 0.5)
        ..strokeWidth = weight;

      final paint2 = Paint()
        ..color = Colors.green.withOpacity(light * 0.5)
        ..strokeWidth = weight;

      final paint3 = Paint()
        ..color = Colors.blue.withOpacity(light * 0.5)
        ..strokeWidth = weight;

      canvas.drawLine(Offset(centerX, centerY), Offset(x1, y1), paint1);
      canvas.drawLine(Offset(centerX, centerY), Offset(x2, y2), paint2);
      canvas.drawLine(Offset(centerX, centerY), Offset(x3, y3), paint3);
      return;
    }
    for (double t = -tolerance; t <= tolerance; t += tolerance / 8) {
      double pitchOffset, yawOffset, rollOffset;

      for (int i = 1; i <= 8; i++) {
        switch (i) {
          case 1:
            pitchOffset = (pitch + t) * pi / 180;
            yawOffset = -(yaw) * pi / 180;
            rollOffset = (roll) * pi / 180;
            break;
          case 2:
            pitchOffset = (pitch) * pi / 180;
            yawOffset = -(yaw + t) * pi / 180;
            rollOffset = (roll) * pi / 180;
            break;
          case 3:
            pitchOffset = (pitch) * pi / 180;
            yawOffset = -(yaw) * pi / 180;
            rollOffset = (roll + t) * pi / 180;
            break;
          case 4:
            pitchOffset = (pitch + t) * pi / 180;
            yawOffset = -(yaw + t) * pi / 180;
            rollOffset = (roll) * pi / 180;
            break;
          case 5:
            pitchOffset = (pitch + t) * pi / 180;
            yawOffset = -(yaw) * pi / 180;
            rollOffset = (roll + t) * pi / 180;
            break;
          case 6:
            pitchOffset = (pitch) * pi / 180;
            yawOffset = -(yaw + t) * pi / 180;
            rollOffset = (roll + t) * pi / 180;
            break;
          case 7:
            pitchOffset = (pitch + t) * pi / 180;
            yawOffset = -(yaw + t) * pi / 180;
            rollOffset = (roll + t) * pi / 180;
            break;
          case 8:
          default:
            pitchOffset = (pitch) * pi / 180;
            yawOffset = -(yaw) * pi / 180;
            rollOffset = (roll) * pi / 180;
            break;
        }

        double x1 = this.size * (cos(yawOffset) * cos(rollOffset)) + centerX;
        double y1 = this.size *
                (cos(pitchOffset) * sin(rollOffset) +
                    sin(pitchOffset) * sin(yawOffset) * cos(rollOffset)) +
            centerY;

        double x2 = -this.size * (-sin(rollOffset) * cos(yawOffset)) + centerX;
        double y2 = -this.size *
                (cos(rollOffset) * cos(pitchOffset) -
                    sin(pitchOffset) * sin(yawOffset) * sin(rollOffset)) +
            centerY;

        double x3 = this.size * (sin(yawOffset)) + centerX;
        double y3 = this.size * (-sin(pitchOffset) * cos(yawOffset)) + centerY;

        final paint1 = Paint()
          ..color = Colors.red.withOpacity(
              light * 0.5) // Make the tolerance lines more transparent
          ..strokeWidth = weight * 0.2;

        final paint2 = Paint()
          ..color = Colors.green.withOpacity(light * 0.5)
          ..strokeWidth = weight * 0.2;

        final paint3 = Paint()
          ..color = Colors.blue.withOpacity(light * 0.5)
          ..strokeWidth = weight * 0.2;

        canvas.drawLine(Offset(centerX, centerY), Offset(x1, y1), paint1);
        canvas.drawLine(Offset(centerX, centerY), Offset(x2, y2), paint2);
        canvas.drawLine(Offset(centerX, centerY), Offset(x3, y3), paint3);
      }
    }
  }

  @override
  bool shouldRepaint(covariant TolerancePainter oldDelegate) {
    return (oldDelegate.pitch != pitch ||
            oldDelegate.yaw != yaw ||
            oldDelegate.roll != roll ||
            oldDelegate.tolerance != tolerance) &&
        tolerance > 0;
  }
}
