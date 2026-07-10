# MathMate 服务器共同开发交接包

> 交接人：马兆坤 · 2026-07-08
> 给队友的完整交接资料，自包含。你基于这套基础设施开发**考试三件套**（组卷/判卷/评估）。

---

## 这是什么

MathMate「题库 + 考试」功能的开发基础设施，已经搭好并上线：

- ✅ **云端题库 API** 已部署：`https://mathmate.top/api/library/`（**1083 题**，全 12 板块覆盖：函数与导数196/解析几何181/立体几何142/三角函数126/概率统计105/数列85/集合与逻辑60/复数49/向量49/不等式38/计数原理30/其他22；题型 单选483/多选41/填空256/解答303；难度 基础93/中等669/较难320）
- ✅ **本地数据生产链路**：MinerU（PDF→Markdown）+ 切题打标脚本 → 灌库
- ✅ **App 题库骨架**：Flutter `lib/exam/`（模型 + API 客户端 + 浏览页）
- ✅ **完整文档**：服务器运维、API、考试设计、资料库设计

你的任务：在此基础上做**组卷 / 判卷 / 评估（雷达图）**，并把判卷结果回写学习画像（闭环）。详见 `3-考试系统设计.md`。

---

## 📖 阅读顺序（先看这个）

1. **本 README**（整体认知）
2. `1-服务器交接与运维.md`（怎么连服务器 + 架构 + 运维规范）
3. `2-题库API文档.md`（题库 API 怎么用）
4. `3-考试系统设计.md`（你要做的考试功能规划 + 软件杯对标）

---

## 📂 文件夹结构

```
exchange/
├── README.md                       ← 本文件（总导航）
├── 1-服务器交接与运维.md           ← SSH/PM2/Nginx/运维/已知问题
├── 2-题库API文档.md                ← 题库 API 端点+Schema+curl
├── 3-考试系统设计.md               ← 组卷/判卷/评估/闭环设计
├── 4-资料库模块设计.md             ← 学习资料库（PPT/PDF上传）设计
├── server/                         ← 后端源码
│   ├── library_server.js           ← 题库 API（纯node+JSON存储，零依赖）
│   ├── deploy_library.sh           ← 部署脚本（带 Nginx 备份+测试+回滚）
│   └── proxy_server.js             ← AI 代理（现有风格参考）
├── scripts/
│   └── build_questions.py          ← 切题+DeepSeek打标脚本
├── app/                            ← App 题库骨架（Flutter）
│   ├── question.dart               ← Question 模型
│   ├── question_api.dart           ← 云端 API 客户端
│   └── question_bank_page.dart     ← 题库浏览页（筛选/列表/详情）
└── data/
    └── questions_2024.json         ← 种子数据样例（19 题，2024新高考I卷）
```

---

## 🚀 快速开始

```bash
# 1. 找马兆坤要 SSH 密钥 mathmate_server，放到 ~/.ssh/
# 2. 连服务器
ssh -i ~/.ssh/mathmate_server root@mathmate.top

# 3. 看题库现状
curl -s https://mathmate.top/api/library/stats
# → {"total":19, "bySection":{...}, "byType":{...}, "byDiff":{...}}

# 4. 列题（按板块+难度过滤，组卷用）
curl -s "https://mathmate.top/api/library/questions?section=函数与导数&dmin=0.4&dmax=0.6"
```

---

## ⚠️ 关键提醒（必读）

1. **SSH 密钥找马兆坤索取**——不在本包里（密钥不进文档/代码库）。放自己 `~/.ssh/mathmate_server`。
2. **服务器 fail2ban**：SSH 一次会话做完多步（用 `;` 或脚本串联），**别频繁断连**，否则触发 10–30 分钟封禁。
3. **题库 API 暂无认证**（内部开发用）。上生产前接 `auth_server`(:3002)。
4. **改 Nginx 务必备份 + `nginx -t` + 失败回滚**（参考 `server/deploy_library.sh`）。
5. **本地产题依赖**：MinerU（`pip install "mineru[pipeline]"` + torch）+ `.env` 里的 `DEEPSEEK_API_KEY`（向马兆坤要）。
6. **大 PDF**（如 600 题真题 1291 页）用 `mineru -s/-e` 分段解析，别一次跑。

---

## 🎯 考试三件套（已上线）

考试 API 已移植到 Node `library_server.js` 并部署云端（`https://mathmate.top/api/library/exams/`）：

| API | 功能 |
|---|---|
| `POST /exams/compose` | 组卷（按板块/难度/题型随机抽题） |
| `GET /exams/:id` | 考试详情（题目列表） |
| `POST /exams/submit-answer` | 判分（选择题规则比对 / 填空规则+LLM / 简答 DeepSeek AI） |
| `POST /exams/finish` | 报告（总分/正确率/板块分析/错题列表） |

Flutter 考试页已接云端 API：
- `app/exam_api.dart` — ExamApi 客户端（baseUrl=`https://mathmate.top/api/library`）
- `app/exam_taking_page.dart` — 答题页（组卷→作答→判分→交卷）
- `app/exam_result_page.dart` — 报告页（总分/正确率/板块分析/错题回顾）
- main.dart 有"智能测试"入口卡（紫色调，题库入口卡下方）

**队员可扩展**：智能组卷（读 `lib/learner/` 画像薄弱点加权抽题）、雷达图可视化、判卷结果回写画像 `mastery` 闭环。

---

## 📞 出问题先看
- `pm2 logs mathmate-library`（题库日志）
- `nginx -t`（Nginx 配置）
- `curl https://mathmate.top/api/library/health`（API 存活）
- 交接人：马兆坤
