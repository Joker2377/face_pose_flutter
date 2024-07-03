import 'package:camera/camera.dart';
import 'package:face_pose/TFLiteModel.dart';
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

imglib.Image square_crop(
    imglib.Image img, int zoom, double scrollXPercent, double scrollYPercent) {
  int minDimension = img.width < img.height ? img.width : img.height;
  int size = minDimension ~/ zoom;

  int scrollX = (img.width * scrollXPercent).toInt();
  int scrollY = (img.height * scrollYPercent).toInt();

  int x = ((img.width - size) ~/ 2) + scrollX;
  int y = ((img.height - size) ~/ 2) + scrollY;

  x = x.clamp(0, img.width - size);
  y = y.clamp(0, img.height - size);

  return imglib.copyCrop(img, x, y, size, size);
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
  late TFliteModel model;
  bool isModelLoaded = false;

  int _frameCount = 0;
  var processing = false;
  String mes = "nothing yet";
  imglib.Image? _currimg;
  var streaming = false;
  var zoom_factor = 1;
  var scrollX = 0.0, scrollY = 0.0;
  var thres = 0.3;

  @override
  void initState() {
    super.initState();
    _loadModel();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.low,
      enableAudio: false,
    );
    _initializeControllerFuture = _controller.initialize();
    _initializeControllerFuture.then((_) {
      _controller.startImageStream((CameraImage image) {
        if (streaming == true) {
          _frameCount++;
          if (processing == false && isModelLoaded && _frameCount % 7 == 0) {
            _frameCount = 0;
            processing = true;
            _processImage(image);
          } else {
            print('isModelLoaded: $isModelLoaded, processing: $processing');
          }
        } else {
          imglib.Image img = _convertYUV420toRGBImage(image);
          img = square_crop(img, zoom_factor, scrollX, scrollY);
          setState(() {
            _currimg = imglib.copyResize(img, width: 224, height: 224);
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadModel() async {
    model = TFliteModel();
    await model.loadModel();
    isModelLoaded = true;
  }

  Future<void> _processImage(CameraImage image) async {
    int start_time = DateTime.now().millisecondsSinceEpoch;
    imglib.Image img = _convertYUV420toRGBImage(image);
    img = square_crop(img, zoom_factor, scrollX, scrollY);
    _currimg = imglib.copyResize(img, width: 224, height: 224);
    print(
        'Processing time: ${DateTime.now().millisecondsSinceEpoch - start_time} ms');
    start_time = DateTime.now().millisecondsSinceEpoch;
    var pose = await model.predictPose(img);
    processing = false;
    print(
        'Predicting time: ${DateTime.now().millisecondsSinceEpoch - start_time} ms');
    print('Pose: $pose');
    if (pose.isNotEmpty) {
      var pitch = pose['pitch']!.toStringAsFixed(2);
      var yaw = pose['yaw']!.toStringAsFixed(2);
      var roll = pose['roll']!.toStringAsFixed(2);
      setState(() {
        _currimg = _currimg;
        mes = 'Pitch: $pitch, Yaw: $yaw, Roll: $roll';
      });
    } else {
      setState(() {
        mes = 'Detection failed';
      });
    }
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
                  child: _currimg != null
                      ? Image.memory(
                          Uint8List.fromList(
                              imglib.encodeJpg(_currimg!, quality: 10)),
                          gaplessPlayback: true,
                          fit: BoxFit.contain,
                        )
                      : const Center(
                          child: SizedBox(
                              width: 50,
                              height: 50,
                              child: CircularProgressIndicator())),
                ),
                SizedBox(
                  height: 20,
                  child: Text(
                    mes,
                  ),
                ),
                Row(
                  children: [
                    SizedBox(width: 20),
                    Text('Zoom factor: $zoom_factor'),
                    Expanded(
                        child: Slider(
                      min: 1,
                      max: 5,
                      divisions: 4,
                      label: '$zoom_factor',
                      value: zoom_factor.toDouble(),
                      onChanged: streaming
                          ? null
                          : (value) {
                              setState(() {
                                zoom_factor = value.toInt();
                              });
                            },
                    )),
                    SizedBox(width: 10),
                  ],
                ),
                Row(
                  children: [
                    SizedBox(width: 20),
                    Text('Scroll X: $scrollX'),
                    Expanded(
                        child: Slider(
                      min: -10.0,
                      max: 10.0,
                      divisions: 2,
                      label: '$scrollX',
                      value: scrollX.toDouble(),
                      onChanged: streaming
                          ? null
                          : (value) {
                              setState(() {
                                scrollX = value;
                              });
                            },
                    )),
                    SizedBox(width: 10),
                  ],
                ),
                Row(
                  children: [
                    SizedBox(width: 20),
                    Text('Scroll Y: $scrollY'),
                    Expanded(
                        child: Slider(
                      min: -10.0,
                      max: 10.0,
                      divisions: 2,
                      label: '$scrollY',
                      value: scrollY.toDouble(),
                      onChanged: streaming
                          ? null
                          : (value) {
                              setState(() {
                                scrollY = value;
                              });
                            },
                    )),
                    SizedBox(width: 10),
                  ],
                ),
                Row(
                  children: [
                    SizedBox(width: 20),
                    Text('Threshold: $thres'),
                    Expanded(
                        child: Slider(
                      min: 0.0,
                      max: 1.0,
                      divisions: 10,
                      label: '$thres',
                      value: thres.toDouble(),
                      onChanged: streaming
                          ? null
                          : (value) {
                              setState(() {
                                thres = value;
                                model.setThres(thres);
                              });
                            },
                    )),
                    SizedBox(width: 10),
                  ],
                ),
                ButtonBar(
                  alignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          streaming = !streaming;
                          mes = 'nothing yet';
                        });
                      },
                      child: Text(streaming ? 'Stop' : 'Start'),
                    ),
                  ],
                ),
              ],
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}
