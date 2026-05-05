import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class MLService {
  Interpreter? _interpreter;

  Future<void> loadModel() async {
    try {
      // Make sure the path matches your pubspec.yaml
      _interpreter = await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');
      debugPrint('Model loaded successfully');
    } catch (e) {
      debugPrint('Failed to load model: $e');
    }
  }

  List<double> predict(img.Image image) {
    if (_interpreter == null) return [];
    
    var input = _imageToByteListFloat32(image, 112);
    var output = List<double>.filled(192, 0).reshape([1, 192]);

    _interpreter!.run(input, output);

    return List<double>.from(output[0]);
  }

  Uint8List _imageToByteListFloat32(img.Image image, int inputSize) {
    var convertedBytes = Float32List(1 * inputSize * inputSize * 3);
    var buffer = Float32List.view(convertedBytes.buffer);
    int pixelIndex = 0;
    
    for (int i = 0; i < inputSize; i++) {
      for (int j = 0; j < inputSize; j++) {
        var pixel = image.getPixel(j, i);

        buffer[pixelIndex++] = (pixel.r - 128) / 128;   // Normalize to [-1, 1]
        buffer[pixelIndex++] = (pixel.g - 128) / 128;   // Normalize to [-1, 1]
        buffer[pixelIndex++] = (pixel.b - 128) / 128;   // Normalize to [-1, 1]
      }
    }
    // Return as List<List<List<List<double>>>> shape [1, 112, 112, 3]
    return convertedBytes.buffer.asUint8List();
  }

  void dispose() {
    _interpreter?.close();
  }
}