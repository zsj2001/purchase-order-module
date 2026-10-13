import 'package:flutter/material.dart';

class AppTheme {
  // ── Theme-driven colors (sourced from dark.dart / light.dart's ColorScheme) ──
  static Color primary(BuildContext context) => Theme.of(context).colorScheme.primary;

  static Color danger(BuildContext context) => Theme.of(context).colorScheme.onError;

  static Color textPrimary(BuildContext context) => Theme.of(context).colorScheme.onSurface;

  static Color textSecondary(BuildContext context) => Theme.of(context).colorScheme.secondary;

  static Color surface(BuildContext context) => Theme.of(context).colorScheme.surface;

  static Color background(BuildContext context) => Theme.of(context).scaffoldBackgroundColor;

  // dark.dart / light.dart don't define a ColorScheme.outline, so this stays
  // a brightness check rather than a colorScheme lookup.
  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black;

  // ── Status color helpers (semantic — same meaning regardless of theme) ───
  static Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'new':              return const Color(0xFF3498DB);
      case 'draft':            return const Color(0xFF95A5A6);
      case 'pending approval': return const Color(0xFFE67E22);
      case 'posted':           return const Color(0xFF2980B9);
      case 'partial':          return const Color(0xFF8E44AD);
      case 'completed':        return const Color(0xFF27AE60);
      case 'cancelled':        return const Color(0xFFE74C3C);
      default:                 return const Color(0xFF7F8C8D);
    }
  }

  static Color statusBgColor(String status) => statusColor(status).withValues(alpha: 0.1);

  // ── Approval-log action colors (Reject / Approve) ─────────────────────────
  static Color actionLogColor(String action, BuildContext context) {
    switch (action.toLowerCase()) {
      case 'reject':
        return danger(context);
      case 'approve':
        return const Color(0xFF27AE60);
      default:
        return const Color(0xFF7F8C8D);
    }
  }
}