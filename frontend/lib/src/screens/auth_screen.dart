import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../state/auth_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_text_field.dart';
import '../widgets/error_banner.dart';
import '../widgets/loading_button.dart';

/// Login / registration screen.
///
/// Responsive: on wide screens it shows a branded panel next to the form;
/// on narrow screens only the form (with a compact logo header) is shown.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _registerMode = false;
  bool _submitting = false;
  String? _serverError;

  // Success message human sa registration (makita sa Sign in form)
  String? _successMessage;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _registerMode = !_registerMode;
      _serverError = null;
      _successMessage = null;
    });
    _formKey.currentState?.reset();
  }

  Future<void> _submit() async {
    setState(() {
      _serverError = null;
      _successMessage = null;
    });

    // Kung mapakyas ang validation sa register, i-clear ang password fields
    if (!(_formKey.currentState?.validate() ?? false)) {
      if (_registerMode) {
        _password.clear();
        _confirm.clear();
      }
      return;
    }

    setState(() => _submitting = true);
    try {
      if (_registerMode) {
        await widget.auth.register(
          name: _name.text,
          email: _email.text,
          password: _password.text,
        );
        if (!mounted) return;

        // Walay auto-login: balik sa Sign in, ibilin ang email,
        // i-clear ang name ug password fields.
        setState(() {
          _registerMode = false;
          _name.clear();
          _password.clear();
          _confirm.clear();
          _successMessage = 'Account created successfully. Please sign in.';
        });
      } else {
        await widget.auth.login(email: _email.text, password: _password.text);
        _showSnack('Signed in successfully.');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        final fieldErrors = error.fields.values.join(' ');
        _serverError = fieldErrors.isEmpty
            ? error.message
            : '${error.message} $fieldErrors';

        // Kung register ang napakyas: ibilin ang name ug email,
        // i-clear lang ang password fields.
        if (_registerMode) {
          _password.clear();
          _confirm.clear();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _serverError = 'Something went wrong. Please try again.';
        if (_registerMode) {
          _password.clear();
          _confirm.clear();
        }
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;

    return Scaffold(
      body: Row(
        children: [
          if (wide) const Expanded(child: _BrandPanel()),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _buildForm(showLogo: !wide),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm({required bool showLogo}) {
    final busy = _submitting || widget.auth.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showLogo) ...[const _CompactLogo(), const SizedBox(height: 28)],
        Text(
          _registerMode ? 'Create your account' : 'Welcome back',
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          _registerMode
              ? 'Start organizing your private notes in seconds.'
              : 'Sign in to open your secure notes.',
          style: const TextStyle(fontSize: 15, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 24),

        // Success message human sa registration
        if (_successMessage != null) ...[
          Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA5D6A7)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: Color(0xFF2E7D32),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _successMessage!,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFF1B5E20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],

        ErrorBanner(message: _serverError),
        if (_serverError != null) const SizedBox(height: 18),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_registerMode) ...[
                AppTextField(
                  // Key para dili mag-share og state ang fields
                  key: const ValueKey('register-name'),
                  controller: _name,
                  label: 'Full name',
                  hint: 'Your full name',
                  prefixIcon: Icons.person_outline,
                  enabled: !busy,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return 'Name is required.';
                    if (text.length < 2) return 'Enter at least 2 characters.';
                    if (text.length > 80) {
                      return 'Keep the name under 80 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],
              AppTextField(
                key: const ValueKey('auth-email'),
                obscureText: false, // email kinahanglan makita ang text
                controller: _email,
                label: 'Email address',
                hint: 'name@example.com',
                prefixIcon: Icons.mail_outline,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                enabled: !busy,
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return 'Email is required.';
                  final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$')
                      .hasMatch(text);
                  if (!valid) return 'Enter a valid email address.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              AppTextField(
                key: const ValueKey('auth-password'),
                controller: _password,
                label: 'Password',
                hint: _registerMode ? 'At least 8 characters' : 'Your password',
                prefixIcon: Icons.lock_outline,
                obscureText: true,
                textInputAction: _registerMode
                    ? TextInputAction.next
                    : TextInputAction.done,
                enabled: !busy,
                onSubmitted: (_) => _registerMode ? null : _submit(),
                validator: (value) {
                  final text = value ?? '';
                  if (text.isEmpty) return 'Password is required.';
                  if (_registerMode && text.length < 8) {
                    return 'Use at least 8 characters.';
                  }
                  return null;
                },
              ),
              if (_registerMode) ...[
                const SizedBox(height: 16),
                AppTextField(
                  key: const ValueKey('register-confirm'),
                  controller: _confirm,
                  label: 'Confirm password',
                  hint: 'Re-enter your password',
                  prefixIcon: Icons.lock_reset_outlined,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  enabled: !busy,
                  onSubmitted: (_) => _submit(),
                  validator: (value) {
                    if (value != _password.text) {
                      return 'Passwords do not match.';
                    }
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        LoadingButton(
          expand: true,
          label: _registerMode ? 'Create account' : 'Sign in',
          icon: _registerMode
              ? Icons.person_add_alt_1_outlined
              : Icons.login_rounded,
          loading: busy,
          onPressed: _submit,
        ),
        const SizedBox(height: 18),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              _registerMode
                  ? 'Already have an account?'
                  : "Don't have an account?",
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            TextButton(
              onPressed: busy ? null : _toggleMode,
              child: Text(_registerMode ? 'Sign in' : 'Register'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Row(
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 14,
              color: AppTheme.textSecondary,
            ),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Passwords are salted and hashed — LockNote never stores them in plain text.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Gradient panel with product branding (wide screens only).
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(56),
      decoration: const BoxDecoration(gradient: AppTheme.brandGradient),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              const Text(
                'LockNote',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          const Text(
            'Your notes,\nlocked down.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 40,
              height: 1.15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'A secure personal notes system: register, sign in, and manage '
            'your private notes — only you can ever read them.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 15.5,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 36),
          _FeatureRow(
            icon: Icons.enhanced_encryption_outlined,
            text: 'PBKDF2 password hashing — plain text is never stored',
          ),
          const SizedBox(height: 14),
          _FeatureRow(
            icon: Icons.verified_user_outlined,
            text: 'Server-side authentication on every request',
          ),
          const SizedBox(height: 14),
          _FeatureRow(
            icon: Icons.folder_shared_outlined,
            text: 'Per-user data isolation enforced in SQL',
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact logo + wordmark shown above the form on narrow screens.
class _CompactLogo extends StatelessWidget {
  const _CompactLogo();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.lock_rounded, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),
        const Text(
          'LockNote',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}