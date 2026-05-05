import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class OfflineSyncService {
    static const String studentsBoxName = 'students_cache';
    static const String attendanceQueueBoxName = 'attendance_queue';

    static Future<void> init() async {
        await Hive.initFlutter();
        await Hive.openBox(studentsBoxName);
        await Hive.openBox(attendanceQueueBoxName);
    }

    static Future<void> syncStudentsToLocal() async {
        try {
            final List<ConnectivityResult> connectivityResult = await (Connectivity().checkConnectivity());
            if (connectivityResult.contains(ConnectivityResult.none)) {
                debugPrint("Offline: Using existing local student cache");
                return;
            }
            final snapshot = await FirebaseFirestore.instance.collection('students').get();
            final box = Hive.box(studentsBoxName);

            await box.clear();

            for (var doc in snapshot.docs) {
                var data = doc.data();
                data['doc_id'] = doc.id;

                if (data['registered_at'] is Timestamp) {
                  data['registered_at'] = (data['registered_at'] as Timestamp).toDate().toIso8601String();
                }
                await box.put(doc.id, data);
            }
            debugPrint("Value Secured: ${snapshot.docs.length} students cached offline.");
        } catch(e) {
            debugPrint("Error syncing students: $e");
        }
    }

    static Future<void> logAttendanceLocally(Map<String, dynamic> attendanceData) async {
        final box = Hive.box(attendanceQueueBoxName);
        String localId = "log_${DateTime.now().millisecondsSinceEpoch}";

        if (attendanceData['timestamp'] is Timestamp) {
            attendanceData['timestamp'] = (attendanceData['timestamp'] as Timestamp).toDate().toIso8601String();
        }
        await box.put(localId, attendanceData);
        debugPrint("Saved locally: $localId");

        syncAttendanceToFirebase();
    }

    static Future<void> syncAttendanceToFirebase() async {
        try {
            final List<ConnectivityResult> connectivityResult = await (Connectivity().checkConnectivity());
            if (connectivityResult.contains(ConnectivityResult.none)) return;

            final box = Hive.box(attendanceQueueBoxName);
            if (box.isEmpty) return;

            final keys = box.keys.toList();
            final batch = FirebaseFirestore.instance.batch();

            for (var key in keys) {
                final data = Map<String, dynamic>.from(box.get(key));

                if (data['timestamp'] is String) {
                    data['timestamp'] = Timestamp.fromDate(DateTime.parse(data['timestamp']));
                }
                final docRef = FirebaseFirestore.instance.collection('attendance').doc();
                batch.set(docRef, data);
            }
            await batch.commit();

            await box.deleteAll(keys);
            debugPrint("Cloud Sync Complete: Uploaded ${keys.length} logs.");
        } catch(e) {
            debugPrint("Error syncing attendance: $e");
        }
    }

    static List<Map<String, dynamic>> getLocalStudents() {
        final box = Hive.box(studentsBoxName);
        return box.values.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
}