import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';
import '../../admin/screens/admin_attendance_screen.dart';

// ── Office Config ─────────────────────────────────────────────────────────────
const double _officeLat = 19.0717; // ← Change to your office latitude
const double _officeLng = 73.0158; // ← Change to your office longitude
const double _officeRadius = 200.0; // 200 metres
const int _officeStartH = 10; // 10 AM
const int _officeEndH = 19; // 7 PM

double _haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLon / 2) *
          sin(dLon / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with SingleTickerProviderStateMixin {
  bool _checkedIn = false;
  DateTime? _checkInTime;
  DateTime? _checkOutTime;
  bool _loading = false;
  bool _locLoading = false;
  bool _locationVerified = false;
  String _locationStatus = 'Tap 📍 to verify location';
  String _locationError = '';
  double _currentLat = 0;
  double _currentLng = 0;
  String _tab = 'monthly';
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _leaveRequests = [];

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  int get _presentCount =>
      _records.where((d) => d['status'] == 'Present').length;
  int get _leaveCount => _records.where((d) => d['status'] == 'Leave').length;

  @override
  void initState() {
    super.initState();
    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 1.0, end: 1.12)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _loadAttendance();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAttendance() async {
    try {
      final list = await ApiService.getAttendance();
      if (mounted)
        setState(() {
          _records = list
              .map((a) => {
                    'date': _fmtDate(a.date),
                    'in': a.checkIn != null ? _fmtTime(a.checkIn!) : '—',
                    'out': a.checkOut != null ? _fmtTime(a.checkOut!) : '—',
                    'status': (a.status == 'present' || a.status == 'late')
                        ? 'Present'
                        : 'Leave',
                    'isLate': a.status == 'late',
                    'hours': a.checkIn != null && a.checkOut != null
                        ? _calcDur(a.checkIn!, a.checkOut!)
                        : '—',
                    'location': a.location,
                  })
              .toList();
          _checkedIn = list.isNotEmpty &&
              list.first.checkIn != null &&
              list.first.checkOut == null &&
              _isToday(list.first.date);
          if (_checkedIn && list.first.checkIn != null) {
            _checkInTime = list.first.checkIn;
          }
        });
    } catch (_) {}
  }

  bool _isToday(DateTime dt) {
    final n = DateTime.now();
    return dt.year == n.year && dt.month == n.month && dt.day == n.day;
  }

  String _calcDur(DateTime a, DateTime b) {
    final d = b.difference(a);
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  // ── Real GPS ────────────────────────────────────────────────────────────────
  Future<void> _detectLocation() async {
    setState(() {
      _locLoading = true;
      _locationStatus = 'Getting GPS...';
    });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locLoading = false;
          _locationVerified = false;
          _locationStatus = '⚠️ Location disabled';
        });
        _showLocationHelp(
            'Location services are off. Please enable them in your device settings.');
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() {
          _locLoading = false;
          _locationVerified = false;
          _locationStatus = '⚠️ Permission denied';
        });
        _showLocationHelp(
            'Location blocked.\n\nTo fix in Chrome:\n1. Click 🔒 in address bar\n2. Site settings\n3. Location → Allow\n4. Refresh page');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20));
      _currentLat = pos.latitude;
      _currentLng = pos.longitude;
      final dist = _haversine(_currentLat, _currentLng, _officeLat, _officeLng);
      final ok = dist <= _officeRadius;
      setState(() {
        _locLoading = false;
        _locationVerified = ok;
        _locationStatus = ok
            ? '✅ At Office (${dist.toStringAsFixed(0)}m)'
            : '❌ ${dist.toStringAsFixed(0)}m from office';
        _locationError =
            ok ? '' : 'Must be within ${_officeRadius.toInt()}m of office.';
      });
      if (!ok) _showOutOfRange(dist);
    } catch (e) {
      setState(() {
        _locLoading = false;
        _locationVerified = false;
        _locationStatus = '⚠️ Location failed';
      });
    }
  }

  void _showLocationHelp(String msg) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Row(children: [
                Icon(Icons.location_off, color: Color(0xFFEF4444)),
                SizedBox(width: 8),
                Text('Location Required',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ]),
              content: Text(msg,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              actions: [
                ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _detectLocation();
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF)),
                    child: const Text('Try Again')),
              ],
            ));
  }

  void _showOutOfRange(double dist) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Row(children: [
                Icon(Icons.wrong_location, color: Color(0xFFEF4444)),
                SizedBox(width: 8),
                Text('Not at Office',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ]),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.location_on,
                    color: Color(0xFFEF4444), size: 36),
                const SizedBox(height: 8),
                Text('You are ${dist.toStringAsFixed(0)}m from office',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text('Required: within ${_officeRadius.toInt()}m',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 12),
                const Text('You must be at the office to check in.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                    textAlign: TextAlign.center),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close',
                        style: TextStyle(color: Colors.white54))),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    final url = Uri.parse(
                        'https://maps.google.com/?q=$_officeLat,$_officeLng&zoom=17');
                    if (await canLaunchUrl(url))
                      await launchUrl(url,
                          mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.map, size: 16),
                  label: const Text('View Office on Maps'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF)),
                ),
              ],
            ));
  }

  bool _isOfficeHours() {
    final h = DateTime.now().hour;
    return h >= _officeStartH && h < _officeEndH;
  }

  Future<void> _checkIn() async {
    if (!_locationVerified) {
      _snack('📍 Verify your location first', Colors.orange);
      await _detectLocation();
      return;
    }
    if (!_isOfficeHours()) {
      _snack('⏰ Check-in only 10:00 AM – 7:00 PM', const Color(0xFFEF4444));
      return;
    }
    setState(() => _loading = true);
    try {
      final rec = await ApiService.checkIn(_locationStatus);
      setState(() {
        _checkedIn = true;
        _checkInTime = rec.checkIn ?? DateTime.now();
        _checkOutTime = null;
        _loading = false;
      });
      _snack('✅ Checked in at ${_fmtTime(_checkInTime!)}',
          const Color(0xFF22C55E));
    } catch (e) {
      setState(() => _loading = false);
      _snack('Check-in failed: $e', const Color(0xFFEF4444));
    }
  }

  Future<void> _checkOut() async {
    setState(() => _loading = true);
    try {
      await ApiService.checkOut();
      final now = DateTime.now();
      setState(() {
        _checkOutTime = now;
        _checkedIn = false;
        _loading = false;
      });
      await _loadAttendance();
      // ✅ Show to-do list popup after checkout
      if (mounted) _showTodoPopup(now);
    } catch (e) {
      setState(() => _loading = false);
      _snack('Check-out failed: $e', const Color(0xFFEF4444));
    }
  }

  // ── To-Do List Popup after checkout ────────────────────────────────────────
  void _showTodoPopup(DateTime checkoutTime) {
    final user = context.read<AuthProvider>().user;
    final tasks = <TextEditingController>[TextEditingController()];
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
          builder: (ctx, setS) => Container(
                height: MediaQuery.of(context).size.height * 0.85,
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252545),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(24)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.1), blurRadius: 8)
                      ],
                    ),
                    child: Column(children: [
                      const Icon(Icons.assignment_outlined,
                          color: Color(0xFF6C63FF), size: 36),
                      const SizedBox(height: 8),
                      const Text('Daily Work Report',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      const SizedBox(height: 4),
                      Text(
                          'Checked out at ${_fmtTime(checkoutTime)} · Share your work with admin',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white54),
                          textAlign: TextAlign.center),
                    ]),
                  ),

                  Expanded(
                      child: Form(
                          key: formKey,
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              const Text('What did you work on today?',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white70)),
                              const SizedBox(height: 12),

                              // Task inputs
                              ...tasks.asMap().entries.map((entry) => Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 28,
                                            height: 28,
                                            margin: const EdgeInsets.only(
                                                top: 10, right: 8),
                                            decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: const Color(0xFF6C63FF)
                                                    .withOpacity(0.2)),
                                            child: Center(
                                                child: Text('${entry.key + 1}',
                                                    style: const TextStyle(
                                                        color:
                                                            Color(0xFF6C63FF),
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w700))),
                                          ),
                                          Expanded(
                                              child: TextField(
                                            controller: entry.value,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14),
                                            maxLines: 2,
                                            decoration: InputDecoration(
                                              hintText:
                                                  'Describe task ${entry.key + 1}...',
                                              hintStyle: const TextStyle(
                                                  color: Colors.white38,
                                                  fontSize: 13),
                                              filled: true,
                                              fillColor:
                                                  const Color(0xFF252538),
                                              border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: BorderSide.none),
                                              contentPadding:
                                                  const EdgeInsets.all(12),
                                            ),
                                          )),
                                          if (tasks.length > 1)
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.remove_circle_outline,
                                                  color: Color(0xFFEF4444),
                                                  size: 20),
                                              onPressed: () => setS(() =>
                                                  tasks.removeAt(entry.key)),
                                            ),
                                        ]),
                                  )),

                              // Add task button
                              GestureDetector(
                                onTap: () => setS(
                                    () => tasks.add(TextEditingController())),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                      color: const Color(0xFF6C63FF)
                                          .withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: const Color(0xFF6C63FF)
                                              .withOpacity(0.3),
                                          style: BorderStyle.solid)),
                                  child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.add,
                                            color: Color(0xFF6C63FF), size: 18),
                                        SizedBox(width: 6),
                                        Text('Add Another Task',
                                            style: TextStyle(
                                                color: Color(0xFF6C63FF),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600)),
                                      ]),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ))),

                  // Submit button
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        16, 8, 16, MediaQuery.of(context).padding.bottom + 16),
                    child: Column(children: [
                      SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              final taskList = tasks
                                  .map((c) => c.text.trim())
                                  .where((t) => t.isNotEmpty)
                                  .toList();
                              if (taskList.isEmpty) {
                                _snack('Please add at least one task',
                                    Colors.orange);
                                return;
                              }
                              // Save to TodoStore so admin can see it
                              TodoStore.submissions.insert(0, {
                                'employee': user?.name ?? 'Employee',
                                'employeeId': user?.id ?? '',
                                'date': _fmtDate(DateTime.now()),
                                'checkOut': _fmtTime(checkoutTime),
                                'tasks': taskList,
                                'acknowledged': false,
                                'submittedAt': DateTime.now().toIso8601String(),
                              });
                              Navigator.pop(context);
                              _snack('📋 Work report sent to admin!',
                                  const Color(0xFF22C55E));
                              _loadAttendance();
                            },
                            icon: const Icon(Icons.send_rounded, size: 18),
                            label: const Text('Send to Admin',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6C63FF),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))),
                          )),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _snack('Work report skipped', Colors.grey);
                        },
                        child: const Text('Skip for now',
                            style:
                                TextStyle(color: Colors.white38, fontSize: 13)),
                      ),
                    ]),
                  ),
                ]),
              )),
    );
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _applyLeave() {
    final reasonCtrl = TextEditingController();
    String leaveType = 'Sick Leave';
    DateTime from = DateTime.now(), to = DateTime.now();
    List<Map<String, String>> admins = [];
    String approverId = '', approverName = '';
    bool loadingAdmins = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) {
        if (loadingAdmins) {
          loadingAdmins = false;
          ApiService.getUsers().then((users) {
            final al = users
                .where((u) => u.isAdmin)
                .map((u) => {'id': u.id, 'name': u.name})
                .toList();
            setS(() {
              admins = al;
              if (al.isNotEmpty) {
                approverId = al.first['id']!;
                approverName = al.first['name']!;
              }
            });
          });
        }
        return Container(
          decoration: const BoxDecoration(
              color: Color(0xFF1A1A2E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
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
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                const Text('Apply Leave',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 16),
                Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      'Sick Leave',
                      'Casual Leave',
                      'Annual Leave',
                      'Emergency Leave'
                    ]
                        .map((t) => GestureDetector(
                            onTap: () => setS(() => leaveType = t),
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                    gradient: leaveType == t
                                        ? const LinearGradient(colors: [
                                            Color(0xFF6C63FF),
                                            Color(0xFF3B82F6)
                                          ])
                                        : null,
                                    color:
                                        leaveType == t ? null : Colors.white10,
                                    borderRadius: BorderRadius.circular(20)),
                                child: Text(t,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: leaveType == t
                                            ? Colors.white
                                            : Colors.white60)))))
                        .toList()),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                      child: GestureDetector(
                          onTap: () async {
                            final d = await showDatePicker(
                                context: context,
                                initialDate: from,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 365)));
                            if (d != null) setS(() => from = d);
                          },
                          child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(14)),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('FROM',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.white38,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 4),
                                    Text(
                                        '${from.day}/${from.month}/${from.year}',
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white)),
                                  ])))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: GestureDetector(
                          onTap: () async {
                            final d = await showDatePicker(
                                context: context,
                                initialDate: to,
                                firstDate: from,
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 365)));
                            if (d != null) setS(() => to = d);
                          },
                          child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(14)),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('TO',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.white38,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 4),
                                    Text('${to.day}/${to.month}/${to.year}',
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white)),
                                  ])))),
                ]),
                const SizedBox(height: 16),
                const Text('Send To *',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white54,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (admins.isEmpty)
                  const Text('Loading admins...',
                      style: TextStyle(color: Colors.white38))
                else
                  ...admins.map((a) => GestureDetector(
                      onTap: () => setS(() {
                            approverId = a['id']!;
                            approverName = a['name']!;
                          }),
                      child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: approverId == a['id']
                                  ? const Color(0xFF6C63FF).withOpacity(0.15)
                                  : Colors.white10,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: approverId == a['id']
                                      ? const Color(0xFF6C63FF)
                                      : Colors.white12)),
                          child: Row(children: [
                            Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withOpacity(0.1)),
                                child: Center(
                                    child: Text(a['name']![0].toUpperCase(),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800)))),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(a['name']!,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600))),
                            if (approverId == a['id'])
                              const Icon(Icons.check_circle,
                                  color: Color(0xFF6C63FF), size: 20),
                          ])))),
                const SizedBox(height: 12),
                TextField(
                    controller: reasonCtrl,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                        hintText: 'Reason for leave...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none))),
                const SizedBox(height: 20),
                SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (reasonCtrl.text.trim().isEmpty) {
                          _snack('Enter a reason', Colors.orange);
                          return;
                        }
                        if (approverId.isEmpty) {
                          _snack('Select an admin', Colors.orange);
                          return;
                        }
                        try {
                          await ApiService.createApproval({
                            'title': '$leaveType Request',
                            'approval_type': leaveType,
                            'approver_id': approverId,
                            'description':
                                '${from.day}/${from.month}/${from.year} to ${to.day}/${to.month}/${to.year} — ${reasonCtrl.text.trim()}',
                          });
                        } catch (_) {}
                        setState(() => _leaveRequests.insert(0, {
                              'date':
                                  '${from.day}/${from.month} – ${to.day}/${to.month}',
                              'type': leaveType,
                              'status': 'Pending',
                              'reason': reasonCtrl.text.trim(),
                              'approver': approverName,
                            }));
                        if (context.mounted) Navigator.pop(context);
                        _snack('📋 Leave sent to $approverName!',
                            const Color(0xFF6C63FF));
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14))),
                      child: const Text('Submit Leave Request',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    )),
              ])),
        );
      }),
    );
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    return '$h:${dt.minute.toString().padLeft(2, '0')} ${dt.hour < 12 ? 'AM' : 'PM'}';
  }

  String _fmtDate(DateTime dt) {
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
    const da = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${da[dt.weekday - 1]}, ${mo[dt.month - 1]} ${dt.day}';
  }

  String _duration() {
    if (_checkInTime == null) return '—';
    final d = (_checkOutTime ?? DateTime.now()).difference(_checkInTime!);
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  String _lateLabel() {
    if (_checkInTime == null) return '';
    final late =
        _checkInTime!.hour * 60 + _checkInTime!.minute - _officeStartH * 60;
    if (late <= 0) return '✅ On time';
    if (late <= 15) return '⏱ ${late}m late';
    return '🔴 ${late}m late';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E1A),
      body: CustomScrollView(slivers: [
        SliverAppBar(
          floating: true,
          backgroundColor: const Color(0xFF0F0E1A),
          surfaceTintColor: Colors.transparent,
          title: const Text('Attendance',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  color: Colors.white)),
          actions: [
            IconButton(
              icon: _locLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.my_location_rounded,
                      color: Colors.white70),
              onPressed: _detectLocation,
              tooltip: 'Verify location',
            ),
            IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                onPressed: _loadAttendance),
          ],
        ),
        SliverToBoxAdapter(
            child: Column(children: [
          // ── Hero card ──────────────────────────────────────────────────
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    colors: _checkedIn
                        ? [
                            const Color(0xFF6C63FF),
                            const Color(0xFF3B82F6),
                            const Color(0xFF06B6D4)
                          ]
                        : [
                            const Color(0xFF1E1E3A),
                            const Color(0xFF252545),
                            const Color(0xFF1A2744)
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (_checkedIn ? const Color(0xFF6C63FF) : Colors.black)
                              .withOpacity(0.4),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Stack(children: [
                  Positioned(
                      top: -20,
                      right: -20,
                      child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.04)))),
                  Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(children: [
                        Row(children: [
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    _checkedIn
                                        ? 'Working Now'
                                        : 'Not Checked In',
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500)),
                                const SizedBox(height: 2),
                                Text(timeStr,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 36,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -1)),
                                Text('Office: 10:00 AM – 7:00 PM',
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.4),
                                        fontSize: 11)),
                              ]),
                          const Spacer(),
                          GestureDetector(
                            onTap: _loading
                                ? null
                                : (_checkedIn ? _checkOut : _checkIn),
                            child: AnimatedBuilder(
                              animation: _pulseAnim,
                              builder: (_, child) => Transform.scale(
                                  scale: _checkedIn ? _pulseAnim.value : 1.0,
                                  child: child),
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.white.withOpacity(0.3),
                                          blurRadius: 16)
                                    ]),
                                child: _loading
                                    ? const Padding(
                                        padding: EdgeInsets.all(20),
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Color(0xFF6C63FF)))
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                            Icon(
                                                _checkedIn
                                                    ? Icons.stop_rounded
                                                    : Icons.play_arrow_rounded,
                                                color: const Color(0xFF6C63FF),
                                                size: 32),
                                            Text(_checkedIn ? 'OUT' : 'IN',
                                                style: const TextStyle(
                                                    color: Color(0xFF6C63FF),
                                                    fontSize: 10,
                                                    fontWeight:
                                                        FontWeight.w800)),
                                          ]),
                              ),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 14),
                        if (_checkedIn)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(14)),
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.timer_outlined,
                                      color: Colors.white, size: 16),
                                  const SizedBox(width: 8),
                                  Text('Working for ${_duration()}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700)),
                                  if (_lateLabel().isNotEmpty) ...[
                                    const SizedBox(width: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      child: Text(_lateLabel(),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ]),
                          ),
                        const SizedBox(height: 14),
                        Row(children: [
                          _TimeChip(
                              'CHECK IN',
                              _checkInTime != null
                                  ? _fmtTime(_checkInTime!)
                                  : '—'),
                          const SizedBox(width: 8),
                          _TimeChip(
                              'CHECK OUT',
                              _checkOutTime != null
                                  ? _fmtTime(_checkOutTime!)
                                  : '—'),
                          const SizedBox(width: 8),
                          _TimeChip('DURATION', _duration()),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: GestureDetector(
                            onTap: _detectLocation,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: _locationVerified
                                    ? const Color(0xFF22C55E).withOpacity(0.2)
                                    : _locationError.isNotEmpty
                                        ? const Color(0xFFEF4444)
                                            .withOpacity(0.2)
                                        : Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: _locationVerified
                                        ? const Color(0xFF22C55E)
                                            .withOpacity(0.4)
                                        : Colors.white.withOpacity(0.2)),
                              ),
                              child: Row(children: [
                                _locLoading
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 1.5))
                                    : Icon(
                                        _locationVerified
                                            ? Icons.location_on
                                            : Icons.location_searching,
                                        color: Colors.white,
                                        size: 14),
                                const SizedBox(width: 6),
                                Flexible(
                                    child: Text(_locationStatus,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis)),
                              ]),
                            ),
                          )),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: _isOfficeHours()
                                  ? const Color(0xFF22C55E).withOpacity(0.2)
                                  : const Color(0xFFEF4444).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.2)),
                            ),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(
                                  _isOfficeHours()
                                      ? Icons.lock_open
                                      : Icons.lock,
                                  color: Colors.white,
                                  size: 14),
                              const SizedBox(width: 6),
                              Text(_isOfficeHours() ? 'Open ✓' : 'Closed',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        GestureDetector(
                            onTap: _applyLeave,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: Colors.white.withOpacity(0.2))),
                              child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.beach_access_outlined,
                                        color: Colors.white, size: 16),
                                    SizedBox(width: 8),
                                    Text('Apply for Leave',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700)),
                                  ]),
                            )),
                      ])),
                ]),
              )),
          const SizedBox(height: 16),

          // ── Stats ──────────────────────────────────────────────────────
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                _StatCard('Present', '$_presentCount', const Color(0xFF6C63FF),
                    Icons.check_circle_outline),
                const SizedBox(width: 10),
                _StatCard('Leave', '$_leaveCount', const Color(0xFF3B82F6),
                    Icons.beach_access_outlined),
                const SizedBox(width: 10),
                _StatCard('Total', '${_records.length}',
                    const Color(0xFF06B6D4), Icons.calendar_month_outlined),
              ])),
          const SizedBox(height: 16),

          // ── Tabs ───────────────────────────────────────────────────────
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  _TabBtn('Monthly', _tab == 'monthly',
                      () => setState(() => _tab = 'monthly')),
                  _TabBtn('Leave Requests', _tab == 'leave',
                      () => setState(() => _tab = 'leave')),
                ]),
              )),
          const SizedBox(height: 14),

          if (_tab == 'monthly') ...[
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Text(
                      '${_monthName(DateTime.now().month)} ${DateTime.now().year}',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)]),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('$_presentCount Present',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                ])),
            const SizedBox(height: 10),
            if (_records.isEmpty)
              Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(children: [
                    Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [
                              const Color(0xFF6C63FF).withOpacity(0.2),
                              const Color(0xFF3B82F6).withOpacity(0.1)
                            ])),
                        child: const Icon(Icons.calendar_today_outlined,
                            size: 32, color: Color(0xFF6C63FF))),
                    const SizedBox(height: 16),
                    const Text('No records yet',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white70)),
                    const SizedBox(height: 6),
                    const Text('Verify location & check in to start',
                        style: TextStyle(fontSize: 12, color: Colors.white38),
                        textAlign: TextAlign.center),
                  ]))
            else
              ..._records.map((a) => _RecordCard(record: a)),
          ],

          if (_tab == 'leave') ...[
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  const Text('Leave Requests',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const Spacer(),
                  GestureDetector(
                      onTap: _applyLeave,
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                Color(0xFF6C63FF),
                                Color(0xFF3B82F6)
                              ]),
                              borderRadius: BorderRadius.circular(20)),
                          child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add, color: Colors.white, size: 14),
                                SizedBox(width: 4),
                                Text('Apply',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                              ]))),
                ])),
            const SizedBox(height: 10),
            if (_leaveRequests.isEmpty)
              Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(children: [
                    Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF3B82F6).withOpacity(0.15)),
                        child: const Icon(Icons.beach_access_outlined,
                            size: 30, color: Color(0xFF3B82F6))),
                    const SizedBox(height: 12),
                    const Text('No leave requests yet',
                        style: TextStyle(fontSize: 14, color: Colors.white70)),
                  ]))
            else
              ..._leaveRequests.map((l) => _LeaveCard(leave: l)),
          ],

          const SizedBox(height: 100),
        ])),
      ]),
    );
  }

  String _monthName(int m) {
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
    return mo[m - 1];
  }
}

class _TimeChip extends StatelessWidget {
  final String label, value;
  const _TimeChip(this.label, this.value);
  @override
  Widget build(BuildContext context) => Expanded(
          child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ]),
      ));
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _StatCard(this.label, this.value, this.color, this.icon);
  @override
  Widget build(BuildContext context) => Expanded(
          child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3))),
        child: Column(children: [
          Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: color.withOpacity(0.15)),
              child: Icon(icon, color: color, size: 16)),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.white38)),
        ]),
      ));
}

class _TabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabBtn(this.label, this.active, this.onTap);
  @override
  Widget build(BuildContext context) => Expanded(
          child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                gradient: active
                    ? const LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)])
                    : null,
                borderRadius: BorderRadius.circular(10)),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : Colors.white38))),
      ));
}

class _RecordCard extends StatelessWidget {
  final Map<String, dynamic> record;
  const _RecordCard({required this.record});
  @override
  Widget build(BuildContext context) {
    final status = record['status'] as String;
    final isLate = record['isLate'] as bool? ?? false;
    final color =
        status == 'Present' ? const Color(0xFF6C63FF) : const Color(0xFF3B82F6);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2))),
      child: Row(children: [
        Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    colors: [color.withOpacity(0.3), color.withOpacity(0.1)])),
            child: Icon(
                status == 'Present' ? Icons.check_rounded : Icons.beach_access,
                color: color,
                size: 22)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(record['date'] as String,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(height: 3),
          Text(
              status == 'Present'
                  ? '${record['in']} → ${record['out']}  ·  ${record['hours']}'
                  : 'Absent',
              style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [color.withOpacity(0.3), color.withOpacity(0.1)]),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(status,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color))),
          if (isLate) ...[
            const SizedBox(height: 4),
            const Text('⏱ Late',
                style: TextStyle(fontSize: 10, color: Colors.orange))
          ],
        ]),
      ]),
    );
  }
}

class _LeaveCard extends StatelessWidget {
  final Map<String, dynamic> leave;
  const _LeaveCard({required this.leave});
  @override
  Widget build(BuildContext context) {
    final status = leave['status'] as String;
    final color = status == 'Approved'
        ? const Color(0xFF22C55E)
        : status == 'Rejected'
            ? const Color(0xFFEF4444)
            : const Color(0xFFF59E0B);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Row(children: [
        Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: color.withOpacity(0.15)),
            child: Icon(Icons.beach_access, color: color, size: 22)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(leave['type'] as String,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          Text(leave['date'] as String,
              style: const TextStyle(fontSize: 11, color: Colors.white54)),
          if ((leave['reason'] as String).isNotEmpty)
            Text(leave['reason'] as String,
                style: const TextStyle(fontSize: 11, color: Colors.white38),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
        ])),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20)),
            child: Text(
                status == 'Pending'
                    ? '⏳ Pending'
                    : status == 'Approved'
                        ? '✅ Approved'
                        : '❌ Rejected',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, color: color))),
      ]),
    );
  }
}
