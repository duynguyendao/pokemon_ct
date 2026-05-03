import 'package:flutter/foundation.dart';

class DebugService extends ChangeNotifier {
  static final DebugService _instance = DebugService._internal();

  factory DebugService() {
    return _instance;
  }

  DebugService._internal();

  final List<String> _logs = [];
  static const int _maxLogs = 100;

  List<String> get logs => _logs;

  void log(String message) {
    final timestamp = DateTime.now().toIso8601String().split('T')[1].split('.')[0];
    final formatted = '[$timestamp] $message';
    _logs.insert(0, formatted);
    if (_logs.length > _maxLogs) {
      _logs.removeLast();
    }
    notifyListeners();
    if (kDebugMode) {
      print(formatted);
    }
  }

  void clear() {
    _logs.clear();
    notifyListeners();
  }
}

final debugService = DebugService();
