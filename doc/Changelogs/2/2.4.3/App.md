# 📝 版本更新日志
## [version-2.4.3] - 2026-07-12

> 🔒 安全加固版本：认证后端安全重构 + 代理认证头统一 + 考试API修复 + GeoChat地址迁移 + 笔记标题修复

### 🔒 安全加固

#### 认证后端安全重构（deploy/auth_server.js）
- 🛡️ JWT Token 新增过期时间（exp），默认 7 天有效
- 🔐 Token 验证改用 `crypto.timingSafeEqual`，防时序攻击
- 📦 请求体大小限制（MAX_BODY_BYTES，默认 1MB），防大请求攻击
- 🔁 验证码验证逻辑提取为独立函数 `consumeVerificationAttempt`
  - 统一验证码校验入口，注册/验证复用同一逻辑
  - 限制最多 5 次尝试，过期自动清理
- 🚫 生产环境（NODE_ENV=production）不再回退验证码到 console
  - 邮件/短信服务未配置时返回 503 错误
- 📊 健康检查接口返回配置状态（smsConfigured / smtpConfigured）
- 📤 模块化导出（module.exports），支持测试引用
- 🌐 监听地址可配置（AUTH_HOST 环境变量）

#### 代理认证头统一
- 🔑 AuthService 新增 `proxyAuthHeaders` getter（X-MathMate-Token）
- 📡 所有 AI 服务请求统一添加认证头，共 10 个服务接入：
  - DeepSeekService（deepseek_service.dart）
  - ChatStreamService（chat_stream_service.dart）
  - HandwritingOcrService（handwriting_ocr_service.dart）
  - FormulaAnalysisService（formula_analysis_service.dart）
  - VolcAiClientService（volc_ai_client_service.dart）
  - GeogebraAgentService（geogebra_agent_service.dart）
  - VideoRecommendationService（video_recommendation_service.dart）
  - HistoryRepository（history_repository.dart）
  - MathRecognizer（math_recognizer.dart）
  - AIDrawingService（ai_drawing_service.dart）
  - ApiSettingsPage（api_settings_page.dart）

### 🐛 问题修复

#### 考试 API 语法修复（exam_api.dart）
- 🔧 修复 `?` 语法兼容性问题，改用标准 `if` 语法
  - `createExam`: board / difficultyMin / difficultyMax / questionTypes
  - `availableQuestionCount`: 同上
  - `submitAnswer`: imageUrl

#### 笔记标题修复
- 📝 新建笔记保存时，空标题自动生成时间戳（`笔记 2026-07-12 15:30`）
- 🛡️ 笔记列表标题防御：标题为空或 JSON 泄露（以 `{` / `[` 开头）时兜底显示时间戳

#### GeoGebra Chat 地址迁移
- 🌐 从 `http://47.94.83.150:3003/chat` 迁移至 `https://mathmate.top/geogebra-chat/`
  - HTTPS 加密传输
  - 统一域名访问

#### 测试修复
- 🧪 修复 widget_test 因首页动画导致 `pumpAndSettle` 无法结束的问题

### 📦 依赖更新
- nodemailer: ^6.9.13 → ^9.0.3（安全升级）

### 🧪 新增测试
- 📝 新增认证后端测试文件（deploy/auth_server.test.js）

### 📊 改动规模
- 改动文件：20 个
- 新增代码：约 140 行
- 删除/重构：约 50 行
- 涵盖：认证安全、代理认证头、考试API修复、笔记标题、GeoChat迁移
