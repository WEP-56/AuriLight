# 漫画 JSON 规则编写要点

> **目标**：让规则在新引擎（`lib/core/services/manga_json_engine.dart`）下稳定运行，避免因“隐式行为”导致的兼容问题。  
> **原则**：显式优于隐式，字段缺失时引擎会尽量回退到兼容行为，但建议按规范写，便于维护和迁移。

---

## 一、基础结构

```json
{
  "api": "4",
  "type": "manga",
  "name": "唯一标识符（英文，无空格）",
  "displayName": "显示名称（中文）",
  "version": "1.0.0",
  "baseURL": "https://example.com",
  "userAgent": "Mozilla/5.0 ...",
  "useWebview": false,
  "search": { ... },
  "detail": { ... },
  "reader": { ... }
}
```

- `baseURL`：用于拼接相对路径。如果站点支持多域名，可在规则中实现 `domainRefresh`（见下文）。
- `useWebview`：如果站点需要 WebView（如 Cloudflare/JS 加密），设为 `true`。

---

## 二、搜索（`search`）

### 2.1 基础写法（HTML 列表页）

```json
{
  "searchURL": "/s/{keyword}",
  "pageParam": "?page={page}",
  "resultList": ".item-list > .item",
  "itemSelectors": {
    "id": {
      "selector": "a",
      "attr": "href",
      "regex": "/comic/([^/?#]+)"
    },
    "title": {
      "selector": "h3",
      "attr": "text"
    },
    "cover": {
      "selector": "img",
      "attr": "src"
    }
  }
}
```

- **`id`**：必须返回**唯一标识**（通常是相对路径或纯 ID）。如果返回的是绝对 URL，引擎会自动处理。
- **`regex`**：可选，用于从 `href` 中提取 ID。推荐用，避免把整段 URL 当 ID。
- **`pageParam`**：分页参数。如果站点分页用 `?page=`，直接写；如果用 `/page/2`，则 `searchURL` 写成 `/s/{keyword}/page/{page}`。

### 2.2 多域名/域名刷新（可选）

```json
{
  "domainRefresh": {
    "url": "https://example.com/domains",
    "selector": "a[href*='//']",
    "pattern": "//([^/]+)/",
    "exclude": ["ads.", "track."]
  }
}
```

- 适用于“经常换域名”的站点。引擎会先请求 `url`，用 `selector` + `pattern` 提取可用域名，排除 `exclude` 列表。
- **注意**：`baseURL` 仍需填写一个默认值。

---

## 三、详情（`detail`）

### 3.1 基础字段提取

```json
{
  "detailURL": "{id}",
  "selectors": {
    "title": {
      "selector": ".title",
      "attr": "text"
    },
    "cover": {
      "selector": ".cover img",
      "attr": "src"
    },
    "description": {
      "selector": ".desc",
      "attr": "text"
    },
    "tags": {
      "selector": ".tag-list a",
      "attr": "text"
    }
  }
}
```

- `detailURL`：`{id}` 会被替换为搜索阶段返回的 `id`。
- `tags`：返回字符串数组，引擎会统一为 `Map<String, List<String>>`。

### 3.2 章节（`chapters`）

#### 3.2.1 `method: selector`（推荐，适用于 HTML 章节列表）

```json
{
  "method": "selector",
  "selector": ".chapter-list a",
  "attr": "text",
  "reverse": true,
  "hrefBase": "https://www.example.com"
}
```

- `selector`：选中章节元素（通常是 `<a>` 或包含标题的子元素）。
- `attr`：提取标题（默认 `text`）。
- `reverse`：是否倒序（默认 `false`）。
- **`hrefBase`（重要）**：如果章节 `<a href>` 是相对路径，但实际章节页在另一个域名，请填写该域名。引擎会自动补全。

> **为什么需要 `hrefBase`？**  
> 有些站点（如 baozi）搜索/详情页在一个域名，章节页在另一个域名。`hrefBase` 用于补全章节 `href`，避免 `chapterId` 错误。

#### 3.2.2 `method: json`（适用于返回 JSON 的章节 API）

```json
{
  "method": "json",
  "mangaId": {
    "selector": "#manga-info",
    "attr": "data-mid"
  },
  "apiURL": "https://api.example.com/chapters?mid={mid}&t={ts}",
  "resultPath": "data.chapters",
  "idPath": "id",
  "titlePath": "title",
  "idTemplate": "{mid}@{id}",
  "headers": {
    "Referer": "https://example.com"
  }
}
```

- `mangaId`：从详情页提取漫画 ID（用于 API 请求）。
- `apiURL`：章节 API URL，支持 `{mid}`（漫画 ID）和 `{ts}`（时间戳）。
- `resultPath`：JSON 中章节列表的路径。
- `idPath` / `titlePath`：章节 ID 和标题在 JSON 中的字段。
- `idTemplate`：可选，用于拼接章节 ID（如 `{mid}@{id}`）。
- `headers`：可选，API 请求头。

#### 3.2.3 `method: html`（适用于返回 HTML 的章节 API）

```json
{
  "method": "html",
  "mangaId": {
    "selector": "#manga-info",
    "attr": "data-mid"
  },
  "apiURL": "https://example.com/chapters?mid={mid}&t={ts}",
  "itemSelector": ".chapter-item",
  "msAttr": "data-ms",
  "csAttr": "data-cs",
  "idTemplate": "{ms}@{cs}",
  "titleSelector": ".title",
  "titleAttr": "text",
  "reverse": true,
  "headers": {
    "Referer": "https://example.com"
  }
}
```

- `itemSelector`：章节项选择器。
- `msAttr` / `csAttr`：用于拼接章节 ID 的两个属性（如 `data-ms`、`data-cs`）。
- `idTemplate`：用 `{ms}` 和 `{cs}` 拼接章节 ID。

---

## 四、阅读（`reader`）

### 4.1 `method: selector`（推荐，适用于章节页直接包含图片）

```json
{
  "imagesURL": "{chapterId}",
  "method": "selector",
  "selector": ".comic-page img",
  "attr": "data-src,src",
  "headers": {
    "Referer": "https://example.com"
  },
  "postProcess": [
    {
      "type": "replace",
      "from": "/w640/",
      "to": "/"
    }
  ]
}
```

- `imagesURL`：章节页 URL。如果章节 ID 是绝对 URL，直接写 `{chapterId}`；如果是相对路径，引擎会用 `baseURL` 拼接。
- `selector`：图片元素选择器。
- `attr`：图片 URL 属性（支持多个，用逗号分隔）。
- `postProcess`：图片 URL 后处理（见下文）。

### 4.2 `method: json`（适用于返回 JSON 的图片 API）

```json
{
  "imagesURL": "https://api.example.com/images?mid={mangaId}&cid={chapterId}",
  "method": "json",
  "listPath": "data.images",
  "urlTemplate": "https://cdn.example.com{imageName}",
  "headers": {
    "Referer": "https://example.com"
  }
}
```

- `imagesURL`：图片 API URL。引擎会先请求该 URL，解析 JSON。
- `listPath`：JSON 中图片列表的路径。
- `urlTemplate`：图片 URL 模板。支持 `{imageName}`、`{mangaId}`、`{chapterId}` 等占位符。

> **兼容说明**：新引擎支持 `json` 分支使用 `imagesURL`（旧引擎语义）。如果规则只写了 `imagesURL` 而没有 `path`，引擎会直接请求该 URL。

### 4.3 `method: apiJsonPaged`（适用于分页 API）

```json
{
  "method": "apiJsonPaged",
  "baseApiUrl": "https://api.example.com",
  "path": "/images?mid={mangaId}&cid={chapterId}&page={page}",
  "listPath": "data.images",
  "pagesPath": "data.pages",
  "fileServerPath": "fileServer",
  "pathPath": "path",
  "urlTemplate": "{fileServer}/static/{path}"
}
```

- `baseApiUrl`：API 基础 URL。
- `path`：分页路径，支持 `{page}`。
- `pagesPath`：总页数字段路径。
- `fileServerPath` / `pathPath`：图片 URL 中的文件服务器和路径字段。

### 4.4 `method: regex`（适用于直接用正则提取图片 URL）

```json
{
  "imagesURL": "{chapterId}",
  "method": "regex",
  "pattern": "\"images\":\\s*\\[(.*?)\\]",
  "prefix": "https://example.com",
  "postProcess": [
    {
      "type": "replace",
      "from": "\\\\",
      "to": ""
    }
  ]
}
```

- `pattern`：正则表达式，用于提取图片 URL 数组。
- `prefix`：图片 URL 前缀（可选）。

### 4.5 `method: script`（适用于需要 JS 执行的站点，如 nhentai）

```json
{
  "imagesURL": "{chapterId}",
  "method": "script",
  "scriptPattern": "window\\._gallery",
  "jsonPath": "media.pages",
  "urlTemplate": "https://i.example.com/{media_id}/{index}.{ext}"
}
```

- `scriptPattern`：用于定位 JS 对象的正则。
- `jsonPath`：图片列表在 JS 对象中的路径。
- `urlTemplate`：图片 URL 模板，支持 `{media_id}`、`{index}`、`{ext}`。

---

## 五、图片 URL 后处理（`postProcess`）

用于修复图片 URL 中的常见问题（如域名替换、路径修正）。

### 5.1 常用操作

```json
{
  "postProcess": [
    {
      "type": "replace",
      "from": "/w640/",
      "to": "/"
    },
    {
      "type": "replaceDomain",
      "to": "cdn.example.com"
    },
    {
      "type": "removeLastChar"
    }
  ]
}
```

- `replace`：字符串替换。
- `replaceDomain`：替换 URL 的域名。
- `removeLastChar`：移除最后一个字符（适用于末尾多余的分隔符）。

### 5.2 简写形式

```json
{
  "postProcess": ["removeLastChar"]
}
```

- 直接写字符串表示 `type`。

---

## 六、登录与账号（可选）

如果站点需要登录才能访问完整内容，可在规则中配置 `account`。

```json
{
  "account": {
    "loginUrl": "https://example.com/login",
    "loginMethod": "POST",
    "loginFields": {
      "username": "username",
      "password": "password"
    },
    "checkLogin": {
      "url": "https://example.com/profile",
      "selector": ".username",
      "attr": "text"
    },
    "baseApiUrl": "https://api.example.com",
    "fallbackServers": ["https://backup.example.com"]
  }
}
```

- `loginUrl`：登录接口 URL。
- `loginMethod`：请求方法（`GET`/`POST`）。
- `loginFields`：登录表单字段映射。
- `checkLogin`：用于检查登录状态的接口/页面。
- `baseApiUrl`：登录后 API 的基础 URL（可选）。
- `fallbackServers`：备用服务器列表（适用于多域名站点）。

---

## 七、常见问题与最佳实践

### 7.1 为什么“点击阅读没反应”？
- **原因**：`reader.method=json` 但只写了 `imagesURL`，没有 `path`。旧引擎会直接请求 `imagesURL`，新引擎需要显式支持。
- **解决**：确保 `imagesURL` 可访问，或改用 `method: selector`。

### 7.2 为什么章节 ID 错误？
- **原因**：章节 `<a href>` 是相对路径，但实际章节页在另一个域名。
- **解决**：在 `chapters` 中添加 `hrefBase`。

### 7.3 为什么图片 URL 错误？
- **原因**：图片 URL 需要后处理（如去掉缩放参数、替换域名）。
- **解决**：在 `reader` 中添加 `postProcess`。

### 7.4 如何调试？
- 在引擎中查看日志（`Logger.info`/`Logger.error`）。
- 用浏览器的开发者工具检查网络请求和页面结构。
- 参考 `oldengine.dart` 的行为（如果新引擎不兼容）。

---

## 八、迁移指南（从旧引擎到新引擎）

| 旧引擎行为 | 新引擎要求 | 建议 |
|------------|------------|------|
| `reader.method=json` 直接请求 `imagesURL` | 需要显式支持 `imagesURL` | 确保 `imagesURL` 可访问，或改用 `method: selector` |
| 章节 ID 用索引 | 默认尝试从 `<a href>` 推导 | 如果不需要 href，可把 `selector` 改为 `<a>`，或保留隐式回退 |
| URL 拼接用 `baseUrl + path` | 需要区分绝对/相对 URL | 确保 `detailURL`、`searchURL`、`imagesURL` 的模板正确 |

---

## 九、示例规则

### 9.1 简单 HTML 站点（如 mh18）

```json
{
  "api": "4",
  "type": "manga",
  "name": "mh18",
  "displayName": "18漫画",
  "baseURL": "https://18mh.org",
  "search": {
    "searchURL": "/s/{keyword}",
    "resultList": ".item",
    "itemSelectors": {
      "id": {
        "selector": "a",
        "attr": "href",
        "regex": "/manga/([^/?#]+)"
      },
      "title": {
        "selector": "h3",
        "attr": "text"
      },
      "cover": {
        "selector": "img",
        "attr": "src"
      }
    }
  },
  "detail": {
    "detailURL": "{id}",
    "selectors": {
      "title": {
        "selector": ".title",
        "attr": "text"
      },
      "cover": {
        "selector": ".cover img",
        "attr": "src"
      }
    },
    "chapters": {
      "method": "selector",
      "selector": ".chapter-list a",
      "attr": "text",
      "reverse": true
    }
  },
  "reader": {
    "imagesURL": "{chapterId}",
    "method": "selector",
    "selector": ".comic-page img",
    "attr": "data-src,src"
  }
}
```

### 9.2 JSON API 站点（如 goda）

```json
{
  "api": "4",
  "type": "manga",
  "name": "goda",
  "displayName": "GoDa漫画",
  "baseURL": "https://godamh.com",
  "search": {
    "searchURL": "/s/{keyword}",
    "resultList": ".item",
    "itemSelectors": {
      "id": {
        "selector": "a",
        "attr": "href",
        "regex": "/comic/([^/?#]+)"
      },
      "title": {
        "selector": "h3",
        "attr": "text"
      },
      "cover": {
        "selector": "img",
        "attr": "src"
      }
    }
  },
  "detail": {
    "detailURL": "{id}",
    "selectors": {
      "title": {
        "selector": ".title",
        "attr": "text"
      },
      "cover": {
        "selector": ".cover img",
        "attr": "src"
      }
    },
    "chapters": {
      "method": "json",
      "mangaId": {
        "selector": "#manga-info",
        "attr": "data-mid"
      },
      "apiURL": "https://api.example.com/chapters?mid={mid}&t={ts}",
      "resultPath": "data.chapters",
      "idPath": "id",
      "titlePath": "title",
      "idTemplate": "{mid}@{id}"
    }
  },
  "reader": {
    "imagesURL": "https://api.example.com/images?mid={mangaId}&cid={chapterId}",
    "method": "json",
    "listPath": "data.images",
    "urlTemplate": "https://cdn.example.com{imageName}"
  }
}
```

---

## 十、结语

- **显式优于隐式**：尽量把依赖的字段写清楚，避免依赖引擎的隐式回退。
- **测试优先**：写完规则后，先测试搜索、详情、阅读三个流程。
- **参考旧引擎**：如果新引擎不兼容，可以参考 `oldengine.dart` 的行为，但优先按新引擎规范调整规则。

希望这份文档能帮助后来的开发者快速上手，减少踩坑。祝 KazuVera2D 越来越好！