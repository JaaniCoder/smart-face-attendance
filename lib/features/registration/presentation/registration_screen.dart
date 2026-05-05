import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../../core/theme/app_theme.dart';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:smart_attendance_app/core/utils/auto_illumination_service.dart';
import '../../../core/utils/offline_sync_service.dart';
import 'dart:io';
import 'dart:async';
import '../../../core/utils/ml_service.dart';
import 'dart:math' as math;

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});
  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final AutoIlluminationService _illuminationService = AutoIlluminationService();
  CameraController? _controller;
  bool _isBusy = false;
  bool _faceCaptured = false;
  List<double>? _tempFaceVector;
  File? _capturedImageFile;

  Timer? _previewTimer;
  bool _isFaceInFrame = false;
  bool _isPreviewProcessing = false;

  final FaceDetector _fastFaceDetector = FaceDetector(options: FaceDetectorOptions(
    performanceMode: FaceDetectorMode.fast,
    enableClassification: false,
  ));

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableClassification: true,
    ),
  );

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _rollController = TextEditingController();

  String? _selectedBranch;
  String? _selectedYear;

  final MLService _mlService = MLService();

  final List<String> _branches = [
    'Computer Science & Engineering',
    'Computer Science & Engineering (AI & ML)',
    'Electronics & Communication Engineering',
    'Mechanical Engineering',
    'Civil Engineering',
    'Electrical Engineering',
  ];
  final List<String> _years = ['1st Year', '2nd Year', '3rd Year', '4th Year'];

  @override
  void initState() {
    super.initState();
    _initialize();
    _illuminationService.startAutoIllumination();
  }

  Future<void> _initialize() async {
    final status = await Permission.camera.request();
    if (status.isDenied) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Camera permission is required.")));
      return;
    }

    await _mlService.loadModel();
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);

    _controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await _controller!.initialize();
    if (mounted) { 
      setState(() {});
      _startPreviewCycle();
    }
  }

  void _startPreviewCycle() {
    _previewTimer?.cancel();
    _isFaceInFrame = false;
    _isPreviewProcessing = false;

    _previewTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      if (_isBusy || _faceCaptured || _isPreviewProcessing || !mounted || _controller == null || !_controller!.value.isInitialized) return;

      _isPreviewProcessing = true;
      try {
        final XFile file = await _controller!.takePicture();
        final inputImage = InputImage.fromFilePath(file.path);
        final faces = await _fastFaceDetector.processImage(inputImage);

        bool hasFace = faces.isNotEmpty && faces.first.boundingBox.width >= 80;

        if (mounted && _isFaceInFrame != hasFace) {
          setState(() => _isFaceInFrame = hasFace);
        }
        try {await File(file.path).delete();} catch(_) {}
      } catch (e) {
        debugPrint("Preview error: $e");
      } finally {
        if (mounted) _isPreviewProcessing = false;
      }
    });
  }

  double _calculateCosineDistance(List<double> e1, List<double> e2) {
    double dotProduct = 0.0, normA = 0.0, normB = 0.0;
    for (int i = 0; i < e1.length; i++) {
      dotProduct += e1[i] * e2[i];
      normA += math.pow(e1[i], 2);
      normB += math.pow(e2[i], 2);
    }
    if (normA == 0.0 || normB == 0.0) return 1.0;
    return 1.0 - (dotProduct / (math.sqrt(normA) * math.sqrt(normB)));
  }

  Future<void> _captureFace() async {
    _previewTimer?.cancel();
    if (_isBusy || _controller == null) return;
    setState(() => _isBusy = true);

    try {
      final XFile file = await _controller!.takePicture();
      final faces = await _faceDetector.processImage(InputImage.fromFilePath(file.path));

      if (faces.isEmpty) throw Exception("No face detected. Look directly at the camera.");

      final face = faces.first;

      if (face.headEulerAngleY!.abs() > 15 || face.headEulerAngleZ!.abs() > 15) {
        throw Exception("Head tilted. Please look perfectly straight at the camera.");
      }

      final bytes = await File(file.path).readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) throw Exception("Failed to process image.");

      image = img.bakeOrientation(image);
      final int padding = (face.boundingBox.width * 0.10).toInt();
      final int x = (face.boundingBox.left.toInt() - padding).clamp(0, image.width - 1);
      final int y = (face.boundingBox.top.toInt() - padding).clamp(0, image.height - 1);
      final int w = (face.boundingBox.width.toInt() + (padding * 2)).clamp(1, image.width - x);
      final int h = (face.boundingBox.height.toInt() + (padding * 2)).clamp(1, image.height - y);

      final img.Image cropped = img.copyCrop(image, x: x, y: y, width: w, height: h);
      final img.Image resized = img.copyResize(cropped, width: 112, height: 112);

      final List<double> vector = _mlService.predict(resized);
      if (vector.isEmpty) throw Exception("Face embedding failed. Please try again.");

      final allStudents = await FirebaseFirestore.instance.collection('students').get();

      for (var doc in allStudents.docs) {
        if (doc.data().containsKey('face_vector')) {
          List<double> storedVector = List<double>.from(doc['face_vector'].map((e) => (e as num).toDouble()));
          if (vector.length == storedVector.length) {
            double distance = _calculateCosineDistance(vector, storedVector);
            
            if (distance < 0.35) {
              throw Exception("Face already registered to ${doc['name']} (${doc['roll_no']}).");
            }
          }
        }
      }
      
      setState(() {
        _tempFaceVector = vector;
        _faceCaptured = true;
        _capturedImageFile = File(file.path);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: AppTheme.dangerRed));
        _startPreviewCycle();
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _finalizeRegistration() async {
    final name = _nameController.text.trim();
    final rollNo = _rollController.text.trim();

    if (name.isEmpty || rollNo.isEmpty || _selectedBranch == null || _selectedYear == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill in all the details.")));
      return;
    }
    if (_tempFaceVector == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No face captured. Please capture first.")));
      return;
    }

    setState(() => _isBusy = true);

    try {
      final newStudentData = {
        'name': name,
        'roll_no': rollNo,
        'branch': _selectedBranch!,
        'year': _selectedYear!,
        'face_vector': _tempFaceVector!.map((e) => e).toList(),
        'search_key': "${name}_$rollNo",
        'registered_at': FieldValue.serverTimestamp(),
      };

      final query = await FirebaseFirestore.instance.collection('students').where('roll_no', isEqualTo: rollNo).get();

      String docId;
      if (query.docs.isNotEmpty) {
        docId = query.docs.first.id;
        await FirebaseFirestore.instance.collection('students').doc(docId).update(newStudentData);
      } else {
        final docRef = await FirebaseFirestore.instance.collection('students').add(newStudentData);
        docId = docRef.id;
      }

      final localData = Map<String, dynamic>.from(newStudentData);
      localData['registered_at'] = DateTime.now().toIso8601String();
      localData['doc_id'] = docId;

      await Hive.box(OfflineSyncService.studentsBoxName).put(docId, localData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$name registered successfully!"), backgroundColor: AppTheme.successGreen));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: AppTheme.dangerRed));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(backgroundColor: AppTheme.bgLight, body: Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue)));
    }

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(title: const Text("Register Student")),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.4,
                  child: _faceCaptured
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(_capturedImageFile!, fit: BoxFit.cover),
                            Positioned(
                              top: 12, right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: AppTheme.successGreen.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(20)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.check, color: Colors.white, size: 16),
                                    SizedBox(width: 4),
                                    Text("Face Captured", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : Stack(
                          alignment: Alignment.center,
                          children: [
                            CameraPreview(_controller!),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 240, height: 320,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _isFaceInFrame ? AppTheme.successGreen : AppTheme.dangerRed,
                                  width: _isFaceInFrame ? 4.0 : 2.0
                                ),
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: [
                                  BoxShadow(
                                    color: (_isFaceInFrame ? AppTheme.successGreen : AppTheme.dangerRed).withValues(alpha: 0.3),
                                    blurRadius: 15, spreadRadius: 2,
                                  )
                                ],
                              ),
                            ),
                            Positioned(
                              bottom: 20,
                              child: AnimatedOpacity(
                                opacity: 1.0, duration: const Duration(milliseconds: 300),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: AppTheme.textDark.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
                                  child: Text(
                                    _isFaceInFrame ? "Hold Still" : "Align face in frame",
                                    style: TextStyle(color: _isFaceInFrame ? AppTheme.successGreen : AppTheme.dangerRed, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),

                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_faceCaptured) ...[
                        ElevatedButton.icon(
                          onPressed: _isBusy ? null : _captureFace,
                          icon: const Icon(Icons.camera_alt),
                          label: Text(_isBusy ? "Processing..." : "Capture Face"),
                        ),
                      ] else ...[
                        TextField(controller: _nameController, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: "Full Name", prefixIcon: Icon(Icons.person_outline))),
                        const SizedBox(height: 12),
                        TextField(controller: _rollController, decoration: const InputDecoration(labelText: "Roll Number", prefixIcon: Icon(Icons.badge_outlined))),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedBranch,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: "Branch", prefixIcon: Icon(Icons.school_outlined)),
                          items: _branches.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                          onChanged: (val) => setState(() => _selectedBranch = val),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedYear,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: "Year", prefixIcon: Icon(Icons.calendar_today_outlined)),
                          items: _years.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
                          onChanged: (val) => setState(() => _selectedYear = val),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _isBusy ? null : _finalizeRegistration,
                          icon: const Icon(Icons.how_to_reg),
                          label: Text(_isBusy ? "Registering..." : "Finalize Registration"),
                        ),
                        TextButton.icon(
                          onPressed: _isBusy ? null : () => setState(() {
                            _faceCaptured = false; _tempFaceVector = null; _capturedImageFile = null;
                            _nameController.clear(); _rollController.clear(); _selectedBranch = null; _selectedYear = null;
                            _startPreviewCycle();
                          }),
                          icon: const Icon(Icons.refresh),
                          label: const Text("Retake Photo"),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_isBusy)
            Positioned.fill(
              child: Container(
                color: AppTheme.bgLight.withValues(alpha: 0.8),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      CircularProgressIndicator(color: AppTheme.primaryBlue),
                      SizedBox(height: 15),
                      Text("Verifying Face Integrity...", style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _controller?.dispose();
    _faceDetector.close();
    _fastFaceDetector.close();
    _nameController.dispose();
    _rollController.dispose();
    _mlService.dispose();
    _illuminationService.stopAutoIllumination();
    super.dispose();
  }
}