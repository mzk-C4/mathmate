# Kimi (Moonshot) API 兼容文档

> 基于 [官方文档](https://platform.kimi.com/docs) 整理，最后更新 2026-06-06。

## 模型列表

| 模型 ID | 代际 | 模态 | 上下文 | 思考模式 | temperature |
|---------|------|------|--------|---------|-------------|
| `kimi-k2.6` | 最新 | 文本+图片+视频 | 256K | **默认开启** | **固定 1.0** |
| `kimi-k2.5` | 上一代 | 文本+图片 | 256K | **默认开启** | **固定 1.0** |
| `moonshot-v1-128k` | v1 遗留 | 文本 | 128K | 不支持 | **固定 0.6** |
| `moonshot-v1-8k` | v1 遗留 | 文本 | 8K | 不支持 | **固定 0.6** |

关键区别：
- **K2 系列**：temperature 必须为 `1.0`，否则返回 400
- **v1 系列**：temperature 必须为 `0.6`，否则返回 400
- **K2 系列**：思考模式默认开启，输出 `reasoning_content` 后再输出 `content`
- **v1 系列**：无思考模式，直接输出 `content`

## API 基础信息

```
Base URL: https://api.moonshot.cn/v1
Endpoint: POST /chat/completions
格式: OpenAI 兼容
```

## 请求参数

### 通用参数

| 参数 | K2.6/K2.5 | moonshot-v1 | 说明 |
|------|-----------|-------------|------|
| `temperature` | **1.0** (固定) | **0.6** (固定) | 不能改，改了就 400 |
| `max_tokens` | ≥ 16000 推荐 | 按需 | K2 思考+回答共享预算 |
| `stream` | `true` (推荐) | `true` | 输出量大，流式避免超时 |
| `top_p` | 1.0 (默认) | 1.0 (默认) | 通常不需要设置 |

### thinking 参数（仅 K2 系列）

放在请求体的顶层（非 `extra_body` 嵌套）：

```json
{
  "model": "kimi-k2.6",
  "temperature": 1.0,
  "stream": true,
  "thinking": { "type": "disabled" }
}
```

| thinking.type | 效果 |
|---------------|------|
| 不传 | 默认开启思考 |
| `"enabled"` | 显式开启（默认行为） |
| `"disabled"` | **关闭思考**，直接输出 content |

### thinking.keep（多轮对话）

```json
{
  "thinking": { "type": "enabled", "keep": "all" }
}
```

保留历史 `reasoning_content` 以维持推理连贯性。注意会持续计费。

## 流式响应格式

### K2 系列（思考开启时）

```
data: {"choices":[{"delta":{"reasoning_content":"思考内容..."}}]}
data: {"choices":[{"delta":{"reasoning_content":"更多思考..."}}]}
data: {"choices":[{"delta":{"content":"实际回答..."}}]}
data: [DONE]
```

**关键**：`reasoning_content` **始终在 `content` 之前**。思考完成前 `content` 字段不存在。

### K2 系列（思考关闭 / thinking: disabled）

```
data: {"choices":[{"delta":{"content":"直接回答..."}}]}
data: [DONE]
```

没有 `reasoning_content`。

### v1 系列

```
data: {"choices":[{"delta":{"content":"回答..."}}]}
data: [DONE]
```

无思考模式，只有 `content`。

## Vision API（图片理解）

只支持 K2.6 和 K2.5。v1 系列不支持图片。

### 消息格式

```json
{
  "role": "user",
  "content": [
    { "type": "text", "text": "请识别图中的数学题..." },
    {
      "type": "image_url",
      "image_url": { "url": "data:image/jpeg;base64,..." }
    }
  ]
}
```

### 注意事项

1. **不支持 `role: "system"`** — Kimi vision API 拒绝 system role。解决：将 system prompt 合并到 user 的 text 字段。
2. 图片大小限制：官方未明确，实测 ~150KB base64 以内安全。
3. 图片格式：JPEG base64（先压缩到 1024px + quality 75）。

## 错误码

| HTTP 状态 | 典型错误信息 | 原因 |
|-----------|-------------|------|
| 400 | `invalid temperature: only 1.0 is allowed` | K2 模型用了其他 temperature |
| 400 | `invalid temperature: only 0.6 is allowed` | v1 模型用了其他 temperature |
| 400 | `role 'system' is not supported` | vision 请求带了 system role |
| 401 | `Invalid API key` | API Key 错误或过期 |
| 429 | `Rate limit exceeded` | 频率限制 |

## 代码中的实现要点

### 1. temperature 必须可配置

不同模型要求不同 temperature，不能硬编码。需要在 `ProviderConfigService` 中增加每槽位 temperature 字段。

### 2. 流式解析

```dart
// SSE chunk 解析
final String? content = delta['content'] as String?;
final String? reasoning = delta['reasoning_content'] as String?;

// K2 思考关闭或 v1 模型：只用 content
// K2 思考开启：reasoning 在前，content 在后
// 两者不会同时出现
```

### 3. extraBody 传递 thinking 参数

```dart
streamFromRequest(
  // ...
  extraBody: const {'thinking': {'type': 'disabled'}},
);
```

注意：`thinking` 放在请求体**顶层**，不嵌套在 extraBody 内。`streamFromRequest` 的 `extraBody` 通过 `body.addAll(extraBody)` 合并到顶层。

### 4. Vision system prompt 处理

```dart
// 错误：Kimi vision 不接受
messages = [
  {'role': 'system', 'content': '...'},
  {'role': 'user', 'content': [...]},
];

// 正确：合并到 user text
final userPrompt = '$systemPrompt\n\n请识别图片中的数学题。';
messages = [
  {'role': 'user', 'content': [
    {'type': 'text', 'text': userPrompt},
    {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,$image'}},
  ]},
];
```

## 参考链接

- [Kimi 开放平台](https://platform.kimi.com/docs)
- [K2 思考模型使用指南](https://platform.kimi.com/docs/guide/use-kimi-k2-thinking-model)
- [K2.6 API 第三方指南](https://apidog.com/blog/kimi-k2-6-api/)
