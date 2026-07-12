<div align="center">

  <!-- MathMate Logo with Gradient -->
  <img src="assets/icon.png" alt="MathMate Logo" width="120" height="120">

  # 🧮 MathMate

  ### **AI 驱动的智能数学学习应用**

  [![Flutter](https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter)](https://flutter.dev)
  [![Dart](https://img.shields.io/badge/Dart-^3.11.3-blue?logo=dart)](https://dart.dev)
  [![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
  [![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web-lightgrey)](https://github.com/mzk-C4/mathmate)
  [![Version](https://img.shields.io/badge/v2.4.3-purple)](https://github.com/mzk-C4/mathmate/releases)

  **拍照搜题 · 几何可视化 · AI 对话助手 · 学习画像 · 智能考试系统**

  [官网](https://mathmate.top) · [技术详解](https://mathmate.top/tech.html) · [演示视频](https://www.bilibili.com/video/BV1EfLJ6bEnw/) · [在线体验](https://mathmate.top/app)

</div>

---

## ✨ 核心功能

### 📸 拍照搜题 + AI 求解

支持手写和印刷题目的智能识别，AI 自动生成详细的分步解析。10 秒内完成「拍照 → 识别 → 解题 → 可视化」全流程，无题库限制。

<p align="center">
  <img src="https://mathmate.top/images/app-search.jpg" width="260" alt="拍照识别">
  <img src="https://mathmate.top/images/app-result.jpg" width="260" alt="AI解题">
</p>

### 🎨 交互式几何可视化

核心创新技术：AI 自动从题目文本中抽取几何参数，自研 `GeometryPainter` 引擎（纯 Dart Canvas）实时渲染可交互图形。支持拖拽动点、轨迹动画，60fps 原生帧率。

### 💬 AI 对话助手

嵌入式数学导师，提供一对一智能辅导。支持流式聊天、Markdown + LaTeX 实时渲染、深度思考链展示、多轮上下文对话。

### 🧰 GeoGebra 数学工具箱

集成 GeoGebra 离线版，提供：
- 🔬 科学计算器
- 📐 几何画板
- 📈 函数绘图
- 🎲 3D 视图
- 📏 尺规作图
- 🎲 概率模型

### 📝 智能笔记系统

- **手写笔记**：Catmull-Rom 样条平滑笔迹、AI 手写识别转 LaTeX
- **富文本笔记**：基于 flutter_quill，支持公式插入与图片嵌入
- **PDF 导入标注**：支持 PDF 查看与标注

### 🎬 个性化视频推荐

基于 DeepSeek AI 推荐算法 + 本地关键词匹配的 B 站数学视频推荐系统。

### 📚 Awesome Math 资源库

收录 5000+ 高质量数学资源，涵盖代数、分析、几何、拓扑、数论等领域。支持按学科分类浏览、关键词搜索，打造专属数学学习资料库。

### 🎯 学习画像体系

6 维能力评估模型（计算能力、逻辑推理、空间想象、抽象思维、应用能力、数学建模），自动生成个性化学习雷达图，精准定位薄弱环节，智能推荐学习路径。

### 📝 智能考试系统

- **自由组卷**：按知识点/难度/题型灵活组卷，绑定个人学习画像
- **在线答题**：支持单选/多选/填空/解答题型，实时倒计时
- **AI 评分**：后端 FastAPI + LLM 自动评分，错题解析与知识点分析

---

## 🎬 产品演示

<table align="center">
<tr>
<td align="center" width="600">

<a href="https://www.bilibili.com/video/BV1EfLJ6bEnw/">
  <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); border-radius: 16px; padding: 40px 30px; text-align: center; color: white;">
    <div style="font-size: 60px; margin-bottom: 16px;">▶️</div>
    <div style="font-size: 22px; font-weight: bold; margin-bottom: 8px;">MathMate 产品演示视频</div>
    <div style="font-size: 14px; opacity: 0.9;">AI 拍照搜题 · 几何可视化 · 智能对话 · 数学工具箱</div>
    <div style="margin-top: 16px; display: inline-block; background: rgba(255,255,255,0.2); padding: 8px 20px; border-radius: 20px; font-size: 13px;">
      🕐 时长 3 分钟 · 点击播放
    </div>
  </div>
</a>

</td>
</tr>
</table>

---

## 🏗️ 技术架构

```
┌─────────────────────────────────────────────────────────────┐
│                     MathMate 应用层                          │
│  拍照搜题 │ AI 对话助手 │ 数学工具箱 │ 手写笔记 │ 视频推荐  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                      服务层 (Service Layer)                  │
│  MathPipelineService │ ChatStreamService │ GeometryPainter  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                   AI 模型层 (Multi-Model AI)                  │
│     DeepSeek │ Volc Engine OCR │ Qwen-PLUS                 │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                  可视化引擎 (自研 Flutter 原生)               │
│        GeometryPainter (纯 Dart Canvas · 60fps)             │
└─────────────────────────────────────────────────────────────┘
```

### 技术栈

| 分类 | 技术 |
|:-----|:-----|
| **前端框架** | Flutter 3.x (Dart ^3.11.3) |
| **AI 模型** | DeepSeek API / 火山引擎 Ark / Qwen-PLUS |
| **数据库** | Hive (本地 NoSQL) / SQLite (后端) |
| **后端** | FastAPI (考试系统) / Node.js (认证服务) |
| **可视化** | 自研 GeometryPainter + GeoGebra WebView |
| **公式渲染** | KaTeX / flutter_math_fork |
| **富文本** | flutter_quill |

---

## 🚀 快速开始

### 环境要求

- Flutter SDK >= 3.11.3
- Dart SDK >= 3.11.3
- Android Studio / Xcode
- Node.js >= 16.0.0 (用于 Web 代理服务器)

### 安装

```bash
# 1. 克隆项目
git clone https://github.com/mzk-C4/mathmate.git
cd mathmate

# 2. 安装依赖
flutter pub get

# 3. 复制环境变量模板
cp .env.example .env

# 4. 编辑 .env 文件，填入你的 API Key
nano .env
```

**`.env` 配置示例：**

```bash
# DeepSeek API
DEEPSEEK_API_KEY=sk-your-deepseek-api-key
DEEPSEEK_API_URL=https://api.deepseek.com/v1

# 火山引擎 API
VOLC_API_KEY=your-volc-api-key
VOLC_API_URL=https://ark.cn-beijing.volces.com/api/v3

# Qwen API
QWEN_API_KEY=sk-your-qwen-api-key
QWEN_API_URL=https://dashscope.aliyuncs.com/api/v1
```

### 运行

```bash
# Android / iOS
flutter run

# Web
flutter build web --release
```

---

## 📦 项目结构

```
lib/
├── main.dart                      # 应用入口
├── models/                        # 数据模型
├── services/                      # 服务层
│   ├── math_pipeline_service.dart # 核心流水线
│   ├── ocr_service.dart           # OCR 识别
│   ├── solver_service.dart        # AI 解题
│   ├── visualization_service.dart # 几何可视化
│   └── prompts/                   # AI 提示词模板
├── visualization/                 # 几何可视化引擎
│   ├── geometry_painter.dart      # Canvas 渲染引擎
│   └── geometry_validator.dart    # JSON 校验
├── scanner/                       # 拍照与裁剪
├── pages/                         # 功能页面
└── theme/                         # 主题配置
```

---

## 🎯 核心优势

| 维度 | MathMate | 传统搜题 App | 通用大模型 |
|:-----|:--------:|:------------:|:----------:|
| **解题方式** | AI 实时推理 | 题库匹配 | 文本推理 |
| **几何可视化** | ✅ 交互式图形 | ❌ 静态图片 | ❌ 无 |
| **题目覆盖** | 无题库限制 | 仅题库收录 | 中等 |
| **个性化辅导** | ✅ 多轮对话 | ❌ 无 | ✅ 对话 |
| **学习画像** | ✅ 6维能力评估 | ❌ 无 | ❌ 无 |
| **考试系统** | ✅ 组卷/答题/AI评分 | ❌ 无 | ❌ 无 |
| **资源库** | ✅ Awesome Math 5000+ | ❌ 无 | ❌ 无 |
| **专业工具** | ✅ GeoGebra 6件套 | ❌ 无 | ❌ 无 |
| **数学严谨性** | ★★★★★ 92分 | ★★☆☆☆ 48分 | ★★★☆☆ 72分 |

---

## 🌐 在线体验

- **官网**: https://mathmate.top
- **技术详解**: https://mathmate.top/tech.html
- **Flutter Web**: https://mathmate.top/app

---

## 📸 应用截图

### 拍照搜题 · 一站式解题流程

<p align="center">
  <img src="https://mathmate.top/images/app-search.jpg" width="220" alt="拍照识别">
  <img src="https://mathmate.top/images/app-result.jpg" width="220" alt="AI 求解">
</p>

### 核心功能模块

<p align="center">
  <img src="https://mathmate.top/images/app-chat.jpg" width="220" alt="AI 对话">
  <img src="https://mathmate.top/images/app-notes.png" width="220" alt="手写笔记">
  <img src="https://mathmate.top/images/app-tools.jpg" width="220" alt="数学工具箱">
</p>

---

## 🔮 开发路线

### ✅ 已完成 (v2.4.3)

- [x] 核心流水线（OCR → 解题 → 可视化）
- [x] AI 对话助手（流式响应）
- [x] GeoGebra 工具箱集成
- [x] 手写笔记 + 富文本笔记
- [x] PDF 查看与标注
- [x] B 站视频推荐系统
- [x] Web 平台支持
- [x] 数据库迁移（Isar → Hive）
- [x] Awesome Math 资源库（5000+ 数学资源）
- [x] 学习画像体系（6 维能力雷达图）
- [x] 智能考试系统（组卷/答题/AI 评分）
- [x] LaTeX 公式渲染全链路（练习/题库/答题页）
- [x] 登录注册体系（Node.js 后端 + JWT 认证）
- [x] 火山 Ark 多模型接入
- [x] Material 3 底部导航升级
- [x] API 自定义配置系统（DeepSeek/通义/火山 Ark 用户可配）
- [x] 聊天 UI 全面升级（背景图、消息气泡、流式优化）
- [x] 年级吉祥物悬浮球（flutter_floating）
- [x] 考试系统安全修复（权限验证、成绩计算、健康检查）
- [x] 认证后端安全加固（JWT过期、防时序攻击、请求体限制）
- [x] 代理认证头统一（10个AI服务接入X-MathMate-Token）
- [x] GeoChat 迁移至 HTTPS（mathmate.top）
- [x] 笔记标题修复（空标题自动时间戳、JSON泄露防御）

### 🚧 进行中

- [ ] 个人知识图谱构建
- [ ] 智能错题本
- [ ] 学习路径智能推荐

### 📋 计划中

- [ ] 本地化 AI（flutter_onnxruntime）
- [ ] 3D 几何可视化增强
- [ ] Wolfram Alpha / Symbolab 集成
- [ ] 资料上传与自动分类（PPT/PDF/图片/录音）

---

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

---

## 👥 团队

**AK完全队** — 来自软件学院的跨学科创新团队

| 成员 | 角色 |
|:----|:----|
| **马兆坤** | 产品经理 |
| **丁宇鑫** | 前端设计 |
| **周星橙** | 前端开发 |
| **章开元** | 后端开发 |
| **应沛成** | AI 提示词工程师 |

**指导老师**
- 孙永谦（副教授 · 博士生导师）
- 王超（副研究员 · 硕士生导师）

---

## 📄 开源协议

本项目采用 **MIT 协议**开源 — 详见 [LICENSE](LICENSE) 文件

---

## 🌟 Star History

<p align="center">
  <a href="https://github.com/mzk-C4/mathmate/stargazers">
    <img src="assets/star_badge.svg" alt="GitHub stars">
  </a>
</p>

感谢所有给本项目点 Star 的朋友们！ ⭐

---

<div align="center">

  **如果觉得有用，请给我们一个 ⭐Star⭐**

  Made with ❤️ by AK完全队

  [官网](https://mathmate.top) · [技术文档](https://mathmate.top/tech.html) · [演示视频](https://www.bilibili.com/video/BV1EfLJ6bEnw/) · [问题反馈](https://github.com/mzk-C4/mathmate/issues)

</div>
