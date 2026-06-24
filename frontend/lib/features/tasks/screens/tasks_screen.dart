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

class _TasksScreenState extends State<TasksScreen>
    with TickerProviderStateMixin {
  List<TaskModel> _tasks = [];
  List<ApprovalModel> _approvals = [];
  List<UserModel> _admins = [];
  bool _loading = true;
  late AnimationController _headerAnim;
  late Animation<double> _headerFade;

  @override
  void initState() {
    super.initState();
    _headerAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _headerFade = CurvedAnimation(parent: _headerAnim, curve: Curves.easeOut);
    _load();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 8));
      if (!mounted) return false;
      await _load();
      return mounted;
    });
  }

  @override
  void dispose() {
    _headerAnim.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiService.getTasks(),
        ApiService.getApprovals(),
        ApiService.getUsers()
      ]);
      if (mounted)
        setState(() {
          _tasks = results[0] as List<TaskModel>;
          _approvals = results[1] as List<ApprovalModel>;
          _admins =
              (results[2] as List<UserModel>).where((u) => u.isAdmin).toList();
          _loading = false;
        });
      _headerAnim.forward(from: 0);
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                        BorderRadius.vertical(top: Radius.circular(28))),
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
                      Row(children: [
                        Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                                gradient: AppColors.orangeGrad,
                                borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.approval_rounded,
                                color: Colors.white, size: 22)),
                        const SizedBox(width: 12),
                        const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('New Request',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700)),
                              Text('Submit to your admin',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted)),
                            ]),
                      ]),
                      const SizedBox(height: 20),
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
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 7),
                                    decoration: BoxDecoration(
                                      gradient: type == t
                                          ? AppColors.primaryGrad
                                          : null,
                                      color: type == t
                                          ? null
                                          : AppColors.surfaceVar,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                          color: type == t
                                              ? Colors.transparent
                                              : AppColors.border),
                                    ),
                                    child: Text(t,
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: type == t
                                                ? Colors.white
                                                : AppColors.textSecondary)),
                                  )))
                              .toList()),
                      const SizedBox(height: 16),
                      TextField(
                          controller: titleCtrl,
                          decoration: InputDecoration(
                              labelText: '$type Title *',
                              prefixIcon: const Icon(Icons.title_rounded))),
                      const SizedBox(height: 12),
                      TextField(
                          controller: descCtrl,
                          maxLines: 3,
                          decoration: const InputDecoration(
                              labelText: 'Details / Reason',
                              prefixIcon: Icon(Icons.notes_rounded),
                              alignLabelWithHint: true)),
                      const SizedBox(height: 16),
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
                                color: AppColors.busy.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12)),
                            child: const Row(children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: AppColors.busy, size: 16),
                              SizedBox(width: 8),
                              Expanded(
                                  child: Text('No admin found',
                                      style: TextStyle(
                                          fontSize: 12, color: AppColors.busy)))
                            ]))
                      else
                        ..._admins.map((admin) => GestureDetector(
                            onTap: () => setS(() {
                                  approverId = admin.id;
                                  approverName = admin.name;
                                }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: approverId == admin.id
                                    ? AppColors.primary.withOpacity(0.08)
                                    : AppColors.surfaceVar,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: approverId == admin.id
                                        ? AppColors.primary
                                        : AppColors.border,
                                    width: approverId == admin.id ? 1.5 : 1),
                              ),
                              child: Row(children: [
                                UserAvatar(
                                    name: admin.name,
                                    size: 38,
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
                                  Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                          gradient: AppColors.primaryGrad,
                                          shape: BoxShape.circle),
                                      child: const Icon(Icons.check,
                                          color: Colors.white, size: 14)),
                              ]),
                            ))),
                      const SizedBox(height: 20),
                      Container(
                          width: double.infinity,
                          height: 52,
                          decoration: BoxDecoration(
                              gradient: AppColors.primaryGrad,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                    color: AppColors.primary.withOpacity(0.3),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6))
                              ]),
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              if (titleCtrl.text.trim().isEmpty) {
                                _snack('Please enter a title', AppColors.busy);
                                return;
                              }
                              if (approverId.isEmpty) {
                                _snack(
                                    'Please select an admin', AppColors.busy);
                                return;
                              }
                              try {
                                await ApiService.createApproval({
                                  'title': titleCtrl.text.trim(),
                                  'approval_type': type,
                                  'approver_id': approverId,
                                  'description': descCtrl.text.trim()
                                });
                                if (context.mounted) Navigator.pop(context);
                                await _load();
                                _snack('✅ $type request sent to $approverName!',
                                    AppColors.online);
                              } catch (e) {
                                _snack('Error: $e', AppColors.busy);
                              }
                            },
                            icon: const Icon(Icons.send_rounded, size: 18),
                            label: const Text('Send Request',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))),
                          )),
                      const SizedBox(height: 16),
                    ])),
              )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;
    final auth = context.watch<AuthProvider>();
    final myTasks = _myTasks;
    final todo = myTasks.where((t) => t.status == 'todo').toList();
    final inProgress = myTasks.where((t) => t.status == 'in_progress').toList();
    final done = myTasks.where((t) => t.status == 'done').toList();
    final approved = myTasks.where((t) => t.status == 'approved').toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 160,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [themeColor, AppColors.purple],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight)),
              child: Stack(children: [
                Positioned(
                    top: -20,
                    right: -20,
                    child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.07)))),
                Positioned(
                    bottom: -10,
                    left: 40,
                    child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.05)))),
                Padding(
                    padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Text('My Tasks',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(
                              '${myTasks.length} total · ${inProgress.length} in progress',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 13)),
                        ])),
              ]),
            ),
          ),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                onPressed: _load),
          ],
        ),
        if (_loading)
          const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()))
        else
          SliverToBoxAdapter(
              child: FadeTransition(
                  opacity: _headerFade,
                  child: Column(children: [
                    // Stats row
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(children: [
                          _StatPill('To Do', todo.length, AppColors.textMuted,
                              Icons.radio_button_unchecked),
                          const SizedBox(width: 8),
                          _StatPill('Doing', inProgress.length, themeColor,
                              Icons.pending_rounded),
                          const SizedBox(width: 8),
                          _StatPill('Review', done.length, AppColors.away,
                              Icons.hourglass_top_rounded),
                          const SizedBox(width: 8),
                          _StatPill('Done', approved.length, AppColors.online,
                              Icons.check_circle_rounded),
                        ])),

                    if (myTasks.isEmpty)
                      _EmptyTasks()
                    else ...[
                      if (inProgress.isNotEmpty) ...[
                        _SectionLabel(
                            '🔄 In Progress', inProgress.length, themeColor),
                        ...inProgress.map((t) => _TaskCard(
                            task: t,
                            themeColor: themeColor,
                            onStatusChange: _updateStatus,
                            onMarkDone: () => _markDone(t))),
                      ],
                      if (todo.isNotEmpty) ...[
                        _SectionLabel(
                            '📋 To Do', todo.length, AppColors.textSecondary),
                        ...todo.map((t) => _TaskCard(
                            task: t,
                            themeColor: themeColor,
                            onStatusChange: _updateStatus,
                            onMarkDone: () => _markDone(t))),
                      ],
                      if (done.isNotEmpty) ...[
                        _SectionLabel(
                            '⏳ Awaiting Approval', done.length, AppColors.away),
                        ...done.map((t) => _TaskCard(
                            task: t,
                            themeColor: themeColor,
                            onStatusChange: _updateStatus,
                            onMarkDone: () => _markDone(t),
                            isPending: true)),
                      ],
                      if (approved.isNotEmpty) ...[
                        _SectionLabel(
                            '✅ Approved', approved.length, AppColors.online),
                        ...approved.map((t) => _TaskCard(
                            task: t,
                            themeColor: themeColor,
                            onStatusChange: _updateStatus,
                            onMarkDone: () {},
                            isApproved: true)),
                      ],
                    ],

                    // Requests
                    const SizedBox(height: 8),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(children: [
                          const Text('My Requests',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          _PillButton(
                              label: '+ New Request',
                              color: themeColor,
                              onTap: _showCreateApproval),
                        ])),
                    const SizedBox(height: 12),
                    if (_myRequests.isEmpty)
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.border)),
                            child: const Center(
                                child: Text(
                                    'No requests yet. Tap + New Request to submit one.',
                                    style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 13),
                                    textAlign: TextAlign.center)),
                          ))
                    else
                      ..._myRequests.map((a) => _RequestCard(approval: a)),
                    const SizedBox(height: 100),
                  ]))),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateApproval,
        backgroundColor: themeColor,
        elevation: 4,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('New Request',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  const _StatPill(this.label, this.count, this.color, this.icon);
  @override
  Widget build(BuildContext context) => Expanded(
          child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                  color: color.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 3))
            ]),
        child: Column(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text('$count',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style: const TextStyle(
                  fontSize: 9,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500),
              textAlign: TextAlign.center),
        ]),
      ));
}

class _SectionLabel extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  const _SectionLabel(this.title, this.count, this.color);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Text('$count',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color))),
        ]),
      );
}

class _PillButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PillButton(
      {required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color, color.withOpacity(0.8)]),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ]),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      ));
}

class _EmptyTasks extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(48),
      child: Column(children: [
        Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
                gradient: AppColors.primaryGrad.scale(0.15),
                borderRadius: BorderRadius.circular(24)),
            child: const Icon(Icons.task_alt_rounded,
                size: 40, color: AppColors.primary)),
        const SizedBox(height: 16),
        const Text('No tasks yet',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        const Text('Your admin will assign tasks to you here.',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            textAlign: TextAlign.center),
      ]));
}

class _TaskCard extends StatefulWidget {
  final TaskModel task;
  final Color themeColor;
  final Function(TaskModel, String) onStatusChange;
  final VoidCallback onMarkDone;
  final bool isPending, isApproved;
  const _TaskCard(
      {required this.task,
      required this.themeColor,
      required this.onStatusChange,
      required this.onMarkDone,
      this.isPending = false,
      this.isApproved = false});
  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _scale;
  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 100),
        lowerBound: 0.97,
        upperBound: 1.0,
        value: 1.0);
    _scale = _anim;
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Color get _priColor {
    switch (widget.task.priority) {
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
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _anim.reverse(),
        onTapUp: (_) => _anim.forward(),
        onTapCancel: () => _anim.forward(),
        child: ScaleTransition(
            scale: _scale,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: widget.isApproved
                    ? AppColors.online.withOpacity(0.04)
                    : widget.isPending
                        ? AppColors.away.withOpacity(0.04)
                        : AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: widget.isApproved
                        ? AppColors.online.withOpacity(0.25)
                        : widget.isPending
                            ? AppColors.away.withOpacity(0.25)
                            : AppColors.border),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ],
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: _priColor, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(widget.task.title,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700))),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: _priColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(widget.task.priority.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: _priColor,
                                  letterSpacing: 0.5))),
                    ]),
                    if (widget.task.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(widget.task.description,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 10),
                    Row(children: [
                      const Icon(Icons.person_outline_rounded,
                          size: 13, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                          'By ${widget.task.creatorName.isNotEmpty ? widget.task.creatorName : 'Admin'}',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textMuted)),
                      const Spacer(),
                      Icon(Icons.calendar_today_rounded,
                          size: 11,
                          color: widget.task.isOverdue
                              ? AppColors.busy
                              : AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                          '${widget.task.dueDate.day}/${widget.task.dueDate.month}/${widget.task.dueDate.year}',
                          style: TextStyle(
                              fontSize: 11,
                              color: widget.task.isOverdue
                                  ? AppColors.busy
                                  : AppColors.textMuted,
                              fontWeight: widget.task.isOverdue
                                  ? FontWeight.w700
                                  : FontWeight.w400)),
                    ]),
                    if (!widget.isPending && !widget.isApproved) ...[
                      const SizedBox(height: 12),
                      Row(children: [
                        _StatusChip(
                            'Todo',
                            widget.task.status == 'todo',
                            AppColors.textMuted,
                            () => widget.onStatusChange(widget.task, 'todo')),
                        const SizedBox(width: 6),
                        _StatusChip(
                            'Doing',
                            widget.task.status == 'in_progress',
                            widget.themeColor,
                            () => widget.onStatusChange(
                                widget.task, 'in_progress')),
                        const SizedBox(width: 6),
                        _StatusChip(
                            'Review',
                            widget.task.status == 'review',
                            AppColors.away,
                            () => widget.onStatusChange(widget.task, 'review')),
                      ]),
                      const SizedBox(height: 10),
                      GestureDetector(
                          onTap: widget.onMarkDone,
                          child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                  gradient: AppColors.emeraldGrad,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                        color:
                                            AppColors.online.withOpacity(0.3),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4))
                                  ]),
                              child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check_circle_rounded,
                                        color: Colors.white, size: 16),
                                    SizedBox(width: 6),
                                    Text('Mark Done — Send to Admin',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700)),
                                  ]))),
                    ],
                    if (widget.isPending) ...[
                      const SizedBox(height: 10),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                              color: AppColors.away.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: AppColors.away.withOpacity(0.2))),
                          child: const Row(children: [
                            Icon(Icons.schedule_rounded,
                                size: 14, color: AppColors.away),
                            SizedBox(width: 6),
                            Text('Waiting for admin approval',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.away,
                                    fontWeight: FontWeight.w500))
                          ]))
                    ],
                    if (widget.isApproved) ...[
                      const SizedBox(height: 10),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                              color: AppColors.online.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: AppColors.online.withOpacity(0.2))),
                          child: const Row(children: [
                            Icon(Icons.verified_rounded,
                                size: 14, color: AppColors.online),
                            SizedBox(width: 6),
                            Text('Approved by admin ✅',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.online,
                                    fontWeight: FontWeight.w500))
                          ]))
                    ],
                  ]),
            )),
      );
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _StatusChip(this.label, this.active, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: active ? color : AppColors.surfaceVar,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? color : AppColors.border)),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? Colors.white : AppColors.textMuted)),
      ));
}

class _RequestCard extends StatelessWidget {
  final ApprovalModel approval;
  const _RequestCard({required this.approval});
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
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _color.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                  color: _color.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 3))
            ]),
        child: Row(children: [
          Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: _color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.approval_rounded, color: _color, size: 20)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(approval.title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                Text(
                    '${approval.approvalType} · ${approval.approverName.isNotEmpty ? 'To: ${approval.approverName}' : ''}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
              ])),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: _color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(_label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _color))),
        ]),
      );
}

extension on LinearGradient {
  LinearGradient scale(double factor) => LinearGradient(
      colors: colors.map((c) => c.withOpacity(factor)).toList(),
      begin: begin,
      end: end);
}
