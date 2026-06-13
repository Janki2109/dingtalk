import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/auth_provider.dart';
import '../../chat/screens/chat_list_screen.dart';
import '../../attendance/screens/attendance_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../tasks/screens/tasks_screen.dart';
import '../../meeting/screens/meeting_screen.dart';
import '../../attendance/screens/attendance_screen.dart';
import '../../admin/screens/admin_attendance_screen.dart';
import '../../attendance/screens/attendance_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with TickerProviderStateMixin {
  int _index = 0;
  late AnimationController _navAnim;

  final _screens = [
    const ChatListScreen(),
    const MeetingScreen(),
    const AttendanceScreen(),
    TasksScreen(),
    const ProfileScreen(),
  ];

  final _labels = ['Messages', 'Meetings', 'Attendance', 'Tasks', 'Profile'];
  final _icons = [
    Icons.chat_bubble_outline_rounded,
    Icons.videocam_outlined,
    Icons.access_time_outlined,
    Icons.task_outlined,
    Icons.person_outline_rounded,
  ];
  final _selectedIcons = [
    Icons.chat_bubble_rounded,
    Icons.videocam_rounded,
    Icons.access_time_filled_rounded,
    Icons.task_rounded,
    Icons.person_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _navAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _navAnim.forward();
  }

  @override
  void dispose() {
    _navAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;

    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor == AppColors.bgDark
              ? AppColors.surfaceDark
              : AppColors.surface,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 24,
                offset: const Offset(0, -6)),
          ],
          border:
              Border(top: BorderSide(color: AppColors.border.withOpacity(0.5))),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_screens.length, (i) {
                final selected = _index == i;
                return GestureDetector(
                  onTap: () {
                    setState(() => _index = i);
                    _navAnim.forward(from: 0);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.symmetric(
                        horizontal: selected ? 16 : 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: selected
                          ? LinearGradient(colors: [
                              themeColor.withOpacity(0.15),
                              themeColor.withOpacity(0.08)
                            ])
                          : null,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          selected ? _selectedIcons[i] : _icons[i],
                          key: ValueKey('$i$selected'),
                          color: selected ? themeColor : AppColors.textMuted,
                          size: 22,
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: 6),
                        Text(_labels[i],
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: themeColor)),
                      ],
                    ]),
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
