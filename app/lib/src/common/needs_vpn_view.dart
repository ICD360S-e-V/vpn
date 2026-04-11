// ICD360SVPN — lib/src/common/needs_vpn_view.dart
//
// Reusable empty-state widget shown by Peers and Health when the
// agent at https://10.8.0.1:8443 is unreachable. The cause is
// invariably "the WireGuard tunnel isn't active yet" so we show a
// friendly Romanian prompt and a Retry button.

import 'package:flutter/material.dart';

class NeedsVpnView extends StatelessWidget {
  const NeedsVpnView({
    super.key,
    required this.onRetry,
    this.isRetrying = false,
  });

  final VoidCallback onRetry;
  final bool isRetrying;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.vpn_lock_outlined,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Conectează-te la VPN',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Datele se afișează doar prin tunelul WireGuard. '
                'Apasă butonul "Connect to VPN" din colțul '
                'din dreapta-jos și activează tunelul în WireGuard. '
                'Apoi revino aici și apasă Reîncarcă.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: isRetrying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh),
                label: Text(isRetrying ? 'Se verifică…' : 'Reîncarcă'),
                onPressed: isRetrying ? null : onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
