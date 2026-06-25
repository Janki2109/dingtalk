import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/auth_provider.dart';
import '../../../shared/widgets/app_widgets.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _selected = DateTime.now();
  DateTime _focused = DateTime.now();

  final List<_Event> _events = [];
  final List<_Event> _history = [];
  bool _showHistory = false;

  final _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];
  final _weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  int get _daysInMonth =>
      DateUtils.getDaysInMonth(_focused.year, _focused.month);
  int get _firstWeekday =>
      DateTime(_focused.year, _focused.month, 1).weekday - 1;

  bool _isToday(int d) =>
      _focused.year == DateTime.now().year &&
      _focused.month == DateTime.now().month &&
      d == DateTime.now().day;

  bool _isSelected(int d) =>
      _focused.year == _selected.year &&
      _focused.month == _selected.month &&
      d == _selected.day;

  bool _hasEvent(int d) => _events.any((e) =>
      e.date.day == d &&
      e.date.month == _focused.month &&
      e.date.year == _focused.year);

  List<_Event> get _dayEvents => _events
      .where((e) =>
          e.date.day == _selected.day &&
          e.date.month == _selected.month &&
          e.date.year == _selected.year)
      .toList();

  void _addEvent() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddEventSheet(
        selectedDate: _selected,
        onAdd: (event) {
          setState(() => _events.add(event));
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Event "${event.title}" added ✅'),
            backgroundColor: AppColors.online,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));

          // Auto-move to history when end time passes
          final now = DateTime.now();
          final endTime = event.endTime;
          final delay =
              endTime.isAfter(now) ? endTime.difference(now) : Duration.zero;

          Future.delayed(delay, () {
            if (mounted) {
              setState(() {
                _events.remove(event);
                _history.insert(0, event.copyWith(completed: true));
              });
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content:
                    Text('📋 "${event.title}" completed and moved to history'),
                backgroundColor: AppColors.online,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 3),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ));
            }
          });
        },
      ),
    );
  }

  void _deleteEvent(_Event event) {
    setState(() => _events.remove(event));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('"${event.title}" deleted'),
      backgroundColor: AppColors.busy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(slivers: [
        // ── App Bar ──────────────────────────────────────────────────────────
        SliverAppBar(
          floating: true,
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          title: const Text('Calendar',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
          actions: [
            TextButton(
              onPressed: () => setState(() {
                _selected = DateTime.now();
                _focused = DateTime.now();
              }),
              child: Text('Today',
                  style: TextStyle(
                      color: themeColor, fontWeight: FontWeight.w600)),
            ),
            // History icon with badge
            Stack(children: [
              IconButton(
                icon: const Icon(Icons.history_rounded),
                tooltip: 'Event History',
                onPressed: () => setState(() => _showHistory = !_showHistory),
              ),
              if (_history.isNotEmpty)
                Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                          color: AppColors.busy, shape: BoxShape.circle),
                      child: Center(
                          child: Text('${_history.length}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800))),
                    )),
            ]),
          ],
        ),

        // ── History Panel ─────────────────────────────────────────────────────
        if (_showHistory)
          SliverToBoxAdapter(
              child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const Icon(Icons.history_rounded,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  const Text('Completed Events',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (_history.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _history.clear()),
                      child: const Text('Clear All',
                          style:
                              TextStyle(color: AppColors.busy, fontSize: 12)),
                    ),
                ]),
              ),
              if (_history.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text('No completed events yet',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 14)),
                )
              else ...[
                ...(_history.take(5).map((e) => _HistoryTile(event: e)))
                    .toList(),
                if (_history.length > 5)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Center(
                        child: Text('+${_history.length - 5} more events',
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 12))),
                  ),
              ],
            ]),
          )),

        // ── Calendar Grid ─────────────────────────────────────────────────────
        SliverToBoxAdapter(
            child: Container(
          color: AppColors.surface,
          child: Column(children: [
            // Month navigation
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(children: [
                IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() => _focused =
                        DateTime(_focused.year, _focused.month - 1))),
                Expanded(
                    child: Text(
                        '${_months[_focused.month - 1]} ${_focused.year}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center)),
                IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => setState(() => _focused =
                        DateTime(_focused.year, _focused.month + 1))),
              ]),
            ),
            // Weekday headers
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                  children: _weekDays
                      .map((d) => Expanded(
                          child: Center(
                              child: Text(d,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textMuted)))))
                      .toList()),
            ),
            const SizedBox(height: 8),
            // Date grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7, childAspectRatio: 1),
                itemCount: _firstWeekday + _daysInMonth,
                itemBuilder: (ctx, i) {
                  if (i < _firstWeekday) return const SizedBox();
                  final day = i - _firstWeekday + 1;
                  final today = _isToday(day);
                  final selected = _isSelected(day);
                  final hasEvent = _hasEvent(day);

                  return GestureDetector(
                    onTap: () => setState(() => _selected =
                        DateTime(_focused.year, _focused.month, day)),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: selected
                                  ? themeColor
                                  : today
                                      ? themeColor.withOpacity(0.15)
                                      : null,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                                child: Text('$day',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: today || selected
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                      color: selected
                                          ? Colors.white
                                          : today
                                              ? themeColor
                                              : AppColors.textPrimary,
                                    ))),
                          ),
                          if (hasEvent)
                            Container(
                              width: 5,
                              height: 5,
                              margin: const EdgeInsets.only(top: 1),
                              decoration: BoxDecoration(
                                color: selected ? Colors.white : themeColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ]),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ]),
        )),

        // ── Day Events Header ─────────────────────────────────────────────────
        SliverToBoxAdapter(
            child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            Text(
                _isToday(_selected.day) &&
                        _selected.month == DateTime.now().month
                    ? "Today's Events"
                    : 'Events — ${_selected.day} ${_months[_selected.month - 1]}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            GestureDetector(
              onTap: _addEvent,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: themeColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text('Add Event',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
        )),

        // ── Day Events List ───────────────────────────────────────────────────
        if (_dayEvents.isEmpty)
          SliverToBoxAdapter(
              child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(children: [
              Icon(Icons.event_available,
                  size: 52, color: AppColors.textMuted.withOpacity(0.3)),
              const SizedBox(height: 12),
              const Text('No events on this day',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _addEvent,
                child: Text('+ Add an event',
                    style: TextStyle(
                        color: themeColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ))
        else
          SliverList(
              delegate: SliverChildBuilderDelegate(
            (ctx, i) => _EventCard(
              event: _dayEvents[i],
              themeColor: themeColor,
              onDelete: () => _deleteEvent(_dayEvents[i]),
            ),
            childCount: _dayEvents.length,
          )),

        const SliverToBoxAdapter(child: SizedBox(height: 90)),
      ]),
    );
  }
}

// ── Event Model ───────────────────────────────────────────────────────────────
class _Event {
  final String id, title, description, type;
  final DateTime date, startTime, endTime;
  final bool completed;
  final Color color;

  _Event({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.date,
    required this.startTime,
    required this.endTime,
    this.completed = false,
    required this.color,
  });

  _Event copyWith({bool? completed}) => _Event(
        id: id,
        title: title,
        description: description,
        type: type,
        date: date,
        startTime: startTime,
        endTime: endTime,
        completed: completed ?? this.completed,
        color: color,
      );
}

// ── Event Card — only delete, no approve ─────────────────────────────────────
class _EventCard extends StatelessWidget {
  final _Event event;
  final Color themeColor;
  final VoidCallback onDelete;

  const _EventCard({
    required this.event,
    required this.themeColor,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isOngoing = DateTime.now().isAfter(event.startTime) &&
        DateTime.now().isBefore(event.endTime);
    final isPast = DateTime.now().isAfter(event.endTime);

    return Dismissible(
      key: Key(event.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: AppColors.busy,
        child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_outline, color: Colors.white, size: 26),
              Text('Delete',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ]),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color:
                  isOngoing ? event.color.withOpacity(0.5) : AppColors.border),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(children: [
          // Color strip
          Container(
            width: 4,
            height: 80,
            decoration: BoxDecoration(
              color: event.color,
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(16)),
            ),
          ),
          // Content
          Expanded(
              child: Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(event.title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700))),
                if (isOngoing)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: AppColors.online.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('● Ongoing',
                        style: TextStyle(
                            color: AppColors.online,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                if (isPast)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: AppColors.textMuted.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('Ended',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 11)),
                  ),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.access_time, size: 12, color: event.color),
                const SizedBox(width: 4),
                Text(
                    '${formatHM(event.startTime)} – ${formatHM(event.endTime)}',
                    style: TextStyle(
                        fontSize: 12,
                        color: event.color,
                        fontWeight: FontWeight.w500)),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: event.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(event.type,
                      style: TextStyle(
                          fontSize: 10,
                          color: event.color,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
              if (event.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(event.description,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ]),
          )),
          // Only delete button — no approve/check
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.busy.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline,
                    color: AppColors.busy, size: 20),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── History Tile ──────────────────────────────────────────────────────────────
class _HistoryTile extends StatelessWidget {
  final _Event event;
  const _HistoryTile({required this.event});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.divider))),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: AppColors.online.withOpacity(0.1),
                shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_outline,
                color: AppColors.online, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(event.title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.lineThrough,
                        color: AppColors.textSecondary)),
                Text(
                    '${formatHM(event.startTime)} – ${formatHM(event.endTime)} · ${event.type}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
              ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: AppColors.online.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: const Text('Done ✅',
                style: TextStyle(
                    color: AppColors.online,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

// ── Add Event Sheet ───────────────────────────────────────────────────────────
class _AddEventSheet extends StatefulWidget {
  final DateTime selectedDate;
  final Function(_Event) onAdd;
  const _AddEventSheet({required this.selectedDate, required this.onAdd});
  @override
  State<_AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<_AddEventSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _type = 'Meeting';

  @override
  void dispose() {
    // FIX BUG #60: dispose controllers to prevent memory leak
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }
  TimeOfDay _startTime = TimeOfDay.now();
  TimeOfDay _endTime = TimeOfDay(
      hour: (TimeOfDay.now().hour + 1) % 24, minute: TimeOfDay.now().minute);
  int _colorIndex = 0;

  final _types = [
    'Meeting',
    'Task',
    'Reminder',
    'Event',
    'Holiday',
    'Personal'
  ];
  final _colors = [
    AppColors.primary,
    AppColors.accent,
    AppColors.purple,
    AppColors.orange,
    AppColors.online,
    AppColors.busy,
  ];

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked != null) {
      setState(() {
        if (isStart)
          _startTime = picked;
        else
          _endTime = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
                    borderRadius: BorderRadius.circular(2)),
              )),
              const SizedBox(height: 20),
              Row(children: [
                const Text('Add Event',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(
                    '${widget.selectedDate.day} '
                    '${[
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
                    ][widget.selectedDate.month - 1]}',
                    style: TextStyle(
                        fontSize: 14,
                        color: themeColor,
                        fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 16),

              // Title
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Event Title *',
                  prefixIcon: Icon(Icons.title),
                ),
              ),
              const SizedBox(height: 12),

              // Description
              TextField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
              const SizedBox(height: 16),

              // Time pickers
              Row(children: [
                Expanded(
                    child: GestureDetector(
                  onTap: () => _pickTime(true),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: AppColors.surfaceVar,
                        borderRadius: BorderRadius.circular(12)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Start Time',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.textMuted)),
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.access_time,
                                size: 16, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text(_startTime.format(context),
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                          ]),
                        ]),
                  ),
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: GestureDetector(
                  onTap: () => _pickTime(false),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: AppColors.surfaceVar,
                        borderRadius: BorderRadius.circular(12)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('End Time',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.textMuted)),
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.access_time,
                                size: 16, color: AppColors.busy),
                            const SizedBox(width: 6),
                            Text(_endTime.format(context),
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                          ]),
                        ]),
                  ),
                )),
              ]),
              const SizedBox(height: 16),

              // Event type
              const Text('Event Type',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _types
                    .map((t) => GestureDetector(
                          onTap: () => setState(() => _type = t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: _type == t
                                  ? themeColor
                                  : AppColors.surfaceVar,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: _type == t
                                      ? themeColor
                                      : AppColors.border),
                            ),
                            child: Text(t,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: _type == t
                                        ? Colors.white
                                        : AppColors.textSecondary)),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),

              // Color picker
              const Text('Event Color',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Row(
                  children: List.generate(
                _colors.length,
                (i) => GestureDetector(
                  onTap: () => setState(() => _colorIndex = i),
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _colors[i],
                      shape: BoxShape.circle,
                      border: _colorIndex == i
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                      boxShadow: _colorIndex == i
                          ? [
                              BoxShadow(
                                  color: _colors[i].withOpacity(0.4),
                                  blurRadius: 6,
                                  spreadRadius: 1)
                            ]
                          : null,
                    ),
                    child: _colorIndex == i
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                ),
              )),
              const SizedBox(height: 20),

              // Add button
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (_titleCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Please enter an event title'),
                                backgroundColor: AppColors.busy,
                                behavior: SnackBarBehavior.floating));
                        return;
                      }
                      final date = widget.selectedDate;
                      final start = DateTime(date.year, date.month, date.day,
                          _startTime.hour, _startTime.minute);
                      final end = DateTime(date.year, date.month, date.day,
                          _endTime.hour, _endTime.minute);
                      widget.onAdd(_Event(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        title: _titleCtrl.text.trim(),
                        description: _descCtrl.text.trim(),
                        type: _type,
                        date: date,
                        startTime: start,
                        endTime: end,
                        color: _colors[_colorIndex],
                      ));
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add Event'),
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                  )),
            ]),
      ),
    );
  }
}
