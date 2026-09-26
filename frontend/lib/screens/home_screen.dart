import 'package:flutter/material.dart';

import '../api.dart';
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

  void _refreshAppointments() {
    setState(() => _appointments = widget.api.appointments());
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Hi, ${widget.user.username}' : 'My appointments'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: widget.onSignOut,
          ),
        ],
      ),
      body: _tab == 0 ? _servicesView() : _appointmentsView(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          if (i == 1) _refreshAppointments();
          setState(() => _tab = i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.spa_outlined), label: 'Services'),
          NavigationDestination(icon: Icon(Icons.event_note_outlined), label: 'Bookings'),
        ],
      ),
    );
  }

  Widget _servicesView() {
    return FutureBuilder<List<Service>>(
      future: _services,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _ErrorView(
            message: snap.error.toString(),
            onRetry: () => setState(() => _services = widget.api.services()),
          );
        }
        final services = snap.data!;
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: services.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final s = services[i];
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: const CircleAvatar(child: Icon(Icons.spa)),
                title: Text(s.name),
                subtitle: Text('${s.durationMinutes} min · \$${s.price}'),
                trailing: FilledButton.tonal(
                  onPressed: () => _book(s),
                  child: const Text('Book'),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _appointmentsView() {
    return FutureBuilder<List<Appointment>>(
      future: _appointments,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _ErrorView(message: snap.error.toString(), onRetry: _refreshAppointments);
        }
        final list = snap.data!;
        if (list.isEmpty) {
          return const Center(child: Text('No appointments yet. Book one from Services.'));
        }
        final loc = MaterialLocalizations.of(context);
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final a = list[i];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.event_available),
                title: Text(a.serviceName),
                subtitle: Text(
                  '${loc.formatFullDate(a.startsAt)} at '
                  '${loc.formatTimeOfDay(TimeOfDay.fromDateTime(a.startsAt))}',
                ),
              ),
            );
          },
        );
      },
    );
  }
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
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
