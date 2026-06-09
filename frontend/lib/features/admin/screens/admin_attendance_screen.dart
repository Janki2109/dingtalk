import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';
import '../../../shared/widgets/app_widgets.dart';

// Shared storage for todo submissions (in production save to DB)
class TodoStore {
  static final List<Map<String, dynamic>> submissions = [];
}

class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});
  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<UserModel> _employees = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
    // Auto-refresh every 10 seconds
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 10));
      if (!mounted) return false;
      await _load();
      return mounted;
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final users = await ApiService.getUsers();
      if (mounted)
        setState(() {
          _employees = users.where((u) => !u.isAdmin).toList();
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _viewTodo(Map<String, dynamic> s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                UserAvatar(name: s['employee'], size: 48),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(s['employee'],
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700)),
                      Text('${s['date']} · Out: ${s['checkOut']}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textMuted)),
                    ])),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: AppColors.online.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20)),
                  child: const Text('Submitted ✅',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.online,
                          fontWeight: FontWeight.w700)),
                ),
              ])),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                const Text('Daily Work Report',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('${(s['tasks'] as List).length} tasks',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700)),
                ),
              ])),
          const SizedBox(height: 12),
          Expanded(
              child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: (s['tasks'] as List).length,
            itemBuilder: (ctx, i) {
              final task = s['tasks'][i] as String;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: AppColors.surfaceVar,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border)),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.online.withOpacity(0.15)),
                          child: const Icon(Icons.check,
                              color: AppColors.online, size: 14)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(task,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500))),
                    ]),
              );
            },
          )),
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, MediaQuery.of(context).padding.bottom + 16),
            child: Row(children: [
              Expanded(
                  child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              )),
              const SizedBox(width: 12),
              Expanded(
                  child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() => s['acknowledged'] = true);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('✅ Work report acknowledged!'),
                    backgroundColor: AppColors.online,
                    behavior: SnackBarBehavior.floating,
                  ));
                },
                icon: const Icon(Icons.thumb_up_outlined, size: 16),
                label: const Text('Acknowledge'),
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.online),
              )),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;
    final now = DateTime.now();
    final present = _employees.where((e) => e.status == 'online').length;
    final absent = _employees.length - present;
    final todos = TodoStore.submissions;
    final newTodos = todos.where((t) => t['acknowledged'] != true).length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Attendance',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          Text('${now.day}/${now.month}/${now.year} — Live Status',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: themeColor,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: themeColor,
          tabs: [
            const Tab(text: 'Attendance'),
            Tab(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('To-Do Lists'),
              if (newTodos > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppColors.busy,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('$newTodos',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ])),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tab, children: [
              // ── Attendance Tab ─────────────────────────────────────────
              Column(children: [
                // Summary card
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [themeColor, themeColor.withOpacity(0.7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                            color: themeColor.withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 6))
                      ]),
                  child: Row(children: [
                    Expanded(
                        child: _Sum(
                            'Total', '${_employees.length}', Colors.white)),
                    Container(
                        width: 1,
                        height: 50,
                        color: Colors.white.withOpacity(0.3)),
                    Expanded(child: _Sum('Present', '$present', Colors.white)),
                    Container(
                        width: 1,
                        height: 50,
                        color: Colors.white.withOpacity(0.3)),
                    Expanded(child: _Sum('Absent', '$absent', Colors.white)),
                  ]),
                ),

                // Present label
                if (present > 0)
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(children: [
                        Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.online)),
                        const SizedBox(width: 8),
                        Text('Present ($present)',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.online)),
                        const SizedBox(width: 16),
                        Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                                shape: BoxShape.circle, color: AppColors.busy)),
                        const SizedBox(width: 8),
                        Text('Absent ($absent)',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.busy)),
                      ])),

                // Employee list
                Expanded(
                    child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _employees.length,
                  itemBuilder: (ctx, i) {
                    final e = _employees[i];
                    final isHere = e.status == 'online';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: isHere
                                  ? AppColors.online.withOpacity(0.25)
                                  : AppColors.border)),
                      child: Row(children: [
                        UserAvatar(name: e.name, size: 46, status: e.status),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(e.name,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700)),
                              Text('${e.role} · ${e.department}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted)),
                              Text(e.email,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted)),
                            ])),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 5),
                                  decoration: BoxDecoration(
                                      color: (isHere
                                              ? AppColors.online
                                              : AppColors.busy)
                                          .withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Text(isHere ? 'Present' : 'Absent',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isHere
                                              ? AppColors.online
                                              : AppColors.busy))),
                              const SizedBox(height: 4),
                              Text(e.lastSeenText,
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: isHere
                                          ? AppColors.online
                                          : AppColors.textMuted)),
                            ]),
                      ]),
                    );
                  },
                )),
              ]),

              // ── To-Do Lists Tab ────────────────────────────────────────
              todos.isEmpty
                  ? Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          Icon(Icons.assignment_outlined,
                              size: 64,
                              color: AppColors.textMuted.withOpacity(0.3)),
                          const SizedBox(height: 16),
                          const Text('No work reports yet',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary)),
                          const SizedBox(height: 8),
                          const Text(
                              'Employee daily work reports appear here\nafter they check out',
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.textMuted),
                              textAlign: TextAlign.center),
                        ]))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: todos.length,
                      itemBuilder: (ctx, i) {
                        final s = todos[i];
                        final acknowledged = s['acknowledged'] == true;
                        return GestureDetector(
                          onTap: () => _viewTodo(s),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: acknowledged
                                        ? AppColors.border
                                        : AppColors.online.withOpacity(0.4)),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2))
                                ]),
                            child: Row(children: [
                              UserAvatar(name: s['employee'], size: 46),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Row(children: [
                                      Text(s['employee'],
                                          style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700)),
                                      if (!acknowledged) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                            width: 8,
                                            height: 8,
                                            decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: AppColors.busy)),
                                      ],
                                    ]),
                                    Text(
                                        '${s['date']} · Checked out: ${s['checkOut']}',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textMuted)),
                                    const SizedBox(height: 4),
                                    Text(
                                        '${(s['tasks'] as List).length} tasks completed',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.online,
                                            fontWeight: FontWeight.w600)),
                                  ])),
                              Column(children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                      color: acknowledged
                                          ? AppColors.online.withOpacity(0.1)
                                          : AppColors.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Text(acknowledged ? '✅ Done' : 'View',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: acknowledged
                                              ? AppColors.online
                                              : AppColors.primary,
                                          fontWeight: FontWeight.w700)),
                                ),
                                const SizedBox(height: 4),
                                const Icon(Icons.arrow_forward_ios,
                                    size: 12, color: AppColors.textMuted),
                              ]),
                            ]),
                          ),
                        );
                      }),
            ]),
    );
  }
}

class _Sum extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Sum(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.w800, color: color)),
        Text(label,
            style: TextStyle(fontSize: 12, color: color.withOpacity(0.8))),
      ]);
}
