import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';

class LiveProgressEvent {
  final int jobId;
  final String status;
  final double progress;
  final double speedMbs;
  final int etaSeconds;
  final int activeWorkers;
  final int totalFiles;
  final int processedFiles;
  final int dedupCount;

  LiveProgressEvent({
    required this.jobId,
    required this.status,
    required this.progress,
    required this.speedMbs,
    required this.etaSeconds,
    this.activeWorkers = 1,
    this.totalFiles = 0,
    this.processedFiles = 0,
    this.dedupCount = 0,
  });

  factory LiveProgressEvent.fromJson(Map<String, dynamic> json) {
    return LiveProgressEvent(
      jobId: json['job_id'] ?? 0,
      status: json['status'] ?? 'RUNNING',
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      speedMbs: (json['speed_mbs'] as num?)?.toDouble() ?? 0.0,
      etaSeconds: json['eta_seconds'] ?? 0,
      activeWorkers: json['active_workers'] ?? 1,
      totalFiles: json['total_files'] ?? 0,
      processedFiles: json['processed_files'] ?? 0,
      dedupCount: json['dedup_count'] ?? 0,
    );
  }
}

class WebSocketService extends ChangeNotifier {
  final ApiService _apiService;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  LiveProgressEvent? _latestProgress;
  bool _isConnected = false;
  Timer? _reconnectTimer;

  LiveProgressEvent? get latestProgress => _latestProgress;
  bool get isConnected => _isConnected;

  WebSocketService(this._apiService) {
    _apiService.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (_apiService.isAuthenticated && _apiService.userProfile != null) {
      connect();
    } else {
      disconnect();
    }
  }

  void connect() {
    if (_isConnected || _apiService.userProfile == null) return;

    final uId = _apiService.userProfile!.id;
    String wsUrl = _apiService.rootServerUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
    wsUrl = '$wsUrl/ws/progress/$uId';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      notifyListeners();

      _subscription = _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            _latestProgress = LiveProgressEvent.fromJson(data);
            notifyListeners();
          } catch (e) {
            debugPrint('Error parseando WS message: ');
          }
        },
        onError: (error) {
          debugPrint('Error en WS: ');
          _reconnect();
        },
        onDone: () {
          _isConnected = false;
          notifyListeners();
          _reconnect();
        },
      );
    } catch (e) {
      _isConnected = false;
      notifyListeners();
      _reconnect();
    }
  }

  void _reconnect() {
    _isConnected = false;
    notifyListeners();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), () {
      if (_apiService.isAuthenticated) {
        connect();
      }
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _latestProgress = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _apiService.removeListener(_onAuthChanged);
    disconnect();
    super.dispose();
  }
}
