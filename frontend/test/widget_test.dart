import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:the20sspa/api.dart';
import 'package:the20sspa/main.dart';
import 'package:the20sspa/session_storage.dart';

/// A small in-memory stand-in for the backend, so widget tests don't need a server.
class FakeBackend {
  final booked = <Map<String, dynamic>>[];
  final requests = <String>[];
  String role = 'guest';
  bool emailVerified = false;

  /// Access tokens the fake accepts; anything else gets a 401 like an expired token.
  final validTokens = <String>{};
  int _tokens = 0;
  String? lastResetCode;

  Map<String, dynamic> _session(String email, String username) {
    final token = 'access-${++_tokens}';
    validTokens.add(token);
    return {
      'token': token,
      'refreshToken': 'refresh-ok',
      'user': {'id': '1', 'username': username, 'email': email, 'role': role, 'emailVerified': emailVerified},
    };
  }

  static const service = {
    'id': 'swedish-60',
    'signature': 'The Gatsby',
    'name': 'Swedish Massage',
    'durationMinutes': 60,
    'price': 80,
    'description': 'Long, flowing strokes.',
  };

  static const spa = {
    'name': 'the20sspa',
    'timezone': 'America/New_York',
    'openHour': 10,
    'closeHour': 20,
    'cancelCutoffHours': 24,
    'address': '1920 Gatsby Lane',
    'phone': '(555) 019-2020',
    'email': 'hello@the20sspa.com',
    'about': 'A Roaring Twenties day spa.',
    'closedWeekdays': <int>[],
  };

  Map<String, dynamic> _appointment(Map<String, dynamic> body, String id) => {
    'id': id,
    'kind': 'booking',
    'serviceId': body['serviceId'],
    'serviceName': 'Swedish Massage',
    'price': 80,
    'durationMinutes': 60,
    'therapistId': body['therapistId'] ?? 'evelyn',
    'therapistName': body['therapistId'] == 'zelda' ? 'Zelda' : 'Evelyn',
    'startsAt': body['startsAt'],
    'localDate': '2030-01-08',
    'localTime': (body['startsAt'] as String).contains('T16') ? '11:00' : '10:00',
    'status': 'confirmed',
    'isPast': false,
    'canChange': true,
  };

  MockClient client() => MockClient((req) async {
    final path = req.url.path.replaceFirst('/v1', '');
    requests.add('${req.method} $path');
    final body = req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
    http.Response json(Object data, [int status = 200]) =>
        http.Response(jsonEncode(data), status, headers: {'Content-Type': 'application/json'});

    const public = {
      '/register',
      '/login',
      '/auth/refresh',
      '/password/forgot',
      '/password/reset',
      '/services',
      '/spa',
      '/therapists',
      '/availability',
      '/availability/days',
    };
    if (!public.contains(path)) {
      final auth = req.headers['Authorization'] ?? '';
      if (!validTokens.contains(auth.replaceFirst('Bearer ', ''))) {
        return json({'message': 'Session expired.', 'code': 'token_expired'}, 401);
      }
    }

    switch (path) {
      case '/register':
        return json({..._session(body['email'] as String, body['username'] as String), 'devCode': '424242'}, 201);
      case '/login':
        if (body['password'] == 'wrongpass') return json({'message': 'Invalid email or password.'}, 401);
        return json(_session(body['email'] as String, 'Jake Edward'));
      case '/auth/refresh':
        if (body['refreshToken'] != 'refresh-ok') return json({'message': 'Unauthorized'}, 401);
        return json(_session('jake@example.com', 'Jake Edward'));
      case '/logout':
        return json({'message': 'Signed out.'});
      case '/password/forgot':
        lastResetCode = '135790';
        return json({'message': 'Sent.', 'devCode': lastResetCode});
      case '/password/reset':
        if (body['code'] != lastResetCode) return json({'message': 'That code is wrong or has expired.'}, 400);
        return json(_session(body['email'] as String, 'Jake Edward'));
      case '/me/verify-email':
        if (body['code'] != '424242') return json({'message': 'That code is wrong or has expired.'}, 400);
        emailVerified = true;
        return json({
          'user': {'id': '1', 'username': 'Jake Edward', 'email': 'jake@example.com', 'emailVerified': true},
        });
      case '/services':
        return json({
          'services': [service],
        });
      case '/spa':
        return json({'spa': spa});
      case '/therapists':
        return json({
          'therapists': [
            {'id': 'evelyn', 'name': 'Evelyn', 'bio': 'Swedish and hot stone.'},
            {'id': 'zelda', 'name': 'Zelda', 'bio': 'Does it all.'},
          ],
        });
      case '/availability/days':
        return json({
          'days': [
            {'date': '2030-01-07', 'available': false},
            {'date': '2030-01-08', 'available': true},
            {'date': '2030-01-09', 'available': true},
          ],
        });
      case '/availability':
        return json({
          'slots': [
            {'time': '10:00', 'startsAt': '2030-01-08T15:00:00.000Z', 'available': true},
            {'time': '10:30', 'startsAt': '2030-01-08T15:30:00.000Z', 'available': false},
            {'time': '11:00', 'startsAt': '2030-01-08T16:00:00.000Z', 'available': true},
          ],
        });
      case '/appointments':
        if (req.method == 'POST') {
          booked.add(_appointment(body, '${booked.length + 1}'));
          return json({'appointment': booked.last}, 201);
        }
        final scope = req.url.queryParameters['scope'];
        final list = booked.where((a) => (scope == 'past') == (a['status'] != 'confirmed')).toList();
        return json({'appointments': list, 'nextOffset': null});
      case '/admin/appointments':
        return json({
          'date': '2030-01-08',
          'therapists': [
            {'id': 'evelyn', 'name': 'Evelyn'},
          ],
          'appointments': [
            {
              ..._appointment({'serviceId': 'swedish-60', 'startsAt': '2030-01-08T15:00:00.000Z'}, '9'),
              'guestName': 'Daisy',
              'guestEmail': 'daisy@example.com',
              'notes': 'Allergic to lavender',
            },
          ],
        });
    }
    final match = RegExp(r'^/appointments/(\w+)$').firstMatch(path);
    if (match != null) {
      final a = booked.firstWhere((x) => x['id'] == match.group(1));
      if (req.method == 'DELETE') {
        a['status'] = 'cancelled';
        a['canChange'] = false;
      } else if (req.method == 'PATCH') {
        a.addAll(_appointment({...a, ...body}, a['id'] as String));
      }
      return json({'appointment': a});
    }
    return json({'message': 'Not found.'}, 404);
  });
}

/// Phone-sized test surface (400 x 880 logical pixels) so the whole form fits on screen.
void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2640);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  late FakeBackend backend;
  late MemorySessionStorage storage;

  setUp(() {
    backend = FakeBackend();
    storage = MemorySessionStorage();
  });

  ApiClient api() => ApiClient(baseUrl: 'http://test', client: backend.client(), storage: storage);

  Future<void> start(WidgetTester tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(SpaApp(api: api()));
    await tester.pumpAndSettle();
  }

  Future<void> register(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('username')), 'Jake Edward');
    await tester.enterText(find.byKey(const Key('email')), 'jake@example.com');
    await tester.enterText(find.byKey(const Key('password')), 'secret123');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
  }

  Future<void> bookFirstSlot(WidgetTester tester) async {
    await tester.tap(find.text('RESERVE'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the20sspa branding and the membership form first', (tester) async {
    await start(tester);
    expect(find.text('the20sspa'), findsOneWidget);
    expect(find.text('Become a member'), findsOneWidget);
    expect(find.text('BECOME A MEMBER'), findsOneWidget);
  });

  testWidgets('validates empty fields and short new passwords', (tester) async {
    await start(tester);
    await tester.enterText(find.byKey(const Key('password')), 'short');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();
    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('At least 8 characters'), findsOneWidget);
  });

  testWidgets('registering shows the treatment menu and spa details', (tester) async {
    await start(tester);
    await register(tester);
    expect(find.text('Welcome, Jake'), findsOneWidget);
    expect(find.text('Swedish Massage'), findsOneWidget);
    expect(find.text('THE GATSBY'), findsOneWidget);
    expect(find.text(r'$80'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('1920 Gatsby Lane'), 200);
    expect(find.text('1920 Gatsby Lane'), findsOneWidget);
  });

  testWidgets('shows server error on bad login', (tester) async {
    await start(tester);
    await tester.tap(find.text('Already a member? Log in'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('email')), 'jake@example.com');
    await tester.enterText(find.byKey(const Key('password')), 'wrongpass');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    expect(find.text('Invalid email or password.'), findsOneWidget);
  });

  testWidgets('booking offers only open times and shows the reservation', (tester) async {
    await start(tester);
    await register(tester);
    await tester.tap(find.text('RESERVE'));
    await tester.pumpAndSettle();

    // The fully booked day and the taken slot are marked, the first free slot is picked.
    expect(find.text('FULL'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'10:30 AM, unavailable')), findsOneWidget);
    final summary = find.textContaining('at 10:00 AM');
    // The booking page has a horizontal date strip too, so scroll the page itself.
    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(summary, 200, scrollable: page);
    expect(summary, findsOneWidget);
    expect(find.text('First available therapist'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('therapist-zelda')), -200, scrollable: page);

    await tester.tap(find.byKey(const Key('therapist-zelda')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('slot-11:00')));
    await tester.pump();
    await tester.scrollUntilVisible(find.textContaining('at 11:00 AM'), 200, scrollable: page);
    expect(find.text('Zelda'.toUpperCase()), findsOneWidget);
    await tester.enterText(find.byKey(const Key('notes')), 'Sore shoulder');
    await tester.tap(find.byKey(const Key('confirm')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(backend.booked.single['therapistId'], 'zelda');
    expect(find.text('Your reservations'), findsOneWidget);
    expect(find.text('Swedish Massage'), findsOneWidget);
    expect(find.text('with Zelda'), findsOneWidget);
    expect(find.text('CONFIRMED'), findsOneWidget);
  });

  testWidgets('a reservation can be cancelled', (tester) async {
    await start(tester);
    await register(tester);
    await bookFirstSlot(tester);
    await tester.tap(find.byKey(const Key('cancel-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-cancel')));
    await tester.pumpAndSettle();
    expect(backend.booked.single['status'], 'cancelled');
    expect(find.text('No reservations yet'), findsOneWidget);
    await tester.tap(find.text('PAST'));
    await tester.pumpAndSettle();
    expect(find.text('CANCELLED'), findsOneWidget);
  });

  testWidgets('a reservation can be rescheduled', (tester) async {
    await start(tester);
    await register(tester);
    await bookFirstSlot(tester);
    await tester.tap(find.byKey(const Key('reschedule-1')));
    await tester.pumpAndSettle();
    expect(find.text('RESCHEDULE'), findsOneWidget);
    await tester.tap(find.byKey(const Key('slot-11:00')));
    await tester.tap(find.byKey(const Key('confirm')));
    await tester.pumpAndSettle();
    expect(backend.requests, contains('PATCH /appointments/1'));
    expect(find.textContaining('11:00 AM'), findsOneWidget);
  });

  testWidgets('empty reservations shows a friendly prompt', (tester) async {
    await start(tester);
    await register(tester);
    await tester.tap(find.text('BOOKINGS'));
    await tester.pumpAndSettle();
    expect(find.text('No reservations yet'), findsOneWidget);
  });

  testWidgets('opens signed in when a session was saved', (tester) async {
    storage.value = 'refresh-ok';
    await start(tester);
    expect(find.text('Welcome, Jake'), findsOneWidget);
  });

  testWidgets('a rejected saved session goes to the login screen', (tester) async {
    storage.value = 'revoked';
    await start(tester);
    expect(find.text('Become a member'), findsOneWidget);
    expect(storage.value, isNull);
  });

  testWidgets('an expired access token is refreshed without bothering the guest', (tester) async {
    await start(tester);
    await register(tester);
    backend.validTokens.clear(); // every current access token now "expires"
    await tester.tap(find.text('BOOKINGS'));
    await tester.pumpAndSettle();
    expect(backend.requests, contains('POST /auth/refresh'));
    expect(find.text('No reservations yet'), findsOneWidget);
  });

  testWidgets('signing out forgets the saved session', (tester) async {
    await start(tester);
    await register(tester);
    expect(storage.value, 'refresh-ok');
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Become a member'), findsOneWidget);
    expect(storage.value, isNull);
  });

  testWidgets('resets a forgotten password with a code', (tester) async {
    await start(tester);
    await tester.tap(find.text('Already a member? Log in'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('email')), 'jake@example.com');
    await tester.tap(find.byKey(const Key('forgot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reset-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.textContaining('your code is 135790'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('reset-code')), '135790');
    await tester.enterText(find.byKey(const Key('reset-password')), 'brand-new-pass');
    await tester.tap(find.byKey(const Key('reset-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Welcome, Jake'), findsOneWidget);
  });

  testWidgets('confirms the email from the account tab', (tester) async {
    await start(tester);
    await register(tester);
    await tester.tap(find.text('ACCOUNT'));
    await tester.pumpAndSettle();
    expect(find.text('NOT CONFIRMED'), findsOneWidget);
    expect(find.textContaining('your code is 424242'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('verify-code')), '424242');
    await tester.tap(find.byKey(const Key('verify')));
    await tester.pumpAndSettle();
    expect(find.text('CONFIRMED'), findsOneWidget);
  });

  testWidgets('guests do not see the staff tab; staff do', (tester) async {
    await start(tester);
    await register(tester);
    expect(find.text('STAFF'), findsNothing);

    backend.role = 'admin';
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    await register(tester);
    await tester.tap(find.text('STAFF'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Daisy'), findsOneWidget);
    expect(find.textContaining('Allergic to lavender'), findsOneWidget);
    expect(find.text('NO-SHOW'), findsOneWidget);
  });
}
