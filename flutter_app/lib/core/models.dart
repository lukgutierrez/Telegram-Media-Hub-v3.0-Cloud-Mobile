class UserProfile {
  final int id;
  final String email;
  final bool isActive;
  final bool telegramConnected;
  final bool driveConnected;

  UserProfile({
    required this.id,
    required this.email,
    required this.isActive,
    required this.telegramConnected,
    required this.driveConnected,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] ?? 0,
      email: json['email'] ?? '',
      isActive: json['is_active'] ?? false,
      telegramConnected: json['telegram_connected'] ?? false,
      driveConnected: json['drive_connected'] ?? false,
    );
  }
}

class SearchResult {
  final int msgId;
  final int chatId;
  final String chatTitle;
  final String senderName;
  final String date;
  final String text;
  final bool hasMedia;
  final String mediaType; // VIDEO, PHOTO, DOCUMENT, TEXT
  final String filename;
  final double sizeMb;
  final int sizeBytes;
  final String origin; // FORUM_TOPIC, ALBUM_PACK, CONTEXT_ADJACENT, DIRECT_MATCH
  bool isSelected;

  SearchResult({
    required this.msgId,
    required this.chatId,
    required this.chatTitle,
    required this.senderName,
    required this.date,
    required this.text,
    required this.hasMedia,
    required this.mediaType,
    required this.filename,
    required this.sizeMb,
    required this.sizeBytes,
    required this.origin,
    this.isSelected = true,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      msgId: json['msg_id'] ?? 0,
      chatId: json['chat_id'] ?? 0,
      chatTitle: json['chat_title'] ?? 'Chat',
      senderName: json['sender_name'] ?? 'Usuario',
      date: json['date'] ?? '',
      text: json['text'] ?? '',
      hasMedia: json['has_media'] ?? false,
      mediaType: json['media_type'] ?? 'TEXT',
      filename: json['filename'] ?? 'archivo',
      sizeMb: (json['size_mb'] as num?)?.toDouble() ?? 0.0,
      sizeBytes: json['size_bytes'] ?? 0,
      origin: json['origin'] ?? 'DIRECT_MATCH',
      isSelected: json['has_media'] ?? false,
    );
  }
}

class SearchSummary {
  final int totalMatches;
  final int videosCount;
  final int photosCount;
  final int docsCount;
  final double totalMb;

  SearchSummary({
    required this.totalMatches,
    required this.videosCount,
    required this.photosCount,
    required this.docsCount,
    required this.totalMb,
  });

  factory SearchSummary.fromJson(Map<String, dynamic> json) {
    return SearchSummary(
      totalMatches: json['total_matches'] ?? 0,
      videosCount: json['videos_count'] ?? 0,
      photosCount: json['photos_count'] ?? 0,
      docsCount: json['docs_count'] ?? 0,
      totalMb: (json['total_mb'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class JobModel {
  final int id;
  final String jobType;
  final String targetUrl;
  final String status;
  final int totalFiles;
  final int processedFiles;
  final int failedFiles;
  final int totalBytes;
  final int processedBytes;
  final double speedMbs;
  final int etaSeconds;
  final String destination;
  final String createdAt;

  JobModel({
    required this.id,
    required this.jobType,
    required this.targetUrl,
    required this.status,
    required this.totalFiles,
    required this.processedFiles,
    required this.failedFiles,
    required this.totalBytes,
    required this.processedBytes,
    required this.speedMbs,
    required this.etaSeconds,
    required this.destination,
    required this.createdAt,
  });

  factory JobModel.fromJson(Map<String, dynamic> json) {
    return JobModel(
      id: json['id'] ?? 0,
      jobType: json['job_type'] ?? '',
      targetUrl: json['target_url'] ?? '',
      status: json['status'] ?? 'PENDING',
      totalFiles: json['total_files'] ?? 0,
      processedFiles: json['processed_files'] ?? 0,
      failedFiles: json['failed_files'] ?? 0,
      totalBytes: json['total_bytes'] ?? 0,
      processedBytes: json['processed_bytes'] ?? 0,
      speedMbs: (json['speed_mbs'] as num?)?.toDouble() ?? 0.0,
      etaSeconds: json['eta_seconds'] ?? 0,
      destination: json['destination'] ?? 'DIRECT_DOWNLOAD',
      createdAt: json['created_at'] ?? '',
    );
  }

  double get progressPercentage {
    if (totalFiles > 0) {
      return (processedFiles / totalFiles).clamp(0.0, 1.0);
    }
    return 0.0;
  }
}

class JobFileModel {
  final int id;
  final String filename;
  final double sizeMb;
  final String status;
  final String sha256;
  final bool hasLocalDownload;
  final String? downloadUrl;
  final String? driveLink;

  JobFileModel({
    required this.id,
    required this.filename,
    required this.sizeMb,
    required this.status,
    required this.sha256,
    required this.hasLocalDownload,
    this.downloadUrl,
    this.driveLink,
  });

  factory JobFileModel.fromJson(Map<String, dynamic> json) {
    return JobFileModel(
      id: json['id'] ?? 0,
      filename: json['filename'] ?? 'archivo',
      sizeMb: (json['size_mb'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] ?? 'COMPLETED',
      sha256: json['sha256'] ?? '',
      hasLocalDownload: json['has_local_download'] ?? false,
      downloadUrl: json['download_url'],
      driveLink: json['drive_link'],
    );
  }
}

class ChatModel {
  final dynamic id;
  final String title;
  final bool isChannel;
  final bool isGroup;
  final bool isForum;
  final String? username;
  final String? type;
  final dynamic members;

  ChatModel({
    required this.id,
    required this.title,
    required this.isChannel,
    required this.isGroup,
    required this.isForum,
    this.username,
    this.type,
    this.members,
  });

  factory ChatModel.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['type'] ?? '').toString().toLowerCase();
    return ChatModel(
      id: json['id']?.toString() ?? '0',
      title: json['title'] ?? 'Sin título',
      isChannel: json['is_channel'] == true || typeStr.contains('canal'),
      isGroup: json['is_group'] == true || typeStr.contains('grupo'),
      isForum: json['is_forum'] == true || typeStr.contains('foro') || typeStr.contains('topic'),
      username: json['username'],
      type: json['type']?.toString() ?? 'Canal',
      members: json['members'],
    );
  }
}

class TopicModel {
  final int id;
  final String title;
  final dynamic totalFiles;
  final dynamic sizeMb;
  bool isSelected;

  TopicModel({
    required this.id,
    required this.title,
    required this.totalFiles,
    required this.sizeMb,
    this.isSelected = true,
  });

  factory TopicModel.fromJson(Map<String, dynamic> json) {
    return TopicModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      title: json['title'] ?? 'Tema',
      totalFiles: json['total_files'] ?? '-',
      sizeMb: json['size_mb'] ?? '-',
      isSelected: true,
    );
  }
}

class DedupStats {
  final int totalUniqueFiles;
  final double totalSavedMb;
  final int totalQueries;

  DedupStats({
    required this.totalUniqueFiles,
    required this.totalSavedMb,
    required this.totalQueries,
  });

  factory DedupStats.fromJson(Map<String, dynamic> json) {
    return DedupStats(
      totalUniqueFiles: json['total_unique_files'] ?? 0,
      totalSavedMb: (json['total_saved_mb'] as num?)?.toDouble() ?? 0.0,
      totalQueries: json['total_queries'] ?? 0,
    );
  }
}
