import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';
import '../../../shared/widgets/app_widgets.dart';

// ── Shared store ───────────────────────────────────────────────────────────────
class TodoStore {
  static final List<Map<String, dynamic>> submissions = [];
}

// ── Office coordinates ─────────────────────────────────────────────────────────
const double _officeLat = 19.08418593557618;
const double _officeLng = 73.01567975767158;
const double _officeRadius = 200.0;

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

// ══════════════════════════════════════════════════════════════════════════════
// ADMIN ATTENDANCE SCREEN
// ══════════════════════════════════════════════════════════════════════════════
class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});
  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<UserModel> _employees = [];
  List<Map<String, dynamic>> _workReports = [];
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _loadWorkReports();
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    await Future.wait([_loadEmployees(), _loadWorkReports()]);
  }

  Future<void> _loadEmployees() async {
    try {
      final users = await ApiService.getUsers();
      if (mounted)
        setState(() {
          _employees = users.where((u) => !u.isAdmin).toList();
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadWorkReports() async {
    try {
      final approvals = await ApiService.getApprovals();
      if (mounted)
        setState(() {
          _workReports = approvals
              .where((a) => a.approvalType == 'work_report')
              .map((a) => {
                    'id': a.id,
                    'employee': a.title.replaceAll('Work Report - ', ''),
                    'date': _fmtDate(a.createdAt),
                    'tasks': a.description.split('\n'),
                    'acknowledged': a.status == 'approved',
                    'submittedAt': a.createdAt.toIso8601String(),
                    'approvalId': a.id,
                  })
              .toList();
          for (final s in TodoStore.submissions) {
            if (!_workReports.any((r) =>
                r['employee'] == s['employee'] && r['date'] == s['date'])) {
              _workReports.insert(0, s);
            }
          }
        });
    } catch (_) {}
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

  void _viewTodo(Map<String, dynamic> s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.80,
        decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(children: [
          Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                UserAvatar(name: s['employee'], size: 48),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(s['employee'],
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700)),
                      Text(s['date'],
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textMuted)),
                    ])),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        gradient: AppColors.emeraldGrad,
                        borderRadius: BorderRadius.circular(20)),
                    child: const Text('Submitted ✅',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w700))),
              ])),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                const Text('Daily Work Report',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text('${(s['tasks'] as List).length} tasks',
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700))),
              ])),
          const SizedBox(height: 12),
          Expanded(
              child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: (s['tasks'] as List).length,
            itemBuilder: (ctx, i) {
              final task = s['tasks'][i] as String;
              return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: AppColors.surfaceVar,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border)),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                                gradient: AppColors.emeraldGrad,
                                shape: BoxShape.circle),
                            child: const Icon(Icons.check_rounded,
                                color: Colors.white, size: 14)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(task,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500))),
                      ]));
            },
          )),
          Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, MediaQuery.of(context).padding.bottom + 16),
              child: Row(children: [
                Expanded(
                    child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'))),
                const SizedBox(width: 12),
                Expanded(
                    child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                            gradient: AppColors.emeraldGrad,
                            borderRadius: BorderRadius.circular(14)),
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            Navigator.pop(context);
                            setState(() => s['acknowledged'] = true);
                            if (s['approvalId'] != null) {
                              try {
                                await ApiService.updateApprovalStatus(
                                    s['approvalId'], 'approved');
                              } catch (_) {}
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('✅ Work report acknowledged!'),
                                    backgroundColor: AppColors.online,
                                    behavior: SnackBarBehavior.floating));
                          },
                          icon: const Icon(Icons.thumb_up_rounded, size: 16),
                          label: const Text('Acknowledge'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14))),
                        ))),
              ])),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;
    final now = DateTime.now();
    final present = _employees.where((e) => e.status == 'online').length;
    final absent = _employees.length - present;
    final newReports =
        _workReports.where((t) => t['acknowledged'] != true).length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Attendance',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          Text('${now.day}/${now.month}/${now.year} — Live Status',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: themeColor,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: themeColor,
          tabs: [
            const Tab(text: 'Attendance'),
            Tab(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Work Reports'),
              if (newReports > 0) ...[
                const SizedBox(width: 6),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppColors.busy,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text('$newReports',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700))),
              ],
            ])),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tab, children: [
              // Attendance Tab
              Column(children: [
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: [
                                themeColor,
                                themeColor.withOpacity(0.8),
                                AppColors.purple
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                                color: themeColor.withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8))
                          ]),
                      child: Row(children: [
                        _AttStat('${_employees.length}', 'Total', Colors.white),
                        Container(
                            width: 1,
                            height: 50,
                            color: Colors.white.withOpacity(0.3)),
                        _AttStat('$present', 'Present', Colors.white),
                        Container(
                            width: 1,
                            height: 50,
                            color: Colors.white.withOpacity(0.3)),
                        _AttStat('$absent', 'Absent', Colors.white),
                      ]),
                    )),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              shape: BoxShape.circle, color: AppColors.online)),
                      const SizedBox(width: 6),
                      Text('Present ($present)',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.online)),
                      const SizedBox(width: 16),
                      Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              shape: BoxShape.circle, color: AppColors.busy)),
                      const SizedBox(width: 6),
                      Text('Absent ($absent)',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.busy)),
                    ])),
                const SizedBox(height: 12),
                Expanded(
                    child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _employees.length,
                  itemBuilder: (ctx, i) {
                    final e = _employees[i];
                    final isHere = e.status == 'online';
                    return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: isHere
                                    ? AppColors.online.withOpacity(0.25)
                                    : AppColors.border),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3))
                            ]),
                        child: Row(children: [
                          Stack(children: [
                            UserAvatar(
                                name: e.name, size: 46, status: e.status),
                            if (isHere)
                              Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                          color: AppColors.online,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: Colors.white, width: 2)))),
                          ]),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(e.name,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)),
                                Text('${e.role} · ${e.department}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textMuted)),
                                Text(e.email,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textMuted)),
                              ])),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                        color: (isHere
                                                ? AppColors.online
                                                : AppColors.busy)
                                            .withOpacity(0.1),
                                        borderRadius:
                                            BorderRadius.circular(20)),
                                    child: Text(isHere ? 'Present' : 'Absent',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: isHere
                                                ? AppColors.online
                                                : AppColors.busy))),
                                const SizedBox(height: 4),
                                Text(e.lastSeenText,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: isHere
                                            ? AppColors.online
                                            : AppColors.textMuted)),
                              ]),
                        ]));
                  },
                )),
              ]),

              // Work Reports Tab
              _workReports.isEmpty
                  ? Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                  color: AppColors.surfaceVar,
                                  borderRadius: BorderRadius.circular(24)),
                              child: const Icon(Icons.assignment_outlined,
                                  size: 40, color: AppColors.textMuted)),
                          const SizedBox(height: 16),
                          const Text('No work reports yet',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary)),
                          const SizedBox(height: 8),
                          const Text('Reports appear after employees check out',
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.textMuted),
                              textAlign: TextAlign.center),
                        ]))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _workReports.length,
                      itemBuilder: (ctx, i) {
                        final s = _workReports[i];
                        final acknowledged = s['acknowledged'] == true;
                        return GestureDetector(
                            onTap: () => _viewTodo(s),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: acknowledged
                                          ? AppColors.border
                                          : AppColors.online.withOpacity(0.4)),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2))
                                  ]),
                              child: Row(children: [
                                UserAvatar(name: s['employee'], size: 46),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Row(children: [
                                        Text(s['employee'],
                                            style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700)),
                                        if (!acknowledged) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                              width: 8,
                                              height: 8,
                                              decoration: const BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: AppColors.busy))
                                        ],
                                      ]),
                                      Text(s['date'],
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textMuted)),
                                      const SizedBox(height: 3),
                                      Text(
                                          '${(s['tasks'] as List).length} tasks completed',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.online,
                                              fontWeight: FontWeight.w600)),
                                    ])),
                                Column(children: [
                                  Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                          color: acknowledged
                                              ? AppColors.online
                                                  .withOpacity(0.1)
                                              : AppColors.primary
                                                  .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(20)),
                                      child: Text(
                                          acknowledged ? '✅ Done' : 'New',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: acknowledged
                                                  ? AppColors.online
                                                  : AppColors.primary,
                                              fontWeight: FontWeight.w700))),
                                  const SizedBox(height: 4),
                                  const Icon(Icons.arrow_forward_ios_rounded,
                                      size: 12, color: AppColors.textMuted),
                                ]),
                              ]),
                            ));
                      }),
            ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// EMPLOYEE ATTENDANCE SCREEN
// ══════════════════════════════════════════════════════════════════════════════
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
  double _currentLat = 0;
  double _currentLng = 0;
  String _tab = 'monthly';
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _leaveRequests = [];
  Timer? _refreshTimer;
  Timer? _clockTimer;
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
    _pulseAnim = Tween(begin: 1.0, end: 1.08)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _loadAttendance();
    _loadLeaveRequests();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _loadLeaveRequests();
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _refreshTimer?.cancel();
    _clockTimer?.cancel();
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
          if (_checkedIn && list.first.checkIn != null)
            _checkInTime = list.first.checkIn!.toLocal();
        });
    } catch (_) {}
  }

  Future<void> _loadLeaveRequests() async {
    try {
      final approvals = await ApiService.getApprovals();
      if (mounted)
        setState(() {
          _leaveRequests = approvals
              .where((a) => a.approvalType != 'work_report')
              .map((a) => {
                    'date':
                        '${a.createdAt.day}/${a.createdAt.month}/${a.createdAt.year}',
                    'type':
                        a.approvalType.isNotEmpty ? a.approvalType : a.title,
                    'status': a.status == 'approved'
                        ? 'Approved'
                        : a.status == 'rejected'
                            ? 'Rejected'
                            : 'Pending',
                    'reason': a.description,
                    'approver': a.approverName,
                  })
              .toList();
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

  Future<void> _detectLocation() async {
    setState(() {
      _locLoading = true;
      _locationStatus = 'Getting GPS...';
    });
    try {
      bool svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) {
        setState(() {
          _locLoading = false;
          _locationVerified = false;
          _locationStatus = '❌ GPS is off';
        });
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
          _locationStatus = '❌ Permission denied';
        });
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
            ? '✅ At office (${dist.toStringAsFixed(0)}m)'
            : '❌ Not at office (${dist.toStringAsFixed(0)}m away)';
      });
    } catch (e) {
      setState(() {
        _locLoading = false;
        _locationVerified = false;
        _locationStatus = '❌ Could not get location';
      });
    }
  }

  Future<void> _checkIn() async {
    if (!_locationVerified) {
      _snack('📍 Verify location first', Colors.orange);
      return;
    }
    setState(() => _loading = true);
    try {
      final now = DateTime.now();
      final rec = await ApiService.checkIn(_locationStatus);
      setState(() {
        _checkedIn = true;
        _checkInTime = (rec.checkIn ?? now).toLocal();
        _checkOutTime = null;
        _loading = false;
      });
      _snack('✅ Checked in at ${_fmtTime(_checkInTime!)}', AppColors.online);
    } catch (e) {
      setState(() => _loading = false);
      _snack('Check-in failed: $e', AppColors.busy);
    }
  }

  Future<void> _checkOut() async {
    if (mounted) _showTodoPopup();
  }

  void _showTodoPopup() {
    final user = context.read<AuthProvider>().user;
    final tasks = <TextEditingController>[TextEditingController()];
    bool submitting = false;

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
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(28))),
                child: Column(children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    decoration: BoxDecoration(
                        gradient: AppColors.emeraldGrad,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(28))),
                    child: Column(children: [
                      Center(
                          child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(2)))),
                      const SizedBox(height: 16),
                      Row(children: [
                        Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle),
                            child: const Icon(
                                Icons.assignment_turned_in_rounded,
                                color: Colors.white,
                                size: 24)),
                        const SizedBox(width: 12),
                        const Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('Daily Work Report',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800)),
                              Text('Submit before checking out',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 13)),
                            ])),
                      ]),
                    ]),
                  ),
                  Expanded(
                      child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                        const Text('What did you work on today?',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 12),
                        ...tasks.asMap().entries.map((entry) => Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                      width: 28,
                                      height: 28,
                                      margin: const EdgeInsets.only(
                                          top: 10, right: 8),
                                      decoration: BoxDecoration(
                                          gradient: AppColors.emeraldGrad,
                                          shape: BoxShape.circle),
                                      child: Center(
                                          child: Text('${entry.key + 1}',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight:
                                                      FontWeight.w700)))),
                                  Expanded(
                                      child: TextField(
                                          controller: entry.value,
                                          maxLines: 2,
                                          decoration: InputDecoration(
                                              hintText:
                                                  'Describe task ${entry.key + 1}...',
                                              border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: const BorderSide(
                                                      color: AppColors.border)),
                                              focusedBorder: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: const BorderSide(
                                                      color: AppColors.online,
                                                      width: 1.5)),
                                              filled: true,
                                              fillColor: AppColors.surfaceVar,
                                              contentPadding:
                                                  const EdgeInsets.all(12)))),
                                  if (tasks.length > 1)
                                    IconButton(
                                        icon: const Icon(
                                            Icons.remove_circle_outline,
                                            color: AppColors.busy,
                                            size: 20),
                                        onPressed: () => setS(
                                            () => tasks.removeAt(entry.key))),
                                ]))),
                        GestureDetector(
                            onTap: () =>
                                setS(() => tasks.add(TextEditingController())),
                            child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                    color: AppColors.online.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color:
                                            AppColors.online.withOpacity(0.2))),
                                child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_rounded,
                                          color: AppColors.online, size: 18),
                                      SizedBox(width: 6),
                                      Text('Add Another Task',
                                          style: TextStyle(
                                              color: AppColors.online,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600)),
                                    ]))),
                      ])),
                  Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16,
                          MediaQuery.of(context).padding.bottom + 16),
                      child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: submitting
                                ? null
                                : () async {
                                    final taskList = tasks
                                        .map((c) => c.text.trim())
                                        .where((t) => t.isNotEmpty)
                                        .toList();
                                    if (taskList.isEmpty) {
                                      _snack('Add at least one task',
                                          Colors.orange);
                                      return;
                                    }
                                    setS(() => submitting = true);
                                    try {
                                      await ApiService.createApproval({
                                        'title':
                                            'Work Report - ${user?.name ?? 'Employee'}',
                                        'approval_type': 'work_report',
                                        'description': taskList.join('\n'),
                                      });
                                    } catch (_) {}
                                    try {
                                      await ApiService.checkOut();
                                    } catch (_) {}
                                    final now = DateTime.now();
                                    if (mounted) {
                                      setState(() {
                                        _checkOutTime = now;
                                        _checkedIn = false;
                                      });
                                      Navigator.pop(context);
                                      _snack(
                                          '📋 Work report sent! Checked out at ${_fmtTime(now)}',
                                          AppColors.online);
                                      _loadAttendance();
                                    }
                                  },
                            icon: submitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.send_rounded, size: 18),
                            label: Text(
                                submitting
                                    ? 'Submitting...'
                                    : 'Submit & Check Out',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))),
                          ))),
                ]),
              )),
    ).whenComplete(() {
      // FIX BUG #58: dispose all dynamically-created task controllers when popup closes
      for (final c in tasks) {
        c.dispose();
      }
    });
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16)));
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
              color: Colors.white,
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
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                const Text('Apply Leave',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
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
                            child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                    gradient: leaveType == t
                                        ? AppColors.primaryGrad
                                        : null,
                                    color: leaveType == t
                                        ? null
                                        : AppColors.surfaceVar,
                                    borderRadius: BorderRadius.circular(20)),
                                child: Text(t,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: leaveType == t
                                            ? Colors.white
                                            : AppColors.textSecondary)))))
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
                                  color: AppColors.surfaceVar,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.border)),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('FROM',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.textMuted,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 4),
                                    Text(
                                        '${from.day}/${from.month}/${from.year}',
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700)),
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
                                  color: AppColors.surfaceVar,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.border)),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('TO',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.textMuted,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 4),
                                    Text('${to.day}/${to.month}/${to.year}',
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700)),
                                  ])))),
                ]),
                const SizedBox(height: 16),
                const Text('Send To *',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (admins.isEmpty)
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Loading admins...',
                          style: TextStyle(color: AppColors.textMuted)))
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
                                  ? AppColors.primary.withOpacity(0.08)
                                  : AppColors.surfaceVar,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: approverId == a['id']
                                      ? AppColors.primary
                                      : AppColors.border)),
                          child: Row(children: [
                            CircleAvatar(
                                radius: 18,
                                backgroundColor:
                                    AppColors.primary.withOpacity(0.1),
                                child: Text(a['name']![0].toUpperCase(),
                                    style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w800))),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(a['name']!,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600))),
                            if (approverId == a['id'])
                              const Icon(Icons.check_circle,
                                  color: AppColors.primary, size: 20),
                          ])))),
                const SizedBox(height: 12),
                TextField(
                    controller: reasonCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                        hintText: 'Reason for leave...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: AppColors.border)))),
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
                          if (context.mounted) Navigator.pop(context);
                          _snack('📋 Leave sent to $approverName!',
                              AppColors.primary);
                          _loadLeaveRequests();
                        } catch (e) {
                          _snack('Failed: $e', AppColors.busy);
                        }
                      },
                      style: ElevatedButton.styleFrom(
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
    ).whenComplete(() {
      // FIX BUG #64: dispose leave reason controller when modal closes
      reasonCtrl.dispose();
    });
  }

  String _fmtTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    return '$h:${local.minute.toString().padLeft(2, '0')} ${local.hour < 12 ? 'AM' : 'PM'}';
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
    final end = _checkOutTime ?? DateTime.now();
    final d = end.difference(_checkInTime!);
    if (d.isNegative) return '0h 0m';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          floating: true,
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          title: const Text('Attendance',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
          actions: [
            IconButton(
                icon: _locLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location_rounded),
                onPressed: _detectLocation),
            IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () {
                  _loadAttendance();
                  _loadLeaveRequests();
                }),
          ],
        ),
        SliverToBoxAdapter(
            child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: _checkedIn ? themeColor : AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: _checkedIn ? themeColor : AppColors.border),
                  boxShadow: [
                    BoxShadow(
                        color: (_checkedIn ? themeColor : Colors.black)
                            .withOpacity(0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      Row(children: [
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  _checkedIn ? 'Working Now' : 'Not Checked In',
                                  style: TextStyle(
                                      color: _checkedIn
                                          ? Colors.white70
                                          : AppColors.textMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(height: 2),
                              Text(timeStr,
                                  style: TextStyle(
                                      color: _checkedIn
                                          ? Colors.white
                                          : AppColors.textPrimary,
                                      fontSize: 36,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -1)),
                              Text('Tap 📍 to verify, then Check In',
                                  style: TextStyle(
                                      color: _checkedIn
                                          ? Colors.white54
                                          : AppColors.textMuted,
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
                                        color: _checkedIn
                                            ? Colors.white
                                            : (_locationVerified
                                                ? themeColor
                                                : AppColors.surfaceVar),
                                        boxShadow: [
                                          BoxShadow(
                                              color: (_checkedIn
                                                      ? Colors.white
                                                      : themeColor)
                                                  .withOpacity(0.3),
                                              blurRadius: 12)
                                        ]),
                                    child: _loading
                                        ? Padding(
                                            padding: const EdgeInsets.all(20),
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                color: _checkedIn
                                                    ? themeColor
                                                    : Colors.white))
                                        : Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                                Icon(
                                                    _checkedIn
                                                        ? Icons.stop_rounded
                                                        : Icons
                                                            .play_arrow_rounded,
                                                    color: _checkedIn
                                                        ? themeColor
                                                        : (_locationVerified
                                                            ? Colors.white
                                                            : AppColors
                                                                .textMuted),
                                                    size: 32),
                                                Text(_checkedIn ? 'OUT' : 'IN',
                                                    style: TextStyle(
                                                        color: _checkedIn
                                                            ? themeColor
                                                            : (_locationVerified
                                                                ? Colors.white
                                                                : AppColors
                                                                    .textMuted),
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w800)),
                                              ])))),
                      ]),
                      if (_checkedIn) ...[
                        const SizedBox(height: 12),
                        Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12)),
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
                                ])),
                      ],
                      const SizedBox(height: 12),
                      Row(children: [
                        _TimeChip(
                            'CHECK IN',
                            _checkInTime != null
                                ? _fmtTime(_checkInTime!)
                                : '—',
                            _checkedIn),
                        const SizedBox(width: 8),
                        _TimeChip(
                            'CHECK OUT',
                            _checkOutTime != null
                                ? _fmtTime(_checkOutTime!)
                                : '—',
                            _checkedIn),
                        const SizedBox(width: 8),
                        _TimeChip('DURATION', _duration(), _checkedIn),
                      ]),
                      const SizedBox(height: 10),
                      GestureDetector(
                          onTap: _detectLocation,
                          child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                  color: _locationVerified
                                      ? AppColors.online
                                          .withOpacity(_checkedIn ? 0.2 : 0.1)
                                      : (_checkedIn
                                          ? Colors.white.withOpacity(0.1)
                                          : AppColors.surfaceVar),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: _locationVerified
                                          ? AppColors.online.withOpacity(0.4)
                                          : AppColors.border)),
                              child: Row(children: [
                                _locLoading
                                    ? SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: _checkedIn
                                                ? Colors.white
                                                : AppColors.primary))
                                    : Icon(
                                        _locationVerified
                                            ? Icons.location_on_rounded
                                            : Icons.location_searching_rounded,
                                        color: _locationVerified
                                            ? AppColors.online
                                            : (_checkedIn
                                                ? Colors.white54
                                                : AppColors.textMuted),
                                        size: 14),
                                const SizedBox(width: 6),
                                Flexible(
                                    child: Text(_locationStatus,
                                        style: TextStyle(
                                            color: _checkedIn
                                                ? Colors.white
                                                : AppColors.textSecondary,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis)),
                              ]))),
                      const SizedBox(height: 10),
                      GestureDetector(
                          onTap: _applyLeave,
                          child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                  color: _checkedIn
                                      ? Colors.white.withOpacity(0.1)
                                      : AppColors.surfaceVar,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: _checkedIn
                                          ? Colors.white.withOpacity(0.2)
                                          : AppColors.border)),
                              child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.beach_access_outlined,
                                        color: _checkedIn
                                            ? Colors.white
                                            : AppColors.textSecondary,
                                        size: 16),
                                    const SizedBox(width: 8),
                                    Text('Apply for Leave',
                                        style: TextStyle(
                                            color: _checkedIn
                                                ? Colors.white
                                                : AppColors.textSecondary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700)),
                                  ]))),
                    ])),
              )),
          const SizedBox(height: 16),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                _StatCard('Present', '$_presentCount', AppColors.online,
                    Icons.check_circle_outline),
                const SizedBox(width: 10),
                _StatCard('Leave', '$_leaveCount', AppColors.away,
                    Icons.beach_access_outlined),
                const SizedBox(width: 10),
                _StatCard('Total', '${_records.length}', themeColor,
                    Icons.calendar_month_outlined),
              ])),
          const SizedBox(height: 16),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: AppColors.surfaceVar,
                    borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  _TabBtn('Monthly', _tab == 'monthly', themeColor,
                      () => setState(() => _tab = 'monthly')),
                  _TabBtn('Leave Requests', _tab == 'leave', themeColor,
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
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                          color: AppColors.online.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('$_presentCount Present',
                          style: const TextStyle(
                              color: AppColors.online,
                              fontSize: 11,
                              fontWeight: FontWeight.w700))),
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
                            color: themeColor.withOpacity(0.1)),
                        child: Icon(Icons.calendar_today_outlined,
                            size: 32, color: themeColor)),
                    const SizedBox(height: 16),
                    const Text('No records yet',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    const Text('Verify location then tap IN to check in',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.textMuted),
                        textAlign: TextAlign.center),
                  ]))
            else
              ..._records
                  .map((a) => _RecordCard(record: a, themeColor: themeColor)),
          ],
          if (_tab == 'leave') ...[
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  const Text('Leave Requests',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  GestureDetector(
                      onTap: _applyLeave,
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                              color: themeColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.add, color: themeColor, size: 14),
                            const SizedBox(width: 4),
                            Text('Apply',
                                style: TextStyle(
                                    color: themeColor,
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
                            color: AppColors.away.withOpacity(0.1)),
                        child: const Icon(Icons.beach_access_outlined,
                            size: 30, color: AppColors.away)),
                    const SizedBox(height: 12),
                    const Text('No leave requests yet',
                        style: TextStyle(
                            fontSize: 14, color: AppColors.textSecondary)),
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

// ── Shared widgets ─────────────────────────────────────────────────────────────
class _AttStat extends StatelessWidget {
  final String value, label;
  final Color color;
  const _AttStat(this.value, this.label, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
          child: Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 28, fontWeight: FontWeight.w800, color: color)),
        Text(label,
            style: TextStyle(fontSize: 12, color: color.withOpacity(0.8))),
      ]));
}

class _TimeChip extends StatelessWidget {
  final String label, value;
  final bool dark;
  const _TimeChip(this.label, this.value, this.dark);
  @override
  Widget build(BuildContext context) => Expanded(
          child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
            color: dark ? Colors.white.withOpacity(0.12) : AppColors.surfaceVar,
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: dark ? Colors.white12 : AppColors.border)),
        child: Column(children: [
          Text(label,
              style: TextStyle(
                  color: dark ? Colors.white38 : AppColors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: dark ? Colors.white : AppColors.textPrimary,
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
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)
            ]),
        child: Column(children: [
          Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: color.withOpacity(0.12)),
              child: Icon(icon, color: color, size: 16)),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ]),
      ));
}

class _TabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _TabBtn(this.label, this.active, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => Expanded(
      child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: active ? color : Colors.transparent,
                  borderRadius: BorderRadius.circular(10)),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.white : AppColors.textMuted)))));
}

class _RecordCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final Color themeColor;
  const _RecordCard({required this.record, required this.themeColor});
  @override
  Widget build(BuildContext context) {
    final status = record['status'] as String;
    final isLate = record['isLate'] as bool? ?? false;
    final color = status == 'Present' ? AppColors.online : AppColors.away;
    return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)
            ]),
        child: Row(children: [
          Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: color.withOpacity(0.1)),
              child: Icon(
                  status == 'Present'
                      ? Icons.check_rounded
                      : Icons.beach_access,
                  color: color,
                  size: 22)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(record['date'] as String,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                    status == 'Present'
                        ? '${record['in']} → ${record['out']}  ·  ${record['hours']}'
                        : 'Absent',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
              ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(status,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: color))),
            if (isLate) ...[
              const SizedBox(height: 4),
              const Text('⏱ Late',
                  style: TextStyle(fontSize: 10, color: AppColors.away))
            ],
          ]),
        ]));
  }
}

class _LeaveCard extends StatelessWidget {
  final Map<String, dynamic> leave;
  const _LeaveCard({required this.leave});
  @override
  Widget build(BuildContext context) {
    final status = leave['status'] as String;
    final color = status == 'Approved'
        ? AppColors.online
        : status == 'Rejected'
            ? AppColors.busy
            : AppColors.away;
    return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)
            ]),
        child: Row(children: [
          Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: color.withOpacity(0.1)),
              child: Icon(Icons.beach_access, color: color, size: 22)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(leave['type'] as String,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                Text(leave['date'] as String,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
                if ((leave['reason'] as String).isNotEmpty)
                  Text(leave['reason'] as String,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ])),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(
                  status == 'Pending'
                      ? '⏳ Pending'
                      : status == 'Approved'
                          ? '✅ Approved'
                          : '❌ Rejected',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color))),
        ]));
  }
}
