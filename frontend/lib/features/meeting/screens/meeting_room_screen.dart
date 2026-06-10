import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/auth_provider.dart';
import '../../meeting/screens/meeting_room_screen.dart';
import 'meeting_screen.dart'; // ← for MeetingStatus, WaitingPerson, RoomParticipant, MeetingRoomService
import '../../meeting/screens/meeting_screen.dart';

class MeetingRoomScreen extends StatefulWidget {
  final String meetingId;
  final String meetingCode;
  final String inviteLink;
  final bool isHost;
  final String meetingTitle;
  final String userName;

  const MeetingRoomScreen({
    super.key,
    this.meetingId = '',
    this.meetingCode = '',
    this.inviteLink = '',
    this.isHost = false,
    this.meetingTitle = 'Meeting',
    this.userName = 'Guest',
  });

  @override
  State<MeetingRoomScreen> createState() => _MeetingRoomScreenState();
}

class _MeetingRoomScreenState extends State<MeetingRoomScreen> {
  late final MeetingRoomService _svc;
  bool _initialized = false;
  bool _jitsiLaunched = false;

  @override
  void initState() {
    super.initState();
    _svc = MeetingRoomService();
    _svc.addListener(_onUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    if (_initialized || !mounted) return;
    _initialized = true;

    final auth = context.read<AuthProvider>();
    await _svc.connect(
      meetingId: widget.meetingCode, // use the meeting code as room ID
      userId: auth.user?.id ?? '',
      userName: auth.user?.name ?? widget.userName,
      isHost: widget.isHost,
      title: widget.meetingTitle,
    );
  }

  void _onUpdate() {
    if (!mounted) return;
    setState(() {});

    // When admitted, auto-launch Jitsi
    if (_svc.status == MeetingStatus.admitted && !_jitsiLaunched) {
      _jitsiLaunched = true;
      _launchJitsi();
    }

    // When ended/rejected, pop back
    if (_svc.status == MeetingStatus.ended ||
        _svc.status == MeetingStatus.removed) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) Navigator.pop(context);
      });
    }
    if (_svc.status == MeetingStatus.rejected) {
      // Stay on screen to show rejection message
    }
  }

  Future<void> _launchJitsi() async {
    // Small delay so user sees "admitted" before Jitsi opens
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    final jitsiUrl = 'https://meet.jit.si/WorkspacePro-${widget.meetingCode}';
    final uri = Uri.parse(jitsiUrl);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _snack('Could not open meeting. Install a browser.', AppColors.busy);
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

  @override
  void dispose() {
    _svc.removeListener(_onUpdate);
    _svc.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    switch (_svc.status) {
      case MeetingStatus.connecting:
        return _buildConnecting();
      case MeetingStatus.waiting:
        return _buildWaiting();
      case MeetingStatus.admitted:
        return widget.isHost ? _buildHostRoom() : _buildAdmitted();
      case MeetingStatus.rejected:
        return _buildRejected();
      case MeetingStatus.removed:
        return _buildRemoved();
      case MeetingStatus.ended:
        return _buildEnded();
    }
  }

  // ── Connecting ─────────────────────────────────────────────────────────────

  Widget _buildConnecting() {
    final themeColor = context.read<AuthProvider>().themeColor;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 90,
            height: 90,
            decoration:
                BoxDecoration(color: themeColor, shape: BoxShape.circle),
            child: const Icon(Icons.videocam_rounded,
                color: Colors.white, size: 44),
          ),
          const SizedBox(height: 28),
          Text(widget.meetingTitle,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(widget.isHost ? 'Setting up your meeting…' : 'Connecting…',
              style: const TextStyle(color: Colors.white70, fontSize: 15)),
          const SizedBox(height: 32),
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 32),
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.cancel_outlined, color: Colors.white54),
            label:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
        ]),
      ),
    );
  }

  // ── Waiting room (user side) ───────────────────────────────────────────────

  Widget _buildWaiting() {
    final themeColor = context.read<AuthProvider>().themeColor;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            // Animated hourglass icon
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                  color: themeColor.withOpacity(0.15), shape: BoxShape.circle),
              child: Icon(Icons.hourglass_top_rounded,
                  color: themeColor, size: 56),
            ),
            const SizedBox(height: 32),
            Text(widget.meetingTitle,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            if (_svc.hostName.isNotEmpty)
              Text('Hosted by ${_svc.hostName}',
                  style: const TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 8),
            const Text('Waiting for the host to let you in…',
                style: TextStyle(color: Colors.white70, fontSize: 15),
                textAlign: TextAlign.center),
            const SizedBox(height: 40),
            // Pulsing dots
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _dot(themeColor, 0),
              const SizedBox(width: 8),
              _dot(themeColor, 1),
              const SizedBox(width: 8),
              _dot(themeColor, 2),
            ]),
            const SizedBox(height: 48),
            // Meeting code display
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.tag_rounded, color: Colors.white54, size: 16),
                const SizedBox(width: 8),
                Text(widget.meetingCode,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4)),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: widget.meetingCode));
                    _snack('Code copied!', themeColor);
                  },
                  child: const Icon(Icons.copy_rounded,
                      color: Colors.white38, size: 18),
                ),
              ]),
            ),
            const SizedBox(height: 40),
            TextButton.icon(
              onPressed: () {
                _svc.leave();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.cancel_outlined, color: Colors.white54),
              label: const Text('Leave',
                  style: TextStyle(color: Colors.white54, fontSize: 15)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _dot(Color color, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1.0),
      duration: Duration(milliseconds: 600 + index * 200),
      builder: (_, val, child) => Opacity(opacity: val, child: child),
      child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    );
  }

  // ── Admitted (user side — Jitsi is launching) ──────────────────────────────

  Widget _buildAdmitted() {
    final themeColor = context.read<AuthProvider>().themeColor;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
                color: AppColors.online.withOpacity(0.15),
                shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_rounded,
                color: AppColors.online, size: 56),
          ),
          const SizedBox(height: 28),
          const Text('You\'re admitted! 🎉',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text('Opening meeting…',
              style: TextStyle(color: Colors.white70, fontSize: 15)),
          const SizedBox(height: 32),
          CircularProgressIndicator(color: themeColor),
          const SizedBox(height: 40),
          // Manual open button if browser didn't launch
          OutlinedButton.icon(
            onPressed: _launchJitsi,
            icon:
                const Icon(Icons.open_in_new, color: Colors.white70, size: 16),
            label: const Text('Open Meeting Manually',
                style: TextStyle(color: Colors.white70)),
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white24)),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Go Back', style: TextStyle(color: Colors.white38)),
          ),
        ]),
      ),
    );
  }

  // ── Host room (admin side) ─────────────────────────────────────────────────

  Widget _buildHostRoom() {
    final themeColor = context.read<AuthProvider>().themeColor;
    final waitingCount = _svc.waitingRoom.length;
    final participantCount = _svc.participants.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        surfaceTintColor: Colors.transparent,
        title: Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: AppColors.online, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(widget.meetingTitle,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        actions: [
          // Code chip
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.meetingCode));
              _snack('Code copied!', themeColor);
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: themeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: themeColor.withOpacity(0.4))),
              child: Text(widget.meetingCode,
                  style: TextStyle(
                      color: themeColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3)),
            ),
          ),
        ],
      ),
      body: Column(children: [
        // ── Stats bar ──────────────────────────────────────────────────────
        Container(
          color: const Color(0xFF1A1A2E),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            _statChip(Icons.people_rounded, '$participantCount in meeting',
                AppColors.online),
            const SizedBox(width: 12),
            if (waitingCount > 0)
              _statChip(Icons.hourglass_empty_rounded, '$waitingCount waiting',
                  AppColors.away),
          ]),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── Waiting room section ────────────────────────────────────
              if (_svc.waitingRoom.isNotEmpty) ...[
                Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: AppColors.away, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text('Waiting Room (${_svc.waitingRoom.length})',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.away)),
                ]),
                const SizedBox(height: 10),
                ..._svc.waitingRoom
                    .map((person) => _buildWaitingCard(person, themeColor)),
                const SizedBox(height: 20),
              ],

              // ── In meeting section ──────────────────────────────────────
              Row(children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                      color: AppColors.online, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text('In Meeting (${_svc.participants.length})',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.online)),
              ]),
              const SizedBox(height: 10),
              // Host tile
              _buildParticipantCard(
                  name: 'You (Host)', isHost: true, color: themeColor),
              // Others
              ..._svc.participants.where((p) => !p.isHost).map((p) =>
                  _buildParticipantCard(
                      name: p.userName, isHost: false, color: themeColor)),
            ]),
          ),
        ),

        // ── Bottom actions ─────────────────────────────────────────────────
        Container(
          color: const Color(0xFF1A1A2E),
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
          child: Column(children: [
            // Join Jitsi button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _launchJitsi,
                icon: const Icon(Icons.videocam_rounded, size: 20),
                label: const Text('Join Video Call',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.online,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _confirmEnd,
                icon: const Icon(Icons.call_end_rounded,
                    color: AppColors.busy, size: 18),
                label: const Text('End Meeting for All',
                    style: TextStyle(
                        color: AppColors.busy, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.busy),
                    padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _statChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _buildWaitingCard(WaitingPerson person, Color themeColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.away.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.away.withOpacity(0.3))),
      child: Row(children: [
        // Avatar
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: AppColors.away.withOpacity(0.15), shape: BoxShape.circle),
          child: Center(
            child: Text(
              person.userName.isNotEmpty
                  ? person.userName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                  color: AppColors.away,
                  fontSize: 18,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(person.userName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const Text('Waiting to join',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
        // Deny button
        GestureDetector(
          onTap: () => _svc.denyUser(person.userId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
                color: AppColors.busy.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.busy.withOpacity(0.4))),
            child: const Text('Deny',
                style: TextStyle(
                    color: AppColors.busy,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 8),
        // Admit button
        GestureDetector(
          onTap: () => _svc.admitUser(person.userId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
                color: AppColors.online,
                borderRadius: BorderRadius.circular(8)),
            child: const Text('Admit',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  Widget _buildParticipantCard({
    required String name,
    required bool isHost,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12)),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: color.withOpacity(0.15), shape: BoxShape.circle),
          child: Center(
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                  color: color, fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
        if (isHost)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: AppColors.away.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6)),
            child: const Text('Host',
                style: TextStyle(
                    color: AppColors.away,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          )
        else
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: AppColors.online, shape: BoxShape.circle),
          ),
      ]),
    );
  }

  void _confirmEnd() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('End Meeting?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text('This will end the meeting for all participants.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _svc.endMeeting();
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.busy),
            child: const Text('End for All'),
          ),
        ],
      ),
    );
  }

  // ── Rejected ───────────────────────────────────────────────────────────────

  Widget _buildRejected() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                  color: AppColors.busy.withOpacity(0.15),
                  shape: BoxShape.circle),
              child: const Icon(Icons.cancel_rounded,
                  color: AppColors.busy, size: 52),
            ),
            const SizedBox(height: 28),
            const Text('Request Declined',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const Text('The host did not let you into this meeting.',
                style: TextStyle(color: Colors.white54, fontSize: 14),
                textAlign: TextAlign.center),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Go Back'),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Removed ────────────────────────────────────────────────────────────────

  Widget _buildRemoved() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.person_remove_rounded,
              color: AppColors.busy, size: 64),
          const SizedBox(height: 20),
          const Text('You were removed',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Go Back'),
          ),
        ]),
      ),
    );
  }

  // ── Ended ──────────────────────────────────────────────────────────────────

  Widget _buildEnded() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.call_end_rounded, color: AppColors.busy, size: 64),
          const SizedBox(height: 20),
          const Text('Meeting ended',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Go Back'),
          ),
        ]),
      ),
    );
  }
}
