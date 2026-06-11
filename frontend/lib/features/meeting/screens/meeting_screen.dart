import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';

// ══════════════════════════════════════════════════════════════════════════════
// WEBRTC MEETING SCREEN — uses Jitsi for real video calls
// ══════════════════════════════════════════════════════════════════════════════

class WebRTCMeetingScreen extends StatefulWidget {
  final String meetingCode;
  final String meetingTitle;
  final bool isHost;

  const WebRTCMeetingScreen({
    super.key,
    required this.meetingCode,
    required this.meetingTitle,
    required this.isHost,
  });

  @override
  State<WebRTCMeetingScreen> createState() => _WebRTCMeetingScreenState();
}

class _WebRTCMeetingScreenState extends State<WebRTCMeetingScreen> {
  final _jitsi = JitsiMeet();
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _joinMeeting());
  }

  Future<void> _joinMeeting() async {
    if (_joining) return;
    setState(() => _joining = true);

    final auth = context.read<AuthProvider>();
    final userName = auth.user?.name ?? 'Guest';
    final userEmail = auth.user?.email ?? '';

    // Room name = WorkspacePro-CODE (same for everyone with same code)
    final roomName = 'WorkspacePro-${widget.meetingCode}';

    final options = JitsiMeetConferenceOptions(
      serverURL: 'https://meet.jit.si',
      room: roomName,
      configOverrides: {
        'startWithAudioMuted': false,
        'startWithVideoMuted': false,
        'prejoinPageEnabled': false,
        'disableDeepLinking': true,
        'subject': widget.meetingTitle,
      },
      featureFlags: {
        'welcomepage.enabled': false,
        'pip.enabled': true,
        'chat.enabled': true,
        'invite.enabled': false,
        'kick-out.enabled': widget.isHost,
        'meeting-name.enabled': true,
        'notifications.enabled': true,
        'raise-hand.enabled': true,
        'recording.enabled': false,
        'live-streaming.enabled': false,
        'video-share.enabled': false,
        'android.screensharing.enabled': true,
      },
      userInfo: JitsiMeetUserInfo(
        displayName: userName,
        email: userEmail,
      ),
    );

    _jitsi.addListener(JitsiMeetEventListener(
      conferenceJoined: (url) => debugPrint('Joined: $url'),
      conferenceTerminated: (url, error) {
        debugPrint('Left: $url, error: $error');
        if (mounted) Navigator.pop(context);
      },
      conferenceWillJoin: (url) => debugPrint('Joining: $url'),
    ));

    try {
      await _jitsi.join(options);
    } catch (e) {
      debugPrint('Jitsi error: $e');
      if (mounted) {
        _snack('Could not join meeting: $e', AppColors.busy);
        Navigator.pop(context);
      }
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  void dispose() {
    _jitsi.hangUp();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(color: Colors.white),
        const SizedBox(height: 24),
        Text(widget.meetingTitle,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('Opening meeting…', style: TextStyle(color: Colors.white54)),
        const SizedBox(height: 40),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
        ),
      ])),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MEETING SCREEN (main tab)
// ══════════════════════════════════════════════════════════════════════════════

class MeetingScreen extends StatefulWidget {
  const MeetingScreen({super.key});
  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  List<MeetingModel> _meetings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final m = await ApiService.getMeetings();
      if (mounted)
        setState(() {
          _meetings = m;
          _loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _meetings = [];
          _loading = false;
        });
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

  void _openRoom(MeetingModel meeting, UserModel? user,
      {required bool isHost}) {
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WebRTCMeetingScreen(
            meetingCode: meeting.code,
            meetingTitle: meeting.title,
            isHost: isHost,
          ),
        ));
  }

  void _openRoomByCode(String code) {
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WebRTCMeetingScreen(
            meetingCode: code,
            meetingTitle: 'Meeting',
            isHost: false,
          ),
        ));
  }

  void _showNewMeeting(UserModel? user) {
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
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 20),
                  Row(children: [
                    Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                            color: context.read<AuthProvider>().themeColor,
                            borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.videocam_rounded,
                            color: Colors.white, size: 26)),
                    const SizedBox(width: 14),
                    const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('New Meeting',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                          Text('Code generated automatically',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textMuted)),
                        ]),
                  ]),
                  const SizedBox(height: 20),
                  TextField(
                      controller: titleCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                          labelText: 'Meeting Title',
                          prefixIcon: Icon(Icons.title_rounded))),
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
                                  if (context.mounted) Navigator.pop(context);
                                  _load();
                                  if (mounted) _showCreated(meeting, user);
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
                            : const Icon(Icons.add_rounded),
                        label: Text(loading ? 'Creating...' : 'Create Meeting'),
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                      )),
                ]),
              )),
    );
  }

  void _showJoinWithCode(UserModel? user) {
    final codeCtrl = TextEditingController();
    String error = '';
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
                  Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 20),
                  const Row(children: [
                    Icon(Icons.login_rounded,
                        size: 28, color: AppColors.accent),
                    SizedBox(width: 12),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Join Meeting',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                          Text('Enter the code from the host',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textMuted)),
                        ]),
                  ]),
                  const SizedBox(height: 20),
                  TextField(
                    controller: codeCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8),
                    decoration: InputDecoration(
                        hintText: 'ABC123',
                        errorText: error.isNotEmpty ? error : null,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12))),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final code = codeCtrl.text.trim().toUpperCase();
                          if (code.isEmpty) {
                            setS(() => error = 'Enter the code');
                            return;
                          }
                          if (context.mounted) Navigator.pop(context);
                          _openRoomByCode(code);
                        },
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Join Meeting'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                      )),
                ]),
              )),
    );
  }

  void _showCreated(MeetingModel meeting, UserModel? user) {
    bool codeCopied = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) {
        final themeColor = ctx.watch<AuthProvider>().themeColor;
        return Container(
          decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: AppColors.online.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: AppColors.online.withOpacity(0.3))),
                child: const Row(children: [
                  Icon(Icons.check_circle_rounded,
                      color: AppColors.online, size: 24),
                  SizedBox(width: 10),
                  Text('Meeting Created! ✅',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.online)),
                ])),
            const SizedBox(height: 20),
            const Text('MEETING CODE',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                    letterSpacing: 1.5)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                  color: themeColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: themeColor.withOpacity(0.3))),
              child: Row(children: [
                Expanded(
                    child: Text(meeting.code,
                        style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 10,
                            color: themeColor),
                        textAlign: TextAlign.center)),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: meeting.code));
                    setS(() => codeCopied = true);
                    Future.delayed(const Duration(seconds: 2), () {
                      if (ctx.mounted) setS(() => codeCopied = false);
                    });
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: codeCopied ? AppColors.online : themeColor,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(codeCopied ? '✅ Copied' : 'Copy',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            const Text('Share this code with employees to let them join',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                final chats = await ApiService.getChats();
                if (!mounted) return;
                if (context.mounted) Navigator.pop(context);
                if (mounted) _showShareInChat(meeting, chats);
              },
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Send Invite to Employee Chat',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                final msg =
                    '📹 Meeting Invite\nTitle: ${meeting.title}\nCode: ${meeting.code}\n\nOpen WorkSpace Pro → Meetings → Join with Code → ${meeting.code}';
                Clipboard.setData(ClipboardData(text: msg));
                _snack('✅ Invite copied!', AppColors.online);
              },
              icon: const Icon(Icons.copy_all_rounded, size: 16),
              label: const Text('Copy Invite Text',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48)),
            ),
            const SizedBox(height: 12),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _openRoom(meeting, user, isHost: true);
                  },
                  icon: const Icon(Icons.videocam_rounded, size: 22),
                  label: const Text('Start Meeting Now',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppColors.online),
                )),
          ]),
        );
      }),
    );
  }

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
                    child: Text('Send Invite to Chat',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700))),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ])),
          Expanded(
              child: chats.isEmpty
                  ? const Center(child: Text('No chats available'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: chats.length,
                      itemBuilder: (ctx, i) {
                        final chat = chats[i];
                        return ListTile(
                          leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  shape: BoxShape.circle),
                              child: Icon(
                                  chat.isGroup
                                      ? Icons.group_rounded
                                      : Icons.person_rounded,
                                  color: AppColors.primary,
                                  size: 22)),
                          title: Text(chat.name.isEmpty ? 'Chat' : chat.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                          trailing: const Icon(Icons.send_rounded,
                              color: AppColors.primary),
                          onTap: () async {
                            Navigator.pop(context);
                            final msg =
                                '📹 Meeting Invite\n━━━━━━━━━━━━━━━━━\nTitle: ${meeting.title}\nCode: ${meeting.code}\n━━━━━━━━━━━━━━━━━\nOpen WorkSpace Pro → Meetings → Join with Code → ${meeting.code}';
                            try {
                              await ApiService.sendMessage(chat.id, msg);
                              _snack('✅ Invite sent to ${chat.name}!',
                                  AppColors.online);
                            } catch (e) {
                              _snack('Failed: $e', AppColors.busy);
                            }
                          },
                        );
                      })),
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
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, size: 20), onPressed: _load)
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            Expanded(
                child: ElevatedButton.icon(
              onPressed: () => _showNewMeeting(user),
              icon: const Icon(Icons.videocam_rounded),
              label: const Text('New Meeting',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            )),
            const SizedBox(width: 12),
            Expanded(
                child: OutlinedButton.icon(
              onPressed: () => _showJoinWithCode(user),
              icon: const Icon(Icons.login_rounded),
              label: const Text('Join with Code',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            )),
          ]),
        ),
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
                          const SizedBox(height: 12),
                          const Text('No meetings yet',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary)),
                          const SizedBox(height: 8),
                          const Text('Tap New Meeting to create one',
                              style: TextStyle(color: AppColors.textMuted)),
                        ]))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
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
                                      ? AppColors.online.withOpacity(0.5)
                                      : AppColors.border)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                          color: isLive
                                              ? AppColors.online
                                                  .withOpacity(0.15)
                                              : themeColor.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      child: Icon(Icons.videocam_rounded,
                                          color: isLive
                                              ? AppColors.online
                                              : themeColor,
                                          size: 22)),
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
                                        Text(m.organizer,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textMuted)),
                                      ])),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                        color: isLive
                                            ? AppColors.online.withOpacity(0.1)
                                            : AppColors.primary
                                                .withOpacity(0.1),
                                        borderRadius:
                                            BorderRadius.circular(20)),
                                    child: Text(
                                        isLive
                                            ? '🔴 LIVE'
                                            : m.status.toUpperCase(),
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: isLive
                                                ? AppColors.online
                                                : AppColors.primary)),
                                  ),
                                ]),
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
                                                themeColor.withOpacity(0.2))),
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
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 4,
                                              color: themeColor)),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () {
                                          Clipboard.setData(
                                              ClipboardData(text: m.code));
                                          _snack('Code copied!', themeColor);
                                        },
                                        child: Icon(Icons.copy_rounded,
                                            size: 16, color: themeColor),
                                      ),
                                    ]),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Row(children: [
                                  if (isHost && m.code.isNotEmpty) ...[
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
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                      child: ElevatedButton.icon(
                                    onPressed: () =>
                                        _openRoom(m, user, isHost: isHost),
                                    icon: Icon(
                                        isHost
                                            ? Icons.videocam_rounded
                                            : Icons.login_rounded,
                                        size: 16),
                                    label: Text(
                                        isHost
                                            ? (isLive ? 'Rejoin' : 'Start')
                                            : 'Join',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700)),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: isLive
                                            ? AppColors.online
                                            : themeColor,
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
}
