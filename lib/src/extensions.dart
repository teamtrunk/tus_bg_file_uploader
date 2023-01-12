import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const pendingStoreKey = 'pending_uploading';
const processingStoreKey = 'processing_uploading';
const completeStoreKey = 'complete_uploading';
const failedStoreKey = 'failed_uploading';
const baseUrlStoreKey = 'base_files_uploading_url';
const failOnLostConnectionStoreKey = 'fail_on_lost_connection';
const appIconStoreKey = 'app_icon';

extension SharedPreferencesUtils on SharedPreferences {
  // PUBLIC ----------------------------------------------------------------------------------------
  String? getBaseUrl() {
    return getString(baseUrlStoreKey);
  }

  Future<bool> setBaseUrl(String value) async{
    return setString(baseUrlStoreKey, value);
  }

  bool getFailOnLostConnection() {
    return getBool(failOnLostConnectionStoreKey) ?? false;
  }

  Future<bool> setFailOnLostConnection(bool value) async{
    return setBool(failOnLostConnectionStoreKey, value);
  }

  String? getAppIcon() {
    return getString(appIconStoreKey);
  }

  Future<bool> setAppIcon(String value) async {
    return setString(appIconStoreKey, value);
  }

  Map<String, String> getPendingUploading() {
    return _getFilesForKey(pendingStoreKey);
  }

  Map<String, String> getProcessingUploading() {
    return _getFilesForKey(processingStoreKey);
  }

  Map<String, String> getCompleteUploading() {
    return _getFilesForKey(completeStoreKey);
  }

  Map<String, String> getFailedUploading() {
    return _getFilesForKey(failedStoreKey);
  }

  Future<void> addFileToPending(String localPath) async{
    await _updateMapEntry(localPath, pendingStoreKey);
  }

  Future<void> addFileToProcessing(String localPath, String uploadUrl) async{
    await removeFile(localPath, pendingStoreKey);
    await _updateMapEntry(localPath, processingStoreKey, uploadUrl);
  }

  Future<void> addFileToComplete(String localPath) async{
    await removeFile(localPath, processingStoreKey);
    await _updateMapEntry(localPath, completeStoreKey);
  }

  Future<void> removeFile(String localPath, String storeKey) async{
    String? encodedResult = getString(storeKey);
    if (encodedResult != null) {
      final result = Map<String, String>.from(jsonDecode(encodedResult));
      result.remove(localPath);
      await setString(storeKey, jsonEncode(result));
    }
  }

  Future<void> addFileToFailed(String localPath) async{
    await removeFile(localPath, processingStoreKey);
    await _updateMapEntry(localPath, failedStoreKey);
  }

  Future<void> removeFileFromFailed(String localPath) async{
    return removeFile(localPath, failedStoreKey);
  }



  Future<void> resetUploading() async {
    await remove(pendingStoreKey);
    await remove(processingStoreKey);
    await remove(completeStoreKey);
  }

  // PRIVATE ---------------------------------------------------------------------------------------
  Map<String, String> _getFilesForKey(String key) {
    String? encodedResult = getString(key);
    late Map<String, String> result;
    if (encodedResult == null) {
      result = {};
    } else {
      result = Map<String, String>.from(jsonDecode(encodedResult));
    }
    return result;
  }

  Future<bool> _updateMapEntry(String key, String storeKey, [String value = '']) async{
    String? encodedResult = getString(storeKey);
    late Map<String, String> result;
    if (encodedResult == null) {
      result = {};
    } else {
      result = Map<String, String>.from(jsonDecode(encodedResult));
    }
    result[key] = value;
    return setString(storeKey, jsonEncode(result));
  }
}
