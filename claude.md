# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 常用命令

```bash
# 安装依赖
flutter pub get

# 运行应用 (需先创建 .env 文件，见下方「环境变量」章节)
flutter run

# 静态分析 / Lint 检查
flutter analyze

# 运行测试
flutter test

# 运行单个测试文件
flutter test test/widget_test.dart

# 代码生成 (Isar 模型等)
flutter pub run build_runner build

# 代码生成 + 冲突处理
flutter pub run build_runner build --delete-conflicting-outputs

# 更新应用图标
flutter pub run flutter_launcher_icons
```

## 环境变量

应用依赖 `.env` 文件提供 API 密钥，不提供默认值。运行前必须在项目根目录创建 `.env`：

```bash
DEEPSEEK_API_KEY=sk-your-deepseek-key
DEEPSEEK_MODEL_ID=deepseek-chat
DEEPSEEK_BASE_URL=https://api.deepseek.com/chat/completions
VIVO_API_KEY=sk-your-qwen-key
VIVO_MODEL_ID=qwen-plus
VIVO_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions
VOLC_API_KEY=your-volc-api-key
VOLC_MODEL_ID=your-model-id
VOLC_BASE_URL=https://ark.cn-beijing.volces.com/api/v3/chat/completions
```

- **DeepSeek** — 被 `DeepSeekService` 用于 OCR 识别、解题、可视化三个核心阶段
- **VIVO** (Qwen) — 被 `HistoryRepository._generateTitle()` 用于生成搜题历史标题
- **VOLC** (火山引擎) — 被 `HandwritingOcrService` 和 `FormulaAnalysisService` 用于手写识别和公式分析

> `.env` 已被 `.gitignore` 忽略，不会提交到版本库。

## 架构概览

MathMate 是一款 Flutter 数学学习助手应用，使用 Material Design (Material 3)，面向移动端 (Android/iOS)。应用界面为中文，支持 zh_CN / en_US 多语言本地化。

### 状态管理：无外部状态管理库

项目不使用 Provider、Riverpod、Bloc 等状态管理框架。所有状态通过 `StatefulWidget` + `setState` 管理，页面间通过构造参数传递数据。

### 核心流水线 (Pipeline)

应用的核心流程是「拍照搜题 → 结果展示」：

1. **OCR 识别** (`OcrService`) - 将图片识别为 Markdown 数学公式
2. **解题** (`SolverService`) - 对识别结果求解
3. **可视化** (`VisualizationService`) - 生成几何图形 JSON 用于渲染

这三个步骤由 `MathPipelineService` 串联，按顺序执行。每步调用 DeepSeek API (`DeepSeekService`) 完成 AI 推理。

### 目录结构

| 目录 | 用途 |
|------|------|
| `lib/` 根目录 | 页面文件 (chat_page, handwriting_page, notes_page, result_page 等) |
| `lib/services/` | AI 服务调用 (OCR、解题、可视化、聊天流、DeepSeek/Vivo 客户端) |
| `lib/services/prompts/` | 各 AI 服务的 System Prompt 模板 |
| `lib/models/` | 数据模型 (pipeline_models, pipeline_stage, user_profile) |
| `lib/data/` | 本地持久化 (Isar 数据库, HistoryRepository, ConversationRepository) |
| `lib/visualization/` | 几何可视化渲染 (验证器、JSON 解析、Canvas 绘制) |
| `lib/scanner/` | 拍照/裁剪页面 |
| `lib/pages/` | 子页面 (calculator, chat_home, video_player) |
| `lib/theme/` | 主题定义 (亮色/暗色) |

**关键工具类：**
- `SafeJsonParser` (`lib/visualization/safe_json_parser.dart`) — 安全 JSON 解析器，所有来自 AI 响应的 JSON 解析都应使用它，能容错处理 `Infinity`、`NaN` 等非标准 JSON 值

### 数据层

- **Isar** (`HistoryRepository`, `ConversationRepository`) - 本地数据库，存储搜题历史、AI 对话记录、用户设置
- **SharedPreferences** (`ThemeService`) - 主题模式持久化
- `isar_generator` + `build_runner` - 生成 `.g.dart` 序列化代码

### 服务层约定

- **Singleton（单例）服务** — `HistoryRepository`、`ConversationRepository`、`ThemeService` 使用 `static final instance = ClassName._()` 工厂单例模式，初始化入口在 `main()` 函数中
- **普通服务** — `DeepSeekService`、`ChatStreamService` 等每次按需实例化
- **ThemeService** 继承 `ChangeNotifier`，通过 `addListener` 驱动 `MaterialApp` 的 `themeMode` 重建，无需 context 即可切换主题

### AI 服务

- `DeepSeekService` - DeepSeek API 客户端 (超时 60 秒)，被 Ocr/Solver/Visualization 三个服务共用
- `ChatStreamService` - 聊天流式响应
- `VivoChatService` - Vivo 聊天服务
- `VideoRecommendationService` - AI 视频推荐

### 页面路由

应用入口 `main.dart`，首次启动显示 `GradeSelectionPage` → `TutorialPage` → `MainScreen`。`MainScreen` 使用 `IndexedStack` + `BottomNavigationBar` 三个 Tab：题目首页、笔记、我的。

## 工作约束

### 通用规范
1. 严格遵循需求，只实现指定功能、修复指定问题，禁止额外新增功能。
2. 禁止擅自全局重构、修改原有业务逻辑、改动无关页面与代码。
3. 代码修改遵循最小改动原则，保留原有项目风格、结构与依赖。
4. 不主动优化UI、不调整格式、不删减原有可用代码。

### Flutter 专属规则
1. 针对 Flutter 项目修改，优先兼容空安全、组件生命周期、状态管理逻辑。
2. 涉及页面、函数、组件改造时，保证运行稳定，杜绝闪退、崩溃、空白、报错。
3. 提供完整可直接使用的代码块，如需修改文件，给出完整文件代码而非片段。
4. 所有改动必须清晰标注：修改位置、改动内容、实现逻辑。

### 输出格式要求
1. 先简述需求实现思路，简洁明了。
2. 列出所有修改点，明确变更范围。
3. 给出完整替换代码，可直接复制运行。
4. 关键代码添加简短注释，便于理解。

### 强制禁令
- 无需求许可，不得擅自删减、替换原有业务代码
- 不做过度封装、不强行统一编码风格
- 功能改造后，保证原有其他功能正常可用
