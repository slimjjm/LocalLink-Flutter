import 'package:flutter/material.dart';

import '../services/auth_service.dart';

// =====================================================
// LOGIN SCREEN
// =====================================================

class LoginScreen extends StatefulWidget {

  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() =>
      _LoginScreenState();
}

class _LoginScreenState
    extends State<LoginScreen> {

final authService = AuthService();
String? error;

  final emailController =
      TextEditingController();

  final passwordController =
      TextEditingController();

  bool isLoading = false;

  // =====================================================
  // LOGIN
  // =====================================================

  Future<void> login() async {

    try {

      setState(() {

        isLoading = true;
        error = null;
      });

     await authService.login(

  email: emailController.text,

  password: passwordController.text,
);

      if (!mounted) return;

      Navigator.pop(context);

    } catch (e) {

      setState(() {

        error = e.toString()
                .contains('user-not-found')

            ? 'No account found'

            : e.toString()
                    .contains('wrong-password')

                ? 'Incorrect password'

                : 'Login failed';
      });

    } finally {

      if (mounted) {

        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // =====================================================
  // REGISTER
  // =====================================================

  Future<void> register() async {

    try {

      setState(() {

        isLoading = true;
        error = null;
      });

  await authService.register(

  email: emailController.text,

  password: passwordController.text,
);

     

      if (!mounted) return;

      Navigator.pop(context);

    } catch (e) {

      setState(() {

        error = e.toString()
                .contains(
                    'email-already-in-use')

            ? 'Email already registered'

            : 'Register failed';
      });

    } finally {

      if (mounted) {

        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // =====================================================
  // CLEANUP
  // =====================================================

  @override
  void dispose() {

    emailController.dispose();
    passwordController.dispose();

    super.dispose();
  }

  // =====================================================
  // UI
  // =====================================================

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text('Login'),
      ),

      body: Padding(

        padding:
            const EdgeInsets.all(16),

        child: Column(

          children: [

            TextField(

              controller:
                  emailController,

              keyboardType:
                  TextInputType
                      .emailAddress,

              decoration:
                  const InputDecoration(
                labelText: 'Email',
              ),
            ),

            const SizedBox(height: 12),

            TextField(

              controller:
                  passwordController,

              obscureText: true,

              decoration:
                  const InputDecoration(
                labelText: 'Password',
              ),
            ),

            const SizedBox(height: 20),

            if (error != null)

              Text(

                error!,

                style: const TextStyle(
                  color: Colors.red,
                ),
              ),

            const SizedBox(height: 10),

            SizedBox(

              width: double.infinity,

              child: ElevatedButton(

                onPressed:
                    isLoading
                        ? null
                        : login,

                child: isLoading

                    ? const SizedBox(

                        width: 20,
                        height: 20,

                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )

                    : const Text('Login'),
              ),
            ),

            TextButton(

              onPressed:
                  isLoading
                      ? null
                      : register,

              child:
                  const Text(
                'Create account',
              ),
            ),
            const SizedBox(height: 16),

SizedBox(

  width: double.infinity,

  child: OutlinedButton.icon(

    onPressed: () async {

      try {

        await authService
            .signInWithGoogle();

        if (!mounted) return;

        Navigator.pop(context);

      } catch (e) {

        setState(() {

          error = e.toString();
        });
      }
    },

    icon: const Icon(
      Icons.g_mobiledata,
      size: 32,
    ),

    label: const Text(
      'Continue with Google',
    ),
  ),
),
          ],
        ),
      ),
    );
  }
}