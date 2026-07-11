# 📝 版本更新日志
## [version-2.4.0] - 2026-07-11

> 🎉 重大版本更新：考试系统全链路 + Awesome Math 资源库 + 聊天系统重构 + 学习画像体系 + 资料库迁移

### ✨ 新增功能

#### 🏫 考试系统（全链路打通）
- 📝 新增自由组卷页面（lib/pages/exam_creation_page.dart）
  - 按知识点/难度/题型灵活组卷
  - 绑定个人学习画像，针对性出题
- ✍️ 新增在线答题页面（lib/pages/exam_taking_page.dart）
  - 支持单选/多选/填空/解答题型
  - 实时倒计时、答题进度
- 📊 新增成绩结果页面（lib/pages/exam_result_page.dart）
  - 得分统计、错题解析
  - 知识点掌握度分析
- 🔌 新增考试系统 API 服务（lib/services/exam_api.dart）
  - 对接后端 ExamSystem（已部署至 mathmate.top）
  - 支持题目获取、提交答卷、自动评分

#### 🖥️ 考试系统后端（Python FastAPI）
- 🗄️ 完整数据库设计（SQLite，题目/试卷/答题记录）
- 🤖 AI 自动评分（LLM 评分主观题）
- 🔍 OCR 服务集成（图片题目识别）
- 📋 RESTful API（题目/试卷/评分/记录）
- 🧪 单元测试覆盖
- 📱 Flutter 客户端示例代码

#### 📖 Awesome Math 资源库
- 📚 新增 awesome_math.json 资源数据（5468 行，涵盖数学各领域）
- 🔧 新增 Python 解析脚本（scripts/parse_awesome_math.py）
- 📦 新增 AwesomeResource 模型与 Repository
- 🎨 新增资源卡片组件（awesome_resource_tile.dart）
- 📑 新增资源库标签页（resource_library_tab.dart）
- 📝 新增 awesome_math_readme.md 说明文档

#### 💬 聊天系统重构
- 🔄 重构 chat_page.dart（优化消息流、UI 交互）
- 🏠 重构 chat_home_page.dart（对话列表管理）
- 📡 重构 chat_stream_service.dart（流式响应优化）
- ❌ 移除 vivo_chat_service.dart（统一为 DeepSeek 通道）
- 🎥 优化视频推荐服务
- 📝 LaTeX 编译器微调

#### 🧠 学习画像体系
- 👤 新增 Learner Profile 模型（6 维特征）
- 💾 新增 ProfileRepository（Hive 持久化）
- 💬 新增 ProfileSetupDialog（对话式画像构建）
- 🎯 画像随学随新，持续优化

#### 📚 资料库迁移与优化
- 📌 资料库入口迁移至笔记页 + 号菜单（轻量化主页）
- 📁 重构资料库存储结构
- 🔗 与学习画像联动，个性化推荐资料

### 📦 新增模块与文档
- ExamSystem/ — 完整考试系统后端（Python FastAPI）
- exchange/ — 题库数据与服务端脚本
- docs-fusion/ — 融合架构分析与实施文档
- scripts/COMMIT_TO_GITHUB.sh — Git 提交脚本
- scripts/parse_awesome_math.py — Awesome Math 解析脚本
- plan.md / 改动.md — 项目规划文档
- about_mathmate_page.dart — 关于页面

### 🐛 问题修复
- 🧹 删除 __MACOSX 垃圾文件，完善 .gitignore
- 🔧 修复考试系统 API 地址配置（切换至生产环境）
- 🧩 合并多分支功能，解决代码冲突
- 🗑️ 移除废弃的 vivo_chat_service

### 🎨 UI/UX 改进
- 🏠 主页精简 Tab，聚焦核心功能（搜题/笔记/练习/我的）
- 📝 笔记页新增 + 号菜单入口（资料库/更多功能）
- 📊 能力雷达图交互优化（点击 Tab 触发动画）
- 🎯 学习画像入口卡片视觉升级
- 📖 资料库页面集成 Awesome Math 资源展示

### 🏗️ 架构升级
- 前后端分离架构确立（Flutter + FastAPI）
- Nginx 反向代理配置（/api/exams/、/api/grading/）
- 多模型服务统一入口（DeepSeek/通义/豆包）
- 聊天系统统一为 DeepSeek 通道，移除冗余服务
- 为软件杯参赛奠定完整系统架构基础

### 📊 改动规模
- 新增约 70+ 文件
- 代码新增约 16000+ 行
- 涵盖前端/后端/资源库/架构文档全链路
