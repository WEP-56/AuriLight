import 'package:hive/hive.dart';

import '../utils/logger.dart';

class MangaAuthService {
  static final MangaAuthService _instance = MangaAuthService._internal();
  factory MangaAuthService() => _instance;
  MangaAuthService._internal();

  static const String _boxName = 'manga_auth';
  Box<dynamic>? _box;

  Future<void> ensureInitialized() async {
    if (_box != null && _box!.isOpen) return;
    _box = await Hive.openBox<dynamic>(_boxName);
  }

  Map<String, dynamic> _getRuleData(String ruleKey) {
    final raw = _box?.get(ruleKey);
    if (raw is Map) {
      return Map<String, dynamic>.from(raw.map((k, v) => MapEntry(k.toString(), v)));
    }
    return <String, dynamic>{};
  }

  Future<void> _setRuleData(String ruleKey, Map<String, dynamic> data) async {
    await ensureInitialized();
    await _box!.put(ruleKey, data);
  }

  String? getToken(String ruleKey) {
    final data = _getRuleData(ruleKey);
    final token = data['token']?.toString();
    return (token != null && token.trim().isNotEmpty) ? token : null;
  }

  Future<void> setToken(String ruleKey, String? token) async {
    final data = _getRuleData(ruleKey);
    if (token == null || token.trim().isEmpty) {
      data.remove('token');
    } else {
      data['token'] = token.trim();
    }
    await _setRuleData(ruleKey, data);
  }

  List<String>? getAccount(String ruleKey) {
    final data = _getRuleData(ruleKey);
    final raw = data['account'];
    if (raw is List && raw.length >= 2) {
      return [raw[0].toString(), raw[1].toString()];
    }
    return null;
  }

  Future<void> setAccount(String ruleKey, String username, String password) async {
    final data = _getRuleData(ruleKey);
    data['account'] = [username, password];
    await _setRuleData(ruleKey, data);
  }

  Future<void> clear(String ruleKey) async {
    await ensureInitialized();
    await _box!.delete(ruleKey);
    Logger.info('[MangaAuth] cleared: $ruleKey');
  }
}
