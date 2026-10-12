import 'package:flutter/material.dart';

class SyncErrorService {
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  static void report(String message) {
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }
}
