import 'package:flutter/material.dart';

import '../api/rpc_client.dart';
import '../state/app_controller.dart';
import '../theme.dart';
import '../widgets/motion.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _invite = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _invite.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_creating) {
        await widget.controller.register(email, password, _invite.text);
      } else {
        await widget.controller.signIn(email, password);
      }
    } on RpcException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.signInWithGoogle(signUp: _creating);
    } on RpcException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editServer() async {
    final field = TextEditingController(text: widget.controller.serverUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server'),
        content: TextField(
          controller: field,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(hintText: 'https://chat.example.com'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, field.text), child: const Text('Save')),
        ],
      ),
    );
    if (url != null) {
      await widget.controller.setServer(url);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PopIn(
                    rise: 24,
                    duration: const Duration(milliseconds: 500),
                    child: Center(
                      child: Hero(
                        tag: 'logo',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.asset('assets/logo.png', width: 72, height: 72),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      _creating ? 'Create your account' : 'Welcome back',
                      key: ValueKey<bool>(_creating),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Palette.danger.withAlpha(38),
                        border: Border.all(color: Palette.danger),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_error!, key: const Key('login-error')),
                    ),
                  TextField(
                    key: const Key('email'),
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('password'),
                    controller: _password,
                    enabled: !_busy,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Password'),
                    onSubmitted: (_) => _submit(),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: _creating
                        ? Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: TextField(
                              key: const Key('invite'),
                              controller: _invite,
                              enabled: !_busy,
                              autocorrect: false,
                              decoration: const InputDecoration(labelText: 'Invite code'),
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('submit'),
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_creating ? 'Create account' : 'Sign in'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or', style: TextStyle(color: Palette.textMuted)),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    key: const Key('google'),
                    onPressed: _busy ? null : _google,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      side: BorderSide(color: Palette.border),
                      foregroundColor: Palette.textPrimary,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: const Text(
                            'G',
                            style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(_creating ? 'Sign up with Google' : 'Sign in with Google'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('toggle'),
                    onPressed: _busy ? null : () => setState(() {
                      _creating = !_creating;
                      _error = null;
                    }),
                    child: Text(_creating ? 'I already have an account' : 'Create an account'),
                  ),
                  TextButton(
                    key: const Key('server'),
                    onPressed: _busy ? null : _editServer,
                    child: Text(
                      'Server: ${widget.controller.serverUrl.replaceFirst('https://', '')}',
                      style: TextStyle(color: Palette.textMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
