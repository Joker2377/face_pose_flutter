import 'dart:isolate';
import 'package:image/image.dart' as imglib;
import 'package:face_pose/TFLiteModel.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:face_pose/TFLiteModel.dart';
import 'package:flutter_isolate/flutter_isolate.dart';

void isolateEntry(SendPort sendPort) async {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);
  print('Isolate started');
  receivePort.listen((message) async {
    if (message is String) {
      switch (message) {
        case 'exit':
          Isolate.exit();
        default:
          print('Unknown message: $message');
      }
    }
    if (message is Map) {
      final inputData = message['inputData'] as List<List<List<List<double>>>>;
      final address = message['address'] as int;
      final replyPort = message['responsePort'] as SendPort;
      final model = TFliteModel();
      model.assignInterpreterFromAdress(address);
      final result =
          await model.rawPredictPose(inputData) as Map<String, double>;
      print('Isolate got result: ${result.values}');
      replyPort.send(result);
    }
  });
}

class IsolateManager {
  FlutterIsolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort = ReceivePort();
  Interpreter? _interpreter;

  final modelPath = 'assets/final0526.tflite';
  bool _isLoaded = false;

  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(modelPath);
      _isLoaded = true;
    } catch (e) {
      print('Failed to load model: $e');
    }
  }

  Future<void> start() async {
    _isolate = await FlutterIsolate.spawn(isolateEntry, _receivePort!.sendPort);
    _sendPort = await _receivePort!.first;
  }

  Future<Map<String, double>> predictPose(imglib.Image image) async {
    if (!_isLoaded) {
      print('Interpreter is not loaded');
      return {};
    }
    var inputData = TFliteModel.transform(image);
    print('trying to send data with type: ${inputData.runtimeType}');
    ReceivePort responsePort = ReceivePort();
    _sendPort!.send({
      'address': _interpreter!.address,
      'inputData': inputData,
      'responsePort': responsePort.sendPort
    });
    print('Data sent');
    var result = await responsePort.first as Map<String, double>;
    print('Got result: ${result.values}');
    return result;
  }

  void dispose() {
    _sendPort!.send('exit');
  }
}
