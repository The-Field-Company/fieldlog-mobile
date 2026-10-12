/// Pure-Dart expression evaluator for SurveyJS visibleIf / enableIf / requiredIf.
///
/// Supported syntax (case-insensitive operators):
///   {field} = 'value'      {field} <> 'value'
///   {field} > 5             {field} >= 5       < <=
///   {field} contains 'text'
///   {field} anyof ['a','b']
///   {field} empty           {field} notempty
///   expr and expr           expr or expr       (expr)
///
/// Design: **fail-open** — unparseable expressions evaluate to `true`.
class ExpressionEngine {
  const ExpressionEngine._();

  /// Evaluate [expression] against [data]. Returns `true` when the expression
  /// is null, empty, or cannot be parsed (fail-open).
  static bool evaluate(String? expression, Map<String, dynamic> data) {
    if (expression == null || expression.trim().isEmpty) return true;
    try {
      final tokens = _tokenize(expression);
      final parser = _Parser(tokens, data);
      return parser.parseExpression();
    } catch (_) {
      return true; // fail-open
    }
  }

  // ── Tokenizer ──────────────────────────────────────────────────────────

  static List<_Token> _tokenize(String input) {
    final tokens = <_Token>[];
    int i = 0;

    while (i < input.length) {
      final ch = input[i];

      // Whitespace
      if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
        i++;
        continue;
      }

      // Field reference: {fieldName}
      if (ch == '{') {
        final end = input.indexOf('}', i + 1);
        if (end == -1) throw FormatException('Unterminated {');
        tokens.add(_Token(_TType.field, input.substring(i + 1, end)));
        i = end + 1;
        continue;
      }

      // String literal: 'value' or "value"
      if (ch == "'" || ch == '"') {
        final quote = ch;
        final buf = StringBuffer();
        i++;
        while (i < input.length && input[i] != quote) {
          buf.write(input[i]);
          i++;
        }
        if (i >= input.length) throw FormatException('Unterminated string');
        i++; // skip closing quote
        tokens.add(_Token(_TType.string, buf.toString()));
        continue;
      }

      // Array literal: ['a', 'b']
      if (ch == '[') {
        final end = input.indexOf(']', i + 1);
        if (end == -1) throw FormatException('Unterminated [');
        final inner = input.substring(i + 1, end);
        final items = <String>[];
        final regex = RegExp(r"""'([^']*)'|"([^"]*)"|([^\s,]+)""");
        for (final m in regex.allMatches(inner)) {
          items.add(m.group(1) ?? m.group(2) ?? m.group(3) ?? '');
        }
        tokens.add(_Token(_TType.array, items));
        i = end + 1;
        continue;
      }

      // Number
      if (_isDigit(ch) || (ch == '-' && i + 1 < input.length && _isDigit(input[i + 1]))) {
        final start = i;
        if (ch == '-') i++;
        while (i < input.length && (_isDigit(input[i]) || input[i] == '.')) {
          i++;
        }
        tokens.add(_Token(_TType.number, num.parse(input.substring(start, i))));
        continue;
      }

      // Operators: <> >= <= = > < != !
      if (ch == '<' || ch == '>' || ch == '=' || ch == '!') {
        if (i + 1 < input.length) {
          final two = input.substring(i, i + 2);
          if (two == '<>' || two == '>=' || two == '<=' || two == '!=') {
            tokens.add(_Token(_TType.op, two));
            i += 2;
            continue;
          }
        }
        tokens.add(_Token(_TType.op, ch));
        i++;
        continue;
      }

      // Parentheses
      if (ch == '(') {
        tokens.add(_Token(_TType.lparen, '('));
        i++;
        continue;
      }
      if (ch == ')') {
        tokens.add(_Token(_TType.rparen, ')'));
        i++;
        continue;
      }

      // Word (keyword / boolean literal / bare value)
      if (_isAlpha(ch) || ch == '_') {
        final start = i;
        while (i < input.length && (_isAlpha(input[i]) || _isDigit(input[i]) || input[i] == '_')) {
          i++;
        }
        final word = input.substring(start, i).toLowerCase();
        switch (word) {
          case 'and':
            tokens.add(_Token(_TType.and, word));
          case 'or':
            tokens.add(_Token(_TType.or, word));
          case 'contains':
          case 'notcontains':
          case 'anyof':
          case 'allof':
          case 'empty':
          case 'notempty':
          case 'equal':
          case 'notequal':
          case 'greater':
          case 'less':
          case 'greaterorequal':
          case 'lessorequal':
            tokens.add(_Token(_TType.op, word));
          case 'true':
            tokens.add(_Token(_TType.boolean, true));
          case 'false':
            tokens.add(_Token(_TType.boolean, false));
          default:
            // Bare word value (e.g. unquoted choice value)
            tokens.add(_Token(_TType.string, input.substring(start, i)));
        }
        continue;
      }

      // Skip unknown characters
      i++;
    }

    return tokens;
  }

  static bool _isDigit(String ch) => ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;
  static bool _isAlpha(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
  }
}

// ── Token types ────────────────────────────────────────────────────────

enum _TType { field, string, number, boolean, array, op, and, or, lparen, rparen }

class _Token {
  final _TType type;
  final dynamic value;
  const _Token(this.type, this.value);
  @override
  String toString() => '_Token($type, $value)';
}

// ── Recursive descent parser + evaluator ───────────────────────────────

class _Parser {
  final List<_Token> tokens;
  final Map<String, dynamic> data;
  int pos = 0;

  _Parser(this.tokens, this.data);

  _Token? get _current => pos < tokens.length ? tokens[pos] : null;

  _Token _advance() => tokens[pos++];

  bool _match(_TType type) {
    if (_current?.type == type) {
      pos++;
      return true;
    }
    return false;
  }

  /// expression = orExpr
  bool parseExpression() {
    final result = _orExpr();
    return result;
  }

  /// orExpr = andExpr ( 'or' andExpr )*
  bool _orExpr() {
    var result = _andExpr();
    while (_current?.type == _TType.or) {
      _advance();
      final right = _andExpr();
      result = result || right;
    }
    return result;
  }

  /// andExpr = primary ( 'and' primary )*
  bool _andExpr() {
    var result = _primary();
    while (_current?.type == _TType.and) {
      _advance();
      final right = _primary();
      result = result && right;
    }
    return result;
  }

  /// primary = '(' orExpr ')' | comparison
  bool _primary() {
    if (_match(_TType.lparen)) {
      final result = _orExpr();
      _match(_TType.rparen);
      return result;
    }
    return _comparison();
  }

  /// comparison = field op value | field unaryOp
  bool _comparison() {
    if (_current?.type != _TType.field) {
      throw FormatException('Expected field reference');
    }
    final fieldName = _advance().value as String;
    final fieldValue = data[fieldName];

    if (_current == null) {
      // bare field — truthy check (matches JavaScript semantics)
      return fieldValue != null && fieldValue != '' && fieldValue != false && fieldValue != 0;
    }

    if (_current?.type != _TType.op) {
      // bare field — truthy check (matches JavaScript semantics)
      return fieldValue != null && fieldValue != '' && fieldValue != false && fieldValue != 0;
    }

    final op = _advance().value as String;

    // Unary operators
    if (op == 'empty') {
      return fieldValue == null ||
          fieldValue == '' ||
          (fieldValue is List && fieldValue.isEmpty);
    }
    if (op == 'notempty') {
      return fieldValue != null &&
          fieldValue != '' &&
          !(fieldValue is List && fieldValue.isEmpty);
    }

    // Binary operators — get right-hand side
    final rhs = _value();

    switch (op) {
      case '=':
      case 'equal':
        return _equals(fieldValue, rhs);
      case '<>':
      case '!=':
      case 'notequal':
        return !_equals(fieldValue, rhs);
      case '>':
      case 'greater':
        return _compareNum(fieldValue, rhs) > 0;
      case '<':
      case 'less':
        return _compareNum(fieldValue, rhs) < 0;
      case '>=':
      case 'greaterorequal':
        return _compareNum(fieldValue, rhs) >= 0;
      case '<=':
      case 'lessorequal':
        return _compareNum(fieldValue, rhs) <= 0;
      case 'contains':
        return _contains(fieldValue, rhs);
      case 'notcontains':
        return !_contains(fieldValue, rhs);
      case 'anyof':
        return _anyOf(fieldValue, rhs);
      case 'allof':
        return _allOf(fieldValue, rhs);
      default:
        return true; // fail-open on unknown operator
    }
  }

  /// Parse a value token (string, number, boolean, array, field ref).
  dynamic _value() {
    final t = _current;
    if (t == null) return null;
    switch (t.type) {
      case _TType.string:
      case _TType.number:
      case _TType.boolean:
      case _TType.array:
        _advance();
        return t.value;
      case _TType.field:
        _advance();
        return data[t.value as String];
      default:
        return null;
    }
  }

  // ── Comparison helpers ───────────────────────────────────────────────

  static bool _equals(dynamic a, dynamic b) {
    if (a == b) return true;
    if (a == null || b == null) return false;
    // Type coercion: compare as numbers if both parseable
    final na = _tryNum(a);
    final nb = _tryNum(b);
    if (na != null && nb != null) return na == nb;
    return a.toString() == b.toString();
  }

  static int _compareNum(dynamic a, dynamic b) {
    final na = _tryNum(a) ?? 0;
    final nb = _tryNum(b) ?? 0;
    return na.compareTo(nb);
  }

  static bool _contains(dynamic fieldValue, dynamic search) {
    if (fieldValue is List) {
      return fieldValue.any((e) => e.toString() == search.toString());
    }
    return fieldValue.toString().contains(search.toString());
  }

  static bool _anyOf(dynamic fieldValue, dynamic rhs) {
    final values = rhs is List ? rhs.map((e) => e.toString()).toSet() : <String>{};
    if (fieldValue is List) {
      return fieldValue.any((e) => values.contains(e.toString()));
    }
    return values.contains(fieldValue?.toString());
  }

  static bool _allOf(dynamic fieldValue, dynamic rhs) {
    final values = rhs is List ? rhs.map((e) => e.toString()).toSet() : <String>{};
    if (fieldValue is List) {
      return values.every((v) => fieldValue.any((e) => e.toString() == v));
    }
    return values.contains(fieldValue?.toString());
  }

  static num? _tryNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }
}
