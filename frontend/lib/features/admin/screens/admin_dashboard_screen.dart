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

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List<UserModel> _employees = [];
  List<ApprovalModel> _pending = [];
  List<TaskModel> _tasks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    // ✅ Load each API separately so one failure doesn't block others
    try {
      final users = await ApiService.getUsers();
      if (mounted) setState(() => _employees = users);
    } catch (e) {
      debugPrint('Users error: $e');
    }

    try {
      final approvals = await ApiService.getApprovals();
      if (mounted) {
        setState(() =>
            _pending = approvals.where((a) => a.status == 'pending').toList());
      }
    } catch (e) {
      debugPrint('Approvals error: $e');
    }

    try {
      final tasks = await ApiService.getTasks();
      if (mounted) setState(() => _tasks = tasks);
    } catch (e) {
      debugPrint('Tasks error: $e');
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _handleApproval(ApprovalModel a, String status) async {
    try {
      await ApiService.updateApprovalStatus(a.id, status);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(status == 'approved' ? '✅ Approved!' : '❌ Rejected'),
            backgroundColor:
                status == 'approved' ? AppColors.online : AppColors.busy,
            behavior: SnackBarBehavior.floating));
      }
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
      body: CustomScrollView(slivers: [
        SliverAppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          expandedHeight: 160,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [themeColor, themeColor.withOpacity(0.8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight)),
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Hello, ${auth.user?.name ?? 'Admin'}! 👋',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800)),
                            const Text('Admin Control Panel',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                          ])),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(20)),
                          child: const Row(children: [
                            Icon(Icons.admin_panel_settings,
                                color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text('ADMIN',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800)),
                          ])),
                    ]),
                  ]),
            ),
          ),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: _load),
          ],
        ),
        SliverToBoxAdapter(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()))
                : Column(children: [
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        _StatCard('Total Staff', '${_employees.length}',
                            Icons.people, themeColor),
                        const SizedBox(width: 8),
                        _StatCard('Online Now', '$online', Icons.circle,
                            AppColors.online),
                        const SizedBox(width: 8),
                        _StatCard('Approvals', '${_pending.length}',
                            Icons.pending_actions, AppColors.away),
                        const SizedBox(width: 8),
                        _StatCard('Done Tasks', '$doneTasks', Icons.task_alt,
                            AppColors.purple),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        const Text('Team Members',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                                color: themeColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10)),
                            child: Text('${_employees.length}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: themeColor))),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    if (_employees.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(children: [
                          Icon(Icons.people_outline,
                              size: 56,
                              color: AppColors.textMuted.withOpacity(0.3)),
                          const SizedBox(height: 12),
                          const Text('No team members yet',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary)),
                          const SizedBox(height: 6),
                          const Text(
                              'Users will appear here when they register',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textMuted)),
                        ]),
                      )
                    else
                      ..._employees.map((e) => Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.border)),
                            child: Row(children: [
                              UserAvatar(
                                  name: e.name, size: 44, status: e.status),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(e.name,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700)),
                                    Text(
                                        '${e.role.isNotEmpty ? e.role : 'Employee'} · ${e.department.isNotEmpty ? e.department : 'General'}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textMuted)),
                                    Text(e.email,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textMuted)),
                                  ])),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                    color: (e.status == 'online'
                                            ? AppColors.online
                                            : AppColors.offline)
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20)),
                                child: Text(
                                    e.status == 'online'
                                        ? '🟢 Online'
                                        : '⚫ Offline',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: e.status == 'online'
                                            ? AppColors.online
                                            : AppColors.offline)),
                              ),
                            ]),
                          )),
                    const SizedBox(height: 20),
                    if (_pending.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(children: [
                          const Text('Pending Approvals',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 8),
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                  color: AppColors.busy.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10)),
                              child: Text('${_pending.length}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.busy))),
                        ]),
                      ),
                      const SizedBox(height: 10),
                      ..._pending.map((a) => Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 5),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: AppColors.away.withOpacity(0.3))),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                            color:
                                                AppColors.away.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        child: Text(a.approvalType,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.away,
                                                fontWeight: FontWeight.w600))),
                                    const Spacer(),
                                    Text(formatDate(a.createdAt),
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textMuted)),
                                  ]),
                                  const SizedBox(height: 8),
                                  Text(a.title,
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700)),
                                  Text('From: ${a.requesterName}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary)),
                                  if (a.description.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(a.description,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textMuted)),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    Expanded(
                                        child: OutlinedButton(
                                            onPressed: () =>
                                                _handleApproval(a, 'rejected'),
                                            style: OutlinedButton.styleFrom(
                                                foregroundColor: AppColors.busy,
                                                side: const BorderSide(
                                                    color: AppColors.busy)),
                                            child: const Text('Reject'))),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: ElevatedButton(
                                            onPressed: () =>
                                                _handleApproval(a, 'approved'),
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    AppColors.online),
                                            child: const Text('Approve ✅'))),
                                  ]),
                                ]),
                          )),
                    ],
                    const SizedBox(height: 90),
                  ])),
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard(this.label, this.value, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
          child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border)),
        child: Column(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
              textAlign: TextAlign.center),
        ]),
      ));
}
