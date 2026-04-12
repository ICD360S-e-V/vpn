// ICD360SVPN — lib/src/common/log_console.dart
//
// Collapsible debug console panel shown above the app footer.
// Displays timestamped, color-coded log entries from AppLogger.
// Inspired by ProtonVPN/Mullvad's exportable log feature, but
// shown inline for instant debugging.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/app_logger.dart';

class LogConsole extends StatefulWidget {
  const LogConsole({super.key});

  @override
  State<LogConsole> createState() => _LogConsoleState();
}

class _LogConsoleState extends State<LogConsole> {
  bool _expanded = false;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    appLogger.entries.addListener(_onNewEntry);
  }

  @override
  void dispose() {
    appLogger.entries.removeListener(_onNewEntry);
    _scroll.dispose();
    super.dispose();
  }

  void _onNewEntry() {
    if (!mounted) return;
    setState(() {});
    // Auto-scroll to bottom when expanded.
    if (_expanded && _scroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _copyAll() {
    final text = appLogger.export();
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 2),
        content: Text('Loguri copiate în clipboard.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = appLogger.entries.value;
    final count = entries.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Toggle bar
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              border: Border(
                top: BorderSide(
                    color: theme.colorScheme.outlineVariant, width: 1),
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_up,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Consolă',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (count > 0) ...<Widget>[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$count',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (_expanded) ...<Widget>[
                  IconButton(
                    tooltip: 'Copiază tot',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints:
                        const BoxConstraints(minWidth: 24, minHeight: 24),
                    icon: const Icon(Icons.copy),
                    onPressed: count > 0 ? _copyAll : null,
                  ),
                  IconButton(
                    tooltip: 'Șterge',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints:
                        const BoxConstraints(minWidth: 24, minHeight: 24),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: count > 0
                        ? () {
                            appLogger.clear();
                            setState(() {});
                          }
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),

        // Log entries
        if (_expanded)
          Container(
            height: 180,
            width: double.infinity,
            color: theme.brightness == Brightness.dark
                ? Colors.black
                : const Color(0xFFF5F5F5),
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      'Nicio intrare în log.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    itemCount: entries.length,
                    itemExtent: 20,
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      return _LogLine(entry: e);
                    },
                  ),
          ),
      ],
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});
  final LogEntry entry;

  Color _tagColor(LogLevel level) {
    return switch (level) {
      LogLevel.info => Colors.grey,
      LogLevel.warning => Colors.orange,
      LogLevel.error => Colors.red,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = entry.timestamp.toLocal();
    final time =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    return Row(
      children: <Widget>[
        Text(
          time,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: _tagColor(entry.level).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            entry.tag,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _tagColor(entry.level),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            entry.message,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: entry.level == LogLevel.error
                  ? Colors.red
                  : (Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade300
                      : Colors.grey.shade800),
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}
