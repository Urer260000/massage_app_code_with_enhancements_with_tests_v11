import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../theme/deco.dart';

/// Pick a therapist, day and time for [service] and reserve it.
/// With [rescheduling], moves that reservation instead. Pops `true` on success.
class BookingScreen extends StatefulWidget {
  const BookingScreen({
    super.key,
    required this.api,
    required this.service,
    this.rescheduling,
    this.cancelCutoffHours = 24,
  });
  final ApiClient api;
  final Service service;
  final Appointment? rescheduling;
  final int cancelCutoffHours;

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final _notes = TextEditingController();
  List<Therapist> _therapists = const [];
  String? _therapistId; // null = whoever is free
  List<DayAvailability>? _days;
  String? _day;
  List<Slot>? _slots;
  Slot? _slot;
  String? _pressure;
  bool _saving = false;
  bool _waitlisting = false;
  String? _error;
  String? _loadError;

  bool get _isReschedule => widget.rescheduling != null;

  @override
  void initState() {
    super.initState();
    _therapistId = widget.rescheduling?.therapistId;
    _loadTherapists();
    _loadDays();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadTherapists() async {
    try {
      final list = await widget.api.therapists(widget.service.id);
      if (mounted) setState(() => _therapists = list);
    } on ApiException {
      // The picker just stays on "Any"; booking still works.
    }
  }

  Future<void> _loadDays() async {
    setState(() {
      _loadError = null;
      _days = null;
    });
    try {
      final days = await widget.api.availabilityDays(widget.service.id, therapistId: _therapistId);
      if (!mounted) return;
      final keep = days.where((d) => d.date == _day).firstOrNull;
      final first = days.where((d) => d.available).firstOrNull ?? days.firstOrNull;
      setState(() => _days = days);
      final pick = keep ?? first;
      if (pick != null) await _selectDay(pick.date);
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  Future<void> _selectDay(String day) async {
    setState(() {
      _day = day;
      _slots = null;
      _error = null;
    });
    try {
      final slots = await widget.api.availability(widget.service.id, day, therapistId: _therapistId);
      if (!mounted || _day != day) return;
      setState(() {
        _slots = slots;
        final same = slots.where((s) => s.available && s.startsAt == _slot?.startsAt).firstOrNull;
        _slot = same ?? slots.where((s) => s.available).firstOrNull;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  void _selectTherapist(String? id) {
    if (id == _therapistId) return;
    setState(() => _therapistId = id);
    _loadDays();
  }

  Future<void> _confirm() async {
    final slot = _slot;
    if (slot == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_isReschedule) {
        await widget.api.reschedule(widget.rescheduling!.id, slot.startsAt, therapistId: _therapistId);
      } else {
        await widget.api.book(
          widget.service.id,
          slot.startsAt,
          therapistId: _therapistId,
          notes: _notes.text.trim(),
          pressure: _pressure,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isReschedule ? 'Reservation moved. See you then!' : '${widget.service.name} reserved. See you soon!',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      // Someone else may have just taken it; show the latest times.
      if (e.statusCode == 409 && _day != null) await _selectDay(_day!);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _joinWaitlist() async {
    final day = _day;
    if (day == null) return;
    setState(() => _waitlisting = true);
    try {
      final message = await widget.api.joinWaitlist(widget.service.id, day);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _waitlisting = false);
    }
  }

  String get _therapistLabel {
    if (_therapistId == null) return 'First available therapist';
    return _therapists.where((t) => t.id == _therapistId).firstOrNull?.name ?? 'Your therapist';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final slots = _slots;
    final dayFull = slots != null && !slots.any((x) => x.available);

    return Scaffold(
      appBar: AppBar(title: Text(_isReschedule ? 'RESCHEDULE' : 'RESERVE', style: Deco.label(size: 14))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Center(child: Medallion(icon: serviceIcon(s.id), size: 64)),
          const SizedBox(height: 14),
          if (s.signature != null)
            Text(s.signature!.toUpperCase(), textAlign: TextAlign.center, style: Deco.label(size: 12)),
          const SizedBox(height: 4),
          Text(s.name, textAlign: TextAlign.center, style: Deco.heading(size: 34)),
          const SizedBox(height: 8),
          Text(
            '${s.durationMinutes} MIN  ·  ${money(s.price)}',
            textAlign: TextAlign.center,
            style: Deco.label(size: 12, color: Deco.muted),
          ),
          const SizedBox(height: 18),
          const DecoDivider(),
          const SizedBox(height: 22),
          if (_therapists.isNotEmpty) ...[
            const SectionTitle('YOUR THERAPIST'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Choice(
                  key: const Key('therapist-any'),
                  label: 'ANY',
                  selected: _therapistId == null,
                  onTap: () => _selectTherapist(null),
                ),
                for (final t in _therapists)
                  _Choice(
                    key: Key('therapist-${t.id}'),
                    label: t.name.toUpperCase(),
                    selected: _therapistId == t.id,
                    onTap: () => _selectTherapist(t.id),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _therapists.where((t) => t.id == _therapistId).firstOrNull?.bio ??
                  "We'll match you with whoever is free at your time.",
              style: const TextStyle(color: Deco.muted, fontSize: 14),
            ),
            const SizedBox(height: 24),
          ],
          const SectionTitle('SELECT A DATE'),
          const SizedBox(height: 12),
          if (_loadError != null)
            _InlineError(message: _loadError!, onRetry: _loadDays)
          else if (_days == null)
            const SizedBox(height: 96, child: Center(child: CircularProgressIndicator()))
          else
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _days!.length,
                separatorBuilder: (context, i) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final d = _days![i];
                  return _DateTile(
                    date: parseDay(d.date),
                    selected: d.date == _day,
                    available: d.available,
                    onTap: () => _selectDay(d.date),
                  );
                },
              ),
            ),
          const SizedBox(height: 24),
          const SectionTitle('SELECT A TIME'),
          const SizedBox(height: 12),
          if (_day != null && slots == null && _loadError == null)
            const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()))
          else if (dayFull)
            _FullyBooked(onWaitlist: _isReschedule ? null : _joinWaitlist, loading: _waitlisting)
          else if (slots != null)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final slot in slots.where((x) => !x.past))
                  _TimeChip(
                    key: Key('slot-${slot.time}'),
                    label: timeLabel(context, slot.time),
                    selected: slot.startsAt == _slot?.startsAt,
                    enabled: slot.available,
                    onTap: () => setState(() => _slot = slot),
                  ),
              ],
            ),
          if (!_isReschedule) ...[
            const SizedBox(height: 24),
            const SectionTitle('FOR YOUR THERAPIST'),
            const SizedBox(height: 12),
            Text('Pressure', style: Deco.label(size: 11, color: Deco.muted)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: [
                for (final p in const ['light', 'medium', 'firm'])
                  _Choice(
                    label: p.toUpperCase(),
                    selected: _pressure == p,
                    onTap: () => setState(() => _pressure = _pressure == p ? null : p),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('notes'),
              controller: _notes,
              maxLength: 500,
              maxLines: 3,
              minLines: 2,
              style: const TextStyle(color: Deco.cream, fontSize: 15),
              decoration: decoInput('INJURIES, ALLERGIES, PREGNANCY…', Icons.healing_outlined),
            ),
          ],
          const SizedBox(height: 18),
          DecoFrame(
            highlight: true,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_isReschedule ? 'NEW TIME' : 'YOUR RESERVATION', style: Deco.label(size: 11)),
                const SizedBox(height: 10),
                Text(s.name, style: Deco.heading(size: 22)),
                const SizedBox(height: 6),
                Text(
                  _slot == null || _day == null
                      ? 'Choose a time'
                      : '${fullDate(context, _day!)} at ${timeLabel(context, _slot!.time)}',
                  style: const TextStyle(color: Deco.cream, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(_therapistLabel, style: const TextStyle(color: Deco.muted, fontSize: 14)),
                const SizedBox(height: 14),
                Container(height: 1, color: Deco.goldDeep.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('TOTAL', style: Deco.label(size: 12, color: Deco.muted)),
                    const Spacer(),
                    Text(money(s.price), style: Deco.price(size: 26)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Pay at the spa. Free cancellation until ${widget.cancelCutoffHours} hours before.',
                  style: const TextStyle(color: Deco.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Deco.danger),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: GoldButton(
            key: const Key('confirm'),
            label: _isReschedule ? 'MOVE RESERVATION' : 'CONFIRM RESERVATION',
            loading: _saving,
            onPressed: _slot == null ? null : _confirm,
          ),
        ),
      ),
    );
  }
}

class _FullyBooked extends StatelessWidget {
  const _FullyBooked({required this.onWaitlist, required this.loading});
  final VoidCallback? onWaitlist;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Fully booked this day.', style: TextStyle(color: Deco.cream, fontSize: 15)),
        if (onWaitlist != null) ...[
          const SizedBox(height: 6),
          const Text(
            "Join the waitlist and we'll email you if a spot opens.",
            style: TextStyle(color: Deco.muted, fontSize: 14),
          ),
          const SizedBox(height: 12),
          GoldOutlineButton(
            key: const Key('waitlist'),
            label: loading ? 'JOINING…' : 'JOIN WAITLIST',
            onPressed: loading ? null : onWaitlist,
          ),
        ],
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(message, style: const TextStyle(color: Deco.danger)),
        ),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(foregroundColor: Deco.gold),
          child: const Text('Try again'),
        ),
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.date, required this.selected, required this.available, required this.onTap});
  final DateTime date;
  final bool selected;
  final bool available;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Deco.ink : (available ? Deco.cream : Deco.muted.withValues(alpha: 0.55));
    final day = MaterialLocalizations.of(context).formatFullDate(date);
    final label = available ? day : '$day, fully booked';
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: motion(context, 180),
          width: 64,
          decoration: BoxDecoration(
            gradient: selected ? Deco.goldGradient : null,
            color: selected ? null : Deco.panel,
            border: Border.all(
              color: selected ? Deco.goldBright : Deco.goldDeep.withValues(alpha: available ? 0.7 : 0.25),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(weekdayAbbr[date.weekday - 1], style: Deco.label(size: 10, color: fg)),
              const SizedBox(height: 4),
              Text(
                '${date.day}',
                style: TextStyle(fontFamily: Deco.display, fontSize: 26, color: fg),
              ),
              const SizedBox(height: 2),
              Text(available ? monthAbbr[date.month - 1] : 'FULL', style: Deco.label(size: 10, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({super.key, required this.label, required this.selected, required this.enabled, required this.onTap});
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Deco.ink : (enabled ? Deco.cream : Deco.muted.withValues(alpha: 0.5));
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: enabled ? label : '$label, unavailable',
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: motion(context, 160),
          width: 96,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: selected ? Deco.goldGradient : null,
            color: selected ? null : Deco.panel,
            border: Border.all(
              color: selected ? Deco.goldBright : Deco.goldDeep.withValues(alpha: enabled ? 0.7 : 0.2),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: fg,
              fontSize: 14,
              decoration: enabled ? null : TextDecoration.lineThrough,
              fontVariations: const [FontVariation('wght', 600)],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small gold toggle used for therapist and pressure choices.
class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: motion(context, 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: selected ? Deco.goldGradient : null,
            color: selected ? null : Deco.panel,
            border: Border.all(color: selected ? Deco.goldBright : Deco.goldDeep.withValues(alpha: 0.7)),
          ),
          child: Text(label, style: Deco.label(size: 11, color: selected ? Deco.ink : Deco.cream)),
        ),
      ),
    );
  }
}
