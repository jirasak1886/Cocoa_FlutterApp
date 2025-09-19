import 'package:cocoa_app/api/auth_api.dart';
import 'package:cocoa_app/screens/area.dart';
import 'package:cocoa_app/screens/forgot_password_screen.dart';
import 'package:cocoa_app/screens/inspection_history_page.dart';
import 'package:cocoa_app/screens/inspection_page.dart';
import 'package:cocoa_app/screens/login_screen.dart';
import 'package:cocoa_app/screens/dashboard_screen.dart';
import 'package:cocoa_app/screens/profile_edit_page.dart';
import 'package:cocoa_app/screens/profile_page.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize authentication
  await AuthApiService.initAuth();

  runApp(CocoaApp());
}

class CocoaApp extends StatelessWidget {
  const CocoaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cocoa Farm Management',
      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'Roboto',
      ),
      home: SplashScreen(),
      routes: {
        '/login': (context) => LoginScreen(),
        '/dashboard': (context) => DashboardScreen(),
        '/field': (context) => FieldManagement(),
        '/profile': (context) => ProfilePage(),
        '/profile/edit': (context) => const ProfileEditPage(),
        '/inspection': (context) => const InspectionPage(),
        '/history': (context) => const InspectionHistoryPage(),
        '/forgot-password': (context) => ForgotPasswordScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    try {
      print('🚀 SplashScreen: Checking authentication...');

      // รอ 1 วินาทีเพื่อแสดง splash screen
      await Future.delayed(Duration(seconds: 1));

      // ตรวจสอบ authentication
      final authResult = await AuthApiService.checkAuth();

      print('🚀 SplashScreen auth result: $authResult');

      if (mounted) {
        if (authResult['authenticated'] == true) {
          print('✅ SplashScreen: User authenticated, going to dashboard');
          Navigator.of(context).pushReplacementNamed('/dashboard');
        } else {
          print('❌ SplashScreen: User not authenticated, going to login');
          Navigator.of(context).pushReplacementNamed('/login');
        }
      }
    } catch (e) {
      print('❌ SplashScreen error: $e');

      if (mounted) {
        // เกิดข้อผิดพลาด ให้ไปหน้า login
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              padding: EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    spreadRadius: 5,
                    blurRadius: 15,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(Icons.agriculture, size: 80, color: Colors.green),
            ),

            SizedBox(height: 30),

            // App Title
            Text(
              'ระบบจัดการสวนโกโก้',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),

            SizedBox(height: 10),

            Text(
              'Cocoa Farm Management',
              style: TextStyle(fontSize: 16, color: Colors.white70),
            ),

            SizedBox(height: 50),

            // Loading indicator
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),

            SizedBox(height: 20),

            Text(
              'กำลังเข้าสู่ระบบ...',
              style: TextStyle(fontSize: 16, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
