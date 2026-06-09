import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';
import '../../../shared/widgets/app_widgets.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<TaskModel> _tasks = [];
  List<ApprovalModel> _approvals = [];
  List<UserModel> _admins = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // ✅ Auto-refresh every 8 seconds — no manual refresh needed
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 8));
      if (!mounted) return false;
      await _load();
      return mounted;
    });
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiService.getTasks(),
        ApiService.getApprovals(),
        ApiService.getUsers(),
      ]);
      if (mounted)
        setState(() {
          _tasks = results[0] as List<TaskModel>;
          _approvals = results[1] as List<ApprovalModel>;
          _admins =
              (results[2] as List<UserModel>).where((u) => u.isAdmin).toList();
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<TaskModel> get _myTasks {
    final myId = context.read<AuthProvider>().user?.id ?? '';
    return _tasks.where((t) => t.assigneeId == myId || t.isMine).toList();
  }

  List<ApprovalModel> get _myRequests {
    final myId = context.read<AuthProvider>().user?.id ?? '';
    return _approvals.where((a) => a.requesterId == myId).toList();
  }

  Future<void> _markDone(TaskModel task) async {
    try {
      await ApiService.updateTaskStatus(task.id, 'done');
      await _load();
      if (mounted)
        _snack('✅ Marked done — sent to admin for approval', AppColors.online);
    } catch (e) {
      if (mounted) _snack('Error: $e', AppColors.busy);
    }
  }

  Future<void> _updateStatus(TaskModel task, String status) async {
    try {
      await ApiService.updateTaskStatus(task.id, status);
      await _load();
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

  void _showCreateApproval() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String type = 'Leave';
    String approverId = _admins.isNotEmpty ? _admins.first.id : '';
    String approverName = _admins.isNotEmpty ? _admins.first.name : '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
          builder: (ctx, setS) => Container(
                decoration: const BoxDecoration(
                    color: AppColors.surface,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24))),
                padding: EdgeInsets.fromLTRB(
                    24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
                child: SingleChildScrollView(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                    const Text('New Approval Request',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),

                    // Type
                    Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          'Leave',
                          'Expense',
                          'Overtime',
                          'Equipment',
                          'Travel',
                          'Other'
                        ]
                            .map((t) => GestureDetector(
                                  onTap: () => setS(() => type = t),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 7),
                                    decoration: BoxDecoration(
                                        color: type == t
                                            ? AppColors.primary
                                            : AppColors.surfaceVar,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                            color: type == t
                                                ? AppColors.primary
                                                : AppColors.border)),
                                    child: Text(t,
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: type == t
                                                ? Colors.white
                                                : AppColors.textSecondary)),
                                  ),
                                ))
                            .toList()),
                    const SizedBox(height: 16),

                    TextField(
                        controller: titleCtrl,
                        decoration: InputDecoration(
                            labelText: '$type Request Title *',
                            prefixIcon: const Icon(Icons.title))),
                    const SizedBox(height: 12),
                    TextField(
                        controller: descCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                            labelText: 'Details / Reason',
                            prefixIcon: Icon(Icons.notes))),
                    const SizedBox(height: 16),

                    // Admin selector
                    const Text('Send To *',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    if (_admins.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: AppColors.busy.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10)),
                        child: const Row(children: [
                          Icon(Icons.warning_amber_rounded,
                              color: AppColors.busy, size: 16),
                          SizedBox(width: 8),
                          Text('No admin found. Contact your administrator.',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.busy)),
                        ]),
                      )
                    else
                      ..._admins.map((admin) => GestureDetector(
                            onTap: () => setS(() {
                              approverId = admin.id;
                              approverName = admin.name;
                            }),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  color: approverId == admin.id
                                      ? AppColors.primary.withOpacity(0.1)
                                      : AppColors.surfaceVar,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: approverId == admin.id
                                          ? AppColors.primary
                                          : AppColors.border)),
                              child: Row(children: [
                                UserAvatar(
                                    name: admin.name,
                                    size: 36,
                                    status: admin.status),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(admin.name,
                                          style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600)),
                                      Text('Admin · ${admin.department}',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textMuted)),
                                    ])),
                                if (approverId == admin.id)
                                  const Icon(Icons.check_circle,
                                      color: AppColors.primary, size: 22),
                              ]),
                            ),
                          )),
                    const SizedBox(height: 16),

                    SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (titleCtrl.text.trim().isEmpty) {
                              _snack('Please enter a title', AppColors.busy);
                              return;
                            }
                            if (approverId.isEmpty) {
                              _snack('Please select an admin', AppColors.busy);
                              return;
                            }
                            try {
                              await ApiService.createApproval({
                                'title': titleCtrl.text.trim(),
                                'approval_type': type,
                                'approver_id': approverId,
                                'description': descCtrl.text.trim(),
                              });
                              if (context.mounted) Navigator.pop(context);
                              await _load();
                              _snack('✅ $type request sent to $approverName!',
                                  AppColors.online);
                            } catch (e) {
                              _snack('Error: $e', AppColors.busy);
                            }
                          },
                          icon: const Icon(Icons.send),
                          label: const Text('Send Request'),
                          style: ElevatedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14)),
                        )),
                    const SizedBox(height: 16),
                  ],
                )),
              )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;
    final myTasks = _myTasks;
    final todo = myTasks.where((t) => t.status == 'todo').toList();
    final inProgress = myTasks.where((t) => t.status == 'in_progress').toList();
    final done = myTasks.where((t) => t.status == 'done').toList();
    final approved = myTasks.where((t) => t.status == 'approved').toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('My Tasks',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        actions: [
          // ✅ Show auto-refresh indicator
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: 'Auto-refreshing every 8s',
              child: Icon(Icons.sync,
                  color: themeColor.withOpacity(0.6), size: 18),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              // Info banner
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: themeColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: themeColor.withOpacity(0.2))),
                    child: Row(children: [
                      Icon(Icons.sync, color: themeColor, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              'Tasks auto-refresh every 8 seconds. New tasks appear automatically!',
                              style:
                                  TextStyle(fontSize: 12, color: themeColor))),
                    ]),
                  )),

              // Stats
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    _Stat('To Do', '${todo.length}', AppColors.textMuted),
                    const SizedBox(width: 8),
                    _Stat('In Progress', '${inProgress.length}', themeColor),
                    const SizedBox(width: 8),
                    _Stat('Done', '${done.length}', AppColors.away),
                    const SizedBox(width: 8),
                    _Stat('Approved', '${approved.length}', AppColors.online),
                  ])),
              const SizedBox(height: 16),

              if (myTasks.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(children: [
                      Icon(Icons.task_alt,
                          size: 56,
                          color: AppColors.textMuted.withOpacity(0.3)),
                      const SizedBox(height: 12),
                      const Text('No tasks assigned yet',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      const Text('Your admin will assign tasks to you.',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textMuted),
                          textAlign: TextAlign.center),
                    ])),

              if (inProgress.isNotEmpty) ...[
                _SectionHeader(
                    '🔄 In Progress', '${inProgress.length}', themeColor),
                ...inProgress.map((t) => _EmpTaskCard(
                    task: t,
                    onStatusChange: _updateStatus,
                    onMarkDone: () => _markDone(t))),
                const SizedBox(height: 8),
              ],
              if (todo.isNotEmpty) ...[
                _SectionHeader(
                    '📋 To Do', '${todo.length}', AppColors.textSecondary),
                ...todo.map((t) => _EmpTaskCard(
                    task: t,
                    onStatusChange: _updateStatus,
                    onMarkDone: () => _markDone(t))),
                const SizedBox(height: 8),
              ],
              if (done.isNotEmpty) ...[
                _SectionHeader(
                    '⏳ Awaiting Approval', '${done.length}', AppColors.away),
                ...done.map((t) => _EmpTaskCard(
                    task: t,
                    onStatusChange: _updateStatus,
                    onMarkDone: () => _markDone(t),
                    isPendingApproval: true)),
                const SizedBox(height: 8),
              ],
              if (approved.isNotEmpty) ...[
                _SectionHeader('✅ Approved by Admin', '${approved.length}',
                    AppColors.online),
                ...approved.map((t) => _EmpTaskCard(
                    task: t,
                    onStatusChange: _updateStatus,
                    onMarkDone: () {},
                    isApproved: true)),
                const SizedBox(height: 8),
              ],

              // My Requests
              const SizedBox(height: 8),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    const Text('My Requests',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    GestureDetector(
                      onTap: _showCreateApproval,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                            color: themeColor,
                            borderRadius: BorderRadius.circular(20)),
                        child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text('Request',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ]),
                      ),
                    ),
                  ])),
              const SizedBox(height: 10),
              if (_myRequests.isEmpty)
                Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border)),
                        child: const Center(
                            child: Text(
                                'No approval requests yet.\nTap Request to submit one.',
                                style: TextStyle(
                                    color: AppColors.textMuted, fontSize: 13),
                                textAlign: TextAlign.center))))
              else
                ..._myRequests.map((a) => _ApprovalCard(approval: a)),

              const SizedBox(height: 90),
            ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateApproval,
        backgroundColor: themeColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Request',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Stat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
          child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border)),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
              textAlign: TextAlign.center),
        ]),
      ));
}

class _SectionHeader extends StatelessWidget {
  final String title, count;
  final Color color;
  const _SectionHeader(this.title, this.count, this.color);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Text(count,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color))),
        ]),
      );
}

class _EmpTaskCard extends StatelessWidget {
  final TaskModel task;
  final Function(TaskModel, String) onStatusChange;
  final VoidCallback onMarkDone;
  final bool isPendingApproval, isApproved;
  const _EmpTaskCard(
      {required this.task,
      required this.onStatusChange,
      required this.onMarkDone,
      this.isPendingApproval = false,
      this.isApproved = false});

  Color get _priColor {
    switch (task.priority) {
      case 'urgent':
        return AppColors.busy;
      case 'high':
        return AppColors.orange;
      case 'low':
        return AppColors.online;
      default:
        return AppColors.away;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: isApproved
                ? AppColors.online.withOpacity(0.05)
                : isPendingApproval
                    ? AppColors.away.withOpacity(0.05)
                    : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isApproved
                    ? AppColors.online.withOpacity(0.3)
                    : isPendingApproval
                        ? AppColors.away.withOpacity(0.3)
                        : AppColors.border),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(task.title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700))),
            AppChip(label: task.priority.toUpperCase(), color: _priColor),
          ]),
          const SizedBox(height: 6),
          if (task.description.isNotEmpty)
            Text(task.description,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.person_outline,
                size: 14, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Text(
                'By: ${task.creatorName.isNotEmpty ? task.creatorName : 'Admin'}',
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            const Spacer(),
            Icon(Icons.calendar_today,
                size: 10,
                color: task.isOverdue ? AppColors.busy : AppColors.textMuted),
            const SizedBox(width: 4),
            Text(
                '${task.dueDate.day}/${task.dueDate.month}/${task.dueDate.year}',
                style: TextStyle(
                    fontSize: 11,
                    color:
                        task.isOverdue ? AppColors.busy : AppColors.textMuted,
                    fontWeight:
                        task.isOverdue ? FontWeight.w700 : FontWeight.w400)),
          ]),
          if (!isPendingApproval && !isApproved) ...[
            const SizedBox(height: 10),
            Row(children: [
              _StatusBtn('To Do', task.status == 'todo', AppColors.textMuted,
                  () => onStatusChange(task, 'todo')),
              const SizedBox(width: 4),
              _StatusBtn('In Progress', task.status == 'in_progress',
                  AppColors.primary, () => onStatusChange(task, 'in_progress')),
              const SizedBox(width: 4),
              _StatusBtn('Review', task.status == 'review', AppColors.away,
                  () => onStatusChange(task, 'review')),
            ]),
            const SizedBox(height: 8),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onMarkDone,
                  icon: const Icon(Icons.check_circle, size: 16),
                  label: const Text('Mark Done — Send to Admin'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.online,
                      padding: const EdgeInsets.symmetric(vertical: 10)),
                )),
          ],
          if (isPendingApproval)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: AppColors.away.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Row(children: [
                      Icon(Icons.schedule, size: 14, color: AppColors.away),
                      SizedBox(width: 6),
                      Text('Waiting for admin approval',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.away,
                              fontWeight: FontWeight.w500)),
                    ]))),
          if (isApproved)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: AppColors.online.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Row(children: [
                      Icon(Icons.verified, size: 14, color: AppColors.online),
                      SizedBox(width: 6),
                      Text('Approved by admin ✅',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.online,
                              fontWeight: FontWeight.w500)),
                    ]))),
        ]),
      );
}

class _StatusBtn extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _StatusBtn(this.label, this.active, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: active ? color.withOpacity(0.15) : AppColors.surfaceVar,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: active ? color : AppColors.border)),
          child: Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  color: active ? color : AppColors.textMuted)),
        ),
      );
}

class _ApprovalCard extends StatelessWidget {
  final ApprovalModel approval;
  const _ApprovalCard({required this.approval});

  Color get _color {
    switch (approval.status) {
      case 'approved':
        return AppColors.online;
      case 'rejected':
        return AppColors.busy;
      default:
        return AppColors.away;
    }
  }

  String get _label {
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
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _color.withOpacity(0.3))),
        child: Row(children: [
          Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: _color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.approval, color: _color, size: 20)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(approval.title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                Text(approval.approvalType,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted)),
                if (approval.approverName.isNotEmpty)
                  Text('To: ${approval.approverName}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted)),
              ])),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: _color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(_label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _color))),
        ]),
      );
}
