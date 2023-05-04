import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tus_file_uploader/tus_file_uploader.dart';
import 'package:cross_file/cross_file.dart' show XFile;

import 'extensions.dart';

const _progressStream = 'progress_stream';
const _completionStream = 'completion_stream';
const _failureStream = 'failure_stream';

@pragma('vm:entry-point')
enum _NotificationIds {
  uploadProgress(888),
  // uploadFailure(333)
  ;

  final int id;

  const _NotificationIds(this.id);
}

Future<void> initAndroidNotifChannel() async {
  await FlutterLocalNotificationsPlugin().initialize(
    const InitializationSettings(
      iOS: DarwinInitializationSettings(),
      android: AndroidInitializationSettings('ic_bg_service_small'),
    ),
    onDidReceiveNotificationResponse: (response) async {
      // print('onDidReceiveNotificationResponse');
    },
  );

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'my_foreground', // id
    'MY FOREGROUND SERVICE', // title
    description: 'This channel is used for important notifications.', // description
    importance: Importance.low, // importance must be at low or higher level
  );

  await FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

class TusBGFileUploaderManager {
  @pragma('vm:entry-point')
  static final _instance = TusBGFileUploaderManager._();
  @pragma('vm:entry-point')
  static final cache = <String, TusFileUploader>{};

  @pragma('vm:entry-point')
  TusBGFileUploaderManager._();

  factory TusBGFileUploaderManager() {
    return _instance;
  }

  Stream<Map<String, dynamic>?> get progressStream => FlutterBackgroundService().on(
        _progressStream,
      );

  Stream<Map<String, dynamic>?> get completionStream => FlutterBackgroundService().on(
        _completionStream,
      );

  Stream<Map<String, dynamic>?> get failureStream => FlutterBackgroundService().on(
        _failureStream,
      );

  Future<void> setup(
    String baseUrl, {
    bool failOnLostConnection = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBaseUrl(baseUrl);
    prefs.setFailOnLostConnection(failOnLostConnection);
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'my_foreground',
        initialNotificationTitle: 'Upload files',
        initialNotificationContent: 'Preparing to upload',
        foregroundServiceNotificationId: _NotificationIds.uploadProgress.id,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  Future<Map<String, String>> checkForUnfinishedUploads() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingUploads = prefs.getPendingUploading();
    final processingUploads = prefs.getProcessingUploading();

    return pendingUploads..addAll(processingUploads);
  }

  Future<Map<String, String>> checkForFailedUploads() async {
    final prefs = await SharedPreferences.getInstance();
    final failedUploads = prefs.getFailedUploading();
    return failedUploads;
  }

  Future<void> uploadFiles(
    List<String> localFilePathList, {
    String? customScheme,
    Map<String, String>? headers,
    Map<String, String>? metadata,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await Future.wait(localFilePathList.map((path) => prefs.addFileToPending(path)));
    await prefs.setHeadersMetadata(headers: headers, metadata: metadata);
    await prefs.setCustomScheme(customScheme);
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
    }
  }

  void resumeAllUploading() async {
    final unfinishedFiles = await checkForUnfinishedUploads();
    if (unfinishedFiles.isEmpty) return;

    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
    }
  }

  // BACKGROUND ------------------------------------------------------------------------------------
  @pragma('vm:entry-point')
  static _onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }
    service.on('stopService').listen((_) => _dispose(service));

    _uploadFilesCallback(service);
  }

  @pragma('vm:entry-point')
  static FutureOr<bool> onIosBackground(ServiceInstance service) async {
    const workTime = 30;
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    await Future.delayed(const Duration(seconds: workTime));
    return true;
  }

  @pragma('vm:entry-point')
  static Future<void> _uploadFilesCallback(ServiceInstance service) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final processingUploads = _getProcessingUploads(prefs, service);
    await _uploadFiles(prefs, service, processingUploads);
    await prefs.reload();
    await prefs.resetUploading();
    _dispose(service);
  }

  @pragma('vm:entry-point')
  static Future<void> _onNextFileComplete({
    required ServiceInstance service,
    required String filePath,
    required String uploadUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.addFileToComplete(filePath);
    await _updateProgress(currentFileProgress: 1);
    service.invoke(_completionStream, {'filePath': filePath, 'url': uploadUrl});
  }

  @pragma('vm:entry-point')
  static Future<void> _onProgress({
    required String localPath,
    required double progress,
    required ServiceInstance service,
  }) async {
    service.invoke(_progressStream, {
      "filePath": localPath,
      "progress": (progress * 100).toInt(),
    });
    await _updateProgress(currentFileProgress: progress);
  }

  @pragma('vm:entry-point')
  static Future<void> _updateProgress({required double currentFileProgress}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final pendingFiles = prefs.getPendingUploading().length;
    final uploadingFiles = prefs.getProcessingUploading().length;
    final completeFiles = prefs.getCompleteUploading().length;
    final failedFiles = prefs.getFailedUploading().length;
    final allFiles = pendingFiles + uploadingFiles + completeFiles + failedFiles;
    final int progress;
    final String message;
    final bool iosShowProgress;
    if (allFiles == 1) {
      progress = (currentFileProgress * 100).toInt();
      message = 'Uploading file';
      iosShowProgress = true;
    } else {
      progress = (completeFiles / allFiles * 100).toInt();
      message = 'Uploaded $completeFiles of $allFiles files';
      iosShowProgress = false;
    }
    await updateNotification(
      title: message,
      progress: progress,
      iosShowProgress: iosShowProgress,
    );
  }

  @pragma('vm:entry-point')
  static Future<void> _onNextFileFailed({
    required String filePath,
    required ServiceInstance service,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.addFileToFailed(filePath);
    service.invoke(_failureStream, {'filePath': filePath});
  }

  // PRIVATE ---------------------------------------------------------------------------------------
  @pragma('vm:entry-point')
  static Future<void> _uploadFiles(
    SharedPreferences prefs,
    ServiceInstance service, [
    Iterable<Future<TusFileUploader>> processingUploads = const [],
  ]) async {
    await prefs.reload();
    final pendingUploads = _getPendingUploads(prefs, service);
    final headers = prefs.getHeaders();
    final total = processingUploads.length + pendingUploads.length;
    if (total > 0) {
      final uploaderList = await Future.wait([...processingUploads, ...pendingUploads]);
      await Future.wait(uploaderList.map((uploader) => uploader.upload(headers: headers)));
      await _uploadFiles(prefs, service);
    }
  }

  @pragma('vm:entry-point')
  static Iterable<Future<TusFileUploader>> _getProcessingUploads(
    SharedPreferences prefs,
    ServiceInstance service,
  ) {
    final uploadingFiles = prefs.getProcessingUploading();
    final metadata = prefs.getMetadata();
    final headers = prefs.getHeaders();
    return uploadingFiles.entries.where((e) => !cache.containsKey(e.key)).map((entry) async {
      final uploader = await _uploaderFromPath(
        service,
        entry.key,
        uploadUrl: entry.value,
        metadata: metadata,
        headers: headers,
      );
      cache[entry.key] = uploader;
      return uploader;
    });
  }

  @pragma('vm:entry-point')
  static Iterable<Future<TusFileUploader>> _getPendingUploads(
    SharedPreferences prefs,
    ServiceInstance service,
  ) {
    final pendingFiles = prefs.getPendingUploading();
    final customScheme = prefs.getCustomScheme();
    final metadata = prefs.getMetadata();
    final headers = prefs.getHeaders();
    return pendingFiles.entries.where((e) => !cache.containsKey(e.key)).map((entry) async {
      final uploader = await _uploaderFromPath(
        service,
        entry.key,
        customScheme: customScheme,
        metadata: metadata,
        headers: headers,
      );
      cache[entry.key] = uploader;
      final uploadUrl = await uploader.setupUploadUrl();
      if (uploadUrl != null) {
        prefs.addFileToProcessing(entry.key, uploadUrl);
      } else {
        prefs.removeFile(entry.key, processingStoreKey);
      }
      return uploader;
    });
  }

  @pragma('vm:entry-point')
  static Future<TusFileUploader> _uploaderFromPath(
    ServiceInstance service,
    String path, {
    String? uploadUrl,
    String? customScheme,
    Map<String, String>? headers,
    Map<String, String>? metadata,
  }) async {
    final xFile = XFile(path);
    final totalBytes = await xFile.length();
    final uploadMetadata = xFile.generateMetadata(originalMetadata: metadata);
    final resultHeaders = Map<String, String>.from(headers ?? {})
      ..addAll({
        "Tus-Resumable": tusVersion,
        "Upload-Metadata": uploadMetadata,
        "Upload-Length": "$totalBytes",
      });
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getBaseUrl();
    if (baseUrl == null) {
      throw Exception('baseUrl is required');
    }
    final failOnLostConnection = prefs.getFailOnLostConnection();
    if (uploadUrl == null) {
      return TusFileUploader.init(
        path: path,
        baseUrl: Uri.parse(baseUrl + (customScheme ?? '')),
        headers: resultHeaders,
        failOnLostConnection: failOnLostConnection,
        progressCallback: (filePath, progress) async => _onProgress(
          localPath: filePath,
          progress: progress,
          service: service,
        ),
        completeCallback: (filePath, uploadUrl) async => _onNextFileComplete(
          service: service,
          filePath: filePath,
          uploadUrl: uploadUrl,
        ),
        failureCallback: (filePath, _) async => _onNextFileFailed(
          filePath: filePath,
          service: service,
        ),
      );
    } else {
      return TusFileUploader.initAndSetup(
        path: path,
        baseUrl: Uri.parse(baseUrl),
        uploadUrl: Uri.parse(uploadUrl),
        failOnLostConnection: failOnLostConnection,
        headers: resultHeaders,
        progressCallback: (filePath, progress) async => _onProgress(
          localPath: filePath,
          progress: progress,
          service: service,
        ),
        completeCallback: (filePath, uploadUrl) async => _onNextFileComplete(
          service: service,
          filePath: filePath,
          uploadUrl: uploadUrl,
        ),
        failureCallback: (filePath, _) async => _onNextFileFailed(
          filePath: filePath,
          service: service,
        ),
      );
    }
  }

  @pragma('vm:entry-point')
  static Future<void> updateNotification({
    required String title,
    required int progress,
    required bool iosShowProgress,
    String? appIcon,
  }) async {
    await FlutterLocalNotificationsPlugin().show(
      _NotificationIds.uploadProgress.id,
      title,
      '',
      NotificationDetails(
          android: AndroidNotificationDetails(
            'my_foreground',
            'MY FOREGROUND SERVICE',
            showProgress: true,
            progress: progress,
            maxProgress: 100,
            icon: appIcon ?? 'ic_bg_service_small',
            ongoing: true,
          ),
          iOS: DarwinNotificationDetails(
              presentAlert: true,
              subtitle: iosShowProgress ? 'Progress $progress%' : null,
              interruptionLevel: InterruptionLevel.passive)),
    );
  }

  @pragma('vm:entry-point')
  static Future _dispose(ServiceInstance service) async {
    await Future.delayed(const Duration(seconds: 2)).whenComplete(
        () => FlutterLocalNotificationsPlugin().cancel(_NotificationIds.uploadProgress.id));
    service.stopSelf();
    cache.clear();
  }
}
