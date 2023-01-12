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

void initAndroidNotifChannel() async {
  await FlutterLocalNotificationsPlugin().initialize(
    const InitializationSettings(
      iOS: DarwinInitializationSettings(),
      android: AndroidInitializationSettings('ic_bg_service_small'),
    ),
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    onDidReceiveNotificationResponse: (response) async {
      print('onDidReceiveNotificationResponse');
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

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  FlutterBackgroundService().startService();
}

class TusBGFileUploaderManager {
  @pragma('vm:entry-point')
  static final _instance = TusBGFileUploaderManager._();
  @pragma('vm:entry-point')
  static final _cache = <String, TusFileUploader>{};

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

  Future<void> uploadFile({
    required String localFilePath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.addFileToPending(localFilePath);
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      service.startService();
    }
  }

  void pauseAllUploading() async {
    _cache.forEach((key, value) {
      value.pause();
    });
  }

  // BACKGROUND ------------------------------------------------------------------------------------
  @pragma('vm:entry-point')
  void resumeAllUploading() async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      service.startService();
    }
    _cache.forEach((key, value) {
      value.upload();
    });
  }

  @pragma('vm:entry-point')
  static _onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    await _uploadFilesCallback(service);
    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }
    service.on('stopService').listen((event) => _dispose(service));
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
  static Future _dispose(ServiceInstance service) async {
    FlutterLocalNotificationsPlugin().cancel(_NotificationIds.uploadProgress.id);
    service.stopSelf();
    _cache.clear();
  }

  @pragma('vm:entry-point')
  static Future<void> _uploadFilesCallback(ServiceInstance service) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final storedUploads = _getStoredUploads(prefs, service);
    await _uploadFiles(prefs, service, storedUploads);
    await prefs.resetUploading();
    _dispose(service);
  }

  @pragma('vm:entry-point')
  static void updateNotification({
    required ServiceInstance service,
    required String title,
    required int progress,
    String? appIcon,
  }) {
    FlutterLocalNotificationsPlugin().show(
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
      ),
    );
  }

  @pragma('vm:entry-point')
  static void _onNextFileComplete({
    required String filePath,
    required ServiceInstance service,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.addFileToComplete(filePath);
    final pendingFiles = prefs.getPendingUploading().length;
    final uploadingFiles = prefs.getProcessingUploading().length;
    final completeFiles = prefs.getCompleteUploading().length;
    final allFiles = pendingFiles + uploadingFiles + completeFiles;
    final progress = (completeFiles / allFiles * 100).toInt();
    updateNotification(
      title: 'Uploaded $completeFiles of $allFiles files',
      progress: progress,
      service: service,
    );
  }

  @pragma('vm:entry-point')
  static void _onProgress({
    required String localPath,
    required double progress,
    required ServiceInstance service,
  }) {
    service.invoke(_progressStream, {
      "filePath": localPath,
      "progress": (progress * 100).toInt(),
    });
  }

  @pragma('vm:entry-point')
  static void _onNextFileFailed({
    required String filePath,
    required ServiceInstance service,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.removeFile(filePath, processingStoreKey);
  }

  // PRIVATE ---------------------------------------------------------------------------------------
  static Future<void> _uploadFiles(
    SharedPreferences prefs,
    ServiceInstance service, [
    Iterable<Future> storedUploads = const [],
  ]) async {
    await prefs.reload();
    final pendingUploads = _getPendingUploads(prefs, service);
    final total = storedUploads.length + pendingUploads.length;
    if (total > 0) {
      await Future.wait([...storedUploads, ...pendingUploads]);
      await _uploadFiles(prefs, service);
    }
  }

  static Iterable<Future> _getStoredUploads(
    SharedPreferences prefs,
    ServiceInstance service,
  ) {
    final uploadingFiles = prefs.getProcessingUploading();
    return uploadingFiles.entries.where((e) => !_cache.containsKey(e.key)).map((entry) async {
      final uploader = await _uploaderFromPath(
        service,
        entry.key,
        entry.value,
      );
      _cache[entry.key] = uploader;
      await uploader.upload();
    });
  }

  static Iterable<Future> _getPendingUploads(
    SharedPreferences prefs,
    ServiceInstance service,
  ) {
    final pendingFiles = prefs.getPendingUploading();
    return pendingFiles.entries.where((e) => !_cache.containsKey(e.key)).map((entry) async {
      final uploader = await _uploaderFromPath(
        service,
        entry.key,
      );
      _cache[entry.key] = uploader;
      final uploadUrl = await uploader.setupUploadUrl();
      if (uploadUrl != null) {
        prefs.addFileToProcessing(entry.key, uploadUrl);
      } else {
        prefs.removeFile(entry.key, processingStoreKey);
      }
      await uploader.upload();
    });
  }

  static Future<TusFileUploader> _uploaderFromPath(
    ServiceInstance service,
    String path, [
    String? uploadUrl,
  ]) async {
    final xFile = XFile(path);
    final totalBytes = await xFile.length();
    final uploadMetadata = xFile.generateMetadata();
    final resultHeaders = Map<String, String>.from({})
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
        baseUrl: Uri.parse(baseUrl),
        headers: resultHeaders,
        failOnLostConnection: failOnLostConnection,
        progressCallback: (filePath, progress) => _onProgress(
          localPath: filePath,
          progress: progress,
          service: service,
        ),
        completeCallback: (filePath, _) => _onNextFileComplete(
          filePath: filePath,
          service: service,
        ),
        failureCallback: (filePath, _) => _onNextFileFailed(
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
        progressCallback: (filePath, progress) => _onProgress(
          localPath: filePath,
          progress: progress,
          service: service,
        ),
        completeCallback: (filePath, _) => _onNextFileComplete(
          filePath: filePath,
          service: service,
        ),
        failureCallback: (filePath, _) => _onNextFileFailed(
          filePath: filePath,
          service: service,
        ),
      );
    }
  }
}
