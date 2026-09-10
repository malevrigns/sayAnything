import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player_win/video_player_win.dart';
import 'api.dart';
import 'app.dart';
export 'app.dart' show SayAnythingApp;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    WindowsVideoPlayer.registerWith();
  }
  runApp(SayAnythingApp(api: Api()));
}
