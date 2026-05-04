import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'app.dart';
import 'services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeBackgroundService();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const PokemonCTApp());
}

Future<void> _initializeBackgroundService() async {
  try {
    BackgroundServiceManager().initializeBackground();
  } catch (e) {
    // Silently fail
  }
}
