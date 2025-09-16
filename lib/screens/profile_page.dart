import 'package:cocoa_app/api/auth_api.dart';
import 'package:flutter/material.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? userData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => isLoading = true);
    final result = await AuthApiService.checkAuth();
    if (result['success'] == true && result['authenticated'] == true) {
      setState(() {
        userData = result['user'];
        isLoading = false;
      });
    } else {
      setState(() {
        userData = null;
        isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    // แสดง confirmation dialog
    final shouldLogout = await _showLogoutConfirmation();
    if (!shouldLogout) return;

    try {
      await AuthApiService.logout();
      if (mounted) {
        Navigator.pushReplacementNamed(context, "/login");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('เกิดข้อผิดพลาดในการออกจากระบบ'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _showLogoutConfirmation() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการออกจากระบบ'),
        content: const Text('คุณต้องการออกจากระบบใช่หรือไม่?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('ออกจากระบบ'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _goEdit() async {
    if (userData == null) return;
    final updated = await Navigator.pushNamed(
      context,
      "/profile/edit",
      arguments: userData,
    );
    // ถ้าแก้ไขสำเร็จ จะ pop(true) กลับมา
    if (updated == true) {
      await _loadProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('อัปเดตโปรไฟล์เรียบร้อย'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  // ฟังก์ชันตรวจสอบขนาดหน้าจอ
  bool _isLargeScreen(BuildContext context) {
    return MediaQuery.of(context).size.width >= 768;
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = _isLargeScreen(context);
    final u = userData;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          "โปรไฟล์",
          style: TextStyle(
            fontSize: isLargeScreen ? 20 : 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: !isLargeScreen,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: 'ย้อนกลับ',
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadProfile,
            tooltip: 'รีเฟรช',
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _goEdit,
            tooltip: 'แก้ไขโปรไฟล์',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: isLoading
          ? _buildLoadingScreen(isLargeScreen)
          : u == null
          ? _buildErrorScreen(isLargeScreen)
          : _buildProfileContent(context, u, isLargeScreen),
    );
  }

  Widget _buildLoadingScreen(bool isLargeScreen) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.green),
          const SizedBox(height: 20),
          Text(
            'กำลังโหลดโปรไฟล์...',
            style: TextStyle(
              fontSize: isLargeScreen ? 18 : 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorScreen(bool isLargeScreen) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_off,
              size: isLargeScreen ? 80 : 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 20),
            Text(
              "ไม่พบข้อมูลผู้ใช้",
              style: TextStyle(
                fontSize: isLargeScreen ? 20 : 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "กรุณาเข้าสู่ระบบใหม่",
              style: TextStyle(
                fontSize: isLargeScreen ? 16 : 14,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadProfile,
              icon: const Icon(Icons.refresh),
              label: const Text("ลองอีกครั้ง"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileContent(
    BuildContext context,
    Map<String, dynamic> u,
    bool isLargeScreen,
  ) {
    return Center(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: isLargeScreen ? 600 : double.infinity,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isLargeScreen ? 32 : 20),
          child: Column(
            children: [
              // Profile Header Card
              _buildProfileHeaderCard(u, isLargeScreen),

              SizedBox(height: isLargeScreen ? 32 : 24),

              // Profile Info Cards
              _buildProfileInfoCards(u, isLargeScreen),

              SizedBox(height: isLargeScreen ? 32 : 24),

              // Token Info Card
              _buildTokenInfoCard(isLargeScreen),

              SizedBox(height: isLargeScreen ? 40 : 32),

              // Action Buttons
              _buildActionButtons(isLargeScreen),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeaderCard(Map<String, dynamic> u, bool isLargeScreen) {
    final userName = u['name'] ?? u['username'] ?? 'ผู้ใช้';
    final firstChar = userName.toString().trim().isNotEmpty
        ? userName.toString().trim().substring(0, 1).toUpperCase()
        : '?';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isLargeScreen ? 32 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isLargeScreen ? 20 : 16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 2,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Avatar
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.2),
                  spreadRadius: 4,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: isLargeScreen ? 50 : 40,
              backgroundColor: Colors.green,
              child: Text(
                firstChar,
                style: TextStyle(
                  fontSize: isLargeScreen ? 36 : 30,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          SizedBox(height: isLargeScreen ? 24 : 20),

          // Username badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: Text(
              'Username : '
              "${u['username'] ?? '-'}",
              style: TextStyle(
                fontSize: isLargeScreen ? 16 : 14,
                fontWeight: FontWeight.w500,
                color: Colors.green[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileInfoCards(Map<String, dynamic> u, bool isLargeScreen) {
    return Column(
      children: [
        _buildInfoCard(
          Icons.phone,
          'เบอร์โทรศัพท์',
          u['user_tel'] ?? 'ไม่ได้ระบุ',
          Colors.blue,
          isLargeScreen,
        ),
        SizedBox(height: isLargeScreen ? 16 : 12),
        _buildInfoCard(
          Icons.person,
          'ชื่อ-นามสกุล',
          u['name'] ?? 'ไม่ได้ระบุ',
          Colors.purple,
          isLargeScreen,
        ),
      ],
    );
  }

  Widget _buildInfoCard(
    IconData icon,
    String title,
    String value,
    Color color,
    bool isLargeScreen,
  ) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isLargeScreen ? 20 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isLargeScreen ? 16 : 12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isLargeScreen ? 12 : 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: isLargeScreen ? 24 : 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: isLargeScreen ? 14 : 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: isLargeScreen ? 18 : 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTokenInfoCard(bool isLargeScreen) {
    final remainingDays = AuthApiService.getTokenRemainingDays();
    final isExpiringSoon = remainingDays <= 7;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isLargeScreen ? 20 : 16),
      decoration: BoxDecoration(
        color: isExpiringSoon ? Colors.red[50] : Colors.orange[50],
        borderRadius: BorderRadius.circular(isLargeScreen ? 16 : 12),
        border: Border.all(
          color: isExpiringSoon ? Colors.red[200]! : Colors.orange[200]!,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isLargeScreen ? 12 : 10),
            decoration: BoxDecoration(
              color: isExpiringSoon ? Colors.red[100] : Colors.orange[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isExpiringSoon ? Icons.warning : Icons.access_time,
              color: isExpiringSoon ? Colors.red[700] : Colors.orange[700],
              size: isLargeScreen ? 24 : 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'สถานะการเข้าสู่ระบบ',
                  style: TextStyle(
                    fontSize: isLargeScreen ? 14 : 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  remainingDays > 0
                      ? 'หมดอายุใน $remainingDays วัน'
                      : 'หมดอายุแล้ว',
                  style: TextStyle(
                    fontSize: isLargeScreen ? 18 : 16,
                    fontWeight: FontWeight.w600,
                    color: isExpiringSoon
                        ? Colors.red[700]
                        : Colors.orange[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isLargeScreen) {
    return Column(
      children: [
        // Edit Profile Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _goEdit,
            icon: const Icon(Icons.edit),
            label: Text(
              "แก้ไขโปรไฟล์",
              style: TextStyle(
                fontSize: isLargeScreen ? 18 : 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                vertical: isLargeScreen ? 16 : 14,
                horizontal: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(isLargeScreen ? 16 : 12),
              ),
              elevation: 2,
            ),
          ),
        ),

        SizedBox(height: isLargeScreen ? 16 : 12),

        // Logout Button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: Text(
              "ออกจากระบบ",
              style: TextStyle(
                fontSize: isLargeScreen ? 18 : 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red, width: 2),
              padding: EdgeInsets.symmetric(
                vertical: isLargeScreen ? 16 : 14,
                horizontal: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(isLargeScreen ? 16 : 12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
