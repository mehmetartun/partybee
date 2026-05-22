import 'package:flutter/material.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:google_sign_in_web/google_sign_in_web.dart' as web_plugin;

Widget buildGoogleSignInButton({
  required VoidCallback onPressed,
  required bool isLoading,
}) {
  return Container(
    height: 40,
    constraints: const BoxConstraints(maxWidth: 400),
    child: (GoogleSignInPlatform.instance as web_plugin.GoogleSignInPlugin).renderButton(
      configuration: web_plugin.GSIButtonConfiguration(
        theme: web_plugin.GSIButtonTheme.filledBlack,
        size: web_plugin.GSIButtonSize.large,
        shape: web_plugin.GSIButtonShape.pill,
        text: web_plugin.GSIButtonText.signinWith,
      ),
    ),
  );
}
