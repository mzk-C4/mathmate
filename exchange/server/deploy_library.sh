#!/bin/bash
# 部署题库 API：PM2 启动 :3004 + Nginx 加 /api/library/ 路由
# 安全：备份 Nginx 配置 + nginx -t 测试，失败自动回滚（不影响线上 mathmate.top）
CONF=/etc/nginx/sites-enabled/mathmate

echo "===PM2_START==="
pm2 start /opt/mathmate/library_server.js --name mathmate-library 2>&1 || pm2 restart mathmate-library 2>&1
pm2 save 2>&1
sleep 1
echo "===HEALTH_3004==="
curl -s http://localhost:3004/api/library/health || echo "(health failed)"
echo

echo "===NGINX_BACKUP==="
BAK="${CONF}.bak.library_$(date +%Y%m%d_%H%M%S)"
cp "$CONF" "$BAK"
echo "backup: $BAK"

echo "===ADD_LOCATION==="
if grep -q 'location /api/library/' "$CONF"; then
  echo "location /api/library/ already exists, skip"
else
  awk '/location \/api\// && !d {print "    location /api/library/ {\n        proxy_pass http://127.0.0.1:3004;\n        proxy_http_version 1.1;\n        proxy_set_header Host $host;\n    }"; d=1} {print}' "$CONF" > "${CONF}.tmp" && mv "${CONF}.tmp" "$CONF"
  echo "location /api/library/ inserted before /api/"
fi

echo "===NGINX_TEST==="
if nginx -t 2>&1; then
  echo "===NGINX_RELOAD==="
  nginx -s reload 2>&1 && echo "RELOADED OK"
else
  echo "===TEST_FAILED_ROLLBACK==="
  cp "$BAK" "$CONF"
  echo "rolled back to $BAK (mathmate.top NOT affected)"
fi
