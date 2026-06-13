import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';
import '../../../shared/widgets/app_widgets.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  List<UserModel> _employees = [];
  List<ApprovalModel> _pending = [];
  List<TaskModel> _tasks = [];
  bool _loading = true;
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final users = await ApiService.getUsers();
      if (mounted) setState(() => _employees = users);
    } catch (e) {
      debugPrint('Users error: $e');
    }
    try {
      final approvals = await ApiService.getApprovals();
      if (mounted)
        setState(() =>
            _pending = approvals.where((a) => a.status == 'pending').toList());
    } catch (e) {
      debugPrint('Approvals error: $e');
    }
    try {
      final tasks = await ApiService.getTasks();
      if (mounted) setState(() => _tasks = tasks);
    } catch (e) {
      debugPrint('Tasks error: $e');
    }
    if (mounted) {
      setState(() => _loading = false);
      _anim.forward(from: 0);
    }
  }

  Future<void> _handleApproval(ApprovalModel a, String status) async {
    try {
      await ApiService.updateApprovalStatus(a.id, status);
      _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(status == 'approved' ? '✅ Approved!' : '❌ Rejected'),
          backgroundColor:
              status == 'approved' ? AppColors.online : AppColors.busy,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;
    final auth = context.watch<AuthProvider>();
    final online = _employees.where((e) => e.status == 'online').length;
    final doneTasks = _tasks.where((t) => t.status == 'done').length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          // ✅ FIXED HEADER - stays at top always, never scrolls
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  themeColor,
                  themeColor.withOpacity(0.7),
                  AppColors.purple
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  // Decorative circles
                  Positioned(
                      top: -30,
                      right: -30,
                      child: Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.08)))),
                  Positioned(
                      bottom: -20,
                      left: -20,
                      child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.06)))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Row(children: [
                      Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: 2)),
                          child: const Icon(Icons.admin_panel_settings_rounded,
                              color: Colors.white, size: 26)),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Hello, ${auth.user?.name ?? 'Admin'}! 👋',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800)),
                            const Text('Admin Control Panel',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                          ])),
                      IconButton(
                          icon: const Icon(Icons.refresh_rounded,
                              color: Colors.white),
                          onPressed: _load),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.3))),
                        child: const Row(children: [
                          Icon(Icons.verified_rounded,
                              color: Colors.white, size: 14),
                          SizedBox(width: 5),
                          Text('ADMIN',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1)),
                        ]),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ),

          // ✅ SCROLLABLE CONTENT - only this part scrolls
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: AnimatedBuilder(
                      animation: _anim,
                      builder: (_, child) =>
                          FadeTransition(opacity: _anim, child: child),
                      child: ListView(
                        padding: const EdgeInsets.only(top: 20, bottom: 100),
                        children: [
                          // Stats
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(children: [
                              _StatCard(
                                  'Total Staff',
                                  '${_employees.length}',
                                  Icons.people_rounded,
                                  themeColor,
                                  AppColors.primaryGrad),
                              const SizedBox(width: 10),
                              _StatCard('Online', '$online', Icons.circle,
                                  AppColors.online, AppColors.emeraldGrad),
                              const SizedBox(width: 10),
                              _StatCard(
                                  'Approvals',
                                  '${_pending.length}',
                                  Icons.pending_actions_rounded,
                                  AppColors.away,
                                  AppColors.orangeGrad),
                              const SizedBox(width: 10),
                              _StatCard(
                                  'Done',
                                  '$doneTasks',
                                  Icons.task_alt_rounded,
                                  AppColors.purple,
                                  AppColors.purpleGrad),
                            ]),
                          ),
                          const SizedBox(height: 24),

                          // Team Members
                          _SectionHeader(
                              title: 'Team Members',
                              count: _employees.length,
                              color: themeColor),
                          const SizedBox(height: 10),

                          if (_employees.isEmpty)
                            _EmptyState(
                                icon: Icons.people_outline_rounded,
                                title: 'No team members yet',
                                subtitle:
                                    'Users will appear here when they register')
                          else
                            ..._employees.map((e) => _EmployeeCard(
                                employee: e, themeColor: themeColor)),

                          const SizedBox(height: 24),

                          if (_pending.isNotEmpty) ...[
                            _SectionHeader(
                                title: 'Pending Approvals',
                                count: _pending.length,
                                color: AppColors.away),
                            const SizedBox(height: 10),
                            ..._pending.map((a) => _ApprovalCard(
                                approval: a,
                                onApprove: () => _handleApproval(a, 'approved'),
                                onReject: () =>
                                    _handleApproval(a, 'rejected'))),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  const _SectionHeader(
      {required this.title, required this.count, required this.color});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20)),
            child: Text('$count',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ),
        ]),
      );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const _EmptyState(
      {required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(40),
        child: Column(children: [
          Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                  color: AppColors.surfaceVar, shape: BoxShape.circle),
              child: Icon(icon, size: 36, color: AppColors.textMuted)),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              textAlign: TextAlign.center),
        ]),
      );
}

class _EmployeeCard extends StatelessWidget {
  final UserModel employee;
  final Color themeColor;
  const _EmployeeCard({required this.employee, required this.themeColor});
  @override
  Widget build(BuildContext context) {
    final e = employee;
    final isOnline = e.status == 'online';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: isOnline
                ? AppColors.online.withOpacity(0.2)
                : AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(children: [
        Stack(children: [
          UserAvatar(name: e.name, size: 48, status: e.status),
          if (isOnline)
            Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                        color: AppColors.online,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2)))),
        ]),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.name,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
              '${e.role.isNotEmpty ? e.role : 'Employee'} · ${e.department.isNotEmpty ? e.department : 'General'}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          Text(e.email,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: (isOnline ? AppColors.online : AppColors.offline)
                .withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                    color: isOnline ? AppColors.online : AppColors.offline,
                    shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(isOnline ? 'Online' : 'Offline',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isOnline ? AppColors.online : AppColors.offline)),
          ]),
        ),
      ]),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  final ApprovalModel approval;
  final VoidCallback onApprove, onReject;
  const _ApprovalCard(
      {required this.approval,
      required this.onApprove,
      required this.onReject});
  @override
  Widget build(BuildContext context) {
    final a = approval;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.away.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
              color: AppColors.away.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                gradient: AppColors.orangeGrad,
                borderRadius: BorderRadius.circular(20)),
            child: Text(a.approvalType,
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w700)),
          ),
          const Spacer(),
          Text(formatDate(a.createdAt),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ]),
        const SizedBox(height: 10),
        Text(a.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        Text('From: ${a.requesterName}',
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        if (a.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(a.description,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: OutlinedButton.icon(
            onPressed: onReject,
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text('Reject'),
            style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.busy,
                side: const BorderSide(color: AppColors.busy),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 10)),
          )),
          const SizedBox(width: 12),
          Expanded(
              child: ElevatedButton.icon(
            onPressed: onApprove,
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Approve'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.online,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 10)),
          )),
        ]),
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final LinearGradient gradient;
  const _StatCard(this.label, this.value, this.icon, this.color, this.gradient);
  @override
  Widget build(BuildContext context) => Expanded(
          child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(children: [
          Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  gradient: gradient, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: Colors.white, size: 18)),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style: const TextStyle(
                  fontSize: 9,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500),
              textAlign: TextAlign.center),
        ]),
      ));
}
