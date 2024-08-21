import 'package:camera/camera.dart';

import 'dart:typed_data';
import 'package:image/image.dart' as imglib;
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/services.dart';

Future<ui.Image> convertToUiImage(imglib.Image img) async {
  final completer = Completer<ui.Image>();
  final bytes = Uint8List.fromList(img.getBytes());
  ui.decodeImageFromPixels(
    bytes,
    img.width,
    img.height,
    ui.PixelFormat.rgba8888,
    (ui.Image img) {
      completer.complete(img);
    },
  );
  return completer.future;
}

imglib.Image convertYUV420toRGBImage(CameraImage image) {
  final int width = image.width;
  final int height = image.height;
  final int uvRowStride = image.planes[1].bytesPerRow;
  final int uvPixelStride = image.planes[1].bytesPerPixel!;

  // Create a Uint8List to hold the RGB data
  final Uint8List rgb = Uint8List(width * height * 3);

  // Precompute the UV indices
  final List<int> uvIndices = List<int>.generate(
    width ~/ 2,
    (x) => uvPixelStride * x,
  );

  int rgbIndex = 0;
  for (int y = 0; y < height; y++) {
    int uvIndex = uvRowStride * (y ~/ 2);

    for (int x = 0; x < width; x++) {
      final int yValue = image.planes[0].bytes[y * width + x];
      final int uValue = image.planes[1].bytes[uvIndex + uvIndices[x ~/ 2]];
      final int vValue = image.planes[2].bytes[uvIndex + uvIndices[x ~/ 2]];

      // Inline YUV to RGB conversion
      int r = (yValue + 1.402 * (vValue - 128)).toInt().clamp(0, 255);
      int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))
          .toInt()
          .clamp(0, 255);
      int b = (yValue + 1.772 * (uValue - 128)).toInt().clamp(0, 255);

      // Store RGB values
      rgb[rgbIndex++] = r;
      rgb[rgbIndex++] = g;
      rgb[rgbIndex++] = b;
    }
  }

  // Create image and rotate
  final imglib.Image img =
      imglib.Image.fromBytes(width, height, rgb, format: imglib.Format.rgb);
  // mirror image
  imglib.flip(img, imglib.Flip.vertical);
  return imglib.copyRotate(img, -90);
}

List<int> rgbToBgr(List<int> rgb) {
  return [rgb[2], rgb[1], rgb[0]];
}

int _yuvToRgb(int y, int u, int v) {
  int r = (y + 1.402 * (v - 128)).toInt();
  int g = (y - 0.344136 * (u - 128) - 0.714136 * (v - 128)).toInt();
  int b = (y + 1.772 * (u - 128)).toInt();

  r = r.clamp(0, 255);
  g = g.clamp(0, 255);
  b = b.clamp(0, 255);

  List<int> rgb = rgbToBgr([r, g, b]);
  r = rgb[0];
  g = rgb[1];
  b = rgb[2];

  return 0xff000000 | (r << 16) | (g << 8) | b;
}

imglib.Image square_crop(imglib.Image img, double zoom, double scrollXPercent,
    double scrollYPercent) {
  // Calculate the smallest dimension of the image
  int minDimension = img.width < img.height ? img.width : img.height;

  // Calculate the size of the crop area based on zoom
  int size = (minDimension / zoom).toInt();

  // Calculate the scroll offsets in pixels
  int scrollX = (scrollXPercent * (img.width - size)).toInt();
  int scrollY = (scrollYPercent * (img.height - size)).toInt();

  // Calculate the initial crop coordinates
  int x = ((img.width - size) ~/ 2) + scrollX;
  int y = ((img.height - size) ~/ 2) + scrollY;

  // Ensure the crop area does not exceed image boundaries
  x = x.clamp(0, img.width - size);
  y = y.clamp(0, img.height - size);

  return imglib.copyCrop(img, x, y, size, size);
}
