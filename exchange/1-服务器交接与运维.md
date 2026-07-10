# MathMate 服务器共同开发交接文档

> 版本 v1.0 · 2026-07-08 · 交接人：马兆坤
> 适用：题库 + 考试功能（组卷/判卷/评估）的共同开发
> 相关文档：`docs/library_api.md`（题库 API 速查）、`docs/exam_system_plan.md`（考试系统设计）

---

## 1. 一句话概览

服务器 `mathmate.top`（阿里云 ECS）已部署**题库 API**（`/api/library/`），本地已搭好**数据生产链路**（MinerU + 切题打标脚本）和 **App 题库骨架**（`lib/exam/`）。你的任务：基于这套基础设施开发**考试三件套**（组卷/判卷/评估）。

---

## 2. 服务器访问

| 项 | 值 |
|---|---|
| 域名 | `mathmate.top` |
| 公网 IP | `47.94.83.150` |
| 系统 | 阿里云 ECS · Ubuntu 22.04 |
| SSH 用户 | `root` |
| SSH 密钥 | `C:/Users/MZK/.ssh/mathmate_server`（**向马兆坤索取该密钥文件**，放到自己 `~/.ssh/`） |

### 连接命令
```bash
ssh -i ~/.ssh/mathmate_server -o StrictHostKeyChecking=no root@mathmate.top
```

### ⚠️ fail2ban 注意（重要）
服务器开了 fail2ban：**短时间多次中断/认证失败的 SSH 连接会触发临时封禁（10–30 分钟自动解除）**。
- 规范：**一次 SSH 会话做完多步操作**（用 `;` 或脚本串联），避免频繁连断
- 不要用密码反复试；务必用密钥
- 部署用脚本（见 §7），一次 scp + 一次 ssh

---

## 3. 服务架构总览

### PM2 服务（`pm2 list`）
| id | name | 端口 | 代码 | 用途 |
|---|---|---|---|---|
| 0 | mathmate-proxy | :3001 | `/opt/mathmate/proxy_server.js` | AI 代理（DeepSeek/Vivo/Volc，密钥在 `.env.server`） |
| 6 | **mathmate-library** | **:3004** | `/opt/mathmate/library_server.js` | **题库 API（本次新增）** |
| 5 | geogebra-chat | :3003 | `/opt/geogebra-chat/` | GeoChat |

> auth_server（:3002）代码在 `/opt/mathmate/auth_server.js`，处理 `/api/auth/`。

### Nginx 路由（`/etc/nginx/sites-enabled/mathmate`）
```
/api/auth/       → :3002
/api/library/    → :3004   ← 本次新增（最长前缀优先，不影响 /api/ 兜底）
/api/            → :3001   （兜底）
/geogebra-chat/  → :3003
/app/  /website/  /  → 静态（官网 + Flutter Web）
```

### 关键目录
```
/opt/mathmate/
├── proxy_server.js          # AI 代理
├── auth_server.js           # 认证
├── library_server.js        # ★ 题库 API（本次新增）
├── library_questions.json   # ★ 题库数据（JSON 文件存储）
├── .env.server              # API 密钥（DeepSeek/Vivo/Volc，勿泄露）
└── package.json
```

题库 API 的本地副本：`deploy/library_server.js`（同 `deploy/proxy_server.js` 风格，纯 Node http，零依赖）。

---

## 4. 题库 API（你的开发核心）

**Base URL**: `https://mathmate.top/api/library`

完整端点 + Schema + curl 示例见 **`docs/library_api.md`**。速查：

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/questions?section=&type=&dmin=&dmax=&q=&page=&limit=` | 列表（过滤+分页） |
| GET | `/questions/:id` | 单题 |
| POST | `/questions` | 新增 |
| POST | `/questions/batch` | **批量导入**（灌 questions_*.json） |
| PUT | `/questions/:id` | 编辑 |
| DELETE | `/questions/:id` | 删除 |
| GET | `/sections` | 板块树+题量 |
| GET | `/stats` | 统计 |
| GET | `/health` | 健康检查 |

当前种子：19 题（2024 新高考 I 卷，覆盖全板块全题型）。

### Question Schema（组卷/判卷要用）
```jsonc
{
  "id":"q_<来源>_<题号>", "subject":"数学",
  "section":"函数与导数",           // 板块枚举见下
  "type":"单选题",                  // 单选/多选/填空/解答
  "content":"题干（含 LaTeX $...$）",
  "options":["A. ..","B. ..",...],  // 选择题；非选择 null
  "answer":"C", "solution":"解析",
  "difficulty":0.55,                // 难度系数 0~1
  "knowledgePoints":["知识点"],
  "source":{"type":"pdf","ref":"2024新高考I卷","qnum":1}
}
```
**板块枚举**：集合与逻辑 / 复数 / 向量 / 三角函数 / 数列 / 函数与导数 / 立体几何 / 解析几何 / 概率统计 / 计数原理 / 不等式 / 其他

### 组卷思路（你要做的）
- `GET /questions?section=解析几何&dmin=0.4&dmax=0.6&type=解答题` → 按规则抽题
- 智能组卷：读学习画像薄弱板块（`lib/learner/`）→ 加权多抽 + 难度贴近 `preferredDifficulty`

---

## 5. 本地数据生产链路（产题灌库）

题从哪来：真题 PDF → MinerU 解析 → 切题 + AI 打标 → 灌云端。

### 5.1 MinerU（PDF → 结构化 Markdown）
已装在本地 Python310（`mineru-3.4.2` + pipeline 全依赖：torch/torchvision/transformers 等）。模型已缓存。

```bash
# 解析一份卷子（pipeline 后端，CPU 可跑）
mineru -p "<pdf路径>" -o "<输出目录>" -b pipeline -m auto -l ch
# 产出：<输出>/<文件名>/auto/main.md（题干+公式LaTeX）+ content_list_v2.json + images/
```
真题 PDF 在：`D:\projects\add\senior high question\`（含 `1917-2025年高考数学真题全编600.pdf` 等）

### 5.2 切题 + AI 打标（Markdown → Question JSON）
脚本：`scripts/question_pipeline/build_questions.py`
```bash
python scripts/question_pipeline/build_questions.py \
  "<parsed .../main.md>" "<来源标记如2024新高考I卷>" "<输出 questions.json>"
```
切题（按题型区+题号）+ 选项提取 + DeepSeek 打标（板块/题型/难度/知识点/答案/解析）→ Question JSON。
依赖：`.env` 里的 `DEEPSEEK_API_KEY/MODEL_ID/BASE_URL`（MathMate 项目根）。

### 5.3 灌库
```bash
curl -X POST https://mathmate.top/api/library/questions/batch \
  -H "Content-Type: application/json" -d @questions_xxx.json
```

### ⚠️ 大 PDF 注意
`1917-2025全编600.pdf` 是 **1291 页**，一次解析会失败（超限）+ CPU 约 10 小时。用 `-s/-e` 分段：
```bash
mineru -p "...600.pdf" -o ".../parsed_600_p1" -b pipeline -m auto -l ch -s 0 -e 100   # 第1-100页
```

---

## 6. App 端结构（Flutter，`lib/exam/`）

已有骨架（参考实现，你在此基础上做组卷/判卷/评估）：

```
lib/exam/
├── models/question.dart           # Question 模型（对应云端 Schema）+ 板块/难度/选项解析
├── services/question_api.dart     # 云端 API 客户端（fetchQuestions/fetchQuestion/sections/stats）
└── pages/question_bank_page.dart  # 题库浏览页（统计/板块筛选/难度筛选/列表/详情）
```
入口：`main.dart` 题库入口卡（`_buildQuestionBankEntry`，画像卡下方）→ `QuestionBankPage`。

### 你要加的（参考 `docs/exam_system_plan.md`）
```
lib/exam/
├── pages/exam_compose_page.dart   # 组卷（规则/智能）
├── pages/exam_page.dart           # 答题（计时/作答）
├── pages/exam_result_page.dart    # 成绩+雷达图
├── services/exam_composer.dart    # 组卷引擎
├── services/grader.dart           # 判卷（客观自动 + 主观 AI）
└── widgets/radar_chart.dart       # 板块掌握度雷达图
```
**画像闭环关键**：判卷结果 → 回写 `lib/learner/` 的 `mastery/weakTopics`（字段已存在但无写入路径）→ 影响下次组卷。见 `docs/exam_system_plan.md` §8。

---

## 7. 协作开发流程（场景）

### 场景 A：改了题库后端（`library_server.js`）
```bash
# 1. 本地改 deploy/library_server.js
# 2. 上传 + 重启（一次 scp + 一次 ssh）
scp -i ~/.ssh/mathmate_server deploy/library_server.js root@mathmate.top:/opt/mathmate/
ssh -i ~/.ssh/mathmate_server root@mathmate.top 'pm2 restart mathmate-library && pm2 save'
```

### 场景 B：改了 Nginx（加路由）
**务必用带备份+测试+回滚的脚本**（参考 `deploy/deploy_library.sh`）：
```bash
# 备份 → 改 → nginx -t → 通过才 reload（失败自动回滚）
cp /etc/nginx/sites-enabled/mathmate /etc/nginx/sites-enabled/mathmate.bak.<日期>
# ...编辑配置...
nginx -t && nginx -s reload || cp <备份> /etc/nginx/sites-enabled/mathmate  # 回滚
```

### 场景 C：产新题灌库
MinerU 解析 → `build_questions.py` 切题打标 → `curl POST .../questions/batch`（见 §5）。

### 场景 D：开发 App 考试功能
改 `lib/exam/` → `flutter build apk --debug` 验证 → 真机/模拟器跑（注意：本机 adb 环境不稳，建议 Android Studio 运行）。

---

## 8. 运维规范

### PM2 常用
```bash
pm2 list                       # 查看服务
pm2 restart mathmate-library   # 重启题库
pm2 logs mathmate-library      # 看日志
pm2 stop mathmate-library      # 停
pm2 save                       # 保存进程列表（开机自启）
```

### 题库数据备份
```bash
ssh root@mathmate.top 'cp /opt/mathmate/library_questions.json /opt/mathmate/library_questions.json.bak.$(date +%Y%m%d)'
```
或本地拉一份：`scp root@mathmate.top:/opt/mathmate/library_questions.json ./`

### Nginx
- 配置：`/etc/nginx/sites-enabled/mathmate`
- 测试：`nginx -t`（改完必测）
- 重载：`nginx -s reload`
- 备份目录：`/etc/nginx/sites-enabled/mathmate.bak.*`

---

## 9. 已知问题 + 注意事项

1. **Nginx `conflicting server name` 警告**：mathmate.top 配置里多个 server 块都声明了 `server_name`（预存老问题），nginx 仍 success、不影响功能。别动它，除非你要重构 Nginx。
2. **题库 API 暂无认证**：内部开发用。上生产前接 `auth_server`(:3002) 的 token（`POST /api/auth/` 那套）。
3. **题库存储是 JSON 文件**：初期千级够用，多人并发写有风险（同时录题可能丢）。题库破万或高频写时迁 SQLite/MySQL（改 `library_server.js` 的 load/save 函数即可，API 不变）。
4. **`/api/` 是兜底路由**：新加 `/api/xxx/` 要放在 `/api/` 前面（或靠最长前缀优先，像 `/api/library/` 那样）。
5. **fail2ban**：SSH 一次做多步，别频繁断连（见 §2）。
6. **MathMate `.env`（本地）vs 服务器 `.env.server`**：本地 `.env` 给 Flutter App + 切题脚本用（DeepSeek key）；服务器 `.env.server` 给 proxy_server 用。两边 key 相同但文件不同。

---

## 10. 参考文档清单

| 文档 | 内容 |
|---|---|
| `docs/handover_server_dev.md` | 本文档（服务器交接） |
| `docs/library_api.md` | 题库 API 速查（端点+Schema+curl） |
| `docs/exam_system_plan.md` | 考试系统设计（组卷/判卷/评估/闭环 + 软件杯对标） |
| `docs/library_module_design.md` | 学习资料库模块设计（上传 PPT/PDF 等） |
| `deploy/library_server.js` | 题库 API 源码 |
| `deploy/deploy_library.sh` | 题库部署脚本（带备份回滚） |
| `scripts/question_pipeline/build_questions.py` | 切题+AI打标脚本 |

---

## 11. 联系
- 交接人：马兆坤
- 出问题先看：`pm2 logs <服务>` + `nginx -t` + `curl https://mathmate.top/api/library/health`
- 部署改动务必先备份（`cp ... .bak.日期`），能回滚
