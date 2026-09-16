import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'calc_engine.dart';
import 'vault_state.dart';

/// The disguise: a fully working calculator and the ONLY thing visible on a
/// cold start. Typing the secret vault code and pressing `=` silently swaps
/// to the real app (see VaultShield). A wrong code just computes a number —
/// the failure is indistinguishable from normal calculator use.
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _expr = '';
  String _history = '';
  bool _freshResult = false; // next digit starts a new entry

  static const _keys = [
    ['C', '⌫', '%', '÷'],
    ['7', '8', '9', '×'],
    ['4', '5', '6', '−'],
    ['1', '2', '3', '+'],
  ];

  bool _isOp(String k) => k == '÷' || k == '×' || k == '−' || k == '+' || k == '%';

  void _press(String k) {
    setState(() {
      if (k == 'C') {
        _expr = '';
        _history = '';
        _freshResult = false;
        return;
      }
      if (_freshResult && !_isOp(k) && k != '=') {
        _expr = '';
        _history = '';
        _freshResult = false;
      }
      switch (k) {
        case '⌫':
          if (_expr.isNotEmpty) {
            _expr = _expr.substring(0, _expr.length - 1);
          }
          _freshResult = false;
        case '=':
          _equals();
        default:
          if (_expr.length < 24) _expr += k;
      }
    });
  }

  void _equals() {
    // Vault check FIRST: exact code + '=' unlocks, silently.
    if (context.read<VaultState>().tryUnlock(_expr)) {
      _expr = '';
      _history = '';
      _freshResult = false;
      return;
    }
    if (_expr.isEmpty) return;
    try {
      final result = CalcEngine.evaluate(_expr);
      _history = '$_expr=';
      _expr = result;
      _freshResult = true;
    } on CalcError catch (e) {
      _history = '';
      _expr = e.message;
      _freshResult = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                alignment: Alignment.bottomRight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _history,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _expr.isEmpty ? '0' : _expr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (final row in _keys) _buildRow(row, scheme),
            _buildRow(const ['0', '.', '='], scheme, equalsFlex: 2),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(List<String> row, ColorScheme scheme, {int equalsFlex = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          for (final k in row)
            Expanded(
              flex: k == '=' ? equalsFlex : 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: _CalcKey(
                  label: k,
                  fill: k == '=' ? scheme.primary : scheme.surfaceContainerHighest,
                  fg: k == '='
                      ? scheme.onPrimary
                      : _isOp(k) || k == 'C'
                          ? scheme.primary
                          : scheme.onSurface,
                  onTap: () => _press(k),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CalcKey extends StatelessWidget {
  const _CalcKey({
    required this.label,
    required this.fill,
    required this.fg,
    required this.onTap,
  });

  final String label;
  final Color fill;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: SizedBox(
          height: 68,
          child: Center(
            child: Text(
              label,
              style: TextStyle(fontSize: 26, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}
