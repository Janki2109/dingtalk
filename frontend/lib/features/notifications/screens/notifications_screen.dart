import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../meeting/screens/agora_meeting_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationModel> _notifs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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
            body: 'Alex Morgan assigned "Write release notes" to you',
            type: 'task',
            createdAt: DateTime.now().subtract(const Duration(hours: 1))),
        NotificationModel(
            id: 'n4',
            userId: 'me',
            title: 'Leave request approved',
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
            title: 'Company announcement',
            body: 'Q3 results are out — we hit 127% of target!',
            type: 'system',
            isRead: true,
            createdAt: DateTime.now().subtract(const Duration(days: 1))),
      ];

  IconData _icon(String t) {
    switch (t) {
      case 'meeting':
        return Icons.videocam_outlined;
      case 'message':
        return Icons.chat_bubble_outline;
      case 'task':
        return Icons.task_alt;
      case 'approval':
        return Icons.check_circle_outline;
      case 'attendance':
        return Icons.access_time;
      default:
        return Icons.notifications_outlined;
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
          final uid = meeting.code.hashCode.abs() & 0x7FFFFFFF;
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AgoraMeetingScreen(
                        channelName: meeting.code,
                        meetingTitle: meeting.title,
                        meetingId: meeting.id,
                        isHost: meeting.organizerId == user?.id,
                        uid: uid == 0 ? 1 : uid,
                      )));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifs.where((n) => !n.isRead).toList();
    final read = _notifs.where((n) => n.isRead).toList();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          floating: true,
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          title: Row(children: [
            const Text('Notifications',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
            if (unread.isNotEmpty) ...[
              const SizedBox(width: 8),
              UnreadBadge(count: unread.length)
            ],
          ]),
          actions: [
            TextButton(
                onPressed: _markAllRead,
                child: const Text('Mark all read',
                    style: TextStyle(fontSize: 13))),
            IconButton(
                icon: const Icon(Icons.refresh, size: 20), onPressed: _load),
          ],
        ),
        if (_loading)
          const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()))
        else ...[
          if (unread.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader(title: 'New')),
            SliverList(
                delegate: SliverChildBuilderDelegate(
              (ctx, i) => _NotifTile(
                  notif: unread[i],
                  icon: _icon(unread[i].type),
                  color: _color(unread[i].type),
                  onMarkRead: () => _markRead(unread[i].id),
                  onJoinMeeting: _joinMeeting),
              childCount: unread.length,
            )),
          ],
          if (read.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader(title: 'Earlier')),
            SliverList(
                delegate: SliverChildBuilderDelegate(
              (ctx, i) => _NotifTile(
                  notif: read[i],
                  icon: _icon(read[i].type),
                  color: _color(read[i].type),
                  onMarkRead: () => _markRead(read[i].id),
                  onJoinMeeting: _joinMeeting),
              childCount: read.length,
            )),
          ],
          if (_notifs.isEmpty)
            const SliverFillRemaining(
                child: EmptyState(
                    icon: Icons.notifications_off_outlined,
                    title: 'All caught up!',
                    subtitle: 'No new notifications')),
          const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ],
      ]),
    );
  }
}

class _NotifTile extends StatelessWidget {
  final NotificationModel notif;
  final IconData icon;
  final Color color;
  final VoidCallback onMarkRead;
  final Function(String) onJoinMeeting;

  const _NotifTile(
      {required this.notif,
      required this.icon,
      required this.color,
      required this.onMarkRead,
      required this.onJoinMeeting});

  @override
  Widget build(BuildContext context) {
    final code = notif.meetingCode;
    final isMeetingWithCode = notif.type == 'meeting' && code != null;
    return GestureDetector(
      onTap: notif.isRead ? null : onMarkRead,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notif.isRead
              ? AppColors.surface
              : AppColors.primaryLight.withOpacity(0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: notif.isRead
                  ? AppColors.border
                  : AppColors.primary.withOpacity(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 20)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Expanded(
                        child: Text(notif.title,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: notif.isRead
                                    ? FontWeight.w500
                                    : FontWeight.w700))),
                    if (!notif.isRead)
                      Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle)),
                  ]),
                  const SizedBox(height: 3),
                  Text(notif.body,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(formatTime(notif.createdAt),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted)),
                ])),
          ]),
          if (isMeetingWithCode) ...[
            const SizedBox(height: 10),
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withOpacity(0.2))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.tag_rounded, size: 12, color: color),
                  const SizedBox(width: 4),
                  Text(code,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: color)),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: ElevatedButton.icon(
                onPressed: () => onJoinMeeting(code),
                icon: const Icon(Icons.videocam_rounded, size: 15),
                label:
                    const Text('Join Meeting', style: TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
              )),
            ]),
          ],
        ]),
      ),
    );
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AppColors.busy),
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
