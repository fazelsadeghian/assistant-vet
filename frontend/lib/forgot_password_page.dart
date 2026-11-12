
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _codeControllers =
      List.generate(6, (_) => TextEditingController());
  final _codeFocusNodes =
      List.generate(6, (_) => FocusNode());

  int _step = 0;
  bool _loading = false;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;

  int _resendSeconds = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();

    for (final controller in _codeControllers) {
      controller.dispose();
    }
    for (final node in _codeFocusNodes) {
      node.dispose();
    }

    super.dispose();
  }

  String get _code =>
      _codeControllers.map((controller) => controller.text).join();

  bool _isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
        .hasMatch(value.trim());
  }

  String? _passwordError(String value) {
    if (value.length < 8) return 'Use at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Add at least one uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Add at least one lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Add at least one number';
    }
    return null;
  }

  void _message(String text, {required bool error}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            error ? const Color(0xFFB43C3C) : const Color(0xFF087B76),
        content: Text(text),
      ),
    );
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendSeconds = 60);

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (_resendSeconds <= 1) {
          timer.cancel();
          setState(() => _resendSeconds = 0);
          return;
        }

        setState(() => _resendSeconds--);
      },
    );
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();

    if (!_isValidEmail(email)) {
      _message('Enter a valid email address.', error: true);
      return;
    }

    setState(() => _loading = true);

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);

      if (!mounted) return;

      setState(() => _step = 1);
      _startTimer();

      _message(
        'If an account exists for this email, a recovery code has been sent.',
        error: false,
      );
    } on AuthException catch (error) {
      if (!mounted) return;

      final lower = error.message.toLowerCase();
      if (lower.contains('rate') || lower.contains('too many')) {
        _message(
          'Too many requests. Please wait and try again.',
          error: true,
        );
      } else {
        _message(error.message, error: true);
      }
    } catch (_) {
      if (!mounted) return;
      _message(
        'Could not send the recovery email.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendCode() async {
    if (_loading || _resendSeconds > 0) return;

    for (final controller in _codeControllers) {
      controller.clear();
    }

    await _sendCode();

    if (mounted && _step == 1) {
      _codeFocusNodes.first.requestFocus();
    }
  }

  Future<void> _verifyCode() async {
    if (_code.length != 6) {
      _message(
        'Enter the complete 6-digit recovery code.',
        error: true,
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final response =
          await Supabase.instance.client.auth.verifyOTP(
        email: _emailController.text.trim(),
        token: _code,
        type: OtpType.recovery,
      );

      if (!mounted) return;

      if (response.user == null || response.session == null) {
        _message(
          'The recovery code could not be verified.',
          error: true,
        );
        return;
      }

      setState(() => _step = 2);
    } on AuthException {
      if (!mounted) return;
      _message(
        'The recovery code is incorrect or expired.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updatePassword() async {
    final password = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    final validation = _passwordError(password);

    if (validation != null) {
      _message(validation, error: true);
      return;
    }

    if (password != confirm) {
      _message('Passwords do not match.', error: true);
      return;
    }

    setState(() => _loading = true);

    try {
      final response =
          await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );

      if (!mounted) return;

      if (response.user == null) {
        _message(
          'The password could not be updated.',
          error: true,
        );
        return;
      }

      await Supabase.instance.client.auth.signOut();

      if (!mounted) return;

      Navigator.pop(
        context,
        'Password updated successfully. Sign in with your new password.',
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      _message(error.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _steps() {
    Widget dot(String number, String label, bool active, bool done) {
      return Column(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: active
                ? const Color(0xFF0AA7A0)
                : const Color(0xFFE3E9E9),
            child: done
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : Text(
                    number,
                    style: TextStyle(
                      color: active
                          ? Colors.white
                          : const Color(0xFF7B898F),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active
                  ? const Color(0xFF087B76)
                  : const Color(0xFF859399),
            ),
          ),
        ],
      );
    }

    Widget line(bool active) {
      return Expanded(
        child: Container(
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          color: active
              ? const Color(0xFF0AA7A0)
              : const Color(0xFFDCE5E5),
        ),
      );
    }

    return Row(
      children: [
        dot('1', 'Email', true, _step > 0),
        line(_step > 0),
        dot('2', 'Verify', _step >= 1, _step > 1),
        line(_step > 1),
        dot('3', 'New password', _step >= 2, false),
      ],
    );
  }

  Widget _emailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Forgot your password?',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Color(0xFF102F46),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter the email address linked to your Assistant Vet account.',
          style: TextStyle(
            color: Color(0xFF71818A),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 26),
        TextField(
          controller: _emailController,
          enabled: !_loading,
          keyboardType: TextInputType.emailAddress,
          onSubmitted: (_) => _sendCode(),
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'doctor@example.com',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0AA7A0),
            ),
            onPressed: _loading ? null : _sendCode,
            icon: _loading
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.mark_email_unread_outlined),
            label: Text(
              _loading ? 'Sending...' : 'Send recovery code',
            ),
          ),
        ),
      ],
    );
  }

  Widget _codeStep() {
    return Column(
      children: [
        const Icon(
          Icons.password_outlined,
          size: 46,
          color: Color(0xFF0A8B86),
        ),
        const SizedBox(height: 16),
        const Text(
          'Enter recovery code',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Color(0xFF102F46),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _emailController.text.trim(),
          style: const TextStyle(
            color: Color(0xFF087B76),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 26),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            6,
            (index) {
              return Container(
                width: 52,
                height: 60,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: TextField(
                  controller: _codeControllers[index],
                  focusNode: _codeFocusNodes[index],
                  enabled: !_loading,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 1,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                    filled: true,
                    fillColor: const Color(0xFFF7FAFA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onChanged: (value) {
                    if (value.isNotEmpty && index < 5) {
                      _codeFocusNodes[index + 1].requestFocus();
                    } else if (value.isEmpty && index > 0) {
                      _codeFocusNodes[index - 1].requestFocus();
                    }
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0AA7A0),
            ),
            onPressed: _loading ? null : _verifyCode,
            icon: _loading
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.verified_outlined),
            label: Text(
              _loading ? 'Verifying...' : 'Verify recovery code',
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed:
              _loading || _resendSeconds > 0 ? null : _resendCode,
          icon: const Icon(Icons.refresh),
          label: Text(
            _resendSeconds > 0
                ? 'Resend in $_resendSeconds seconds'
                : 'Resend recovery code',
          ),
        ),
      ],
    );
  }

  Widget _passwordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Create a new password',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Color(0xFF102F46),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose a new password for your Assistant Vet account.',
          style: TextStyle(
            color: Color(0xFF71818A),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 26),
        TextField(
          controller: _newPasswordController,
          enabled: !_loading,
          obscureText: _hidePassword,
          decoration: InputDecoration(
            labelText: 'New password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () {
                setState(() {
                  _hidePassword = !_hidePassword;
                });
              },
              icon: Icon(
                _hidePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _confirmPasswordController,
          enabled: !_loading,
          obscureText: _hideConfirmPassword,
          onSubmitted: (_) => _updatePassword(),
          decoration: InputDecoration(
            labelText: 'Confirm new password',
            prefixIcon: const Icon(Icons.lock_reset_outlined),
            suffixIcon: IconButton(
              onPressed: () {
                setState(() {
                  _hideConfirmPassword = !_hideConfirmPassword;
                });
              },
              icon: Icon(
                _hideConfirmPassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Use at least 8 characters with uppercase, lowercase and a number.',
          style: TextStyle(
            color: Color(0xFF7A8990),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0AA7A0),
            ),
            onPressed: _loading ? null : _updatePassword,
            icon: _loading
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.lock_reset_outlined),
            label: Text(
              _loading ? 'Updating...' : 'Update password',
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _step == 0
        ? _emailStep()
        : _step == 1
            ? _codeStep()
            : _passwordStep();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Password recovery',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF102F46),
          ),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(26),
          child: Container(
            width: 560,
            padding: const EdgeInsets.all(34),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: const Color(0xFFE3ECEC),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 30,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              children: [
                _steps(),
                const SizedBox(height: 30),
                body,
                const SizedBox(height: 14),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () {
                          if (_step == 0) {
                            Navigator.pop(context);
                          } else {
                            setState(() {
                              _step--;
                            });
                          }
                        },
                  child: Text(
                    _step == 0 ? 'Back to sign in' : 'Back',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
