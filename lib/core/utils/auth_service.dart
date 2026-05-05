import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Login with Email/Password
  Future<UserCredential?> signIn(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  // Check if current user is Admin
  Future<bool> isAdmin() async {
    User? user = _auth.currentUser;
    if (user == null) return false;
    
    DocumentSnapshot doc = await _firestore.collection('users').doc(user.email).get();
    if (doc.exists) {
      return doc['role'] == 'admin';
    }
    return false;
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}