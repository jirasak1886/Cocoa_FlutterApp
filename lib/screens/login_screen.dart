import 'package:cocoa_app/api/auth_api.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  // Register controllers
  final _nameController = TextEditingController();
  final _telController = TextEditingController();
  final _emailController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _isRegisterMode = false;
  bool _obscurePwd = true;
  bool _obscurePwdConfirm = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _telController.dispose();
    _emailController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus(); // ปิดคีย์บอร์ด

    try {
      final username = _usernameController.text.trim();
      final password = _passwordController.text;

      final result = await AuthApiService.login(username, password);

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (result['success'] == true) {
        // แจ้งเตือนสั้นๆ
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('เข้าสู่ระบบสำเร็จ'),
            backgroundColor: Colors.green,
            duration: Duration(milliseconds: 900),
          ),
        );
        // กัน race: รอสั้นๆ ให้ ApiServer+Prefs ตั้งค่าเสร็จ (AuthApiService ก็หน่วงไว้แล้ว)
        await Future.delayed(const Duration(milliseconds: 150));
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/dashboard');
      } else {
        _showErrorMessage(result['message'] ?? 'เข้าสู่ระบบไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showErrorMessage('เกิดข้อผิดพลาด: $e');
    }
  }

  Future<void> _handleRegister() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus();

    try {
      final result = await AuthApiService.register(
        _usernameController.text.trim(),
        _telController.text.trim(),
        _emailController.text.trim().toLowerCase(),
        _passwordController.text,
        _confirmPasswordController.text,
        _nameController.text.trim(),
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ลงทะเบียนสำเร็จ กรุณาเข้าสู่ระบบ'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        setState(() => _isRegisterMode = false);
        _clearForm(keepLoginFields: true);
      } else {
        _showErrorMessage(result['message'] ?? 'ลงทะเบียนไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showErrorMessage('เกิดข้อผิดพลาด: $e');
    }
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _clearForm({bool keepLoginFields = false}) {
    if (!keepLoginFields) {
      _usernameController.clear();
      _passwordController.clear();
    }
    _nameController.clear();
    _telController.clear();
    _emailController.clear();
    _confirmPasswordController.clear();
  }

  void _toggleMode() {
    if (_isLoading) return;
    setState(() => _isRegisterMode = !_isRegisterMode);
    _clearForm(keepLoginFields: !_isRegisterMode); // เคลียร์ช่องของโหมดก่อนหน้า
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(_isRegisterMode ? 'ลงทะเบียน' : 'เข้าสู่ระบบ'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 5,
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      if (_isRegisterMode) ...[
                        _buildTextField(
                          controller: _nameController,
                          label: 'ชื่อ-นามสกุล',
                          icon: Icons.person,
                          textInputAction: TextInputAction.next,
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'กรุณากรอกชื่อ'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _telController,
                          label: 'เบอร์โทรศัพท์',
                          icon: Icons.phone,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.isEmpty) return 'กรุณากรอกเบอร์โทรศัพท์';
                            if (t.length < 10) return 'เบอร์ไม่ถูกต้อง';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _emailController,
                          label: 'อีเมล',
                          icon: Icons.email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.isEmpty) return 'กรุณากรอกอีเมล';
                            if (!t.contains('@')) return 'อีเมลไม่ถูกต้อง';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      _buildTextField(
                        controller: _usernameController,
                        label: 'ชื่อผู้ใช้',
                        icon: Icons.account_circle,
                        textInputAction: TextInputAction.next,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'กรุณากรอกชื่อผู้ใช้'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _passwordController,
                        label: 'รหัสผ่าน',
                        icon: Icons.lock,
                        obscureText: _obscurePwd,
                        textInputAction: _isRegisterMode
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onFieldSubmitted: _isRegisterMode
                            ? null
                            : (_) => _handleLogin(),
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePwd
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: Colors.green[600],
                          ),
                          onPressed: _isLoading
                              ? null
                              : () =>
                                    setState(() => _obscurePwd = !_obscurePwd),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty)
                            return 'กรุณากรอกรหัสผ่าน';
                          if (_isRegisterMode && v.length < 6)
                            return 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),
                      if (_isRegisterMode)
                        _buildTextField(
                          controller: _confirmPasswordController,
                          label: 'ยืนยันรหัสผ่าน',
                          icon: Icons.lock_outline,
                          obscureText: _obscurePwdConfirm,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _handleRegister(),
                          suffix: IconButton(
                            icon: Icon(
                              _obscurePwdConfirm
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: Colors.green[600],
                            ),
                            onPressed: _isLoading
                                ? null
                                : () => setState(
                                    () => _obscurePwdConfirm =
                                        !_obscurePwdConfirm,
                                  ),
                          ),
                          validator: (v) {
                            final t = v ?? '';
                            if (t.isEmpty) return 'กรุณายืนยันรหัสผ่าน';
                            if (t.length < 6)
                              return 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';
                            if (t != _passwordController.text)
                              return 'รหัสผ่านไม่ตรงกัน';
                            return null;
                          },
                        ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isLoading
                              ? null
                              : (_isRegisterMode
                                    ? _handleRegister
                                    : _handleLogin),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isRegisterMode ? 'ลงทะเบียน' : 'เข้าสู่ระบบ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      if (!_isRegisterMode) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _isLoading
                              ? null
                              : () => Navigator.pushNamed(
                                  context,
                                  '/forgot-password',
                                ),
                          child: const Text(
                            "ลืมรหัสผ่าน?",
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: _toggleMode,
                  child: Text(
                    _isRegisterMode
                        ? 'มีบัญชีแล้ว? เข้าสู่ระบบ'
                        : 'ยังไม่มีบัญชี? ลงทะเบียน',
                    style: TextStyle(color: Colors.green[700]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const Icon(Icons.agriculture, size: 60, color: Colors.green),
        const SizedBox(height: 16),
        Text(
          'ระบบจัดการสวนโกโก้',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.green[800],
          ),
        ),
        Text(
          _isRegisterMode ? 'สร้างบัญชีใหม่' : 'เข้าสู่ระบบของคุณ',
          style: TextStyle(color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    bool obscureText = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.green[600]),
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      enabled: !_isLoading,
    );
  }
}
