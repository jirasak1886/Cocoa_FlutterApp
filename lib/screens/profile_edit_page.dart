import 'dart:async';
import 'package:cocoa_app/api/auth_api.dart';
import 'package:flutter/material.dart';

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _pwdFormKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _telCtrl;
  late TextEditingController _usernameCtrl;
  late TextEditingController _emailCtrl;

  final _curPwdCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();

  bool _saving = false;
  bool _changingPwd = false;
  bool _showCur = false, _showNew = false, _showConfirm = false;

  bool _isLoading = true; // ✅ โหลด/ตรวจสิทธิ์
  String _errorMessage = '';
  Map<String, dynamic>? _initialUser;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _telCtrl = TextEditingController();
    _usernameCtrl = TextEditingController();
    _emailCtrl = TextEditingController();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // ✅ ตรวจสิทธิ์ + โหลดข้อมูลหลังเฟรมแรก กัน race
    WidgetsBinding.instance.addPostFrameCallback((_) => _guardAndLoad());
  }

  Future<void> _guardAndLoad() async {
    try {
      // 1) รับ args ถ้ามี
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _initialUser = args;
      }

      // 2) checkAuth รอบแรก
      var r = await AuthApiService.checkAuth();
      var authed = r['authenticated'] == true;

      if (!authed) {
        // กัน race: รอสั้นๆ แล้วลองใหม่
        await Future.delayed(const Duration(milliseconds: 200));
        r = await AuthApiService.checkAuth();
        authed = r['authenticated'] == true;
      }

      if (!mounted) return;
      if (!authed) {
        setState(() {
          _isLoading = false;
          _errorMessage = r['message'] ?? 'ไม่มีสิทธิ์เข้าถึง';
        });
        // นำทางกลับ login
        Navigator.of(
          context,
        ).pushReplacementNamed('/login', arguments: {'reason': 'auth_failed'});
        return;
      }

      // 3) ถ้าไม่มี args ให้ใช้ user จาก checkAuth
      _initialUser ??= r['user'] as Map<String, dynamic>?;

      // 4) preload ฟิลด์จาก _initialUser
      _applyUserToFields(_initialUser);

      setState(() {
        _isLoading = false;
      });
      _animationController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'เกิดข้อผิดพลาดในการตรวจสอบสิทธิ์';
      });
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  void _applyUserToFields(Map<String, dynamic>? u) {
    if (u == null) return;
    _nameCtrl.text = (u['name'] ?? '').toString();
    _telCtrl.text = (u['user_tel'] ?? u['tel'] ?? '').toString();
    _usernameCtrl.text = (u['username'] ?? '').toString();
    _emailCtrl.text = (u['user_email'] ?? u['email'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _telCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _curPwdCtrl.dispose();
    _newPwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // ฟังก์ชันตรวจสอบขนาดหน้าจอ
  bool _isLargeScreen(BuildContext context) =>
      MediaQuery.of(context).size.width >= 768;

  Future<void> _save() async {
    if (_saving) return;

    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    if (_changingPwd) {
      if (!_pwdFormKey.currentState!.validate()) return;
      if (_newPwdCtrl.text.trim() != _confirmPwdCtrl.text.trim()) {
        _showSnack('รหัสผ่านใหม่และยืนยันไม่ตรงกัน', isError: true);
        return;
      }
      if (_newPwdCtrl.text.trim() == _curPwdCtrl.text.trim()) {
        _showSnack('รหัสผ่านใหม่ต้องไม่เหมือนรหัสผ่านเดิม', isError: true);
        return;
      }
    }

    setState(() => _saving = true);

    try {
      // ✅ เช็คสิทธิ์อีกรอบแบบเบาๆ (กัน token หลุดกลางจังหวะ)
      final auth = await AuthApiService.checkAuth();
      if (auth['authenticated'] != true) {
        _showSnack('หมดสิทธิ์การใช้งาน กรุณาเข้าสู่ระบบใหม่', isError: true);
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }

      // 1) Update โปรไฟล์
      final upd = await AuthApiService.updateProfile(
        name: _nameCtrl.text.trim(),
        userTel: _telCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        userEmail: _emailCtrl.text.trim().toLowerCase(),
      );

      if (upd['success'] != true) {
        final msg =
            (upd['message'] ?? 'อัปเดตโปรไฟล์ไม่สำเร็จ') +
            (upd['error'] != null ? ' (${upd['error']})' : '');
        _showSnack(msg, isError: true);
        setState(() => _saving = false);
        return;
      }

      // 2) เปลี่ยนรหัสผ่าน (ถ้าผู้ใช้เลือก)
      if (_changingPwd) {
        final ch = await AuthApiService.changePassword(
          currentPassword: _curPwdCtrl.text.trim(),
          newPassword: _newPwdCtrl.text.trim(),
        );

        if (ch['success'] != true) {
          final msg =
              (ch['message'] ??
                  'เปลี่ยนรหัสผ่านไม่สำเร็จ (ตรวจสอบรหัสเดิมว่าถูกต้อง)') +
              (ch['error'] != null ? ' (${ch['error']})' : '');
          _showSnack(msg, isError: true);
          setState(() => _saving = false);
          return;
        }

        _showSnack('เปลี่ยนรหัสผ่านสำเร็จ กำลังออกจากระบบ...');
        await AuthApiService.logout();
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
        return;
      }

      _showSnack('บันทึกข้อมูลสำเร็จ');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showSnack('เกิดข้อผิดพลาด: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = _isLargeScreen(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: _buildAppBar(isLargeScreen),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.green),
              const SizedBox(height: 16),
              Text(
                'กำลังเตรียมข้อมูล...',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    if (_initialUser == null) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: _buildAppBar(isLargeScreen),
        body: _buildErrorScreen(
          isLargeScreen,
          message: _errorMessage.isEmpty ? 'ไม่พบข้อมูลผู้ใช้' : _errorMessage,
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(isLargeScreen),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: _buildEditForm(context, _initialUser!, isLargeScreen),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isLargeScreen) {
    return AppBar(
      title: Text(
        'แก้ไขโปรไฟล์',
        style: TextStyle(
          fontSize: isLargeScreen ? 20 : 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: Colors.green,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: !isLargeScreen,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: () => Navigator.of(context).maybePop(),
        tooltip: 'ย้อนกลับ',
      ),
    );
  }

  Widget _buildErrorScreen(bool isLargeScreen, {required String message}) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: isLargeScreen ? 80 : 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: TextStyle(
                fontSize: isLargeScreen ? 20 : 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'กรุณาลองใหม่อีกครั้ง',
              style: TextStyle(
                fontSize: isLargeScreen ? 16 : 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditForm(
    BuildContext context,
    Map<String, dynamic> u,
    bool isLargeScreen,
  ) {
    return Center(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: isLargeScreen ? 700 : double.infinity,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isLargeScreen ? 32 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderCard(u, isLargeScreen),
              SizedBox(height: isLargeScreen ? 32 : 24),
              _buildProfileInfoCard(isLargeScreen),
              SizedBox(height: isLargeScreen ? 24 : 20),
              _buildPasswordChangeCard(isLargeScreen),
              SizedBox(height: isLargeScreen ? 40 : 32),
              _buildSaveButton(isLargeScreen),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(Map<String, dynamic> u, bool isLargeScreen) {
    final userName = u['name'] ?? u['username'] ?? 'ผู้ใช้';
    final firstChar = userName.toString().trim().isNotEmpty
        ? userName.toString().trim().substring(0, 1).toUpperCase()
        : '?';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isLargeScreen ? 28 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isLargeScreen ? 20 : 16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: isLargeScreen ? 35 : 30,
            backgroundColor: Colors.green,
            child: Text(
              firstChar,
              style: TextStyle(
                fontSize: isLargeScreen ? 28 : 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'แก้ไขข้อมูลส่วนตัว',
                  style: TextStyle(
                    fontSize: isLargeScreen ? 20 : 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'กรอกข้อมูลที่ต้องการเปลี่ยนแปลง',
                  style: TextStyle(
                    fontSize: isLargeScreen ? 16 : 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileInfoCard(bool isLargeScreen) {
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
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.person, color: Colors.green[700], size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'ข้อมูลส่วนตัว',
                  style: TextStyle(
                    fontSize: isLargeScreen ? 18 : 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: isLargeScreen ? 24 : 20),

            _buildTextField(
              controller: _nameCtrl,
              label: 'ชื่อ-นามสกุล',
              icon: Icons.person_outline,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'กรุณากรอกชื่อ' : null,
              isLargeScreen: isLargeScreen,
            ),
            SizedBox(height: isLargeScreen ? 20 : 16),

            _buildTextField(
              controller: _telCtrl,
              label: 'เบอร์โทรศัพท์',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'กรุณากรอกเบอร์โทร';
                final digits = t.replaceAll(RegExp(r'\D'), '');
                if (digits.length < 10) return 'เบอร์โทรไม่ถูกต้อง';
                return null;
              },
              isLargeScreen: isLargeScreen,
            ),
            SizedBox(height: isLargeScreen ? 20 : 16),

            _buildTextField(
              controller: _usernameCtrl,
              label: 'Username',
              icon: Icons.alternate_email,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'กรุณากรอก Username' : null,
              isLargeScreen: isLargeScreen,
            ),
            SizedBox(height: isLargeScreen ? 20 : 16),

            _buildTextField(
              controller: _emailCtrl,
              label: 'อีเมล',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'กรุณากรอกอีเมล';
                final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                if (!emailRegex.hasMatch(t)) return 'อีเมลไม่ถูกต้อง';
                return null;
              },
              isLargeScreen: isLargeScreen,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordChangeCard(bool isLargeScreen) {
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.security,
                  color: Colors.orange[700],
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'เปลี่ยนรหัสผ่าน',
                style: TextStyle(
                  fontSize: isLargeScreen ? 18 : 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          SizedBox(height: isLargeScreen ? 20 : 16),

          // Toggle
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _changingPwd ? Colors.orange[50] : Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _changingPwd ? Colors.orange[200]! : Colors.grey[200]!,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _changingPwd ? Icons.lock_reset : Icons.lock_outline,
                  color: _changingPwd ? Colors.orange[700] : Colors.grey[600],
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ต้องการเปลี่ยนรหัสผ่าน',
                        style: TextStyle(
                          fontSize: isLargeScreen ? 16 : 14,
                          fontWeight: FontWeight.w600,
                          color: _changingPwd
                              ? Colors.orange[700]
                              : Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ต้องใส่รหัสเดิมให้ถูกต้องก่อน',
                        style: TextStyle(
                          fontSize: isLargeScreen ? 14 : 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _changingPwd,
                  onChanged: (v) => setState(() => _changingPwd = v),
                  activeColor: Colors.orange,
                ),
              ],
            ),
          ),

          // Password Fields
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: _changingPwd ? null : 0,
            child: _changingPwd
                ? Form(
                    key: _pwdFormKey,
                    child: Column(
                      children: [
                        SizedBox(height: isLargeScreen ? 20 : 16),
                        _buildPasswordField(
                          controller: _curPwdCtrl,
                          label: 'รหัสผ่านเดิม',
                          icon: Icons.lock_outline,
                          obscureText: !_showCur,
                          onToggleVisibility: () =>
                              setState(() => _showCur = !_showCur),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'กรุณากรอกรหัสผ่านเดิม'
                              : null,
                          isLargeScreen: isLargeScreen,
                        ),
                        SizedBox(height: isLargeScreen ? 16 : 12),
                        _buildPasswordField(
                          controller: _newPwdCtrl,
                          label: 'รหัสผ่านใหม่ (อย่างน้อย 6 ตัว)',
                          icon: Icons.password_outlined,
                          obscureText: !_showNew,
                          onToggleVisibility: () =>
                              setState(() => _showNew = !_showNew),
                          validator: (v) {
                            final t = v?.trim() ?? '';
                            if (t.isEmpty) return 'กรุณากรอกรหัสผ่านใหม่';
                            if (t.length < 6) {
                              return 'รหัสผ่านใหม่ต้องยาวอย่างน้อย 6 ตัวอักษร';
                            }
                            return null;
                          },
                          isLargeScreen: isLargeScreen,
                        ),
                        SizedBox(height: isLargeScreen ? 16 : 12),
                        _buildPasswordField(
                          controller: _confirmPwdCtrl,
                          label: 'ยืนยันรหัสผ่านใหม่',
                          icon: Icons.check_circle_outline,
                          obscureText: !_showConfirm,
                          onToggleVisibility: () =>
                              setState(() => _showConfirm = !_showConfirm),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'กรุณายืนยันรหัสผ่านใหม่'
                              : null,
                          isLargeScreen: isLargeScreen,
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    required bool isLargeScreen,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(fontSize: isLargeScreen ? 16 : 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: isLargeScreen ? 16 : 14),
        prefixIcon: Icon(icon, size: isLargeScreen ? 24 : 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.green, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: EdgeInsets.symmetric(
          horizontal: isLargeScreen ? 16 : 12,
          vertical: isLargeScreen ? 16 : 12,
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool obscureText,
    required VoidCallback onToggleVisibility,
    String? Function(String?)? validator,
    required bool isLargeScreen,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      style: TextStyle(fontSize: isLargeScreen ? 16 : 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: isLargeScreen ? 16 : 14),
        prefixIcon: Icon(icon, size: isLargeScreen ? 24 : 20),
        suffixIcon: IconButton(
          icon: Icon(
            obscureText ? Icons.visibility : Icons.visibility_off,
            size: isLargeScreen ? 24 : 20,
          ),
          onPressed: onToggleVisibility,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.orange, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: EdgeInsets.symmetric(
          horizontal: isLargeScreen ? 16 : 12,
          vertical: isLargeScreen ? 16 : 12,
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildSaveButton(bool isLargeScreen) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? SizedBox(
                width: isLargeScreen ? 20 : 18,
                height: isLargeScreen ? 20 : 18,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Icon(Icons.save_outlined, size: isLargeScreen ? 24 : 20),
        label: Text(
          _saving ? 'กำลังบันทึก...' : 'บันทึกข้อมูล',
          style: TextStyle(
            fontSize: isLargeScreen ? 18 : 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(
            vertical: isLargeScreen ? 18 : 16,
            horizontal: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isLargeScreen ? 16 : 12),
          ),
          elevation: 2,
        ),
      ),
    );
  }
}
