import 'package:flutter/material.dart';

enum AppTab { home, fields, profile, history, detect }

extension on AppTab {
  String get label => switch (this) {
    AppTab.home => 'หน้าหลัก',
    AppTab.fields => 'จัดการพื้นที่',
    AppTab.profile => 'โปรไฟล์',
    AppTab.history => 'ประวัติ',
    AppTab.detect => 'การตรวจจับ',
  };

  IconData get icon => switch (this) {
    AppTab.home => Icons.home_outlined,
    AppTab.fields => Icons.terrain_outlined,
    AppTab.profile => Icons.account_circle_outlined,
    AppTab.history => Icons.history,
    AppTab.detect => Icons.radar,
  };
}

class CocoaNavBar extends StatelessWidget {
  const CocoaNavBar({
    super.key,
    required this.currentIndex,
    required this.onChanged,
  });

  final int currentIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tabs = AppTab.values;
    final useM3 = Theme.of(context).useMaterial3;

    if (useM3) {
      return NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onChanged,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final t in tabs)
            NavigationDestination(icon: Icon(t.icon), label: t.label),
        ],
      );
    }

    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onChanged,
      type: BottomNavigationBarType.fixed,
      items: [
        for (final t in tabs)
          BottomNavigationBarItem(icon: Icon(t.icon), label: t.label),
      ],
    );
  }
}
