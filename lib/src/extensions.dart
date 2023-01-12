import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const pendingStoreKey = 'pending_uploading';
const processingStoreKey = 'processing_uploading';
const completeStoreKey = 'complete_uploading';
const baseUrlStoreKey = 'base_files_uploading_url';
const failOnLostConnectionStoreKey = 'fail_on_lost_connection';
const appIconStoreKey = 'app_icon';

extension SharedPreferencesUtils on SharedPreferences {
  // PUBLIC ----------------------------------------------------------------------------------------
  String? getBaseUrl() {
    return getString(baseUrlStoreKey);
  }

  void setBaseUrl(String value) {
    setString(baseUrlStoreKey, value);
  }

  bool getFailOnLostConnection() {
    return getBool(failOnLostConnectionStoreKey) ?? false;
  }

  void setFailOnLostConnection(bool value) {
    setBool(failOnLostConnectionStoreKey, value);
  }

  String? getAppIcon() {
    return getString(appIconStoreKey);
  }

  void setAppIcon(String value) {
    setString(appIconStoreKey, value);
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

  void addFileToPending(String localPath) {
    _updateMapEntry(localPath, pendingStoreKey);
  }

  void addFileToProcessing(String localPath, String uploadUrl) {
    removeFile(localPath, pendingStoreKey);
    _updateMapEntry(localPath, processingStoreKey, uploadUrl);
  }

  void addFileToComplete(String localPath) {
    removeFile(localPath, processingStoreKey);
    _updateMapEntry(localPath, completeStoreKey);
  }

  void removeFile(String localPath, String storeKey) {
    String? encodedResult = getString(storeKey);
    if (encodedResult != null) {
      final result = Map<String, String>.from(jsonDecode(encodedResult));
      result.remove(localPath);
      setString(storeKey, jsonEncode(result));
    }
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

  void _updateMapEntry(String key, String storeKey, [String value = '']) {
    String? encodedResult = getString(storeKey);
    late Map<String, String> result;
    if (encodedResult == null) {
      result = {};
    } else {
      result = Map<String, String>.from(jsonDecode(encodedResult));
    }
    result[key] = value;
    setString(storeKey, jsonEncode(result));
  }
}
