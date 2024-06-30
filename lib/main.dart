import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as imglib;

imglib.Image _convertYUV420toRGBImage(CameraImage image) {
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front);
  runApp(MyApp(camera: frontCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;

  const MyApp({Key? key, required this.camera}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: CameraScreen(camera: camera),
    );
  }
}

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;

  const CameraScreen({Key? key, required this.camera}) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  int _frameCount = 0;
  Uint8List? _imgBytes;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.low,
      enableAudio: false,
    );
    _initializeControllerFuture = _controller.initialize();
    _initializeControllerFuture.then((_) {
      _controller.startImageStream((CameraImage image) {
        _frameCount++;
        if (_frameCount % 100 == 0) {
          _processImage(image);
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _processImage(CameraImage image) async {
    int start_time = DateTime.now().millisecondsSinceEpoch;
    imglib.Image img = _convertYUV420toRGBImage(image);
    print(
        'Processing time: ${DateTime.now().millisecondsSinceEpoch - start_time} ms');
    start_time = DateTime.now().millisecondsSinceEpoch;
    Uint8List imgBytes = Uint8List.fromList(imglib.encodePng(img, level: 0));
    print(
        'Encoding time: ${DateTime.now().millisecondsSinceEpoch - start_time} ms');
    setState(() {
      _imgBytes = imgBytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Camera App')),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Column(
              children: [
                Expanded(
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: Container(
                          width: MediaQuery.of(context).size.width,
                          height: MediaQuery.of(context).size.width *
                              _controller.value.aspectRatio,
                          child: CameraPreview(_controller),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _imgBytes != null
                      ? Image.memory(
                          _imgBytes!,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: Colors.black,
                          child: Center(
                            child: Text(
                              'No image yet',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                ),
              ],
            );
          } else {
            return Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}
