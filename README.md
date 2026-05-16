# MathMate - 智能数学学习助手

**MathMate** 是一款功能丰富的智能数学学习移动应用，基于 Flutter 构建，支持 Android 和 iOS 双平台。

## 核心功能

- **拍照搜题** - 拍照识别数学题目，AI 自动求解并展示解题过程
- **几何可视化** - 题目中的几何图形自动渲染为交互式图形
- **AI 对话助手** - 流式聊天解答数学问题，支持 Markdown/LaTeX 公式渲染
- **数学工具箱** - 集成 GeoGebra (科学计算器、几何画板、函数绘图、3D 视图、尺规作图、概率模型)
- **智能笔记** - 支持多种纸张背景的手写笔记与笔记编辑
- **视频推荐** - 基于 AI 推荐和本地筛选的 B 站数学视频推荐
- **拍照扫描** - 拍照裁剪后进入 AI 识别与解题流程

## 技术栈

| 技术 | 说明 |
|------|------|
| Flutter 3.x (Dart SDK ^3.11.3) | 跨平台移动开发框架 |
| DeepSeek API | AI 大模型 (OCR 识别、解题推理、可视化生成、对话聊天) |
| Isar | 高性能本地数据库 (搜题历史、对话记录、用户设置) |
| GeoGebra (WebView) | 数学可视化工具 |
| KaTeX / flutter_math_fork | 数学公式渲染 |
| flutter_quill | 富文本/手写笔记编辑 |

## 项目结构

```
lib/
├── main.dart                        # 应用入口、主页面框架
├── models/                          # 数据模型
│   ├── pipeline_models.dart         # 识别/解题/可视化结果模型
│   └── pipeline_stage.dart          # 流水线阶段枚举
├── services/                        # 服务层
│   ├── math_pipeline_service.dart   # 核心流水线 (OCR→解题→可视化)
│   ├── ocr_service.dart             # 图片识别服务
│   ├── solver_service.dart          # 解题服务
│   ├── visualization_service.dart   # 几何可视化生成
│   ├── deepseek_service.dart        # DeepSeek API 客户端
│   ├── chat_stream_service.dart     # 聊天流式响应
│   ├── prompts/                     # AI 提示词模板
│   └── ...
├── data/                            # 数据持久化
│   ├── history_repository.dart      # 搜题历史 (Isar)
│   ├── conversation_repository.dart # 对话记录 (Isar)
│   └── ...
├── visualization/                   # 几何可视化渲染
│   ├── geometry_painter.dart        # Canvas 绘制引擎
│   ├── geometry_validator.dart      # JSON 校验
│   └── response_extractor.dart      # AI 响应解析
├── scanner/                         # 拍照与裁剪
├── pages/                           # 子页面
├── theme/                           # 主题 (亮色/暗色)
└── [各功能页面].dart                 # 手写、笔记、PDF、GeoGebra 等
```

## 运行项目

```bash
# 克隆项目
git clone https://github.com/mzk-C4/mathmate.git

# 安装依赖
flutter pub get

# 生成代码 (Isar 序列化等)
flutter pub run build_runner build

# 运行应用
flutter run
```

## 下载应用

- **Android**: 即将发布
- **iOS**: 即将发布

## 开源协议

本项目采用 MIT 协议开源。

---

## 更新日志

查看完整更新日志：[Changelogs](doc/Changelogs/)
