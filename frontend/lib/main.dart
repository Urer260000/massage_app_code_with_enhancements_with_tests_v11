import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'theme/deco.dart';

void main() => runApp(SpaApp(api: ApiClient()));

/// the20sspa — a Roaring Twenties day spa.
class SpaApp extends StatefulWidget {
  const SpaApp({super.key, required this.api});
  final ApiClient api;

  @override
  State<SpaApp> createState() => _SpaAppState();
}

class _SpaAppState extends State<SpaApp> {
  User? _user;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'the20sspa',
      debugShowCheckedModeBanner: false,
      theme: buildDecoTheme(),
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
