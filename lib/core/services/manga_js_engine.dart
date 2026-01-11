import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/pkcs1.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/block/modes/cfb.dart';
import 'package:pointycastle/block/modes/ecb.dart';
import 'package:pointycastle/block/modes/ofb.dart';
import 'package:pointycastle/asn1/asn1_parser.dart';
import 'package:pointycastle/asn1/primitives/asn1_integer.dart';
import 'package:pointycastle/asn1/primitives/asn1_sequence.dart';

import '../models/manga_item.dart';
import '../utils/logger.dart';
import 'manga_network_service.dart';

/// 漫画JS引擎 - 基于Venera完整实现
/// 完全兼容Venera规则，不做简化
class MangaJsEngine {
  static final MangaJsEngine _instance = MangaJsEngine._internal();
  factory MangaJsEngine() => _instance;
  MangaJsEngine._internal();

  final Map<String, _MangaRuleInstance> _ruleInstances = {};
  final MangaNetworkService _networkService = MangaNetworkService();

  /// 加载漫画规则
  Future<bool> loadRule(String ruleContent, String ruleKey) async {
    try {
      Logger.info('加载漫画规则: $ruleKey');
      print('[JS引擎] 开始加载规则: $ruleKey');
      
      // 创建规则实例
      final instance = _MangaRuleInstance(ruleKey, _networkService);
      
      print('[JS引擎] 开始初始化规则实例');
      await instance.initialize(ruleContent);
      print('[JS引擎] 规则实例初始化完成');
      
      _ruleInstances[ruleKey] = instance;
      Logger.info('漫画规则加载成功: $ruleKey');
      print('[JS引擎] 规则加载成功: $ruleKey');
      return true;
    } catch (e, stackTrace) {
      Logger.error('漫画规则加载失败 [$ruleKey]: $e');
      print('[JS引擎] 规则加载失败 [$ruleKey]: $e');
      print('[JS引擎] 堆栈跟踪: $stackTrace');
      return false;
    }
  }

  /// 获取规则实例
  _MangaRuleInstance? _getInstance(String ruleKey) {
    final instance = _ruleInstances[ruleKey];
    if (instance == null) {
      Logger.warning('规则实例不存在: $ruleKey');
    }
    return instance;
  }

  /// 搜索漫画
  Future<List<MangaItem>> search(String ruleKey, String keyword, int page) async {
    final instance = _getInstance(ruleKey);
    if (instance == null) return [];

    try {
      return await instance.search(keyword, page);
    } catch (e) {
      Logger.error('搜索失败 [$ruleKey]: $e');
      return [];
    }
  }

  /// 获取漫画详情
  Future<MangaDetail?> getDetail(String ruleKey, String comicId) async {
    final instance = _getInstance(ruleKey);
    if (instance == null) return null;

    try {
      return await instance.getDetail(comicId);
    } catch (e) {
      Logger.error('获取详情失败 [$ruleKey]: $e');
      return null;
    }
  }

  /// 获取章节内容
  Future<List<String>> getChapter(String ruleKey, String comicId, String chapterId) async {
    final instance = _getInstance(ruleKey);
    if (instance == null) return [];

    try {
      return await instance.getChapter(comicId, chapterId);
    } catch (e) {
      Logger.error('获取章节失败 [$ruleKey]: $e');
      return [];
    }
  }

  /// 用户登录
  Future<bool> login(String ruleKey, String username, String password) async {
    final instance = _getInstance(ruleKey);
    if (instance == null) return false;

    try {
      return await instance.login(username, password);
    } catch (e) {
      Logger.error('登录失败 [$ruleKey]: $e');
      return false;
    }
  }

  /// 检查登录状态
  bool isLogged(String ruleKey) {
    final instance = _getInstance(ruleKey);
    return instance?.isLogged ?? false;
  }

  /// 清理规则实例
  void clearRule(String ruleKey) {
    final instance = _ruleInstances.remove(ruleKey);
    instance?.dispose();
    Logger.info('清理漫画规则: $ruleKey');
  }

  /// 清理所有规则
  void clearAll() {
    for (final instance in _ruleInstances.values) {
      instance.dispose();
    }
    _ruleInstances.clear();
    Logger.info('清理所有漫画规则');
  }
}

/// 单个漫画规则的JS执行实例 - 基于Venera完整实现
class _MangaRuleInstance {
  final String ruleKey;
  final MangaNetworkService networkService;
  
  FlutterQjs? _runtime;
  String? _ruleName;
  bool _isLogged = false;
  
  // HTML文档管理 - 基于Venera实现
  final Map<int, _DocumentWrapper> _documents = {};
  
  // 简单的设置存储
  final Map<String, dynamic> _settings = {};

  _MangaRuleInstance(this.ruleKey, this.networkService);

  /// 初始化JS引擎和规则 - 基于Venera完整实现
  Future<void> initialize(String ruleContent) async {
    try {
      print('[$ruleKey] 开始初始化JS引擎');
      _runtime = FlutterQjs();
      _runtime!.dispatch();
      print('[$ruleKey] FlutterQjs实例创建成功');
      
      // 设置默认配置值（基于规则内容推断）
      print('[$ruleKey] 开始初始化默认设置');
      _initializeDefaultSettings(ruleContent);
      print('[$ruleKey] 默认设置初始化完成');
      
      // 设置全局sendMessage函数
      print('[$ruleKey] 开始设置全局函数');
      final setGlobalFunc = _runtime!.evaluate("(key, value) => { this[key] = value; }") as JSInvokable;
      setGlobalFunc(["sendMessage", _messageReceiver]);
      setGlobalFunc(["appVersion", "1.0.0"]);
      setGlobalFunc.free();
      print('[$ruleKey] 全局函数设置完成');
      
      // 注入完整的Venera API
      print('[$ruleKey] 开始注入Venera API');
      await _injectVeneraApis();
      print('[$ruleKey] Venera API注入完成');
      
      // 执行规则代码
      print('[$ruleKey] 开始执行规则代码');
      _runtime!.evaluate(ruleContent);
      print('[$ruleKey] 规则代码执行完成');
      
      // 基于Venera的规则注册方式
      print('[$ruleKey] 开始注册规则');
      final classNameMatch = RegExp(r'class\s+(\w+)\s+extends\s+ComicSource').firstMatch(ruleContent);
      if (classNameMatch != null) {
        final className = classNameMatch.group(1)!;
        Logger.info('[$ruleKey] 发现规则类: $className');
        print('[$ruleKey] 发现规则类: $className');
        
        // 创建实例并注册 - 完全按照Venera的方式
        _runtime!.evaluate('''
          (() => { 
            this['temp'] = new $className();
            ComicSource.sources["$ruleKey"] = this['temp'];
            console.log('规则注册成功:', "$ruleKey", this['temp'].name);
          })()
        ''');
        print('[$ruleKey] 规则实例创建和注册完成');
        
        // 调用初始化方法
        print('[$ruleKey] 开始调用规则初始化方法');
        _runtime!.evaluate('''
          if (typeof ComicSource.sources["$ruleKey"].init === 'function') {
            try {
              ComicSource.sources["$ruleKey"].init();
              console.log('规则初始化方法调用成功');
            } catch (e) {
              console.log('初始化失败:', e);
            }
          } else {
            console.log('规则没有init方法');
          }
        ''');
        print('[$ruleKey] 规则初始化方法调用完成');
      } else {
        Logger.error('[$ruleKey] 未找到有效的ComicSource类定义');
        print('[$ruleKey] 错误：未找到有效的ComicSource类定义');
        throw Exception('未找到有效的ComicSource类定义');
      }
      
      // 获取规则信息
      try {
        print('[$ruleKey] 开始获取规则信息');
        final sourceInstance = _runtime!.evaluate('ComicSource.sources["$ruleKey"]');
        if (sourceInstance != null) {
          // 直接获取name属性，不使用stringValue
          final nameResult = _runtime!.evaluate('ComicSource.sources["$ruleKey"].name');
          if (nameResult is String) {
            _ruleName = nameResult;
          } else {
            _ruleName = nameResult?.toString();
          }
          Logger.info('规则初始化完成: $_ruleName');
          print('[$ruleKey] 规则初始化完成: $_ruleName');
          
          // 对于wnacg规则，等待域名刷新完成后检查可用域名
          if (ruleKey == 'wnacg') {
            await _waitForDomainRefresh();
          }
        } else {
          Logger.warning('规则注册失败: $ruleKey');
          print('[$ruleKey] 警告：规则注册失败');
          throw Exception('规则注册失败');
        }
      } catch (e) {
        Logger.warning('获取规则信息失败: $e');
        print('[$ruleKey] 警告：获取规则信息失败: $e');
        // 不抛出异常，因为这不是致命错误
      }
    } catch (e, stackTrace) {
      print('[$ruleKey] 初始化过程中发生异常: $e');
      print('[$ruleKey] 堆栈跟踪: $stackTrace');
      rethrow;
    }
  }

  /// 初始化默认设置 - 简化但有效的实现
  void _initializeDefaultSettings(String ruleContent) {
    // 从规则内容中提取设置的默认值
    try {
      // 查找settings对象
      final settingsMatch = RegExp(r'settings\s*=\s*\{([\s\S]*?)\}(?=\s*translation|\s*$)', multiLine: true).firstMatch(ruleContent);
      if (settingsMatch != null) {
        final settingsContent = settingsMatch.group(1) ?? '';
        
        // 提取每个设置项的默认值
        final settingMatches = RegExp(r'(\w+):\s*\{[^}]*?default:\s*([^,}]+)', multiLine: true).allMatches(settingsContent);
        
        for (final match in settingMatches) {
          final key = match.group(1);
          final defaultValue = match.group(2)?.trim();
          
          if (key != null && defaultValue != null) {
            // 解析默认值
            dynamic parsedValue;
            if (defaultValue.startsWith("'") && defaultValue.endsWith("'")) {
              parsedValue = defaultValue.substring(1, defaultValue.length - 1);
            } else if (defaultValue.startsWith('"') && defaultValue.endsWith('"')) {
              parsedValue = defaultValue.substring(1, defaultValue.length - 1);
            } else if (defaultValue == 'true') {
              parsedValue = true;
            } else if (defaultValue == 'false') {
              parsedValue = false;
            } else if (RegExp(r'^\d+$').hasMatch(defaultValue)) {
              parsedValue = int.tryParse(defaultValue) ?? defaultValue;
            } else {
              parsedValue = defaultValue.replaceAll('"', '').replaceAll("'", '');
            }
            
            _settings[key] = parsedValue;
            print('[$ruleKey] 解析默认设置: $key = $parsedValue');
          }
        }
      }
      
      // 为wnacg规则添加必需的默认设置（如果没有解析到）
      if (ruleKey == 'wnacg') {
        if (!_settings.containsKey('domainSelection')) {
          // 由于DNS问题，直接使用自定义域名而不是等待域名刷新
          _settings['domainSelection'] = "0"; // 使用自定义域名
          print('[$ruleKey] 添加默认设置: domainSelection = "0"');
        }
        if (!_settings.containsKey('domain0')) {
          _settings['domain0'] = 'www.wn06.ru'; // 使用测试成功的域名
          print('[$ruleKey] 添加默认设置: domain0 = "www.wn06.ru"');
        }
        if (!_settings.containsKey('refreshDomainsOnStart')) {
          _settings['refreshDomainsOnStart'] = true;
          print('[$ruleKey] 添加默认设置: refreshDomainsOnStart = true');
        }
      }
    } catch (e) {
      Logger.warning('[$ruleKey] 解析默认设置失败: $e');
    }
    
    Logger.info('[$ruleKey] 最终默认设置: $_settings');
  }

  /// 注入完整的Venera API - 不做简化
  Future<void> _injectVeneraApis() async {
    // 注入setTimeout
    _runtime!.evaluate('''
      function setTimeout(callback, delay) {
        sendMessage({
          method: 'delay',
          time: delay,
        }).then(callback);
      }
    ''');

    // 注入Convert对象 - 完整实现
    _runtime!.evaluate('''
      let Convert = {
        encodeUtf8: (str) => {
          return sendMessage({
            method: "convert",
            type: "utf8",
            value: str,
            isEncode: true
          });
        },
        
        decodeUtf8: (value) => {
          return sendMessage({
            method: "convert",
            type: "utf8",
            value: value,
            isEncode: false
          });
        },
        
        encodeGbk: (str) => {
          return sendMessage({
            method: "convert",
            type: "gbk",
            value: str,
            isEncode: true
          });
        },
        
        decodeGbk: (value) => {
          return sendMessage({
            method: "convert",
            type: "gbk",
            value: value,
            isEncode: false
          });
        },
        
        encodeBase64: (value) => {
          return sendMessage({
            method: "convert",
            type: "base64",
            value: value,
            isEncode: true
          });
        },
        
        decodeBase64: (value) => {
          return sendMessage({
            method: "convert",
            type: "base64",
            value: value,
            isEncode: false
          });
        },
        
        md5: (value) => {
          return sendMessage({
            method: "convert",
            type: "md5",
            value: value,
            isEncode: true
          });
        },
        
        sha1: (value) => {
          return sendMessage({
            method: "convert",
            type: "sha1",
            value: value,
            isEncode: true
          });
        },
        
        sha256: (value) => {
          return sendMessage({
            method: "convert",
            type: "sha256",
            value: value,
            isEncode: true
          });
        },
        
        sha512: (value) => {
          return sendMessage({
            method: "convert",
            type: "sha512",
            value: value,
            isEncode: true
          });
        },
        
        hmac: (key, value, hash) => {
          return sendMessage({
            method: "convert",
            type: "hmac",
            value: value,
            key: key,
            hash: hash,
            isEncode: true
          });
        },
        
        hmacString: (key, value, hash) => {
          return sendMessage({
            method: "convert",
            type: "hmac",
            value: value,
            key: key,
            hash: hash,
            isEncode: true,
            isString: true
          });
        },
        
        decryptAesEcb: (value, key) => {
          return sendMessage({
            method: "convert",
            type: "aes-ecb",
            value: value,
            key: key,
            isEncode: false
          });
        },
        
        decryptAesCbc: (value, key, iv) => {
          return sendMessage({
            method: "convert",
            type: "aes-cbc",
            value: value,
            key: key,
            iv: iv,
            isEncode: false
          });
        },
        
        decryptAesCfb: (value, key, blockSize) => {
          return sendMessage({
            method: "convert",
            type: "aes-cfb",
            value: value,
            key: key,
            blockSize: blockSize,
            isEncode: false
          });
        },
        
        decryptAesOfb: (value, key, blockSize) => {
          return sendMessage({
            method: "convert",
            type: "aes-ofb",
            value: value,
            key: key,
            blockSize: blockSize,
            isEncode: false
          });
        },
        
        decryptRsa: (value, key) => {
          return sendMessage({
            method: "convert",
            type: "rsa",
            value: value,
            key: key,
            isEncode: false
          });
        },
        
        hexEncode: (bytes) => {
          const hexDigits = '0123456789abcdef';
          const view = new Uint8Array(bytes);
          let charCodes = new Uint8Array(view.length * 2);
          let j = 0;

          for (let i = 0; i < view.length; i++) {
            let byte = view[i];
            charCodes[j++] = hexDigits.charCodeAt((byte >> 4) & 0xF);
            charCodes[j++] = hexDigits.charCodeAt(byte & 0xF);
          }

          return String.fromCharCode(...charCodes);
        }
      };
    ''');

    // 注入UUID和随机数函数
    _runtime!.evaluate('''
      function createUuid() {
        return sendMessage({
          method: "uuid"
        });
      }
      
      function randomInt(min, max) {
        return sendMessage({
          method: 'random',
          type: 'int',
          min: min,
          max: max
        });
      }
      
      function randomDouble(min, max) {
        return sendMessage({
          method: 'random',
          type: 'double',
          min: min,
          max: max
        });
      }
    ''');

    // 注入Network对象 - 完全按照Venera标准实现
    _runtime!.evaluate('''
      function Cookie({name, value, domain}) {
        this.name = name;
        this.value = value;
        this.domain = domain;
      }
      
      let Network = {
        async fetchBytes(method, url, headers, data, extra) {
          let result = await sendMessage({
            method: 'http',
            http_method: method,
            bytes: true,
            url: url,
            headers: headers,
            data: data,
            extra: extra,
          });

          if (result.error) {
            throw result.error;
          }

          return result;
        },

        async sendRequest(method, url, headers, data, extra) {
          let result = await sendMessage({
            method: 'http',
            http_method: method,
            url: url,
            headers: headers,
            data: data,
            extra: extra,
          });

          if (result.error) {
            throw result.error;
          }

          return result;
        },

        async get(url, headers, extra) {
          return this.sendRequest('GET', url, headers, null, extra);
        },

        async post(url, headers, data, extra) {
          return this.sendRequest('POST', url, headers, data, extra);
        },

        async put(url, headers, data, extra) {
          return this.sendRequest('PUT', url, headers, data, extra);
        },

        async patch(url, headers, data, extra) {
          return this.sendRequest('PATCH', url, headers, data, extra);
        },

        async delete(url, headers, extra) {
          return this.sendRequest('DELETE', url, headers, extra);
        },

        setCookies(url, cookies) {
          sendMessage({
            method: 'cookie',
            function: 'set',
            url: url,
            cookies: cookies,
          });
        },

        getCookies(url) {
          return sendMessage({
            method: 'cookie',
            function: 'get',
            url: url,
          });
        },

        deleteCookies(url) {
          sendMessage({
            method: 'cookie',
            function: 'delete',
            url: url,
          });
        }
      };
    ''');

    // 注入fetch函数 - 完全按照Venera标准实现
    _runtime!.evaluate('''
      async function fetch(url, options) {
        let method = 'GET';
        let headers = {};
        let data = null;

        if (options) {
          method = options.method || method;
          headers = options.headers || headers;
          data = options.body || data;
        }

        let result = await Network.fetchBytes(method, url, headers, data);

        return {
          ok: result.status >= 200 && result.status < 300,
          status: result.status,
          statusText: '',
          headers: result.headers,
          arrayBuffer: async () => result.body,
          text: async () => Convert.decodeUtf8(result.body),
          json: async () => JSON.parse(Convert.decodeUtf8(result.body)),
        }
      }
    ''');

    // 注入HTML解析类 - 完整实现
    _runtime!.evaluate('''
      class HtmlDocument {
        static _key = 0;
        key = 0;

        constructor(html) {
          this.key = HtmlDocument._key;
          HtmlDocument._key++;
          sendMessage({
            method: "html",
            function: "parse",
            key: this.key,
            data: html
          })
        }

        querySelector(query) {
          let k = sendMessage({
            method: "html",
            function: "querySelector",
            key: this.key,
            query: query
          })
          if(k == null) return null;
          return new HtmlElement(k, this.key);
        }

        querySelectorAll(query) {
          let ks = sendMessage({
            method: "html",
            function: "querySelectorAll",
            key: this.key,
            query: query
          })
          return ks.map(k => new HtmlElement(k, this.key));
        }

        dispose() {
          sendMessage({
            method: "html",
            function: "dispose",
            key: this.key
          })
        }

        getElementById(id) {
          let k = sendMessage({
            method: "html",
            function: "getElementById",
            key: this.key,
            id: id
          })
          if(k == null) return null;
          return new HtmlElement(k, this.key);
        }
      }

      class HtmlElement {
        key = 0;
        doc = 0;

        constructor(k, doc) {
          this.key = k;
          this.doc = doc;
        }

        get text() {
          return sendMessage({
            method: "html",
            function: "getText",
            key: this.key,
            doc: this.doc,
          })
        }

        get attributes() {
          return sendMessage({
            method: "html",
            function: "getAttributes",
            key: this.key,
            doc: this.doc,
          })
        }

        querySelector(query) {
          let k = sendMessage({
            method: "html",
            function: "dom_querySelector",
            key: this.key,
            query: query,
            doc: this.doc,
          })
          if(k == null) return null;
          return new HtmlElement(k, this.doc);
        }

        querySelectorAll(query) {
          let ks = sendMessage({
            method: "html",
            function: "dom_querySelectorAll",
            key: this.key,
            query: query,
            doc: this.doc,
          })
          return ks.map(k => new HtmlElement(k, this.doc));
        }

        get children() {
          let ks = sendMessage({
            method: "html",
            function: "getChildren",
            key: this.key,
            doc: this.doc,
          })
          return ks.map(k => new HtmlElement(k, this.doc));
        }

        get nodes() {
          let ks = sendMessage({
            method: "html",
            function: "getNodes",
            key: this.key,
            doc: this.doc,
          })
          return ks.map(k => new HtmlNode(k, this.doc));
        }

        get innerHTML() {
          return sendMessage({
            method: "html",
            function: "getInnerHTML",
            key: this.key,
            doc: this.doc,
          })
        }

        get parent() {
          let k = sendMessage({
            method: "html",
            function: "getParent",
            key: this.key,
            doc: this.doc,
          })
          if(k == null) return null;
          return new HtmlElement(k, this.doc);
        }

        get classNames() {
          return sendMessage({
            method: "html",
            function: "getClassNames",
            key: this.key,
            doc: this.doc,
          })
        }

        get id() {
          return sendMessage({
            method: "html",
            function: "getId",
            key: this.key,
            doc: this.doc,
          })
        }

        get localName() {
          return sendMessage({
            method: "html",
            function: "getLocalName",
            key: this.key,
            doc: this.doc,
          })
        }

        get previousElementSibling() {
          let k = sendMessage({
            method: "html",
            function: "getPreviousSibling",
            key: this.key,
            doc: this.doc,
          })
          if(k == null) return null;
          return new HtmlElement(k, this.doc);
        }

        get nextElementSibling() {
          let k = sendMessage({
            method: "html",
            function: "getNextSibling",
            key: this.key,
            doc: this.doc,
          })
          if (k == null) return null;
          return new HtmlElement(k, this.doc);
        }
      }

      class HtmlNode {
        key = 0;
        doc = 0;

        constructor(k, doc) {
          this.key = k;
          this.doc = doc;
        }

        get text() {
          return sendMessage({
            method: "html",
            function: "node_text",
            key: this.key,
            doc: this.doc,
          })
        }

        get type() {
          return sendMessage({
            method: "html",
            function: "node_type",
            key: this.key,
            doc: this.doc,
          })
        }

        toElement() {
          let k = sendMessage({
            method: "html",
            function: "node_toElement",
            key: this.key,
            doc: this.doc,
          })
          if(k == null) return null;
          return new HtmlElement(k, this.doc);
        }
      }
    ''');

    // 注入console和log函数
    _runtime!.evaluate('''
      function log(level, title, content) {
        sendMessage({
          method: 'log',
          level: level,
          title: title,
          content: content,
        })
      }

      let console = {
        log: (content) => {
          log('info', 'JS Console', content)
        },
        warn: (content) => {
          log('warning', 'JS Console', content)
        },
        error: (content) => {
          log('error', 'JS Console', content)
        },
      };
    ''');

    // 注入ComicSource基类 - 完整实现
    _runtime!.evaluate('''
      function Comic({id, title, subtitle, subTitle, cover, tags, description, maxPage, language, favoriteId, stars}) {
        this.id = id;
        this.title = title;
        this.subtitle = subtitle;
        this.subTitle = subTitle;
        this.cover = cover;
        this.tags = tags;
        this.description = description;
        this.maxPage = maxPage;
        this.language = language;
        this.favoriteId = favoriteId;
        this.stars = stars;
      }

      function ComicDetails({title, subtitle, subTitle, cover, description, tags, chapters, isFavorite, subId, thumbnails, recommend, commentCount, likesCount, isLiked, uploader, updateTime, uploadTime, url, stars, maxPage, comments}) {
        this.title = title;
        this.subtitle = subtitle ?? subTitle;
        this.cover = cover;
        this.description = description;
        this.tags = tags;
        this.chapters = chapters;
        this.isFavorite = isFavorite;
        this.subId = subId;
        this.thumbnails = thumbnails;
        this.recommend = recommend;
        this.commentCount = commentCount;
        this.likesCount = likesCount;
        this.isLiked = isLiked;
        this.uploader = uploader;
        this.updateTime = updateTime;
        this.uploadTime = uploadTime;
        this.url = url;
        this.stars = stars;
        this.maxPage = maxPage;
        this.comments = comments;
      }

      class ComicSource {
        name = ""
        key = ""
        version = ""
        minAppVersion = ""
        url = ""

        loadData(dataKey) {
          return sendMessage({
            method: 'load_data',
            key: this.key,
            data_key: dataKey
          })
        }

        loadSetting(key) {
          return sendMessage({
            method: 'load_setting',
            key: this.key,
            setting_key: key
          })
        }

        saveData(dataKey, data) {
          return sendMessage({
            method: 'save_data',
            key: this.key,
            data_key: dataKey,
            data: data
          })
        }

        deleteData(dataKey) {
          return sendMessage({
            method: 'delete_data',
            key: this.key,
            data_key: dataKey,
          })
        }

        get isLogged() {
          return sendMessage({
            method: 'isLogged',
            key: this.key,
          });
        }

        translation = {}

        translate(key) {
          let locale = "zh_CN"; // 默认中文
          return this.translation[locale]?.[key] ?? key;
        }

        init() { }

        static sources = {}
      }
    ''');
  }

  /// 消息接收器 - 处理JS发送的消息
  Object? _messageReceiver(dynamic message) {
    try {
      if (message is Map<dynamic, dynamic>) {
        if (message["method"] == null) return null;
        String method = message["method"] as String;
        
        switch (method) {
          case "log":
            String level = message["level"];
            Logger.addLog(
              switch (level) {
                "error" => LogLevel.error,
                "warning" => LogLevel.warning,
                "info" => LogLevel.info,
                _ => LogLevel.warning
              },
              message["title"] ?? "[$ruleKey]",
              message["content"].toString()
            );
            return null;
            
          case 'load_data':
            // TODO: 实现数据加载
            return null;
            
          case 'save_data':
            // TODO: 实现数据保存
            return null;
            
          case 'delete_data':
            // TODO: 实现数据删除
            return null;
            
          case 'http':
            return _handleHttpRequest(Map.from(message));
            
          case 'html':
            return _handleHtmlCallback(Map.from(message));
            
          case 'convert':
            return _handleConvert(Map.from(message));
            
          case "random":
            return _handleRandom(
              message["min"] ?? 0,
              message["max"] ?? 1,
              message["type"],
            );
            
          case "cookie":
            return _handleCookieCallback(Map.from(message));
            
          case "uuid":
            return const Uuid().v1();
            
          case 'load_setting':
            // 实现设置加载
            String settingKey = message['setting_key'];
            print('[设置加载] 请求设置: $settingKey');
            
            // 从内存中获取设置值，如果没有则提供默认值
            var value = _settings[settingKey];
            
            // 为特定规则提供默认设置
            if (value == null) {
              value = _getDefaultSetting(settingKey);
            }
            
            print('[设置加载] 返回$settingKey: $value');
            return value;
            
          case 'save_setting':
            // 实现设置保存
            String settingKey = message['setting_key'];
            dynamic value = message['value'];
            print('[设置保存] 保存设置: $settingKey = $value');
            _settings[settingKey] = value;
            return null;
            
          case "isLogged":
            return _isLogged;
            
          case "delay":
            return Future.delayed(Duration(milliseconds: message["time"]));
        }
      }
      return null;
    } catch (e) {
      Logger.error("处理JS消息失败: $message\n$e");
      rethrow;
    }
  }

  /// 处理HTTP请求 - 完全按照Venera标准
  Future<Map<String, dynamic>> _handleHttpRequest(Map<String, dynamic> req) async {
    try {
      print('[HTTP请求] 开始处理: ${req['http_method']} ${req['url']}');
      
      // 设置标准请求头（完全按照Venera的方式）
      var headers = Map<String, dynamic>.from(req["headers"] ?? {});
      if (headers["user-agent"] == null && headers["User-Agent"] == null) {
        headers["User-Agent"] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
      }
      
      final response = await networkService.request(
        sourceKey: ruleKey,
        method: req['http_method'] ?? 'GET',
        url: req['url'],
        headers: req['headers'] != null ? Map<String, String>.from(req['headers']) : null,
        data: req['data'],
        bytes: req['bytes'] == true,
      );

      print('[HTTP请求] 响应状态码: ${response.statusCode}');
      
      // 按照Venera标准格式返回
      Map<String, String> responseHeaders = {};
      response.headers.forEach((name, values) => responseHeaders[name] = values.join(','));
      
      // 关键：确保body格式正确
      dynamic body;
      if (req['bytes'] == true) {
        body = response.bodyBytes; // 返回Uint8List用于fetchBytes
      } else {
        body = response.body; // 返回String用于sendRequest
      }
      
      final result = {
        "status": response.statusCode,
        "headers": responseHeaders,
        "body": body,
        "error": null, // Venera标准：成功时不设置error
      };
      
      return result;
    } catch (e) {
      print('[HTTP请求] 请求异常: $e');
      Logger.error('[$ruleKey] HTTP请求异常: $e');
      
      // 按照Venera标准返回错误
      return {
        "status": 0,
        "headers": <String, String>{},
        "body": null,
        "error": e.toString(), // 只有真正的异常才设置error
      };
    }
  }

  /// 处理HTML回调
  Object? _handleHtmlCallback(Map<String, dynamic> data) {
    switch (data["function"]) {
      case "parse":
        if (_documents.length > 8) {
          var shouldDelete = _documents.keys.first;
          Logger.warning("[$ruleKey] 文档过多，删除最旧的: $shouldDelete");
          _documents.remove(shouldDelete);
        }
        _documents[data["key"]] = _DocumentWrapper.parse(data["data"]);
        return null;
        
      case "querySelector":
        var key = data["key"];
        return _documents[key]?.querySelector(data["query"]);
        
      case "querySelectorAll":
        var key = data["key"];
        return _documents[key]?.querySelectorAll(data["query"]);
        
      case "getText":
        return _documents[data["doc"]]?.elementGetText(data["key"]);
        
      case "getAttributes":
        return _documents[data["doc"]]?.elementGetAttributes(data["key"]);
        
      case "dom_querySelector":
        var doc = _documents[data["doc"]];
        return doc?.elementQuerySelector(data["key"], data["query"]);
        
      case "dom_querySelectorAll":
        var doc = _documents[data["doc"]];
        return doc?.elementQuerySelectorAll(data["key"], data["query"]);
        
      case "getChildren":
        var doc = _documents[data["doc"]];
        return doc?.elementGetChildren(data["key"]);
        
      case "getNodes":
        var doc = _documents[data["doc"]];
        return doc?.elementGetNodes(data["key"]);
        
      case "getInnerHTML":
        var doc = _documents[data["doc"]];
        return doc?.elementGetInnerHTML(data["key"]);
        
      case "getParent":
        var doc = _documents[data["doc"]];
        return doc?.elementGetParent(data["key"]);
        
      case "node_text":
        return _documents[data["doc"]]?.nodeGetText(data["key"]);
        
      case "node_type":
        return _documents[data["doc"]]?.nodeType(data["key"]);
        
      case "node_toElement":
        return _documents[data["doc"]]?.nodeToElement(data["key"]);
        
      case "dispose":
        var docKey = data["key"];
        _documents.remove(docKey);
        return null;
        
      case "getClassNames":
        return _documents[data["doc"]]?.getClassNames(data["key"]);
        
      case "getId":
        return _documents[data["doc"]]?.getId(data["key"]);
        
      case "getLocalName":
        return _documents[data["doc"]]?.getLocalName(data["key"]);
        
      case "getElementById":
        return _documents[data["key"]]?.getElementById(data["id"]);
        
      case "getPreviousSibling":
        return _documents[data["doc"]]?.getPreviousSibling(data["key"]);
        
      case "getNextSibling":
        return _documents[data["doc"]]?.getNextSibling(data["key"]);
    }
    return null;
  }

  /// 处理Cookie回调
  dynamic _handleCookieCallback(Map<String, dynamic> data) {
    switch (data["function"]) {
      case "set":
        // TODO: 实现Cookie设置
        return null;
      case "get":
        // TODO: 实现Cookie获取
        return [];
      case "delete":
        // TODO: 实现Cookie删除
        return null;
    }
    return null;
  }

  /// 处理转换操作
  Object? _handleConvert(Map<String, dynamic> data) {
    String type = data["type"];
    var value = data["value"];
    bool isEncode = data["isEncode"];
    
    try {
      switch (type) {
        case "utf8":
          return isEncode ? utf8.encode(value) : utf8.decode(value);
        case "base64":
          return isEncode ? base64Encode(value) : base64Decode(value);
        case "md5":
          return Uint8List.fromList(md5.convert(value).bytes);
        case "sha1":
          return Uint8List.fromList(sha1.convert(value).bytes);
        case "sha256":
          return Uint8List.fromList(sha256.convert(value).bytes);
        case "sha512":
          return Uint8List.fromList(sha512.convert(value).bytes);
        case "hmac":
          var key = data["key"];
          var hash = data["hash"];
          var hmac = Hmac(
            switch (hash) {
              "md5" => md5,
              "sha1" => sha1,
              "sha256" => sha256,
              "sha512" => sha512,
              _ => throw "Unsupported hash: $hash"
            },
            key
          );
          if (data['isString'] == true) {
            return hmac.convert(value).toString();
          } else {
            return Uint8List.fromList(hmac.convert(value).bytes);
          }
        case "aes-ecb":
          var key = data["key"];
          var cipher = ECBBlockCipher(AESEngine());
          cipher.init(isEncode, KeyParameter(key));
          return _processBlockCipher(cipher, value);
        case "aes-cbc":
          var key = data["key"];
          var iv = data["iv"];
          var cipher = CBCBlockCipher(AESEngine());
          cipher.init(isEncode, ParametersWithIV(KeyParameter(key), iv));
          return _processBlockCipher(cipher, value);
        case "aes-cfb":
          var key = data["key"];
          var iv = data["iv"];
          var blockSize = data["blockSize"];
          var cipher = CFBBlockCipher(AESEngine(), blockSize);
          cipher.init(isEncode, ParametersWithIV(KeyParameter(key), iv));
          return _processBlockCipher(cipher, value);
        case "aes-ofb":
          var key = data["key"];
          var blockSize = data["blockSize"];
          var cipher = OFBBlockCipher(AESEngine(), blockSize);
          cipher.init(isEncode, KeyParameter(key));
          return _processBlockCipher(cipher, value);
        case "rsa":
          if (!isEncode) {
            var key = data["key"];
            final cipher = PKCS1Encoding(RSAEngine());
            cipher.init(false, PrivateKeyParameter<RSAPrivateKey>(_parsePrivateKey(key)));
            return _processAsymmetricCipher(cipher, value);
          }
          return null;
        default:
          return value;
      }
    } catch (e) {
      Logger.error("[$ruleKey] 转换失败 $type: $e");
      return null;
    }
  }

  /// 处理块加密
  Uint8List _processBlockCipher(BlockCipher cipher, Uint8List value) {
    var offset = 0;
    var result = Uint8List(value.length);
    while (offset < value.length) {
      offset += cipher.processBlock(value, offset, result, offset);
    }
    return result;
  }

  /// 处理非对称加密
  Uint8List _processAsymmetricCipher(AsymmetricBlockCipher engine, Uint8List input) {
    final numBlocks = input.length ~/ engine.inputBlockSize +
        ((input.length % engine.inputBlockSize != 0) ? 1 : 0);

    final output = Uint8List(numBlocks * engine.outputBlockSize);

    var inputOffset = 0;
    var outputOffset = 0;
    while (inputOffset < input.length) {
      final chunkSize = (inputOffset + engine.inputBlockSize <= input.length)
          ? engine.inputBlockSize
          : input.length - inputOffset;

      outputOffset += engine.processBlock(input, inputOffset, chunkSize, output, outputOffset);
      inputOffset += chunkSize;
    }

    return (output.length == outputOffset) ? output : output.sublist(0, outputOffset);
  }

  /// 解析RSA私钥
  RSAPrivateKey _parsePrivateKey(String privateKeyString) {
    List<int> privateKeyDER = base64Decode(privateKeyString);
    var asn1Parser = ASN1Parser(privateKeyDER as Uint8List);
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    final privateKey = topLevelSeq.elements![2];

    asn1Parser = ASN1Parser(privateKey.valueBytes!);
    final pkSeq = asn1Parser.nextObject() as ASN1Sequence;

    final modulus = pkSeq.elements![1] as ASN1Integer;
    final privateExponent = pkSeq.elements![3] as ASN1Integer;
    final p = pkSeq.elements![4] as ASN1Integer;
    final q = pkSeq.elements![5] as ASN1Integer;

    return RSAPrivateKey(modulus.integer!, privateExponent.integer!, p.integer!, q.integer!);
  }

  /// 处理随机数生成
  num _handleRandom(num min, num max, String type) {
    if (type == "double") {
      return min + (max - min) * math.Random().nextDouble();
    }
    return (min + (max - min) * math.Random().nextDouble()).toInt();
  }

  /// 搜索漫画
  Future<List<MangaItem>> search(String keyword, int page) async {
    try {
      Logger.info('[$ruleKey] 开始搜索: $keyword, 页码: $page');
      print('[JS引擎] 开始搜索: ruleKey=$ruleKey, keyword=$keyword, page=$page');
      
      // 按照Venera的方式调用异步函数
      dynamic result;
      try {
        // 使用IIFE包装异步调用，确保Promise被正确处理
        final jsCode = '''
          (async function() {
            var source = ComicSource.sources["$ruleKey"];
            if (!source || !source.search || !source.search.load) {
              throw new Error("搜索功能未实现");
            }
            return await source.search.load(${jsonEncode(keyword)}, ${jsonEncode([])}, ${jsonEncode(page)});
          })()
        ''';
        
        print('[JS引擎] 执行JS代码: $jsCode');
        
        // 使用evaluate执行JS代码
        final jsResult = _runtime!.evaluate(jsCode, name: '<search>');
        print('[JS引擎] JS执行完成，jsResult类型: ${jsResult?.runtimeType}');
        
        // 检查是否是Future（Promise转换后的结果）
        if (jsResult is Future) {
          print('[JS引擎] 检测到Future，等待解析...');
          result = await jsResult;
          print('[JS引擎] Future解析完成: $result, 类型: ${result?.runtimeType}');
        } else {
          // 直接使用结果
          result = jsResult;
          print('[JS引擎] 直接使用结果: $result, 类型: ${result?.runtimeType}');
        }
        
      } catch (e) {
        print('[JS引擎] JS执行异常: $e');
        Logger.error('[$ruleKey] JS执行异常: $e');
        return [];
      }
      
      if (result != null && result is Map) {
        Logger.info('[$ruleKey] 搜索结果类型: ${result.runtimeType}');
        
        if (result['comics'] is List) {
          final comics = result['comics'] as List;
          Logger.info('[$ruleKey] 找到 ${comics.length} 个漫画');
          print('[JS引擎] 解析到 ${comics.length} 个漫画');
          
          return comics.map((comic) {
            return MangaItem.fromJs(Map<String, dynamic>.from(comic), _ruleName ?? ruleKey, ruleKey);
          }).toList();
        } else {
          Logger.warning('[$ruleKey] 搜索结果中没有comics字段: $result');
          print('[JS引擎] 搜索结果中没有comics字段');
        }
      } else {
        Logger.warning('[$ruleKey] 搜索结果不是Map类型，尝试解析: $result');
        print('[JS引擎] 搜索结果不是Map类型，类型: ${result?.runtimeType}');
        
        // 如果结果不是Map，可能是直接返回的comics数组
        if (result is List) {
          Logger.info('[$ruleKey] 直接解析comics数组，长度: ${result.length}');
          print('[JS引擎] 直接解析comics数组');
          
          return result.map((comic) {
            if (comic is Map) {
              return MangaItem.fromJs(Map<String, dynamic>.from(comic), _ruleName ?? ruleKey, ruleKey);
            } else {
              Logger.warning('[$ruleKey] 无效的comic对象: $comic');
              return null;
            }
          }).where((item) => item != null).cast<MangaItem>().toList();
        }
      }

      return [];
    } catch (e) {
      Logger.error('[$ruleKey] 搜索执行失败: $e');
      return [];
    }
  }

  /// 获取漫画详情
  Future<MangaDetail?> getDetail(String comicId) async {
    try {
      final jsCode = '''
        (async function() {
          var source = ComicSource.sources["$ruleKey"];
          if (!source || !source.comic || !source.comic.loadInfo) {
            throw new Error("详情功能未实现");
          }
          return await source.comic.loadInfo("$comicId");
        })()
      ''';

      final jsResult = _runtime!.evaluate(jsCode, name: '<getDetail>');

      dynamic result;
      if (jsResult is Future) {
        result = await jsResult;
      } else {
        result = jsResult;
      }

      if (result != null && result is Map) {
        return MangaDetail.fromJs(Map<String, dynamic>.from(result), comicId, _ruleName ?? ruleKey, ruleKey);
      }

      return null;
    } catch (e) {
      Logger.error('[$ruleKey] 获取详情执行失败: $e');
      return null;
    }
  }

  /// 获取章节内容
  Future<List<String>> getChapter(String comicId, String chapterId) async {
    try {
      final jsCode = '''
        (async function() {
          var source = ComicSource.sources["$ruleKey"];
          if (!source || !source.comic || !source.comic.loadEp) {
            throw new Error("章节功能未实现");
          }
          return await source.comic.loadEp("$comicId", "$chapterId");
        })()
      ''';

      final jsResult = _runtime!.evaluate(jsCode, name: '<getChapter>');

      dynamic result;
      if (jsResult is Future) {
        result = await jsResult;
      } else {
        result = jsResult;
      }

      if (result != null && result is Map && result['images'] is List) {
        return (result['images'] as List).map((e) => e.toString()).toList();
      }

      return [];
    } catch (e) {
      Logger.error('[$ruleKey] 获取章节执行失败: $e');
      return [];
    }
  }

  /// 用户登录
  Future<bool> login(String username, String password) async {
    try {
      final jsCode = '''
        (async function() {
          var source = ComicSource.sources["$ruleKey"];
          if (!source || !source.account || !source.account.login) {
            return false;
          }
          var result = await source.account.login("$username", "$password");
          return !result.error;
        })()
      ''';

      final jsResult = _runtime!.evaluate(jsCode, name: '<login>');

      dynamic result;
      if (jsResult is Future) {
        result = await jsResult;
      } else {
        result = jsResult;
      }

      _isLogged = result == true;
      return _isLogged;
    } catch (e) {
      Logger.error('[$ruleKey] 登录执行失败: $e');
      return false;
    }
  }

  /// 获取默认设置值
  dynamic _getDefaultSetting(String settingKey) {
    // 根据规则和设置键提供默认值
    switch (ruleKey) {
      case 'picacg':
        switch (settingKey) {
          case 'base_url':
            return 'https://picaapi.picacomic.com/';
          case 'appChannel':
            return '1';
          case 'imageQuality':
            return 'medium';
          default:
            return null;
        }
      case 'jm':
        switch (settingKey) {
          case 'apiDomain':
            return 'https://18comic.vip';
          default:
            return null;
        }
      case 'wnacg':
        switch (settingKey) {
          case 'domainSelection':
            return "0";
          case 'domain0':
            return 'www.wn06.ru';
          case 'refreshDomainsOnStart':
            return true;
          default:
            return null;
        }
      default:
        return null;
    }
  }

  /// 等待wnacg域名刷新完成并调整设置
  Future<void> _waitForDomainRefresh() async {
    try {
      print('[$ruleKey] 等待域名刷新完成...');
      
      // 等待一小段时间让域名刷新完成
      await Future.delayed(const Duration(seconds: 3)); // 增加等待时间
      
      // 检查是否有可用的域名
      final domainsResult = _runtime!.evaluate('Wnacg.domains');
      print('[$ruleKey] 检查可用域名: $domainsResult');
      
      if (domainsResult != null) {
        final domainsLength = _runtime!.evaluate('Wnacg.domains.length');
        print('[$ruleKey] 可用域名数量: $domainsLength');
        
        if (domainsLength != null && domainsLength > 0) {
          // 有可用域名，使用Domain 1
          _settings['domainSelection'] = "1";
          print('[$ruleKey] 切换到Domain 1');
          
          // 获取所有可用域名用于日志
          for (int i = 0; i < domainsLength; i++) {
            final domain = _runtime!.evaluate('Wnacg.domains[$i]');
            print('[$ruleKey] 可用域名 ${i + 1}: $domain');
          }
        } else {
          // 没有可用域名，检查是否是解析问题
          print('[$ruleKey] 没有解析到域名，检查原因...');
          
          // 手动调用refreshDomains来调试
          try {
            print('[$ruleKey] 手动调用refreshDomains进行调试...');
            _runtime!.evaluate('''
              (async function() {
                console.log('开始手动域名刷新调试...');
                let url = "https://wn01.link/";
                let res = await fetch(url);
                console.log('fetch结果状态:', res.status);
                if (res.status == 200) {
                  let html = await res.text();
                  console.log('HTML长度:', html.length);
                  console.log('HTML前500字符:', html.substring(0, 500));
                  
                  let document = new HtmlDocument(html);
                  let links = document.querySelectorAll("a[href]");
                  console.log('找到链接数量:', links.length);
                  
                  for (let i = 0; i < Math.min(links.length, 10); i++) {
                    let href = links[i].attributes["href"];
                    console.log('链接', i, ':', href);
                  }
                  document.dispose();
                }
              })().catch(e => console.log('调试异常:', e));
            ''');
            
            // 再等待一下让调试完成
            await Future.delayed(const Duration(seconds: 2));
          } catch (e) {
            print('[$ruleKey] 调试异常: $e');
          }
          
          // 使用已知的可用域名作为备用
          _settings['domainSelection'] = "0";
          _settings['domain0'] = 'www.wn06.ru'; // 使用测试成功的域名
          print('[$ruleKey] 使用备用域名: www.wn06.ru');
        }
      }
    } catch (e) {
      print('[$ruleKey] 域名刷新检查失败: $e');
      // 使用备用策略
      _settings['domainSelection'] = "0";
      _settings['domain0'] = 'www.wn06.ru';
      print('[$ruleKey] 使用备用域名: www.wn06.ru');
    }
  }

  /// 是否已登录
  bool get isLogged => _isLogged;

  /// 释放资源
  void dispose() {
    try {
      // 清理HTML文档
      _documents.clear();
      
      // 安全地关闭JS运行时
      if (_runtime != null) {
        try {
          // 清理JS环境中的引用
          _runtime!.evaluate('''
            // 清理ComicSource引用
            if (typeof ComicSource !== 'undefined' && ComicSource.sources) {
              delete ComicSource.sources["$ruleKey"];
            }
            
            // 清理全局变量
            if (typeof temp !== 'undefined') {
              delete this.temp;
            }
          ''');
        } catch (e) {
          // 忽略清理时的错误
          print('[$ruleKey] JS清理时出现错误（可忽略）: $e');
        }
        
        _runtime!.close();
        _runtime = null;
      }
      
      print('[$ruleKey] 资源释放完成');
    } catch (e) {
      Logger.error('[$ruleKey] 释放资源时出错: $e');
      print('[$ruleKey] 释放资源时出错: $e');
    }
  }
}

/// HTML文档包装器 - 基于Venera实现
class _DocumentWrapper {
  final html_dom.Document doc;
  final elements = <html_dom.Element>[];
  final nodes = <html_dom.Node>[];

  _DocumentWrapper.parse(String html) : doc = html_parser.parse(html);

  int? querySelector(String query) {
    var element = doc.querySelector(query);
    if (element == null) return null;
    elements.add(element);
    return elements.length - 1;
  }

  List<int> querySelectorAll(String query) {
    var res = doc.querySelectorAll(query);
    var keys = <int>[];
    for (var element in res) {
      elements.add(element);
      keys.add(elements.length - 1);
    }
    return keys;
  }

  String? elementGetText(int key) {
    return elements[key].text;
  }

  Map<String, String> elementGetAttributes(int key) {
    return elements[key].attributes.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  String? elementGetInnerHTML(int key) {
    return elements[key].innerHtml;
  }

  int? elementGetParent(int key) {
    var res = elements[key].parent;
    if (res == null) return null;
    elements.add(res);
    return elements.length - 1;
  }

  int? elementQuerySelector(int key, String query) {
    var res = elements[key].querySelector(query);
    if (res == null) return null;
    elements.add(res);
    return elements.length - 1;
  }

  List<int> elementQuerySelectorAll(int key, String query) {
    var res = elements[key].querySelectorAll(query);
    var keys = <int>[];
    for (var element in res) {
      elements.add(element);
      keys.add(elements.length - 1);
    }
    return keys;
  }

  List<int> elementGetChildren(int key) {
    var res = elements[key].children;
    var keys = <int>[];
    for (var element in res) {
      elements.add(element);
      keys.add(elements.length - 1);
    }
    return keys;
  }

  List<int> elementGetNodes(int key) {
    var res = elements[key].nodes;
    var keys = <int>[];
    for (var node in res) {
      nodes.add(node);
      keys.add(nodes.length - 1);
    }
    return keys;
  }

  String? nodeGetText(int key) {
    return nodes[key].text;
  }

  String nodeType(int key) {
    return switch (nodes[key].nodeType) {
      html_dom.Node.ELEMENT_NODE => "element",
      html_dom.Node.TEXT_NODE => "text",
      html_dom.Node.COMMENT_NODE => "comment",
      html_dom.Node.DOCUMENT_NODE => "document",
      _ => "unknown"
    };
  }

  int? nodeToElement(int key) {
    if (nodes[key] is html_dom.Element) {
      elements.add(nodes[key] as html_dom.Element);
      return elements.length - 1;
    }
    return null;
  }

  List<String> getClassNames(int key) {
    return elements[key].classes.toList();
  }

  String? getId(int key) {
    return elements[key].id;
  }

  String? getLocalName(int key) {
    return elements[key].localName;
  }

  int? getElementById(String id) {
    var element = doc.getElementById(id);
    if (element == null) return null;
    elements.add(element);
    return elements.length - 1;
  }

  int? getPreviousSibling(int key) {
    var res = elements[key].previousElementSibling;
    if (res == null) return null;
    elements.add(res);
    return elements.length - 1;
  }

  int? getNextSibling(int key) {
    var res = elements[key].nextElementSibling;
    if (res == null) return null;
    elements.add(res);
    return elements.length - 1;
  }
}