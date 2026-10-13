import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../theme/deco.dart';
import 'account_screen.dart';
import 'booking_screen.dart';
import 'staff_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.user,
    required this.onSignOut,
    required this.onUserChanged,
  });
  final ApiClient api;
  final User user;
  final VoidCallback onSignOut;
  final ValueChanged<User> onUserChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _showPast = false;
  late Future<List<Service>> _services;
  late Future<List<Appointment>> _appointments;
  SpaInfo? _spa;

  @override
  void initState() {
    super.initState();
    _services = widget.api.services();
    _appointments = _loadAppointments();
    widget.api
        .spaInfo()
        .then((spa) {
          if (mounted) setState(() => _spa = spa);
        })
        .catchError((Object _) {});
  }

  Future<List<Appointment>> _loadAppointments() => widget.api.appointments(scope: _showPast ? 'past' : 'upcoming');

  // Block bodies: an arrow here would hand the Future back to setState, which Flutter rejects.
  Future<void> _refreshAppointments() {
    final next = _loadAppointments();
    setState(() {
      _appointments = next;
    });
    return next.then((_) {}, onError: (Object _) {});
  }

  Future<void> _refreshServices() {
    final next = widget.api.services();
    setState(() {
      _services = next;
    });
    return next.then((_) {}, onError: (Object _) {});
  }

  int get _cutoff => _spa?.cancelCutoffHours ?? 24;

  Future<void> _book(Service service) async {
    final booked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BookingScreen(api: widget.api, service: service, cancelCutoffHours: _cutoff),
      ),
    );
    if (booked == true) {
      _showPast = false;
      _refreshAppointments();
      setState(() => _tab = 1);
    }
  }

  /// The menu entry for a past booking, or a stand-in if it's no longer on the menu.
  Future<Service> _serviceFor(Appointment a) async {
    try {
      final services = await _services;
      final match = services.where((s) => s.id == a.serviceId).firstOrNull;
      if (match != null) return match;
    } catch (_) {}
    return Service(
      id: a.serviceId ?? '',
      name: a.serviceName,
      durationMinutes: a.durationMinutes ?? 60,
      price: a.price ?? 0,
    );
  }

  Future<void> _reschedule(Appointment a) async {
    final service = await _serviceFor(a);
    if (!mounted) return;
    final moved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BookingScreen(api: widget.api, service: service, rescheduling: a, cancelCutoffHours: _cutoff),
      ),
    );
    if (moved == true) _refreshAppointments();
  }

  Future<void> _bookAgain(Appointment a) async {
    final services = await _services.catchError((Object _) => <Service>[]);
    final match = services.where((s) => s.id == a.serviceId).firstOrNull;
    if (!mounted) return;
    if (match == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("That treatment isn't on the menu right now.")));
      return;
    }
    await _book(match);
  }

  Future<void> _cancel(Appointment a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel reservation?', style: Deco.heading(size: 24)),
        content: Text(
          '${a.serviceName} on ${a.localDate == null ? '' : fullDate(context, a.localDate!)}'
          '${a.localTime == null ? '' : ' at ${timeLabel(context, a.localTime!)}'}',
          style: const TextStyle(color: Deco.cream),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('KEEP IT')),
          TextButton(
            key: const Key('confirm-cancel'),
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Deco.danger),
            child: const Text('CANCEL IT'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.cancel(a.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reservation cancelled.')));
      _refreshAppointments();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _review(Appointment a) async {
    final result = await showDialog<(int, String)>(
      context: context,
      builder: (context) => _ReviewDialog(serviceName: a.serviceName),
    );
    if (result == null) return;
    try {
      await widget.api.review(a.id, result.$1, comment: result.$2);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thank you for your review!')));
      _refreshAppointments();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String get _firstName => widget.user.username.split(' ').first;

  List<_Tab> get _tabs => [
    _Tab('MENU', Icons.spa_outlined, Icons.spa, _menu),
    _Tab('BOOKINGS', Icons.confirmation_number_outlined, Icons.confirmation_number, _reservations),
    _Tab(
      'ACCOUNT',
      Icons.person_outline,
      Icons.person,
      () => AccountScreen(
        api: widget.api,
        user: widget.user,
        onUserChanged: widget.onUserChanged,
        onSignOut: widget.onSignOut,
      ),
    ),
    if (widget.user.isStaff) _Tab('STAFF', Icons.badge_outlined, Icons.badge, () => StaffScreen(api: widget.api)),
  ];

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    final tab = _tab.clamp(0, tabs.length - 1);
    return Scaffold(
      body: tabs[tab].build(),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0x669C7C3E))),
        ),
        child: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) {
            if (i == 1) _refreshAppointments();
            setState(() => _tab = i);
          },
          destinations: [
            for (final t in tabs)
              NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selectedIcon), label: t.label),
          ],
        ),
      ),
    );
  }

  Widget _header({required String title, required String subtitle}) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 190,
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: SunburstPainter(opacity: 0.13))),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const FanEmblem(size: 34),
                        const SizedBox(width: 10),
                        const GoldText('the20sspa', style: TextStyle(fontFamily: Deco.display, fontSize: 22)),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Sign out',
                          icon: const Icon(Icons.logout, color: Deco.gold),
                          onPressed: widget.onSignOut,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(title, style: Deco.heading(size: 34)),
                    const SizedBox(height: 6),
                    Text(subtitle, style: Deco.label(size: 11, color: Deco.muted)),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menu() {
    return FutureBuilder<List<Service>>(
      future: _services,
      builder: (context, snap) {
        return RefreshIndicator(
          color: Deco.gold,
          onRefresh: _refreshServices,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _header(title: 'Welcome, $_firstName', subtitle: 'CHOOSE YOUR INDULGENCE'),
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
                sliver: SliverToBoxAdapter(child: SectionTitle('THE TREATMENT MENU')),
              ),
              if (snap.connectionState != ConnectionState.done)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              else if (snap.hasError)
                SliverFillRemaining(
                  child: _ErrorView(message: snap.error.toString(), onRetry: _refreshServices),
                )
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: snap.data!.length,
                    separatorBuilder: (context, i) => const SizedBox(height: 16),
                    itemBuilder: (context, i) =>
                        _ServiceCard(service: snap.data![i], onBook: () => _book(snap.data![i])),
                  ),
                ),
                if (_spa != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                    sliver: SliverToBoxAdapter(child: _VisitCard(spa: _spa!)),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _reservations() {
    return FutureBuilder<List<Appointment>>(
      future: _appointments,
      builder: (context, snap) {
        final list = snap.data ?? const <Appointment>[];
        return RefreshIndicator(
          color: Deco.gold,
          onRefresh: _refreshAppointments,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _header(title: 'Your reservations', subtitle: 'WE LOOK FORWARD TO SEEING YOU'),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                sliver: SliverToBoxAdapter(
                  child: _Segmented(
                    options: const ['UPCOMING', 'PAST'],
                    selected: _showPast ? 1 : 0,
                    onChanged: (i) {
                      _showPast = i == 1;
                      _refreshAppointments();
                    },
                  ),
                ),
              ),
              if (snap.connectionState != ConnectionState.done)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              else if (snap.hasError)
                SliverFillRemaining(
                  child: _ErrorView(message: snap.error.toString(), onRetry: _refreshAppointments),
                )
              else if (list.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        const FanEmblem(size: 70),
                        const SizedBox(height: 16),
                        Text(_showPast ? 'No past visits yet' : 'No reservations yet', style: Deco.heading(size: 24)),
                        const SizedBox(height: 8),
                        const Text(
                          'Pick a treatment from the menu and we\'ll hold your place.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Deco.muted, fontSize: 15),
                        ),
                        const SizedBox(height: 20),
                        GoldOutlineButton(label: 'VIEW THE MENU', onPressed: () => setState(() => _tab = 0)),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: list.length,
                    separatorBuilder: (context, i) => const SizedBox(height: 14),
                    itemBuilder: (context, i) {
                      final a = list[i];
                      return _TicketCard(
                        appointment: a,
                        spa: _spa,
                        onCancel: () => _cancel(a),
                        onReschedule: () => _reschedule(a),
                        onReview: () => _review(a),
                        onBookAgain: () => _bookAgain(a),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Tab {
  _Tab(this.label, this.icon, this.selectedIcon, this.build);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() build;
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.options, required this.selected, required this.onChanged});
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < options.length; i++)
          Expanded(
            child: Semantics(
              button: true,
              selected: i == selected,
              label: options[i],
              excludeSemantics: true,
              child: InkWell(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: motion(context, 160),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    gradient: i == selected ? Deco.goldGradient : null,
                    color: i == selected ? null : Deco.panel,
                    border: Border.all(color: Deco.goldDeep),
                  ),
                  child: Text(
                    options[i],
                    textAlign: TextAlign.center,
                    style: Deco.label(size: 11, color: i == selected ? Deco.ink : Deco.cream),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.onBook});
  final Service service;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final s = service;
    return DecoFrame(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Medallion(icon: serviceIcon(s.id)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (s.signature != null) Text(s.signature!.toUpperCase(), style: Deco.label(size: 11)),
                    const SizedBox(height: 2),
                    Text(s.name, style: Deco.heading(size: 24)),
                  ],
                ),
              ),
            ],
          ),
          if (s.description != null) ...[
            const SizedBox(height: 12),
            Text(s.description!, style: const TextStyle(color: Deco.muted, fontSize: 15, height: 1.35)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.schedule, size: 16, color: Deco.goldDeep),
              const SizedBox(width: 6),
              Text('${s.durationMinutes} MIN', style: Deco.label(size: 12, color: Deco.cream)),
              const SizedBox(width: 16),
              Text(money(s.price), style: Deco.price()),
              const Spacer(),
              GoldOutlineButton(label: 'RESERVE', onPressed: onBook),
            ],
          ),
        ],
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.spa});
  final SpaInfo spa;

  @override
  Widget build(BuildContext context) {
    String hour(int h) => MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay(hour: h, minute: 0));
    final closed = spa.closedWeekdays.map((d) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1]);
    Widget line(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: Deco.goldDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: Deco.cream, fontSize: 15)),
          ),
        ],
      ),
    );
    return DecoFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VISIT US', style: Deco.label(size: 12)),
          const SizedBox(height: 6),
          Text(spa.about, style: const TextStyle(color: Deco.muted, fontSize: 14, height: 1.35)),
          line(Icons.place_outlined, spa.address),
          line(
            Icons.access_time,
            'Daily ${hour(spa.openHour)} – ${hour(spa.closeHour)}'
            '${closed.isEmpty ? '' : ' (closed ${closed.join(', ')})'}',
          ),
          line(Icons.call_outlined, spa.phone),
          line(Icons.mail_outline, spa.email),
        ],
      ),
    );
  }
}

/// A reservation styled as an admission ticket.
class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.appointment,
    required this.spa,
    required this.onCancel,
    required this.onReschedule,
    required this.onReview,
    required this.onBookAgain,
  });
  final Appointment appointment;
  final SpaInfo? spa;
  final VoidCallback onCancel;
  final VoidCallback onReschedule;
  final VoidCallback onReview;
  final VoidCallback onBookAgain;

  static const _statusLabels = {
    'confirmed': 'CONFIRMED',
    'completed': 'COMPLETED',
    'cancelled': 'CANCELLED',
    'no_show': 'MISSED',
  };

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final d = a.localDate != null ? parseDay(a.localDate!) : a.startsAt;
    final time = a.localTime != null
        ? timeLabel(context, a.localTime!)
        : MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(a.startsAt));
    final status = a.status == 'confirmed' && a.isPast
        ? 'COMPLETED'
        : _statusLabels[a.status] ?? a.status.toUpperCase();
    final dim = a.status == 'cancelled' || a.status == 'no_show';
    final details = [
      time,
      if (a.durationMinutes != null) '${a.durationMinutes} min',
      if (a.price != null) money(a.price!),
    ].join('  ·  ');

    return DecoFrame(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 58,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(monthAbbr[d.month - 1], style: Deco.label(size: 11)),
                      GoldText('${d.day}', style: const TextStyle(fontFamily: Deco.display, fontSize: 34)),
                      Text(weekdayAbbr[d.weekday - 1], style: Deco.label(size: 11, color: Deco.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                const _Perforation(),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(a.serviceName, style: Deco.heading(size: 22, color: dim ? Deco.muted : Deco.cream)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.schedule, size: 15, color: Deco.goldDeep),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(details, style: const TextStyle(color: Deco.cream, fontSize: 15)),
                          ),
                        ],
                      ),
                      if (a.therapistName != null) ...[
                        const SizedBox(height: 4),
                        Text('with ${a.therapistName}', style: const TextStyle(color: Deco.muted, fontSize: 14)),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              border: Border.all(color: dim ? Deco.muted : Deco.gold, width: 0.8),
                            ),
                            child: Text(status, style: Deco.label(size: 10, color: dim ? Deco.muted : Deco.gold)),
                          ),
                          if (a.review != null) ...[
                            const SizedBox(width: 10),
                            _Stars(rating: a.review!.rating, size: 15),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ..._actions(context),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    final a = appointment;
    Widget bar(List<Widget> children) => Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 8, children: children),
    );
    if (a.isUpcoming) {
      if (a.canChange) {
        return [
          bar([
            TextButton(
              key: Key('cancel-${a.id}'),
              onPressed: onCancel,
              style: TextButton.styleFrom(foregroundColor: Deco.muted),
              child: const Text('CANCEL'),
            ),
            GoldOutlineButton(key: Key('reschedule-${a.id}'), label: 'RESCHEDULE', onPressed: onReschedule),
          ]),
        ];
      }
      return [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'Within ${spa?.cancelCutoffHours ?? 24} hours of your visit. To change it, call ${spa?.phone ?? 'the spa'}.',
            style: const TextStyle(color: Deco.muted, fontSize: 13),
          ),
        ),
      ];
    }
    final canReview = a.review == null && (a.status == 'confirmed' || a.status == 'completed');
    return [
      bar([
        if (canReview)
          TextButton(
            key: Key('review-${a.id}'),
            onPressed: onReview,
            style: TextButton.styleFrom(foregroundColor: Deco.gold),
            child: const Text('RATE YOUR VISIT'),
          ),
        if (a.serviceId != null) GoldOutlineButton(label: 'BOOK AGAIN', onPressed: onBookAgain),
      ]),
    ];
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rating, this.size = 28, this.onChanged});
  final int rating;
  final double size;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$rating out of 5 stars',
      excludeSemantics: onChanged == null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            onChanged == null
                ? Icon(i <= rating ? Icons.star : Icons.star_border, size: size, color: Deco.gold)
                : IconButton(
                    key: Key('star-$i'),
                    tooltip: '$i star${i == 1 ? '' : 's'}',
                    onPressed: () => onChanged!(i),
                    icon: Icon(i <= rating ? Icons.star : Icons.star_border, size: size, color: Deco.gold),
                  ),
        ],
      ),
    );
  }
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({required this.serviceName});
  final String serviceName;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  int _rating = 0;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('How was your ${widget.serviceName}?', style: Deco.heading(size: 22)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Stars(rating: _rating, size: 30, onChanged: (r) => setState(() => _rating = r)),
          const SizedBox(height: 12),
          TextField(
            key: const Key('review-comment'),
            controller: _comment,
            maxLength: 1000,
            maxLines: 3,
            style: const TextStyle(color: Deco.cream),
            decoration: decoInput('COMMENTS (OPTIONAL)', Icons.edit_outlined),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('LATER')),
        TextButton(
          key: const Key('submit-review'),
          onPressed: _rating == 0 ? null : () => Navigator.pop(context, (_rating, _comment.text.trim())),
          child: const Text('SEND'),
        ),
      ],
    );
  }
}

class _Perforation extends StatelessWidget {
  const _Perforation();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 1, child: CustomPaint(painter: _DashPainter()));
}

class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Deco.goldDeep
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 7) {
      canvas.drawLine(Offset(0.5, y), Offset(0.5, y + 3), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => false;
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, color: Deco.goldDeep, size: 36),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Deco.muted),
            ),
            const SizedBox(height: 16),
            GoldOutlineButton(label: 'TRY AGAIN', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
