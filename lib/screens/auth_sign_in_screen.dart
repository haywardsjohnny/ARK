import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthSignInScreen extends StatefulWidget {
  const AuthSignInScreen({super.key});

  @override
  State<AuthSignInScreen> createState() => _AuthSignInScreenState();
}

class _AuthSignInScreenState extends State<AuthSignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _signInOrSignUp() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final supa = Supabase.instance.client;
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      bool loggedIn = false;

      // 1) Try SIGN IN first
      try {
        final res = await supa.auth.signInWithPassword(
          email: email,
          password: password,
        );
        if (res.session != null) {
          loggedIn = true;
        }
      } on AuthException {
        // ignore, we'll try sign-up next
      }

      // 2) If sign-in failed, try SIGN UP
      if (!loggedIn) {
        final signUpRes = await supa.auth.signUp(
          email: email,
          password: password,
        );
        if (signUpRes.session == null) {
          throw Exception(
            'Account created, but no active session. Check email settings in Supabase.',
          );
        }
      }

      if (!mounted) return;
      setState(() => _loading = false);

      // ✅ No manual navigation here:
      // AuthGate listens to auth changes and will switch to Profile screen.
    } on AuthException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SPORTSDUG Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Sign In / Create Account',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loading ? null : _signInOrSignUp,
              child: Text(_loading ? 'Please wait...' : 'Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
