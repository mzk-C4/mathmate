#!/usr/bin/env bash
set -euo pipefail

readonly PORT=18001
readonly BACKEND_DIR=/opt/exam_system/backend
readonly PYTHON=/opt/exam_system/.venv/bin/python
readonly PRODUCTION_DB=/opt/exam_system/db/exam_data.json
readonly AUTH_SECRET=/opt/mathmate/auth_secret.txt
readonly SMOKE_SCRIPT=/tmp/mathmate-exam-e2e-smoke.py

if fuser "${PORT}/tcp" >/dev/null 2>&1; then
  echo "Port ${PORT} is already in use; refusing to disturb the existing process." >&2
  exit 1
fi

run_dir="$(mktemp -d /tmp/mathmate-exam-e2e.XXXXXX)"
pid=""

cleanup() {
  exit_code=$?
  if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" 2>/dev/null || true
  fi
  if [[ ${exit_code} -ne 0 && -f "${run_dir}/uvicorn.log" ]]; then
    tail -n 100 "${run_dir}/uvicorn.log" >&2
  fi
  rm -rf -- "${run_dir}"
  exit "${exit_code}"
}
trap cleanup EXIT INT TERM

cp -- "${PRODUCTION_DB}" "${run_dir}/exam_data.json"

cd "${BACKEND_DIR}"
APP_ENV=production \
JSON_DATABASE_PATH="${run_dir}/exam_data.json" \
AUTH_SECRET_PATH="${AUTH_SECRET}" \
AUTH_TOKEN_MAX_AGE_SECONDS=604800 \
"${PYTHON}" -m uvicorn main:app --host 127.0.0.1 --port "${PORT}" \
  >"${run_dir}/uvicorn.log" 2>&1 &
pid=$!

for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PORT}/api/exams/health" >/dev/null; then
    break
  fi
  if ! kill -0 "${pid}" >/dev/null 2>&1; then
    echo "Disposable exam server exited during startup." >&2
    exit 1
  fi
  sleep 0.5
done

curl -fsS "http://127.0.0.1:${PORT}/api/exams/health" >/dev/null

"${PYTHON}" "${SMOKE_SCRIPT}" \
  --base-url "http://127.0.0.1:${PORT}" \
  --public-url "https://mathmate.top" \
  --secret-path "${AUTH_SECRET}" \
  --database-path "${run_dir}/exam_data.json"
