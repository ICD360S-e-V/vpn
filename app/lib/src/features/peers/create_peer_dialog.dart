// ICD360SVPN — lib/src/features/peers/create_peer_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../common/qr_code_view.dart';
import '../../models/api_error.dart';
import '../../models/peer_create_response.dart';

class CreatePeerDialog extends StatefulWidget {
  const CreatePeerDialog({super.key, required this.client});

  final ApiClient client;

  @override
  State<CreatePeerDialog> createState() => _CreatePeerDialogState();
}

class _CreatePeerDialogState extends State<CreatePeerDialog> {
  final TextEditingController _nameController = TextEditingController();
  bool _creating = false;
  PeerCreateResponse? _result;
  String? _error;
  bool _showQr = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _creating) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final res = await widget.client.createPeer(name: name);
      if (!mounted) return;
      setState(() => _result = res);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _copyConfig() {
    if (_result == null) return;
    Clipboard.setData(ClipboardData(text: _result!.clientConfig));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Config copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _result == null ? _buildInputBody() : _buildResultBody(_result!),
        ),
      ),
    );
  }

  Widget _buildInputBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('New peer', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Pick a label, e.g. "phone" or "work-laptop". The server allocates the IP and generates the keys.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _create(),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _creating ? null : _create,
              child: Text(_creating ? 'Creating…' : 'Create'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResultBody(PeerCreateResponse res) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Peer created', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Save this config or scan the QR with WireGuard mobile.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _showQr
              ? Center(child: QrCodeView(payload: res.clientConfig, size: 320))
              : Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      res.clientConfig,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            TextButton.icon(
              icon: Icon(_showQr ? Icons.text_snippet : Icons.qr_code),
              label: Text(_showQr ? 'Show text' : 'Show QR code'),
              onPressed: () => setState(() => _showQr = !_showQr),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copy config'),
              onPressed: _copyConfig,
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ],
    );
  }
}
