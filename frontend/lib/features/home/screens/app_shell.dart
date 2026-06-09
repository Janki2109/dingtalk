import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/auth_provider.dart';
import '../../chat/screens/chat_list_screen.dart';
import '../../attendance/screens/attendance_screen.dart';
import '../../tasks/screens/tasks_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../meeting/screens/meeting_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  final _screens = const [
    ChatListScreen(),
    MeetingScreen(),
    AttendanceScreen(),
    TasksScreen(),
    ProfileScreen(),
  ];

  final _labels = ['Messages', 'Meetings', 'Attendance', 'Tasks', 'Profile'];

  final _icons = [
    Icons.chat_bubble_outline_rounded,
    Icons.videocam_outlined,
    Icons.access_time_outlined,
    Icons.task_outlined,
    Icons.person_outline,
  ];

  final _selectedIcons = [
    Icons.chat_bubble_rounded,
    Icons.videocam_rounded,
    Icons.access_time_filled,
    Icons.task_rounded,
    Icons.person_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;

    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_screens.length, (i) {
                final selected = _index == i;
                return GestureDetector(
                  onTap: () => setState(() => _index = i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? themeColor.withOpacity(0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          selected ? _selectedIcons[i] : _icons[i],
                          color: selected ? themeColor : AppColors.textMuted,
                          size: 24,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _labels[i],
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w400,
                            color: selected ? themeColor : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
