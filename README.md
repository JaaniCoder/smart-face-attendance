# 🛡️ Smart Face Attendance System (Enterprise-Grade)

A highly secure, offline-first Flutter application designed to automate student/employee attendance using Facial Recognition, Active Liveness Detection, and Geofencing.

## ✨ Core Features
* **Biometric Facial Recognition:** Powered by Google ML Kit to extract and compare facial vectors using Cosine Distance math.
* **Anti-Spoofing (Active Liveness):** Implements a real-time "Blink Challenge" and strict Euler-angle head alignment checks to completely block smartphone video and photo presentation attacks.
* **Geofencing & Time-Fencing:** Integrates GPS validation to ensure attendance is only marked within a 200-meter radius of the campus and within designated operational hours.
* **Offline-First Architecture:** Utilizes `Hive` NoSQL local vaults. If the campus Wi-Fi drops, attendance logs are securely cached on the device and automatically synced to Firebase when the connection is restored.
* **Admin Dashboard:** Features real-time data visualization using `fl_chart` and 1-click exporting to Excel (.xlsx) files.

## 🛠️ Tech Stack
* **Framework:** Flutter / Dart
* **Backend:** Firebase (Firestore, Auth)
* **Machine Learning:** Google ML Kit (Face Detection API)
* **Local Database:** Hive
* **Hardware APIs:** Camera, Geolocator, Haptic Feedback

## 🚀 Setup Instructions
1. Clone the repository.
2. Connect to your own Firebase project by adding your `google-services.json` to `android/app/`.
3. Update the `campusLat` and `campusLng` variables in `attendance_screen.dart` to your location.
4. Run `flutter pub get` and `flutter run`.