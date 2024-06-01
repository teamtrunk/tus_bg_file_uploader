import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tus_file_uploader/tus_file_uploader.dart';
import 'package:synchronized/synchronized.dart';

const pendingStoreKey = 'pending_uploading';
const processingStoreKey = 'processing_uploading';
const completeStoreKey = 'complete_uploading';
const failedStoreKey = 'failed_uploading';
const baseUrlStoreKey = 'base_files_uploading_url';
const failOnLostConnectionStoreKey = 'fail_on_lost_connection';
const compressParamsKey = 'compress_params';
const appIconStoreKey = 'app_icon';
const customSchemeKey = 'custom_scheme';
const metadataKey = 'metadata';
const headersKey = 'headers';
const timeoutKey = 'timeout';
const loggerLevel = 'logger_level';
const uploadAfterStartingServiceKey = 'upload_after_starting_service';

extension SharedPreferencesUtils on SharedPreferences {
  static final lock = Lock();

  // PUBLIC ----------------------------------------------------------------------------------------
  Future<void> init({required bool clearStorage}) async {
    return lock.synchronized(() async {
      if (clearStorage) {
        await remove(pendingStoreKey);
        await remove(processingStoreKey);
        await remove(completeStoreKey);
        await remove(failedStoreKey);
      }
    });
  }

  bool getUploadAfterStartingService() {
    return getBool(uploadAfterStartingServiceKey) ?? true;
  }

  Future<bool> setUploadAfterStartingService(bool value) async {
    return lock.synchronized(() => setBool(uploadAfterStartingServiceKey, value));
  }

  String? getBaseUrl() {
    return getString(baseUrlStoreKey);
  }

  Future<bool> setBaseUrl(String value) async {
    return lock.synchronized(() => setString(baseUrlStoreKey, value));
  }

  bool getFailOnLostConnection() {
    return getBool(failOnLostConnectionStoreKey) ?? false;
  }

  Future<bool> setFailOnLostConnection(bool value) async {
    return lock.synchronized(() => setBool(failOnLostConnectionStoreKey, value));
  }

  String? getAppIcon() {
    return getString(appIconStoreKey);
  }

  Future<bool> setAppIcon(String value) async {
    return lock.synchronized(() => setString(appIconStoreKey, value));
  }

  CompressParams? getCompressParams() {
    final encoded = getString(compressParamsKey);
    if (encoded == null) {
      return null;
    }
    final json = jsonDecode(encoded);
    if (json is Map<String, dynamic>) {
      return CompressParams.fromJson(json);
    }
    return null;
  }

  Future<bool> setCompressParams(CompressParams params) async {
    return lock.synchronized(() => setString(compressParamsKey, jsonEncode(params.toJson())));
  }

  List<UploadingModel> getPendingUploading() {
    return _getFilesForKey(pendingStoreKey).toList();
  }

  List<UploadingModel> getProcessingUploading() {
    return _getFilesForKey(processingStoreKey).toList();
  }

  List<UploadingModel> getCompleteUploading() {
    return _getFilesForKey(completeStoreKey).toList();
  }

  List<UploadingModel> getFailedUploading() {
    return _getFilesForKey(failedStoreKey).toList();
  }

  Map<String, String> getMetadata() {
    String? encodedResult = getString(metadataKey);
    if (encodedResult != null) {
      return Map.castFrom<String, dynamic, String, String>(jsonDecode(encodedResult));
    }
    return {};
  }

  Map<String, String> getHeaders() {
    String? encodedResult = getString(headersKey);
    if (encodedResult != null) {
      return Map.castFrom<String, dynamic, String, String>(jsonDecode(encodedResult));
    }
    return {};
  }

  int? getTimeout() {
    return getInt(timeoutKey);
  }

  int getLoggerLevel() {
    return getInt(loggerLevel) ?? 0;
  }

  Future<bool> setLoggerLevel(int level) async {
    return lock.synchronized(() => setInt(loggerLevel, level));
  }

  Future<void> setHeadersMetadata({
    Map<String, String>? headers,
    Map<String, String>? metadata,
  }) async {
    await lock.synchronized(() async {
      if (metadata != null) {
        await setString(metadataKey, jsonEncode(metadata));
      }
      if (headers != null) {
        await setString(headersKey, jsonEncode(headers));
      }
    });
  }

  Future<bool> setTimeout(int? timeout) async {
    return lock.synchronized(() {
      if (timeout != null) {
        return setInt(timeoutKey, timeout);
      } else {
        return false;
      }
    });
  }

  Future<void> addFileToPending({required UploadingModel uploadingModel}) async {
    final processingFiles = getProcessingUploading();

    if (processingFiles.contains(uploadingModel)) return;

    await removeFile(uploadingModel, failedStoreKey);
    await _updateMapEntry(uploadingModel, pendingStoreKey);
  }

  Future<void> addFileToProcessing({required UploadingModel uploadingModel}) async {
    await removeFile(uploadingModel, pendingStoreKey);
    await removeFile(uploadingModel, failedStoreKey);
    await removeFile(uploadingModel, completeStoreKey);
    await _updateMapEntry(uploadingModel, processingStoreKey);
  }

  Future<void> addFileToComplete({required UploadingModel uploadingModel}) async {
    await removeFile(uploadingModel, pendingStoreKey);
    await removeFile(uploadingModel, processingStoreKey);
    await removeFile(uploadingModel, failedStoreKey);
    uploadingModel.compressedPath = null;
    await _updateMapEntry(uploadingModel, completeStoreKey);
  }

  Future<bool> removeFile(UploadingModel uploadingModel, String storeKey) async {
    return lock.synchronized(() {
      final encodedResult = getStringList(storeKey);
      if (encodedResult != null) {
        final result = encodedResult.map((e) => UploadingModel.fromJson(jsonDecode(e))).toList();
        result.remove(uploadingModel);
        return setStringList(storeKey, result.map((e) => jsonEncode(e.toJson())).toList());
      } else {
        return false;
      }
    });
  }

  Future<void> addFileToFailed({required UploadingModel uploadingModel}) async {
    await removeFile(uploadingModel, pendingStoreKey);
    await removeFile(uploadingModel, processingStoreKey);
    await removeFile(uploadingModel, completeStoreKey);
    await _updateMapEntry(uploadingModel, failedStoreKey);
  }

  Future<bool> resetUploading() async {
    return lock.synchronized(() async {
      return remove(completeStoreKey);
    });
  }

  // PRIVATE ---------------------------------------------------------------------------------------
  Set<UploadingModel> _getFilesForKey(String storeKey) {
    final encodedResult = getStringList(storeKey);
    final Set<UploadingModel> result;
    if (encodedResult == null) {
      result = {};
    } else {
      result = encodedResult.map((e) => UploadingModel.fromJson(jsonDecode(e))).toSet();
    }

    return result;
  }

  Future<bool> _updateMapEntry(UploadingModel uploadingModel, String storeKey) async {
    return lock.synchronized(() async {
      final result = _getFilesForKey(storeKey);
      result.remove(uploadingModel);
      result.add(uploadingModel);

      return setStringList(storeKey, result.map((e) => jsonEncode(e.toJson())).toList());
    });
  }
}

const oneKB = 1000;

class CompressParams {
  final int relativeWidth;
  final int idealSize;

  const CompressParams({
    this.relativeWidth = 1920,
    this.idealSize = 1000 * oneKB,
  });

  Map<String, dynamic> toJson() {
    return {
      'relativeWidth': relativeWidth,
      'idealSize': idealSize,
    };
  }

  factory CompressParams.fromJson(Map<String, dynamic> map) {
    return CompressParams(
      relativeWidth: map['relativeWidth'] as int,
      idealSize: map['idealSize'] as int,
    );
  }
}
