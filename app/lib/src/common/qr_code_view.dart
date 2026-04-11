// ICD360SVPN — lib/src/common/qr_code_view.dart
//
// Thin wrapper around qr_flutter so the view layer doesn't have to
// know which package generates the QR. The payload is the rendered
// WireGuard client config string returned by POST /v1/peers; the
// mobile WireGuard app accepts it as-is.

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrCodeView extends StatelessWidget {
  const QrCodeView({super.key, required this.payload, this.size = 256});

  final String payload;
  final double size;

  @override
  Widget build(BuildContext context) {
    return QrImageView(
      data: payload,
      version: QrVersions.auto,
      size: size,
      backgroundColor: Colors.white,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
    );
  }
}
