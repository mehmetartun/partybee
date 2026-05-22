import 'package:flutter/material.dart';

Widget buildGoogleSignInButton({
  required VoidCallback onPressed,
  required bool isLoading,
}) {
  return OutlinedButton(
    onPressed: isLoading ? null : onPressed,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.network(
          'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
          height: 20,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.g_mobiledata_rounded, size: 24),
        ),
        const SizedBox(width: 12),
        const Text('Sign In with Google'),
      ],
    ),
  );
}
