#!/usr/bin/env bash
set -euo pipefail

: "${JENKINS_URL:?Set JENKINS_URL, e.g. https://jenkins.example.internal}"
: "${JENKINS_USER:?Set JENKINS_USER}"
: "${JENKINS_API_TOKEN:?Set JENKINS_API_TOKEN in the shell environment}"

OUT_DIR="${OUT_DIR:-jenkins-export}"
mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

# API tokens are sent through curl's authenticated request; they are not placed in the URL.
curl --fail --silent --show-error \
  --user "$JENKINS_USER:$JENKINS_API_TOKEN" \
  "$JENKINS_URL/configuration-as-code/export" \
  --output "$OUT_DIR/jenkins-casc-export.yaml"

curl --fail --silent --show-error \
  --user "$JENKINS_USER:$JENKINS_API_TOKEN" \
  "$JENKINS_URL/pluginManager/api/json?depth=1" \
  --output "$OUT_DIR/plugins.json"

python3 - "$OUT_DIR/plugins.json" "$OUT_DIR/plugins.lock.candidate.txt" <<'PY'
import json, sys
source, destination = sys.argv[1:]
with open(source, encoding="utf-8") as f:
    data = json.load(f)
plugins = data.get("plugins", [])
rows = []
for plugin in sorted(plugins, key=lambda p: p.get("shortName", "")):
    name = plugin.get("shortName")
    version = plugin.get("version")
    if name and version:
        rows.append(f"{name}:{version}")
with open(destination, "w", encoding="utf-8") as f:
    f.write("\n".join(rows) + "\n")
print(f"Wrote {len(rows)} plugin pins to {destination}")
PY

chmod 600 "$OUT_DIR"/*
echo "Export complete: $OUT_DIR"
echo "Review files for secrets before sharing or committing. Do not commit API tokens or credentials."
