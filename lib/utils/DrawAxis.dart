import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class ImageWithLines extends StatelessWidget {
  final ui.Image? image;
  final double pitch;
  final double yaw;
  final double roll;
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
    this.x,
    this.y,
    this.size = 150,
    this.light = 1.0,
    this.weight = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: LinePainter(image, pitch, yaw, roll, x, y, size, light, weight),
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
