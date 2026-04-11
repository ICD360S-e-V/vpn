// ICD360SVPN — lib/src/features/enrollment/enrollment_screen.dart
//
// First-run screen: paste the single base64 blob produced by
// `vpn-agent issue-bundle <name>`, hit Connect, done. The previous
// SwiftUI version had three TextEditor blocks for three PEMs; M4.2
// reduced that to one input.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';

class EnrollmentScreen extends ConsumerStatefulWidget {
  const EnrollmentScreen({super.key});

  @override
  ConsumerState<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends ConsumerState<EnrollmentScreen> {
  final TextEditingController _bundleController = TextEditingController();
  bool _connecting = false;

  @override
  void dispose() {
    _bundleController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_bundleController.text.trim().isEmpty || _connecting) return;
    setState(() => _connecting = true);
    try {
      await ref
          .read(appPhaseProvider.notifier)
          .enrollFromBundleString(_bundleController.text);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(appPhaseProvider);
    final lastError = phase is NeedsEnrollment ? phase.lastError : null;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Enroll this device',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Run on the server:\n'
                  '    sudo vpn-agent issue-bundle <your-name>\n'
                  'Paste the printed line below.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _bundleController,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Enrollment bundle',
                    hintText: 'H4sIAAAAAAAA/5...',
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
                if (lastError != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    lastError,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.lock_open),
                  label: Text(_connecting ? 'Connecting…' : 'Connect'),
                  onPressed: _connecting ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
