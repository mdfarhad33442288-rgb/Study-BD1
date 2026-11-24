import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/providers.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/common.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _signup = false, _busy = false, _hide = true;

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } on FirebaseAuthException catch (e) {
      if (mounted) snack(context, e.message ?? e.code);
    } catch (e) {
      if (mounted) snack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(authRepoProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(22), child: Image.asset('assets/images/logo.png', width: 84, height: 84)),
                  const SizedBox(height: 12),
                  Text(context.tr('appName'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  if (_signup) Field(context.tr('name'), _name, validator: Validators.requiredText),
                  Field(context.tr('email'), _email,
                      keyboard: TextInputType.emailAddress, validator: Validators.email),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: _pass,
                      obscureText: _hide,
                      validator: Validators.password,
                      decoration: InputDecoration(
                        labelText: context.tr('password'),
                        suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _hide = !_hide)),
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            if (!_form.currentState!.validate()) return;
                            _run(() => _signup ? repo.signUp(_name.text, _email.text, _pass.text) : repo.signIn(_email.text, _pass.text));
                          },
                    child: _busy
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(context.tr(_signup ? 'signup' : 'login')),
                  ),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    TextButton(
                      onPressed: () => _run(() async {
                        if (Validators.email(_email.text) != null) throw 'Enter your email first';
                        await repo.resetPassword(_email.text);
                        if (mounted) snack(context, 'Password reset email sent');
                      }),
                      child: Text(context.tr('forgot')),
                    ),
                    TextButton(onPressed: () => setState(() => _signup = !_signup), child: Text(context.tr(_signup ? 'login' : 'signup'))),
                  ]),
                  const Divider(height: 32),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: _busy ? null : () => _run(repo.signInWithGoogle),
                    icon: const Icon(Icons.g_mobiledata, size: 30),
                    label: Text(context.tr('google')),
                  ),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _busy ? null : () => _run(repo.continueAsGuest), child: Text(context.tr('guest'))),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
