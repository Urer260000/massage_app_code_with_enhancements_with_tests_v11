import 'package:flutter/material.dart';

import '../api.dart';
import '../theme/deco.dart';
import 'booking_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, required this.user, required this.onSignOut});
  final ApiClient api;
  final User user;
  final VoidCallback onSignOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  late Future<List<Service>> _services;
  late Future<List<Appointment>> _appointments;

  @override
  void initState() {
    super.initState();
    _services = widget.api.services();
    _appointments = widget.api.appointments();
  }

  // Block bodies: an arrow here would hand the Future back to setState, which Flutter rejects.
  void _refreshAppointments() {
    setState(() {
      _appointments = widget.api.appointments();
    });
  }

  void _refreshServices() {
    setState(() {
      _services = widget.api.services();
    });
  }

  Future<void> _book(Service service) async {
    final booked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BookingScreen(api: widget.api, service: service)),
    );
    if (booked == true) {
      _refreshAppointments();
      setState(() => _tab = 1);
    }
  }

  String get _firstName => widget.user.username.split(' ').first;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _tab == 0 ? _menu() : _reservations(),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0x669C7C3E))),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) {
            if (i == 1) _refreshAppointments();
            setState(() => _tab = i);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.spa_outlined),
              selectedIcon: Icon(Icons.spa),
              label: 'MENU',
            ),
            NavigationDestination(
              icon: Icon(Icons.confirmation_number_outlined),
              selectedIcon: Icon(Icons.confirmation_number),
              label: 'RESERVATIONS',
            ),
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
                        const GoldText(
                          'the20sspa',
                          style: TextStyle(fontFamily: Deco.display, fontSize: 22),
                        ),
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
        return CustomScrollView(
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
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList.separated(
                  itemCount: snap.data!.length,
                  separatorBuilder: (context, i) => const SizedBox(height: 16),
                  itemBuilder: (context, i) =>
                      _ServiceCard(service: snap.data![i], onBook: () => _book(snap.data![i])),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _reservations() {
    return FutureBuilder<List<Appointment>>(
      future: _appointments,
      builder: (context, snap) {
        final list = snap.data ?? const <Appointment>[];
        return CustomScrollView(
          slivers: [
            _header(title: 'Your reservations', subtitle: 'WE LOOK FORWARD TO SEEING YOU'),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
              sliver: SliverToBoxAdapter(child: SectionTitle('UPCOMING')),
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
                      Text('No reservations yet', style: Deco.heading(size: 24)),
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
                  itemBuilder: (context, i) => _TicketCard(appointment: list[i]),
                ),
              ),
          ],
        );
      },
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
                    if (s.signature != null)
                      Text(s.signature!.toUpperCase(), style: Deco.label(size: 11)),
                    const SizedBox(height: 2),
                    Text(s.name, style: Deco.heading(size: 24)),
                  ],
                ),
              ),
            ],
          ),
          if (s.description != null) ...[
            const SizedBox(height: 12),
            Text(
              s.description!,
              style: const TextStyle(color: Deco.muted, fontSize: 15, height: 1.35),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.schedule, size: 16, color: Deco.goldDeep),
              const SizedBox(width: 6),
              Text('${s.durationMinutes} MIN', style: Deco.label(size: 12, color: Deco.cream)),
              const SizedBox(width: 16),
              Text('\$${s.price}', style: Deco.price()),
              const Spacer(),
              GoldOutlineButton(label: 'RESERVE', onPressed: onBook),
            ],
          ),
        ],
      ),
    );
  }
}

/// A reservation styled as an admission ticket.
class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final d = a.startsAt;
    final loc = MaterialLocalizations.of(context);
    return DecoFrame(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: IntrinsicHeight(
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
                  Text(a.serviceName, style: Deco.heading(size: 22)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 15, color: Deco.goldDeep),
                      const SizedBox(width: 6),
                      Text(
                        loc.formatTimeOfDay(TimeOfDay.fromDateTime(d)),
                        style: const TextStyle(color: Deco.cream, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(border: Border.all(color: Deco.gold, width: 0.8)),
                    child: Text('CONFIRMED', style: Deco.label(size: 10)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Perforation extends StatelessWidget {
  const _Perforation();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 1, child: CustomPaint(painter: _DashPainter()));
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
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Deco.muted)),
            const SizedBox(height: 16),
            GoldOutlineButton(label: 'TRY AGAIN', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
