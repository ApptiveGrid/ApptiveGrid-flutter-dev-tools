import 'package:apptive_grid_error_reporting/src/model/log_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Equality', () {
    final time = DateTime(2023, 9, 12, 13, 52);

    const message = 'Log Message';

    final entry1 = LogEntry(time: time, message: message);
    final entry2 = LogEntry(time: time, message: message);

    expect(entry1, equals(entry2));
  });

  test('Hash', () {
    final time = DateTime(2023, 9, 12, 13, 52);

    const message = 'Log Message';

    final entry = LogEntry(time: time, message: message);

    expect(entry.hashCode, equals(Object.hash(time, message)));
  });

  test('toString()', () {
    final time = DateTime(2023, 9, 12, 13, 52);

    const message = 'Log Message';

    final entry = LogEntry(time: time, message: message);

    expect(entry.toString(), equals('${time.toIso8601String()}: $message'));
  });
}
