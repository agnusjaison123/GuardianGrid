import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/app_snackbar.dart';
import '../application/auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<void>>(authControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (error, _) =>
            showAppSnackBar(context, _friendlyAuthError(error)),
      );
    });

    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      body: _RoadSafetyShell(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: _AuthCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const _AuthHeader(title: 'Welcome Back'),
                      const SizedBox(height: 20),
                      Form(
                        key: _formKey,
                        child: Column(
                          children: <Widget>[
                            _AuthInput(
                              controller: _emailController,
                              icon: Icons.mail_outline,
                              hint: 'Email',
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Enter your email.';
                                }
                                if (!value.contains('@')) {
                                  return 'Enter a valid email.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            _AuthInput(
                              controller: _passwordController,
                              icon: Icons.lock_outline,
                              hint: 'Password',
                              obscureText: true,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Enter your password.';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: isLoading ? null : _sendPasswordReset,
                          child: const Text(
                            'Forgot password?',
                            style: TextStyle(
                              color: Color(0xFF55627C),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: isLoading ? null : _signInWithEmail,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFFB200),
                          foregroundColor: const Color(0xFF1D1A0C),
                          minimumSize: const Size(double.infinity, 54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Sign In',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                      const SizedBox(height: 18),
                      const _DividerLabel(label: 'or continue with'),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: isLoading ? null : _signInWithGoogle,
                        icon: const Icon(Icons.g_mobiledata, size: 28),
                        label: const Text(
                          'Google',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF3F4B66),
                          side: const BorderSide(color: Color(0xFFD7DDE8)),
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const Text(
                            "Don't have an account? ",
                            style: TextStyle(
                              color: Color(0xFF65738E),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextButton(
                            onPressed: isLoading
                                ? null
                                : () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => const SignUpPage(),
                                      ),
                                    );
                                  },
                            child: const Text(
                              'Sign Up',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
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

  Future<void> _signInWithEmail() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    await ref
        .read(authControllerProvider.notifier)
        .signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );

    if (!mounted || ref.read(authControllerProvider).hasError) {
      return;
    }
    context.go('/map');
  }

  Future<void> _signInWithGoogle() async {
    await ref.read(authControllerProvider.notifier).signInWithGoogle();
    if (!mounted || ref.read(authControllerProvider).hasError) {
      return;
    }
    context.go('/map');
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      showAppSnackBar(context, 'Enter a valid email to reset password.');
      return;
    }

    await ref
        .read(authControllerProvider.notifier)
        .sendPasswordResetEmail(email);
    if (!mounted || ref.read(authControllerProvider).hasError) {
      return;
    }
    showAppSnackBar(context, 'Password reset email sent.');
  }
}

class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<void>>(authControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (error, _) =>
            showAppSnackBar(context, _friendlyAuthError(error)),
      );
    });

    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      body: _RoadSafetyShell(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: _AuthCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          IconButton(
                            onPressed: isLoading
                                ? null
                                : () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back),
                          ),
                          const Expanded(
                            child: _AuthHeader(title: 'Create Account'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Form(
                        key: _formKey,
                        child: Column(
                          children: <Widget>[
                            _AuthInput(
                              controller: _nameController,
                              icon: Icons.person_outline,
                              hint: 'Full name',
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Enter your full name.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            _AuthInput(
                              controller: _emailController,
                              icon: Icons.mail_outline,
                              hint: 'Email',
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Enter your email.';
                                }
                                if (!value.contains('@')) {
                                  return 'Enter a valid email.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            _AuthInput(
                              controller: _passwordController,
                              icon: Icons.lock_outline,
                              hint: 'Password',
                              obscureText: true,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Enter your password.';
                                }
                                if (value.length < 6) {
                                  return 'Password must be at least 6 characters.';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: isLoading ? null : _registerWithEmail,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFFB200),
                          foregroundColor: const Color(0xFF1D1A0C),
                          minimumSize: const Size(double.infinity, 54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Create Account',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: isLoading ? null : _signUpWithGoogle,
                        icon: const Icon(Icons.g_mobiledata, size: 28),
                        label: const Text(
                          'Sign up with Google',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF3F4B66),
                          side: const BorderSide(color: Color(0xFFD7DDE8)),
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
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

  Future<void> _registerWithEmail() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    await ref
        .read(authControllerProvider.notifier)
        .register(
          email: _emailController.text,
          password: _passwordController.text,
          fullName: _nameController.text,
        );

    if (!mounted || ref.read(authControllerProvider).hasError) {
      return;
    }
    context.go('/map');
  }

  Future<void> _signUpWithGoogle() async {
    await ref.read(authControllerProvider.notifier).signInWithGoogle();
    if (!mounted || ref.read(authControllerProvider).hasError) {
      return;
    }
    context.go('/map');
  }
}

class _RoadSafetyShell extends StatelessWidget {
  const _RoadSafetyShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFF2A2D33), Color(0xFF111317)],
            ),
          ),
        ),
        const Positioned.fill(child: _LanePainter()),
        child,
      ],
    );
  }
}

class _LanePainter extends StatelessWidget {
  const _LanePainter();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.center,
        child: SizedBox(
          width: 26,
          child: Column(
            children: List<Widget>.generate(16, (index) {
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: index.isEven
                        ? const Color(0xFFEDEFF3).withValues(alpha: 0.34)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _AuthHeader extends StatelessWidget {
  const _AuthHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const Icon(Icons.shield_outlined, size: 30, color: Color(0xFFFFB200)),
        const SizedBox(height: 6),
        const Text(
          'Guardian Grid',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E232D),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF5D6880),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _DividerLabel extends StatelessWidget {
  const _DividerLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Expanded(child: Divider(color: Color(0xFFDCE2EA))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF7D879C),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xFFDCE2EA))),
      ],
    );
  }
}

class _AuthInput extends StatelessWidget {
  const _AuthInput({
    required this.controller,
    required this.icon,
    required this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF7E899C)),
        filled: true,
        fillColor: const Color(0xFFF4F7FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFFFB200), width: 1.5),
        ),
        errorStyle: const TextStyle(color: Color(0xFFBB1E1E)),
      ),
    );
  }
}

String _friendlyAuthError(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Invalid email or password.';
      case 'email-already-in-use':
        return 'Email is already registered.';
      case 'weak-password':
        return 'Use a stronger password (at least 6 characters).';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'account-exists-with-different-credential':
        return 'Use the original provider for this email account.';
      case 'popup-closed-by-user':
      case 'aborted-by-user':
        return 'Google sign-in was cancelled.';
      case 'network-request-failed':
        return 'Network issue. Check your connection and retry.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled in Firebase.';
      case 'google-sign-in-not-configured':
        return 'Google sign-in is not configured for this Android build. '
            'Add SHA keys in Firebase, download new google-services.json, '
            'then rebuild.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
  return 'Something went wrong. Please try again.';
}
