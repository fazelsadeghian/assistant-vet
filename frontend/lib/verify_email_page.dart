import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dashboard_page.dart';

class VerifyEmailPage extends StatefulWidget {
  final String email;

  const VerifyEmailPage({
    super.key,
    required this.email,
  });

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());

  final List<FocusNode> _focusNodes =
      List.generate(6, (_) => FocusNode());

  bool _isVerifying = false;
  bool _isResending = false;

  int _resendSeconds = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();

    for (final controller in _controllers) {
      controller.dispose();
    }

    for (final node in _focusNodes) {
      node.dispose();
    }

    super.dispose();
  }

  String get _code {
    return _controllers.map((controller) => controller.text).join();
  }

  void _showMessage(
    String message, {
    required bool isError,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError
            ? const Color(0xFFB43C3C)
            : const Color(0xFF087B76),
        content: Text(message),
      ),
    );
  }

  Future<void> _verifyCode() async {
    FocusScope.of(context).unfocus();

    final code = _code.trim();

    if (code.length != 6) {
      _showMessage(
        'Please enter the complete 6-digit verification code.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isVerifying = true;
    });

    try {
      final response =
          await Supabase.instance.client.auth.verifyOTP(
        email: widget.email,
        token: code,
        type: OtpType.signup,
      );

      if (!mounted) return;

      if (response.user == null) {
        _showMessage(
          'The verification code could not be confirmed.',
          isError: true,
        );
        return;
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const DashboardPage(),
        ),
        (route) => false,
      );
    } on AuthException catch (error) {
      if (!mounted) return;

      String message =
          'Invalid or expired verification code.';

      final lower = error.message.toLowerCase();

      if (lower.contains('expired')) {
        message =
            'This verification code has expired. Please request a new code.';
      } else if (lower.contains('invalid')) {
        message =
            'The verification code is incorrect. Please check the email and try again.';
      } else if (lower.contains('token')) {
        message =
            'The verification code is invalid or expired.';
      }

      _showMessage(
        message,
        isError: true,
      );
    } catch (_) {
      if (!mounted) return;

      _showMessage(
        'Could not verify the code. Please check your internet connection.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  Future<void> _resendCode() async {
    if (_resendSeconds > 0 || _isResending) {
      return;
    }

    setState(() {
      _isResending = true;
    });

    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
      );

      if (!mounted) return;

      for (final controller in _controllers) {
        controller.clear();
      }

      _focusNodes.first.requestFocus();

      _startResendTimer();

      _showMessage(
        'A new 6-digit verification code was sent to your email.',
        isError: false,
      );
    } on AuthException catch (error) {
      if (!mounted) return;

      String message = error.message;

      if (error.message.toLowerCase().contains('rate')) {
        message =
            'Please wait before requesting another verification code.';
      }

      _showMessage(
        message,
        isError: true,
      );
    } catch (_) {
      if (!mounted) return;

      _showMessage(
        'Could not resend the code. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  void _startResendTimer() {
    _timer?.cancel();

    setState(() {
      _resendSeconds = 60;
    });

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (_resendSeconds <= 1) {
          timer.cancel();

          setState(() {
            _resendSeconds = 0;
          });

          return;
        }

        setState(() {
          _resendSeconds--;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F8),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Container(
            width: 540,
            padding: const EdgeInsets.all(36),
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5F6F4),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.mark_email_read_outlined,
                    size: 38,
                    color: Color(0xFF0A8B86),
                  ),
                ),

                const SizedBox(height: 22),

                const Text(
                  'Verify your email',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF102F46),
                  ),
                ),

                const SizedBox(height: 10),

                const Text(
                  'We sent a 6-digit verification code to',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF71818A),
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  widget.email,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF087B76),
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 30),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    6,
                    (index) {
                      return Container(
                        width: 54,
                        height: 62,
                        margin: const EdgeInsets.symmetric(
                          horizontal: 5,
                        ),
                        child: TextField(
                          controller: _controllers[index],
                          focusNode: _focusNodes[index],
                          enabled: !_isVerifying,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          maxLength: 1,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF102F46),
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            counterText: '',
                            contentPadding: EdgeInsets.zero,
                            filled: true,
                            fillColor: const Color(0xFFF7FAFA),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(15),
                              borderSide: const BorderSide(
                                color: Color(0xFFD5E3E3),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(15),
                              borderSide: const BorderSide(
                                color: Color(0xFFD5E3E3),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(15),
                              borderSide: const BorderSide(
                                color: Color(0xFF0AA7A0),
                                width: 1.8,
                              ),
                            ),
                          ),
                          onChanged: (value) {
                            if (value.isNotEmpty) {
                              if (index < 5) {
                                _focusNodes[index + 1]
                                    .requestFocus();
                              } else {
                                _focusNodes[index].unfocus();
                              }
                            } else if (index > 0) {
                              _focusNodes[index - 1]
                                  .requestFocus();
                            }
                          },
                          onSubmitted: (_) {
                            if (index == 5) {
                              _verifyCode();
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF0AA7A0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                    onPressed:
                        _isVerifying ? null : _verifyCode,
                    icon: _isVerifying
                        ? const SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.verified_outlined,
                          ),
                    label: Text(
                      _isVerifying
                          ? 'Verifying...'
                          : 'Verify email',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                const Text(
                  "Didn't receive the code?",
                  style: TextStyle(
                    color: Color(0xFF71818A),
                  ),
                ),

                const SizedBox(height: 2),

                TextButton.icon(
                  onPressed: _resendSeconds > 0 ||
                          _isResending
                      ? null
                      : _resendCode,
                  icon: _isResending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.refresh,
                        ),
                  label: Text(
                    _resendSeconds > 0
                        ? 'Resend in $_resendSeconds seconds'
                        : 'Resend verification code',
                  ),
                ),

                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFA),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 19,
                        color: Color(0xFF0A8B86),
                      ),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Your account will not be activated until the email verification code is confirmed.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: Color(0xFF647781),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                TextButton(
                  onPressed: _isVerifying
                      ? null
                      : () {
                          Navigator.pop(context);
                        },
                  child: const Text(
                    'Back to registration',
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