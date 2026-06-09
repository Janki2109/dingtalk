import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';
import '../../../shared/widgets/app_widgets.dart';

class AdminTasksScreen extends StatefulWidget {
  const AdminTasksScreen({super.key});
  @override
  State<AdminTasksScreen> createState() => _AdminTasksScreenState();
}

class _AdminTasksScreenState extends State<AdminTasksScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<TaskModel> _tasks = [];
  List<ApprovalModel> _approvals = [];
  List<UserModel> _employees = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
    // ✅ Auto-refresh every 8 seconds
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 8));
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
      final results = await Future.wait([
        ApiService.getTasks(),
        ApiService.getUsers(),
        ApiService.getApprovals(),
      ]);
      if (mounted)
        setState(() {
          _tasks = results[0] as List<TaskModel>;
          _employees =
              (results[1] as List<UserModel>).where((u) => !u.isAdmin).toList();
          _approvals = results[2] as List<ApprovalModel>;
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ApprovalModel> get _pendingApprovals {
    final myId = context.read<AuthProvider>().user?.id ?? '';
    return _approvals
        .where((a) => a.approverId == myId && a.status == 'pending')
        .toList();
  }

  List<ApprovalModel> get _allApprovals {
    final myId = context.read<AuthProvider>().user?.id ?? '';
    return _approvals.where((a) => a.approverId == myId).toList();
  }

  Future<void> _approveTask(TaskModel task) async {
    try {
      await ApiService.updateTaskStatus(task.id, 'approved');
      await _load();
      if (mounted) _snack('✅ Task approved!', AppColors.online);
    } catch (_) {}
  }

  Future<void> _handleApproval(ApprovalModel approval, String status) async {
    try {
      await ApiService.updateApprovalStatus(approval.id, status);
      await _load();
      if (mounted)
        _snack(
          status == 'approved'
              ? '✅ Approved & employee notified!'
              : '❌ Rejected & employee notified!',
          status == 'approved' ? AppColors.online : AppColors.busy,
        );
    } catch (_) {}
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showCreateTask() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final projectCtrl = TextEditingController(text: 'General');
    String priority = 'medium';
    String assigneeId = '';
    String assigneeName = '';
    DateTime dueDate = DateTime.now().add(const Duration(days: 7));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: EdgeInsets.fromLTRB(
              24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 16),
          child: SingleChildScrollView(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              const Text('Assign New Task',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Task Title *',
                      prefixIcon: Icon(Icons.task_alt))),
              const SizedBox(height: 12),
              TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Description', prefixIcon: Icon(Icons.notes))),
              const SizedBox(height: 12),
              TextField(
                  controller: projectCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Project',
                      prefixIcon: Icon(Icons.folder_outlined))),
              const SizedBox(height: 16),
              const Text('Assign To *',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              ..._employees.map((e) => GestureDetector(
                    onTap: () => setS(() {
                      assigneeId = e.id;
                      assigneeName = e.name;
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: assigneeId == e.id
                              ? AppColors.primary.withOpacity(0.1)
                              : AppColors.surfaceVar,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: assigneeId == e.id
                                  ? AppColors.primary
                                  : AppColors.border)),
                      child: Row(children: [
                        UserAvatar(name: e.name, size: 36, status: e.status),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(e.name,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              Text('${e.role} · ${e.department}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted)),
                            ])),
                        if (assigneeId == e.id)
                          const Icon(Icons.check_circle,
                              color: AppColors.primary, size: 20),
                      ]),
                    ),
                  )),
              const SizedBox(height: 16),
              const Text('Priority',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Row(
                  children: ['low', 'medium', 'high', 'urgent']
                      .map((p) => Expanded(
                            child: GestureDetector(
                              onTap: () => setS(() => priority = p),
                              child: Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                    color: priority == p
                                        ? AppColors.primary.withOpacity(0.1)
                                        : AppColors.surfaceVar,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: priority == p
                                            ? AppColors.primary
                                            : AppColors.border)),
                                child: Text(p[0].toUpperCase() + p.substring(1),
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: priority == p
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                        color: priority == p
                                            ? AppColors.primary
                                            : AppColors.textMuted),
                                    textAlign: TextAlign.center),
                              ),
                            ),
                          ))
                      .toList()),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  final d = await showDatePicker(
                      context: context,
                      initialDate: dueDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (d != null) setS(() => dueDate = d);
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: AppColors.surfaceVar,
                      borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 10),
                    const Text('Due Date',
                        style: TextStyle(
                            fontSize: 14, color: AppColors.textSecondary)),
                    const Spacer(),
                    Text(formatDate(dueDate),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (titleCtrl.text.trim().isEmpty) {
                        _snack('Enter task title', AppColors.busy);
                        return;
                      }
                      if (assigneeId.isEmpty) {
                        _snack('Select an employee', AppColors.busy);
                        return;
                      }
                      try {
                        await ApiService.createTask({
                          'title': titleCtrl.text.trim(),
                          'description': descCtrl.text.trim(),
                          'assignee_id': assigneeId,
                          'priority': priority,
                          'project_name': projectCtrl.text.trim(),
                          'due_date': dueDate.toIso8601String(),
                        });
                        Navigator.pop(context);
                        await _load();
                        _snack('✅ Task assigned to $assigneeName!',
                            AppColors.online);
                      } catch (e) {
                        _snack('Error: $e', AppColors.busy);
                      }
                    },
                    icon: const Icon(Icons.send),
                    label: const Text('Assign Task'),
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                  )),
              const SizedBox(height: 20),
            ],
          )),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;
    final needApproval = _tasks.where((t) => t.status == 'done').toList();
    final active = _tasks
        .where((t) => t.status != 'done' && t.status != 'approved')
        .toList();
    final approved = _tasks.where((t) => t.status == 'approved').toList();
    final pendingCount = _pendingApprovals.length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Task Management',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(icon: const Icon(Icons.add), onPressed: _showCreateTask),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: themeColor,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: themeColor,
          tabs: [
            const Tab(text: 'Tasks'),
            Tab(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Approvals'),
              if (pendingCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppColors.busy,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('$pendingCount',
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
              // ── Tasks Tab ──────────────────────────────────────────────
              ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  _TCard('Active', '${active.length}', themeColor),
                  const SizedBox(width: 8),
                  _TCard('Review', '${needApproval.length}', AppColors.away),
                  const SizedBox(width: 8),
                  _TCard('Approved', '${approved.length}', AppColors.online),
                ]),
                const SizedBox(height: 20),
                if (needApproval.isNotEmpty) ...[
                  Row(children: [
                    const Text('⏳ Needs Approval',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: AppColors.away.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10)),
                        child: Text('${needApproval.length}',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.away))),
                  ]),
                  const SizedBox(height: 10),
                  ...needApproval.map((t) => _TaskCard(
                      task: t,
                      showApprove: true,
                      onApprove: () => _approveTask(t))),
                  const SizedBox(height: 16),
                ],
                if (active.isNotEmpty) ...[
                  const Text('📋 Active Tasks',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  ...active.map((t) => _TaskCard(task: t)),
                  const SizedBox(height: 16),
                ],
                if (approved.isNotEmpty) ...[
                  const Text('✅ Approved',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  ...approved.map((t) => _TaskCard(task: t)),
                ],
                if (_tasks.isEmpty)
                  Center(
                      child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(children: [
                      Icon(Icons.task_alt,
                          size: 56,
                          color: AppColors.textMuted.withOpacity(0.3)),
                      const SizedBox(height: 12),
                      const Text('No tasks yet',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary)),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                          onPressed: _showCreateTask,
                          icon: const Icon(Icons.add),
                          label: const Text('Assign Task')),
                    ]),
                  )),
                const SizedBox(height: 90),
              ]),

              // ── Approvals Tab ──────────────────────────────────────────
              ListView(padding: const EdgeInsets.all(16), children: [
                if (_pendingApprovals.isNotEmpty) ...[
                  Row(children: [
                    const Text('🔔 Pending Requests',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.busy.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10)),
                      child: Text('$pendingCount',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.busy)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  ..._pendingApprovals.map((a) => _ApprovalCard(
                        approval: a,
                        canAction: true,
                        onApprove: () => _handleApproval(a, 'approved'),
                        onReject: () => _handleApproval(a, 'rejected'),
                      )),
                  const SizedBox(height: 20),
                ],
                const Text('📋 All Requests',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                if (_allApprovals.isEmpty)
                  Container(
                      padding: const EdgeInsets.all(32),
                      child: Column(children: [
                        Icon(Icons.inbox_outlined,
                            size: 48,
                            color: AppColors.textMuted.withOpacity(0.3)),
                        const SizedBox(height: 12),
                        const Text('No approval requests yet',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 6),
                        const Text('Employee requests will appear here',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textMuted)),
                      ]))
                else
                  ..._allApprovals.map((a) => _ApprovalCard(
                        approval: a,
                        canAction: a.status == 'pending',
                        onApprove: () => _handleApproval(a, 'approved'),
                        onReject: () => _handleApproval(a, 'rejected'),
                      )),
                const SizedBox(height: 90),
              ]),
            ]),
      floatingActionButton: FloatingActionButton(
          onPressed: _showCreateTask,
          backgroundColor: themeColor,
          child: const Icon(Icons.add, color: Colors.white)),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  final ApprovalModel approval;
  final bool canAction;
  final VoidCallback onApprove, onReject;
  const _ApprovalCard(
      {required this.approval,
      required this.canAction,
      required this.onApprove,
      required this.onReject});

  Color get _statusColor {
    switch (approval.status) {
      case 'approved':
        return AppColors.online;
      case 'rejected':
        return AppColors.busy;
      default:
        return AppColors.away;
    }
  }

  String get _statusLabel {
    switch (approval.status) {
      case 'approved':
        return 'Approved ✅';
      case 'rejected':
        return 'Rejected ❌';
      default:
        return 'Pending ⏳';
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: canAction && approval.status == 'pending'
                  ? AppColors.away.withOpacity(0.5)
                  : AppColors.border),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(approval.approvalType,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary)),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(_statusLabel,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _statusColor)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(approval.title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          if (approval.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(approval.description,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 10),
          Row(children: [
            UserAvatar(name: approval.requesterName, size: 22),
            const SizedBox(width: 6),
            Text(approval.requesterName,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            const Text('→ You',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const Spacer(),
            Text(formatDate(approval.createdAt),
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
          if (canAction && approval.status == 'pending') ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                onPressed: onReject,
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.busy,
                    side: const BorderSide(color: AppColors.busy)),
                child: const Text('Reject'),
              )),
              const SizedBox(width: 12),
              Expanded(
                  child: ElevatedButton(
                onPressed: onApprove,
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.online),
                child: const Text('Approve'),
              )),
            ]),
          ],
        ]),
      );
}

class _TCard extends StatelessWidget {
  final String label, value;
  final Color color;
  const _TCard(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
          child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.2))),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ]),
      ));
}

class _TaskCard extends StatelessWidget {
  final TaskModel task;
  final bool showApprove;
  final VoidCallback? onApprove;
  const _TaskCard(
      {required this.task, this.showApprove = false, this.onApprove});

  Color get _color {
    switch (task.status) {
      case 'done':
        return AppColors.away;
      case 'approved':
        return AppColors.online;
      case 'in_progress':
        return AppColors.primary;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: showApprove
                    ? AppColors.away.withOpacity(0.4)
                    : AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(task.title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700))),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: _color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(task.status.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _color))),
          ]),
          const SizedBox(height: 6),
          if (task.description.isNotEmpty)
            Text(task.description,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Row(children: [
            UserAvatar(name: task.assigneeName, size: 20),
            const SizedBox(width: 6),
            Text(task.assigneeName,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const Spacer(),
            Icon(Icons.calendar_today,
                size: 10,
                color: task.isOverdue ? AppColors.busy : AppColors.textMuted),
            const SizedBox(width: 4),
            Text(formatDate(task.dueDate),
                style: TextStyle(
                    fontSize: 11,
                    color:
                        task.isOverdue ? AppColors.busy : AppColors.textMuted,
                    fontWeight:
                        task.isOverdue ? FontWeight.w700 : FontWeight.w400)),
          ]),
          if (showApprove && onApprove != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(children: [
              const Expanded(
                  child: Text('✅ Employee marked done',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.away,
                          fontWeight: FontWeight.w500))),
              ElevatedButton(
                  onPressed: onApprove,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.online,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8)),
                  child: const Text('Approve', style: TextStyle(fontSize: 12))),
            ]),
          ],
        ]),
      );
}
