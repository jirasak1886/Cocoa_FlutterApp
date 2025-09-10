import 'package:cocoa_app/api/auth_api.dart';
import 'package:flutter/material.dart';

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  bool _isAuthenticated = false;
  Map<String, dynamic>? _userData;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    try {
      print('🔍 Dashboard: Checking authentication...');

      final authResult = await AuthApiService.checkAuth();

      print('🔍 Dashboard auth result: $authResult');

      if (mounted) {
        setState(() {
          _isAuthenticated = authResult['authenticated'] ?? false;
          _userData = authResult['user'];
          _isLoading = false;

          if (!_isAuthenticated) {
            _errorMessage = authResult['message'] ?? 'ไม่มีสิทธิ์เข้าถึง';
          }
        });

        if (!_isAuthenticated) {
          print('❌ Dashboard: Not authenticated, redirecting to login...');
          _redirectToLogin();
        } else {
          print('✅ Dashboard: Authentication successful');
        }
      }
    } catch (e) {
      print('❌ Dashboard auth error: $e');

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isAuthenticated = false;
          _errorMessage = 'เกิดข้อผิดพลาดในการตรวจสอบสิทธิ์';
        });
        _redirectToLogin();
      }
    }
  }

  void _redirectToLogin() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    });
  }

  Future<void> _handleLogout() async {
    try {
      await AuthApiService.logout();

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (e) {
      print('Logout error: $e');
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Loading screen
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.green),
              const SizedBox(height: 20),
              Text(
                'กำลังตรวจสอบสิทธิ์...',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    // Authentication failed screen
    if (!_isAuthenticated) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 80, color: Colors.red),
              const SizedBox(height: 20),
              const Text(
                'ไม่มีสิทธิ์เข้าถึง',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _errorMessage,
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              Text(
                'กำลังนำคุณกลับสู่หน้าเข้าสู่ระบบ...',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    }

    // Main Dashboard Screen
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('แดชบอร์ด'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,

        // ⬅️ ปุ่มย้อนกลับ: โชว์เฉพาะเมื่อมีหน้าก่อนหน้าในสแตก
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,

        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                _handleLogout();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 8),
                    Text('ออกจากระบบ'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    // ❗️แก้ withValues → withOpacity
                    color: Colors.grey.withValues(alpha: 0.1),
                    spreadRadius: 2,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.agriculture,
                        size: 40,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ยินดีต้อนรับ',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              _userData?['name'] ??
                                  _userData?['username'] ??
                                  'ผู้ใช้',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.verified,
                          color: Colors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'เข้าสู่ระบบสำเร็จ',
                          style: TextStyle(
                            color: Colors.green[800],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Menu Grid
            Text(
              'เมนูหลัก',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 16),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: [
                _buildMenuCard('จัดการแปลง', Icons.landscape, Colors.blue, () {
                  // ✅ เปลี่ยนเป็น pushNamed เพื่อให้ย้อนกลับได้
                  Navigator.of(context).pushNamed('/field');
                  print('Navigate to fields management');
                }),
                _buildMenuCard('ตรวจสอบพืช', Icons.search, Colors.orange, () {
                  Navigator.of(context).pushNamed('/inspection');
                  print('Navigate to plant inspection');
                }),
                _buildMenuCard('รายงาน', Icons.analytics, Colors.purple, () {
                  //Navigator.of(context).pushNamed('/history');
                  print('Navigate to reports');
                }),
                _buildMenuCard('ตั้งค่า', Icons.settings, Colors.grey, () {
                  // ✅ เปลี่ยนเป็น pushNamed เพื่อให้ย้อนกลับได้
                  Navigator.of(context).pushNamed('/profile');
                  print('Navigate to settings');
                }),
              ],
            ),

            const SizedBox(height: 24),

            // Debug Info Card (เฉพาะ Debug mode)
            if (true) // เปลี่ยนเป็น kDebugMode ในโปรดักชัน
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.yellow[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.yellow[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ข้อมูลการเข้าสู่ระบบ (Debug)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('User ID: ${_userData?['user_id']}'),
                    Text('Username: ${_userData?['username']}'),
                    Text('Name: ${_userData?['name']}'),
                    const SizedBox(height: 8),
                    Text(
                      'Token Remaining: ${AuthApiService.getTokenRemainingDays()} วัน',
                      style: TextStyle(
                        color: AuthApiService.getTokenRemainingDays() < 7
                            ? Colors.red
                            : Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              spreadRadius: 2,
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 40, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
