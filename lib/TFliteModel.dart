import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as imglib;
import 'dart:typed_data';
import 'dart:math' as math;

class TFliteModel {
  final String modelPath = 'assets/final0526.tflite';
  Interpreter? _interpreter;
  var threshold = 0.3;

  void setThres(double thres) {
    threshold = thres;
  }

  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(modelPath);
      // print input shape
      print('Input shape: ${_interpreter!.getInputTensor(0).shape}');
    } catch (e) {
      print('Failed to load model: $e');
    }
  }

  Future<Map<String, double>> predictPose(imglib.Image image) async {
    if (_interpreter == null) {
      print('Interpreter is not loaded');
      return {};
    }

    try {
      var inputData = transform(image);
      var outputs = <int, Object>{};
      for (int i = 0; i < _interpreter!.getOutputTensors().length; i++) {
        var tmp = List.empty(growable: true);
        tmp.add(Float32List(_interpreter!.getOutputTensor(i).numElements()));
        outputs[i] = tmp;
      }
      print("Running inference");
      _interpreter!.runForMultipleInputs([inputData], outputs);
      print("Inference done");
      var out = outputs;
      var outputData1 = out[0];
      var outputData2 = out[1];
      var outputData3 = out[2];

      outputData1 = (outputData1 as List).first as List<double>;
      outputData2 = (outputData2 as List).first as List<double>;
      outputData3 = (outputData3 as List).first as List<double>;

      outputData1 = outputData1 as List<double>;
      outputData2 = outputData2 as List<double>;
      outputData3 = outputData3 as List<double>;

      var rollSoftmax = softmax(outputData1);
      var pitchSoftmax = softmax(outputData2);
      var yawSoftmax = softmax(outputData3);

      var bins = List.generate(66, (i) => (-99 + i * 3).toDouble());
      var pitch = dotProduct(pitchSoftmax, bins);
      var yaw = dotProduct(yawSoftmax, bins);
      var roll = dotProduct(rollSoftmax, bins);

      var pitchConfidence = sumTop3(pitchSoftmax);
      var yawConfidence = sumTop3(yawSoftmax);
      var rollConfidence = sumTop3(rollSoftmax);

      var confidence = (pitchConfidence + yawConfidence + rollConfidence) / 3;

      return {
        'pitch': pitch,
        'yaw': yaw,
        'roll': roll,
        'confidence': confidence
      };
    } catch (e, stackTrace) {
      print('Error in predictPose: $e');
      print('Stack trace: $stackTrace');
      return {};
    }
  }

  void dispose() {
    _interpreter?.close();
  }

  static double sumTop3(List<double> numbers) {
    numbers.sort((a, b) => b.compareTo(a));
    double sum = numbers.take(3).reduce((a, b) => a + b);
    return sum;
  }

  static double dotProduct(List<double> a, List<double> b) {
    return List.generate(a.length, (i) => a[i] * b[i]).reduce((x, y) => x + y);
  }

  static List<double> softmax(List<double> input) {
    var max = input.reduce(math.max);
    var exps = input.map((x) => math.exp(x - max)).toList();
    var sum = exps.reduce((a, b) => a + b);
    return exps.map((x) => x / sum).toList();
  }

  static List<List<List<List<double>>>> transform(imglib.Image image) {
    // resize to 224x224
    imglib.Image resizedImage =
        imglib.copyResize(image, width: 224, height: 224);
    // convert to byte list
    /*
    RGB
    mean = np.array([0.485, 0.456, 0.406])
    std = np.array([0.229, 0.224, 0.225])
    image = (image / 255.0 - mean) / std
    */
    List<double> mean = [0.485, 0.456, 0.406];
    List<double> std = [0.229, 0.224, 0.225];
    var flattenedData = _imageToByteListFloat32(resizedImage, 224, mean, std);

    // Reshape to [1, 3, 224, 224]
    var reshapedData = List.generate(
        1,
        (_) => List.generate(
            3,
            (c) => List.generate(
                224,
                (y) => List.generate(
                    224,
                    (x) => flattenedData[c * 224 * 224 + y * 224 + x]
                        .toDouble()))));

    print(
        'Transformed data shape: [${reshapedData.length}, ${reshapedData[0].length}, ${reshapedData[0][0].length}, ${reshapedData[0][0][0].length}]');
    return reshapedData;
  }

  // perform transform -> (1, 3, 224, 224)
  static Float32List _imageToByteListFloat32(
      imglib.Image image, int inputSize, List<double> mean, List<double> std) {
    var convertedBytes = Float32List(1 * 3 * inputSize * inputSize);
    int pixelIndex = 0;
    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < inputSize; y++) {
        for (var x = 0; x < inputSize; x++) {
          var pixel = image.getPixel(x, y);
          double pixelValue;
          if (c == 0) {
            pixelValue = imglib.getRed(pixel).toDouble();
          } else if (c == 1) {
            pixelValue = imglib.getGreen(pixel).toDouble();
          } else {
            pixelValue = imglib.getBlue(pixel).toDouble();
          }
          convertedBytes[pixelIndex++] =
              (pixelValue / 255.0 - mean[c]) / std[c];
        }
      }
    }
    return convertedBytes;
  }
}
