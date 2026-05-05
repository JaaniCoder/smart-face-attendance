import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smart_attendance_app/core/theme/app_theme.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/utils/offline_sync_service.dart';
import 'dart:io';
import 'dart:math' as math;
import 'dart:async';
import '../../../core/utils/ml_service.dart';
import '../../../core/utils/auto_illumination_service.dart';

enum _ScanStatus { scanning, verifying, success, alreadyMarked, notRegistered, noMatch, error }

class AttendanceScreen extends StatefulWidget {
  final String selectedBranch;
  const AttendanceScreen({super.key, required this.selectedBranch});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final AutoIlluminationService _illuminationService = AutoIlluminationService();
  CameraController? _controller;
  bool _isProcessing = false;
  bool _isActive = false;

  bool _livenessPassed = false;
  bool _eyesWereClosed = false;

  final MLService _mlService = MLService();
  
  final FaceDetector _fastFaceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableClassification: true, 
      enableTracking: true,
    ),
  );

  final FaceDetector _accurateFaceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableClassification: true,
    ),
  );

  Timer? _captureTimer;
  _ScanStatus _status = _ScanStatus.scanning;
  String _statusMessage = "Position your face inside the frame";
  String _matchedName = "", _matchedRoll = "";

  late AnimationController _pulseController, _scanLineController, _resultController;
  late Animation<double> _pulseAnimation, _scanLineAnimation, _resultScaleAnimation, _resultFadeAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAnimations();
    _initialize();
    _illuminationService.startAutoIllumination();
  }

  void _initAnimations() {
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    
    _scanLineController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat();
    _scanLineAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _scanLineController, curve: Curves.linear));

    _resultController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _resultScaleAnimation = CurvedAnimation(parent: _resultController, curve: Curves.elasticOut);
    _resultFadeAnimation = CurvedAnimation(parent: _resultController, curve: Curves.easeIn);
  }

  Future<void> _initialize() async {
    try {
      await _mlService.loadModel();
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);

      _controller = CameraController(frontCamera, ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await _controller!.initialize();
      if (!mounted) return;
      setState(() {});
      _startScanningCycle();
    } catch (e) {
      debugPrint("Camera Init Error: $e");
    }
  }

  void _startScanningCycle() {
    if (!mounted) return;
    _captureTimer?.cancel();
    _isProcessing = false;
    _isActive = true;
    _livenessPassed = false;
    _eyesWereClosed = false;
    _resultController.reset();

    setState(() {
      _status = _ScanStatus.scanning;
      _statusMessage = "Position your face inside the frame";
    });

    _pulseController.repeat(reverse: true);
    _scanLineController.repeat();

    _captureTimer = Timer.periodic(const Duration(milliseconds: 800), (_) async {
      if (!_isActive || _isProcessing || !mounted || _controller == null || !_controller!.value.isInitialized) return;
      _isProcessing = true;
      await _checkForFace();
    });
  }

  void _stopScanningCycle() {
    _captureTimer?.cancel();
    _captureTimer = null;
    _isActive = false;
    _isProcessing = false;
    _pulseController.stop();
    _scanLineController.stop();
  }

  Future<void> _checkForFace() async {
    try {
      final XFile file = await _controller!.takePicture();
      final faces = await _fastFaceDetector.processImage(InputImage.fromFilePath(file.path));

      if (faces.isEmpty || faces.first.boundingBox.width < 80) {
        if (mounted) setState(() => _statusMessage = "Move closer to the camera.");
        _isProcessing = false;
        try { await File(file.path).delete(); } catch (_) {}
        return;
      }

      final face = faces.first;

      if (face.headEulerAngleY!.abs() > 10 || face.headEulerAngleZ!.abs() > 10) {
        if (mounted) setState(() => _statusMessage = "Look straight ahead.");
        _isProcessing = false;
        try { await File(file.path).delete(); } catch (_) {}
        return;
      }

      if (!_livenessPassed) {
        if (face.leftEyeOpenProbability != null && face.rightEyeOpenProbability != null) {
          if (face.leftEyeOpenProbability! < 0.3 && face.rightEyeOpenProbability! < 0.3) {
            _eyesWereClosed = true;
            if (mounted) setState(() => _statusMessage = "Eyes closed. Now open them.");
            _isProcessing = false;
            try {await File(file.path).delete(); } catch (_) {}
            return;
          }
          else if (_eyesWereClosed && face.leftEyeOpenProbability! > 0.8 && face.rightEyeOpenProbability! > 0.8) {
            _livenessPassed = true;
          }
          else {
            if (mounted) setState(() => _statusMessage = "Please BLINK to verify you are real.");
            _isProcessing = false;
            try {await File(file.path).delete(); } catch(_) {}
            return;
          }
        } else {
          if (mounted) setState(() => _statusMessage = "Ensure your eyes are clearly visible.");
          _isProcessing = false;
          try { await File(file.path).delete(); } catch(_) {}
          return;
        }
      }

      _stopScanningCycle();
      if (mounted) {
        setState(() {
          _status = _ScanStatus.verifying;
          _statusMessage = "Liveness verified. Processing...";
        });
      }
      await _scanFace(file.path);

    } catch (e) {
      _isProcessing = false;
    }
  }

  Future<void> _scanFace(String imagePath) async {
    try {
      final faces = await _accurateFaceDetector.processImage(InputImage.fromFilePath(imagePath));
      if (faces.isEmpty) {
        _setStatus(_ScanStatus.error, "Face lost. Retrying...");
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) _startScanningCycle();
        return;
      }

      final face = faces.first;
      final bytes = await File(imagePath).readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return _startScanningCycle();

      image = img.bakeOrientation(image);
      final int padding = (face.boundingBox.width * 0.10).toInt(); 
      final int x = (face.boundingBox.left.toInt() - padding).clamp(0, image.width - 1);
      final int y = (face.boundingBox.top.toInt() - padding).clamp(0, image.height - 1);
      final int w = (face.boundingBox.width.toInt() + (padding * 2)).clamp(1, image.width - x);
      final int h = (face.boundingBox.height.toInt() + (padding * 2)).clamp(1, image.height - y);

      final img.Image cropped = img.copyCrop(image, x: x, y: y, width: w, height: h);
      final List<double> currentVector = _mlService.predict(img.copyResize(cropped, width: 112, height: 112));

      final branchStudents = OfflineSyncService.getLocalStudents().where((s) => s['branch'] == widget.selectedBranch).toList();

      if (branchStudents.isEmpty) {
        _setStatus(_ScanStatus.notRegistered, "No local database for ${widget.selectedBranch}");
        _resultController.forward();
        await Future.delayed(const Duration(seconds: 3));
        return _startScanningCycle();
      }

      double bestDistance = double.infinity;
      Map<String, dynamic>? bestMatch;

      for (final data in branchStudents) {
        if (data['face_vector'] == null) continue;
        final List<double> sv = data['face_vector'].map<double>((e) => (e as num).toDouble()).toList();
        if (sv.length != currentVector.length) continue;

        double dotProduct = 0.0, normA = 0.0, normB = 0.0;
        for (int i = 0; i < currentVector.length; i++) {
          dotProduct += currentVector[i] * sv[i];
          normA += math.pow(currentVector[i], 2);
          normB += math.pow(sv[i], 2);
        }
        final double dist = 1.0 - (dotProduct / (math.sqrt(normA) * math.sqrt(normB)));

        if (dist < bestDistance) {
          bestDistance = dist;
          bestMatch = data;
        }
      }

      const double threshold = 0.45; 

      if (bestMatch != null && bestDistance < threshold) {
        final String name = bestMatch['name'] ?? 'Unknown';
        final String rollNo = bestMatch['roll_no'] ?? '';
        final String today = DateTime.now().toIso8601String().split('T')[0];

        bool alreadyMarked = false;
        try {
          final queue = Hive.box(OfflineSyncService.attendanceQueueBoxName);
          for (var log in queue.values) {
            if (log['roll_no'] == rollNo && log['date'] == today) {
              alreadyMarked = true; break;
            }
          }
          if (!alreadyMarked) {
            final existing = await FirebaseFirestore.instance.collection('attendance').where('roll_no', isEqualTo: rollNo).where('date', isEqualTo: today).get();
            if (existing.docs.isNotEmpty) alreadyMarked = true;
          }
        } catch (_) {}

        if (!alreadyMarked) {
          await OfflineSyncService.logAttendanceLocally({
            'name': name, 'roll_no': rollNo, 'branch': bestMatch['branch'] ?? widget.selectedBranch,
            'year': bestMatch['year'] ?? '', 'date': today, 'timestamp': DateTime.now(),
          });
          if (mounted) {
            setState(() { _matchedName = name; _matchedRoll = rollNo; });
            _setStatus(_ScanStatus.success, "Attendance Marked!");
            _resultController.forward();
          }
        } else {
          if (mounted) {
            setState(() { _matchedName = name; _matchedRoll = rollNo; });
            _setStatus(_ScanStatus.alreadyMarked, "$name — Already present.");
            _resultController.forward();
          }
        }

        await Future.delayed(const Duration(seconds: 3));

      } else {
        _setStatus(_ScanStatus.notRegistered, "Not Recognized. Score: ${bestDistance.toStringAsFixed(2)}");
        _resultController.forward();
        await Future.delayed(const Duration(seconds: 4));
      }

    } finally {
      try { await File(imagePath).delete(); } catch (_) {}
      if (mounted) _startScanningCycle();
    }
  }

  void _setStatus(_ScanStatus status, String message) {
    if (mounted) setState(() { _status = status; _statusMessage = message; });
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(backgroundColor: AppTheme.bgLight, body: const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue)));
    }

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(title: const Text("Mark Attendance")),
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_controller!)),

          Positioned(
            top: 20.h, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(20), boxShadow: AppTheme.softShadow),
                child: Text(widget.selectedBranch, style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold, fontSize: 12.sp)),
              ),
            ),
          ),

          Center(
            child: SizedBox(
              width: 260.w, height: 320.h,
              child: Stack(
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (_, _) => Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: _getBorderColor().withValues(alpha: _status == _ScanStatus.scanning ? _pulseAnimation.value : 1.0), width: _status == _ScanStatus.scanning ? 2 : 3),
                        boxShadow: [BoxShadow(color: _getBorderColor().withValues(alpha: 0.25), blurRadius: 20, spreadRadius: 2)],
                      ),
                    ),
                  ),
                  ..._buildCorners(),
                  if (_status == _ScanStatus.scanning)
                    AnimatedBuilder(
                      animation: _scanLineAnimation,
                      builder: (_, _) => Positioned(
                        top: _scanLineAnimation.value * 310.h, left: 10.w, right: 10.w,
                        child: Container(height: 3, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.transparent, AppTheme.primaryBlue, Colors.transparent]), boxShadow: [BoxShadow(color: AppTheme.primaryBlue.withValues(alpha: 0.8), blurRadius: 6)])),
                      ),
                    ),
                  if (_status == _ScanStatus.verifying)
                    Center(child: Column(mainAxisSize: MainAxisSize.min, children: [SizedBox(width: 56.w, height: 56.w, child: const CircularProgressIndicator(color: Colors.blueAccent, strokeWidth: 3)), SizedBox(height: 12.h), Text("Analyzing...", style: TextStyle(color: Colors.blueAccent, fontSize: 13.sp, fontWeight: FontWeight.w600))])),
                ],
              ),
            ),
          ),

          if (_status != _ScanStatus.scanning && _status != _ScanStatus.verifying)
            Positioned.fill(
              child: FadeTransition(
                opacity: _resultFadeAnimation,
                child: Container(
                  color: AppTheme.surfaceLight.withValues(alpha: 0.95),
                  child: Center(
                    child: ScaleTransition(
                      scale: _resultScaleAnimation,
                      child: Container(
                        width: 300.w, padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(20), border: Border.all(color: _getBorderColor(), width: 2), boxShadow: AppTheme.softShadow),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_getStatusIcon(), color: _getBorderColor(), size: 48.sp),
                            SizedBox(height: 16.h),
                            Text(_status == _ScanStatus.success ? "Welcome, $_matchedName!" : _status == _ScanStatus.notRegistered ? "Not Recognized" : _matchedName, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textDark, fontSize: 18.sp, fontWeight: FontWeight.bold)),
                            SizedBox(height: 8.h),
                            Text(_statusMessage, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.sp)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          Positioned(
            bottom: 40.h, left: 20.w, right: 20.w,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(15), boxShadow: AppTheme.softShadow),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_getStatusIcon(), color: _getBorderColor(), size: 20.sp),
                  SizedBox(width: 12.w),
                  Flexible(child: Text(_statusMessage, style: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w600, fontSize: 13.sp))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCorners() {
    const double size = 24; const double thickness = 3; final color = _getBorderColor();
    Widget corner(AlignmentGeometry align, bool flipH, bool flipV) {
      return Align(alignment: align, child: Transform.scale(scaleX: flipH ? -1 : 1, scaleY: flipV ? -1 : 1, child: SizedBox(width: size, height: size, child: CustomPaint(painter: _CornerPainter(color: color, thickness: thickness)))));
    }
    return [corner(Alignment.topLeft, false, false), corner(Alignment.topRight, true, false), corner(Alignment.bottomLeft, false, true), corner(Alignment.bottomRight, true, true)];
  }

  Color _getBorderColor() {
    switch (_status) {
      case _ScanStatus.success: return AppTheme.successGreen;
      case _ScanStatus.alreadyMarked: return AppTheme.warningAmber;
      case _ScanStatus.notRegistered: case _ScanStatus.error: return AppTheme.dangerRed;
      case _ScanStatus.verifying: return AppTheme.primaryBlue;
      default: return AppTheme.primaryBlue;
    }
  }

  IconData _getStatusIcon() {
    switch (_status) {
      case _ScanStatus.scanning: return Icons.remove_red_eye_rounded;
      case _ScanStatus.verifying: return Icons.search;
      case _ScanStatus.success: return Icons.check_circle_rounded;
      case _ScanStatus.alreadyMarked: return Icons.info_rounded;
      default: return Icons.error_rounded;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopScanningCycle();
    _pulseController.dispose();
    _scanLineController.dispose();
    _resultController.dispose();
    _controller?.dispose();
    _fastFaceDetector.close();
    _accurateFaceDetector.close();
    _mlService.dispose();
    _illuminationService.stopAutoIllumination();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _stopScanningCycle();
      _controller!.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initialize();
    }
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double thickness;
  const _CornerPainter({required this.color, required this.thickness});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = thickness..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(size.width, 0), paint);
    canvas.drawLine(Offset.zero, Offset(0, size.height), paint);
  }
  @override
  bool shouldRepaint(_CornerPainter old) => old.color != color || old.thickness != thickness;
}