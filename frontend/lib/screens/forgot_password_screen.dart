import 'package:flutter/material.dart';

import '../api.dart';
import '../theme/deco.dart';

/// Two steps: send a code to the email, then enter it with a new password.
/// Pops with the signed-in [User] when done.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.api, this.initialEmail = ''});
  final ApiClient api;
  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  String? _error;
  String? _devCode;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
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
      if (!_codeSent) {
        final devCode = await widget.api.forgotPassword(_email.text.trim());
        if (!mounted) return;
        setState(() {
          _codeSent = true;
          _devCode = devCode;
        });
      } else {
        final result = await widget.api.resetPassword(_email.text.trim(), _code.text.trim(), _password.text);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated. Welcome back!')));
        Navigator.of(context).pop(result.user);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('RESET PASSWORD', style: Deco.label(size: 14))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: DecoFrame(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _codeSent ? 'Check your email' : 'Forgot your password?',
                        textAlign: TextAlign.center,
                        style: Deco.heading(size: 26),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _codeSent
                            ? 'If ${_email.text.trim()} has an account, we have sent it a 6-digit code.'
                            : "Enter your email and we'll send you a code.",
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Deco.muted, fontSize: 15),
                      ),
                      const SizedBox(height: 22),
                      TextFormField(
                        key: const Key('reset-email'),
                        controller: _email,
                        enabled: !_codeSent,
                        style: const TextStyle(color: Deco.cream, fontSize: 16),
                        decoration: decoInput('EMAIL', Icons.alternate_email),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) =>
                            (v == null || !v.contains('@') || !v.contains('.')) ? 'Enter a valid email' : null,
                      ),
                      if (_codeSent) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('reset-code'),
                          controller: _code,
                          style: const TextStyle(color: Deco.cream, fontSize: 16, letterSpacing: 4),
                          decoration: decoInput('CODE', Icons.pin_outlined),
                          keyboardType: TextInputType.number,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          validator: (v) =>
                              (v == null || !RegExp(r'^\d{6}$').hasMatch(v.trim())) ? 'Enter the 6-digit code' : null,
                        ),
                        if (_devCode != null) DevCodeHint(code: _devCode!),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('reset-password'),
                          controller: _password,
                          obscureText: true,
                          style: const TextStyle(color: Deco.cream, fontSize: 16),
                          decoration: decoInput('NEW PASSWORD', Icons.lock_outline),
                          autofillHints: const [AutofillHints.newPassword],
                          validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Deco.danger),
                        ),
                      ],
                      const SizedBox(height: 22),
                      GoldButton(
                        key: const Key('reset-submit'),
                        label: _codeSent ? 'SET NEW PASSWORD' : 'SEND CODE',
                        loading: _loading,
                        onPressed: _submit,
                      ),
                      if (_codeSent)
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                  _codeSent = false;
                                  _error = null;
                                }),
                          style: TextButton.styleFrom(foregroundColor: Deco.gold),
                          child: const Text('Use a different email'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown only when the server runs without real email (local testing).
class DevCodeHint extends StatelessWidget {
  const DevCodeHint({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Testing mode (no email set up): your code is $code',
        key: const Key('dev-code'),
        style: const TextStyle(color: Deco.goldBright, fontSize: 13),
      ),
    );
  }
}
