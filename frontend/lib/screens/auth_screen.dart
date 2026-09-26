import 'package:flutter/material.dart';

import '../api.dart';
import '../theme/deco.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.api, required this.onSignedIn});
  final ApiClient api;
  final ValueChanged<User> onSignedIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isRegister = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = _isRegister
          ? await widget.api.register(_username.text.trim(), _email.text.trim(), _password.text)
          : await widget.api.login(_email.text.trim(), _password.text);
      if (!mounted) return;
      widget.onSignedIn(result.user);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleMode() {
    setState(() {
      _isRegister = !_isRegister;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: SunburstPainter(origin: const Alignment(0, -1.15), opacity: 0.1)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const BrandMark(size: 104),
                        const SizedBox(height: 32),
                        DecoFrame(
                          padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _isRegister ? 'Become a member' : 'Welcome back',
                                textAlign: TextAlign.center,
                                style: Deco.heading(size: 28),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _isRegister ? 'JOIN THE PARTY' : 'THE PARTY AWAITS',
                                textAlign: TextAlign.center,
                                style: Deco.label(size: 11, color: Deco.muted),
                              ),
                              const SizedBox(height: 24),
                              if (_isRegister) ...[
                                TextFormField(
                                  key: const Key('username'),
                                  controller: _username,
                                  style: const TextStyle(color: Deco.cream, fontSize: 16),
                                  decoration: decoInput('NAME', Icons.person_outline),
                                  textInputAction: TextInputAction.next,
                                  textCapitalization: TextCapitalization.words,
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                                ),
                                const SizedBox(height: 14),
                              ],
                              TextFormField(
                                key: const Key('email'),
                                controller: _email,
                                style: const TextStyle(color: Deco.cream, fontSize: 16),
                                decoration: decoInput('EMAIL', Icons.alternate_email),
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                validator: (v) => (v == null || !v.contains('@') || !v.contains('.'))
                                    ? 'Enter a valid email'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                key: const Key('password'),
                                controller: _password,
                                style: const TextStyle(color: Deco.cream, fontSize: 16),
                                decoration: decoInput('PASSWORD', Icons.lock_outline),
                                obscureText: true,
                                onFieldSubmitted: (_) => _submit(),
                                validator: (v) =>
                                    (v == null || v.length < 6) ? 'At least 6 characters' : null,
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 14),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Deco.danger, fontSize: 14),
                                ),
                              ],
                              const SizedBox(height: 22),
                              GoldButton(
                                key: const Key('submit'),
                                label: _isRegister ? 'BECOME A MEMBER' : 'LOG IN',
                                loading: _loading,
                                onPressed: _submit,
                              ),
                              const SizedBox(height: 6),
                              TextButton(
                                onPressed: _loading ? null : _toggleMode,
                                style: TextButton.styleFrom(foregroundColor: Deco.gold),
                                child: Text(
                                  _isRegister ? 'Already a member? Log in' : 'New here? Become a member',
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
