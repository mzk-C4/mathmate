# 📝 版本更新日志
## [version-2.4.1] - 2026-07-11

### ✨ 新增功能

#### 📚 Awesome Math 资源库
- 🎁 新增精选数学资源库（ssets/awesome_math.json）
  - 内置丰富的数学学习资源集合
  - 涵盖公式、定理、解题技巧等
- 📋 新增资源模型（lib/library/models/awesome_resource.dart）
- 🗂️ 新增资源库 Tab 页（lib/library/presentation/resource_library_tab.dart）
- 🎨 新增资源卡片组件（lib/library/presentation/awesome_resource_tile.dart）
- 📦 新增资源仓库服务（lib/library/services/awesome_math_repository.dart）
- 🐍 新增 Python 数据解析脚本（scripts/parse_awesome_math.py）

#### 💬 聊天系统重构
- 🔄 重构 chat_stream_service.dart（统一流式对话服务）
- 📱 重构 chat_page.dart（优化对话交互体验）
- 🏠 重构 chat_home_page.dart（增强首页对话入口）
- 🎥 优化视频推荐服务（ideo_recommendation_service.dart）

### 🐛 问题修复
- 🗑️ 移除废弃的 ivo_chat_service.dart（功能已合并至统一聊天服务）
- 🔧 修复 LaTeX 编译器引用问题
- 🔧 修复模型服务配置问题
- 🔧 修复历史记录仓库小问题

### 🎨 UI/UX 改进
- 📚 资料库页面新增资源库 Tab（分类浏览精选资源）
- 💬 聊天页面交互优化
- 📖 教程页面微调
