import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:the20sspa/api.dart';
import 'package:the20sspa/main.dart';

/// Fake backend so widget tests don't need a server.
MockClient fakeBackend() {
  final booked = <Map<String, dynamic>>[];
  return MockClient((req) async {
    final json = {'Content-Type': 'application/json'};
    switch (req.url.path) {
      case '/register':
      case '/login':
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        if (body['password'] == 'wrongpass') {
          return http.Response(jsonEncode({'message': 'Invalid email or password.'}), 401,
              headers: json);
        }
        return http.Response(
          jsonEncode({
            'token': 't',
            'user': {'id': '1', 'username': body['username'] ?? 'Jake', 'email': body['email']},
          }),
          req.url.path == '/register' ? 201 : 200,
          headers: json,
        );
      case '/services':
        return http.Response(
          jsonEncode({
            'services': [
              {
                'id': 'swedish-60',
                'signature': 'The Gatsby',
                'name': 'Swedish Massage',
                'durationMinutes': 60,
                'price': 80,
                'description': 'Long, flowing strokes.',
              },
            ],
          }),
          200,
          headers: json,
        );
      case '/appointments':
        if (req.method == 'POST') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          booked.add({
            'id': '${booked.length + 1}',
            'serviceName': 'Swedish Massage',
            'startsAt': body['startsAt'],
          });
          return http.Response(jsonEncode({'appointment': booked.last}), 201, headers: json);
        }
        return http.Response(jsonEncode({'appointments': booked}), 200, headers: json);
    }
    return http.Response('{}', 404);
  });
}

/// Phone-sized test surface (400 x 880 logical pixels) so the whole form fits on screen.
void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2640);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  ApiClient api() => ApiClient(baseUrl: 'http://test', client: fakeBackend());

  Future<void> register(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('username')), 'Jake Edward');
    await tester.enterText(find.byKey(const Key('email')), 'jake@example.com');
    await tester.enterText(find.byKey(const Key('password')), 'secret123');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the20sspa branding and the membership form first', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(SpaApp(api: api()));
    expect(find.text('the20sspa'), findsOneWidget);
    expect(find.text('Become a member'), findsOneWidget);
    expect(find.text('BECOME A MEMBER'), findsOneWidget);
  });

  testWidgets('validates empty fields', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(SpaApp(api: api()));
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();
    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Enter a valid email'), findsOneWidget);
  });

  testWidgets('registering shows the treatment menu', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(SpaApp(api: api()));
    await register(tester);
    expect(find.text('Welcome, Jake'), findsOneWidget);
    expect(find.text('Swedish Massage'), findsOneWidget);
    expect(find.text('THE GATSBY'), findsOneWidget);
  });

  testWidgets('shows server error on bad login', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(SpaApp(api: api()));
    await tester.tap(find.text('Already a member? Log in'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('email')), 'jake@example.com');
    await tester.enterText(find.byKey(const Key('password')), 'wrongpass');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    expect(find.text('Invalid email or password.'), findsOneWidget);
  });

  testWidgets('reserving a treatment shows it under Reservations', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(SpaApp(api: api()));
    await register(tester);

    await tester.tap(find.text('RESERVE'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm')), findsOneWidget);
    expect(find.text('YOUR RESERVATION'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Your reservations'), findsOneWidget);
    expect(find.text('Swedish Massage'), findsOneWidget);
    expect(find.text('CONFIRMED'), findsOneWidget);
  });

  testWidgets('empty reservations shows a friendly prompt', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(SpaApp(api: api()));
    await register(tester);
    await tester.tap(find.text('RESERVATIONS'));
    await tester.pumpAndSettle();
    expect(find.text('No reservations yet'), findsOneWidget);
  });
}
