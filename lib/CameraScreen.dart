import 'package:camera/camera.dart';
import 'package:face_pose/utils/DrawAxis.dart';
import 'package:face_pose/IsolateManager.dart';
import 'package:face_pose/utils/tool.dart';

import 'package:flutter/material.dart';

import 'package:image/image.dart' as imglib;
import 'dart:async';
import 'package:flutter/services.dart';

IsolateManager manager = IsolateManager();
// static manager

double abs(double x) {
  return x < 0 ? -x : x;
}

class CameraService {
  late CameraController _controller;
  late Future<void> initializeControllerFuture;

  Future<void> initCamera(CameraDescription camera) async {
    _controller = CameraController(
      camera,
      ResolutionPreset.low,
      enableAudio: false,
    );
    initializeControllerFuture = _controller.initialize();
  }

  Future<void> startImageStream(Function(CameraImage) onImage) async {
    _controller.startImageStream(onImage);
  }

  Future<void> stopImageStream() async {
    await _controller.stopImageStream();
  }

  Future<void> dispose() async {
    await _controller.dispose();
  }

  CameraController get controller => _controller;
}

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;

  const CameraScreen({Key? key, required this.camera}) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  final CameraService _cameraService = CameraService();

  var isModelLoaded = false;
  var processing = false;
  var streaming = false;
  var rendering = true;
  var detected = false;
  var debugIsHidden = false;

  String mes = "nothing yet";
  imglib.Image? _currimg;
  int _frameCount = 0;

  double zoom_factor = 1;
  var _minZoom = 1.0;
  var _maxZoom = 5.0;
  var scrollX = 0.0, scrollY = 0.0;
  var conf_thres = 0.3;

  double? pitch = 0.0;
  double? yaw = 0.0;
  double? roll = 0.0;

  double base_pitch = 0.0;
  double base_yaw = 0.0;
  double base_roll = 0.0;
  double tolerance_angle = 0.0;

  var detect_frame = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance!.addObserver(this);
    _loadModel();
    _cameraService.initCamera(widget.camera);
    if (_cameraService._controller.value.isInitialized) {
      setState(() {
        rendering = true;
      });
    }
    startImageStream();
    initZoomLevel();
  }

  @override
  void dispose() {
    _cameraService.dispose();
    manager.dispose();
    super.dispose();
  }

  void initZoomLevel() async {
    await _cameraService.initializeControllerFuture;
    _minZoom = await _cameraService._controller.getMinZoomLevel();
    _maxZoom = await _cameraService._controller.getMaxZoomLevel();
  }

  void startImageStream() async {
    await _cameraService.initializeControllerFuture;
    _cameraService.startImageStream((CameraImage image) async {
      if (streaming == true) {
        _frameCount++;
        if (processing == false &&
            isModelLoaded &&
            _frameCount % detect_frame == 0) {
          imglib.Image img = convertYUV420toRGBImage(image);
          img = square_crop(img, zoom_factor, scrollX, scrollY);
          _currimg = imglib.copyResize(img, width: 224, height: 224);
          _frameCount = 0;
          processing = true;
          _processImage(_currimg!);
          setState(() {});
        }
      }
    });
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

      mes = 'Processing time: $processingTime ms';
      detected = true;
    } else if (pose.isEmpty) {
      detected = false;
      mes = 'Empty result';
    } else {
      detected = false;
      mes = 'Detection failed';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraService.controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      cameraController.dispose();
      rendering = false;
    } else if (state == AppLifecycleState.resumed) {
      if (cameraController != null) {
        _cameraService.initCamera(widget.camera);
        startImageStream();
      }
      rendering = true;
    }
  }

  Future<void> _loadModel() async {
    manager.loadModel();
    isModelLoaded = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: rendering
            ? () {
                showModalBottomSheet(
                    context: context,
                    builder: (context) {
                      return _bottomSheet(context);
                    });
              }
            : null,
        child: const Icon(Icons.settings),
      ),
      body: FutureBuilder<void>(
        future: _cameraService.initializeControllerFuture,
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
        const SizedBox(
          height: 50,
        ),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
            child: _imageView(context)),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: _buttonRow(context)),
        Visibility(
            visible: !debugIsHidden,
            replacement: const SizedBox.shrink(),
            child: Column(children: [
              Row(children: [
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: Colors.white, width: 2), // Add border here
                          // Make the border rounded
                        ),
                        height: 100,
                        width: 100,
                        child: _currimg != null && streaming
                            ? Image.memory(
                                Uint8List.fromList(
                                    imglib.encodeJpg(_currimg!, quality: 50)),
                              )
                            : const Center(child: Text('No image')))),
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(
                        style: const TextStyle(
                          fontSize: 15,
                          fontFamily: 'Roboto',
                          decoration: TextDecoration.underline,
                        ),
                        mes))
              ]),
              Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: SizedBox(
                    width: double.infinity,
                    height: 2,
                    child: Container(
                      color: Colors.grey,
                    ),
                  )),
              Row(children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
                  child: Container(
                      width: 120,
                      child: Text(
                          style: const TextStyle(
                            fontSize: 20,
                            fontFamily: 'Roboto',
                          ),
                          pitch != null
                              ? 'Pitch: ${pitch!.toStringAsFixed(2)}°'
                              : 'Pitch: 0.0°')),
                ),
                Icon(
                  pitch == null
                      ? Icons.close
                      : (abs(pitch!) > 7)
                          ? (pitch! > 0
                              ? Icons.arrow_circle_up
                              : Icons.arrow_circle_down)
                          : Icons.do_not_disturb_on_rounded,
                  size: 50,
                  color: Colors.red,
                ),
              ]),
              Row(children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
                  child: Container(
                      width: 120,
                      child: Text(
                          style: TextStyle(
                            fontSize: 20,
                            fontFamily: 'Roboto',
                          ),
                          yaw != null
                              ? 'Yaw: ${yaw!.toStringAsFixed(2)}°'
                              : 'Yaw: 0.0°')),
                ),
                Icon(
                  yaw == null
                      ? Icons.close
                      : (abs(yaw!) > 7)
                          ? (yaw! > 0
                              ? Icons.arrow_circle_left
                              : Icons.arrow_circle_right)
                          : Icons.do_not_disturb_on_rounded,
                  size: 50,
                  color: Colors.blue,
                ),
              ]),
              Row(children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 15, vertical: 20),
                  child: Container(
                      width: 120,
                      child: Text(
                          style: const TextStyle(
                            fontSize: 20,
                            fontFamily: 'Roboto',
                          ),
                          roll != null
                              ? 'Roll: ${roll!.toStringAsFixed(2)}°'
                              : 'Roll: 0.0°')),
                ),
                Icon(
                  roll == null
                      ? Icons.close
                      : (abs(roll!) > 7)
                          ? (roll! > 0 ? Icons.rotate_right : Icons.rotate_left)
                          : Icons.do_not_disturb_on_rounded,
                  size: 50,
                  color: Colors.green,
                ),
              ])
            ])),
        Visibility(
            visible: debugIsHidden,
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: double.infinity,
                    height: 2,
                    child: Container(
                      color: Colors.grey,
                    ),
                  )),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                    child: pitch != null &&
                            yaw != null &&
                            roll != null &&
                            abs(pitch! - base_pitch) < tolerance_angle &&
                            abs(yaw! - base_yaw) < tolerance_angle &&
                            abs(roll! - base_roll) < tolerance_angle &&
                            detected
                        ? const Icon(
                            size: 70,
                            Icons.check,
                            color: Colors.green,
                          )
                        : const Icon(
                            size: 70,
                            Icons.close,
                            color: Colors.red,
                          )),
              ]),
              Center(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 15, vertical: 15),
                      child: Text(
                          style: const TextStyle(
                            fontSize: 20,
                            fontFamily: 'Roboto',
                          ),
                          pitch != null &&
                                  yaw != null &&
                                  roll != null &&
                                  abs(pitch! - base_pitch) < tolerance_angle &&
                                  abs(yaw! - base_yaw) < tolerance_angle &&
                                  abs(roll! - base_roll) < tolerance_angle &&
                                  detected
                              ? 'Focused'
                              : (detected)
                                  ? 'Not focused'
                                  : 'No face detected'))),
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: SizedBox(
                    width: double.infinity,
                    height: 2,
                    child: Container(
                      color: Colors.grey,
                    ),
                  )),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(children: [
                    Expanded(
                        child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _buttonResetAngle(context),
                    )),
                    Expanded(
                        child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _buttonSetAngle(context),
                    ))
                  ])),
              Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Padding(
                      padding: EdgeInsets.only(right: 50),
                      child: _sliderAcceptRate(context))),
            ])),
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
                            ? Colors.blue
                            : Colors.grey, // Set border color
                        width: 4), // Add border here
                    borderRadius:
                        BorderRadius.circular(15), // Make the border rounded
                  ),
                  child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(10), // Make the image rounded
                      child: streaming
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
            image: null,
            pitch: pitch ?? 0.0,
            yaw: yaw ?? 0.0,
            roll: roll ?? 0.0,
            base_pitch: base_pitch,
            base_yaw: base_yaw,
            base_roll: base_roll,
            tolerance: tolerance_angle,
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
              height: size * _cameraService._controller.value.aspectRatio,
              child: CameraPreview(_cameraService._controller),
            ),
          )),
    );
  }

  Row _sliderAcceptRate(context) {
    return Row(children: [
      Padding(
          padding: EdgeInsets.only(left: 15),
          child: Text('Tolerance: ${tolerance_angle.toStringAsFixed(0)}')),
      Expanded(
          child: Slider(
        min: 0.0,
        max: 30.0,
        divisions: 15,
        label: '${tolerance_angle.toStringAsFixed(0)}',
        value: tolerance_angle.toDouble(),
        onChanged: streaming
            ? null
            : (value) {
                setState(() {
                  tolerance_angle = value;
                });
              },
      )),
    ]);
  }

  Row _sliderZoomFactor(context, setState) {
    return Row(
      children: [
        const SizedBox(width: 20),
        Text('Zoom factor: $zoom_factor'),
        Expanded(
            child: Slider(
          min: _minZoom,
          max: _maxZoom,
          divisions: (_maxZoom - _minZoom).toInt() * 10,
          label: '${zoom_factor.toStringAsFixed(2)}',
          value: zoom_factor.toDouble(),
          onChanged: !rendering
              ? null
              : (value) {
                  setState(() {
                    zoom_factor = value;
                    _cameraService._controller.setZoomLevel(zoom_factor);
                  });
                },
        )),
        const SizedBox(width: 10),
      ],
    );
  }

  Row _sliderScrollX(context, setState) {
    return Row(
      children: [
        const SizedBox(width: 20),
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
        const SizedBox(width: 10),
      ],
    );
  }

  Row _sliderScrollY(context, setState) {
    return Row(
      children: [
        const SizedBox(width: 20),
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
        const SizedBox(width: 10),
      ],
    );
  }

  Row _sliderThres(context, setState) {
    return Row(
      children: [
        const SizedBox(width: 20),
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
        const SizedBox(width: 10),
      ],
    );
  }

  Row _sliderDetectFrame(context, setState) {
    return Row(
      children: [
        const SizedBox(width: 20),
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
        const SizedBox(width: 10),
      ],
    );
  }

  ElevatedButton _buttonResetAngle(context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 60)),
      child: const Text("reset"),
      onPressed: () => {
        setState(() {
          base_pitch = 0.0;
          base_yaw = 0.0;
          base_roll = 0.0;
        })
      },
    );
  }

  ElevatedButton _buttonSetAngle(context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 60)),
      child: const Text("set angle"),
      onPressed: !streaming
          ? () {
              setState(() {
                base_pitch = 0.0;
                base_yaw = 0.0;
                base_roll = 0.0;
              });
            }
          : () => {
                setState(() {
                  base_pitch = pitch ?? 0.0;
                  base_yaw = yaw ?? 0.0;
                  base_roll = roll ?? 0.0;
                })
              },
    );
  }

  ElevatedButton _buttonCameraControl(context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
          backgroundColor: rendering ? Colors.redAccent : Colors.green,
          minimumSize: const Size(double.infinity, 60)),
      onPressed: () {
        setState(() {
          if (rendering == false) {
            rendering = true;
            _cameraService.initCamera(widget.camera);
            startImageStream();
          } else {
            rendering = false;
            streaming = false;
            mes = 'nothing yet';
            final CameraController? cameraController =
                _cameraService.controller;
            cameraController!.dispose();
          }
        });
      },
      child: Text(rendering ? 'Off' : 'On'),
    );
  }

  ElevatedButton _buttonStreamControl(context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
          backgroundColor: streaming ? Colors.redAccent : Colors.green,
          minimumSize: const Size(double.infinity, 60)),
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
    );
  }

  ElevatedButton _buttonDebugVisible(context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 60)),
      onPressed: () {
        setState(() {
          debugIsHidden = !debugIsHidden;
        });
      },
      child: const Text('Debug'),
    );
  }

  StatefulBuilder _bottomSheet(context) {
    return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
      return Container(
        width: double.infinity,
        height: 250,
        child: Center(
          child: Column(
            children: [
              Expanded(child: _sliderZoomFactor(context, setState)),
              Expanded(child: _sliderThres(context, setState)),
              Expanded(
                child: _sliderDetectFrame(context, setState),
              ),
              Expanded(
                  child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
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
                    child: const Text('Reset'),
                  ),
                ],
              ))
            ],
          ),
        ),
      );
    });
  }

  Row _buttonRow(context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _buttonCameraControl(context),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _buttonStreamControl(context),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _buttonDebugVisible(context),
          ),
        ),
      ],
    );
  }
}
