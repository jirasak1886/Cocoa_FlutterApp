// lib/screens/auth/forgot_password_screen.dart
import 'dart:async';
import 'package:cocoa_app/api/auth_api.dart';
import 'package:flutter/material.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();

  // step: 0=email, 1=otp, 2=new password
  int _step = 0;

  // controllers
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _loading = false;
  String? _tempToken;

  // email prefill/lock
  bool _emailLocked = false;

  // resend OTP cooldown
  Timer? _resendTimer;
  int _resendSeconds = 0; // 0 = ready

  // show/hide password eyes
  bool _showNewPwd = false;
  bool _showConfirmPwd = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillEmail());
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  // ---------- Helpers ----------
  bool _isOk(Map<String, dynamic> res) =>
      res['success'] == true || res['ok'] == true;

  void _toast(String msg, {Color? color}) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color ?? Colors.black87,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _startResendCooldown([int seconds = 60]) {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_resendSeconds <= 1) {
        t.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _prefillEmail() async {
    try {
      // 1) จาก route arguments
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map &&
          (args['email']?.toString().trim().isNotEmpty ?? false)) {
        final e = args['email'].toString().trim().toLowerCase();
        setState(() {
          _emailCtrl.text = e;
          _emailLocked = true;
        });
        return;
      }

      // 2) จาก checkAuth (ถ้ายังล็อกอินอยู่)
      try {
        final r = await AuthApiService.checkAuth();
        if (r['authenticated'] == true) {
          final u = r['user'] as Map<String, dynamic>?;
          final e = (u?['user_email'] ?? u?['email'] ?? '').toString().trim();
          if (e.isNotEmpty) {
            setState(() {
              _emailCtrl.text = e.toLowerCase();
              _emailLocked = true;
            });
            return;
          }
        }
      } catch (_) {}

      // ถ้าไม่มีค่า อย่าล็อกช่องไว้
      if (_emailCtrl.text.isEmpty) {
        setState(() => _emailLocked = false);
      }
    } catch (_) {}
  }

  // ---------- Actions ----------
  Future<void> _submitStep() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      if (_step == 0) {
        // 1) request OTP
        final res = await AuthApiService.requestPasswordReset(
          email: _emailCtrl.text.trim(),
        );

        if (_isOk(res)) {
          _toast(
            'ถ้าอีเมลนี้มีในระบบ จะได้รับ OTP ภายในไม่กี่นาที',
            color: Colors.green,
          );
          setState(() => _step = 1);
          _startResendCooldown();
        } else {
          _toast(res['message'] ?? 'ขอ OTP ไม่สำเร็จ', color: Colors.red);
        }
      } else if (_step == 1) {
        // 2) verify OTP -> temp token
        final res = await AuthApiService.verifyPasswordReset(
          email: _emailCtrl.text.trim(),
          otp: _otpCtrl.text.trim(),
        );

        final token =
            (res['tempToken'] ?? res['data']?['tempToken']) as String?;
        if (_isOk(res) && (token?.isNotEmpty ?? false)) {
          _tempToken = token;
          _toast('ยืนยันรหัสสำเร็จ', color: Colors.green);
          setState(() => _step = 2);
        } else {
          _toast(
            res['message'] ?? 'OTP ไม่ถูกต้องหรือหมดอายุ',
            color: Colors.red,
          );
        }
      } else {
        // 3) reset new password with temp token
        if ((_tempToken ?? '').isEmpty) {
          _toast('โทเค็นยืนยันหายไป กรุณาขอ OTP ใหม่', color: Colors.red);
          setState(() => _step = 0);
          return;
        }

        final res = await AuthApiService.resetPasswordWithTempToken(
          tempToken: _tempToken!,
          newPassword: _newPassCtrl.text.trim(),
        );

        if (_isOk(res)) {
          _toast(
            'รีเซ็ตรหัสผ่านสำเร็จ! กรุณาเข้าสู่ระบบด้วยรหัสใหม่',
            color: Colors.green,
          );
          // ล้างข้อมูลละเอียดอ่อนก่อนออก
          _otpCtrl.clear();
          _newPassCtrl.clear();
          _confirmPassCtrl.clear();
          _tempToken = null;

          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) Navigator.pop(context); // กลับไปหน้า Login
        } else {
          _toast(
            res['message'] ?? 'รีเซ็ตรหัสผ่านไม่สำเร็จ',
            color: Colors.red,
          );
        }
      }
    } catch (e) {
      _toast('ข้อผิดพลาด: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goBackStep() {
    if (_loading) return;
    if (_step > 0) setState(() => _step--);
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final titles = ['ลืมรหัสผ่าน', 'ยืนยันรหัส (OTP)', 'ตั้งรหัสผ่านใหม่'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_step]),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _buildCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStepHeader(),
                      const SizedBox(height: 16),
                      if (_step == 0) _buildEmailForm(),
                      if (_step == 1) _buildOtpForm(),
                      if (_step == 2) _buildNewPasswordForm(),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          if (_step > 0)
                            OutlinedButton(
                              onPressed: _loading ? null : _goBackStep,
                              child: const Text('ย้อนกลับ'),
                            ),
                          const Spacer(),
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _submitStep,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(_step == 2 ? 'ยืนยัน' : 'ถัดไป'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _loading ? null : () => Navigator.pop(context),
                  child: const Text('กลับไปหน้าเข้าสู่ระบบ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------- Forms --------------------
  Widget _buildEmailForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _input(
          controller: _emailCtrl,
          label: 'อีเมล',
          icon: Icons.email_outlined,
          keyboard: TextInputType.emailAddress,
          validator: (v) {
            final t = (v ?? '').trim();
            if (t.isEmpty) return 'กรุณากรอกอีเมล';
            final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
            if (!emailRegex.hasMatch(t)) return 'อีเมลไม่ถูกต้อง';
            return null;
          },
          readOnly: _emailLocked,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(
              child: Text(
                'เราจะส่งรหัสยืนยัน (OTP) ไปยังอีเมลของคุณ รหัสมีอายุ 10 นาที',
                style: TextStyle(color: Colors.black54),
              ),
            ),
            if (_emailLocked)
              TextButton(
                onPressed: _loading
                    ? null
                    : () => setState(() => _emailLocked = false),
                child: const Text('ใช้เมลอื่น'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildOtpForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _input(
          controller: _otpCtrl,
          label: 'รหัสยืนยัน (OTP)',
          icon: Icons.password,
          keyboard: TextInputType.number,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'กรุณากรอกรหัส OTP';
            if (v.trim().length < 4) return 'OTP สั้นเกินไป';
            return null;
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(
              child: Text(
                'กรุณาตรวจสอบอีเมล (รวมถึงโฟลเดอร์สแปม)',
                style: TextStyle(color: Colors.black54),
              ),
            ),
            TextButton(
              onPressed: (_loading || _resendSeconds > 0)
                  ? null
                  : () async {
                      if (_emailCtrl.text.trim().isEmpty) {
                        _toast('กรุณากรอกอีเมลก่อน', color: Colors.red);
                        return;
                      }
                      setState(() => _loading = true);
                      final res = await AuthApiService.requestPasswordReset(
                        email: _emailCtrl.text.trim(),
                      );
                      if (mounted) setState(() => _loading = false);
                      if (_isOk(res)) {
                        _toast(
                          'ส่ง OTP ใหม่ (ถ้าอีเมลอยู่ในระบบ)',
                          color: Colors.green,
                        );
                        _startResendCooldown();
                      } else {
                        _toast(
                          res['message'] ?? 'ส่ง OTP ใหม่ไม่สำเร็จ',
                          color: Colors.red,
                        );
                      }
                    },
              child: Text(
                _resendSeconds > 0
                    ? 'ส่งรหัสใหม่ ($_resendSeconds)'
                    : 'ส่งรหัสใหม่',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNewPasswordForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _input(
          controller: _newPassCtrl,
          label: 'รหัสผ่านใหม่',
          icon: Icons.lock,
          obscure: !_showNewPwd,
          validator: (v) {
            final t = v ?? '';
            if (t.isEmpty) return 'กรุณากรอกรหัสผ่านใหม่';
            if (t.length < 6) return 'อย่างน้อย 6 ตัวอักษร';
            return null;
          },
          suffix: IconButton(
            icon: Icon(
              _showNewPwd ? Icons.visibility_off : Icons.visibility,
              color: Colors.green,
            ),
            onPressed: _loading
                ? null
                : () => setState(() => _showNewPwd = !_showNewPwd),
            tooltip: _showNewPwd ? 'ซ่อนรหัสผ่าน' : 'แสดงรหัสผ่าน',
          ),
        ),
        const SizedBox(height: 12),
        _input(
          controller: _confirmPassCtrl,
          label: 'ยืนยันรหัสผ่านใหม่',
          icon: Icons.lock_outline,
          obscure: !_showConfirmPwd,
          validator: (v) {
            final t = v ?? '';
            if (t.isEmpty) return 'กรุณายืนยันรหัสผ่าน';
            if (t.length < 6) return 'อย่างน้อย 6 ตัวอักษร';
            if (t != _newPassCtrl.text) return 'รหัสผ่านไม่ตรงกัน';
            return null;
          },
          suffix: IconButton(
            icon: Icon(
              _showConfirmPwd ? Icons.visibility_off : Icons.visibility,
              color: Colors.green,
            ),
            onPressed: _loading
                ? null
                : () => setState(() => _showConfirmPwd = !_showConfirmPwd),
            tooltip: _showConfirmPwd ? 'ซ่อนรหัสผ่าน' : 'แสดงรหัสผ่าน',
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'หลังยืนยัน ระบบจะตั้งรหัสใหม่ให้บัญชีของคุณทันที',
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }

  // -------------------- UI pieces --------------------
  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            spreadRadius: 2,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildStepHeader() {
    final steps = ['อีเมล', 'OTP', 'รหัสใหม่'];
    return Row(
      children: List.generate(steps.length, (i) {
        final active = i <= _step;
        return Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: active ? Colors.green : Colors.grey[300],
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: active ? Colors.white : Colors.black54,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (i < steps.length - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: (i < _step) ? Colors.green : Colors.grey[300],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                steps[i],
                style: TextStyle(
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? Colors.green[700] : Colors.black54,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboard,
    String? Function(String?)? validator,
    bool obscure = false,
    bool readOnly = false,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      validator: validator,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.green),
        suffixIcon: suffix,
        filled: true,
        fillColor: readOnly ? Colors.grey[100] : Colors.grey[50],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.green.shade600, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }
}
