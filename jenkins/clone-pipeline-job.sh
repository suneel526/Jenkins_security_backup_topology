#!/usr/bin/env bash
set -euo pipefail

: "${JENKINS_URL:?Set JENKINS_URL}"
: "${JENKINS_USER:?Set JENKINS_USER}"
: "${JENKINS_API_TOKEN:?Set JENKINS_API_TOKEN}"
: "${SOURCE_JOB:?Set SOURCE_JOB to an existing top-level Pipeline job}"
: "${TARGET_JOB:?Set TARGET_JOB to a NEW name, e.g. payment-service-cd}"

if [[ "$SOURCE_JOB" == "$TARGET_JOB" ]]; then
  echo "ERROR: source and target job names must differ." >&2
  exit 1
fi

SOURCE_ENC=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$SOURCE_JOB")
TARGET_ENC=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$TARGET_JOB")
SOURCE_URL="${JENKINS_URL%/}/job/${SOURCE_ENC}"

TARGET_STATUS=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  --user "$JENKINS_USER:$JENKINS_API_TOKEN" \
  "${JENKINS_URL%/}/job/${TARGET_ENC}/api/json")
if [[ "$TARGET_STATUS" == "200" ]]; then
  echo "ERROR: target job '$TARGET_JOB' already exists. Refusing to overwrite." >&2
  exit 1
elif [[ "$TARGET_STATUS" != "404" ]]; then
  echo "ERROR: unable to determine whether target exists (HTTP $TARGET_STATUS). Refusing to continue." >&2
  exit 1
fi

TMP_XML=$(mktemp)
trap 'rm -f "$TMP_XML"' EXIT
curl --fail --silent --show-error \
  --user "$JENKINS_USER:$JENKINS_API_TOKEN" \
  "${SOURCE_URL}/config.xml" --output "$TMP_XML"

# Only copy classic Pipeline jobs. XML is parsed and sanitized before creation:
# - fail closed for other job types;
# - remove trigger definitions so the CD copy cannot inherit CI schedules/webhooks;
# - set disabled=true before Jenkins creates the new item.
SAFE_XML=$(mktemp)
trap 'rm -f "$TMP_XML" "$SAFE_XML"' EXIT
python3 - "$TMP_XML" "$SAFE_XML" <<'PYXML'
import sys
import xml.etree.ElementTree as ET
source, destination = sys.argv[1:]
tree = ET.parse(source)
root = tree.getroot()
if root.tag != "flow-definition":
    raise SystemExit("ERROR: source is not a classic Pipeline flow-definition job")
# Remove top-level and plugin-owned trigger definitions recursively.
for parent in root.iter():
    for child in list(parent):
        local = child.tag.rsplit("}", 1)[-1]
        if local.lower() in {"triggers", "triggersproperty"}:
            parent.remove(child)
disabled = root.find("disabled")
if disabled is None:
    disabled = ET.SubElement(root, "disabled")
disabled.text = "true"
tree.write(destination, encoding="utf-8", xml_declaration=True)
PYXML

curl --fail --silent --show-error \
  --user "$JENKINS_USER:$JENKINS_API_TOKEN" \
  -X POST \
  -H 'Content-Type: application/xml' \
  --data-binary "@$SAFE_XML" \
  "${JENKINS_URL%/}/createItem?name=${TARGET_ENC}"

echo "Created '$TARGET_JOB' from '$SOURCE_JOB' and disabled the new job for review."
echo "The source job was not modified. Review triggers/SCM and set script path to jenkins/Jenkinsfile.cd."
echo "Enable the new job only after its parameters, approvals and deployment permissions are verified."
