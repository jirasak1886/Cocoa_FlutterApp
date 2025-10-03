// utils/variable.dart

/// ดึง BASE_URL จาก --dart-define ถ้าไม่ระบุจะใช้ 127.0.0.1
const String baseUrl = String.fromEnvironment(
  'BASE_URL',
  defaultValue: 'http://127.0.0.1:5000',
);

/// ชุด URL สำรอง (เรียงตามความน่าจะใช้ในแต่ละแพลตฟอร์ม)
/// - Android emulator ใช้ 10.0.2.2
/// - อุปกรณ์จริงใน LAN ให้ใส่ IP ของเครื่อง server
const List<String> alternativeUrls = <String>[
  'http://127.0.0.1:5000',
  'http://localhost:5000',
  'http://10.0.2.2:5000', // Android emulator
  // 👉 เพิ่ม/แก้เป็น LAN IP ของเครื่องคุณ เช่น:
  // 'http://192.168.1.50:5000',
  // หรือ domain จริงในโปรดักชัน:
  // 'https://api.your-domain.com',
];
