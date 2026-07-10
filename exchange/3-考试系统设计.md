# MathMate 考试系统 + 云端题库 建设计划

> 版本 v1.0 · 2026-07-08 · 目标：题库上云多人协作 + 考试（组卷/判卷/评估）闭环
>
> 决策（已确认）：① 题库来源 = 自有题库录入 + 真题 PDF 抽题 + add 开源数据打标；② 云端复用 mathmate.top Node 后端；③ 协作 = 共录内容 + 共写代码 + 多端共享

---

## 0. 一句话目标

建一个**云端共享题库**（按板块/难度系数标准化），App 端做**组卷→答题→判卷→评估**闭环，判卷结果回写学习画像的 `mastery`，激活整条「学习智能体」链路。多人员通过同一 API 共录题库、多端共享。

---

## 1. 现状基线（决定哪些从零、哪些复用）

| 能力 | 状态 | 复用方式 |
|---|---|---|
| 多智能体框架 / 解题 / 可视化 | ✅ 已实现 | 组卷/判卷包成 Agent 接 Orchestrator |
| 学习画像 `mastery`/`weakTopics`/`preferredDifficulty` | ⚠️ 字段已存在**但无代码写入** | 考试判卷结果回写，激活闭环 |
| 题库(Question/Repository) / 组卷 / 判卷 / 评估 / 雷达图 | ❌ 完全没有 | 从零建 |
| 出题 Agent(quizzer) | ❌ 仅枚举占位 | 新建 `QuizzerAgent` |
| 云端 mathmate.top | ✅ Node(:3001)+auth(:3002)+Nginx+PM2 | 加题库 API |

**add 文件夹现实（已核实）**：
- ★ **真实中文真题（核心数据源）**：
  - `add/senior high question/1917-2025年高考数学真题全编600.pdf`（15.5MB，600 道高考真题，1917-2025）
  - `add/senior high question/2024新高考I卷数学/`（含 `main.tex` LaTeX 源 + 试卷 PDF/JPG，**已结构化**，可直接转题目）
- ★ **抽题工具**：`add/mineru/`（MinerU 源码，PDF→结构化 Markdown/JSON，公式→LaTeX，版面/表格识别，支持扫描件）
- 开源英文数据集（辅助语料）：`ToRA/examples.jsonl`、`mathematics_dataset/`

真题 PDF 是中文、有年份，但**无板块/难度系数标签** → 用 MinerU 解析成结构化文本（题干+公式 LaTeX）→ AI 打标（板块/难度/知识点）→ 入库。

---

## 2. 整体架构

```
   数据来源                              云端 mathmate.top                    App 多端
 ┌───────────────┐                ┌─────────────────────────┐         ┌──────────────┐
 │ 自有题库Excel │──批量导入──┐   │  题库 API  /api/library/ │         │  题库浏览    │
 │ 真题 PDF      │──OCR抽题──┼──▶│  (Node, 复用 :3001 或新  │◀──────▶│  组卷        │
 │ AI 生成       │───────────┤    │   起 :3004)              │         │  答题/判卷   │
 │ add 开源数据  │──打标─────┘    │         │                 │         │  评估雷达图  │
 └───────────────┘                │  MySQL/Postgres 题库表   │         └──────┬───────┘
        多人协作录入 ──认证──▶    │  auth_server(:3002) 复用 │                │
                                  └─────────────────────────┘         判卷结果
                                                                         │
                                                          回写 mastery/weakTopics
                                                                         ▼
                                                              画像闭环 → 路径调整
```

---

## 3. 数据模型：Question Schema（核心）

```jsonc
{
  "id": "q_<timestamp>",
  "subject": "数学",
  "section": "解析几何",          // ★板块（枚举，见 §4）
  "subsection": "椭圆",           // 子板块（可选）
  "type": "解答题",               // 选择 / 填空 / 解答
  "options": null,                // 选择题: ["A. ..","B. ..","C. ..","D. .."]
  "content": "已知椭圆 ... 求离心率",  // 题干，支持 LaTeX/Markdown
  "answer": "e = 1/2",            // 标准答案
  "solution": "由 a²=b²+c² ... ",  // 解析步骤
  "difficulty": 0.65,             // ★难度系数 0~1（越高越难）
  "knowledgePoints": ["椭圆方程","离心率"],
  "source": {
    "type": "manual | pdf | ai | dataset",  // 录入/抽题/生成/开源
    "ref": "ToRA/examples.jsonl:L1234"      // 溯源
  },
  "meta": { "year": 2024, "university": "清华大学", "examType": "期末" },
  "createdAt": "2026-07-08T...",
  "createdBy": "u_<userId>",      // 协作：谁录的
  "verified": false               // 协作：是否已人工校验
}
```

**组卷相关派生模型**：
- `ExamPaper`：`{id, name, questions[], rules, createdBy, createdAt}` —— 一份卷子
- `ExamResult`：`{id, paperId, userId, answers{}, scores{}, totalScore, duration, submittedAt}` —— 答卷

---

## 4. 板块枚举 + 难度系数定义

**高中数学板块**（标准化，可按你校课程调）：
```
函数 / 导数 / 三角函数 / 数列 / 立体几何 / 解析几何 / 概率统计 / 向量 / 不等式 / 集合与逻辑 / 复数 / 计数原理
```
每个板块下可挂子板块（如 解析几何 → 直线/圆/椭圆/双曲线/抛物线）。

**难度系数 0~1**（教育测量学惯例，越低越难）：
- `[0.0, 0.3]` 基础 / `[0.3, 0.6]` 中等 / `[0.6, 0.8]` 较难 / `[0.8, 1.0]` 挑战
- 组卷规则示例："解几 3 题（难度 0.4-0.6）+ 导数 2 题（0.5-0.7）+ ..."

---

## 5. 云端方案（复用 mathmate.top）

### 5.1 部署
- **推荐**：在现有 `mathmate-proxy`（:3001，`/opt/mathmate/proxy_server.js`）里**加题库路由**，挂 Nginx `/api/library/`。最快，复用现有认证/HTTPS/PM2。
- 备选：新起 `mathmate-library`（:3004）独立微服务，Nginx 加 `/api/library/ → :3004`。

### 5.2 API（REST，复用 auth_server 的 token）
```
题库 CRUD
  GET    /api/library/questions?section=&difficulty=&type=&kp=&q=&page=
  GET    /api/library/questions/:id
  POST   /api/library/questions            (单题新增，需认证)
  PUT    /api/library/questions/:id        (编辑，记操作日志)
  DELETE /api/library/questions/:id
  POST   /api/library/questions/batch      (批量导入 Excel/JSON)

数据导入
  POST   /api/library/import/pdf           (上传PDF → OCR+AI抽题 → 返回候选题)
  POST   /api/library/import/dataset       (add开源数据 → AI打标 → 入库)
  POST   /api/library/tag/:id              (AI 给单题打 板块/难度/知识点)

考试
  POST   /api/library/exams/compose        (按规则组卷 → 返回 ExamPaper)
  POST   /api/library/exams/:id/submit     (提交答卷 → 判分 → 返回 ExamResult)

元数据
  GET    /api/library/sections             (板块树)
  GET    /api/library/stats                (题库统计：各板块题量/难度分布)
```

### 5.3 存储
- **起步**：SQLite（`/opt/mathmate/data/library.db`）——单服务器、零运维、题库千级够用。
- **扩容**：上 MySQL/Postgres（题库破万或多人高频写时再迁）。

### 5.4 协作
- 复用 auth_server 的用户 token，每题记 `createdBy`；`verified` 字段标记人工校验。
- 操作日志表（谁改了哪题），便于团队协作审计。

---

## 6. 数据导入（三来源 → 云端题库）

| 来源 | 工序 | 工具 |
|---|---|---|
| **自有题库**（Excel/Word） | 解析 → 映射字段 → `POST /batch` | 服务端解析脚本 + Web/App 录入页 |
| **真题 PDF**（senior high question 600题等） | **MinerU 解析**（PDF→Markdown，公式→LaTeX，识别题号/版面）→ 按题切分 → AI 打标(板块/难度/知识点) → 入库 | `add/mineru/`（CLI/Python SDK）；打标复用 DeepSeek |
| **add 开源数据** | 选筛选(数学相关) → AI 翻译/打标/赋难度系数 → 入库 | 导入脚本调 `/import/dataset`；ToRA 的 `level`→难度、`gt_cot`→解析 可直接映射 |

> add 数据打标 Prompt 范式复用 `classification_prompt.dart`：一次调用产出 `{section, subsection, difficulty, knowledgePoints, type}`。

---

## 7. App 端模块（Flutter，新增 `lib/exam/`）

```
lib/exam/
├── models/
│   ├── question.dart              # Question + ExamPaper + ExamResult
│   └── section.dart               # 板块枚举 + 难度档
├── services/
│   ├── question_api.dart          # 云端题库 API 客户端(dio/http)
│   ├── question_repository.dart   # 本地缓存(Hive) + 云端同步
│   ├── exam_composer.dart         # 组卷引擎(按规则/按画像)
│   └── grader.dart                # 判卷(客观自动 + 主观AI)
├── agents/
│   ├── quizzer_agent.dart         # AI 出题(实现 BaseAgent，注册 Orchestrator)
│   └── grader_agent.dart          # AI 判主观题(可选)
├── pages/
│   ├── question_bank_page.dart    # 题库浏览(板块/难度筛选+搜索)
│   ├── exam_compose_page.dart     # 组卷(规则配置 / 智能组卷)
│   ├── exam_page.dart             # 答题(计时/作答/交卷)
│   └── exam_result_page.dart      # 成绩+雷达图+错题
└── widgets/
    ├── radar_chart.dart           # 板块掌握度雷达图(自绘 CustomPainter)
    ├── difficulty_dist_chart.dart # 难度分布
    └── question_card.dart
```

**资料库联动**：`lib/library/` 的资料详情页加「抽题入库」按钮 → 调云端 `/import/pdf`。

---

## 8. 组卷 / 判卷 / 评估 细节

### 组卷（ExamComposer）
- **规则组卷**：用户选「板块×难度×题量×题型」→ 服务端按 `difficulty` 区间随机抽题。
- **智能组卷**：读画像 `weakTopics` + `mastery` 低的板块 → 加权多抽 + 难度贴近 `preferredDifficulty`。
- **手动组卷**：题库浏览页勾选题目 → 生成卷。

### 判卷（Grader）
- **客观题**（选择/填空）：答案标准化后字符串/数值比对，自动判分。
- **主观题**（解答）：调 `SolverService`/DeepSeek，比对关键步骤 + 给分 + 补解析；AI 不确定时标记「待人工复核」。

### 评估（ExamResultPage + 雷达图）
- 板块掌握度雷达图（各板块本次得分率 / 历史均值）。
- 薄弱点列表（低分板块 + 错题知识点）。
- **闭环**：`ProfileFeeder.feedExamResult()` 把各板块得分率转成 `KnowledgeMastery` 增量，`profile.copyWith` + `save` → 下次组卷/路径据此调整。

---

## 9. 分阶段落地

| 阶段 | 交付 | 验收 |
|---|---|---|
| **P1 题库地基+云端** | Question Schema + 云端 API(CRUD+batch+sections) + SQLite + App 题库浏览页 + add 数据打标导入跑通1条链 | 能在 App 看到从 add 导入的题、按板块/难度筛选 |
| **P2 组卷+答题+客观判卷** | 组卷引擎 + 答题 UI + 客观题自动判分 + 成绩页 | 能组一份卷、答题、出客观题分数 |
| **P3 主观判卷+评估闭环** | AI 判主观题 + 雷达图 + mastery 回写闭环 | 判卷后画像 mastery 更新、雷达图可见 |
| **P4 协作+多端** | 多用户认证 + 成绩汇总 + 共录优化(操作日志/校验) + 真题PDF抽题入库 | 多人共录、多端做题成绩汇总 |

> P1 最关键（地基），建议先做。每个阶段完成构建 APK 真机验收。

---

## 10. 软件杯对标

| 赛题要求 | 本系统对标 |
|---|---|
| 多智能体协同 | QuizzerAgent(出题) + GraderAgent(判卷) 接 Orchestrator |
| 个性化 | 按画像薄弱点/难度偏好智能组卷 |
| 学习效果评估(加分) | 雷达图 + mastery 闭环 |
| 多模态(加分) | 真题 PDF OCR 抽题 |
| 对话式画像 | 判卷结果增量更新画像 |

---

## 11. 风险与对策

| 风险 | 对策 |
|---|---|
| add 开源数据英文+无板块 | AI 打标工序；优先用 mathematics_dataset 生成器产出中文题 |
| 主观题 AI 判分不准 | 关键步骤比对 + 不确定标记「待复核」；不阻塞客观分 |
| 云端多人并发写冲突 | 操作日志 + `verified` 校验字段；后期加锁/版本 |
| 题库初期为空 | P1 先导入 add 打标数据 + 自有几份真题起底 |
| 数学公式渲染 | 复用项目现有 flutter_markdown_plus + LaTeX 方案 |

---

## 附录：下一步动作

1. **先确认板块枚举**（§4）是否符合你校课程 —— 你定。
2. **P1 启动**：先定 Schema + 起云端 API 骨架（在 proxy_server.js 加 `/api/library/` + SQLite）+ App 题库浏览页。add 数据打标导入脚本同步写。
3. 每阶段交付 APK 真机验收（参照资料库模块的 build→install 流程）。
