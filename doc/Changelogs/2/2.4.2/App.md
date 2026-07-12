# 📝 版本更新日志
## [version-2.4.2] - 2026-07-12

> 🔧 功能增强版本：API 自定义配置 + 聊天 UI 全面升级 + 吉祥物悬浮球 + 考试系统修复 + 服务层重构

### ✨ 新增功能

#### 🔧 API 自定义配置系统
- 🎛️ 新增 API 设置页面（lib/pages/api_settings_page.dart）
  - 支持 DeepSeek / 通义千问 / 火山 Ark 三大模型自定义配置
  - 可自定义 API Key、Base URL、模型 ID、视觉模型
  - 在线测试连接功能
- 💾 新增 API 配置服务（lib/services/api_config_service.dart）
  - 基于 SharedPreferences 持久化存储
  - 统一的 ApiProvider 枚举管理
  - 支持请求格式选择（auto / openai / custom）

#### 🎨 聊天 UI 全面升级
- 💬 聊天页面重构（lib/chat_page.dart，+506 行改动）
  - 全新消息气泡设计
  - 优化流式响应体验
  - 更流畅的交互动画
- 🏠 对话列表页面优化（lib/pages/chat_home_page.dart）
  - 改进对话管理交互
- 🖼️ 新增聊天背景图
  - assets/images/background-chat-home.png（对话列表背景）
  - assets/images/background-chat-conversation.png（对话页背景）
  - assets/images/background-profile.png（个人页背景）

#### 🐾 吉祥物悬浮球
- 🔮 新增年级吉祥物悬浮球组件（lib/widgets/grade_mascot_orb.dart）
  - 基于 flutter_floating 实现桌面悬浮窗
  - 联动能力评估服务实时更新
  - 点击交互触发功能
- 🎭 新增年级 UI 主题配置（lib/theme/grade_ui_profile.dart）
  - 不同年级对应不同视觉风格
- 🧸 新增吉祥物素材资源（assets/mascots/）

#### 📚 教程与引导优化
- 📖 教程页面改进（lib/tutorial_page.dart）
  - 更直观的新手引导流程
- 🎓 年级选择页面优化（lib/grade_selection_page.dart）
  - 改进年级选择交互体验

### 🔧 服务层重构

#### AI 服务统一改造
- 🧠 DeepSeek 服务重构（lib/services/deepseek_service.dart）
  - 接入 API 配置服务，支持用户自定义配置
  - 统一的请求/响应处理
- 🌋 火山引擎客户端重构（lib/services/volc_ai_client_service.dart）
  - 支持自定义模型配置
  - 优化错误处理
- 💬 聊天流服务优化（lib/services/chat_stream_service.dart）
  - 改进流式响应解析
- 📝 手写 OCR 服务重构（lib/services/handwriting_ocr_service.dart）
  - 接入统一 API 配置
- 🔢 公式分析服务重构（lib/services/formula_analysis_service.dart）
  - 统一模型调用接口
- 🎥 视频推荐服务优化（lib/services/video_recommendation_service.dart）
  - 改进推荐算法
- 🤖 GeoGebra Agent 服务重构（lib/services/geogebra_agent_service.dart）
  - 优化指令解析逻辑

#### 认证与部署
- 🔐 认证服务优化（lib/services/auth_service.dart）
  - 改进 Token 管理机制
- 🖥️ 认证后端优化（deploy/auth_server.js）
  - 完善用户认证逻辑
- 🌐 代理服务器优化（deploy/proxy_server.js）
  - 改进请求转发机制

### 🐛 考试系统修复（PR #5 合并）
- 🔒 后端新增学生 ID 权限验证，防止越权提交
- 📊 修复成绩计算逻辑，基于考试题目统计而非记录
- 🩺 新增 `/api/exams/health` 健康检查接口
- 📦 新增 `/api/exams/available-count` 可用题量查询
- 🔑 前端考试 API 接入 JWT Token 认证
- ⏱️ 前端新增 30 秒请求超时
- 🧪 新增后端考试测试用例（81 行）
- 🧪 新增前端 API 测试用例（63 行）

### 🎨 UI/UX 改进
- 🏠 主页面重构（lib/main.dart，+584 行改动）
  - 集成吉祥物悬浮球
  - 优化页面路由与导航
- 👤 个人页面优化（lib/profile_page.dart）
  - 新增 API 设置入口
  - 改进视觉布局
- 🔢 数学识别器优化（lib/math_recognizer.dart）
  - 改进公式识别流程
- 📜 历史记录仓库优化（lib/data/history_repository.dart）
  - 改进记录管理逻辑
- 🎨 AI 绘画服务优化（lib/fusion/ai_drawing/services/ai_drawing_service.dart）

### 📦 新增依赖
- flutter_floating: ^2.0.2 — 桌面悬浮窗组件

### 🛠️ 工具脚本
- 📜 新增公开演示构建脚本（scripts/build_public_demo.ps1）

### 📊 改动规模
- 改动文件：23 个（已跟踪）+ 12 个（新增）
- 新增代码：约 1700+ 行
- 删除/重构：约 900 行
- 涵盖：API 配置、聊天 UI、吉祥物、考试系统修复、服务层重构
