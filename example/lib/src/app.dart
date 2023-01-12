import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:tus_bg_file_uploader/tus_bg_file_uploader.dart';

import 'tile.dart';

class App extends StatefulWidget {
  const App({Key? key}) : super(key: key);

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final uploadingManager = TusBGFileUploaderManager();
  final files = <String, double>{};

  StreamSubscription? progressSubscription;
  StreamSubscription? completionSubscription;
  StreamSubscription? failureSubscription;

  UploadingState uploadingState = UploadingState.notStarted;

  @override
  void initState() {
    super.initState();
    uploadingManager.setup('https://master.tus.io/files/');
    progressSubscription = uploadingManager.progressStream.listen((event) {
      final data = event as Map<String, dynamic>;
      final progress = data['progress'] as int;
      final filePath = data['filePath'];
      setState(() {
        files[filePath] = progress / 100;
      });
    });
    completionSubscription = uploadingManager.completionStream.listen((event) {
      setState(() {
        updateUploadingStatus();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Upload images'),
          actions: [
            if (uploadingState == UploadingState.uploading)
              IconButton(
                onPressed: pauseAll,
                icon: const Icon(Icons.pause),
              )
            else if (uploadingState == UploadingState.paused)
              IconButton(
                onPressed: resumeAll,
                icon: const Icon(Icons.play_arrow),
              )
            else
              IconButton(
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    allowMultiple: true,
                  );
                  setState(() {
                    if (result != null) {
                      for (final file in result.files) {
                        final path = file.path;
                        if (path != null && !files.containsKey(path)) {
                          files[path] = 0;
                        }
                      }
                    }
                  });
                },
                icon: const Icon(Icons.file_copy),
              ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: files.keys.fold(
              [],
              (res, next) => [
                ...res,
                const SizedBox(height: 16),
                ImageTile(next, progress: files[next]),
              ],
            ),
          ),
        ),
        bottomNavigationBar: files.values.where((e) => e == 0).isNotEmpty
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: ElevatedButton(
                    onPressed: uploadAll,
                    child: const Text('Upload Files'),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Future<void> uploadAll() async {
    setState(() {
      uploadingState = UploadingState.uploading;
    });
    Future.delayed(const Duration(milliseconds: 0)).then((value) {
      for (final path in files.keys) {
        if (files[path] == 0) {
          uploadingManager.uploadFile(
            localFilePath: path,
            // completeCallback: onUploadingComplete,
            // progressCallback: onUploadingProgress,
            // failureCallback: onUploadingFailed,
          );
        }
      }
    });
  }

  void pauseAll() {
    uploadingManager.pauseAllUploading();
    setState(() {
      uploadingState = UploadingState.paused;
    });
  }

  void resumeAll() {
    uploadingManager.resumeAllUploading();
    setState(() {
      uploadingState = UploadingState.uploading;
    });
  }

  void onUploadingProgress(String filePath, double progress) {
    setState(() {
      files[filePath] = progress;
    });
  }

  void onUploadingComplete(String filePath, String url) {
    setState(() {
      updateUploadingStatus();
    });
  }

  void onUploadingFailed(String filePath, String message) {
    setState(() {
      files[filePath] = 0;
      updateUploadingStatus();
    });
  }

  void updateUploadingStatus() {
    final uploadingFilesCount = files.values.where((v) => v == 0).length;
    if (uploadingFilesCount == 0) {
      uploadingState = UploadingState.notStarted;
    }
  }
}
