# MathMate「个性化学习资料库」模块设计

> 版本：v1.0 · 日期：2026-07-06 · 对标赛题：A1《多模态大模型数字化教学资源制作》/ A7《教学实训智能体软件》
>
> 状态：设计已收敛，与现有架构（agents / learner / Hive / DeepSeek 范式）零冲突，依赖几乎为零。

---

## 0. 一句话定位

把散落在相册 / 微信文件 / 网盘里的 **PPT 课件、往年真题 PDF、板书图片、划重点录音**，统一喂进 MathMate，由多智能体自动 **解析 → 分类 → 打标签 → 建索引**，形成"针对你所在高校 / 课程"的专属资料库；同时把资料行为反哺学习画像，让生成的讲解 / 题目 / 路径都基于你 **真实手头的资料**。

解决真实痛点：平时保存的资料不知道去哪、期末复习时找不到；形成个性化、针对不同高校的资料库。

---

## 1. 现状基线（调研结论，决定设计的硬约束）

资料库必须贴着现有架构长出来，否则就是推倒重来。关键约束：

| 维度 | 现状 | 对资料库的约束 |
|---|---|---|
| **W1 改造进度** | ✅ 已落地。`lib/agents/`(orchestrator + base_agent + visualizer_agent)、`lib/learner/`(6 维画像 + 对话抽取 + 持久化) 已在 `main.dart` 接线 | 资料库是**第四支柱**，不替代 W2 的"AI 生成资源" |
| **状态管理** | 纯 `StatefulWidget + setState`，**无** Riverpod / Bloc / Provider | UI 一律 `StatefulWidget`，不复刻 Riverpod 写法 |
| **存储** | Hive + JSON 字符串（`ProfileRepository` 范式）。**Hive typeId 已用到 0-5** | **必须** 复刻 `Box<String>` + 手写 JSON 方案，**严禁** `@HiveType` adapter（会撞 typeId） |
| **LLM 入口** | `DeepSeekService.callTextPrompt(prompt, userText)` + `_extractJson` 容错（见 `learner/services/profile_builder_service.dart`） | 文本类 AI（分类 / 摘要 / 标签）走这套 JSON 范式 |
| **Vision / OCR 入口** | `VolcAiClientService.callVisionPrompt(imageFile, prompt, modelEnv: VOLC_OCR_MODEL_ID)`；`HandwritingOcrService.recognize(Uint8List)` 直连火山 | **图片解析走 Vision API**，不是 DeepSeek 文本 |
| **PDF 渲染基建** | `pdf_viewer_page.dart` 已用 `assets/pdfjs` + webview 注入 pdf.js（PDF→base64） | PDF 文本提取**复用 pdfjs**，零新依赖 |
| **画像结构** | 6 维已实现；`learningHistory` + `knowledgeBase` 来自**行为数据**，不被对话覆盖 | **接入点**：上传 / 复习资料 → 写 `knowledgeBase` 和 `learningHistory` |
| **Agent 接口** | `BaseAgent.run(AgentRequest) → AgentResult`；`Orchestrator.register/dispatch/generateResources` | 新增 `CuratorAgent` 注册进 Orchestrator |
| **tool-calling 范式** | `geogebra_agent_service.dart` 的 `while + tools + onToolCall` 循环 | `CuratorAgent` 可升级为 tool-calling 智能体（增强） |
| **对话主场景** | `ChatHomePage / ChatPage`（走 VivoAiChatService + ModelService） | "对话中提取画像 / 关联资料"在此打通 |
| **依赖缺口** | 有 `file_picker` / `image_picker` / `open_file` / `path_provider`；缺音频录制 / ASR | 见 §10，MVP 几乎零新依赖 |

---

## 2. 模块定位与赛题对标

| 赛题要求 | 资料库如何对标 |
|---|---|
| **多模态大模型**（A1） | PPT/PDF/图片/录音 四模态采集 + 单次大模型调用完成 9 维标签 |
| **数字化教学资源制作**（A1） | 自动分类 / 打标签 / 摘要 / 知识点抽取 = "制作整理" |
| **多智能体协同**（A7） | `CuratorAgent` 接入 Orchestrator，与 explainer/quizzer 协同 |
| **个性化**（①⑥） | 资料行为反哺 6 维画像；分类时注入画像摘要 |
| **学习路径**（③） | 资料的 `knowledgePoints` 喂路径引擎 |
| **效果评估**（⑤） | 资料使用频次 / 覆盖知识点进入评估 |

**差异化亮点**：高校专属（真题带学校 / 年份，形成"清华高数资料库"）、真实痛点闭环、零额外重型依赖。

---

## 3. 整体架构

```
用户上传 (PPT / PDF / 图 / 录音)
        │
        ▼
┌─────────────────────────────────────────┐
│  IngestionService 采集层                  │   lib/library/services/
│  file_picker / image_picker / record     │      ingestion_service.dart
│  → 落盘到 app docs，产出 RawMaterial       │
└──────────────────┬──────────────────────┘
                   ▼
┌─────────────────────────────────────────┐
│  ParsingService 多模态解析层              │
│  PDF→文本(pdfjs)  图片→Vision OCR        │      parsing/*.dart
│  PPT→元数据    录音→ASR(留接口)           │
│  → 产出 extractedText                    │
└──────────────────┬──────────────────────┘
                   ▼
┌─────────────────────────────────────────┐
│  ClassificationService AI 分类层 ★核心    │
│  DeepSeek 一次调用产出:                   │      classification_service.dart
│  {学科, 知识点[], 类型, 学校, 课程,       │
│   年份, 难度, 摘要, 关键概念[]}           │
└──────────────────┬──────────────────────┘
                   ▼
┌─────────────────────────────────────────┐
│  MaterialRepository(Hive Box<String>)     │   独立 box，复刻 ProfileRepository
│  + 关键词 / 标签索引                       │
└──────┬──────────────────────────────────┘
       │                          │
       ▼                          ▼
┌──────────────┐         ┌──────────────────┐
│ CuratorAgent │         │ ProfileFeeder    │
│ (注册进       │         │ 资料行为→画像     │
│  Orchestrator)│        │ knowledgeBase    │
│ 检索 / 答疑 / │         │ + learningHistory│ ← 随学随新
│ 生成讲解      │         └──────────────────┘
└──────────────┘
```

**与现有系统的关系**：
- 资料 `knowledgePoints[]` 是资料库 ↔ 画像 ↔ 出题 ↔ 路径的**枢纽字段**。
- `ResourceType` 增加 `uploadedMaterial`，与 AI 生成的 document/quiz/mindmap 区分。
- 资料详情页"一键生成讲解 / 出题"直接调 `Orchestrator.dispatch(explainer/quizzer)`。

---

## 4. 目录结构

遵循现有 `lib/agents`、`lib/learner` 的分层范式：

```
lib/library/                           ← 新模块根（与 agents/ learner/ 平级）
├── models/
│   ├── study_material.dart            # 原始资料 + 解析内容 + AI 标签 统一模型
│   └── material_tag.dart              # 标签 / 分类结果模型
├── services/
│   ├── ingestion_service.dart         # 采集(选文件 / 拍照 / 录音)
│   ├── parsing/
│   │   ├── pdf_text_extractor.dart    # PDF→文本(复用 pdfjs，移动端降级文件名)
│   │   ├── image_ocr_parser.dart      # 图→文本(VolcAiClientService.callVisionPrompt)
│   │   ├── pptx_parser.dart           # PPT MVP: 元数据(文件名)，赛后解 zip
│   │   └── audio_asr_parser.dart      # 录音 MVP: 存音频，ASR 留接口
│   ├── classification_service.dart    # ★AI 分类(DeepSeek JSON)
│   ├── material_repository.dart       # Hive Box<String> 持久化 + 索引
│   ├── search_service.dart            # 关键词 / 标签检索
│   └── profile_feeder.dart            # 资料行为→画像反哺
├── agents/
│   └── curator_agent.dart             # 资料管家智能体(实现 BaseAgent)
├── prompts/
│   └── classification_prompt.dart     # 分类 / 摘要 System Prompt
└── presentation/
    ├── library_page.dart              # 资料库主页(按高校/课程/标签筛选)
    ├── material_upload_sheet.dart     # 上传入口(4 类资料)
    ├── material_detail_page.dart      # 资料详情 + 预览 + AI 解读
    └── widgets/
        ├── material_grid.dart
        ├── tag_chip_bar.dart
        └── collection_card.dart       # "XX大学·高数" 集合卡
```

同时在 `lib/agents/models/agent_models.dart` 增量扩展：
- `AgentType` 加 `curator`
- `ResourceType` 加 `uploadedMaterial`

---

## 5. 数据模型

### 5.1 `StudyMaterial`

```dart
/// 一份学习资料（用户上传的多模态原始资料）
class StudyMaterial {
  final String id;
  final String title;              // AI 生成标题或文件名

  // —— 原始文件 ——
  final MaterialKind kind;         // pptx / pdf / image / audio
  final String localPath;          // 落盘路径(app docs)
  final int sizeBytes;
  final DateTime uploadedAt;

  // —— 解析产物 ——
  final String extractedText;      // 解析出的纯文本(供检索 / 喂 AI)
  final int pageCount;             // PDF/PPT 页数

  // —— AI 自动标签(ClassificationService 产出) ——
  final String subject;            // 数学/物理/...
  final List<String> knowledgePoints; // ["极限","洛必达法则"]  ← 枢纽字段
  final String materialType;       // 课件/真题/板书/笔记/录音
  final String? university;        // ★高校专属维度
  final String? course;            // 课程(高等数学/线代)
  final String? year;              // 真题年份
  final String difficulty;         // 基础/中等/挑战
  final String summary;            // AI 一句话摘要
  final List<String> keyConcepts;  // 关键概念(建索引)

  // —— 使用行为(反哺画像) ——
  final int openCount;
  final DateTime? lastOpenedAt;

  Map<String, dynamic> toJson();
  factory StudyMaterial.fromJson(Map<String, dynamic>);
  String encode();                 // Hive Box<String> 存储
  static StudyMaterial? tryDecode(String? raw);
}
```

### 5.2 `MaterialKind` 与 `MaterialTags`

```dart
enum MaterialKind { pptx, pdf, image, audio }

/// 分类服务产出的标签集合（与 StudyMaterial 的标签字段一一对应）
class MaterialTags {
  final String subject;
  final List<String> knowledgePoints;
  final String materialType;
  final String? university;
  final String? course;
  final String? year;
  final String difficulty;
  final String summary;
  final List<String> keyConcepts;

  factory MaterialTags.fromJson(Map<String, dynamic>);
}
```

**关键设计**：
- `knowledgePoints[]` 是枢纽——上传的微积分真题标出"极限 / 连续 / 导数"，直接喂 `knowledgeBase` 和路径引擎。
- `university + course + year` 三元组实现"高校专属"，AI 从文件名 / 内容自动识别（如 `2023清华高数期末.pdf`）。
- 持久化与 `LearnerProfile` 同范式：独立 Hive box `study_materials`，`Box<String>` + JSON，零 build_runner。

---

## 6. AI 分类服务（★答辩核心）

完全复刻 `ProfileBuilderService` 的成功模式：`DeepSeekService.callTextPrompt` + 严格 JSON 输出 + `_extractJson` 容错。

```dart
class ClassificationService {
  final DeepSeekService _deepseek = DeepSeekService();

  /// 一次调用完成 分类 + 打标签 + 摘要 + 知识点抽取
  Future<MaterialTags?> classify({
    required MaterialKind kind,
    required String extractedText,
    required String fileName,
    LearnerProfile? profile,   // 有画像时分类更贴合用户场景
  }) async {
    final system = ClassificationPrompt.system;   // 严格 JSON schema
    final user = '文件名:$fileName\n类型:${kind.name}\n'
                '内容摘要:\n${_truncate(extractedText, 6000)}'
                + (profile != null ? '\n学习者画像:\n${profile.toPromptSummary()}' : '');
    final raw = await _deepseek.callTextPrompt(prompt: system, userText: user);
    return MaterialTags.fromJson(_extractJson(raw));  // 复用同一容错器
  }
}
```

**一次调用产出 9 维标签**（学科 / 知识点 / 类型 / 学校 / 课程 / 年份 / 难度 / 摘要 / 关键概念）——答辩时讲"多模态大模型自动整理"最有力的演示点。

---

## 7. 画像反哺闭环

现有架构已留好接口（`learningHistory` + `knowledgeBase` 来自行为数据，不被对话覆盖）：

```
上传微积分真题 ──classify──► knowledgePoints = ["极限","导数"]
                                    │
                    ProfileFeeder.feed(profile, material)
                                    │
            ┌───────────────────────┴───────────────────────┐
            ▼                                               ▼
  knowledgeBase 增补掌握度                          learningHistory 追加
  (KnowledgeMastery: 极限 0.3)                      (HistoryItem: 极限-进行中)
                                    │
                                    ▼
                  ProfileRepository.save()  ← 随学随新生效
                                    │
                                    ▼
        出题 Agent 据薄弱点出题 / 路径引擎调整 / 资料库首页置顶推荐
```

`ProfileFeeder` 把资料的 `knowledgePoints / difficulty / openCount` 转成画像增量，调 `profile.copyWith(...)` 后 `save`——**完全复用现有 copyWith / save**，零侵入。

**反向也通**：用户在 AI 对话里说"我下周高数期末"，`ProfileBuilderService` 增量更新 `learningGoals`，资料库据此把"高数真题"置顶。**双向闭环**。

---

## 8. UI / UX 设计

入口决策：**题目首页加入口卡**（零导航改动）。位置：`main.dart` 现有 `_buildProfileEntry()`（学习画像卡）正下方，两张卡视觉成组，构成"我的学习资产"区。

```
题目首页(QuestionHomePage)
  └─ 新增"我的学习资料库"入口卡(绿系，区别于 GeoChat 蓝系)
            │
            ▼
   ┌─ library_page.dart 资料库主页 ──────────────┐
   │ 顶部: 高校/课程 筛选 chip + 搜索框           │
   │ 横滚: 高校资料集合卡 "清华·高数 (12份)"      │  ← 高校专属视觉
   │ 网格: 资料卡(缩略图/类型角标/标签/AI 摘要)   │
   │ FAB: ➕上传 (弹 material_upload_sheet)       │
   └─────────────────────────────────────────────┘
            │ 上传 sheet: [选PPT][选PDF][拍照][录音]
            ▼
   解析中状态(进度 / AI 正在分类动画) → 自动入库
            │
            ▼
   material_detail_page.dart
     · 文件预览(PDF 用 pdfjs webview / 图片直显 / 录音播放)
     · AI 标签面板(知识点 / 学校 / 课程 / 难度)
     · "基于此资料: [生成讲解][出题][加入路径]" ← 一键调度 Orchestrator
```

---

## 9. 多模态解析深度（决策已定）

**MVP：图片 + PDF 为主，PPT / 录音 MVP**

| 资料类型 | MVP 做法 | 依赖 |
|---|---|---|
| 板书图片 | ✅ 复用 `VolcAiClientService.callVisionPrompt`（VOLC_OCR_MODEL_ID） | 无 |
| 真题 PDF | ✅ 复用 `assets/pdfjs` 抽文本（新写 `pdf_text_extractor`，不改 `pdf_viewer_page`）；移动端降级用文件名 | 无 |
| PPT 课件 | MVP 存文件 + 用文件名喂 AI 分类；赛后用 `archive` 解 zip 增强 | 无 |
| 划重点录音 | MVP 用 `record` 录制存储，标题手填；`audio_asr_parser` 留接口，赛后接火山 ASR（复用 VOLC 账号） | +1(record)，可推迟 |

**修订版依赖结论**：MVP 四类资料**几乎零新依赖**，全部复用项目已有基建。

---

## 10. 依赖清单（零依赖版）

| 资料 | 方案 | 新依赖 |
|---|---|---|
| 板书图片 | 复用 `VolcAiClientService.callVisionPrompt` | **0** |
| 真题 PDF | 复用 `assets/pdfjs` 抽文本 | **0** |
| PPT 课件 | MVP 存元数据 + 文件名分类 | **0** |
| 划重点录音 | `record` 包录制；ASR 留接口 | +1（可推迟到赛后） |

> 不引重型依赖：不上 vector DB（语义检索先 TF-IDF + 关键词），不上 whisper 本地模型。保持 APK 体积可控。

---

## 11. 分阶段落地（融入 4 周计划）

| 阶段 | 并入周次 | 交付 | 价值 |
|---|---|---|---|
| **L1 地基** | W2 并行 | 数据模型 + `MaterialRepository` + Ingestion(图/PDF) + Vision OCR + 入口卡 + `LibraryPage` 空壳 | 跑通"上传→解析→分类→入库→可见" |
| **L2 智能** | W2 后半 | `ClassificationService` + 标签体系 + 资料库主页 UI + 高校集合卡 | ★AI 自动分类演示 |
| **L3 闭环** | W3 | `ProfileFeeder` 画像反哺 + `CuratorAgent` 注册 Orchestrator + 资料详情"一键生成讲解/出题" | 闭环打通 |
| **L4 多模态** | W4 或赛后 | PPT 解析 + 录音 ASR + 语义检索 + tool-calling CuratorAgent | 完整多模态 |

**优先级**：L1→L2→L3 必做（参赛核心），L4 可做 MVP。图片 + PDF + AI 分类三件套，4 周内能做出可演示完整闭环。

---

## 12. 关键接口契约

### 12.1 `MaterialRepository`（复刻 `ProfileRepository`）

```dart
class MaterialRepository {
  MaterialRepository._();
  static final MaterialRepository instance = MaterialRepository._();

  static const String _boxName = 'study_materials';

  Box<String>? _box;
  bool get isReady => _box != null && _box!.isOpen;

  Future<void> init();
  Future<List<StudyMaterial>> loadAll();
  Future<void> save(StudyMaterial m);
  Future<void> delete(String id);
  Future<List<StudyMaterial>> byUniversityCourse(String? uni, String? course);
  Stream<List<StudyMaterial>> watch();   // 供 UI 监听刷新
}
```

### 12.2 `CuratorAgent`（实现 `BaseAgent`）

```dart
class CuratorAgent implements BaseAgent {
  @override AgentType get type => AgentType.curator;
  @override String get name => '资料管家';
  @override String get description => '检索 / 归纳用户上传的学习资料，答疑时引用真实资料';

  @override
  Future<AgentResult> run(AgentRequest request) async {
    // 据 request.topic / userNeed 调 SearchService 检索相关资料
    // 汇总成 AgentResource(type: uploadedMaterial, content: 资料摘要列表)
    // L4 可升级为 tool-calling: search_material / open_material / summarize
  }
}
```

注册：`Orchestrator.instance.register(CuratorAgent())`（`main.dart` 现有 `VisualizerAgent` 注册处旁）。

### 12.3 `agent_models.dart` 扩展

```dart
enum AgentType { ..., curator }       // 加 curator
enum ResourceType { ..., uploadedMaterial }  // 加 uploadedMaterial
```

---

## 13. 答辩亮点

1. **真痛点 + 真多模态**：期末找不到资料是每个学生痛点；PPT/PDF/图/录音四模态命中 A1"多模态大模型"。
2. **AI 自动整理 ≠ 手动建文件夹**：一次大模型调用完成 9 维标签，演示极具冲击力。
3. **高校专属**：真题带学校 / 年份，天然形成"清华高数资料库""北航线代资料库"。
4. **闭环可证**：上传资料 → 反哺画像 → 影响出题 / 路径，数据闭环完整可演示。
5. **架构一致 + 零重型依赖**：复用 BaseAgent / Hive / DeepSeek / pdfjs / VOLC，工程完整度加分。

---

## 14. 风险与对策

| 风险 | 对策 |
|---|---|
| 4 周时间紧 | 优先 L1→L2→L3；L4 录音 / PPT 做 MVP |
| PDF 文本提取在移动端 pdfjs 桥接不稳 | 降级用文件名 + open_file 系统查看器；文本提取失败不阻塞入库 |
| AI 分类 JSON 偶发解析失败 | 复用 `_extractJson` 容错 + 失败回退为"未分类"仍入库 |
| VOLC Vision 配额 / 超时 | 图片解析失败回退为文件名分类；非阻塞 |
| 资料体积膨胀占满存储 | 落盘到 app docs；后续加"仅元数据 / 清理大文件"策略 |
| 老 `UserProfile` 与新 `LearnerProfile` 并存 | 资料库阶段**不动**，高校信息存在资料标签里，赛后统一 |

---

## 附录：调研修正记录（v1.0）

5 处调研发现对设计的影响：
1. PDF 解析改走 pdfjs（已有基建），省掉 `syncfusion_flutter_pdf`。
2. 图片解析明确走 `VolcAiClientService.callVisionPrompt`（Vision API）。
3. `MaterialRepository` 强制 `Box<String>` + JSON（避开 typeId 0-5）。
4. `CuratorAgent` 可升级 tool-calling（借鉴 `geogebra_agent_service`）。
5. 对话集成点 = `ChatHomePage / ChatPage`。
