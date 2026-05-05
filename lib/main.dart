import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'core/utils/offline_sync_service.dart';
import 'features/management/presentation/admin_panel_screen.dart';
import 'features/registration/presentation/login_screen.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'features/registration/presentation/registration_screen.dart';
import 'features/attendance/presentation/attendance_screen.dart';
import 'features/attendance/presentation/attendance_history_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
    await OfflineSyncService.init();
    await OfflineSyncService.syncStudentsToLocal();
    await OfflineSyncService.syncAttendanceToFirebase();
  } catch (e) {
    debugPrint("Firebase Initialization Error: $e");
  }

  runApp(const ProviderScope(child: SmartAttendanceApp()));
}

class SmartAttendanceApp extends StatelessWidget {
  const SmartAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 690),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          title: 'Smart Face Attendance',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          initialRoute: '/',
          onGenerateRoute: (settings) {
            switch (settings.name) {
              case '/': return _fadeRoute(const AuthGate());
              case '/login': return _fadeRoute(const LoginScreen());
              case '/registration': return _slideRoute(const RegistrationScreen());
              case '/admin': return _slideRoute(const AdminPanelScreen());
              case '/history': return _slideRoute(const AttendanceHistoryScreen());
              case '/attendance':
                final branch = settings.arguments as String? ?? 'Default';
                return _slideRoute(AttendanceScreen(selectedBranch: branch));
              default: return _fadeRoute(const InitialCheckScreen());
            }
          },
        );
      },
    );
  }

  static PageRouteBuilder _fadeRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, animation, _) => page,
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 350),
    );
  }

  static PageRouteBuilder _slideRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, animation, _) => page,
      transitionsBuilder: (_, animation, _, child) {
        final tween = Tween(begin: const Offset(0, 0.06), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic));
        return FadeTransition(opacity: animation, child: SlideTransition(position: animation.drive(tween), child: child));
      },
      transitionDuration: const Duration(milliseconds: 400),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<auth.User?>(
      stream: auth.FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue)));
        } 
        if (snapshot.hasData) return const InitialCheckScreen();
        return const LoginScreen();
      },
    );
  }
}

class InitialCheckScreen extends StatefulWidget {
  const InitialCheckScreen({super.key});
  @override
  State<InitialCheckScreen> createState() => _InitialCheckScreenState();
}

class _InitialCheckScreenState extends State<InitialCheckScreen> with TickerProviderStateMixin {
  late AnimationController _bootController;
  late Animation<double> _bootAnim;

  @override
  void initState() {
    super.initState();
    _bootController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _bootAnim = CurvedAnimation(parent: _bootController, curve: Curves.easeOut);
    _bootController.forward();
  }

  @override
  void dispose() {
    _bootController.dispose();
    super.dispose();
  }

  void _showBranchPicker(BuildContext context) {
    final branches = [
      'Computer Science & Engineering',
      'Computer Science & Engineering (AI & ML)',
      'Electronics & Communication Engineering',
      'Mechanical Engineering',
      'Civil Engineering',
      'Electrical Engineering',
    ];

    final rootNavigator = Navigator.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _BranchPickerSheet(
        branches: branches,
        onBranchSelected: (branch) {
          Navigator.pop(sheetContext); 
          rootNavigator.pushNamed('/attendance', arguments: branch); 
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: FadeTransition(
                  opacity: _bootAnim,
                  child: Column(
                    children: [
                      SizedBox(height: 40.h),
                      _buildHeader(),
                      const Spacer(),
                      _buildBiometricIcon(),
                      const Spacer(),
                      _buildActionButtons(context),
                      SizedBox(height: 30.h),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text("SYSTEM ACTIVE", style: TextStyle(color: AppTheme.primaryBlue, fontSize: 10.sp, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        ),
        SizedBox(height: 16.h),
        Text("Smart Attendance", style: TextStyle(color: AppTheme.textDark, fontSize: 24.sp, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
        Text("FACIAL RECOGNITION PORTAL", style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.sp, fontWeight: FontWeight.w600, letterSpacing: 2)),
      ],
    );
  }

  Widget _buildBiometricIcon() {
    return Container(
      width: 140.w,
      height: 140.w,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.surfaceLight,
        boxShadow: AppTheme.softShadow,
      ),
      child: Icon(Icons.face_unlock_rounded, size: 70.sp, color: AppTheme.primaryBlue),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Column(
        children: [
          _CleanButton(label: "REGISTER STUDENT", icon: Icons.person_add_rounded, color: AppTheme.primaryBlue, onPressed: () => Navigator.pushNamed(context, '/registration')),
          SizedBox(height: 14.h),
          _CleanButton(label: "MARK ATTENDANCE", icon: Icons.fingerprint_rounded, color: AppTheme.successGreen, onPressed: () => _showBranchPicker(context)),
          SizedBox(height: 14.h),
          _CleanButton(label: "ATTENDANCE LOGS", icon: Icons.history_rounded, color: AppTheme.textSecondary, onPressed: () => Navigator.pushNamed(context, '/history')),
          SizedBox(height: 14.h),
          _CleanButton(label: "MANAGE DATABASE", icon: Icons.admin_panel_settings_rounded, color: AppTheme.warningAmber, onPressed: () => Navigator.pushNamed(context, '/admin')),
          SizedBox(height: 14.h),
          TextButton.icon(
            onPressed: () async {
              showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue)));
              await Future.delayed(const Duration(seconds: 1));
              await auth.FirebaseAuth.instance.signOut();
              if (context.mounted) Navigator.pop(context);
            },
            icon: Icon(Icons.logout_rounded, color: AppTheme.dangerRed, size: 18.sp),
            label: Text("Logout", style: TextStyle(color: AppTheme.dangerRed, fontWeight: FontWeight.bold, fontSize: 13.sp)),
          )
        ],
      ),
    );
  }
}

class _CleanButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _CleanButton({required this.label, required this.icon, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        height: 56.h,
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderSubtle),
          boxShadow: AppTheme.softShadow,
        ),
        child: Row(
          children: [
            SizedBox(width: 20.w),
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20.sp)),
            SizedBox(width: 16.w),
            Text(label, style: TextStyle(color: AppTheme.textDark, fontSize: 13.sp, fontWeight: FontWeight.w700)),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 20.sp),
            SizedBox(width: 20.w),
          ],
        ),
      ),
    );
  }
}

class _BranchPickerSheet extends StatelessWidget {
  final List<String> branches;
  final void Function(String branch) onBranchSelected;

  const _BranchPickerSheet({required this.branches, required this.onBranchSelected});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        color: AppTheme.surfaceLight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 12.h),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.borderSubtle, borderRadius: BorderRadius.circular(2))),
            SizedBox(height: 20.h),
            Text("Select Branch", style: TextStyle(color: AppTheme.textDark, fontSize: 16.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 10.h),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: branches.map((branch) => ListTile(
                    contentPadding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 4.h),
                    leading: const Icon(Icons.business_rounded, color: AppTheme.primaryBlue),
                    title: Text(branch, style: TextStyle(color: AppTheme.textDark, fontSize: 13.sp, fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.textMuted),
                    onTap: () => onBranchSelected(branch),
                  )).toList(),
                ),
              ),
            ),
            SizedBox(height: 20.h),
          ],
        ),
      ),
    );
  }
}