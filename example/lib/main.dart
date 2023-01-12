import 'package:flutter/material.dart';

import 'package:tus_bg_file_uploader/tus_bg_file_uploader.dart';

import 'src/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initAndroidNotifChannel();
  runApp(const App());
}
