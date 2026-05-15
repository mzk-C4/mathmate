import os
import requests
from pathlib import Path
from datetime import datetime

API_KEY = "sk-7d21e797a5b54b89a29c6fc864f0899b"
API_URL = "https://api.deepseek.com/chat/completions"
MODEL = "deepseek-v4-flash"

main_version = "1.9"
sub_version = "1.9.0"
current_tag = "v1.9.0"

update_date = datetime.now().strftime("%Y-%m-%d")

with open("commit_diff.txt", "r", encoding="utf-8") as f:
    commit_content = f.read().strip()

with open(".github/workflows/scripts/template.txt", "r", encoding="utf-8") as f:
    template = f.read().strip()

prompt = template.format(
    main_version=main_version,
    sub_version=sub_version,
    current_tag=current_tag,
    update_date=update_date,
    commit_content=commit_content
)

headers = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}
body = {
    "model": MODEL,
    "messages": [
        {"role": "user", "content": prompt}
    ],
    "temperature": 0.3
}

resp = requests.post(API_URL, json=body, headers=headers, timeout=60)
resp.raise_for_status()
result = resp.json()
changelog_md = result["choices"][0]["message"]["content"]

save_dir = Path(f"doc/Changelogs/{main_version}/{sub_version}")
save_dir.mkdir(parents=True, exist_ok=True)

save_path = save_dir / "App.md"
with open(save_path, "w", encoding="utf-8") as f:
    f.write(changelog_md)

print(f"Changelog 已生成完毕，路径：{save_path}")
