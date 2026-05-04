class StartAllResult {
  final String accountEmail;
  final bool success;
  final String? error;
  final DateTime startTime;
  final DateTime endTime;
  final String status; // 'success' | 'error' | 'stopped'

  StartAllResult({
    required this.accountEmail,
    required this.success,
    this.error,
    required this.startTime,
    required this.endTime,
    required this.status,
  });

  Duration get duration => endTime.difference(startTime);
}

class StartAllReport {
  final DateTime startTime;
  final DateTime? endTime;
  final List<StartAllResult> results;

  StartAllReport({
    required this.startTime,
    this.endTime,
    required this.results,
  });

  int get successCount => results.where((r) => r.status == 'success').length;
  int get errorCount => results.where((r) => r.status == 'error').length;
  int get stoppedCount => results.where((r) => r.status == 'stopped').length;

  String toTxt() {
    final buf = StringBuffer();
    buf.writeln('=== START ALL REPORT ===');
    buf.writeln('Start: ${startTime.toString()}');
    buf.writeln('End: ${endTime?.toString() ?? "Running..."}');
    buf.writeln('---');
    buf.writeln('Success: $successCount | Error: $errorCount | Stopped: $stoppedCount');
    buf.writeln('---');
    for (final r in results) {
      buf.writeln('${r.accountEmail}: ${r.status} (${r.duration.inSeconds}s)');
      if (r.error != null) buf.writeln('  Error: ${r.error}');
    }
    return buf.toString();
  }

  String toCsv() {
    final buf = StringBuffer();
    buf.writeln('Email,Status,Duration(s),Error');
    for (final r in results) {
      final error = r.error?.replaceAll(',', ';') ?? '';
      buf.writeln('${r.accountEmail},${r.status},${r.duration.inSeconds},$error');
    }
    return buf.toString();
  }
}
