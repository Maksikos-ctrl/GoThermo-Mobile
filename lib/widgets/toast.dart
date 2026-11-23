import 'package:flutter/material.dart';

/// A short message at the bottom of the screen.
void showToast(BuildContext context, String text) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
}

/// Shows [error] if there is one (the controller's actions return it).
void toastIfError(BuildContext context, String? error) {
  if (error != null && error.isNotEmpty) showToast(context, error);
}
