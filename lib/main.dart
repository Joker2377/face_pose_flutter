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
  double zoom_factor = 1;
  var scrollX = 0.0, scrollY = 0.0;
  var detected = false;
  var conf_thres = 0.3;

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

          if (processing == false && isModelLoaded && _frameCount % 10 == 0) {
            _frameCount = 0;
            processing = true;
            _processImage(image);
          } else {
            imglib.Image img = _convertYUV420toRGBImage(image);
            img = square_crop(img, zoom_factor, scrollX, scrollY);
            setState(() {
              _currimg = imglib.copyResize(img, width: 224, height: 224);
            });
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
    if (pose.isNotEmpty && pose['confidence']! > conf_thres) {
      var pitch = pose['pitch']!.toStringAsFixed(2);
      var yaw = pose['yaw']!.toStringAsFixed(2);
      var roll = pose['roll']!.toStringAsFixed(2);
      setState(() {
        mes =
            'Pitch: $pitch, Yaw: $yaw, Roll: $roll, Confidence: ${pose['confidence']!.toStringAsFixed(2)}';
        detected = true;
      });
    } else {
      setState(() {
        detected = false;
        mes = 'Detection failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('')),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Column(
              children: [
                Expanded(
                  child: _currimg != null
                      ? Padding(
                          padding:
                              const EdgeInsets.all(0), // Remove any extra space
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: detected
                                      ? Colors.green
                                      : Colors.redAccent, // Set border color
                                  width: 4), // Add border here
                              borderRadius: BorderRadius.circular(
                                  15), // Make the border rounded
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                  10), // Make the image rounded
                              child: Image.memory(
                                Uint8List.fromList(
                                    imglib.encodeJpg(_currimg!, quality: 50)),
                                gaplessPlayback: true,
                                fit: BoxFit
                                    .cover, // Ensure the image covers the entire space
                              ),
                            ),
                          ),
                        )
                      : const Center(
                          child: SizedBox(
                              width: 50,
                              height: 50,
                              child: CircularProgressIndicator())),
                ),
                SizedBox(height: 40),
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
                      divisions: 10,
                      label: '$zoom_factor',
                      value: zoom_factor.toDouble(),
                      onChanged: streaming
                          ? null
                          : (value) {
                              setState(() {
                                zoom_factor = value;
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
                      min: -1.0,
                      max: 1.0,
                      divisions: 20,
                      label: '$scrollX',
                      value: scrollX.toDouble(),
                      onChanged: streaming
                          ? null
                          : (value) {
                              setState(() {
                                scrollX =
                                    double.parse(value.toStringAsFixed(1));
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
                      min: -1.0,
                      max: 1.0,
                      divisions: 20,
                      label: '$scrollY',
                      value: scrollY.toDouble(),
                      onChanged: streaming
                          ? null
                          : (value) {
                              setState(() {
                                scrollY =
                                    double.parse(value.toStringAsFixed(1));
                              });
                            },
                    )),
                    SizedBox(width: 10),
                  ],
                ),
                Row(
                  children: [
                    SizedBox(width: 20),
                    Text('threshold: $conf_thres'),
                    Expanded(
                        child: Slider(
                      min: 0.1,
                      max: 1.0,
                      divisions: 9,
                      label: '$conf_thres',
                      value: conf_thres,
                      onChanged: streaming
                          ? null
                          : (value) {
                              setState(() {
                                conf_thres = value;
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
                          detected = false;
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
