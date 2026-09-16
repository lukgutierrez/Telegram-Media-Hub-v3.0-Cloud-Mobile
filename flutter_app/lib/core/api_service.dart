import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class ApiService extends ChangeNotifier {
  static const String _defaultUrl = 'https://pdas-stats-orbit-forbes.trycloudflare.com/api/v1';
  String _baseUrl = _defaultUrl;
  String? _token;
  UserProfile? _userProfile;
  bool _isLoading = false;

  String get baseUrl => _baseUrl;
  String? get token => _token;
  UserProfile? get userProfile => _userProfile;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  String get rootServerUrl {
    if (_baseUrl.endsWith('/api/v1')) {
      return _baseUrl.substring(0, _baseUrl.length - 7);
    }
    return _baseUrl;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('server_url') ?? _defaultUrl;
    _token = prefs.getString('auth_token');
    if (_token != null) {
      await fetchMe();
    }
    notifyListeners();
  }

  Future<void> setBaseUrl(String url) async {
    String cleanUrl = url.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    if (!cleanUrl.endsWith('/api/v1')) {
      cleanUrl = '$cleanUrl/api/v1';
    }
    _baseUrl = cleanUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', _baseUrl);
    notifyListeners();
  }

  Map<String, String> _headers({bool isJson = true}) {
    final h = <String, String>{};
    if (isJson) {
      h['Content-Type'] = 'application/json';
    }
    if (_token != null && _token!.isNotEmpty) {
      h['Authorization'] = 'Bearer $_token';
    }
    return h;
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'username': email, 'password': password},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _token = data['access_token'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', _token!);
        await fetchMe();
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Error en login: $e');
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> register(String email, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _token = data['access_token'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', _token!);
        await fetchMe();
        return true;
      }
    } catch (e) {
      debugPrint('Error en register: $e');
    }
    return false;
  }

  Future<bool> resetPassword(String email, String newPassword, {String? resetCode}) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'new_password': newPassword,
          'reset_code': resetCode ?? 'DIRECT_RESET'
        }),
      );
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Error en resetPassword: $e');
      return false;
    }
  }

  Future<bool> loginWithQuickCode(String quickCode) async {
    _isLoading = true;
    notifyListeners();
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/quick-login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': quickCode.trim().toUpperCase()}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _token = data['access_token'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', _token!);
        await fetchMe();
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Error en quick-login: $e');
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    _token = null;
    _userProfile = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    notifyListeners();
  }

  Future<UserProfile?> fetchMe() async {
    if (_token == null) return null;
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/auth/me'),
        headers: _headers(),
      );
      if (res.statusCode == 200) {
        _userProfile = UserProfile.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
        notifyListeners();
        return _userProfile;
      }
    } catch (e) {
      debugPrint('Error en fetchMe: $e');
    }
    return null;
  }

  // --- TELEGRAM AUTH ---
  Future<Map<String, dynamic>> telegramSendCode(String phone) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/telegram/auth/send-code'),
        headers: _headers(),
        body: jsonEncode({'phone': phone}),
      );
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (e) {
      return {'detail': 'Error de conexión: $e'};
    }
  }

  Future<Map<String, dynamic>> telegramVerifyCode(String phone, String code, {String? password}) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/telegram/auth/verify-code'),
        headers: _headers(),
        body: jsonEncode({'phone': phone, 'code': code, 'password': password}),
      );
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode == 200) {
        await fetchMe();
      }
      return data;
    } catch (e) {
      return {'detail': 'Error de conexión: $e'};
    }
  }

  Future<void> telegramDisconnect() async {
    try {
      await http.delete(
        Uri.parse('$_baseUrl/telegram/disconnect'),
        headers: _headers(),
      );
      await fetchMe();
    } catch (e) {
      debugPrint('Error desconectando Telegram: $e');
    }
  }

  // --- BUSCADOR ULTRA PROFUNDO 360° ---
  Future<Map<String, dynamic>> searchTelegramGlobal(String query, {String filter = 'ALL', int limit = 150}) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/osint/telegram-global-search'),
        headers: _headers(),
        body: jsonEncode({'query': query, 'media_filter': filter, 'limit': limit}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final list = (data['results'] as List?)?.map((i) => SearchResult.fromJson(i)).toList() ?? [];
        final summary = SearchSummary.fromJson(data['summary'] ?? {});
        return {'results': list, 'summary': summary};
      }
    } catch (e) {
      debugPrint('Error en searchTelegramGlobal: $e');
    }
    return {'results': <SearchResult>[], 'summary': SearchSummary(totalMatches: 0, videosCount: 0, photosCount: 0, docsCount: 0, totalMb: 0)};
  }

  Future<int?> startSearchBatchJob(String query, List<SearchResult> items, {int concurrency = 10, String destination = 'DIRECT_DOWNLOAD'}) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/osint/download-search-batch'),
        headers: _headers(),
        body: jsonEncode({
          'query': query,
          'selected_items': items.map((it) => {
            'chat_id': it.chatId,
            'msg_id': it.msgId,
            'chat_title': it.chatTitle,
          }).toList(),
          'destination': destination,
          'concurrency': concurrency,
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['job_id'];
      }
    } catch (e) {
      debugPrint('Error en startSearchBatchJob: $e');
    }
    return null;
  }

  // --- JOBS & DESCARGAS ---
  Future<int?> createJob({
    required String targetUrl,
    required String jobType,
    int concurrency = 10,
    String destination = 'DIRECT_DOWNLOAD',
    String? filterMedia,
    List<int>? topicIds,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/jobs/'),
        headers: _headers(),
        body: jsonEncode({
          'target_url': targetUrl,
          'job_type': jobType,
          'concurrency': concurrency,
          'destination': destination,
          'media_filter': filterMedia ?? 'ALL',
          'filter_media': filterMedia,
          'selected_topic_ids': topicIds,
          'topic_ids': topicIds,
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['id'];
      }
    } catch (e) {
      debugPrint('Error en createJob: $e');
    }
    return null;
  }

  Future<List<JobModel>> getJobs() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/jobs/'), headers: _headers());
      if (res.statusCode == 200) {
        final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
        return list.map((j) => JobModel.fromJson(j)).toList();
      }
    } catch (e) {
      debugPrint('Error en getJobs: $e');
    }
    return [];
  }

  Future<List<JobFileModel>> getJobFiles(int jobId) async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/jobs/$jobId/files'), headers: _headers());
      if (res.statusCode == 200) {
        final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
        return list.map((f) => JobFileModel.fromJson(f)).toList();
      }
    } catch (e) {
      debugPrint('Error en getJobFiles: $e');
    }
    return [];
  }

  Future<bool> sendJobSignal(int jobId, String action) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/jobs/$jobId/signal'),
        headers: _headers(),
        body: jsonEncode({'action': action}),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<DedupStats> getDedupStats() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/jobs/stats/dedup'), headers: _headers());
      if (res.statusCode == 200) {
        return DedupStats.fromJson(jsonDecode(res.body));
      }
    } catch (e) {
      debugPrint('Error en getDedupStats: $e');
    }
    return DedupStats(totalUniqueFiles: 0, totalSavedMb: 0, totalQueries: 0);
  }

  // --- OSINT & CHATS ---
  Future<List<ChatModel>> getMyChats() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/osint/my-chats'), headers: _headers());
      if (res.statusCode == 200) {
        final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
        return list.map((c) => ChatModel.fromJson(c)).toList();
      }
    } catch (e) {
      debugPrint('Error en getMyChats: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>> inspectChat(String target) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/osint/inspect'),
        headers: _headers(),
        body: jsonEncode({'target': target}),
      );
      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes));
      }
    } catch (e) {
      debugPrint('Error en inspectChat: $e');
      return {'detail': 'Error al inspeccionar chat: $e'};
    }
    return {'detail': 'Error al inspeccionar chat'};
  }

  Future<Map<String, dynamic>> preAnalyzeTopics(String target, {List<int>? topicIds, int concurrency = 10}) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/osint/pre-analyze-topics'),
        headers: _headers(),
        body: jsonEncode({'target': target, 'topic_ids': topicIds, 'concurrency': concurrency}),
      );
      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes));
      }
    } catch (e) {
      debugPrint('Error en preAnalyzeTopics: $e');
    }
    return {};
  }

  String getZipDownloadUrl(int jobId) {
    return '$_baseUrl/jobs/$jobId/download-zip?token=$_token';
  }

  String getSingleMediaDownloadUrl(int chatId, int msgId) {
    return '$_baseUrl/osint/download-single-media?chat_id=$chatId&msg_id=$msgId&token=$_token';
  }
}
