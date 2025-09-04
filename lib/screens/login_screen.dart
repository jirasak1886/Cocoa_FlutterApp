import 'package:cocoa_app/auth_api.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isRegisterMode = false;

  // Controllers for registration
  final _nameController = TextEditingController();
  final _telController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _telController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      print('🔍 Attempting login with username: ${_usernameController.text}');

      final result = await AuthApiService.login(
        _usernameController.text,
        _passwordController.text,
      );

      print('🔍 Login result: $result');

      setState(() {
        _isLoading = false;
      });

      if (result['success'] == true) {
        print('✅ Login successful, navigating to dashboard...');

        // แสดงข้อความสำเร็จ
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เข้าสู่ระบบสำเร็จ'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );

        // รอให้ snackbar แสดงเสร็จ แล้ว navigate
        await Future.delayed(Duration(milliseconds: 800));

        // ตรวจสอบว่า widget ยังมี context หรือไม่
        if (mounted) {
          print('🔍 Navigating to dashboard...');

          // ใช้ pushReplacementNamed แทน เพื่อความเรียบง่าย
          Navigator.of(context).pushReplacementNamed('/dashboard');

          print('✅ Navigation completed successfully');
        }
      } else {
        print('❌ Login failed: ${result['message']}');
        _showErrorMessage(result['message'] ?? 'เข้าสู่ระบบไม่สำเร็จ');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('❌ Login error: $e');
      _showErrorMessage('เกิดข้อผิดพลาดในการเชื่อมต่อ: $e');
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      print('Attempting registration...');

      final result = await AuthApiService.register(
        _usernameController.text,
        _telController.text,
        _passwordController.text,
        _confirmPasswordController.text,
        _nameController.text,
      );

      print('Register result: $result');

      setState(() {
        _isLoading = false;
      });

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ลงทะเบียนสำเร็จ กรุณาเข้าสู่ระบบ'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        setState(() {
          _isRegisterMode = false;
        });
        _clearForm();
      } else {
        _showErrorMessage(result['message'] ?? 'ลงทะเบียนไม่สำเร็จ');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Register error: $e');
      _showErrorMessage('เกิดข้อผิดพลาดในการลงทะเบียน: $e');
    }
  }

  void _showErrorMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _clearForm() {
    _usernameController.clear();
    _passwordController.clear();
    _nameController.clear();
    _telController.clear();
    _confirmPasswordController.clear();
  }

  void _toggleMode() {
    setState(() {
      _isRegisterMode = !_isRegisterMode;
    });
    _clearForm();
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
          padding: EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo และ Title
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 5,
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.agriculture,
                        size: 60,
                        color: Colors.green[600],
                      ),
                      SizedBox(height: 16),
                      Text(
                        'ระบบจัดการสวนโกโก้',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[800],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        _isRegisterMode
                            ? 'สร้างบัญชีใหม่'
                            : 'เข้าสู่ระบบของคุณ',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 32),

                // Form Container
                Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 5,
                        blurRadius: 10,
                        offset: Offset(0, 3),
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
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'กรุณากรอกชื่อ-นามสกุล';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 16),

                        _buildTextField(
                          controller: _telController,
                          label: 'เบอร์โทรศัพท์',
                          icon: Icons.phone,
                          keyboardType: TextInputType.phone,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'กรุณากรอกเบอร์โทรศัพท์';
                            }
                            if (value.length < 10) {
                              return 'เบอร์โทรศัพท์ไม่ถูกต้อง';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 16),
                      ],

                      _buildTextField(
                        controller: _usernameController,
                        label: 'ชื่อผู้ใช้',
                        icon: Icons.account_circle,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'กรุณากรอกชื่อผู้ใช้';
                          }
                          if (value.length < 3) {
                            return 'ชื่อผู้ใช้ต้องมีอย่างน้อย 3 ตัวอักษร';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),

                      _buildTextField(
                        controller: _passwordController,
                        label: 'รหัสผ่าน',
                        icon: Icons.lock,
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'กรุณากรอกรหัสผ่าน';
                          }
                          if (_isRegisterMode && value.length < 6) {
                            return 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16),

                      if (_isRegisterMode) ...[
                        _buildTextField(
                          controller: _confirmPasswordController,
                          label: 'ยืนยันรหัสผ่าน',
                          icon: Icons.lock_outline,
                          obscureText: true,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'กรุณายืนยันรหัสผ่าน';
                            }
                            if (value != _passwordController.text) {
                              return 'รหัสผ่านไม่ตรงกัน';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 24),
                      ] else ...[
                        SizedBox(height: 8),
                      ],

                      // Submit Button
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
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: _isLoading
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text('กำลังดำเนินการ...'),
                                  ],
                                )
                              : Text(
                                  _isRegisterMode ? 'ลงทะเบียน' : 'เข้าสู่ระบบ',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 24),

                // Toggle Mode Button
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: TextButton(
                    onPressed: _isLoading ? null : _toggleMode,
                    child: Text(
                      _isRegisterMode
                          ? 'มีบัญชีแล้ว? เข้าสู่ระบบ'
                          : 'ยังไม่มีบัญชี? ลงทะเบียน',
                      style: TextStyle(
                        color: Colors.green[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    bool obscureText = false,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.green[600]),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.green[500]!, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
    );
  }
}
