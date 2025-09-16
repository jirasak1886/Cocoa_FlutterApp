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

  // ฟังก์ชันสำหรับตรวจสอบว่าเป็นหน้าจอขนาดใหญ่หรือไม่
  bool _isLargeScreen(BuildContext context) {
    return MediaQuery.of(context).size.width >= 768;
  }

  // ฟังก์ชันสำหรับคำนวณจำนวนคอลัมน์ตามขนาดหน้าจอ
  int _getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1200) return 4; // Desktop large
    if (width >= 768) return 3; // Tablet/Desktop small
    return 2; // Mobile
  }

  // ฟังก์ชันสำหรับคำนวณ child aspect ratio
  double _getChildAspectRatio(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 768) return 1.1; // Desktop/Tablet - ให้การ์ดสูงขึ้นเล็กน้อย
    return 1.0; // Mobile - รูปสี่เหลี่ยมจัตุรัส
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = _isLargeScreen(context);
    final screenWidth = MediaQuery.of(context).size.width;

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
                style: TextStyle(
                  fontSize: isLargeScreen ? 18 : 16,
                  color: Colors.grey[600],
                ),
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
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: isLargeScreen ? 100 : 80,
                  color: Colors.red,
                ),
                const SizedBox(height: 20),
                Text(
                  'ไม่มีสิทธิ์เข้าถึง',
                  style: TextStyle(
                    fontSize: isLargeScreen ? 24 : 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _errorMessage,
                  style: TextStyle(
                    fontSize: isLargeScreen ? 18 : 16,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                Text(
                  'กำลังนำคุณกลับสู่หน้าเข้าสู่ระบบ...',
                  style: TextStyle(
                    fontSize: isLargeScreen ? 16 : 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Main Dashboard Screen
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'CocoaDetect',
          style: TextStyle(
            fontSize: isLargeScreen ? 20 : 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: !isLargeScreen, // Center title บนมือถือ
        // ปุ่มย้อนกลับ
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: 'ย้อนกลับ',
              )
            : null,

        actions: [
          // สำหรับหน้าจอใหญ่ - แสดงข้อความ logout
          if (isLargeScreen)
            TextButton.icon(
              onPressed: _handleLogout,
              icon: const Icon(Icons.logout, color: Colors.white),
              label: const Text(
                'ออกจากระบบ',
                style: TextStyle(color: Colors.white),
              ),
            )
          // สำหรับมือถือ - ใช้ popup menu
          else
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'logout') {
                  _handleLogout();
                }
              },
              tooltip: 'เมนู',
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
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // สำหรับหน้าจอใหญ่ - จำกัดความกว้างสูงสุด
          return Center(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: isLargeScreen ? 1200 : double.infinity,
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isLargeScreen ? 32 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Welcome Card
                    _buildWelcomeCard(isLargeScreen),

                    SizedBox(height: isLargeScreen ? 32 : 24),

                    // Menu Section
                    Text(
                      'เมนูหลัก',
                      style: TextStyle(
                        fontSize: isLargeScreen ? 22 : 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    SizedBox(height: isLargeScreen ? 20 : 16),

                    // Menu Grid
                    _buildMenuGrid(context, isLargeScreen),

                    SizedBox(height: isLargeScreen ? 32 : 24),

                    // Debug Info (เฉพาะ Debug mode)
                    // if (true) // เปลี่ยนเป็น kDebugMode ในโปรดักชัน
                    //   _buildDebugCard(isLargeScreen),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWelcomeCard(bool isLargeScreen) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isLargeScreen ? 28 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isLargeScreen ? 16 : 12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(isLargeScreen ? 12 : 8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.agriculture,
                  size: isLargeScreen ? 48 : 40,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ยินดีต้อนรับ',
                      style: TextStyle(
                        fontSize: isLargeScreen ? 18 : 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _userData?['name'] ?? _userData?['username'] ?? 'ผู้ใช้',
                      style: TextStyle(
                        fontSize: isLargeScreen ? 24 : 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: isLargeScreen ? 20 : 16),
          Container(
            padding: EdgeInsets.all(isLargeScreen ? 16 : 12),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Text(
                  'เข้าสู่ระบบสำเร็จ',
                  style: TextStyle(
                    color: Colors.green[800],
                    fontWeight: FontWeight.w500,
                    fontSize: isLargeScreen ? 16 : 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuGrid(BuildContext context, bool isLargeScreen) {
    final crossAxisCount = _getCrossAxisCount(context);
    final childAspectRatio = _getChildAspectRatio(context);

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: isLargeScreen ? 24 : 16,
      mainAxisSpacing: isLargeScreen ? 24 : 16,
      childAspectRatio: childAspectRatio,
      children: [
        _buildMenuCard(
          'จัดการแปลง',
          Icons
              .yard, // เปลี่ยนจาก Icons.landscape เป็น Icons.yard (สำหรับแปลงปลูก)
          Colors.green,
          isLargeScreen,
          () {
            Navigator.of(context).pushNamed('/field');
            print('Navigate to fields management');
          },
        ),
        _buildMenuCard(
          'ตรวจสอบพืช',
          Icons
              .biotech, // เปลี่ยนจาก Icons.search เป็น Icons.biotech (สำหรับการตรวจสอบทางวิทยาศาสตร์)
          Colors.orange,
          isLargeScreen,
          () {
            Navigator.of(context).pushNamed('/inspection');
            print('Navigate to plant inspection');
          },
        ),
        _buildMenuCard(
          'ประวัติการตรวจสอบ',
          Icons
              .history, // เปลี่ยนจาก Icons.analytics เป็น Icons.history (สำหรับประวัติ)
          Colors.purple,
          isLargeScreen,
          () {
            Navigator.of(context).pushNamed('/history');
            print('Navigate to reports');
          },
        ),
        _buildMenuCard(
          'โปรไฟล์',
          Icons
              .person, // เปลี่ยนจาก Icons.settings เป็น Icons.person (สำหรับโปรไฟล์)
          Colors.blue,
          isLargeScreen,
          () {
            Navigator.of(context).pushNamed('/profile');
            print('Navigate to settings');
          },
        ),
      ],
    );
  }

  Widget _buildMenuCard(
    String title,
    IconData icon,
    Color color,
    bool isLargeScreen,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(isLargeScreen ? 16 : 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(isLargeScreen ? 16 : 12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 2,
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(isLargeScreen ? 20 : 16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(isLargeScreen ? 16 : 12),
                ),
                child: Icon(icon, size: isLargeScreen ? 48 : 40, color: color),
              ),
              SizedBox(height: isLargeScreen ? 16 : 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: isLargeScreen ? 18 : 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
