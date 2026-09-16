/// Tiny expression engine for the disguise calculator (pure Dart, no Flutter).
///
/// Supports `+ - × ÷` (and ASCII `+ - * /`), decimals, unary minus, and a
/// postfix `%` (percent = ÷100). No parentheses — like a pocket calculator.
/// Throws [CalcError] with a display-safe message on any bad input.
class CalcError implements Exception {
  CalcError(this.message);
  final String message;
  @override
  String toString() => message;
}

class CalcEngine {
  static String evaluate(String raw) {
    final expr = raw
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll('−', '-')
        .replaceAll(' ', '');
    if (expr.isEmpty) throw CalcError('Empty');
    final tokens = _tokenize(expr);
    final value = _evalRpn(_toRpn(tokens));
    if (value.isNaN || value.isInfinite) {
      throw CalcError("Can't divide by 0");
    }
    return _format(value);
  }

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  /// Tokens: number literals (with trailing % already folded to /100),
  /// binary `+ - * /`, and unary `neg`.
  static List<String> _tokenize(String expr) {
    final out = <String>[];
    var i = 0;
    bool lastWasValue() =>
        out.isNotEmpty && out.last != 'neg' && !'+-*/'.contains(out.last);
    while (i < expr.length) {
      final c = expr[i];
      if (_isDigit(c) || c == '.') {
        var j = i;
        var dots = 0;
        while (j < expr.length && (_isDigit(expr[j]) || expr[j] == '.')) {
          if (expr[j] == '.') dots++;
          if (dots > 1) throw CalcError('Invalid number');
          j++;
        }
        final numText = expr.substring(i, j);
        if (numText == '.') throw CalcError('Invalid number');
        var value = double.parse(numText == '.' ? '0' : numText);
        i = j;
        if (i < expr.length && expr[i] == '%') {
          value /= 100;
          i++;
        }
        out.add(value.toString());
        continue;
      }
      if (c == '%') {
        // A % must follow a number (folded above); anywhere else is invalid.
        throw CalcError('Invalid %');
      }
      if ('+-*/'.contains(c)) {
        if (!lastWasValue()) {
          if (c == '-') {
            out.add('neg'); // unary minus
          } else if (c == '+') {
            // unary plus: no-op, skip
          } else {
            throw CalcError('Invalid input');
          }
        } else {
          out.add(c);
        }
        i++;
        continue;
      }
      throw CalcError('Invalid input');
    }
    if (out.isEmpty || '+-*/'.contains(out.last)) {
      throw CalcError('Incomplete');
    }
    return out;
  }

  static int _prec(String op) {
    if (op == 'neg') return 3;
    if (op == '*' || op == '/') return 2;
    return 1;
  }

  static List<String> _toRpn(List<String> tokens) {
    final out = <String>[];
    final ops = <String>[];
    for (final t in tokens) {
      if (t == 'neg') {
        ops.add(t);
      } else if ('+-*/'.contains(t)) {
        while (ops.isNotEmpty && _prec(ops.last) >= _prec(t)) {
          out.add(ops.removeLast());
        }
        ops.add(t);
      } else {
        out.add(t);
      }
    }
    while (ops.isNotEmpty) {
      out.add(ops.removeLast());
    }
    return out;
  }

  static double _evalRpn(List<String> rpn) {
    final stack = <double>[];
    for (final t in rpn) {
      if (t == 'neg') {
        if (stack.isEmpty) throw CalcError('Invalid input');
        stack.add(-stack.removeLast());
      } else if ('+-*/'.contains(t)) {
        if (stack.length < 2) throw CalcError('Invalid input');
        final b = stack.removeLast();
        final a = stack.removeLast();
        switch (t) {
          case '+':
            stack.add(a + b);
          case '-':
            stack.add(a - b);
          case '*':
            stack.add(a * b);
          case '/':
            if (b == 0) throw CalcError("Can't divide by 0");
            stack.add(a / b);
        }
      } else {
        stack.add(double.parse(t));
      }
    }
    if (stack.length != 1) throw CalcError('Invalid input');
    return stack.single;
  }

  static String _format(double v) {
    if (v == v.truncateToDouble() && v.abs() < 1e12) {
      return v.truncate().toString();
    }
    if (v.abs() >= 1e12 || (v.abs() < 1e-8 && v != 0)) {
      return v.toStringAsExponential(5).replaceAll('e+', 'E').replaceAll('e', 'E');
    }
    var s = v.toStringAsPrecision(10);
    if (s.contains('e') || s.contains('E')) {
      s = v.toStringAsFixed(8);
    }
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }
}
