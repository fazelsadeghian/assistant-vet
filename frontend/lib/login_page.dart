import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dashboard_page.dart';
import 'forgot_password_page.dart';
import 'signup_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _hidePassword = true;
  bool _rememberMe = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }

    final email = value.trim();

    final valid = RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(email);

    if (!valid) {
      return 'Enter a valid email address';
    }

    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }

    return null;
  }

  void _showMessage(
    String message, {
    required bool error,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error
            ? const Color(0xFFB43C3C)
            : const Color(0xFF087B76),
        content: Text(message),
      ),
    );
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final response =
          await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      if (response.user == null || response.session == null) {
        _showMessage(
          'Login failed. Please check your email and password.',
          error: true,
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

      final message = error.message.toLowerCase();

      if (message.contains('invalid login credentials') ||
          message.contains('invalid credentials')) {
        _showMessage(
          'Incorrect email or password.',
          error: true,
        );
      } else if (message.contains('email not confirmed') ||
          message.contains('not confirmed')) {
        _showMessage(
          'Your email is not verified yet. Please verify your email first.',
          error: true,
        );
      } else if (message.contains('rate limit') ||
          message.contains('too many')) {
        _showMessage(
          'Too many login attempts. Please wait and try again.',
          error: true,
        );
      } else {
        _showMessage(
          error.message,
          error: true,
        );
      }
    } catch (_) {
      if (!mounted) return;

      _showMessage(
        'Could not connect to the server. Please check your internet connection.',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openForgotPassword() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ForgotPasswordPage(),
      ),
    );

    if (!mounted) return;

    if (result != null && result.isNotEmpty) {
      _showMessage(
        result,
        error: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;

          final formCard = Container(
            width: 470,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: const Color(0xFFE4ECEC),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x16000000),
                  blurRadius: 34,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Welcome to Assistant Vet',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF102F46),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign in to your veterinary workspace.',
                    style: TextStyle(
                      color: Color(0xFF71818A),
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 28),

                  const Text(
                    'Email',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),

                  TextFormField(
                    controller: _emailController,
                    validator: _validateEmail,
                    enabled: !_loading,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'doctor@example.com',
                      prefixIcon: Icon(
                        Icons.email_outlined,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  const Text(
                    'Password',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),

                  TextFormField(
                    controller: _passwordController,
                    validator: _validatePassword,
                    enabled: !_loading,
                    obscureText: _hidePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) {
                      if (!_loading) {
                        _login();
                      }
                    },
                    decoration: InputDecoration(
                      hintText: '••••••••',
                      prefixIcon: const Icon(
                        Icons.lock_outline,
                      ),
                      suffixIcon: IconButton(
                        onPressed: _loading
                            ? null
                            : () {
                                setState(() {
                                  _hidePassword =
                                      !_hidePassword;
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

                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Checkbox(
                        value: _rememberMe,
                        onChanged: _loading
                            ? null
                            : (value) {
                                setState(() {
                                  _rememberMe =
                                      value ?? false;
                                });
                              },
                      ),
                      const Text('Remember me'),

                      const Spacer(),

                      TextButton(
                        onPressed: _loading
                            ? null
                            : _openForgotPassword,
                        child: const Text(
                          'Forgot password?',
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            const Color(0xFF0AA7A0),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(17),
                        ),
                      ),
                      onPressed:
                          _loading ? null : _login,
                      icon: _loading
                          ? const SizedBox(
                              width: 19,
                              height: 19,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.login,
                            ),
                      label: Text(
                        _loading
                            ? 'Signing in...'
                            : 'Login',
                        style: const TextStyle(
                          fontWeight:
                              FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      const Expanded(
                        child: Divider(),
                      ),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        child: Text(
                          'New user?',
                          style: TextStyle(
                            color:
                                Colors.grey.shade600,
                          ),
                        ),
                      ),
                      const Expanded(
                        child: Divider(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _loading
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const SignUpPage(),
                                ),
                              );
                            },
                      icon: const Icon(
                        Icons.person_add_alt_1_outlined,
                      ),
                      label: const Text(
                        'Create veterinary account',
                        style: TextStyle(
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );

          if (compact) {
            return Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/dog_cat.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    color: const Color(0xAA064B60),
                  ),
                ),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: formCard,
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                flex: 6,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        'assets/dog_cat.png',
                        fit: BoxFit.cover,
                        alignment: Alignment.centerRight,
                      ),
                    ),

                    Positioned.fill(
                      child: Container(
                        decoration:
                            const BoxDecoration(
                          gradient:
                              LinearGradient(
                            begin:
                                Alignment.centerLeft,
                            end:
                                Alignment.centerRight,
                            colors: [
                              Color(0xF2064B60),
                              Color(0xD00B7779),
                              Color(0x330B7779),
                            ],
                            stops: [
                              0,
                              .5,
                              1,
                            ],
                          ),
                        ),
                      ),
                    ),

                    SafeArea(
                      child: Padding(
                        padding:
                            const EdgeInsets.all(42),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 66,
                                  height: 66,
                                  padding:
                                      const EdgeInsets.all(
                                    9,
                                  ),
                                  decoration:
                                      BoxDecoration(
                                    color: Colors.white,
                                    borderRadius:
                                        BorderRadius.circular(
                                      20,
                                    ),
                                  ),
                                  child: Image.asset(
                                    'assets/logo.png',
                                    fit: BoxFit.contain,
                                  ),
                                ),

                                const SizedBox(
                                  width: 14,
                                ),

                                const Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                  children: [
                                    Text(
                                      'Assistant Vet',
                                      style:
                                          TextStyle(
                                        color:
                                            Colors.white,
                                        fontSize: 25,
                                        fontWeight:
                                            FontWeight
                                                .w800,
                                      ),
                                    ),
                                    Text(
                                      'دستیار دامپزشک',
                                      style:
                                          TextStyle(
                                        color: Color(
                                          0xFFD7F2EF,
                                        ),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            const Spacer(),

                            const SizedBox(
                              width: 520,
                              child: Text(
                                'Smarter veterinary decisions,\nwith evidence at every step.',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 40,
                                  height: 1.15,
                                  fontWeight:
                                      FontWeight.w800,
                                ),
                              ),
                            ),

                            const SizedBox(
                              height: 18,
                            ),

                            const SizedBox(
                              width: 540,
                              child: Text(
                                'One workspace for clinical findings, laboratory data, microscopy, imaging and evidence.',
                                style: TextStyle(
                                  color: Color(
                                    0xFFE6F6F5,
                                  ),
                                  fontSize: 16,
                                  height: 1.6,
                                ),
                              ),
                            ),

                            const Spacer(),

                            const Text(
                              'Clinical decision support — final decisions remain with the veterinarian.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                flex: 4,
                child: Container(
                  color: const Color(0xFFF4F8F8),
                  child: Center(
                    child: SingleChildScrollView(
                      padding:
                          const EdgeInsets.all(38),
                      child: formCard,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
