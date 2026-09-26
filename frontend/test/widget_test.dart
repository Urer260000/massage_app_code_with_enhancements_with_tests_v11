import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:massage_app/api.dart';
import 'package:massage_app/main.dart';

/// Fake backend so widget tests don't need a server.
MockClient fakeBackend() {
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
              {'id': 'swedish-60', 'name': 'Swedish Massage', 'durationMinutes': 60, 'price': 80},
            ],
          }),
          200,
          headers: json,
        );
      case '/appointments':
        return http.Response(jsonEncode({'appointments': []}), 200, headers: json);
    }
    return http.Response('{}', 404);
  });
}

void main() {
  ApiClient api() => ApiClient(baseUrl: 'http://test', client: fakeBackend());

  testWidgets('shows the registration form first', (tester) async {
    await tester.pumpWidget(MassageApp(api: api()));
    expect(find.text('Massage Booking'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
  });

  testWidgets('validates empty fields', (tester) async {
    await tester.pumpWidget(MassageApp(api: api()));
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();
    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Enter a valid email'), findsOneWidget);
  });

  testWidgets('registering shows the services list', (tester) async {
    await tester.pumpWidget(MassageApp(api: api()));
    await tester.enterText(find.byKey(const Key('username')), 'Jake');
    await tester.enterText(find.byKey(const Key('email')), 'jake@example.com');
    await tester.enterText(find.byKey(const Key('password')), 'secret123');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    expect(find.text('Hi, Jake'), findsOneWidget);
    expect(find.text('Swedish Massage'), findsOneWidget);
  });

  testWidgets('shows server error on bad login', (tester) async {
    await tester.pumpWidget(MassageApp(api: api()));
    await tester.tap(find.text('Already have an account? Log in'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('email')), 'jake@example.com');
    await tester.enterText(find.byKey(const Key('password')), 'wrongpass');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    expect(find.text('Invalid email or password.'), findsOneWidget);
  });
}
