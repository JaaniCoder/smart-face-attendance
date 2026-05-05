import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/foundation.dart';

InputImage? buildInputImage(CameraImage image, CameraDescription camera) {
  final WriteBuffer allBytes = WriteBuffer();
  for (final Plane plane in image.planes) {
    allBytes.putUint8List(plane.bytes);
  }
  final bytes = allBytes.done().buffer.asUint8List();

  final imageSize = Size(image.width.toDouble(), image.height.toDouble());
  final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) 
                   ?? InputImageRotation.rotation0deg;
  final format = InputImageFormatValue.fromRawValue(image.format.raw) 
                 ?? InputImageFormat.nv21;

  final plane = image.planes.first;

  return InputImage.fromBytes(
    bytes: bytes,
    metadata: InputImageMetadata(
      size: imageSize,
      rotation: rotation,
      format: format,
      bytesPerRow: plane.bytesPerRow,
    ),
  );
}