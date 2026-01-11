import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';

import '../models/manga_item.dart';
import '../utils/logger.dart';
import 'manga_auth_service.dart';
import 'smart_network_service_v2.dart';

class MangaJsonEngine {
  late Map<String, dynamic> rule;
  List<String> availableDomains = [];

  List<String>? _picacgApiBaseCandidates;

  String? _runtimeImageHost;

  final SmartNetworkServiceV2 _networkService = SmartNetworkServiceV2();
  final MangaAuthService _auth = MangaAuthService();
  FlutterQjs? _qjs;

  MangaJsonEngine(String jsonContent) {
    rule = jsonDecode(jsonContent) as Map<String, dynamic>;
    _networkService.initialize();
  }

  String get baseUrl {
    if (availableDomains.isNotEmpty) {
      return 'https://${availableDomains.first}';
    }
    return rule['baseURL']?.toString() ?? '';
  }

  String get name => rule['displayName']?.toString() ?? rule['name']?.toString() ?? '';

  String get userAgent =>
      rule['userAgent']?.toString() ??
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

  bool get supportsAccount => rule['account'] is Map;

  String? get _accountType => (rule['account'] is Map) ? (rule['account']['type']?.toString()) : null;

  Future<void> refreshDomains() async {
    try {
      final cfg = rule['domainRefresh'];
      if (cfg is! Map) return;
      if (cfg['enabled'] != true) return;
      final url = cfg['url']?.toString();
      if (url == null || url.trim().isEmpty) return;

      final res = await _networkService.getHtml(
        url,
        headers: {
          'User-Agent': userAgent,
        },
        forceWebView: rule['useWebview'] == true,
      );
      if (res.isFailure || res.data == null) return;

      final selector = cfg['selector']?.toString() ?? 'a[href]';
      final pattern = cfg['pattern']?.toString();
      if (pattern == null || pattern.isEmpty) return;
      final exclude = <String>{};
      final ex = cfg['exclude'];
      if (ex is List) {
        exclude.addAll(ex.map((e) => e.toString()));
      }

      final doc = html_parser.parse(res.data!);
      final reg = RegExp(pattern);
      final domains = <String>[];
      for (final el in doc.querySelectorAll(selector)) {
        final href = el.attributes['href']?.toString();
        if (href == null || href.trim().isEmpty) continue;
        final m = reg.firstMatch(href);
        if (m == null) continue;
        final d = (m.groupCount >= 1 ? m.group(1) : m.group(0))?.toString();
        if (d == null || d.trim().isEmpty) continue;
        if (exclude.contains(d)) continue;
        if (!domains.contains(d)) domains.add(d);
      }

      availableDomains = domains;
    } catch (e) {
      Logger.warning('[MangaJsonEngine] refreshDomains failed: $e');
    }
  }

  Future<void> logout() async {
    if (!supportsAccount) return;

    final accountCfg = (rule['account'] is Map) ? (rule['account'] as Map).cast<String, dynamic>() : null;
    final logoutCfg = accountCfg == null ? null : accountCfg['logout'];
    if (logoutCfg is Map && logoutCfg['clearCookies'] == true) {
      _networkService.clearCookies();
    }

    await _auth.clear(rule['name']?.toString() ?? 'unknown');
  }

  Future<bool> login(String username, String password) async {
    if (!supportsAccount) return false;
    if (_accountType == 'picacg') {
      return _loginPicacg(username, password);
    }

    // Generic login for cookie/encrypted API rules (e.g. JM) driven by rule json.
    final accountCfg = (rule['account'] as Map).cast<String, dynamic>();
    final loginCfg = accountCfg['login'];
    if (loginCfg is Map) {
      return _loginByRule(username, password, accountCfg, loginCfg.cast<String, dynamic>());
    }
    return false;
  }

  Future<bool> _loginByRule(
    String username,
    String password,
    Map<String, dynamic> accountCfg,
    Map<String, dynamic> loginCfg,
  ) async {
    try {
      final httpMethod = (loginCfg['httpMethod']?.toString() ?? 'POST').toUpperCase();
      final pathTemplate = loginCfg['path']?.toString() ?? '';
      if (pathTemplate.trim().isEmpty) return false;

      final vars = <String, String>{
        'username': Uri.encodeComponent(username),
        'password': Uri.encodeComponent(password),
      };

      final path = _template(pathTemplate, vars);
      final url = _buildAbsoluteUrl(baseUrl, path.startsWith('/') ? path : '/$path');

      final contentType = loginCfg['contentType']?.toString();
      final bodyTemplate = loginCfg['bodyTemplate']?.toString();
      final body = (bodyTemplate != null && bodyTemplate.isNotEmpty) ? _template(bodyTemplate, vars) : null;

      final headers = <String, String>{
        if (contentType != null && contentType.trim().isNotEmpty) 'Content-Type': contentType.trim(),
      };

      Future<NetworkResult<String>> doReq(String p) {
        return _requestRuleApi(
          ruleKey: rule['name']?.toString() ?? 'unknown',
          baseApiUrl: baseUrl,
          method: httpMethod,
          path: p.startsWith('/') ? p : '/$p',
          extraHeaders: headers,
          body: body,
        );
      }

      var res = await doReq(path);
      if (res.isFailure && (res.error?.contains('HTTP 404') == true)) {
        // Generic fallback: some APIs live under '/api/*'.
        // Avoid hardcoding per-source by retrying with '/api' prefix once.
        final normalized = path.startsWith('/') ? path : '/$path';
        if (!normalized.startsWith('/api/')) {
          res = await doReq('/api$normalized');
        }
      }

      if (res.isFailure) {
        Logger.warning('[MangaJsonEngine] loginByRule failed: ${res.error}');
        return false;
      }

      // Persist account, and mark as logged-in via a lightweight token.
      final key = rule['name']?.toString() ?? 'unknown';
      await _auth.setAccount(key, username, password);
      await _auth.setToken(key, 'cookie');

      await _refreshImageHostIfNeeded(accountCfg);
      return true;
    } catch (e) {
      Logger.warning('[MangaJsonEngine] loginByRule exception: $e');
      return false;
    }
  }

  String _getImageHost() {
    final cached = _runtimeImageHost;
    if (cached != null && cached.trim().isNotEmpty) return cached.trim();
    final fallback = rule['imageHost']?.toString();
    if (fallback != null && fallback.trim().isNotEmpty) {
      _runtimeImageHost = fallback.trim();
      return _runtimeImageHost!;
    }
    return '';
  }

  Future<void> _refreshImageHostIfNeeded(Map<String, dynamic> accountCfg) async {
    final cfg = accountCfg['imageHostRefresh'];
    if (cfg is! Map) return;
    final method = cfg['method']?.toString();
    if (method != 'encryptedJson') return;
    final httpMethod = (cfg['httpMethod']?.toString() ?? 'GET').toUpperCase();
    final pathTemplate = cfg['path']?.toString() ?? '';
    if (pathTemplate.trim().isEmpty) return;

    final imageStream = accountCfg['imageStream']?.toString() ?? '1';
    final path = _template(pathTemplate, {
      'imageStream': imageStream,
    });
    final resultPath = cfg['resultPath']?.toString() ?? '';
    if (resultPath.trim().isEmpty) return;

    final res = await _requestRuleApi(
      ruleKey: rule['name']?.toString() ?? 'unknown',
      baseApiUrl: baseUrl,
      method: httpMethod,
      path: path,
    );
    if (res.isFailure || res.data == null) return;

    final decoded = _tryJsonDecode(res.data!);
    if (decoded == null) return;
    final host = _getByPath(decoded, resultPath)?.toString();
    if (host != null && host.trim().isNotEmpty) {
      _runtimeImageHost = host.trim();
    }
  }

  Future<bool> reLogin() async {
    if (!supportsAccount) return false;
    final key = rule['name']?.toString() ?? 'unknown';
    final acc = _auth.getAccount(key);
    if (acc == null || acc.length < 2) return false;
    return login(acc[0], acc[1]);
  }

  Future<List<MangaItem>> search(String keyword, {int page = 1}) async {
    if (!rule.containsKey('search')) return [];

    if (rule.containsKey('domainRefresh') && availableDomains.isEmpty) {
      await refreshDomains();
    }

    final searchConfig = (rule['search'] as Map).cast<String, dynamic>();
    final method = searchConfig['method']?.toString();

    final idSearch = searchConfig['idSearch'];
    if (idSearch is Map && idSearch['enabled'] == true) {
      final regexText = idSearch['regex']?.toString();
      if (regexText != null && regexText.trim().isNotEmpty) {
        final m = RegExp(regexText.trim(), caseSensitive: false).firstMatch(keyword.trim());
        if (m != null) {
          final groupIdx = int.tryParse(idSearch['idGroup']?.toString() ?? '') ?? 1;
          final id = (m.groupCount >= groupIdx ? m.group(groupIdx) : null)?.toString();
          if (id != null && id.trim().isNotEmpty) {
            final detail = await getDetail(id.trim());
            if (detail != null) {
              return [
                MangaItem(
                  id: detail.id,
                  title: detail.title,
                  cover: detail.cover,
                  description: detail.description,
                  ruleName: name,
                  ruleKey: rule['name']?.toString() ?? 'unknown',
                ),
              ];
            }
            return [];
          }
        }
      }
    }

    if (method == 'json') {
      final ruleKey = rule['name']?.toString() ?? 'unknown';
      final baseApiUrl = searchConfig['baseApiUrl']?.toString() ??
          (supportsAccount ? (rule['account']['baseApiUrl']?.toString() ?? baseUrl) : baseUrl);
      final httpMethod = (searchConfig['httpMethod']?.toString() ?? 'GET').toUpperCase();
      final pathTemplate = searchConfig['path']?.toString() ?? '';
      if (pathTemplate.isEmpty) return [];

      final vars = <String, String>{
        'keyword': keyword,
        'page': page.toString(),
      };

      final defaults = searchConfig['defaultVars'];
      if (defaults is Map) {
        for (final e in defaults.entries) {
          final k = e.key.toString();
          if (k.isEmpty) continue;
          vars.putIfAbsent(k, () => e.value.toString());
        }
      }

      final path = _template(pathTemplate, vars);
      final bodyTemplate = searchConfig['bodyTemplate']?.toString();
      final body = (bodyTemplate != null && bodyTemplate.isNotEmpty) ? _template(bodyTemplate, vars) : null;

      Future<NetworkResult<String>> doReq() {
        return _requestJsonApi(
          ruleKey: ruleKey,
          baseApiUrl: baseApiUrl,
          method: httpMethod,
          path: path,
          body: body,
        );
      }

      var res = await doReq();
      if (res.isFailure && (res.error?.contains('HTTP 401') == true) && supportsAccount) {
        final ok = await reLogin();
        if (ok) res = await doReq();
      }

      if (res.isFailure || res.data == null) return [];
      final data = _tryJsonDecode(res.data!);
      if (data == null) return [];
      return _parseJsonSearchResults(data, searchConfig);
    }

    final searchUrlTemplate = searchConfig['searchURL']?.toString() ?? '';
    if (searchUrlTemplate.isEmpty) return [];

    final searchPath = searchUrlTemplate.replaceAll('{keyword}', Uri.encodeComponent(keyword));
    String searchUrl = _buildAbsoluteUrl(baseUrl, searchPath);
    if (page > 1 && searchConfig['pageParam'] != null) {
      searchUrl += searchConfig['pageParam'].toString().replaceAll('{page}', page.toString());
    }

    final headers = Map<String, String>.from(searchConfig['headers'] ?? {});
    headers['User-Agent'] = userAgent;
    final res = await _networkService.getHtml(searchUrl, headers: headers, forceWebView: rule['useWebview'] == true);
    if (res.isFailure || res.data == null) return [];
    return _parseSearchResults(res.data!, searchConfig);
  }

  Future<MangaDetail?> getDetail(String mangaId) async {
    if (!rule.containsKey('detail')) return null;
    final detailConfig = (rule['detail'] as Map).cast<String, dynamic>();
    final method = detailConfig['method']?.toString();

    if (method == 'json') {
      final ruleKey = rule['name']?.toString() ?? 'unknown';
      final baseApiUrl = detailConfig['baseApiUrl']?.toString() ??
          (supportsAccount ? (rule['account']['baseApiUrl']?.toString() ?? baseUrl) : baseUrl);
      final httpMethod = (detailConfig['httpMethod']?.toString() ?? 'GET').toUpperCase();
      final pathTemplate = detailConfig['path']?.toString() ?? '';
      if (pathTemplate.isEmpty) return null;

      final path = _template(pathTemplate, {
        'id': mangaId,
        'mangaId': mangaId,
        'comicId': mangaId,
      });

      Future<NetworkResult<String>> doReq() {
        return _requestJsonApi(
          ruleKey: ruleKey,
          baseApiUrl: baseApiUrl,
          method: httpMethod,
          path: path,
        );
      }

      var res = await doReq();
      if (res.isFailure && (res.error?.contains('HTTP 401') == true) && supportsAccount) {
        final ok = await reLogin();
        if (ok) res = await doReq();
      }

      if (res.isFailure || res.data == null) return null;
      final data = _tryJsonDecode(res.data!);
      if (data == null) return null;

      final mapping = (detailConfig['mapping'] is Map)
          ? (detailConfig['mapping'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      final rootPath = mapping['rootPath']?.toString() ?? 'data.comic';
      final root = _getByPath(data, rootPath);

      final title = _getByPath(root, mapping['titlePath']?.toString() ?? 'title')?.toString() ?? '';
      final description = _getByPath(root, mapping['descriptionPath']?.toString() ?? 'description')?.toString();
      final fs = _getByPath(root, mapping['fileServerPath']?.toString() ?? 'thumb.fileServer')?.toString() ?? '';
      final p = _getByPath(root, mapping['pathPath']?.toString() ?? 'thumb.path')?.toString() ?? '';
      final coverTemplate = mapping['coverTemplate']?.toString() ?? '{fileServer}/static/{path}';
      var cover = coverTemplate.replaceAll('{fileServer}', fs).replaceAll('{path}', p);
      cover = cover.replaceAll('{id}', mangaId);
      cover = cover.replaceAll('{imageHost}', _getImageHost());

      Map<String, List<String>>? tags;
      final tagMap = <String, List<String>>{};
      final author = _getByPath(root, mapping['authorPath']?.toString() ?? 'author')?.toString();
      if (author != null && author.trim().isNotEmpty) tagMap['Author'] = [author.trim()];
      final cats = _getByPath(root, mapping['categoriesPath']?.toString() ?? 'categories');
      if (cats is List) {
        final list = cats.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
        if (list.isNotEmpty) tagMap['Categories'] = list;
      }
      final tgs = _getByPath(root, mapping['tagsPath']?.toString() ?? 'tags');
      if (tgs is List) {
        final list = tgs.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
        if (list.isNotEmpty) tagMap['Tags'] = list;
      }
      if (tagMap.isNotEmpty) tags = tagMap;

      Map<String, String>? chapters;
      final chaptersCfg = detailConfig['chapters'];
      if (chaptersCfg is Map) {
        final cm = chaptersCfg['method']?.toString();

        if (cm == 'fromDetail') {
          final sourcePath = chaptersCfg['sourcePath']?.toString() ?? 'series';
          final idPath = chaptersCfg['idPath']?.toString() ?? 'id';
          final titlePath = chaptersCfg['titlePath']?.toString() ?? 'name';
          final orderPath = chaptersCfg['orderPath']?.toString() ?? 'sort';
          final fallbackSingle = chaptersCfg['fallbackSingle'] == true;

          final src = _getByPath(data, sourcePath);
          if (src is List) {
            final list = src.toList();
            list.sort((a, b) {
              final av = int.tryParse(_getByPath(a, orderPath)?.toString() ?? '') ?? 0;
              final bv = int.tryParse(_getByPath(b, orderPath)?.toString() ?? '') ?? 0;
              return av.compareTo(bv);
            });
            final map = <String, String>{};
            for (final it in list) {
              final id = _getByPath(it, idPath)?.toString();
              if (id == null || id.trim().isEmpty) continue;
              var title = _getByPath(it, titlePath)?.toString() ?? '';
              title = title.trim();
              if (title.isEmpty) {
                final ord = _getByPath(it, orderPath)?.toString() ?? '';
                title = ord.trim().isEmpty ? id.trim() : '第${ord.trim()}話';
              }
              map[id.trim()] = title;
            }
            if (map.isNotEmpty) chapters = map;
          }
          if ((chapters == null || chapters!.isEmpty) && fallbackSingle) {
            chapters = {mangaId: '第1話'};
          }
        }
        if (cm == 'jsonPaged') {
          final pathTemplate2 = chaptersCfg['path']?.toString() ?? '';
          if (pathTemplate2.isNotEmpty) {
            final listPath = chaptersCfg['listPath']?.toString() ?? 'data.eps.docs';
            final pagesPath = chaptersCfg['pagesPath']?.toString() ?? 'data.eps.pages';
            final orderPath = chaptersCfg['orderPath']?.toString() ?? 'order';
            final titlePath = chaptersCfg['titlePath']?.toString() ?? 'title';

            final map = <String, String>{};
            var pIdx = 1;
            var maxP = 1;
            while (pIdx <= maxP) {
              final path2 = _template(pathTemplate2, {
                'id': mangaId,
                'mangaId': mangaId,
                'comicId': mangaId,
                'page': pIdx.toString(),
              });

              final r = await _requestJsonApi(
                ruleKey: ruleKey,
                baseApiUrl: baseApiUrl,
                method: 'GET',
                path: path2,
              );
              if (r.isFailure || r.data == null) break;
              final jd = _tryJsonDecode(r.data!);
              if (jd == null) break;
              final lp = _getByPath(jd, listPath);
              if (lp is List) {
                for (final ep in lp) {
                  final ord = _getByPath(ep, orderPath)?.toString();
                  final tt = _getByPath(ep, titlePath)?.toString() ?? '';
                  if (ord != null && ord.trim().isNotEmpty) {
                    map[ord.trim()] = tt.trim().isEmpty ? ord.trim() : tt.trim();
                  }
                }
              }
              final mp = _getByPath(jd, pagesPath);
              final n = int.tryParse(mp?.toString() ?? '');
              if (n != null && n > 0) maxP = n;
              pIdx++;
            }
            if (map.isNotEmpty) chapters = map;
          }
        }
      }

      return MangaDetail(
        id: mangaId,
        title: title,
        cover: cover,
        description: description,
        tags: tags,
        chapters: chapters,
        ruleName: name,
        ruleKey: rule['name']?.toString() ?? 'unknown',
      );
    }

    final detailUrlTemplate = detailConfig['detailURL']?.toString() ?? '';
    if (detailUrlTemplate.isEmpty) return null;
    final detailUrlPath = detailUrlTemplate.replaceAll('{id}', mangaId);
    final detailUrl = _buildAbsoluteUrl(baseUrl, detailUrlPath);
    final res = await _networkService.getHtml(
      detailUrl,
      headers: {
        'User-Agent': userAgent,
      },
      forceWebView: rule['useWebview'] == true,
    );
    if (res.isFailure || res.data == null) return null;

    final doc = html_parser.parse(res.data!);
    final selectors = (detailConfig['selectors'] as Map).cast<String, dynamic>();
    String readText(dynamic cfg, {String defaultAttr = 'text'}) {
      if (cfg is String) {
        final sel = cfg.trim();
        if (sel.isEmpty) return '';
        return doc.querySelector(sel)?.text.trim() ?? '';
      }
      if (cfg is Map) {
        final sel = cfg['selector']?.toString();
        final attrs = _normalizeAttrList(cfg['attr'], defaultAttr: defaultAttr);
        return _extractElementValue(sel == null ? null : doc.querySelector(sel), attrs)?.trim() ?? '';
      }
      return '';
    }

    final title = readText(selectors['title']);
    String? cover;
    final coverCfg = selectors['cover'];
    if (coverCfg is Map) {
      final sel = coverCfg['selector']?.toString();
      final attr = _normalizeAttrList(coverCfg['attr'], defaultAttr: 'src');
      cover = _extractElementValue(sel == null ? null : doc.querySelector(sel), attr);
    }
    final descriptionText = readText(selectors['description']);
    final description = descriptionText.trim().isEmpty ? null : descriptionText.trim();

    Map<String, List<String>>? tags;
    final tagsCfg = selectors['tags'];
    if (tagsCfg != null) {
      if (tagsCfg is Map) {
        final sel = tagsCfg['selector']?.toString();
        final attrs = _normalizeAttrList(tagsCfg['attr'], defaultAttr: 'text');
        if (sel != null && sel.trim().isNotEmpty) {
          final list = <String>[];
          for (final el in doc.querySelectorAll(sel.trim())) {
            final v = _extractElementValue(el, attrs);
            final t = v?.trim() ?? '';
            if (t.isNotEmpty) list.add(t);
          }
          if (list.isNotEmpty) tags = {'Tags': list};
        }
      } else if (tagsCfg is String) {
        final sel = tagsCfg.trim();
        if (sel.isNotEmpty) {
          final list = doc.querySelectorAll(sel).map((e) => e.text.trim()).where((e) => e.isNotEmpty).toList();
          if (list.isNotEmpty) tags = {'Tags': list};
        }
      }
    }

    Map<String, String>? chapters;
    final chaptersCfg = detailConfig['chapters'];
    if (chaptersCfg is Map) {
      final cm = chaptersCfg['method']?.toString();

      if (cm == 'selector') {
        final sel = chaptersCfg['selector']?.toString() ?? '';
        if (sel.trim().isNotEmpty) {
          final attrs = _normalizeAttrList(chaptersCfg['attr'], defaultAttr: 'text');
          final hrefBase = chaptersCfg['hrefBase']?.toString();
          final reverse = chaptersCfg['reverse'] == true;
          final nodes = doc.querySelectorAll(sel.trim());
          final list = reverse ? nodes.reversed : nodes;
          final map = <String, String>{};
          var idx = 1;
          for (final el in list) {
            final t = _extractElementValue(el, attrs)?.trim() ?? '';
            if (t.isEmpty) continue;
            // Prefer stable chapter id from link href when possible (e.g. chapters are rendered as <a href=...><span>Title</span></a>)
            String id = idx.toString();
            try {
              dom.Element? cur = el;
              while (cur != null && cur.localName != 'a') {
                cur = cur.parent;
              }
              final href = cur?.attributes['href']?.toString();
              if (href != null && href.trim().isNotEmpty) {
                id = href.trim();
                if (hrefBase != null && hrefBase.trim().isNotEmpty) {
                  id = _buildAbsoluteUrl(hrefBase.trim(), id);
                }
              }
            } catch (_) {
              // ignore
            }
            map[id] = t;
            idx++;
          }
          if (map.isNotEmpty) chapters = map;
        }
      }

      if (cm == 'html' || cm == 'json') {
        String? mid;
        final midCfg = chaptersCfg['mangaId'];
        if (midCfg is Map) {
          final sel = midCfg['selector']?.toString();
          final attrs = _normalizeAttrList(midCfg['attr'], defaultAttr: 'data-mid');
          if (sel != null && sel.trim().isNotEmpty) {
            mid = _extractElementValue(doc.querySelector(sel.trim()), attrs)?.trim();
          }
        }

        if (mid != null && mid.trim().isNotEmpty) {
          final apiTemplate = chaptersCfg['apiURL']?.toString() ?? '';
          if (apiTemplate.trim().isNotEmpty) {
            final ts = DateTime.now().millisecondsSinceEpoch.toString();
            final apiPath = apiTemplate.replaceAll('{mid}', mid!.trim()).replaceAll('{ts}', ts);
            final apiUrl = _buildAbsoluteUrl(baseUrl, apiPath);
            final headers = <String, String>{
              'User-Agent': userAgent,
            };
            final chHeaders = chaptersCfg['headers'];
            if (chHeaders is Map) {
              for (final e in chHeaders.entries) {
                headers[e.key.toString()] = e.value.toString();
              }
            }

            final r = await _networkService.requestText(apiUrl, method: 'GET', headers: headers);
            if (!r.isFailure && r.data != null) {
              if (cm == 'html') {
                final itemSel = chaptersCfg['itemSelector']?.toString() ?? '';
                final idTemplate = chaptersCfg['idTemplate']?.toString() ?? '{0}';
                final msAttr = chaptersCfg['msAttr']?.toString() ?? 'data-ms';
                final csAttr = chaptersCfg['csAttr']?.toString() ?? 'data-cs';
                final titleSel = chaptersCfg['titleSelector']?.toString();
                final titleAttr = chaptersCfg['titleAttr'];
                if (itemSel.trim().isNotEmpty) {
                  final d2 = html_parser.parse(r.data!);
                  final map = <String, String>{};
                  for (final el in d2.querySelectorAll(itemSel.trim())) {
                    final ms = el.attributes[msAttr]?.toString().trim() ?? '';
                    final cs = el.attributes[csAttr]?.toString().trim() ?? '';
                    if (ms.isEmpty || cs.isEmpty) continue;
                    final id = idTemplate.replaceAll('{ms}', ms).replaceAll('{cs}', cs).replaceAll('{mid}', mid!.trim());
                    String title = '';
                    if (titleSel != null && titleSel.trim().isNotEmpty) {
                      final tEl = el.querySelector(titleSel.trim());
                      final attrs = _normalizeAttrList(titleAttr, defaultAttr: 'text');
                      title = _extractElementValue(tEl, attrs)?.trim() ?? '';
                    }
                    if (title.isEmpty) title = id;
                    map[id] = title;
                  }
                  if (map.isNotEmpty) chapters = map;
                }
              }

              if (cm == 'json') {
                final data = _tryJsonDecode(r.data!);
                if (data != null) {
                  final resultPath = chaptersCfg['resultPath']?.toString() ?? '';
                  final idPath = chaptersCfg['idPath']?.toString() ?? 'id';
                  final titlePath = chaptersCfg['titlePath']?.toString() ?? 'title';
                  final idTemplate = chaptersCfg['idTemplate']?.toString();
                  final raw = resultPath.trim().isEmpty ? data : _getByPath(data, resultPath);
                  if (raw is List) {
                    final map = <String, String>{};
                    for (final it in raw) {
                      final cid = _getByPath(it, idPath)?.toString().trim();
                      if (cid == null || cid.isEmpty) continue;
                      final t = _getByPath(it, titlePath)?.toString().trim() ?? '';
                      var id = cid;
                      if (idTemplate != null && idTemplate.isNotEmpty) {
                        id = idTemplate.replaceAll('{mid}', mid!.trim()).replaceAll('{id}', cid);
                      }
                      map[id] = t.isEmpty ? id : t;
                    }
                    if (map.isNotEmpty) chapters = map;
                  }
                }
              }
            }
          }
        }
      }
    }

    return MangaDetail(
      id: mangaId,
      title: title,
      cover: cover,
      description: description,
      tags: tags,
      chapters: chapters,
      ruleName: name,
      ruleKey: rule['name']?.toString() ?? 'unknown',
    );
  }

  Future<List<String>> getImages(String mangaId, {String? chapterId}) async {
    if (!rule.containsKey('reader')) return [];

    final readerConfig = (rule['reader'] as Map).cast<String, dynamic>();
    final readerMethod = readerConfig['method']?.toString() ?? 'selector';

    if (readerMethod == 'apiJsonPaged') {
      final ruleKey = rule['name']?.toString() ?? 'unknown';
      final baseApiUrl = readerConfig['baseApiUrl']?.toString() ??
          (supportsAccount ? (rule['account']['baseApiUrl']?.toString() ?? baseUrl) : baseUrl);
      final pathTemplate = readerConfig['path']?.toString() ?? '';
      if (pathTemplate.isEmpty) return [];

      final listPath = readerConfig['listPath']?.toString() ?? '';
      final pagesPath = readerConfig['pagesPath']?.toString() ?? '';
      final fileServerPath = readerConfig['fileServerPath']?.toString() ?? '';
      final imgPathPath = readerConfig['pathPath']?.toString() ?? '';
      final urlTemplate = readerConfig['urlTemplate']?.toString() ?? '{fileServer}/static/{path}';
      if (listPath.isEmpty || pagesPath.isEmpty || fileServerPath.isEmpty || imgPathPath.isEmpty) {
        return [];
      }

      final ep = chapterId ?? '1';
      final images = <String>[];
      var page = 1;
      var maxP = 1;
      while (page <= maxP) {
        final path = _template(pathTemplate, {
          'comicId': mangaId,
          'mangaId': mangaId,
          'id': mangaId,
          'chapterId': ep,
          'epId': ep,
          'page': page.toString(),
        });

        Future<NetworkResult<String>> doReq() {
          return _requestJsonApi(
            ruleKey: ruleKey,
            baseApiUrl: baseApiUrl,
            method: 'GET',
            path: path,
          );
        }

        var res = await doReq();
        if (res.isFailure && (res.error?.contains('HTTP 401') == true) && supportsAccount) {
          final ok = await reLogin();
          if (ok) res = await doReq();
        }
        if (res.isFailure || res.data == null) break;

        final data = _tryJsonDecode(res.data!);
        if (data == null) break;

        final lp = _getByPath(data, listPath);
        if (lp is List) {
          for (final it in lp) {
            final fs = _getByPath(it, fileServerPath)?.toString() ?? '';
            final pth = _getByPath(it, imgPathPath)?.toString() ?? '';
            if (fs.isEmpty || pth.isEmpty) continue;
            var url = urlTemplate.replaceAll('{fileServer}', fs).replaceAll('{path}', pth);
            if (readerConfig.containsKey('postProcess')) {
              url = _applyImagePostProcess(url, readerConfig['postProcess']);
            }
            images.add(url);
          }
        }

        final mp = _getByPath(data, pagesPath);
        final n = int.tryParse(mp?.toString() ?? '');
        if (n != null && n > 0) maxP = n;
        page++;
      }
      return images;
    }

    if (readerMethod == 'json') {
      final ruleKey = rule['name']?.toString() ?? 'unknown';
      final baseApiUrl = readerConfig['baseApiUrl']?.toString() ??
          (supportsAccount ? (rule['account']['baseApiUrl']?.toString() ?? baseUrl) : baseUrl);
      final httpMethod = (readerConfig['httpMethod']?.toString() ?? 'GET').toUpperCase();
      final pathTemplate = readerConfig['path']?.toString() ?? '';
      final imagesUrlTemplate = readerConfig['imagesURL']?.toString() ?? '';
      if (pathTemplate.isEmpty && imagesUrlTemplate.isEmpty) return [];

      final listPath = readerConfig['listPath']?.toString() ?? '';
      final urlTemplate = readerConfig['urlTemplate']?.toString() ?? '';
      if (listPath.isEmpty || urlTemplate.isEmpty) return [];

      final ep = chapterId ?? mangaId;
      Future<NetworkResult<String>> doReq() {
        if (pathTemplate.isNotEmpty) {
          final path = _template(pathTemplate, {
            'id': mangaId,
            'mangaId': mangaId,
            'comicId': mangaId,
            'chapterId': ep,
            'epId': ep,
          });
          return _requestJsonApi(
            ruleKey: ruleKey,
            baseApiUrl: baseApiUrl,
            method: httpMethod,
            path: path,
            extraHeaders: (readerConfig['headers'] is Map)
                ? (readerConfig['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))
                : null,
          );
        }

        final url = _buildUrlFromTemplate(imagesUrlTemplate, mangaId: mangaId, chapterId: ep);
        final headers = <String, String>{
          'User-Agent': userAgent,
        };
        final extra = readerConfig['headers'];
        if (extra is Map) {
          for (final e in extra.entries) {
            headers[e.key.toString()] = e.value.toString();
          }
        }
        return _networkService.requestText(url, method: httpMethod, headers: headers);
      }

      var res = await doReq();
      if (res.isFailure && (res.error?.contains('HTTP 401') == true) && supportsAccount) {
        final ok = await reLogin();
        if (ok) res = await doReq();
      }
      if (res.isFailure || res.data == null) return [];

      final data = _tryJsonDecode(res.data!);
      if (data == null) return [];

      final raw = _getByPath(data, listPath);
      if (raw is! List) return [];

      final images = <String>[];
      for (final it in raw) {
        final imageName = it?.toString() ?? '';
        if (imageName.trim().isEmpty) continue;
        var url = urlTemplate;
        url = url.replaceAll('{imageHost}', _getImageHost());
        url = url.replaceAll('{id}', mangaId);
        url = url.replaceAll('{mangaId}', mangaId);
        url = url.replaceAll('{comicId}', mangaId);
        url = url.replaceAll('{chapterId}', ep);
        url = url.replaceAll('{epId}', ep);
        url = url.replaceAll('{imageName}', imageName.trim());
        images.add(url);
      }
      return images;
    }

    final imagesUrlTemplate = readerConfig['imagesURL']?.toString() ?? '';
    if (imagesUrlTemplate.isEmpty) return [];

    var resolvedMangaId = mangaId;
    var resolvedChapterId = chapterId;
    if (chapterId != null &&
        chapterId.contains('@') &&
        imagesUrlTemplate.contains('{mangaId}') &&
        (imagesUrlTemplate.contains('{chapterId}') || imagesUrlTemplate.contains('{epId}'))) {
      final parts = chapterId.split('@');
      if (parts.length >= 2) {
        final mid = parts[0].trim();
        final cid = parts.sublist(1).join('@').trim();
        if (mid.isNotEmpty && cid.isNotEmpty) {
          resolvedMangaId = mid;
          resolvedChapterId = cid;
        }
      }
    }

    final imagesUrl = _buildUrlFromTemplate(
      imagesUrlTemplate,
      mangaId: resolvedMangaId,
      chapterId: resolvedChapterId,
    );

    final requestHeaders = <String, String>{
      'User-Agent': userAgent,
    };

    final readerHeaders = readerConfig['headers'];
    if (readerHeaders is Map) {
      for (final entry in readerHeaders.entries) {
        requestHeaders[entry.key.toString()] = entry.value.toString();
      }
    }

    final readerReferer = readerConfig['referer']?.toString();
    final referer = (readerReferer != null && readerReferer.trim().isNotEmpty) ? readerReferer : baseUrl;
    if (!requestHeaders.containsKey('Referer') && referer.trim().isNotEmpty) {
      requestHeaders['Referer'] = referer;
    }

    final useWebview = rule['useWebview'] == true;
    final result = await _networkService.getHtml(
      imagesUrl,
      headers: requestHeaders,
      forceWebView: useWebview,
    );
    if (result.isFailure || result.data == null) return [];

    if (readerMethod == 'regex') {
      final pattern = RegExp(readerConfig['pattern'].toString());
      final matches = pattern.allMatches(result.data!);
      final images = <String>[];
      for (final match in matches) {
        var imageUrl = match.group(0) ?? '';
        if (imageUrl.isEmpty) continue;
        if (readerConfig.containsKey('prefix')) {
          imageUrl = readerConfig['prefix'].toString() + imageUrl;
        }
        if (readerConfig.containsKey('postProcess')) {
          imageUrl = _applyImagePostProcess(imageUrl, readerConfig['postProcess']);
        }
        images.add(imageUrl);
      }
      return images;
    }

    if (readerMethod == 'selector') {
      final doc = html_parser.parse(result.data!);
      final selector = readerConfig['selector']?.toString() ?? 'img';
      final attrs = _normalizeAttrList(readerConfig['attr'], defaultAttr: 'src');
      final elements = doc.querySelectorAll(selector);
      final images = <String>[];
      for (final el in elements) {
        var imageUrl = _extractElementValue(el, attrs);
        if (imageUrl == null || imageUrl.trim().isEmpty) continue;
        imageUrl = imageUrl.trim();
        if (readerConfig.containsKey('prefix')) {
          imageUrl = readerConfig['prefix'].toString() + imageUrl;
        }
        if (readerConfig.containsKey('postProcess')) {
          imageUrl = _applyImagePostProcess(imageUrl, readerConfig['postProcess']);
        }
        images.add(imageUrl);
      }
      return images;
    }

    if (readerMethod == 'regexVars') {
      final imagesPatternText = readerConfig['imagesPattern']?.toString();
      final pathPatternText = readerConfig['pathPattern']?.toString();
      if (imagesPatternText == null || imagesPatternText.isEmpty) return [];

      final imagesMatch = RegExp(imagesPatternText, dotAll: true).firstMatch(result.data!);
      if (imagesMatch == null) return [];

      final imagesGroupIndex = int.tryParse(readerConfig['imagesGroup']?.toString() ?? '') ?? 1;
      final imagesRaw = imagesMatch.group(imagesGroupIndex) ?? '';
      if (imagesRaw.trim().isEmpty) return [];

      String chapterPath = '';
      if (pathPatternText != null && pathPatternText.isNotEmpty) {
        final pathMatch = RegExp(pathPatternText, dotAll: true).firstMatch(result.data!);
        if (pathMatch != null) {
          final pathGroupIndex = int.tryParse(readerConfig['pathGroup']?.toString() ?? '') ?? 1;
          chapterPath = (pathMatch.group(pathGroupIndex) ?? '').trim();
        }
      }

      final prefix = readerConfig['prefix']?.toString() ?? '';
      final urls = <String>[];
      final parts = imagesRaw.split('\",\"');
      for (var p in parts) {
        var img = p;
        img = img.replaceAll('\\\\', '\\');
        img = img.replaceAll('\\"', '"');
        img = img.replaceAll('"', '');
        img = img.replaceAll('\\', '');
        img = img.trim();
        if (img.isEmpty) continue;
        var url = '$prefix$chapterPath$img';
        if (readerConfig.containsKey('postProcess')) {
          url = _applyImagePostProcess(url, readerConfig['postProcess']);
        }
        urls.add(url);
      }
      return urls;
    }

    if (readerMethod == 'script') {
      final scriptPattern = readerConfig['scriptPattern']?.toString() ?? 'window\\._gallery';
      final jsonPath = readerConfig['jsonPath']?.toString() ?? '';
      final urlTemplate = readerConfig['urlTemplate']?.toString();

      final objText = _extractScriptJsonObject(result.data!, scriptPattern);
      if (objText == null || objText.isEmpty) return [];

      final runtime = _ensureQjs();
      final js = '''
        (function(){
          var window = {};
          window._gallery = $objText;
          return JSON.stringify(window._gallery);
        })();
      ''';
      final jsonText = runtime.evaluate(js, name: '<manga_json_engine_script>');
      final jsonTextStr = jsonText?.toString();
      if (jsonTextStr == null || jsonTextStr.isEmpty) return [];

      dynamic data;
      try {
        data = jsonDecode(jsonTextStr);
      } catch (_) {
        return [];
      }

      final extracted = jsonPath.isEmpty ? data : _getByPath(data, jsonPath);
      if (extracted is! List) return [];

      final mediaId = (data is Map) ? (data['media_id'] ?? data['mediaId'])?.toString() : null;
      final images = <String>[];
      for (var i = 0; i < extracted.length; i++) {
        final item = extracted[i];
        if (urlTemplate == null || urlTemplate.isEmpty) {
          if (item is String) images.add(item);
          continue;
        }
        var url = urlTemplate;
        url = url.replaceAll('{media_id}', mediaId ?? '');
        url = url.replaceAll('{index}', '${i + 1}');
        String? ext;
        if (item is Map) {
          ext = _nhentaiExtFromType(item['t']);
        }
        url = url.replaceAll('{ext}', ext ?? 'jpg');
        if (readerConfig.containsKey('postProcess')) {
          url = _applyImagePostProcess(url, readerConfig['postProcess']);
        }
        images.add(url);
      }
      return images;
    }

    return [];
  }

  String _buildAbsoluteUrl(String base, String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    if (!path.startsWith('/')) {
      return base.endsWith('/') ? (base + path) : '$base/$path';
    }
    return base.endsWith('/') ? base.substring(0, base.length - 1) + path : base + path;
  }

  String _buildUrlFromTemplate(String template, {required String mangaId, String? chapterId}) {
    var url = template;
    url = url.replaceAll('{id}', mangaId);
    url = url.replaceAll('{mangaId}', mangaId);
    url = url.replaceAll('{comicId}', mangaId);
    url = url.replaceAll('{chapterId}', chapterId ?? mangaId);
    url = url.replaceAll('{epId}', chapterId ?? mangaId);
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    return _buildAbsoluteUrl(baseUrl, url);
  }

  FlutterQjs _ensureQjs() {
    final existing = _qjs;
    if (existing != null) return existing;
    final runtime = FlutterQjs();
    runtime.dispatch();
    _qjs = runtime;
    return runtime;
  }

  Future<NetworkResult<String>> _requestJsonApi({
    required String ruleKey,
    required String baseApiUrl,
    required String method,
    required String path,
    Map<String, String>? extraHeaders,
    dynamic body,
  }) async {
    await _auth.ensureInitialized();
    final token = _auth.getToken(ruleKey);

    Map<String, String> headers = {
      'User-Agent': userAgent,
      ...?extraHeaders,
    };

    if (_accountType == 'picacg') {
      final accountCfg = (rule['account'] as Map).cast<String, dynamic>();
      final bases = await _getPicacgApiBaseCandidates(accountCfg);
      NetworkResult<String>? last;
      for (final b in bases) {
        final headerPath = path.startsWith('/') ? path.substring(1) : path;
        final url = _buildPicacgRequestUrl(
          baseApiUrl: b,
          path: path,
          accountCfg: accountCfg,
        );
        final Map<String, String> h = <String, String>{
          ...headers,
          ..._buildPicacgHeaders(
            method: method,
            path: headerPath,
            token: token,
            accountCfg: accountCfg,
            baseApiUrlOverride: b,
          ),
        };

        last = await _networkService.requestText(
          url,
          method: method,
          headers: h,
          data: body,
        );

        if (last.isFailure && (_isLikelyNetworkUnreachable(last.error) || _isLikelyRetryableUpstreamError(last.error))) {
          Logger.warning('[PicACG] request retry on $b: ${last.error}');
          continue;
        }
        return last;
      }
      return last ?? NetworkResult.failure('PicACG request failed');
    }

    return _requestRuleApi(
      ruleKey: ruleKey,
      baseApiUrl: baseApiUrl,
      method: method,
      path: path,
      extraHeaders: headers,
      body: body,
    );
  }

  Future<NetworkResult<String>> _requestRuleApi({
    required String ruleKey,
    required String baseApiUrl,
    required String method,
    required String path,
    Map<String, String>? extraHeaders,
    dynamic body,
  }) async {
    final candidates = _getRuleApiBaseCandidates(baseApiUrl);
    NetworkResult<String>? last;
    for (final b in candidates) {
      final url = _buildAbsoluteUrl(b, path.startsWith('/') ? path : '/$path');

      final protocol = rule['protocol'];
      if (protocol is Map && protocol['type']?.toString() == 'jmEncryptedApi') {
        final accountCfg = (rule['account'] is Map) ? (rule['account'] as Map).cast<String, dynamic>() : <String, dynamic>{};
        final time = (DateTime.now().millisecondsSinceEpoch / 1000).floor();

        final pkgName = accountCfg['pkgName']?.toString().trim().isNotEmpty == true
            ? accountCfg['pkgName']?.toString().trim()
            : 'com.example.app';
        final jmVersion = accountCfg['jmVersion']?.toString().trim().isNotEmpty == true
            ? accountCfg['jmVersion']?.toString().trim()
            : '2.0.11';
        final authKey = accountCfg['authKey']?.toString().trim().isNotEmpty == true
            ? accountCfg['authKey']?.toString().trim()
            : '18comicAPPContent';

        final jmHeaders = <String, String>{
          'Accept': '*/*',
          'Accept-Encoding': 'gzip, deflate, br',
          'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
          'Connection': 'keep-alive',
          'Origin': 'https://localhost',
          'Referer': 'https://localhost/',
          'User-Agent': userAgent,
          'Authorization': 'Bearer',
          'X-Requested-With': pkgName ?? 'com.example.app',
          'tokenparam': '$time,$jmVersion',
          'token': _md5Hex('$time$authKey'),
        };

        if (extraHeaders != null) {
          jmHeaders.addAll(extraHeaders);
        }

        final res = await _networkService.requestText(
          url,
          method: method,
          headers: jmHeaders,
          data: body,
        );
        if (res.isFailure || res.data == null) {
          last = res;
          if (_shouldTryNextRuleApiBase(last.error)) {
            Logger.warning('[MangaJsonEngine] requestRuleApi retry on $b: ${last.error}');
            continue;
          }
          return res;
        }

        dynamic outer;
        try {
          outer = jsonDecode(res.data!);
        } catch (_) {
          last = NetworkResult.failure('JM outer jsonDecode failed');
          if (_shouldTryNextRuleApiBase(last.error)) {
            Logger.warning('[MangaJsonEngine] requestRuleApi retry on $b: ${last.error}');
            continue;
          }
          return last!;
        }

        final dataField = (protocol['response'] is Map && (protocol['response'] as Map)['outer'] is Map)
            ? ((protocol['response']['outer'] as Map)['dataField']?.toString() ?? 'data')
            : 'data';
        final encrypted = _getByPath(outer, dataField);
        if (encrypted is! String || encrypted.trim().isEmpty) {
          last = NetworkResult.failure('JM missing encrypted data field');
          if (_shouldTryNextRuleApiBase(last.error)) {
            Logger.warning('[MangaJsonEngine] requestRuleApi retry on $b: ${last.error}');
            continue;
          }
          return last!;
        }

        final secret = '$time${accountCfg['dataSecret']?.toString() ?? ''}';
        final decrypted = _jmAesEcbPkcs7DecryptBase64(encrypted, secret);
        if (decrypted == null || decrypted.trim().isEmpty) {
          last = NetworkResult.failure('JM decrypt empty');
          if (_shouldTryNextRuleApiBase(last.error)) {
            Logger.warning('[MangaJsonEngine] requestRuleApi retry on $b: ${last.error}');
            continue;
          }
          return last!;
        }

        final stripped = _stripToJson(decrypted);
        return NetworkResult.success(stripped);
      }

      final res = await _networkService.requestText(
        url,
        method: method,
        headers: extraHeaders,
        data: body,
      );
      if (res.isFailure) {
        last = res;
        if (_shouldTryNextRuleApiBase(last.error)) {
          Logger.warning('[MangaJsonEngine] requestRuleApi retry on $b: ${last.error}');
          continue;
        }
        return res;
      }
      return res;
    }

    return last ?? NetworkResult.failure('requestRuleApi failed');
  }

  String _md5Hex(String input) {
    final bytes = crypto.md5.convert(utf8.encode(input)).bytes;
    final buf = StringBuffer();
    for (final b in bytes) {
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  Uint8List _md5HexUtf8Bytes(String input) {
    final hex = _md5Hex(input);
    return Uint8List.fromList(utf8.encode(hex));
  }

  String? _jmAesEcbPkcs7DecryptBase64(String base64Text, String secret) {
    try {
      final key = _md5HexUtf8Bytes(secret);
      final data = base64Decode(base64Text);

      final cipher = PaddedBlockCipher('AES/ECB/PKCS7');
      cipher.init(false, PaddedBlockCipherParameters<KeyParameter, Null>(KeyParameter(key), null));
      final out = cipher.process(Uint8List.fromList(data));
      return utf8.decode(out, allowMalformed: true);
    } catch (e) {
      Logger.warning('[MangaJsonEngine] jm decrypt failed: $e');
      return null;
    }
  }

  String _stripToJson(String input) {
    var start = 0;
    while (start < input.length && input[start] != '{' && input[start] != '[') {
      start++;
    }
    var end = input.length - 1;
    while (end > start && input[end] != '}' && input[end] != ']') {
      end--;
    }
    return input.substring(start, end + 1);
  }

  bool _isLikelyNetworkUnreachable(String? err) {
    if (err == null) return false;
    final e = err.toLowerCase();
    return e.contains('socketexception') ||
        e.contains('connection error') ||
        e.contains('timed out') ||
        e.contains('errno = 121') ||
        e.contains('信号灯超时时间已到');
  }

  bool _isLikelyRetryableUpstreamError(String? err) {
    if (err == null) return false;
    final e = err.toLowerCase();
    return e.contains('http 520') ||
        e.contains('http 521') ||
        e.contains('http 522') ||
        e.contains('http 523') ||
        e.contains('http 524') ||
        e.contains('http 502') ||
        e.contains('http 503') ||
        e.contains('http 504') ||
        e.contains('status code 520') ||
        e.contains('status code 521') ||
        e.contains('status code 522') ||
        e.contains('status code 523') ||
        e.contains('status code 524') ||
        e.contains('status code 502') ||
        e.contains('status code 503') ||
        e.contains('status code 504') ||
        e.contains('cloudflare');
  }

  bool _shouldTryNextRuleApiBase(String? err) {
    if (err == null) return false;
    final e = err.toLowerCase();
    return _isLikelyNetworkUnreachable(err) ||
        _isLikelyRetryableUpstreamError(err) ||
        e.contains('http 403') ||
        e.contains('http 404') ||
        e.contains('status code 403') ||
        e.contains('status code 404');
  }

  List<String> _getRuleApiBaseCandidates(String baseApiUrl) {
    final out = <String>[];
    void add(String v) {
      final s = v.trim();
      if (s.isEmpty) return;
      if (!out.contains(s)) out.add(s);
    }

    add(baseApiUrl);

    // Prefer refreshed domains first when available.
    for (final d in availableDomains) {
      final host = d.trim();
      if (host.isEmpty) continue;
      add('https://$host');
    }

    final account = rule['account'];
    if (account is Map) {
      final servers = account['fallbackServers'];
      if (servers is List) {
        for (final s in servers) {
          final host = s.toString().trim();
          if (host.isEmpty) continue;
          add('https://$host');
        }
      }
    }

    return out;
  }

  dynamic _getByPath(dynamic data, String path) {
    if (data == null) return null;
    if (path.trim().isEmpty) return data;
    dynamic cur = data;
    for (final part in path.split('.')) {
      if (cur == null) return null;
      final key = part.trim();
      if (key.isEmpty) continue;

      final idx = int.tryParse(key);
      if (idx != null) {
        if (cur is List && idx >= 0 && idx < cur.length) {
          cur = cur[idx];
          continue;
        }
        return null;
      }

      if (cur is Map) {
        if (cur.containsKey(key)) {
          cur = cur[key];
          continue;
        }
        dynamic found;
        for (final entry in cur.entries) {
          if (entry.key.toString() == key) {
            found = entry.value;
            break;
          }
        }
        cur = found;
        continue;
      }
      return null;
    }
    return cur;
  }

  List<MangaItem> _parseJsonSearchResults(dynamic data, Map<String, dynamic> searchConfig) {
    final listPath = searchConfig['resultPath']?.toString() ?? '';
    if (listPath.isEmpty) return [];
    final raw = _getByPath(data, listPath);
    if (raw is! List) return [];

    final mapping = (searchConfig['itemMapping'] is Map)
        ? (searchConfig['itemMapping'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final idPath = mapping['idPath']?.toString() ?? '_id';
    final titlePath = mapping['titlePath']?.toString() ?? 'title';
    final subtitlePath = mapping['subtitlePath']?.toString();
    final fileServerPath = mapping['fileServerPath']?.toString() ?? 'thumb.fileServer';
    final pathPath = mapping['pathPath']?.toString() ?? 'thumb.path';
    final coverTemplate = mapping['coverTemplate']?.toString() ?? '{fileServer}/static/{path}';

    final descPath = mapping['descriptionPath']?.toString();

    final out = <MangaItem>[];
    for (final it in raw) {
      final id = _getByPath(it, idPath)?.toString().trim();
      final title = _getByPath(it, titlePath)?.toString().trim();
      if (id == null || id.isEmpty || title == null || title.isEmpty) continue;
      final fs = _getByPath(it, fileServerPath)?.toString() ?? '';
      final p = _getByPath(it, pathPath)?.toString() ?? '';
      var cover = coverTemplate.replaceAll('{fileServer}', fs).replaceAll('{path}', p);
      cover = cover.replaceAll('{id}', id);
      cover = cover.replaceAll('{imageHost}', _getImageHost());

      out.add(MangaItem(
        id: id,
        title: title,
        subtitle: subtitlePath != null ? _getByPath(it, subtitlePath)?.toString() : null,
        cover: cover,
        description: descPath != null ? _getByPath(it, descPath)?.toString() : null,
        ruleName: name,
        ruleKey: rule['name']?.toString() ?? 'unknown',
      ));
    }
    return out;
  }

  List<String> _normalizeAttrList(dynamic attrConfig, {String defaultAttr = 'text'}) {
    if (attrConfig == null) return [defaultAttr];
    if (attrConfig is List) {
      return attrConfig.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    final raw = attrConfig.toString();
    if (raw.contains(',')) {
      return raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    return [raw.trim().isEmpty ? defaultAttr : raw.trim()];
  }

  String? _extractElementValue(dom.Element? element, List<String> attrs) {
    if (element == null) return null;
    for (final a in attrs) {
      final key = a.trim();
      if (key.isEmpty) continue;
      if (key == 'text') {
        final t = element.text;
        if (t.trim().isNotEmpty) return t;
      } else if (key == 'html') {
        final h = element.innerHtml;
        if (h.trim().isNotEmpty) return h;
      } else {
        final v = element.attributes[key];
        if (v != null && v.trim().isNotEmpty) return v;
      }
    }
    return null;
  }

  String _buildIdFromRegexMatch(RegExpMatch match, String template) {
    var out = template;
    out = out.replaceAll('{0}', match.group(0) ?? '');
    for (var i = 1; i <= match.groupCount; i++) {
      out = out.replaceAll('{$i}', match.group(i) ?? '');
    }
    return out;
  }

  String _applyImagePostProcess(String url, dynamic cfg) {
    if (cfg == null) return url;
    if (cfg is String) {
      final t = cfg.trim();
      if (t.isEmpty) return url;
      if (t == 'fixDoubleSlash') {
        return url.replaceAll(':///', '://');
      }
      if (t == 'removeLastChar') {
        if (url.isEmpty) return url;
        return url.substring(0, url.length - 1);
      }
      return url;
    }

    if (cfg is List) {
      var out = url;
      for (final it in cfg) {
        out = _applyImagePostProcess(out, it);
      }
      return out;
    }
    if (cfg is Map) {
      final type = cfg['type']?.toString();
      if (type == 'replace') {
        final from = cfg['from']?.toString() ?? '';
        final to = cfg['to']?.toString() ?? '';
        if (from.isNotEmpty) return url.replaceAll(from, to);
      }
      if (type == 'replaceDomain') {
        final to = cfg['to']?.toString() ?? '';
        final target = to.trim();
        if (target.isEmpty) return url;
        try {
          final uri = Uri.parse(url);
          if (!uri.hasAuthority) return url;
          final targetUri = Uri.parse(target.contains('://') ? target : 'https://$target');
          return uri.replace(scheme: targetUri.scheme, host: targetUri.host).toString();
        } catch (_) {
          return url;
        }
      }
    }
    return url;
  }

  String? _extractScriptJsonObject(String html, String scriptPattern) {
    final patterns = <RegExp>[
      RegExp('$scriptPattern\\s*=\\s*({[\\s\\S]*?})\\s*;', multiLine: true),
      RegExp('$scriptPattern\\s*=\\s*(\\[[\\s\\S]*?\\])\\s*;', multiLine: true),
    ];
    for (final r in patterns) {
      final m = r.firstMatch(html);
      if (m != null) {
        final g = m.group(1);
        if (g != null && g.trim().isNotEmpty) return g.trim();
      }
    }
    return null;
  }

  String _nhentaiExtFromType(dynamic t) {
    final v = t?.toString();
    if (v == 'p') return 'png';
    if (v == 'g') return 'gif';
    if (v == 'w') return 'webp';
    return 'jpg';
  }

  List<MangaItem> _parseSearchResults(String html, Map<String, dynamic> searchConfig) {
    final resultListSelector = searchConfig['resultList']?.toString();
    if (resultListSelector == null || resultListSelector.isEmpty) return [];
    final doc = html_parser.parse(html);
    final nodes = doc.querySelectorAll(resultListSelector);
    final itemSelectors = (searchConfig['itemSelectors'] is Map)
        ? (searchConfig['itemSelectors'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    String? readField(dom.Element node, dynamic cfg, {String defaultAttr = 'text'}) {
      if (cfg is String) {
        final el = node.querySelector(cfg);
        return el?.text.trim();
      }
      if (cfg is Map) {
        final selector = cfg['selector']?.toString();
        final attrs = _normalizeAttrList(cfg['attr'], defaultAttr: defaultAttr);
        final el = (selector != null && selector.isNotEmpty) ? node.querySelector(selector) : node;
        var raw = _extractElementValue(el, attrs);
        if (raw == null || raw.trim().isEmpty) return null;
        raw = raw.trim();
        final regexText = cfg['regex']?.toString();
        if (regexText != null && regexText.isNotEmpty) {
          final m = RegExp(regexText).firstMatch(raw);
          if (m != null) {
            final template = cfg['template']?.toString();
            if (template != null && template.isNotEmpty) {
              raw = _buildIdFromRegexMatch(m, template);
            } else if (m.groupCount >= 1) {
              raw = m.group(1) ?? raw;
            } else {
              raw = m.group(0) ?? raw;
            }
          }
        }
        final prefix = cfg['prefix']?.toString();
        if (prefix != null && prefix.isNotEmpty) raw = prefix + raw;
        final suffix = cfg['suffix']?.toString();
        if (suffix != null && suffix.isNotEmpty) raw = raw + suffix;
        return raw;
      }
      return null;
    }

    final out = <MangaItem>[];
    for (final node in nodes) {
      final id = readField(node, itemSelectors['id'], defaultAttr: 'href');
      final title = readField(node, itemSelectors['title'], defaultAttr: 'text');
      final cover = readField(node, itemSelectors['cover'], defaultAttr: 'src');
      if (id == null || id.isEmpty || title == null || title.isEmpty) continue;

      out.add(MangaItem(
        id: id,
        title: title,
        cover: cover,
        ruleName: name,
        ruleKey: rule['name']?.toString() ?? 'unknown',
      ));
    }
    return out;
  }

  String _template(String template, Map<String, String> vars) {
    var out = template;
    for (final e in vars.entries) {
      out = out.replaceAll('{${e.key}}', e.value);
    }
    return out;
  }

  dynamic _tryJsonDecode(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _loginPicacg(String username, String password) async {
    final accountCfg = (rule['account'] as Map).cast<String, dynamic>();
    final loginPath = accountCfg['loginPath']?.toString() ?? 'auth/sign-in';
    final body = jsonEncode({'email': username, 'password': password});

    final bases = await _getPicacgApiBaseCandidates(accountCfg);
    NetworkResult<String>? res;
    for (final baseApiUrl in bases) {
      final loginUrl = _buildPicacgRequestUrl(
        baseApiUrl: baseApiUrl,
        path: loginPath,
        accountCfg: accountCfg,
      );
      final headers = _buildPicacgHeaders(
        method: 'POST',
        path: loginPath,
        token: null,
        accountCfg: accountCfg,
        baseApiUrlOverride: baseApiUrl,
      );

      res = await _networkService.requestText(
        loginUrl,
        method: 'POST',
        headers: headers,
        data: body,
      );

      if (res.isFailure && (_isLikelyNetworkUnreachable(res.error) || _isLikelyRetryableUpstreamError(res.error))) {
        continue;
      }
      break;
    }

    if (res == null || res.isFailure || res.data == null) {
      Logger.warning('[PicACG] login failed: ${res?.error}');
      return false;
    }

    final decoded = _tryJsonDecode(res.data!);
    final token = _getByPath(decoded, 'data.token')?.toString();
    if (token == null || token.trim().isEmpty) return false;

    final key = rule['name']?.toString() ?? 'unknown';
    await _auth.ensureInitialized();
    await _auth.setAccount(key, username, password);
    await _auth.setToken(key, token.trim());
    return true;
  }

  Future<List<String>> _getPicacgApiBaseCandidates(
    Map<String, dynamic> accountCfg, {
    String? preferred,
  }) async {
    final base = preferred ?? accountCfg['baseApiUrl']?.toString() ?? baseUrl;
    final out = <String>[];

    void addBase(dynamic v) {
      if (v == null) return;
      final s = v.toString().trim();
      if (s.isEmpty) return;
      final normalized = s.endsWith('/') ? s.substring(0, s.length - 1) : s;
      if (!out.contains(normalized)) out.add(normalized);
    }

    final cands = accountCfg['apiBaseCandidates'];
    if (cands is List) {
      for (final it in cands) {
        addBase(it);
      }
    }
    addBase(base);
    return out;
  }

  String _buildPicacgRequestUrl({
    required String baseApiUrl,
    required String path,
    required Map<String, dynamic> accountCfg,
  }) {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;

    final proxyDomains = <String>{};
    final pd = accountCfg['proxyDomains'];
    if (pd is List) {
      for (final it in pd) {
        final s = it?.toString().trim();
        if (s != null && s.isNotEmpty) proxyDomains.add(s);
      }
    }

    try {
      final u = Uri.parse(baseApiUrl);
      final host = u.host;
      final originHost = accountCfg['proxyOriginHost']?.toString().trim();
      if (originHost != null && originHost.isNotEmpty && proxyDomains.contains(host)) {
        return _buildAbsoluteUrl(baseApiUrl, '/$originHost/$normalizedPath');
      }
    } catch (_) {
      // ignore
    }

    return _buildAbsoluteUrl(baseApiUrl, '/$normalizedPath');
  }

  Map<String, String> _buildPicacgHeaders({
    required String method,
    required String path,
    required String? token,
    required Map<String, dynamic> accountCfg,
    String? baseApiUrlOverride,
  }) {
    final apiKey = accountCfg['apiKey']?.toString() ?? '';
    final hmacKey = accountCfg['hmacKey']?.toString() ?? '';
    final appChannel = accountCfg['appChannel']?.toString() ?? '2';
    final imageQuality = accountCfg['imageQuality']?.toString() ?? 'original';
    final appVersion = accountCfg['appVersion']?.toString() ?? '2.2.1.3.3.4';
    final appPlatform = accountCfg['appPlatform']?.toString() ?? 'android';
    final appBuildVersion = accountCfg['appBuildVersion']?.toString() ?? '45';
    final accept = accountCfg['accept']?.toString() ?? 'application/vnd.picacomic.com.v1+json';

    final uuid = const Uuid().v4();
    final nonce = uuid.replaceAll('-', '');
    final time = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();

    final data = (path + time + nonce + method.toUpperCase() + apiKey).toLowerCase();
    final sigBytes = crypto.Hmac(crypto.sha256, utf8.encode(hmacKey)).convert(utf8.encode(data)).bytes;
    final signature = _bytesToHex(sigBytes);

    final baseApiUrl = baseApiUrlOverride ?? accountCfg['baseApiUrl']?.toString() ?? baseUrl;
    var host = Uri.parse(baseApiUrl).host;

    try {
      final originHost = accountCfg['proxyOriginHost']?.toString().trim();
      final proxyDomains = <String>{};
      final pd = accountCfg['proxyDomains'];
      if (pd is List) {
        for (final it in pd) {
          final s = it?.toString().trim();
          if (s != null && s.isNotEmpty) proxyDomains.add(s);
        }
      }
      if (originHost != null && originHost.isNotEmpty && proxyDomains.contains(host)) {
        host = originHost;
      }
    } catch (_) {
      // ignore
    }

    return {
      'api-key': apiKey,
      'accept': accept,
      'app-channel': appChannel,
      'authorization': token ?? '',
      'time': time,
      'nonce': nonce,
      'app-version': appVersion,
      'app-uuid': 'defaultUuid',
      'image-quality': imageQuality,
      'app-platform': appPlatform,
      'app-build-version': appBuildVersion,
      'Content-Type': 'application/json; charset=UTF-8',
      'user-agent': accountCfg['userAgent']?.toString() ?? 'okhttp/3.8.1',
      'version': accountCfg['apiVersion']?.toString() ?? 'v1.4.1',
      'Host': host,
      'signature': signature,
    };
  }

  String _bytesToHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}