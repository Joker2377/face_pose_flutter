import 'package:camera/camera.dart';
import 'package:face_pose/TFLiteModel.dart';
import 'package:face_pose/DrawAxis.dart';
import 'package:face_pose/IsolateManager.dart';

import 'package:flutter/material.dart';
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

IsolateManager manager = IsolateManager();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await manager.start();
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

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  var isModelLoaded = false;
  var processing = false;
  var streaming = false;
  var rendering = false;
  var detected = false;

  String mes = "nothing yet";
  imglib.Image? _currimg;
  ui.Image? _uiImage;
  int _frameCount = 0;

  double zoom_factor = 1;
  var _minZoom = 1.0;
  var _maxZoom = 5.0;
  var scrollX = 0.0, scrollY = 0.0;
  var conf_thres = 0.3;

  double? pitch = 0.0;
  double? yaw = 0.0;
  double? roll = 0.0;

  var detect_frame = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance!.addObserver(this);
    _loadModel();
    initCameraController();
    initZoomLevel();
  }

  @override
  void dispose() {
    _controller.dispose();
    manager.dispose();
    super.dispose();
  }

  void initZoomLevel() async {
    _minZoom = await _controller.getMinZoomLevel();
    _maxZoom = await _controller.getMaxZoomLevel();
  }

  void initCameraController() async {
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.low,
      enableAudio: false,
    );
    _initializeControllerFuture = _controller.initialize();
    _initializeControllerFuture.then((_) {
      if (!rendering) {
        setState(() {
          rendering = true;
        });
      }
      _controller.startImageStream((CameraImage image) async {
        if (rendering == true) {
          imglib.Image img = _convertYUV420toRGBImage(image);
          img = square_crop(img, zoom_factor, scrollX, scrollY);
          _currimg = imglib.copyResize(img, width: 224, height: 224);
          if (streaming == true) {
            _uiImage = await convertToUiImage(_currimg!);
            _frameCount++;
            if (processing == false &&
                isModelLoaded &&
                _frameCount % detect_frame == 0) {
              _frameCount = 0;
              processing = true;
              _processImage(_currimg!);
              setState(() {});
            }
          }
        }
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      cameraController.dispose();
      rendering = false;
    } else if (state == AppLifecycleState.resumed) {
      initCameraController();
      rendering = true;
    }
  }

  Future<void> _loadModel() async {
    manager.loadModel();
    isModelLoaded = true;
  }

  Future<void> _processImage(imglib.Image image) async {
    int start_time = DateTime.now().millisecondsSinceEpoch;
    var pose = await manager.predictPose(image);
    processing = false;
    if (streaming == false) return;
    var processingTime = DateTime.now().millisecondsSinceEpoch - start_time;
    print('Processing time: $processingTime ms');
    print('Pose: $pose');
    if (pose.isNotEmpty && pose['confidence']! > conf_thres) {
      pitch = pose['pitch'] ?? 0.0;
      yaw = pose['yaw'] ?? 0.0;
      roll = pose['roll'] ?? 0.0;

      var pitchStr = pitch!.toStringAsFixed(2);
      var yawStr = yaw!.toStringAsFixed(2);
      var rollStr = roll!.toStringAsFixed(2);
      mes =
          'Pitch: $pitchStr, Yaw: $yawStr, Roll: $rollStr, Confidence: ${pose['confidence']!.toStringAsFixed(2)} \nProcessing time: $processingTime ms';
      detected = true;
    } else {
      detected = false;
      mes = 'Detection failed';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return _column(context);
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }

  Column _column(context) {
    return Column(
      children: [
        SizedBox(
          height: 50,
        ),
        _imageView(context),
        SizedBox(
          height: 20,
          child: Text('Input Image'),
        ),
        Container(
            height: 100,
            child: _currimg != null && streaming
                ? Image.memory(
                    Uint8List.fromList(
                        imglib.encodeJpg(_currimg!, quality: 50)),
                  )
                : Text('No image')),
        SizedBox(height: 20),
        SizedBox(
          height: 40,
          child: Text(
            mes,
          ),
        ),
        SizedBox(height: 10),
        _buttonRow(context),
      ],
    );
  }

  AspectRatio _imageView(context) {
    return AspectRatio(
      aspectRatio: 1,
      child: rendering
          ? Padding(
              padding: const EdgeInsets.all(0), // Remove any extra space
              child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: detected && streaming
                            ? Colors.green
                            : Colors.redAccent, // Set border color
                        width: 4), // Add border here
                    borderRadius:
                        BorderRadius.circular(15), // Make the border rounded
                  ),
                  child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(10), // Make the image rounded
                      child: _uiImage != null && streaming
                          ? _imageStream(context, setState)
                          : _imagePreview(context, setState))),
            )
          : const Center(
              child: SizedBox(
                  width: 50, height: 50, child: CircularProgressIndicator())),
    );
  }

  Stack _imageStream(context, setState) {
    return Stack(children: [
      _imagePreview(context, setState),
      Container(
          color: Colors.transparent,
          child: Center(
              child: ImageWithLines(
            image: _uiImage!,
            pitch: pitch ?? 0.0,
            yaw: yaw ?? 0.0,
            roll: roll ?? 0.0,
            size: 200,
            light: 1.0,
            weight: 4.0,
          ))),
    ]);
  }

  Container _imagePreview(context, setState) {
    var size = MediaQuery.of(context).size.width;
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: SizedBox(
          width: size,
          height: size,
          child: FittedBox(
            fit: BoxFit.fitWidth,
            child: SizedBox(
              width: size,
              height: size * _controller.value.aspectRatio,
              child: CameraPreview(_controller),
            ),
          )),
    );
  }

  Row _sliderZoomFactor(context, setState) {
    return Row(
      children: [
        SizedBox(width: 20),
        Text('Zoom factor: $zoom_factor'),
        Expanded(
            child: Slider(
          min: _minZoom,
          max: _maxZoom,
          divisions: (_maxZoom - _minZoom).toInt() * 10,
          label: '$zoom_factor',
          value: zoom_factor.toDouble(),
          onChanged: !rendering
              ? null
              : (value) {
                  setState(() {
                    zoom_factor = value;
                    _controller.setZoomLevel(zoom_factor);
                  });
                },
        )),
        SizedBox(width: 10),
      ],
    );
  }

  Row _sliderScrollX(context, setState) {
    return Row(
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
          onChanged: !rendering
              ? null
              : (value) {
                  setState(() {
                    scrollX = double.parse(value.toStringAsFixed(1));
                  });
                },
        )),
        SizedBox(width: 10),
      ],
    );
  }

  Row _sliderScrollY(context, setState) {
    return Row(
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
          onChanged: !rendering
              ? null
              : (value) {
                  setState(() {
                    scrollY = double.parse(value.toStringAsFixed(1));
                  });
                },
        )),
        SizedBox(width: 10),
      ],
    );
  }

  Row _sliderThres(context, setState) {
    return Row(
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
          onChanged: !rendering
              ? null
              : (value) {
                  setState(() {
                    conf_thres = value;
                  });
                },
        )),
        SizedBox(width: 10),
      ],
    );
  }

  Row _buttonRow(context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ButtonBar(
          alignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: rendering ? Colors.redAccent : Colors.green,
              ),
              onPressed: () {
                setState(() {
                  if (rendering == false) {
                    rendering = true;
                  } else {
                    rendering = false;
                    streaming = false;
                    mes = 'nothing yet';
                  }
                });
              },
              child: Text(rendering ? 'Off' : 'On'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: streaming ? Colors.redAccent : Colors.green,
              ),
              onPressed: rendering
                  ? () {
                      setState(() {
                        streaming = !streaming;
                        detected = false;
                        mes = 'nothing yet';
                      });
                    }
                  : null,
              child: Text(streaming ? 'Stop' : 'Start'),
            ),
            ElevatedButton(
                onPressed: rendering
                    ? () {
                        showModalBottomSheet(
                            context: context,
                            builder: (context) {
                              return StatefulBuilder(builder:
                                  (BuildContext context, StateSetter setState) {
                                return Container(
                                  width: double.infinity,
                                  height: 250,
                                  child: Center(
                                    child: Column(
                                      children: [
                                        Expanded(
                                            child: _sliderZoomFactor(
                                                context, setState)),
                                        Expanded(
                                            child: _sliderThres(
                                                context, setState)),
                                        Expanded(
                                          child: _sliderDetectFrame(
                                              context, setState),
                                        ),
                                        Expanded(
                                            child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            ElevatedButton(
                                              onPressed: () {
                                                setState(() {
                                                  zoom_factor = 1;
                                                  scrollX = 0;
                                                  scrollY = 0;
                                                  conf_thres = 0.3;
                                                });
                                              },
                                              child: Text('Reset'),
                                            )
                                          ],
                                        ))
                                      ],
                                    ),
                                  ),
                                );
                              });
                            });
                      }
                    : null,
                child: Text("Cam Set"))
          ],
        ),
      ],
    );
  }

  Row _sliderDetectFrame(context, setState) {
    return Row(
      children: [
        SizedBox(width: 20),
        Text('refresh frame: $detect_frame'),
        Expanded(
            child: Slider(
          min: 5,
          max: 30,
          divisions: 25,
          label: '${detect_frame.toInt()}',
          value: detect_frame.toDouble(),
          onChanged: !rendering
              ? null
              : (value) {
                  setState(() {
                    detect_frame = value.toInt();
                  });
                },
        )),
        SizedBox(width: 10),
      ],
    );
  }
}