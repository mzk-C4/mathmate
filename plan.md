服务器上题目数据的存储位置
数据文件
路径：/opt/mathmate/library_questions.json
格式：纯 JSON 文件存储（题库服务零依赖，直接读写这个文件）
大小：约 20 KB，最后更新 2026-07-08 15:26
权限：root:root，0644（只有 root 能写，不要让队员直接改这个文件）
数据路径在服务器代码里是硬编码的（/opt/mathmate/library_server.js:12）：

const DATA_FILE = __dirname + '/library_questions.json';  // __dirname = /opt/mathmate
队员访问题库的标准方式：走 API（推荐）
不要直接读写 JSON 文件，让队员用题库 API：
服务进程：mathmate-library（PM2 id 6）→ 127.0.0.1:3004，当前已在线运行 19h，状态正常
公网入口：https://mathmate.top/api/library/...（Nginx 把 /api/library/ 转发到 3004）
批量导入题目：POST /api/library/questions/batch（灌 questions_*.json 用这个）