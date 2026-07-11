# 📝 版本更新日志
## [version-2.4.1] - 2026-07-11

> 🚀 功能优化版本：大学维度学习画像 + LaTeX 公式渲染全链路 + 火山 Ark 多模型 + 登录注册体系 + GeoChat Agent 升级

### ✨ 新增功能

#### 🎓 大学维度学习画像体系
- 📊 扩展用户雷达画像模型（lib/models/user_radar_profile.dart）
  - 新增大学维度特征，支持高等数学多领域能力评估
  - 6大核心能力维度：计算能力、逻辑推理、空间想象、抽象思维、应用能力、数学建模
- 🎯 能力评估服务升级（lib/services/ability_score_service.dart）
  - 优化评分算法，更精准的能力诊断
  - 支持多维度综合评估与个性化建议
- 📈 能力评估页面优化（lib/pages/ability_assessment_page.dart）
  - 更直观的雷达图交互
  - 详细的能力分析报告

#### 📐 LaTeX 公式渲染全链路打通
- 🧮 练习页公式渲染（lib/pages/practice_page.dart）
  - 题目、选项、解析全面支持 LaTeX 数学公式
  - 流畅的公式渲染体验，无闪烁、无错位
- 📚 题库页公式支持（lib/exam/pages/question_bank_page.dart）
  - 题目列表与详情页完整数学公式展示
  - 支持复杂公式、矩阵、积分等高等数学内容
- 🔍 搜题结果页公式优化（lib/pages/question_solver_page.dart）
  - 解题步骤逐行公式渲染
  - 推导过程清晰可读

#### 🔐 登录注册体系
- 📝 全新注册页面（lib/pages/register_page.dart）
  - 手机号 + 验证码注册流程
  - 密码设置与确认
  - 用户协议与隐私政策
- 🏠 登录页面重构（lib/services/login_page.dart）
  - 优化登录交互体验
  - 支持手机号 / 账号多种登录方式
  - 记住密码、自动登录
- 🖥️ 本地 Node.js 登录认证后端（deploy/auth_server.js）
  - 完整的用户认证服务
  - JWT Token 鉴权机制
  - 用户信息持久化存储
- 🔗 前后端对接优化（lib/services/auth_service.dart）
  - 修复前后端端口对接问题
  - 移除邀请码机制，开放注册
  - 统一 API 接口规范

#### 💬 聊天系统升级
- 🌋 接入火山 Ark 多模型（lib/services/chat_stream_service.dart）
  - 支持 DeepSeek / 火山 Ark 双模型切换
  - 多模型能力互补，提升对话质量
- 🎨 聊天页面优化（lib/chat_page.dart）
  - 消息流交互体验升级
  - 更流畅的流式响应
  - 优化的消息气泡样式
- 🏠 对话列表优化（lib/pages/chat_home_page.dart）
  - 对话管理更便捷
  - 历史记录快速检索

#### 🤖 GeoChat Agent 优化
- 🧠 GeoGebra Agent 服务升级（lib/services/geogebra_agent_service.dart）
  - 更智能的几何交互理解
  - 优化的指令解析与执行
- 📜 历史记录功能增强（lib/data/history_repository.dart）
  - 搜题历史记录优化
  - 更完善的历史管理
- 🎥 视频推荐服务重构（lib/services/video_recommendation_service.dart）
  - 基于学习画像的个性化视频推荐
  - 更精准的知识点匹配算法

### 🎨 UI/UX 改进
- 🎯 底部导航升级 Material 3（lib/main.dart）
  - 全新 Material 3 设计风格
  - 更现代的导航交互
  - 动态颜色主题适配
- 📱 响应式布局优化（lib/responsive/responsive_shell.dart）
  - 更好的多屏幕尺寸适配
  - 平板 / 折叠屏体验提升
- 📚 Awesome Math 资源库样式微调
  - 资源卡片视觉优化（lib/library/presentation/awesome_resource_tile.dart）
  - 资源库标签页体验升级（lib/library/presentation/resource_library_tab.dart）
- 🎨 主题系统优化（lib/theme/app_theme.dart）
  - Material 3 主题色调整
  - 更统一的视觉风格

### 🧹 清理与优化
- 🗑️ 清理 VIVO 旧文档（VIVO/ 目录）
  - 移除废弃的 BlueLM / vivoAI 文档
  - 精简项目结构
- 📁 资源文件整理
  - icon.png 迁移至 assets/images/ 目录
  - 统一资源目录结构
- 🔧 依赖更新（pubspec.lock）
  - 升级部分依赖至最新版本
  - 修复潜在的兼容性问题

### 🏗️ 架构升级
- 🔌 多模型服务架构（lib/services/model_service.dart）
  - 统一的模型管理接口
  - 可扩展的模型接入框架
- 🏛️ 前后端分离架构深化
  - 认证服务独立部署
  - API 接口标准化
- 📦 模块化程度提升
  - 登录注册模块解耦
  - 能力评估服务独立封装

### 📊 改动规模
- 改动文件：32 个
- 新增代码：约 1460+ 行
- 删除代码：约 900+ 行
- 涵盖：学习画像、公式渲染、登录注册、多模型、GeoChat、UI 升级
