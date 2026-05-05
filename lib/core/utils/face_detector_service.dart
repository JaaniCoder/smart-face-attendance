import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:math';

class FaceDetectorService {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate, // Use accurate for attendance
      enableLandmarks: true,
      enableClassification: true, // Enable classification for better accuracy
    ),
  );

  Future<List<Face>> getFaces(InputImage inputImage) async {
    return await _faceDetector.processImage(inputImage);
  }

  void dispose() {
    _faceDetector.close();
  }
}

class FaceMatcher {
  static const double threshold = 0.85; // Adjust based on your model's performance

  static double euclideanDistance(List<dynamic> e1, List<dynamic> e2) {
    double sum = 0.0;
    for (int i = 0; i < e1.length; i++) {
      double diff = e1[i] - e2[i];
      sum += diff * diff;
    }
    return sqrt(sum);
  }

  static String compareFaces(List<double> capturedFace, Map<String, List<double>> registeredUsers) {
    String name = "Unknown";
    double minDist = 999.0;

    registeredUsers.forEach((key, value) {
      double dist = euclideanDistance(capturedFace, value);
      if (dist < minDist && dist < threshold) {
        minDist = dist;
        name = key;
      }
    });
    return name;
  }
}