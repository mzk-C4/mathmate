# MathMate 题库 API（已上线）

> Base URL: `https://mathmate.top/api/library`
> 服务：PM2 `mathmate-library`（:3004），Nginx 反代 `/api/library/`
> 存储：JSON 文件（`/opt/mathmate/library_questions.json`），零依赖；后期可迁 SQLite/MySQL
> 代码：服务器 `/opt/mathmate/library_server.js` ＝ 本地 `deploy/library_server.js`
> 部署脚本：`deploy/deploy_library.sh`（带 Nginx 备份+测试+回滚）

## 端点

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/health` | 健康检查 + 题量 |
| GET | `/questions` | 列表（支持过滤+分页，见下） |
| GET | `/questions/:id` | 单题 |
| POST | `/questions` | 新增单题 |
| POST | `/questions/batch` | **批量导入**（传 JSON 数组，灌 `questions_*.json`） |
| PUT | `/questions/:id` | 编辑 |
| DELETE | `/questions/:id` | 删除 |
| GET | `/sections` | 板块树 + 题量 |
| GET | `/stats` | 统计（各板块/题型/难度分布） |

### GET /questions 过滤参数
`section=` `type=` `dmin=` `dmax=` `q=`（关键词搜题干+知识点）`page=` `limit=`

## Question Schema

```jsonc
{
  "id": "q_<来源>_<题号>",          // 不传则自动生成
  "subject": "数学",
  "section": "函数与导数",           // 集合与逻辑/复数/向量/三角函数/数列/函数与导数/立体几何/解析几何/概率统计/计数原理/不等式/其他
  "type": "单选题",                 // 单选题/多选题/填空题/解答题
  "content": "题干（支持 LaTeX，如 $x^2+1$）",
  "options": ["A. ..","B. ..","C. ..","D. .."],  // 选择题；非选择题为 null
  "answer": "C",
  "solution": "解析步骤",
  "difficulty": 0.55,              // 难度系数 0~1
  "knowledgePoints": ["知识点1","知识点2"],
  "source": {"type":"pdf","ref":"2024新高考I卷","qnum":1}
}
```

## curl 示例

```bash
# 列表（函数与导数，中等难度）
curl -s "https://mathmate.top/api/library/questions?section=函数与导数&dmin=0.4&dmax=0.6"

# 统计
curl -s https://mathmate.top/api/library/stats

# 批量导入（灌切题脚本产出的 questions_*.json）
curl -s -X POST https://mathmate.top/api/library/questions/batch \
  -H "Content-Type: application/json" \
  -d @questions_2024.json

# 新增单题
curl -s -X POST https://mathmate.top/api/library/questions \
  -H "Content-Type: application/json" \
  -d '{"subject":"数学","section":"数列","type":"解答题","content":"...","difficulty":0.6,"knowledgePoints":["等差数列"],"answer":"...","solution":"..."}'
```

## 数据生产链路（题从哪来）

```
真题 PDF (senior high question/)
  → MinerU 解析 (mineru -p x.pdf -o out -b pipeline -m auto -l ch)
  → main.md (题干 + 公式 LaTeX)
  → 切题 + DeepSeek 打标 (scripts/question_pipeline/build_questions.py)
  → questions_*.json
  → POST /api/library/questions/batch  (本文档 API)
```

## 备注
- 暂未加认证（内部开发用）。上生产前接 `auth_server`(:3002) 的 token。
- Nginx 配置备份：`/etc/nginx/sites-enabled/mathmate.bak.library_*`
