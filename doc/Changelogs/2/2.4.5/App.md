# MathMate v2.4.5 更新日志

## 新增功能

### GeoChat 几何引擎
- 新增几何引擎核心模块 (geometry_engine)，支持几何计划的生成、执行与验证
- 新增 geometry_plan：几何指令计划生成器
- 新增 geometry_plan_executor：计划执行引擎，对接 GeoGebra 命令
- 新增 geometry_plan_validator：计划验证器，确保几何操作的合法性
- 新增 geometry_plan_tool_handler：工具处理器，支持多种几何工具操作
- 新增 geochat_history_builder：会话历史构建器，支持上下文感知
- 新增 geogebra_web_engine：Web 端几何引擎适配
- 离线命令解析器增强，支持更多 GeoGebra 指令格式

### 资料库交互增强
- 我的资料卡片支持长按删除功能 (MaterialRepository.delete)
- 资料管理更加便捷高效

### 练习答题系统优化
- 选择题选项解析增强：支持 (A)/A./A、/285A$$ 多种格式，圆圈内纯 ABCD
- 填空题答案对比优化：支持 3/10 ↔ 0.3 ↔ \frac{3}{10} 数值等价判定
- 新增下一题导航：接收题目列表+索引，第10题隐藏下一题，返回直接回练习页

### 考试认证流程
- 考试创建页面认证流程对齐
- 登录页面认证逻辑优化
- 新增考试 API 单元测试覆盖

## 修复与改进

- 修复 Android 闪退：_LatexRenderer._buildMixed() WidgetSpan→Wrap 布局问题
- 修复下一题按钮：pushReplacement + addPostFrameCallback 防止路由动画冲突
- 删除6个低质视频资源（诱导公式记忆法、核心概念梳理、零基础学数列等）
- 注释摆拍用演示模式代码（enableDemoMode、demoLambda、硬编码题目）

## 测试
- 新增几何计划执行器单元测试
- 新增几何计划工具处理器单元测试
- 新增几何计划验证器单元测试
- 新增离线命令解析器测试用例
- 新增 GeoChat 历史构建器测试
- 新增更新服务单元测试
- 新增考试 API 测试
- 命令搜索服务测试扩展

## 配置与部署
- AndroidManifest 配置更新
- Nginx 配置优化
- pubspec 依赖更新
- Profile 页面配置优化
- 更新服务配置调整
- 对话仓库配置优化
- 新增 Android 发布脚本 (publish_android.ps1)

---
发布日期: 2026-07-13
Full Changelog: https://github.com/mzk-C4/mathmate/compare/v2.4.4...v2.4.5