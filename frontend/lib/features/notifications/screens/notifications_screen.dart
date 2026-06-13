import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../meeting/screens/meeting_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  List<NotificationModel> _notifs = [];
  bool _loading = true;
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _load();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final n = await ApiService.getNotifications();
      if (mounted)
        setState(() {
          _notifs = n;
          _loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _notifs = _demo();
          _loading = false;
        });
    }
    _anim.forward(from: 0);
  }

  List<NotificationModel> _demo() => [
        NotificationModel(
            id: 'n1',
            userId: 'me',
            title: 'Sprint Planning starting soon',
            body: 'Alex Morgan invited you · Code: ABC123',
            type: 'meeting',
            createdAt: DateTime.now().subtract(const Duration(minutes: 5))),
        NotificationModel(
            id: 'n2',
            userId: 'me',
            title: 'New message from Sarah Chen',
            body: 'The API is ready for testing',
            type: 'message',
            createdAt: DateTime.now().subtract(const Duration(minutes: 30))),
        NotificationModel(
            id: 'n3',
            userId: 'me',
            title: 'Task assigned to you',
            body: 'Alex assigned "Write release notes" to you',
            type: 'task',
            createdAt: DateTime.now().subtract(const Duration(hours: 1))),
        NotificationModel(
            id: 'n4',
            userId: 'me',
            title: 'Leave request approved ✅',
            body: 'Your leave for Dec 25-26 has been approved',
            type: 'approval',
            isRead: true,
            createdAt: DateTime.now().subtract(const Duration(hours: 2))),
        NotificationModel(
            id: 'n5',
            userId: 'me',
            title: 'Check-in reminder',
            body: "Don't forget to check in today!",
            type: 'attendance',
            isRead: true,
            createdAt: DateTime.now().subtract(const Duration(hours: 3))),
        NotificationModel(
            id: 'n6',
            userId: 'me',
            title: 'Company announcement 🎉',
            body: 'Q3 results are out — we hit 127% of target!',
            type: 'system',
            isRead: true,
            createdAt: DateTime.now().subtract(const Duration(days: 1))),
      ];

  IconData _icon(String t) {
    switch (t) {
      case 'meeting':
        return Icons.videocam_rounded;
      case 'message':
        return Icons.chat_bubble_rounded;
      case 'task':
        return Icons.task_alt_rounded;
      case 'approval':
        return Icons.check_circle_rounded;
      case 'attendance':
        return Icons.access_time_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  LinearGradient _gradient(String t) {
    switch (t) {
      case 'meeting':
        return AppColors.primaryGrad;
      case 'message':
        return AppColors.accentGrad;
      case 'task':
        return AppColors.orangeGrad;
      case 'approval':
        return AppColors.emeraldGrad;
      case 'attendance':
        return const LinearGradient(
            colors: [AppColors.away, Color(0xFFD97706)]);
      default:
        return AppColors.purpleGrad;
    }
  }

  Color _color(String t) {
    switch (t) {
      case 'meeting':
        return AppColors.primary;
      case 'message':
        return AppColors.accent;
      case 'task':
        return AppColors.orange;
      case 'approval':
        return AppColors.online;
      case 'attendance':
        return AppColors.away;
      default:
        return AppColors.purple;
    }
  }

  Future<void> _markRead(String id) async {
    try {
      await ApiService.markNotificationRead(id);
    } catch (_) {}
    setState(() => _notifs = _notifs
        .map((n) => n.id == id
            ? NotificationModel(
                id: n.id,
                userId: n.userId,
                title: n.title,
                body: n.body,
                type: n.type,
                isRead: true,
                actionId: n.actionId,
                createdAt: n.createdAt)
            : n)
        .toList());
  }

  Future<void> _markAllRead() async {
    try {
      await ApiService.markAllNotificationsRead();
    } catch (_) {}
    setState(() => _notifs = _notifs
        .map((n) => NotificationModel(
            id: n.id,
            userId: n.userId,
            title: n.title,
            body: n.body,
            type: n.type,
            isRead: true,
            actionId: n.actionId,
            createdAt: n.createdAt))
        .toList());
  }

  void _joinMeeting(String code) {
    final user = context.read<AuthProvider>().user;
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _QuickJoinSheet(
            code: code,
            onJoin: (meeting) {
              Navigator.pop(context);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => WebRTCMeetingScreen(
                          meetingCode: meeting.code,
                          meetingTitle: meeting.title,
                          meetingId: meeting.id,
                          isHost: meeting.organizerId == user?.id)));
            }));
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;
    final unread = _notifs.where((n) => !n.isRead).toList();
    final read = _notifs.where((n) => n.isRead).toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 120,
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
                    top: -30,
                    right: -30,
                    child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.07)))),
                Padding(
                    padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(children: [
                            const Text('Notifications',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800)),
                            if (unread.isNotEmpty) ...[
                              const SizedBox(width: 10),
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.25),
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Text('${unread.length} new',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700))),
                            ],
                          ]),
                        ])),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: _markAllRead,
                child: const Text('Mark all read',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600))),
            IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                onPressed: _load),
          ],
        ),
        if (_loading)
          const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()))
        else if (_notifs.isEmpty)
          SliverFillRemaining(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                        gradient: AppColors.primaryGrad,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.primary.withOpacity(0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 8))
                        ]),
                    child: const Icon(Icons.notifications_off_rounded,
                        size: 40, color: Colors.white)),
                const SizedBox(height: 16),
                const Text('All caught up!',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                const Text('No new notifications',
                    style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
              ]))
        else ...[
          if (unread.isNotEmpty) ...[
            SliverToBoxAdapter(
                child: _Label('🔔 New', unread.length, AppColors.primary)),
            SliverList(
                delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _NotifTile(
                        notif: unread[i],
                        icon: _icon(unread[i].type),
                        color: _color(unread[i].type),
                        gradient: _gradient(unread[i].type),
                        onMarkRead: () => _markRead(unread[i].id),
                        onJoinMeeting: _joinMeeting,
                        index: i),
                    childCount: unread.length)),
          ],
          if (read.isNotEmpty) ...[
            SliverToBoxAdapter(
                child: _Label('Earlier', read.length, AppColors.textMuted)),
            SliverList(
                delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _NotifTile(
                        notif: read[i],
                        icon: _icon(read[i].type),
                        color: _color(read[i].type),
                        gradient: _gradient(read[i].type),
                        onMarkRead: () => _markRead(read[i].id),
                        onJoinMeeting: _joinMeeting,
                        index: i + unread.length),
                    childCount: read.length)),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ]),
    );
  }
}

class _Label extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  const _Label(this.title, this.count, this.color);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(children: [
        Text(title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted)),
        const SizedBox(width: 6),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Text('$count',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: color))),
      ]));
}

class _NotifTile extends StatefulWidget {
  final NotificationModel notif;
  final IconData icon;
  final Color color;
  final LinearGradient gradient;
  final VoidCallback onMarkRead;
  final Function(String) onJoinMeeting;
  final int index;
  const _NotifTile(
      {required this.notif,
      required this.icon,
      required this.color,
      required this.gradient,
      required this.onMarkRead,
      required this.onJoinMeeting,
      required this.index});
  @override
  State<_NotifTile> createState() => _NotifTileState();
}

class _NotifTileState extends State<_NotifTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<Offset> _slide;
  late Animation<double> _fade;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: Duration(milliseconds: 400 + widget.index * 60));
    _slide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    Future.delayed(Duration(milliseconds: widget.index * 50), () {
      if (mounted) _anim.forward();
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.notif.meetingCode;
    final isMeeting = widget.notif.type == 'meeting' && code != null;
    return SlideTransition(
        position: _slide,
        child: FadeTransition(
            opacity: _fade,
            child: GestureDetector(
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) {
                setState(() => _pressed = false);
                if (!widget.notif.isRead) widget.onMarkRead();
              },
              onTapCancel: () => setState(() => _pressed = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _pressed
                      ? widget.color.withOpacity(0.04)
                      : widget.notif.isRead
                          ? AppColors.surface
                          : widget.color.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: widget.notif.isRead
                          ? AppColors.border
                          : widget.color.withOpacity(0.25),
                      width: widget.notif.isRead ? 1 : 1.5),
                  boxShadow: widget.notif.isRead
                      ? []
                      : [
                          BoxShadow(
                              color: widget.color.withOpacity(0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4))
                        ],
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                    gradient: widget.gradient,
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                          color: widget.color.withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3))
                                    ]),
                                child: Icon(widget.icon,
                                    color: Colors.white, size: 22)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Row(children: [
                                    Expanded(
                                        child: Text(widget.notif.title,
                                            style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: widget.notif.isRead
                                                    ? FontWeight.w500
                                                    : FontWeight.w700))),
                                    if (!widget.notif.isRead)
                                      Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                              gradient: AppColors.primaryGrad,
                                              shape: BoxShape.circle)),
                                  ]),
                                  const SizedBox(height: 3),
                                  Text(widget.notif.body,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.textSecondary,
                                          height: 1.4),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 5),
                                  Row(children: [
                                    Icon(Icons.access_time_rounded,
                                        size: 11, color: AppColors.textMuted),
                                    const SizedBox(width: 3),
                                    Text(formatTime(widget.notif.createdAt),
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textMuted)),
                                  ]),
                                ])),
                          ]),
                      if (isMeeting) ...[
                        const SizedBox(height: 12),
                        Row(children: [
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                  color: widget.color.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: widget.color.withOpacity(0.2))),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.tag_rounded,
                                        size: 13, color: widget.color),
                                    const SizedBox(width: 4),
                                    Text(code,
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 3,
                                            color: widget.color)),
                                  ])),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Container(
                                  height: 38,
                                  decoration: BoxDecoration(
                                      gradient: widget.gradient,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                            color:
                                                widget.color.withOpacity(0.3),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4))
                                      ]),
                                  child: ElevatedButton.icon(
                                      onPressed: () =>
                                          widget.onJoinMeeting(code),
                                      icon: const Icon(Icons.videocam_rounded,
                                          size: 15, color: Colors.white),
                                      label: const Text('Join Now',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white)),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          shadowColor: Colors.transparent,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      12)))))),
                        ]),
                      ],
                    ]),
              ),
            )));
  }
}

class _QuickJoinSheet extends StatefulWidget {
  final String code;
  final Function(MeetingModel) onJoin;
  const _QuickJoinSheet({required this.code, required this.onJoin});
  @override
  State<_QuickJoinSheet> createState() => _QuickJoinSheetState();
}

class _QuickJoinSheetState extends State<_QuickJoinSheet> {
  bool _loading = false;
  String _error = '';
  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final meeting = await ApiService.getMeetingByCode(widget.code);
      widget.onJoin(meeting);
    } catch (e) {
      final msg = e.toString();
      if (mounted)
        setState(() {
          _loading = false;
          _error = msg.contains('not found') || msg.contains('404')
              ? 'Meeting not found. It may have ended.'
              : 'Could not join. Check your connection.';
        });
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          if (_loading) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Joining meeting ${widget.code}...',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ] else if (_error.isNotEmpty) ...[
            Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                    color: AppColors.busy.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.error_outline_rounded,
                    size: 32, color: AppColors.busy)),
            const SizedBox(height: 12),
            Text(_error,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: AppColors.busy)),
            const SizedBox(height: 16),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'))),
          ],
        ]),
      );
}
