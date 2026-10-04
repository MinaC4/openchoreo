#!/usr/bin/env bash
set -euo pipefail

# Provision one local OpenChoreo/Thunder user without putting a password in Git.
# The password is read from OPENCHOREO_PASSWORD or from the terminal prompt and
# is converted locally to Thunder's PBKDF2-HMAC-SHA256 credential format.

KUBE_CONTEXT="${KUBE_CONTEXT:-k3d-openchoreo}"
NAMESPACE="${THUNDER_NAMESPACE:-thunder}"
USERNAME="${OPENCHOREO_USERNAME:-marshal@openchoreo.dev}"
GIVEN_NAME="${OPENCHOREO_GIVEN_NAME:-Marshal}"
FAMILY_NAME="${OPENCHOREO_FAMILY_NAME:-User}"
EMAIL="${OPENCHOREO_EMAIL:-$USERNAME}"
ENTITY_ID="${OPENCHOREO_ENTITY_ID:-01900000-0000-7000-8001-000000000034}"
DEPLOYMENT_ID="default-deployment"
OU_ID="01900000-0000-7000-8000-000000000001"

if [[ -z "${OPENCHOREO_PASSWORD:-}" ]]; then
  read -r -s -p "OpenChoreo password for ${USERNAME}: " OPENCHOREO_PASSWORD
  printf '\n' >&2
fi
[[ -n "$OPENCHOREO_PASSWORD" ]] || { echo "Password must not be empty." >&2; exit 1; }

SQL="$({ \
  OPENCHOREO_USERNAME="$USERNAME" \
  OPENCHOREO_PASSWORD="$OPENCHOREO_PASSWORD" \
  OPENCHOREO_GIVEN_NAME="$GIVEN_NAME" \
  OPENCHOREO_FAMILY_NAME="$FAMILY_NAME" \
  OPENCHOREO_EMAIL="$EMAIL" \
  OPENCHOREO_ENTITY_ID="$ENTITY_ID" \
  python3 - <<'PY'
import datetime
import hashlib
import json
import os
import secrets

salt = secrets.token_bytes(16)
password_hash = hashlib.pbkdf2_hmac(
    "sha256", os.environ["OPENCHOREO_PASSWORD"].encode(), salt, 600000, 32
)
attributes = {
    "email": os.environ["OPENCHOREO_EMAIL"],
    "family_name": os.environ["OPENCHOREO_FAMILY_NAME"],
    "given_name": os.environ["OPENCHOREO_GIVEN_NAME"],
    "username": os.environ["OPENCHOREO_USERNAME"],
}
credentials = {
    "storageAlgo": "PBKDF2",
    "additional": {"iterations": 600000, "keySize": 32, "memory": 0, "parallelism": 0},
    "salt": salt.hex(),
    "hash": password_hash.hex(),
    "type": "PASSWORD",
}

def sql(value):
    return "'" + value.replace("'", "''") + "'"

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S +0000 UTC")
row = [
    os.environ["OPENCHOREO_ENTITY_ID"], "user", "openchoreo-user", "ACTIVE",
    "01900000-0000-7000-8000-000000000001", json.dumps(attributes, separators=(",", ":")),
    "{}", json.dumps(credentials, separators=(",", ":")), "{}", now, now,
]
print("BEGIN;")
print("DELETE FROM ENTITY_IDENTIFIER WHERE DEPLOYMENT_ID='default-deployment' AND ENTITY_ID=" + sql(os.environ["OPENCHOREO_ENTITY_ID"]) + ";")
print("DELETE FROM ENTITY WHERE DEPLOYMENT_ID='default-deployment' AND ID=" + sql(os.environ["OPENCHOREO_ENTITY_ID"]) + ";")
print("INSERT INTO ENTITY (DEPLOYMENT_ID,ID,CATEGORY,TYPE,STATE,OU_ID,ATTRIBUTES,SYSTEM_ATTRIBUTES,CREDENTIALS,SYSTEM_CREDENTIALS,CREATED_AT,UPDATED_AT) VALUES (" + ",".join(sql(x) for x in ["default-deployment"] + row) + ");")
for name in ("username", "email"):
    print("INSERT INTO ENTITY_IDENTIFIER (DEPLOYMENT_ID,ENTITY_ID,NAME,VALUE,SOURCE,CREATED_AT) VALUES (" + ",".join(sql(x) for x in ["default-deployment", os.environ["OPENCHOREO_ENTITY_ID"], name, attributes[name], "", now]) + ");")
print("COMMIT;")
PY
})"

printf '%s\n' "$SQL" | kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" exec -i deploy/thunder-deployment -- sqlite3 /opt/thunderid/database/entitydb.db
unset OPENCHOREO_PASSWORD
echo "Provisioned ${USERNAME} in Thunder (entity ${ENTITY_ID})."
