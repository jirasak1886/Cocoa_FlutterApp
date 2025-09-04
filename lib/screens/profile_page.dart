import 'package:cocoa_app/auth_api.dart';
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
    await AuthApiService.logout();
    if (mounted) {
      Navigator.pushReplacementNamed(context, "/login"); // กลับไปหน้า Login
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("โปรไฟล์"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadProfile),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : userData == null
          ? const Center(child: Text("ไม่พบข้อมูลผู้ใช้"))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    child: Text(
                      userData?['name']?.substring(0, 1).toUpperCase() ?? "?",
                      style: const TextStyle(fontSize: 30),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    userData?['name'] ?? "ไม่ระบุชื่อ",
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Username: ${userData?['username'] ?? '-'}",
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    "เบอร์โทร: ${userData?['user_tel'] ?? '-'}",
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Token หมดอายุใน: ${AuthApiService.getTokenRemainingDays()} วัน",
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout),
                    label: const Text("ออกจากระบบ"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
