import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../theme/deco.dart';

/// For spa staff: the day's bookings, no-shows, blocked time and menu prices.
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  DateTime _day = DateTime.now();
  late Future<StaffDay> _data;
  SpaInfo? _spa;

  @override
  void initState() {
    super.initState();
    _data = widget.api.staffDay(dayKey(_day));
    widget.api
        .spaInfo()
        .then((spa) {
          if (mounted) setState(() => _spa = spa);
        })
        .catchError((Object _) {});
  }

  void _reload() {
    setState(() {
      _data = widget.api.staffDay(dayKey(_day));
    });
  }

  void _shift(int days) {
    _day = DateTime(_day.year, _day.month, _day.day + days);
    _reload();
  }

  void _say(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _setStatus(Appointment a, String status) async {
    try {
      await widget.api.setStatus(a.id, status);
      _reload();
    } on ApiException catch (e) {
      if (mounted) _say(e.message);
    }
  }

  Future<void> _blockTime(List<Therapist> therapists) async {
    final spa = _spa;
    if (spa == null || therapists.isEmpty) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BlockDialog(api: widget.api, date: dayKey(_day), spa: spa, therapists: therapists),
    );
    if (saved == true) _reload();
  }

  Future<void> _editMenu() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _MenuEditor(api: widget.api)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<StaffDay>(
        future: _data,
        builder: (context, snap) {
          final day = snap.data;
          return RefreshIndicator(
            color: Deco.gold,
            onRefresh: () async => _reload(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Staff', style: Deco.heading(size: 30))),
                    GoldOutlineButton(label: 'MENU & PRICES', onPressed: _editMenu),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous day',
                      onPressed: () => _shift(-1),
                      icon: const Icon(Icons.chevron_left, color: Deco.gold),
                    ),
                    Expanded(
                      child: Text(
                        MaterialLocalizations.of(context).formatFullDate(_day),
                        textAlign: TextAlign.center,
                        style: Deco.label(size: 12, color: Deco.cream),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next day',
                      onPressed: () => _shift(1),
                      icon: const Icon(Icons.chevron_right, color: Deco.gold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (snap.connectionState != ConnectionState.done)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snap.hasError)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(snap.error.toString(), style: const TextStyle(color: Deco.danger)),
                  )
                else ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const Key('block-time'),
                      onPressed: () => _blockTime(day!.therapists),
                      style: TextButton.styleFrom(foregroundColor: Deco.gold),
                      icon: const Icon(Icons.block, size: 18),
                      label: const Text('BLOCK TIME'),
                    ),
                  ),
                  if (day!.appointments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nothing booked this day.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Deco.muted, fontSize: 15),
                      ),
                    )
                  else
                    for (final a in day.appointments) ...[
                      _StaffCard(appointment: a, onStatus: (s) => _setStatus(a, s)),
                      const SizedBox(height: 12),
                    ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.appointment, required this.onStatus});
  final Appointment appointment;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final time = a.localTime == null ? '' : timeLabel(context, a.localTime!);
    final active = a.status == 'confirmed';
    final muted = !active && a.status != 'completed';
    return DecoFrame(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(time, style: Deco.price(size: 18)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(a.serviceName, style: Deco.heading(size: 20, color: muted ? Deco.muted : Deco.cream)),
              ),
              Text(a.status.replaceAll('_', '-').toUpperCase(), style: Deco.label(size: 10, color: Deco.muted)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (a.therapistName != null) a.therapistName!,
              if (a.durationMinutes != null) '${a.durationMinutes} min',
              if (!a.isBlock && a.guestName != null) '${a.guestName} <${a.guestEmail}>',
            ].join('  ·  '),
            style: const TextStyle(color: Deco.cream, fontSize: 14),
          ),
          if (a.pressure != null || a.notes != null) ...[
            const SizedBox(height: 6),
            Text(
              [if (a.pressure != null) 'Pressure: ${a.pressure}', if (a.notes != null) 'Notes: ${a.notes}'].join('\n'),
              style: const TextStyle(color: Deco.goldBright, fontSize: 14),
            ),
          ],
          if (active)
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                if (!a.isBlock) ...[
                  TextButton(onPressed: () => onStatus('completed'), child: const Text('COMPLETED')),
                  TextButton(onPressed: () => onStatus('no_show'), child: const Text('NO-SHOW')),
                ],
                TextButton(
                  onPressed: () => onStatus('cancelled'),
                  style: TextButton.styleFrom(foregroundColor: Deco.danger),
                  child: Text(a.isBlock ? 'REMOVE BLOCK' : 'CANCEL'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _BlockDialog extends StatefulWidget {
  const _BlockDialog({required this.api, required this.date, required this.spa, required this.therapists});
  final ApiClient api;
  final String date;
  final SpaInfo spa;
  final List<Therapist> therapists;

  @override
  State<_BlockDialog> createState() => _BlockDialogState();
}

class _BlockDialogState extends State<_BlockDialog> {
  late String _therapistId = widget.therapists.first.id;
  late String _time = _times.first;
  int _duration = 60;
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  List<String> get _times => [
    for (var h = widget.spa.openHour; h < widget.spa.closeHour; h++)
      for (final m in const [0, 30]) '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
  ];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.blockTime(_therapistId, widget.date, _time, _duration, reason: _reason.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allDay = (widget.spa.closeHour - widget.spa.openHour) * 60;
    return AlertDialog(
      title: Text('Block time', style: Deco.heading(size: 24)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _therapistId,
              decoration: decoInput('THERAPIST', Icons.person_outline),
              dropdownColor: Deco.panelHigh,
              items: [for (final t in widget.therapists) DropdownMenuItem(value: t.id, child: Text(t.name))],
              onChanged: (v) => setState(() => _therapistId = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _time,
              decoration: decoInput('FROM', Icons.schedule),
              dropdownColor: Deco.panelHigh,
              items: [for (final t in _times) DropdownMenuItem(value: t, child: Text(timeLabel(context, t)))],
              onChanged: (v) => setState(() => _time = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _duration,
              decoration: decoInput('FOR', Icons.timelapse),
              dropdownColor: Deco.panelHigh,
              items: [
                for (final d in {30, 60, 120, 240, allDay})
                  DropdownMenuItem(value: d, child: Text(d == allDay ? 'The whole day' : '$d minutes')),
              ],
              onChanged: (v) => setState(() => _duration = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              style: const TextStyle(color: Deco.cream),
              decoration: decoInput('REASON (OPTIONAL)', Icons.notes),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Deco.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CLOSE')),
        TextButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'SAVING…' : 'BLOCK')),
      ],
    );
  }
}

class _MenuEditor extends StatefulWidget {
  const _MenuEditor({required this.api});
  final ApiClient api;

  @override
  State<_MenuEditor> createState() => _MenuEditorState();
}

class _MenuEditorState extends State<_MenuEditor> {
  late Future<List<Service>> _services = widget.api.allServices();

  Future<void> _update(Service s, {num? price, bool? active}) async {
    try {
      await widget.api.updateService(s.id, price: price, active: active);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.name} updated.')));
      setState(() {
        _services = widget.api.allServices();
      });
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _editPrice(Service s) async {
    final controller = TextEditingController(text: s.price.toString());
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.name, style: Deco.heading(size: 22)),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Deco.cream),
          decoration: decoInput('PRICE (USD)', Icons.attach_money),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('SAVE')),
        ],
      ),
    );
    controller.dispose();
    final price = num.tryParse(value ?? '');
    if (price != null && price >= 0) await _update(s, price: price);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('MENU & PRICES', style: Deco.label(size: 14))),
      body: FutureBuilder<List<Service>>(
        future: _services,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Text(snap.error.toString(), style: const TextStyle(color: Deco.danger)),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final s in snap.data!) ...[
                DecoFrame(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name, style: Deco.heading(size: 20)),
                            Text('${s.durationMinutes} min', style: const TextStyle(color: Deco.muted)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _editPrice(s),
                        child: Text(money(s.price), style: Deco.price(size: 18)),
                      ),
                      Switch(
                        value: s.active,
                        activeThumbColor: Deco.gold,
                        onChanged: (v) => _update(s, active: v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const Text(
                'Switched-off treatments are hidden from the menu. Existing reservations keep the price they were booked at.',
                style: TextStyle(color: Deco.muted, fontSize: 13),
              ),
            ],
          );
        },
      ),
    );
  }
}
