import 'package:flutter_test/flutter_test.dart';
import 'package:study_bd/core/utils/formatters.dart';
import 'package:study_bd/core/utils/validators.dart';
import 'package:study_bd/data/models/models.dart';
import 'package:study_bd/features/admin/admin_screens.dart';
import 'package:study_bd/features/english/english_screens.dart';
import 'package:study_bd/features/tools/tools_screens.dart';

void main() {
  test('calculator parses precedence and parentheses', () {
    expect(evalExpr('2+3×4'), 14);
    expect(evalExpr('(2+3)×4'), 20);
    expect(evalExpr('10÷4'), 2.5);
    expect(evalExpr('5÷0'), isNull);
    expect(evalExpr('2+'), isNull);
  });

  test('SSC/HSC GPA with 4th subject bonus and fail rule', () {
    expect(sscHscGpa([5, 5, 5, 5], null), 5.0);
    expect(sscHscGpa([4, 4, 4, 4], 5.0), closeTo(4.75, 0.001)); // (16 + 3) / 4
    expect(sscHscGpa([5, 5, 0, 5], 5.0), 0);
    expect(sscHscGpa([5, 5], 5.0), 5.0); // capped at 5
  });

  test('IELTS overall band rounding', () {
    expect(overallBand(6.25), 6.5);
    expect(overallBand(6.75), 7.0);
    expect(overallBand(6.125), 6.0);
    expect(listeningBand(30), 7.0);
    expect(readingBand(23), 6.0);
  });

  test('bulk MCQ parser skips malformed lines', () {
    final qs = parseMcqBulk('2+2?|1|2|3|4|D|basic\nbad line\nQ|a|b|c|d|Z');
    expect(qs.length, 1);
    expect(qs.first.answerIndex, 3);
  });

  test('search keywords are prefix tokens', () {
    final k = ContentItem.keywords('Physics Notes', '');
    expect(k, containsAll(['ph', 'phy', 'physics', 'no', 'notes']));
  });

  test('formatters', () {
    expect(Formatters.mmss(125), '02:05');
    expect(Formatters.fileSize(5242880), '5.0 MB');
    expect(Formatters.bnDigits('2026'), '২০২৬');
    expect(Formatters.score(6.5), '6.50');
  });

  test('validators', () {
    expect(Validators.email('a@b.com'), isNull);
    expect(Validators.email('nope'), isNotNull);
    expect(Validators.bdPhone('01712345678'), isNull);
    expect(Validators.bdPhone('+8801712345678'), isNull);
    expect(Validators.bdPhone('12345'), isNotNull);
    expect(Validators.isHttpUrl('https://youtu.be/x'), isTrue);
    expect(Validators.isHttpUrl('javascript:alert(1)'), isFalse);
  });
}
