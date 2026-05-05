import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passController = TextEditingController();

  bool _isPoweredOn = false;
  bool _loading = false;

  late AnimationController _pulseController;
  late Animation<double> _glowPadding;
  
  late AnimationController _scanController;
  late Animation<double> _scanAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 1500)
    )..repeat(reverse: true);
    
    _glowPadding = Tween<double>(begin: 2.0, end: 12.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut)
    );

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _scanAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.easeInOut)
    );
  }

  Future<void> _login() async {
    if (_emailController.text.isEmpty || _passController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter credentials"), backgroundColor: AppTheme.warningAmber),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(), 
        password: _passController.text
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("System Error: ${e.toString().split(']').last}"), backgroundColor: AppTheme.dangerRed),
      );
    }
    if (mounted) setState(() => _loading = false);
  }

  void _togglePower() {
    setState(() => _isPoweredOn = !_isPoweredOn);
    if (_isPoweredOn) {
      _scanController.repeat(reverse: true);
    } else {
      _scanController.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: Stack(
        children: [
          // ─── Glowing Bulb Toggle ───
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: _togglePower,
                  child: AnimatedBuilder(
                    animation: _glowPadding,
                    builder: (context, child) {
                      return Container(
                        padding: EdgeInsets.all(_isPoweredOn ? _glowPadding.value : 0),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: _isPoweredOn
                              ? [BoxShadow(
                                  color: AppTheme.primaryBlue.withValues(alpha: 0.4), 
                                  blurRadius: 30, 
                                  spreadRadius: _glowPadding.value)]
                              : [],
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.surfaceLight,
                            border: Border.all(
                              color: _isPoweredOn ? AppTheme.primaryBlue : AppTheme.borderSubtle, 
                              width: 2
                            ),
                            boxShadow: AppTheme.softShadow,
                          ),
                          child: Icon(
                            _isPoweredOn ? Icons.wb_sunny_rounded : Icons.radio_button_off_rounded,
                            size: 65.sp,
                            // Soft red when off, bright blue when on!
                            color: _isPoweredOn ? AppTheme.primaryBlue : AppTheme.secondaryBlue.withValues(alpha: 0.5),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: 24.h),
                Text(
                  _isPoweredOn ? "CORE ONLINE" : "TAP TO INITIALIZE POWER",
                  style: TextStyle(
                    color: _isPoweredOn ? AppTheme.primaryBlue : AppTheme.textSecondary,
                    letterSpacing: 3,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          AnimatedPositioned(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutBack,
            bottom: _isPoweredOn ? 40.h : -400.h,
            left: 20.w,
            right: 20.w,
            child: Stack(
              children: [
                Container(
                  padding: EdgeInsets.all(24.w),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.borderSubtle),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, -4))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("Admin Portal", style: TextStyle(color: AppTheme.textDark, fontSize: 18.sp, fontWeight: FontWeight.bold)),
                      SizedBox(height: 20.h),
                      _buildTextField("AUTH ID", _emailController, false, Icons.email_outlined),
                      SizedBox(height: 16.h),
                      _buildTextField("ACCESS KEY", _passController, true, Icons.lock_outline),
                      SizedBox(height: 24.h),
                      ElevatedButton(
                        onPressed: _login,
                        child: const Text("INITIATE CORE"),
                      )
                    ],
                  ),
                ),

                // Sweeping Scanner Line
                if (_isPoweredOn)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _scanAnimation,
                      builder: (context, child) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Stack(
                            children: [
                              Positioned(
                                top: _scanAnimation.value * 300.h - 10,
                                left: 0,
                                right: 0,
                                child: Container(
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryBlue,
                                    boxShadow: [
                                      BoxShadow(color: AppTheme.primaryBlue.withValues(alpha: 0.6), blurRadius: 10, spreadRadius: 2)
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          if (_loading)
            Positioned.fill(
              child: Container(
                color: AppTheme.bgLight.withValues(alpha: 0.85),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppTheme.primaryBlue),
                      SizedBox(height: 24.h),
                      Text("ESTABLISHING SECURE CONNECTION...", style: TextStyle(color: AppTheme.primaryBlue, letterSpacing: 2, fontSize: 12.sp, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, bool obscure, IconData icon) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanController.dispose();
    _emailController.dispose();
    _passController.dispose();
    super.dispose();
  }
}