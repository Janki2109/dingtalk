import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MEETING STATUS
// ═══════════════════════════════════════════════════════════════════════════

enum MeetingStatus { connecting, waiting, admitted, rejected, removed, ended }

// ═══════════════════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════════════════

class WaitingPerson {
  final String userId;
  final String userName;
  WaitingPerson({required this.userId, required this.userName});
  factory WaitingPerson.fromJson(Map<String, dynamic> j) =>
      WaitingPerson(userId: j['user_id'] ?? '', userName: j['user_name'] ?? '');
}

class RoomParticipant {
  final String userId;
  final String userName;
  final bool isHost;
  RoomParticipant(
      {required this.userId, required this.userName, required this.isHost});
  factory RoomParticipant.fromJson(Map<String, dynamic> j) => RoomParticipant(
      userId: j['user_id'] ?? '',
      userName: j['user_name'] ?? '',
      isHost: j['is_host'] ?? false);
}

// ═══════════════════════════════════════════════════════════════════════════
// MEETING ROOM SERVICE
// ═══════════════════════════════════════════════════════════════════════════

class MeetingRoomService extends ChangeNotifier {
  static const _base = AppConstants.serverUrl;

  MeetingStatus status = MeetingStatus.connecting;
  List<WaitingPerson> waitingRoom = [];
  List<RoomParticipant> participants = [];
  String roomTitle = '';
  String hostName = '';

  Timer? _pollTimer;
  String _meetingId = '';
  String _userId = '';
  String _userName = '';
  bool _isHost = false;

  Future<void> connect({
    required String meetingId,
    required String userId,
    required String userName,
    required bool isHost,
    required String title,
  }) async {
    _meetingId = meetingId;
    _userId = userId;
    _userName = userName;
    _isHost = isHost;
    roomTitle = title;
    status = MeetingStatus.connecting;
    notifyListeners();
    if (isHost) {
      await _createRoom(title);
    } else {
      await _joinWaitingRoom();
    }
  }

  Future<void> _createRoom(String title) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/api/room/create'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'host_id': _userId,
              'host_name': _userName,
              'title': title,
              'meeting_id': _meetingId,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 || res.statusCode == 201) {
        status = MeetingStatus.admitted;
        notifyListeners();
        _startPollingWaitingRoom();
      } else {
        status = MeetingStatus.ended;
        notifyListeners();
      }
    } catch (_) {
      status = MeetingStatus.ended;
      notifyListeners();
    }
  }

  Future<void> _joinWaitingRoom() async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/api/room/join'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'meeting_id': _meetingId,
              'user_id': _userId,
              'user_name': _userName,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      if (res.statusCode == 404) {
        status = MeetingStatus.waiting;
        notifyListeners();
        _startPollingStatus();
        return;
      }
      final joinStatus = body['status'] ?? '';
      hostName = body['host_name'] ?? '';
      roomTitle = body['title'] ?? roomTitle;
      if (joinStatus == 'admitted') {
        status = MeetingStatus.admitted;
      } else {
        status = MeetingStatus.waiting;
        _startPollingStatus();
      }
      notifyListeners();
    } catch (_) {
      status = MeetingStatus.waiting;
      notifyListeners();
      _startPollingStatus();
    }
  }

  void _startPollingStatus() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (status == MeetingStatus.admitted ||
          status == MeetingStatus.rejected ||
          status == MeetingStatus.removed ||
          status == MeetingStatus.ended) {
        _pollTimer?.cancel();
        return;
      }
      await _checkStatus();
    });
  }

  Future<void> _checkStatus() async {
    try {
      final res = await http
          .get(
            Uri.parse(
                '$_base/api/room/status?meeting_id=$_meetingId&user_id=$_userId'),
          )
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      final s = body['status'] ?? '';
      if (s == 'admitted') {
        _pollTimer?.cancel();
        status = MeetingStatus.admitted;
        notifyListeners();
      } else if (s == 'denied') {
        _pollTimer?.cancel();
        status = MeetingStatus.rejected;
        notifyListeners();
      } else if (s == 'not_found') {
        _pollTimer?.cancel();
        status = MeetingStatus.ended;
        notifyListeners();
      }
    } catch (_) {}
  }

  void _startPollingWaitingRoom() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (status == MeetingStatus.ended) {
        _pollTimer?.cancel();
        return;
      }
      await _fetchWaitingRoom();
    });
  }

  Future<void> _fetchWaitingRoom() async {
    try {
      final res = await http
          .get(
            Uri.parse('$_base/api/room/waiting?meeting_id=$_meetingId'),
          )
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      waitingRoom = (body['waiting'] as List? ?? [])
          .map((j) => WaitingPerson.fromJson(j))
          .toList();
      participants = (body['participants'] as List? ?? [])
          .map((j) => RoomParticipant.fromJson(j))
          .toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> admitUser(String userId) async {
    await _admitAction(userId, 'admit');
    waitingRoom.removeWhere((w) => w.userId == userId);
    notifyListeners();
  }

  Future<void> denyUser(String userId) async {
    await _admitAction(userId, 'deny');
    waitingRoom.removeWhere((w) => w.userId == userId);
    notifyListeners();
  }

  Future<void> _admitAction(String userId, String action) async {
    try {
      await http
          .post(
            Uri.parse('$_base/api/room/admit'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'meeting_id': _meetingId,
              'user_id': userId,
              'action': action,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  Future<void> endMeeting() async {
    try {
      await http
          .post(
            Uri.parse('$_base/api/room/end'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'meeting_id': _meetingId}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    _pollTimer?.cancel();
    status = MeetingStatus.ended;
    notifyListeners();
  }

  void leave() {
    _pollTimer?.cancel();
    status = MeetingStatus.ended;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MEETING ROOM SCREEN
// ═══════════════════════════════════════════════════════════════════════════

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
      meetingId: widget.meetingCode,
      userId: auth.user?.id ?? '',
      userName: auth.user?.name ?? widget.userName,
      isHost: widget.isHost,
      title: widget.meetingTitle,
    );
  }

  void _onUpdate() {
    if (!mounted) return;
    setState(() {});
    if (_svc.status == MeetingStatus.admitted && !_jitsiLaunched) {
      _jitsiLaunched = true;
      _launchJitsi();
    }
    if (_svc.status == MeetingStatus.ended ||
        _svc.status == MeetingStatus.removed) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Future<void> _launchJitsi() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    final uri =
        Uri.parse('https://meet.jit.si/WorkspacePro-${widget.meetingCode}');
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
                color: Colors.white, size: 44)),
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
          label: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
      ])),
    );
  }

  Widget _buildWaiting() {
    final themeColor = context.read<AuthProvider>().themeColor;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
          child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                  color: themeColor.withOpacity(0.15), shape: BoxShape.circle),
              child: Icon(Icons.hourglass_top_rounded,
                  color: themeColor, size: 56)),
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
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 40),
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
      )),
    );
  }

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
                color: AppColors.online, size: 56)),
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
        OutlinedButton.icon(
          onPressed: _launchJitsi,
          icon: const Icon(Icons.open_in_new, color: Colors.white70, size: 16),
          label: const Text('Open Meeting Manually',
              style: TextStyle(color: Colors.white70)),
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24)),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Go Back', style: TextStyle(color: Colors.white38)),
        ),
      ])),
    );
  }

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
                  overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
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
            if (_svc.waitingRoom.isNotEmpty) ...[
              Row(children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: AppColors.away, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text('Waiting Room (${_svc.waitingRoom.length})',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.away)),
              ]),
              const SizedBox(height: 10),
              ..._svc.waitingRoom.map((p) => _buildWaitingCard(p, themeColor)),
              const SizedBox(height: 20),
            ],
            Row(children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                      color: AppColors.online, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text('In Meeting (${_svc.participants.length})',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.online)),
            ]),
            const SizedBox(height: 10),
            _buildParticipantCard(
                name: 'You (Host)', isHost: true, color: themeColor),
            ..._svc.participants.where((p) => !p.isHost).map((p) =>
                _buildParticipantCard(
                    name: p.userName, isHost: false, color: themeColor)),
          ]),
        )),
        Container(
          color: const Color(0xFF1A1A2E),
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
          child: Column(children: [
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
                )),
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
                )),
          ]),
        ),
      ]),
    );
  }

  Widget _statChip(IconData icon, String label, Color color) => Container(
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

  Widget _buildWaitingCard(WaitingPerson person, Color themeColor) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.away.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.away.withOpacity(0.3))),
        child: Row(children: [
          Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: AppColors.away.withOpacity(0.15),
                  shape: BoxShape.circle),
              child: Center(
                  child: Text(
                person.userName.isNotEmpty
                    ? person.userName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                    color: AppColors.away,
                    fontSize: 18,
                    fontWeight: FontWeight.w800),
              ))),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(person.userName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const Text('Waiting to join',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ])),
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

  Widget _buildParticipantCard(
          {required String name, required bool isHost, required Color color}) =>
      Container(
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
              ))),
          const SizedBox(width: 12),
          Expanded(
              child: Text(name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600))),
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
                    color: AppColors.online, shape: BoxShape.circle)),
        ]),
      );

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

  Widget _buildRejected() => Scaffold(
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
                    color: AppColors.busy, size: 52)),
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
        )),
      );

  Widget _buildRemoved() => Scaffold(
        backgroundColor: Colors.black,
        body: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
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
        ])),
      );

  Widget _buildEnded() => Scaffold(
        backgroundColor: Colors.black,
        body: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
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
        ])),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// MEETING SCREEN (main tab screen)
// ═══════════════════════════════════════════════════════════════════════════

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
            builder: (_) => MeetingRoomScreen(
                  meetingId: meeting.id,
                  meetingCode: meeting.code,
                  inviteLink:
                      'https://meet.jit.si/WorkspacePro-${meeting.code}',
                  isHost: isHost,
                  meetingTitle: meeting.title,
                  userName: user?.name ?? 'Guest',
                )));
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
    bool loading = false;
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
                        onPressed: loading
                            ? null
                            : () async {
                                final code = codeCtrl.text.trim().toUpperCase();
                                if (code.isEmpty) {
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
                                  if (mounted)
                                    _openRoom(meeting, user, isHost: false);
                                } catch (_) {
                                  setS(() {
                                    loading = false;
                                    error =
                                        'Meeting not found. Check the code.';
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
                        label: Text(loading ? 'Joining...' : 'Join Meeting'),
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
                  border: Border.all(color: AppColors.online.withOpacity(0.3))),
              child: const Row(children: [
                Icon(Icons.check_circle_rounded,
                    color: AppColors.online, size: 24),
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
                    '📹 Meeting Invite\nTitle: ${meeting.title}\nCode: ${meeting.code}\n\n'
                    'Open WorkSpace Pro → Meetings → Join with Code → ${meeting.code}';
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
                            final msg = '📹 Meeting Invite\n━━━━━━━━━━━━━━━━━\n'
                                'Title: ${meeting.title}\nCode:  ${meeting.code}\n━━━━━━━━━━━━━━━━━\n'
                                'Open WorkSpace Pro → Meetings → Join with Code → ${meeting.code}';
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
    final isAdmin = context.watch<AuthProvider>().isAdmin;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Meetings',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, size: 20), onPressed: _load),
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
