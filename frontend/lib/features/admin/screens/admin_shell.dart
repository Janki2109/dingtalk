import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/services/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import 'admin_dashboard_screen.dart';
import 'admin_tasks_screen.dart';
import 'admin_attendance_screen.dart';
import 'admin_meetings_screen.dart';
import 'admin_profile_screen.dart';
import '../../chat/screens/chat_list_screen.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  final _screens = const [
    AdminDashboardScreen(),
    AdminTasksScreen(),
    ChatListScreen(),
    AdminAttendanceScreen(),
    AdminMeetingsScreen(),
    AdminProfileScreen(),
  ];

  final _labels = [
    'Dashboard',
    'Tasks',
    'Messages',
    'Attendance',
    'Meetings',
    'Profile'
  ];

  final _icons = [
    Icons.dashboard_outlined,
    Icons.task_outlined,
    Icons.chat_bubble_outline_rounded,
    Icons.people_outline,
    Icons.videocam_outlined,
    Icons.person_outline,
  ];

  final _selectedIcons = [
    Icons.dashboard_rounded,
    Icons.task_rounded,
    Icons.chat_bubble_rounded,
    Icons.people_rounded,
    Icons.videocam_rounded,
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
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(_screens.length, (i) {
                final selected = _index == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _index = i),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? themeColor.withOpacity(0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            selected ? _selectedIcons[i] : _icons[i],
                            color: selected ? themeColor : AppColors.textMuted,
                            size: 22,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _labels[i],
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w400,
                              color:
                                  selected ? themeColor : AppColors.textMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
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
