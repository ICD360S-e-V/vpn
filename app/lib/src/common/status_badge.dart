// ICD360SVPN — lib/src/common/status_badge.dart

import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  factory StatusBadge.forStatus(String status) {
    final lc = status.toLowerCase();
    final color = switch (lc) {
      'ok' => Colors.green,
      'degraded' => Colors.orange,
      _ => Colors.red,
    };
    return StatusBadge(text: status.toUpperCase(), color: color);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
