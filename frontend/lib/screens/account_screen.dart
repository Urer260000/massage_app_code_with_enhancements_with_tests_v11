import 'package:flutter/material.dart';

import '../api.dart';
import '../theme/deco.dart';
import 'forgot_password_screen.dart' show DevCodeHint;

/// Profile, email confirmation, password and account deletion.
class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.api,
    required this.user,
    required this.onUserChanged,
    required this.onSignOut,
  });
  final ApiClient api;
  final User user;
  final ValueChanged<User> onUserChanged;
  final VoidCallback onSignOut;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final _name = TextEditingController(text: widget.user.username);
  final _code = TextEditingController();
  final _current = TextEditingController();
  final _new = TextEditingController();
  String? _busy; // which action is running
  String? _devCode;

  @override
  void initState() {
    super.initState();
    _devCode = widget.api.lastDevCode;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _current.dispose();
    _new.dispose();
    super.dispose();
  }

  void _say(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  /// Runs [action] with a spinner on [key], showing any error as a snackbar.
  Future<void> _run(String key, Future<void> Function() action) async {
    setState(() => _busy = key);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) _say(e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _saveName() => _run('name', () async {
    final name = _name.text.trim();
    if (name.isEmpty) return _say('Please enter your name.');
    final user = await widget.api.updateName(name);
    widget.onUserChanged(user);
    if (mounted) _say('Name saved.');
  });

  Future<void> _verify() => _run('verify', () async {
    final user = await widget.api.verifyEmail(_code.text.trim());
    widget.onUserChanged(user);
    if (mounted) _say('Email confirmed. Thank you!');
  });

  Future<void> _resend() => _run('resend', () async {
    final code = await widget.api.resendVerification();
    if (!mounted) return;
    setState(() => _devCode = code);
    _say('We have sent a new code.');
  });

  Future<void> _changePassword() => _run('password', () async {
    if (_new.text.length < 8) return _say('New password must be at least 8 characters.');
    await widget.api.changePassword(_current.text, _new.text);
    _current.clear();
    _new.clear();
    if (mounted) _say('Password changed. Other devices have been signed out.');
  });

  Future<void> _delete() async {
    final password = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete your account?', style: Deco.heading(size: 24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This removes your account and all your reservations. It cannot be undone.',
              style: TextStyle(color: Deco.cream),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('delete-password'),
              controller: password,
              obscureText: true,
              style: const TextStyle(color: Deco.cream),
              decoration: decoInput('PASSWORD', Icons.lock_outline),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('KEEP IT')),
          TextButton(
            key: const Key('confirm-delete'),
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Deco.danger),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    final value = password.text;
    password.dispose();
    if (confirmed != true) return;
    await _run('delete', () async {
      await widget.api.deleteAccount(value);
      if (mounted) _say('Your account has been deleted.');
      widget.onSignOut();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    Widget field(TextEditingController c, String label, IconData icon, {Key? key, bool obscure = false}) => TextField(
      key: key,
      controller: c,
      obscureText: obscure,
      style: const TextStyle(color: Deco.cream, fontSize: 16),
      decoration: decoInput(label, icon),
    );

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Row(
            children: [
              const FanEmblem(size: 34),
              const SizedBox(width: 10),
              Flexible(child: Text('Your account', style: Deco.heading(size: 30))),
            ],
          ),
          const SizedBox(height: 24),
          const SectionTitle('PROFILE'),
          const SizedBox(height: 14),
          field(_name, 'NAME', Icons.person_outline, key: const Key('account-name')),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: GoldOutlineButton(
              key: const Key('save-name'),
              label: _busy == 'name' ? 'SAVING…' : 'SAVE NAME',
              onPressed: _busy == null ? _saveName : null,
            ),
          ),
          const SizedBox(height: 20),
          const SectionTitle('EMAIL'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(user.email, style: const TextStyle(color: Deco.cream, fontSize: 16)),
              ),
              Icon(
                user.emailVerified ? Icons.verified : Icons.error_outline,
                color: user.emailVerified ? Deco.gold : Deco.danger,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                user.emailVerified ? 'CONFIRMED' : 'NOT CONFIRMED',
                style: Deco.label(size: 10, color: user.emailVerified ? Deco.gold : Deco.danger),
              ),
            ],
          ),
          if (!user.emailVerified) ...[
            const SizedBox(height: 10),
            const Text(
              'Enter the 6-digit code we emailed you, so we can send confirmations and reminders.',
              style: TextStyle(color: Deco.muted, fontSize: 14),
            ),
            const SizedBox(height: 10),
            field(_code, 'CODE', Icons.pin_outlined, key: const Key('verify-code')),
            if (_devCode != null) DevCodeHint(code: _devCode!),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: _busy == null ? _resend : null,
                  style: TextButton.styleFrom(foregroundColor: Deco.muted),
                  child: const Text('SEND A NEW CODE'),
                ),
                GoldOutlineButton(
                  key: const Key('verify'),
                  label: _busy == 'verify' ? 'CHECKING…' : 'CONFIRM',
                  onPressed: _busy == null ? _verify : null,
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          const SectionTitle('PASSWORD'),
          const SizedBox(height: 14),
          field(_current, 'CURRENT PASSWORD', Icons.lock_outline, obscure: true),
          const SizedBox(height: 12),
          field(_new, 'NEW PASSWORD', Icons.lock_reset, obscure: true),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: GoldOutlineButton(
              label: _busy == 'password' ? 'SAVING…' : 'CHANGE PASSWORD',
              onPressed: _busy == null ? _changePassword : null,
            ),
          ),
          const SizedBox(height: 28),
          GoldButton(key: const Key('sign-out'), label: 'SIGN OUT', onPressed: widget.onSignOut),
          const SizedBox(height: 18),
          Center(
            child: TextButton(
              key: const Key('delete-account'),
              onPressed: _busy == null ? _delete : null,
              style: TextButton.styleFrom(foregroundColor: Deco.danger),
              child: const Text('Delete my account'),
            ),
          ),
        ],
      ),
    );
  }
}
