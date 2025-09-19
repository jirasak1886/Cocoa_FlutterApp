import 'package:cocoa_app/api/auth_api.dart';
import 'package:flutter/material.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  bool _isAuthenticated = false;
  Map<String, dynamic>? _userData;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    // ✅ เรียกหลังเฟรมแรก เพื่อลดโอกาส race กับการ set token หลัง login
    WidgetsBinding.instance.addPostFrameCallback((_) => _guardAuth());
  }

  /// ตรวจสิทธิ์ด้วย retry 1 ครั้งกัน race และอย่าล้าง token เองเมื่อ 401 ที่ไม่ชัดเจน
  Future<void> _guardAuth() async {
    try {
      debugPrint('🔍 Dashboard: Checking authentication (attempt 1)...');
      var authResult = await AuthApiService.checkAuth();
      debugPrint('🔍 Dashboard auth result #1: $authResult');

      var authed = authResult['authenticated'] == true;

      if (!authed) {
        // กัน race: รอสั้นๆ แล้วลองใหม่
        await Future.delayed(const Duration(milliseconds: 200));
        debugPrint('🔁 Dashboard: Retrying authentication (attempt 2)...');
        authResult = await AuthApiService.checkAuth();
        debugPrint('🔍 Dashboard auth result #2: $authResult');
        authed = authResult['authenticated'] == true;
      }

      if (!mounted) return;
      setState(() {
        _isAuthenticated = authed;
        _userData = authResult['user'];
        _isLoading = false;
        if (!authed) {
          _errorMessage = authResult['message'] ?? 'ไม่มีสิทธิ์เข้าถึง';
        }
      });

      if (!authed) {
        debugPrint('❌ Dashboard: Not authenticated → navigating to /login');
        _goLogin();
      } else {
        debugPrint('✅ Dashboard: Authentication successful');
      }
    } catch (e) {
      debugPrint('❌ Dashboard auth error: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isAuthenticated = false;
        _errorMessage = 'เกิดข้อผิดพลาดในการตรวจสอบสิทธิ์';
      });
      _goLogin();
    }
  }

  void _goLogin() {
    // นำทางทันทีแบบไม่หน่วง (ประสบการณ์ลื่นกว่า)
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacementNamed('/login', arguments: {'reason': 'auth_failed'});
  }

  Future<void> _handleLogout() async {
    try {
      await AuthApiService.logout();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/login');
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

    // Authentication failed screen (จะเห็นแค่แว้บเดียวก่อน navigate ใน _goLogin)
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
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: 'ย้อนกลับ',
              )
            : null,
        actions: [
          if (isLargeScreen)
            TextButton.icon(
              onPressed: _handleLogout,
              icon: const Icon(Icons.logout, color: Colors.white),
              label: const Text(
                'ออกจากระบบ',
                style: TextStyle(color: Colors.white),
              ),
            )
          else
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'logout') _handleLogout();
              },
              tooltip: 'เมนู',
              itemBuilder: (context) => const [
                PopupMenuItem(
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
          final isLarge = _isLargeScreen(context);
          return Center(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: isLarge ? 1200 : double.infinity,
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isLarge ? 32 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWelcomeCard(isLarge),
                    SizedBox(height: isLarge ? 32 : 24),
                    Text(
                      'เมนูหลัก',
                      style: TextStyle(
                        fontSize: isLarge ? 22 : 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    SizedBox(height: isLarge ? 20 : 16),
                    _buildMenuGrid(context, isLarge),
                    SizedBox(height: isLarge ? 32 : 24),
                    // ถ้าต้องการ debug card ให้เปิดใช้ได้
                    // if (kDebugMode) _buildDebugCard(isLarge),
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
          Icons.yard,
          Colors.green,
          isLargeScreen,
          () => Navigator.of(context).pushNamed('/field'),
        ),
        _buildMenuCard(
          'ตรวจสอบพืช',
          Icons.biotech,
          Colors.orange,
          isLargeScreen,
          () => Navigator.of(context).pushNamed('/inspection'),
        ),
        _buildMenuCard(
          'ประวัติการตรวจสอบ',
          Icons.history,
          Colors.purple,
          isLargeScreen,
          () => Navigator.of(context).pushNamed('/history'),
        ),
        _buildMenuCard(
          'โปรไฟล์',
          Icons.person,
          Colors.blue,
          isLargeScreen,
          () => Navigator.of(context).pushNamed('/profile'),
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
