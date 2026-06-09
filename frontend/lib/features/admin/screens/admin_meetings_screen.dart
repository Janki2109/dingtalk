import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';
import '../../../shared/widgets/app_widgets.dart';
import 'admin_attendance_screen.dart';
import '../../meeting/screens/meeting_room_screen.dart';

class AdminMeetingsScreen extends StatefulWidget {
  const AdminMeetingsScreen({super.key});
  @override
  State<AdminMeetingsScreen> createState() => _AdminMeetingsScreenState();
}

class _AdminMeetingsScreenState extends State<AdminMeetingsScreen> {
  List<MeetingModel> _meetings = [];
  List<UserModel> _employees = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.getMeetings(),
        ApiService.getUsers(),
      ]);
      if (mounted)
        setState(() {
          _meetings = results[0] as List<MeetingModel>;
          _employees =
              (results[1] as List<UserModel>).where((u) => !u.isAdmin).toList();
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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

  // ── New instant meeting ───────────────────────────────────────────────────
  void _showNewMeeting() {
    final titleCtrl = TextEditingController(text: 'Team Meeting');
    bool loading = false;

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
                      const Text('New Meeting',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700)),
                      const Text(
                          'A unique code will be generated automatically',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textMuted)),
                      const SizedBox(height: 16),
                      TextField(
                          controller: titleCtrl,
                          autofocus: true,
                          decoration: const InputDecoration(
                              labelText: 'Meeting Title',
                              prefixIcon: Icon(Icons.videocam_rounded))),
                      const SizedBox(height: 20),
                      SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: loading
                                ? null
                                : () async {
                                    if (titleCtrl.text.trim().isEmpty) return;
                                    setS(() => loading = true);
                                    try {
                                      final meeting =
                                          await ApiService.createMeeting({
                                        'title': titleCtrl.text.trim(),
                                        'description': '',
                                        'start_time': DateTime.now()
                                            .toUtc()
                                            .toIso8601String(),
                                        'end_time': DateTime.now()
                                            .add(const Duration(hours: 1))
                                            .toUtc()
                                            .toIso8601String(),
                                        'participant_ids': <String>[],
                                      });
                                      if (context.mounted)
                                        Navigator.pop(context);
                                      _load();
                                      if (mounted) _showCreated(meeting);
                                    } catch (e) {
                                      setS(() => loading = false);
                                      _snack('Failed: $e', AppColors.busy);
                                    }
                                  },
                            icon: loading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.videocam_rounded),
                            label: Text(
                                loading ? 'Creating...' : 'Create & Get Code'),
                            style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14)),
                          )),
                    ]),
              )),
    );
  }

  // ── Schedule meeting ──────────────────────────────────────────────────────
  void _showSchedule() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    DateTime start = DateTime.now().add(const Duration(hours: 1));
    DateTime end = DateTime.now().add(const Duration(hours: 2));
    List<String> selectedIds = [];
    bool loading = false;

    String fmtDate(DateTime dt) {
      const mo = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      return '${mo[dt.month - 1]} ${dt.day}, ${dt.year} · '
          '$h:${dt.minute.toString().padLeft(2, '0')} ${dt.hour < 12 ? 'AM' : 'PM'}';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
          builder: (ctx, setS) => Container(
                height: MediaQuery.of(context).size.height * 0.92,
                decoration: const BoxDecoration(
                    color: AppColors.surface,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24))),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, 16, 24,
                      MediaQuery.of(context).viewInsets.bottom + 24),
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
                        Row(children: [
                          Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                  color: AppColors.purple,
                                  borderRadius: BorderRadius.circular(14)),
                              child: const Icon(Icons.calendar_month_rounded,
                                  color: Colors.white, size: 24)),
                          const SizedBox(width: 14),
                          const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Schedule Meeting',
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700)),
                                Text('Code generated automatically',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textMuted)),
                              ]),
                        ]),
                        const SizedBox(height: 20),

                        // Title
                        TextField(
                            controller: titleCtrl,
                            autofocus: true,
                            decoration: const InputDecoration(
                                labelText: 'Meeting Title *',
                                prefixIcon: Icon(Icons.event_rounded))),
                        const SizedBox(height: 12),

                        // Description
                        TextField(
                            controller: descCtrl,
                            maxLines: 2,
                            decoration: const InputDecoration(
                                labelText: 'Agenda (optional)',
                                prefixIcon: Icon(Icons.notes_rounded),
                                alignLabelWithHint: true)),
                        const SizedBox(height: 12),

                        // Start date
                        GestureDetector(
                          onTap: () async {
                            final d = await showDatePicker(
                                context: context,
                                initialDate: start,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 365)));
                            if (d == null) return;
                            final t = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(start));
                            if (t == null) return;
                            setS(() {
                              start = DateTime(
                                  d.year, d.month, d.day, t.hour, t.minute);
                              if (end.isBefore(start))
                                end = start.add(const Duration(hours: 1));
                            });
                          },
                          child:
                              _DateTile(label: 'Start', value: fmtDate(start)),
                        ),
                        const SizedBox(height: 8),

                        // End date
                        GestureDetector(
                          onTap: () async {
                            final d = await showDatePicker(
                                context: context,
                                initialDate: end,
                                firstDate: start,
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 365)));
                            if (d == null) return;
                            final t = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(end));
                            if (t == null) return;
                            setS(() => end = DateTime(
                                d.year, d.month, d.day, t.hour, t.minute));
                          },
                          child: _DateTile(label: 'End', value: fmtDate(end)),
                        ),
                        const SizedBox(height: 16),

                        // Info box
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: AppColors.purple.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: AppColors.purple.withOpacity(0.2))),
                          child: const Row(children: [
                            Icon(Icons.auto_awesome,
                                size: 16, color: AppColors.purple),
                            SizedBox(width: 8),
                            Expanded(
                                child: Text(
                                    'A unique Jitsi meeting code will be generated. '
                                    'Share it with employees so they can join.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.purple))),
                          ]),
                        ),
                        const SizedBox(height: 16),

                        // Employees
                        const Text('Invite Employees',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        ..._employees.map((e) => GestureDetector(
                              onTap: () => setS(() {
                                if (selectedIds.contains(e.id))
                                  selectedIds.remove(e.id);
                                else
                                  selectedIds.add(e.id);
                              }),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: selectedIds.contains(e.id)
                                        ? AppColors.primary.withOpacity(0.1)
                                        : AppColors.surfaceVar,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: selectedIds.contains(e.id)
                                            ? AppColors.primary
                                            : AppColors.border)),
                                child: Row(children: [
                                  UserAvatar(
                                      name: e.name, size: 36, status: e.status),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(e.name,
                                            style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600)),
                                        Text(e.role,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textMuted)),
                                      ])),
                                  if (selectedIds.contains(e.id))
                                    const Icon(Icons.check_circle,
                                        color: AppColors.primary, size: 20),
                                ]),
                              ),
                            )),
                        const SizedBox(height: 20),

                        // Schedule button
                        SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: loading
                                  ? null
                                  : () async {
                                      if (titleCtrl.text.trim().isEmpty) {
                                        _snack('Please enter a meeting title',
                                            AppColors.busy);
                                        return;
                                      }
                                      setS(() => loading = true);
                                      try {
                                        final meeting =
                                            await ApiService.createMeeting({
                                          'title': titleCtrl.text.trim(),
                                          'description': descCtrl.text.trim(),
                                          'start_time':
                                              start.toUtc().toIso8601String(),
                                          'end_time':
                                              end.toUtc().toIso8601String(),
                                          'participant_ids': selectedIds,
                                        });
                                        if (context.mounted)
                                          Navigator.pop(context);
                                        _load();
                                        _snack(
                                            '✅ Scheduled! Code: ${meeting.code}',
                                            AppColors.online);
                                        if (mounted) _showCreated(meeting);
                                      } catch (e) {
                                        setS(() => loading = false);
                                        _snack('Failed: $e', AppColors.busy);
                                      }
                                    },
                              icon: loading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.calendar_month_rounded),
                              label: Text(loading
                                  ? 'Scheduling...'
                                  : 'Schedule & Get Code'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.purple,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14)),
                            )),
                        const SizedBox(height: 20),
                      ]),
                ),
              )),
    );
  }

  // ── Meeting created popup ─────────────────────────────────────────────────
  void _showCreated(MeetingModel meeting) {
    final user = context.read<AuthProvider>().user;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        bool codeCopied = false;
        return StatefulBuilder(
            builder: (ctx, setS) => Container(
                  decoration: const BoxDecoration(
                      color: AppColors.surface,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(24))),
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Center(
                        child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                                color: AppColors.border,
                                borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: AppColors.online.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppColors.online.withOpacity(0.25))),
                      child: const Row(children: [
                        Icon(Icons.check_circle_rounded,
                            color: AppColors.online, size: 26),
                        SizedBox(width: 10),
                        Text('Meeting Created! ✅',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.online)),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    const Text('MEETING CODE',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                            letterSpacing: 1.5)),
                    const SizedBox(height: 10),
                    Consumer<AuthProvider>(
                        builder: (_, auth, __) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 16),
                              decoration: BoxDecoration(
                                  color: auth.themeColor.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color:
                                          auth.themeColor.withOpacity(0.25))),
                              child: Row(children: [
                                Expanded(
                                    child: Text(meeting.code,
                                        style: TextStyle(
                                            fontSize: 32,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 8,
                                            color: auth.themeColor),
                                        textAlign: TextAlign.center)),
                                GestureDetector(
                                  onTap: () {
                                    Clipboard.setData(
                                        ClipboardData(text: meeting.code));
                                    setS(() => codeCopied = true);
                                    Future.delayed(const Duration(seconds: 2),
                                        () {
                                      if (ctx.mounted)
                                        setS(() => codeCopied = false);
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                        color: codeCopied
                                            ? AppColors.online
                                            : auth.themeColor,
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    child: Text(codeCopied ? 'Copied!' : 'Copy',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ),
                              ]),
                            )),
                    const SizedBox(height: 8),
                    const Text(
                        'Share this code — employees go to Meetings → Join with Code',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.textMuted),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                          child: OutlinedButton.icon(
                        onPressed: () {
                          final jitsiLink =
                              'https://meet.jit.si/WorkspacePro-${meeting.code}';
                          final msg = '📹 Meeting Invite\n'
                              '━━━━━━━━━━━━━━━━━\n'
                              'Title: ${meeting.title}\n'
                              'Code:  ${meeting.code}\n'
                              'Link:  $jitsiLink\n'
                              '━━━━━━━━━━━━━━━━━\n'
                              'Go to Meetings → Join with Code → ${meeting.code}';
                          Clipboard.setData(ClipboardData(text: msg));
                          _snack('✅ Invite copied! Paste in chat.',
                              AppColors.online);
                        },
                        icon: const Icon(Icons.copy_all_rounded, size: 16),
                        label: const Text('Copy Invite'),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12)),
                      )),
                      const SizedBox(width: 10),
                      Expanded(
                          child: OutlinedButton.icon(
                        onPressed: () async {
                          if (context.mounted) Navigator.pop(context);
                          final chats = await ApiService.getChats();
                          if (!mounted || chats.isEmpty) return;
                          _showShareInChat(meeting, chats);
                        },
                        icon: const Icon(Icons.chat_bubble_outline_rounded,
                            size: 16),
                        label: const Text('Share in Chat'),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12)),
                      )),
                    ]),
                    const SizedBox(height: 12),
                    SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => MeetingRoomScreen(
                                          meetingId: meeting.id,
                                          meetingCode: meeting.code,
                                          inviteLink:
                                              'https://meet.jit.si/WorkspacePro-${meeting.code}',
                                          isHost: true,
                                          meetingTitle: meeting.title,
                                          userName: user?.name ?? 'Admin',
                                        )));
                          },
                          icon: const Icon(Icons.videocam_rounded),
                          label: const Text('Start Meeting Now',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14)),
                        )),
                  ]),
                ));
      },
    );
  }

  // ── Share in chat ─────────────────────────────────────────────────────────
  void _showShareInChat(MeetingModel meeting, List<ChatModel> chats) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(children: [
                const Expanded(
                    child: Text('Share in Chat',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700))),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ])),
          Expanded(
              child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: chats.length,
            itemBuilder: (ctx, i) {
              final chat = chats[i];
              return ListTile(
                leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        shape: BoxShape.circle),
                    child: Icon(
                        chat.isGroup
                            ? Icons.group_rounded
                            : Icons.person_rounded,
                        color: AppColors.primary,
                        size: 20)),
                title: Text(chat.name.isEmpty ? 'Chat' : chat.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                trailing: const Icon(Icons.send_rounded,
                    color: AppColors.primary, size: 18),
                onTap: () async {
                  Navigator.pop(context);
                  final jitsiLink =
                      'https://meet.jit.si/WorkspacePro-${meeting.code}';
                  final msg = '📹 Meeting Invite\n'
                      '━━━━━━━━━━━━━━━━━\n'
                      'Title: ${meeting.title}\n'
                      'Code:  ${meeting.code}\n'
                      'Link:  $jitsiLink\n'
                      '━━━━━━━━━━━━━━━━━\n'
                      'Meetings → Join with Code → ${meeting.code}';
                  try {
                    await ApiService.sendMessage(chat.id, msg);
                    _snack('✅ Invite sent to ${chat.name}!', AppColors.online);
                  } catch (e) {
                    _snack('Failed: $e', AppColors.busy);
                  }
                },
              );
            },
          )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Meetings',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(children: [
        // Quick action buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            Expanded(
                child: _QuickBtn(
                    icon: Icons.videocam_rounded,
                    label: 'New\nMeeting',
                    color: themeColor,
                    onTap: _showNewMeeting)),
            const SizedBox(width: 10),
            Expanded(
                child: _QuickBtn(
                    icon: Icons.login_rounded,
                    label: 'Join with\nCode',
                    color: AppColors.accent,
                    onTap: _showJoinDialog)),
            const SizedBox(width: 10),
            Expanded(
                child: _QuickBtn(
                    icon: Icons.calendar_month_rounded,
                    label: 'Schedule\nMeeting',
                    color: AppColors.purple,
                    onTap: _showSchedule)),
          ]),
        ),
        const SizedBox(height: 12),

        // Meeting list
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _meetings.isEmpty
                  ? Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          Icon(Icons.videocam_off_outlined,
                              size: 64,
                              color: AppColors.textMuted.withOpacity(0.3)),
                          const SizedBox(height: 16),
                          const Text('No meetings yet',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary)),
                          const SizedBox(height: 8),
                          const Text(
                              'Tap New Meeting or Schedule to create one',
                              style: TextStyle(color: AppColors.textMuted)),
                        ]))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _meetings.length,
                      itemBuilder: (ctx, i) {
                        final m = _meetings[i];
                        final isHost = m.organizerId == user?.id;
                        final isLive = m.status == 'ongoing';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: isLive
                                      ? AppColors.online.withOpacity(0.4)
                                      : AppColors.border)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                          color: themeColor.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      child: Icon(Icons.videocam_rounded,
                                          color: themeColor, size: 22)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(m.title,
                                            style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700)),
                                        Text(
                                            '${m.startTime.day}/${m.startTime.month}/${m.startTime.year} · ${m.organizer}',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textMuted)),
                                      ])),
                                  Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                          color: themeColor.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(20)),
                                      child: Text(m.status.toUpperCase(),
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: themeColor))),
                                ]),

                                // Code
                                if (m.code.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                        color: themeColor.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color:
                                                themeColor.withOpacity(0.15))),
                                    child: Row(children: [
                                      Icon(Icons.tag_rounded,
                                          size: 14, color: themeColor),
                                      const SizedBox(width: 8),
                                      Text('Code',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: themeColor,
                                              fontWeight: FontWeight.w600)),
                                      const Spacer(),
                                      Text(m.code,
                                          style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 3,
                                              color: themeColor)),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () {
                                          Clipboard.setData(
                                              ClipboardData(text: m.code));
                                          _snack('Code ${m.code} copied!',
                                              themeColor);
                                        },
                                        child: Icon(Icons.copy_rounded,
                                            size: 16, color: themeColor),
                                      ),
                                    ]),
                                  ),
                                ],
                                const SizedBox(height: 12),

                                // Buttons
                                Row(children: [
                                  if (m.code.isNotEmpty)
                                    Expanded(
                                        child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final chats =
                                            await ApiService.getChats();
                                        if (mounted) _showShareInChat(m, chats);
                                      },
                                      icon: const Icon(Icons.share_rounded,
                                          size: 14),
                                      label: const Text('Share',
                                          style: TextStyle(fontSize: 13)),
                                      style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 8)),
                                    )),
                                  if (m.code.isNotEmpty)
                                    const SizedBox(width: 8),
                                  Expanded(
                                      child: ElevatedButton.icon(
                                    onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => MeetingRoomScreen(
                                                  meetingId: m.id,
                                                  meetingCode: m.code,
                                                  inviteLink:
                                                      'https://meet.jit.si/WorkspacePro-${m.code}',
                                                  isHost: isHost,
                                                  meetingTitle: m.title,
                                                  userName:
                                                      user?.name ?? 'Admin',
                                                ))),
                                    icon: Icon(
                                        isHost
                                            ? Icons.videocam_rounded
                                            : Icons.login_rounded,
                                        size: 14),
                                    label: Text(
                                        isHost
                                            ? (isLive ? 'Rejoin' : 'Start')
                                            : 'Join',
                                        style: const TextStyle(fontSize: 13)),
                                    style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8)),
                                  )),
                                ]),
                              ]),
                        );
                      }),
        ),
      ]),
    );
  }

  void _showJoinDialog() {
    final codeCtrl = TextEditingController();
    bool loading = false;
    String error = '';
    final user = context.read<AuthProvider>().user;

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
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Center(
                      child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: AppColors.border,
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 20),
                  const Text('Join a Meeting',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 6),
                    decoration: InputDecoration(
                        labelText: 'Meeting Code',
                        hintText: 'e.g. DGMSFX',
                        prefixIcon: const Icon(Icons.meeting_room_rounded),
                        errorText: error.isNotEmpty ? error : null),
                    onSubmitted: (_) async {
                      final code = codeCtrl.text.trim().toUpperCase();
                      if (code.length < 4) {
                        setS(() => error = 'Enter the code');
                        return;
                      }
                      setS(() {
                        loading = true;
                        error = '';
                      });
                      try {
                        final meeting = await ApiService.getMeetingByCode(code);
                        if (context.mounted) Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => MeetingRoomScreen(
                                      meetingId: meeting.id,
                                      meetingCode: meeting.code,
                                      inviteLink:
                                          'https://meet.jit.si/WorkspacePro-${meeting.code}',
                                      isHost: meeting.organizerId == user?.id,
                                      meetingTitle: meeting.title,
                                      userName: user?.name ?? 'Admin',
                                    )));
                      } catch (e) {
                        setS(() {
                          loading = false;
                          error = 'Meeting not found';
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: loading
                            ? null
                            : () async {
                                final code = codeCtrl.text.trim().toUpperCase();
                                if (code.length < 4) {
                                  setS(() => error = 'Enter the code');
                                  return;
                                }
                                setS(() {
                                  loading = true;
                                  error = '';
                                });
                                try {
                                  final meeting =
                                      await ApiService.getMeetingByCode(code);
                                  if (context.mounted) Navigator.pop(context);
                                  Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => MeetingRoomScreen(
                                                meetingId: meeting.id,
                                                meetingCode: meeting.code,
                                                inviteLink:
                                                    'https://meet.jit.si/WorkspacePro-${meeting.code}',
                                                isHost: meeting.organizerId ==
                                                    user?.id,
                                                meetingTitle: meeting.title,
                                                userName: user?.name ?? 'Admin',
                                              )));
                                } catch (e) {
                                  setS(() {
                                    loading = false;
                                    error = 'Meeting not found';
                                  });
                                }
                              },
                        icon: loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.login_rounded),
                        label: Text(loading ? 'Looking up...' : 'Join Meeting'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                      )),
                ]),
              )),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────
class _QuickBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.2))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 22)),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color),
                textAlign: TextAlign.center),
          ]),
        ),
      );
}

class _DateTile extends StatelessWidget {
  final String label, value;
  const _DateTile({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
            color: AppColors.surfaceVar,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border)),
        child: Row(children: [
          const Icon(Icons.calendar_today_rounded,
              size: 16, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ])),
          const Icon(Icons.edit_calendar_rounded,
              size: 16, color: AppColors.textMuted),
        ]),
      );
}
