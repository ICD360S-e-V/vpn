// ICD360SVPN — lib/src/features/enrollment/enrollment_screen.dart
//
// First-run screen (M7.2): the user types the 16-char one-time code
// printed by `vpn-agent issue-code <name>` into four 4-character
// boxes, hits Connect, and the app POSTs the code to
// https://vpn.icd360s.de/enroll to receive the cert + WireGuard
// peer config in one shot.
//
// UX details:
//   - Each box accepts up to 4 characters from the unambiguous
//     32-symbol alphabet (no 0/O/1/I/L). Lowercase is auto-uppered.
//   - Auto-advance to the next box on the 4th character.
//   - Backspace at position 0 of an empty box jumps back to the
//     previous box.
//   - Paste support: pasting a full 16-char code (with or without
//     dashes) into ANY box fills all four.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../common/app_footer.dart';

const String _kAlphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

class EnrollmentScreen extends ConsumerStatefulWidget {
  const EnrollmentScreen({super.key});

  @override
  ConsumerState<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends ConsumerState<EnrollmentScreen> {
  static const int _boxCount = 4;
  static const int _charsPerBox = 4;

  late final List<TextEditingController> _controllers = List.generate(
    _boxCount,
    (_) => TextEditingController(),
  );
  late final List<FocusNode> _focusNodes = List.generate(
    _boxCount,
    (_) => FocusNode(),
  );

  bool _connecting = false;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  /// The current code as a single 16-char string (after stripping
  /// non-alphabet characters and uppercasing).
  String get _code {
    final raw = _controllers.map((c) => c.text).join();
    return _normalize(raw);
  }

  bool get _isComplete => _code.length == _boxCount * _charsPerBox;

  static String _normalize(String s) {
    final upper = s.toUpperCase();
    final buf = StringBuffer();
    for (final r in upper.runes) {
      final c = String.fromCharCode(r);
      if (_kAlphabet.contains(c)) {
        buf.write(c);
      }
    }
    return buf.toString();
  }

  /// Distribute a normalized 16-char code across all four boxes.
  void _spreadAcrossBoxes(String code16) {
    for (var i = 0; i < _boxCount; i++) {
      final start = i * _charsPerBox;
      final end = start + _charsPerBox;
      _controllers[i].value = TextEditingValue(
        text: code16.substring(start, end),
        selection: TextSelection.collapsed(offset: _charsPerBox),
      );
    }
    _focusNodes.last.requestFocus();
  }

  void _onChanged(int index, String value) {
    final normalized = _normalize(value);

    // Paste path: someone dropped 16+ chars into one box.
    if (normalized.length >= _boxCount * _charsPerBox) {
      _spreadAcrossBoxes(normalized.substring(0, _boxCount * _charsPerBox));
      setState(() {});
      return;
    }

    // Trim back to 4 chars and force-upper the visible text.
    final clipped = normalized.length > _charsPerBox
        ? normalized.substring(0, _charsPerBox)
        : normalized;
    if (clipped != value) {
      _controllers[index].value = TextEditingValue(
        text: clipped,
        selection: TextSelection.collapsed(offset: clipped.length),
      );
    }

    // Auto-advance once the box is full.
    if (clipped.length == _charsPerBox && index < _boxCount - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    setState(() {});
  }

  KeyEventResult _handleKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Backspace at empty position 0 → jump to previous box.
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].selection = TextSelection.collapsed(
        offset: _controllers[index - 1].text.length,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _submit() async {
    if (!_isComplete || _connecting) return;
    setState(() => _connecting = true);
    try {
      await ref.read(appPhaseProvider.notifier).enrollFromCode(_code);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(appPhaseProvider);
    final lastError = phase is NeedsEnrollment ? phase.lastError : null;
    final theme = Theme.of(context);

    return Scaffold(
      body: Column(
        children: <Widget>[
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'Conectează acest dispozitiv',
                        style: theme.textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pe server, administratorul rulează:',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'sudo vpn-agent issue-code numele-tau',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tastează codul de 16 caractere primit:',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(_boxCount, (i) {
                          return Flexible(
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: i == 0 ? 0 : 4,
                                right: i == _boxCount - 1 ? 0 : 4,
                              ),
                              child: Focus(
                                onKeyEvent: (_, e) => _handleKey(i, e),
                                child: TextField(
                                  controller: _controllers[i],
                                  focusNode: _focusNodes[i],
                                  enabled: !_connecting,
                                  textAlign: TextAlign.center,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  maxLength: _charsPerBox,
                                  autofocus: i == 0,
                                  decoration: const InputDecoration(
                                    counterText: '',
                                    border: OutlineInputBorder(),
                                    contentPadding:
                                        EdgeInsets.symmetric(vertical: 16),
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 4,
                                  ),
                                  onChanged: (v) => _onChanged(i, v),
                                  onSubmitted: (_) => _submit(),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Codul folosește doar literele și cifrele '
                        '$_kAlphabet (fără 0/O/1/I/L).',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (lastError != null) ...<Widget>[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            lastError,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        icon: _connecting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.lock_open),
                        label: Text(
                          _connecting
                              ? 'Se conectează…'
                              : 'Conectare la VPN',
                        ),
                        style: FilledButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed:
                            (!_isComplete || _connecting) ? null : _submit,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const AppFooter(),
        ],
      ),
    );
  }
}
