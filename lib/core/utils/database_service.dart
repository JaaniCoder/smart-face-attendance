import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<Map<String, List<double>>> loadRegisteredUsers() async {
    Map<String, List<double>> usersMap = {};
    try {
      var snapshot = await _db.collection('users').get();
      for (var doc in snapshot.docs) {
        List<double> embedding = List<double>.from(doc.data()['embedding']);
        usersMap[doc.data()['name']] = embedding;
      }
    } catch (e) {
      print("Error fetching users: $e");
    }
    return usersMap;
  }

  Future<void> saveUser(String name, List<double> embedding) async {
    try {
      await _db.collection('users').add({
        'name': name,
        'embedding': embedding,
        'createdAt': DateTime.now(),
      });
    } catch (e) {
      print("Error registering user: $e");
    }
  }
}