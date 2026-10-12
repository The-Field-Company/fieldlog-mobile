import 'package:flutter_test/flutter_test.dart';
import 'package:fieldlog_mobile/utils/expression_engine.dart';

void main() {
  group('ExpressionEngine', () {
    group('null / empty → true (fail-open)', () {
      test('null expression', () {
        expect(ExpressionEngine.evaluate(null, {}), isTrue);
      });
      test('empty string', () {
        expect(ExpressionEngine.evaluate('', {}), isTrue);
      });
      test('whitespace only', () {
        expect(ExpressionEngine.evaluate('   ', {}), isTrue);
      });
    });

    group('equality', () {
      test('string equal', () {
        expect(
          ExpressionEngine.evaluate("{q1} = 'yes'", {'q1': 'yes'}),
          isTrue,
        );
      });
      test('string not equal', () {
        expect(
          ExpressionEngine.evaluate("{q1} = 'yes'", {'q1': 'no'}),
          isFalse,
        );
      });
      test('<> operator', () {
        expect(
          ExpressionEngine.evaluate("{q1} <> 'yes'", {'q1': 'no'}),
          isTrue,
        );
      });
      test('!= operator', () {
        expect(
          ExpressionEngine.evaluate("{q1} != 'yes'", {'q1': 'no'}),
          isTrue,
        );
      });
      test('numeric equality with coercion', () {
        expect(
          ExpressionEngine.evaluate("{age} = 25", {'age': '25'}),
          isTrue,
        );
      });
    });

    group('comparisons', () {
      test('greater than', () {
        expect(
          ExpressionEngine.evaluate("{age} > 18", {'age': 25}),
          isTrue,
        );
      });
      test('less than', () {
        expect(
          ExpressionEngine.evaluate("{age} < 18", {'age': 10}),
          isTrue,
        );
      });
      test('greater or equal', () {
        expect(
          ExpressionEngine.evaluate("{age} >= 18", {'age': 18}),
          isTrue,
        );
      });
      test('less or equal', () {
        expect(
          ExpressionEngine.evaluate("{age} <= 18", {'age': 18}),
          isTrue,
        );
      });
      test('greater than false', () {
        expect(
          ExpressionEngine.evaluate("{age} > 18", {'age': 10}),
          isFalse,
        );
      });
    });

    group('contains', () {
      test('string contains', () {
        expect(
          ExpressionEngine.evaluate("{name} contains 'ohn'", {'name': 'John'}),
          isTrue,
        );
      });
      test('string not contains', () {
        expect(
          ExpressionEngine.evaluate("{name} contains 'xyz'", {'name': 'John'}),
          isFalse,
        );
      });
      test('list contains', () {
        expect(
          ExpressionEngine.evaluate(
            "{colors} contains 'red'",
            {
              'colors': ['red', 'blue'],
            },
          ),
          isTrue,
        );
      });
    });

    group('anyof', () {
      test('single value in array', () {
        expect(
          ExpressionEngine.evaluate(
            "{q1} anyof ['a', 'b', 'c']",
            {'q1': 'b'},
          ),
          isTrue,
        );
      });
      test('single value not in array', () {
        expect(
          ExpressionEngine.evaluate(
            "{q1} anyof ['a', 'b', 'c']",
            {'q1': 'd'},
          ),
          isFalse,
        );
      });
      test('list value with overlap', () {
        expect(
          ExpressionEngine.evaluate(
            "{q1} anyof ['a', 'b']",
            {
              'q1': ['b', 'x'],
            },
          ),
          isTrue,
        );
      });
    });

    group('empty / notempty', () {
      test('null is empty', () {
        expect(
          ExpressionEngine.evaluate("{q1} empty", {}),
          isTrue,
        );
      });
      test('empty string is empty', () {
        expect(
          ExpressionEngine.evaluate("{q1} empty", {'q1': ''}),
          isTrue,
        );
      });
      test('non-empty string is notempty', () {
        expect(
          ExpressionEngine.evaluate("{q1} notempty", {'q1': 'hello'}),
          isTrue,
        );
      });
      test('empty list is empty', () {
        expect(
          ExpressionEngine.evaluate("{q1} empty", {'q1': []}),
          isTrue,
        );
      });
      test('value present is not empty', () {
        expect(
          ExpressionEngine.evaluate("{q1} empty", {'q1': 'val'}),
          isFalse,
        );
      });
    });

    group('logical combinators', () {
      test('and - both true', () {
        expect(
          ExpressionEngine.evaluate(
            "{a} = 'x' and {b} = 'y'",
            {'a': 'x', 'b': 'y'},
          ),
          isTrue,
        );
      });
      test('and - one false', () {
        expect(
          ExpressionEngine.evaluate(
            "{a} = 'x' and {b} = 'y'",
            {'a': 'x', 'b': 'z'},
          ),
          isFalse,
        );
      });
      test('or - one true', () {
        expect(
          ExpressionEngine.evaluate(
            "{a} = 'x' or {b} = 'y'",
            {'a': 'x', 'b': 'z'},
          ),
          isTrue,
        );
      });
      test('or - both false', () {
        expect(
          ExpressionEngine.evaluate(
            "{a} = 'x' or {b} = 'y'",
            {'a': 'z', 'b': 'z'},
          ),
          isFalse,
        );
      });
    });

    group('parenthesized grouping', () {
      test('changes precedence', () {
        // Without parens: a=x AND (b=y OR c=z) would need explicit parens
        expect(
          ExpressionEngine.evaluate(
            "({a} = 'x' or {b} = 'y') and {c} = 'z'",
            {'a': 'wrong', 'b': 'y', 'c': 'z'},
          ),
          isTrue,
        );
      });
      test('nested parentheses', () {
        expect(
          ExpressionEngine.evaluate(
            "(({a} = 'x'))",
            {'a': 'x'},
          ),
          isTrue,
        );
      });
    });

    group('fail-open on bad input', () {
      test('malformed expression returns true', () {
        expect(
          ExpressionEngine.evaluate("??? broken {{", {'q1': 'x'}),
          isTrue,
        );
      });
      test('unknown operator returns true', () {
        expect(
          ExpressionEngine.evaluate("{q1} unknownop 'x'", {'q1': 'x'}),
          isTrue,
        );
      });
    });

    group('word operators', () {
      test('equal keyword', () {
        expect(
          ExpressionEngine.evaluate("{q1} equal 'yes'", {'q1': 'yes'}),
          isTrue,
        );
      });
      test('notequal keyword', () {
        expect(
          ExpressionEngine.evaluate("{q1} notequal 'yes'", {'q1': 'no'}),
          isTrue,
        );
      });
      test('greater keyword', () {
        expect(
          ExpressionEngine.evaluate("{q1} greater 5", {'q1': 10}),
          isTrue,
        );
      });
    });

    group('boolean literals', () {
      test('equals true', () {
        expect(
          ExpressionEngine.evaluate("{q1} = true", {'q1': true}),
          isTrue,
        );
      });
      test('equals false', () {
        expect(
          ExpressionEngine.evaluate("{q1} = false", {'q1': false}),
          isTrue,
        );
      });
    });

    group('double-quoted strings', () {
      test('double quotes work', () {
        expect(
          ExpressionEngine.evaluate('{q1} = "hello"', {'q1': 'hello'}),
          isTrue,
        );
      });
    });

    group('notcontains', () {
      test('string does not contain substring', () {
        expect(
          ExpressionEngine.evaluate(
            "{name} notcontains 'xyz'",
            {'name': 'John'},
          ),
          isTrue,
        );
      });
      test('string does contain substring → false', () {
        expect(
          ExpressionEngine.evaluate(
            "{name} notcontains 'ohn'",
            {'name': 'John'},
          ),
          isFalse,
        );
      });
      test('list does not contain item', () {
        expect(
          ExpressionEngine.evaluate(
            "{colors} notcontains 'purple'",
            {
              'colors': ['red', 'blue'],
            },
          ),
          isTrue,
        );
      });
    });

    group('allof', () {
      test('list field contains all required values', () {
        expect(
          ExpressionEngine.evaluate(
            "{q1} allof ['a', 'b']",
            {
              'q1': ['a', 'b', 'c'],
            },
          ),
          isTrue,
        );
      });
      test('list field missing one required value → false', () {
        expect(
          ExpressionEngine.evaluate(
            "{q1} allof ['a', 'b']",
            {
              'q1': ['a', 'c'],
            },
          ),
          isFalse,
        );
      });
      test('single value against allof — behaves like anyof (known quirk)', () {
        // When the field is a single string (not a list), the allof code path
        // falls through to values.contains(fieldValue), which is the same as
        // anyof. So {q1} allof ['a','b'] where q1='a' returns TRUE because
        // 'a' is in the set {'a','b'}. This doesn't match the semantic
        // expectation of "field contains ALL of these", but it's the current
        // behavior. Worth knowing if you ever rely on allof with scalar fields.
        expect(
          ExpressionEngine.evaluate(
            "{q1} allof ['a', 'b']",
            {'q1': 'a'},
          ),
          isTrue,
        );
      });
      test('single value satisfies single-element allof', () {
        expect(
          ExpressionEngine.evaluate(
            "{q1} allof ['a']",
            {'q1': 'a'},
          ),
          isTrue,
        );
      });
    });

    group('and/or precedence', () {
      // The parser evaluates: orExpr → andExpr, so 'and' binds tighter.
      // "A and B or C" is parsed as "(A and B) or C", not "A and (B or C)".
      test('and binds tighter than or', () {
        // false AND true → false; false OR true → true
        expect(
          ExpressionEngine.evaluate(
            "{a} = 'x' and {b} = 'y' or {c} = 'z'",
            {'a': 'wrong', 'b': 'y', 'c': 'z'},
          ),
          isTrue, // (false and true) or true → true
        );
      });
      test('and binds tighter than or — second case', () {
        // If or bound tighter: a=x and (b=wrong or c=z) → true and true → true
        // With correct precedence: (a=x and b=wrong) or c=wrong → false or false → false
        expect(
          ExpressionEngine.evaluate(
            "{a} = 'x' and {b} = 'y' or {c} = 'z'",
            {'a': 'x', 'b': 'wrong', 'c': 'wrong'},
          ),
          isFalse, // (true and false) or false → false
        );
      });
    });

    group('bare field reference truthiness', () {
      // Bare {field} with no operator does a truthy check.
      // This differs from JavaScript: 0 and [] are truthy here.
      test('non-empty string is truthy', () {
        expect(
          ExpressionEngine.evaluate('{q1}', {'q1': 'hello'}),
          isTrue,
        );
      });
      test('empty string is falsy', () {
        expect(
          ExpressionEngine.evaluate('{q1}', {'q1': ''}),
          isFalse,
        );
      });
      test('null (missing field) is falsy', () {
        expect(
          ExpressionEngine.evaluate('{q1}', {}),
          isFalse,
        );
      });
      test('false boolean is falsy', () {
        expect(
          ExpressionEngine.evaluate('{q1}', {'q1': false}),
          isFalse,
        );
      });
      test('zero is falsy — matches JavaScript semantics', () {
        // 0 is falsy in JavaScript, and SurveyJS runs in JS on the web.
        // The mobile engine must match so {count} visibility expressions
        // behave identically on both platforms.
        expect(
          ExpressionEngine.evaluate('{q1}', {'q1': 0}),
          isFalse,
        );
      });
      test('zero as double is also falsy', () {
        // Dart's 0.0 != 0 evaluates to false (nums compared cross-type),
        // so the single != 0 check covers both int and double zero.
        expect(
          ExpressionEngine.evaluate('{q1}', {'q1': 0.0}),
          isFalse,
        );
      });
      test('empty list is truthy — unlike JavaScript', () {
        // Same: [] != null, [] != '', [] != false → truthy.
        expect(
          ExpressionEngine.evaluate('{q1}', {'q1': []}),
          isTrue,
        );
      });
    });

    group('field-to-field comparison', () {
      test('two fields with equal values', () {
        expect(
          ExpressionEngine.evaluate(
            '{a} = {b}',
            {'a': 'same', 'b': 'same'},
          ),
          isTrue,
        );
      });
      test('two fields with different values', () {
        expect(
          ExpressionEngine.evaluate(
            '{a} = {b}',
            {'a': 'one', 'b': 'two'},
          ),
          isFalse,
        );
      });
      test('numeric field-to-field comparison', () {
        expect(
          ExpressionEngine.evaluate(
            '{score} > {threshold}',
            {'score': 85, 'threshold': 70},
          ),
          isTrue,
        );
      });
    });
  });
}
