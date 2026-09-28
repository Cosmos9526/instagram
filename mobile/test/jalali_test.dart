import 'package:flutter_test/flutter_test.dart';
import 'package:postyar/screens/home_screen.dart';

void main() {
  test('gregorian to jalali', () {
    expect(toJalali(DateTime(2026, 9, 28)), (1405, 7, 6));
    expect(toJalali(DateTime(2025, 3, 21)), (1404, 1, 1));
    expect(toJalali(DateTime(2024, 3, 19)), (1402, 12, 29));
  });
}
