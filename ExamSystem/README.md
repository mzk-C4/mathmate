# MathMate ExamSystem

ExamSystem 是一个可独立运行、可接入 Flutter 的智能考试与评估模块，采用 FastAPI + JSON 文件存储。Flutter 客户端只通过 HTTP API 访问后端，不直接读写 JSON 文件。

## 功能

- JSON 文件题库管理
- 按板块、难度、题型随机组卷
- 选择题规则判分
- 填空题规则优先，大模型辅助
- 简答题大模型评分
- 图片答案上传与 OCR 接入点
- 保存答题记录和题目快照
- 生成总分、正确率、板块分析、错题报告

## 目录

```text
ExamSystem/
├── README.md
├── .env.example
├── docker-compose.yml
├── backend/
│   ├── main.py
│   ├── config.py
│   ├── database.py
│   ├── routers/
│   ├── services/
│   └── requirements.txt
├── db/
│   └── exam_data.json
└── flutter_client_example/
    ├── exam_api.dart
    ├── exam_page.dart
    └── result_page.dart
```

## 配置 JSON 数据库

复制环境变量文件：

```bash
cd ExamSystem
cp .env.example .env
```

修改 `.env`：

```env
JSON_DATABASE_PATH=db/exam_data.json
```

默认路径是相对于 `ExamSystem/` 的 `db/exam_data.json`。你也可以改成绝对路径：

```env
JSON_DATABASE_PATH=/Users/yourname/data/mathmate_exam_data.json
```

## JSON 数据结构

`db/exam_data.json` 内包含：

```text
counters        自增 ID 计数器
questions       题库
exams           考试记录
exam_questions  考试题目关联
answer_records  答题记录和题目快照
grading_logs    大模型评分日志
```

这个文件可以直接查看、复制和备份。服务运行时会写入考试和答题记录，建议不要在后端运行中手动编辑同一个文件。

## 启动后端

```bash
cd ExamSystem/backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload
```

默认地址：

```text
http://localhost:8000
```

健康检查：

```bash
curl http://localhost:8000/health
```

接口文档：

```text
http://localhost:8000/docs
```

## 配置大模型 API

在 `ExamSystem/.env` 中填写：

```env
LLM_API_KEY=your_api_key
LLM_BASE_URL=https://api.example.com/v1
LLM_MODEL=your_model_name
```

后端按 OpenAI-compatible `chat/completions` 协议调用。未配置 `LLM_API_KEY` 时，简答题和无法规则判断的填空题会使用本地保守兜底判分，便于本地开发。

## API 示例

创建考试：

```bash
curl -X POST http://localhost:8000/api/exams/create \
  -H 'Content-Type: application/json' \
  -d '{
    "student_id": "student_001",
    "title": "解析几何测试",
    "total_count": 3,
    "question_types": ["choice", "blank", "short_answer"]
  }'
```

提交答案：

```bash
curl -X POST http://localhost:8000/api/exams/submit-answer \
  -H 'Content-Type: application/json' \
  -d '{
    "exam_id": 1,
    "student_id": "student_001",
    "question_id": 1,
    "student_answer": "B"
  }'
```

完成考试并获取报告：

```bash
curl -X POST http://localhost:8000/api/exams/finish \
  -H 'Content-Type: application/json' \
  -d '{
    "exam_id": 1,
    "student_id": "student_001"
  }'
```

## Flutter 接入

示例代码在 `flutter_client_example/`。主项目已包含 `http` 依赖，可直接复用 `ExamApi`：

```dart
final api = ExamApi(baseUrl: 'http://localhost:8000');
```

真机调试时，手机上的 `localhost` 指手机本机，需要改成电脑局域网 IP：

```dart
final api = ExamApi(baseUrl: 'http://192.168.1.10:8000');
```

## 数据快照策略

`answer_records` 会保存题目内容、标准答案、解析、难度、板块和题型快照。这样题库后续修改后，历史考试记录仍能还原当时的作答上下文。

## 从 JSON 升级到数据库

当前版本优先服务本地开发和小规模使用。如果后续需要多用户并发、权限管理、复杂查询或云端部署，可以把 `db/exam_data.json` 中的数组迁移到 PostgreSQL、SQLite 或其他数据库。API 层已经和存储层隔离，迁移时主要替换 `backend/database.py`。

## 后续扩展

- Excel / CSV 批量导入题库
- 教师后台和学生账号体系
- 教师复核大模型评分
- 错题本和薄弱板块推荐练习
- 考试计时和试卷模板
- OCR 供应商实现
