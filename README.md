<div align="center">
  <img src="https://mathmate.top/images/icon.png" alt="MathMate" width="96" />
  <h1>MathMate</h1>
  <p><strong>从一道题开始，完成一次真正的学习。</strong></p>
  <p>
    <a href="https://mathmate.top">在线体验</a> ·
    <a href="https://github.com/mzk-C4/mathmate/issues">反馈问题</a> ·
    <a href="#本地运行">本地运行</a>
  </p>
  <p>
    <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" />
    <img src="https://img.shields.io/badge/Dart-3.11%2B-0175C2?logo=dart&logoColor=white" alt="Dart" />
    <img src="https://img.shields.io/badge/version-2.4.5-6C5CE7" alt="Version" />
  </p>
</div>

<p align="center">
  <img src="https://mathmate.top/images/app-home.jpg" alt="MathMate 学习工作台首页" width="860" />
</p>

MathMate 是一个以 Flutter 构建的 AI 数学学习工作台。它把拍照识别、分步推导、动态几何、资料沉淀、组卷评测和学习画像放进同一条学习流程，让一道题不只得到答案，也能留下可复用的理解与复盘记录。

## 学习闭环

| 阶段 | 在 MathMate 中完成的事 |
| --- | --- |
| 1. 理解题目 | 拍照或导入题目，识别公式与结构，确认已知、未知和条件。 |
| 2. 走完推导 | 获取可追问的分步解析，查看关键公式与不同解法。 |
| 3. 看见关系 | 用动态几何、函数图像和可视化工具验证结论。 |
| 4. 练习复盘 | 将题目、错因、笔记和试卷报告沉淀为后续学习依据。 |

## 核心工作台

<table>
  <tr>
    <td width="50%" align="center">
      <img src="https://mathmate.top/images/app-camera-recognition.jpg" alt="拍照识别" width="300" />
      <br /><strong>识别与推导</strong><br />拍照识题、公式结构化、逐步解析与多轮追问。
    </td>
    <td width="50%" align="center">
      <img src="https://mathmate.top/images/app-solution-result.jpg" alt="解题结果" width="300" />
      <br /><strong>可阅读的解题过程</strong><br />LaTeX 排版、关键步骤展开、答案校验与解法对比。
    </td>
  </tr>
  <tr>
    <td width="50%" align="center">
      <img src="https://mathmate.top/images/app-math-toolbox.jpg" alt="数学工具箱" width="300" />
      <br /><strong>动态可视化</strong><br />几何绘图、函数图像和 GeoGebra 工具，把抽象关系变成可操作对象。
    </td>
    <td width="50%" align="center">
      <img src="https://mathmate.top/images/app-profile.jpg" alt="学习画像" width="300" />
      <br /><strong>练习与成长</strong><br />组卷、考试报告、错题整理与六维学习画像，帮助定位薄弱环节。
    </td>
  </tr>
</table>

## 能力一览

- **AI 解题助手**：图像识别、题目解析、分步解答、LaTeX 公式渲染和连续对话。
- **几何与图像工具**：GeometryPainter、函数绘制与内嵌 GeoGebra，支持交互式验证。
- **笔记与资料库**：手写笔记、PDF 资料、个人分类与全文检索，学习材料留在自己的工作台。
- **考试与错题系统**：按知识点组织题目，生成练习与报告，建立可复盘的错题记录。
- **资源索引**：内置精选开放数学资源链接，作为个人资料库之外的补充入口。
- **学习画像**：以六维能力雷达呈现学习状态，并为后续知识图谱和学习路径提供基础。

## 技术实现

| 层级 | 主要方案 |
| --- | --- |
| 客户端 | Flutter、Dart、Material 3、多端响应式布局 |
| AI 能力 | 多模型服务接入、图像理解、流式对话与 LaTeX 公式输出 |
| 数学可视化 | GeometryPainter、函数绘制、GeoGebra 集成 |
| 本地数据 | Hive、本地文件与资料索引 |
| 服务端 | FastAPI 考试服务、认证与数据接口 |

## 本地运行

### 1. 获取依赖

```bash
git clone https://github.com/mzk-C4/mathmate.git
cd mathmate
flutter pub get
```

### 2. 配置环境变量

复制 `.env.example` 为 `.env`，按需填写模型服务、认证与后端地址配置。不要将真实密钥提交到仓库。

```bash
cp .env.example .env
```

### 3. 启动应用

```bash
flutter run
```

若需使用组卷与考试相关接口，请另行启动 `ExamSystem/backend` 中的 FastAPI 服务。

## 项目结构

```text
lib/
  pages/             应用主要页面与学习工作台
  geogebra/          GeoGebra 集成与几何交互
  services/          AI、认证、数据等服务封装
  widgets/           可复用界面组件
  exam/              练习、试卷与报告功能
  wrong_book/        错题与复盘能力
ExamSystem/backend/  FastAPI 考试服务
assets/              图标、资源索引与应用素材
```

## 接下来

- 让个人知识图谱独立承接知识点、题目、错因和资料之间的关系。
- 基于学习画像给出可调整的练习路径与复习建议。
- 持续完善跨端体验、离线资料处理和数学可视化工具。

## 参与贡献

欢迎通过 [Issues](https://github.com/mzk-C4/mathmate/issues) 反馈问题或提出想法。提交 PR 前请先执行格式化与静态检查：

```bash
dart format .
flutter analyze
```
