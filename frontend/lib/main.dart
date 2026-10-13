import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'session_storage.dart';
import 'theme/deco.dart';

void main() => runApp(SpaApp(api: ApiClient(storage: SecureSessionStorage())));

/// the20sspa — a Roaring Twenties day spa.
class SpaApp extends StatefulWidget {
  const SpaApp({super.key, required this.api});
  final ApiClient api;

  @override
  State<SpaApp> createState() => _SpaAppState();
}

class _SpaAppState extends State<SpaApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  User? _user;
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    widget.api.onSessionExpired = () {
      if (!mounted || _user == null) return;
      setState(() => _user = null);
      _messenger.currentState?.showSnackBar(
        const SnackBar(content: Text('Your session has ended. Please log in again.')),
      );
    };
    _restore();
  }

  Future<void> _restore() async {
    final user = await widget.api.restoreSession();
    if (!mounted) return;
    setState(() {
      _user = user;
      _restoring = false;
    });
  }

  Future<void> _signOut() async {
    setState(() => _user = null);
    await widget.api.logout();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'the20sspa',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messenger,
      theme: buildDecoTheme(),
      home: _restoring
          ? const Scaffold(body: Center(child: BrandMark(size: 104)))
          : _user == null
          ? AuthScreen(api: widget.api, onSignedIn: (user) => setState(() => _user = user))
          : HomeScreen(
              key: ValueKey(_user!.id),
              api: widget.api,
              user: _user!,
              onUserChanged: (user) => setState(() => _user = user),
              onSignOut: _signOut,
            ),
    );
  }
}
