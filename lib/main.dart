import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Camera Screen',
      home: CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class CameraPreviewCropped extends StatelessWidget {
  final CameraController controller;
  const CameraPreviewCropped({required this.controller});

  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.width;
    return SizedBox(
      width: size,
      height: size,
      child: FittedBox(
        fit: BoxFit.fitWidth,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: size,
          height: size * controller.value.aspectRatio,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  @override
  void initState() {
    super.initState();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      frontCamera,
      ResolutionPreset.high,
    );
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Camera Screen')),
        body: FutureBuilder<void>(
          future: _initializeControllerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return CameraPreviewCropped(controller: _controller);
            } else {
              return const Center(child: CircularProgressIndicator());
            }
          },
        ));
  }
}
