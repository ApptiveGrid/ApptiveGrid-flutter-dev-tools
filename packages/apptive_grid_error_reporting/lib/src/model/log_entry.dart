class LogEntry {
  const LogEntry({required this.time, required this.message});

  final DateTime time;
  final String message;

  @override
  String toString() {
    return '${time.toIso8601String()}: $message';
  }

  @override
  operator ==(Object other) {
    return identical(this, other) ||
        (other is LogEntry && time == other.time && message == other.message);
  }

  @override
  int get hashCode => Object.hash(time, message);
}
