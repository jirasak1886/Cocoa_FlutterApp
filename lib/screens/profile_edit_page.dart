import 'dart:async';
import 'package:cocoa_app/api/auth_api.dart';
import 'package:flutter/material.dart';

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _pwdFormKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _telCtrl;
  late TextEditingController _usernameCtrl;

  final _curPwdCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();

  bool _saving = false;
  bool _changingPwd = false;
  bool _showCur = false, _showNew = false, _showConfirm = false;

  Map<String, dynamic>? _initialUser;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _telCtrl = TextEditingController();
    _usernameCtrl = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialUser == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _initialUser = args;
        _nameCtrl.text = args['name']?.toString() ?? '';
        _telCtrl.text = args['user_tel']?.toString() ?? '';
        _usernameCtrl.text = args['username']?.toString() ?? '';
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _telCtrl.dispose();
    _usernameCtrl.dispose();
    _curPwdCtrl.dispose();
    _newPwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    // validate ส่วนข้อมูลโปรไฟล์
    if (!_formKey.currentState!.validate()) return;

    // ถ้าจะเปลี่ยนรหัส ให้ validate ฟอร์มรหัสผ่านด้วย
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
      // 1) Update โปรไฟล์ (ชื่อ/เบอร์/username)
      final upd = await AuthApiService.updateProfile(
        name: _nameCtrl.text.trim(),
        userTel: _telCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
      );

      if (upd['success'] != true) {
        _showSnack(upd['message'] ?? 'อัปเดตโปรไฟล์ไม่สำเร็จ', isError: true);
        setState(() => _saving = false);
        return;
      }

      // 2) ถ้า user เลือกเปลี่ยนรหัส ให้ยิงอีกคำสั่ง
      if (_changingPwd) {
        final ch = await AuthApiService.changePassword(
          currentPassword: _curPwdCtrl.text.trim(),
          newPassword: _newPwdCtrl.text.trim(),
        );

        if (ch['success'] != true) {
          _showSnack(
            ch['message'] ??
                'เปลี่ยนรหัสผ่านไม่สำเร็จ (ตรวจสอบรหัสเดิมว่าถูกต้อง)',
            isError: true,
          );
          setState(() => _saving = false);
          return;
        }
      }

      _showSnack('บันทึกข้อมูลสำเร็จ');
      if (mounted)
        Navigator.pop(context, true); // ส่งสถานะสำเร็จกลับไปหน้า Profile
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = _initialUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('แก้ไขโปรไฟล์'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: u == null
          ? const Center(child: Text('ไม่พบข้อมูลผู้ใช้'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // ข้อมูลทั่วไป
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'ชื่อ-นามสกุล',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'กรุณากรอกชื่อ'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _telCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'เบอร์โทร',
                            prefixIcon: Icon(Icons.phone_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'กรุณากรอกเบอร์โทร'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _usernameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.alternate_email),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'กรุณากรอก Username'
                              : null,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // เปลี่ยนรหัสผ่าน (ตัวเลือก)
                  SwitchListTile.adaptive(
                    value: _changingPwd,
                    onChanged: (v) => setState(() => _changingPwd = v),
                    title: const Text('ต้องการเปลี่ยนรหัสผ่าน'),
                    subtitle: const Text('ต้องใส่รหัสเดิมให้ถูกต้องก่อน'),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: !_changingPwd
                        ? const SizedBox.shrink()
                        : Form(
                            key: _pwdFormKey,
                            child: Column(
                              children: [
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _curPwdCtrl,
                                  obscureText: !_showCur,
                                  decoration: InputDecoration(
                                    labelText: 'รหัสผ่านเดิม',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _showCur
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                      ),
                                      onPressed: () =>
                                          setState(() => _showCur = !_showCur),
                                    ),
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? 'กรุณากรอกรหัสผ่านเดิม'
                                      : null,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _newPwdCtrl,
                                  obscureText: !_showNew,
                                  decoration: InputDecoration(
                                    labelText: 'รหัสผ่านใหม่ (อย่างน้อย 6 ตัว)',
                                    prefixIcon: const Icon(
                                      Icons.password_outlined,
                                    ),
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _showNew
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                      ),
                                      onPressed: () =>
                                          setState(() => _showNew = !_showNew),
                                    ),
                                  ),
                                  validator: (v) {
                                    final t = v?.trim() ?? '';
                                    if (t.isEmpty)
                                      return 'กรุณากรอกรหัสผ่านใหม่';
                                    if (t.length < 6) {
                                      return 'รหัสผ่านใหม่ต้องยาวอย่างน้อย 6 ตัวอักษร';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _confirmPwdCtrl,
                                  obscureText: !_showConfirm,
                                  decoration: InputDecoration(
                                    labelText: 'ยืนยันรหัสผ่านใหม่',
                                    prefixIcon: const Icon(
                                      Icons.check_circle_outline,
                                    ),
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _showConfirm
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                      ),
                                      onPressed: () => setState(
                                        () => _showConfirm = !_showConfirm,
                                      ),
                                    ),
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? 'กรุณายืนยันรหัสผ่านใหม่'
                                      : null,
                                ),
                              ],
                            ),
                          ),
                  ),

                  const SizedBox(height: 24),

                  // ปุ่มบันทึก
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'กำลังบันทึก...' : 'บันทึก'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
