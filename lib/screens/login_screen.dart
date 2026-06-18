import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
const LoginScreen({super.key});

@override
State<LoginScreen> createState() =>
_LoginScreenState();
}

class _LoginScreenState
extends State<LoginScreen> {
final authService = AuthService();

final emailController =
TextEditingController();

final passwordController =
TextEditingController();

bool isLoading = false;

String? error;

Future<void> login() async {
try {
setState(() {
isLoading = true;
error = null;
});

  await authService.login(
    email: emailController.text.trim(),
    password:
        passwordController.text.trim(),
  );

  if (!mounted) return;

  Navigator.pushReplacementNamed(
    context,
    '/',
  );
} catch (e) {
  setState(() {
    error = e.toString();
  });
} finally {
  if (mounted) {
    setState(() {
      isLoading = false;
    });
  }
}


}

Future<void> signInWithGoogle() async {
try {
setState(() {
error = null;
});

  await authService.signInWithGoogle();

  if (!mounted) return;

  Navigator.pushReplacementNamed(
    context,
    '/',
  );
} catch (e) {
  setState(() {
    error = e.toString();
  });
}


}

Future<void> signInWithApple() async {
try {
setState(() {
error = null;
});

  await authService.signInWithApple();

  if (!mounted) return;

  Navigator.pushReplacementNamed(
    context,
    '/',
  );
} catch (e) {
  setState(() {
    error = e.toString();
  });
}

}

@override
void dispose() {
emailController.dispose();

passwordController.dispose();

super.dispose();

}

@override
Widget build(BuildContext context) {
return Scaffold(
appBar: AppBar(
title: const Text(
'Login',
),
),
body: SingleChildScrollView(
padding:
const EdgeInsets.all(16),
child: Column(
children: [
TextField(
controller:
emailController,
keyboardType:
TextInputType.emailAddress,
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

        const SizedBox(height: 12),

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
                : const Text(
                    'Login',
                  ),
          ),
        ),

        TextButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const RegisterScreen(),
              ),
            );
          },
          child: const Text(
            'Create Account',
          ),
        ),

        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed:
                signInWithGoogle,
            icon: const Icon(
              Icons.g_mobiledata,
              size: 32,
            ),
            label: const Text(
              'Continue with Google',
            ),
          ),
        ),

        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed:
                signInWithApple,
            icon: const Icon(
              Icons.apple,
              size: 24,
            ),
            label: const Text(
              'Continue with Apple',
            ),
          ),
        ),
      ],
    ),
  ),
);

}
}
