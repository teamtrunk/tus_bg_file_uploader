
class FileModel{
  final String path;
  double progress;
  bool failed;

  FileModel(this.path, {this.progress = 0, this.failed = false});

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'progress': progress,
      'failed': failed,
    };
  }

  factory FileModel.fromJson(Map<String, dynamic> map) {
    return FileModel(
      map['path'] as String,
      progress: map['progress'] as double,
      failed: map['failed'] as bool,
    );
  }
}