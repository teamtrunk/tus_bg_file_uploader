
class FileModel{
  final String path;
  double progress;
  bool failed;
  String? url;

  FileModel(this.path, {this.progress = 0, this.failed = false, this.url});

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'progress': progress,
      'failed': failed,
      'url': url,
    };
  }

  factory FileModel.fromJson(Map<String, dynamic> map) {
    return FileModel(
      map['path'] as String,
      progress: map['progress'] as double,
      failed: map['failed'] as bool,
      url: map['url'] as String?,
    );
  }
}