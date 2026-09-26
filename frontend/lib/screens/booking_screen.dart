import 'package:flutter/material.dart';

import '../api.dart';
import '../theme/deco.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key, required this.api, required this.service});
  final ApiClient api;
  final Service service;

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  static const _hours = [10, 11, 12, 13, 14, 15, 16, 17, 18, 19];
  static const _daysAhead = 21;

  late DateTime _day;
  int? _hour;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _day = DateTime(now.year, now.month, now.day);
    if (_slotsFor(_day).isEmpty) _day = DateTime(now.year, now.month, now.day + 1);
    _hour = _slotsFor(_day).first;
  }

  /// Hours still bookable on [day] (at least 30 minutes from now).
  List<int> _slotsFor(DateTime day) {
    final cutoff = DateTime.now().add(const Duration(minutes: 30));
    return _hours.where((h) => DateTime(day.year, day.month, day.day, h).isAfter(cutoff)).toList();
  }

  void _selectDay(DateTime day) {
    final slots = _slotsFor(day);
    setState(() {
      _day = day;
      if (!slots.contains(_hour)) _hour = slots.isEmpty ? null : slots.first;
    });
  }

  DateTime? get _startsAt => _hour == null ? null : DateTime(_day.year, _day.month, _day.day, _hour!);

  String _hourLabel(int h) =>
      MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay(hour: h, minute: 0));

  Future<void> _confirm() async {
    final start = _startsAt;
    if (start == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.book(widget.service.id, start);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.service.name} reserved. See you soon!')),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final loc = MaterialLocalizations.of(context);
    final today = DateTime.now();
    final days = List.generate(
      _daysAhead,
      (i) => DateTime(today.year, today.month, today.day + i),
    );
    final slots = _slotsFor(_day);

    return Scaffold(
      appBar: AppBar(title: Text('RESERVE', style: Deco.label(size: 14))),
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
            '${s.durationMinutes} MIN  ·  \$${s.price}',
            textAlign: TextAlign.center,
            style: Deco.label(size: 12, color: Deco.muted),
          ),
          const SizedBox(height: 18),
          const DecoDivider(),
          const SizedBox(height: 22),
          const SectionTitle('SELECT A DATE'),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: days.length,
              separatorBuilder: (context, i) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final d = days[i];
                final available = _slotsFor(d).isNotEmpty;
                return _DateTile(
                  date: d,
                  selected: d == _day,
                  enabled: available,
                  onTap: available ? () => _selectDay(d) : null,
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          const SectionTitle('SELECT A TIME'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final h in _hours)
                _TimeChip(
                  label: _hourLabel(h),
                  selected: h == _hour,
                  enabled: slots.contains(h),
                  onTap: () => setState(() => _hour = h),
                ),
            ],
          ),
          const SizedBox(height: 26),
          DecoFrame(
            highlight: true,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YOUR RESERVATION', style: Deco.label(size: 11)),
                const SizedBox(height: 10),
                Text(s.name, style: Deco.heading(size: 22)),
                const SizedBox(height: 6),
                Text(
                  _startsAt == null
                      ? 'Choose a time'
                      : '${loc.formatFullDate(_day)} at ${_hourLabel(_hour!)}',
                  style: const TextStyle(color: Deco.cream, fontSize: 15),
                ),
                const SizedBox(height: 14),
                Container(height: 1, color: Deco.goldDeep.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('TOTAL', style: Deco.label(size: 12, color: Deco.muted)),
                    const Spacer(),
                    Text('\$${s.price}', style: Deco.price(size: 26)),
                  ],
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Deco.danger)),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: GoldButton(
            key: const Key('confirm'),
            label: 'CONFIRM RESERVATION',
            loading: _saving,
            onPressed: _startsAt == null ? null : _confirm,
          ),
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.date, required this.selected, required this.enabled, this.onTap});
  final DateTime date;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Deco.ink : (enabled ? Deco.cream : Deco.muted.withValues(alpha: 0.4));
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 64,
        decoration: BoxDecoration(
          gradient: selected ? Deco.goldGradient : null,
          color: selected ? null : Deco.panel,
          border: Border.all(
            color: selected ? Deco.goldBright : Deco.goldDeep.withValues(alpha: enabled ? 0.7 : 0.25),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(weekdayAbbr[date.weekday - 1], style: Deco.label(size: 10, color: fg)),
            const SizedBox(height: 4),
            Text('${date.day}', style: TextStyle(fontFamily: Deco.display, fontSize: 26, color: fg)),
            const SizedBox(height: 2),
            Text(monthAbbr[date.month - 1], style: Deco.label(size: 10, color: fg)),
          ],
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Deco.ink : (enabled ? Deco.cream : Deco.muted.withValues(alpha: 0.35));
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
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
    );
  }
}
