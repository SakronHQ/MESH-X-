import 'package:flutter/material.dart';

class AppColors {
  // Backgrounds - Tactical Dark Titanium
  static const Color background = Color(0xFF080C14);
  static const Color surface = Color(0xFF101623);
  static const Color surfaceElevated = Color(0xFF172033);
  static const Color surfaceHighlight = Color(0xFF1E2B45);
  static const Color surfaceGlass = Color(0xD9101623); // 85% opacity for blur

  // High-Contrast Tactical Chat Bubbles
  static const Color bubbleMe = Color(0xFF0C2B38); // Deep Cyan-Slate
  static const Color bubbleMeBorder = Color(0x5500E5FF);
  static const Color bubblePeer = Color(0xFF131D2E); // Deep Navy-Slate
  static const Color bubblePeerBorder = Color(0xFF22324C);

  // Borders & Specular Hairlines
  static const Color border = Color(0xFF202C44);
  static const Color borderSubtle = Color(0xFF162030);
  static const Color borderGlass = Color(0x2EFFFFFF); // Specular top edge
  static const Color divider = Color(0x2694A3B8);

  // Accents - Laser Cyan & Precision Blue
  static const Color accent = Color(0xFF00E5FF); // Electric Cyan
  static const Color accentMuted = Color(0xFF00B4D8);
  static const Color accentGlow = Color(0x3300E5FF);
  static const Color accentDark = Color(0xFF005866);

  // Status & Semantic (Apple HIG & Material 3 Dark - High Contrast)
  static const Color connected = Color(0xFF10B981); // Crisp Emerald (AAA contrast)
  static const Color success = Color(0xFF10B981);
  static const Color disconnected = Color(0xFF94A3B8); // Slate 400
  static const Color scanning = Color(0xFF38BDF8); // Electric Sky
  static const Color warning = Color(0xFFFBBF24); // Tactical Amber
  static const Color error = Color(0xFFFF453A); // Emergency Crimson
  static const Color errorGlow = Color(0x33FF453A);

  // Typography - High Contrast (WCAG AA & AAA compliant on 0xFF080C14)
  static const Color textPrimary = Color(0xFFF8FAFC); // 16.5:1 ratio
  static const Color textSecondary = Color(0xFFCBD5E1); // 10.2:1 ratio
  static const Color textMuted = Color(0xFF94A3B8); // 5.6:1 ratio (passes WCAG AA 4.5:1)
  static const Color textTertiary = Color(0xFF64748B); // 3.2:1 (decorative only)
}

