import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

void main() => runApp(MassageApp(api: ApiClient()));

class MassageApp extends StatefulWidget {
  const MassageApp({super.key, required this.api});
  final ApiClient api;

  @override
  State<MassageApp> createState() => _MassageAppState();
}

class _MassageAppState extends State<MassageApp> {
  User? _user;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Massage Booking',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F7F74)),
        useMaterial3: true,
      ),
      home: _user == null
          ? AuthScreen(
              api: widget.api,
              onSignedIn: (user) => setState(() => _user = user),
            )
          : HomeScreen(
              api: widget.api,
              user: _user!,
              onSignOut: () {
                widget.api.logout();
                setState(() => _user = null);
              },
            ),
    );
  }
}
