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

  // Build SPORTSDUG Logo
  Widget _buildLogo() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // SPORTS text
            Text(
              'SPORTS',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                foreground: Paint()
                  ..style = PaintingStyle.fill
                  ..color = const Color(0xFFFF6B35), // Orange fill
                shadows: [
                  Shadow(
                    color: const Color(0xFF0D7377).withOpacity(0.5), // Dark teal shadow
                    offset: const Offset(2, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // DUG text  
            Text(
              'DUG',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                foreground: Paint()
                  ..style = PaintingStyle.fill
                  ..color = const Color(0xFF0D7377), // Dark teal fill
                shadows: [
                  Shadow(
                    color: const Color(0xFFFF6B35).withOpacity(0.3), // Orange shadow
                    offset: const Offset(2, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Sports icon
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B35).withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.sports_soccer,
            size: 32,
            color: Color(0xFFFF6B35),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                
                // SPORTSDUG Logo
                _buildLogo(),
                
                const SizedBox(height: 48),
                
                // Welcome text
                const Text(
                  'Welcome Back!',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0D7377),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sign in to continue',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF757575),
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Email field
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                
                // Password field
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outlined),
                  ),
                  obscureText: true,
                ),
                
                const SizedBox(height: 24),
                
                // Error message
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_error != null) const SizedBox(height: 16),
                
                // Sign in button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _signInOrSignUp,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Continue',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Footer text
                Text(
                  'Don\'t have an account? Sign up automatically!',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
