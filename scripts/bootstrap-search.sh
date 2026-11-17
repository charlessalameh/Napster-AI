#!/usr/bin/env bash
# After `terraform apply`: upload the school documents, then create the AI Search
# data source, skillset, index and indexer through the REST API (azurerm cannot manage
# these), and wait until the indexer has finished. Safe to re-run (PUT = create or update).
#
# Auth: your `az login` (or the GitHub Actions OIDC login). No keys are used anywhere.
# Settings come from the environment, or, if unset, from `terraform output` in ../infra.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_VERSION="2026-04-01"

# Read a setting from the environment, else from terraform output.
tf() {
  local var="$1" out="$2"
  if [[ -n "${!var:-}" ]]; then echo "${!var}"; else terraform -chdir="$ROOT/infra" output -raw "$out"; fi
}

STORAGE_ACCOUNT="$(tf STORAGE_ACCOUNT storage_account_name)"
DOCS_CONTAINER="$(tf DOCS_CONTAINER docs_container_name)"
SEARCH_ENDPOINT="$(tf SEARCH_ENDPOINT search_endpoint)"
INDEX_NAME="$(tf INDEX_NAME search_index_name)"
EMBEDDING_DEPLOYMENT="$(tf EMBEDDING_DEPLOYMENT embedding_deployment_name)"
EMBEDDING_MODEL="$(tf EMBEDDING_MODEL embedding_model_name)"
OPENAI_ENDPOINT="$(tf OPENAI_ENDPOINT openai_endpoint)"
OPENAI_ENDPOINT="${OPENAI_ENDPOINT%/}" # no trailing slash
STORAGE_ACCOUNT_ID="$(az storage account show --name "$STORAGE_ACCOUNT" --query id -o tsv)"

echo "Search:  $SEARCH_ENDPOINT   Index: $INDEX_NAME"

# 1. Upload the documents (Entra ID auth, no account key).
echo "Uploading documents to $STORAGE_ACCOUNT/$DOCS_CONTAINER ..."
retry() { # role assignments can take a few minutes to take effect: retry on failure
  local n=0
  until "$@"; do
    n=$((n + 1))
    if [[ $n -ge 12 ]]; then echo "Giving up after $n attempts" >&2; return 1; fi
    echo "  not ready yet (permissions still propagating?), retry $n/12 in 20 s ..."
    sleep 20
  done
}
retry az storage blob upload-batch --account-name "$STORAGE_ACCOUNT" --auth-mode login \
  --destination "$DOCS_CONTAINER" --source "$ROOT/data/school-docs" --overwrite --only-show-errors >/dev/null

# 2. Search REST API helper: fill the @@PLACEHOLDERS@@ in a JSON template and PUT it.
PUT_OUT="$(mktemp)"
TOKEN="$(az account get-access-token --scope https://search.azure.com/.default --query accessToken -o tsv)"

render() {
  sed -e "s|@@STORAGE_ACCOUNT_ID@@|$STORAGE_ACCOUNT_ID|g" \
    -e "s|@@DOCS_CONTAINER@@|$DOCS_CONTAINER|g" \
    -e "s|@@INDEX_NAME@@|$INDEX_NAME|g" \
    -e "s|@@OPENAI_ENDPOINT@@|$OPENAI_ENDPOINT|g" \
    -e "s|@@EMBEDDING_DEPLOYMENT@@|$EMBEDDING_DEPLOYMENT|g" \
    -e "s|@@EMBEDDING_MODEL@@|$EMBEDDING_MODEL|g" "$1"
}

put() { # put <collection> <name> <template.json>
  local collection="$1" name="$2" template="$3" code
  code="$(render "$template" | curl -sS -o "$PUT_OUT" -w '%{http_code}' -X PUT \
    "$SEARCH_ENDPOINT/$collection/$name?api-version=$API_VERSION" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data-binary @-)"
  if [[ "$code" != 2* ]]; then
    echo "PUT $collection/$name failed (HTTP $code): $(cat "$PUT_OUT")" >&2
    return 1
  fi
  echo "  $collection/$name OK"
}

echo "Creating search objects ..."
retry put datasources school-docs-ds "$ROOT/search/datasource.json"
retry put indexes "$INDEX_NAME" "$ROOT/search/index.json"
retry put skillsets school-skillset "$ROOT/search/skillset.json"
retry put indexers school-indexer "$ROOT/search/indexer.json"

# 3. Run the indexer now and wait for it to finish.
curl -sS -o /dev/null -X POST "$SEARCH_ENDPOINT/indexers/school-indexer/run?api-version=$API_VERSION" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Length: 0"

echo "Waiting for the indexer ..."
for i in $(seq 1 40); do
  status_json="$(curl -sS "$SEARCH_ENDPOINT/indexers/school-indexer/status?api-version=$API_VERSION" \
    -H "Authorization: Bearer $TOKEN")"
  status="$(echo "$status_json" | python3 -c 'import sys,json; d=json.load(sys.stdin); print((d.get("lastResult") or {}).get("status","none"))')"
  echo "  [$i] indexer status: $status"
  case "$status" in
    success)
      echo "Indexed successfully."
      exit 0
      ;;
    transientFailure | persistentFailure)
      echo "$status_json" | python3 -m json.tool | head -40 >&2
      echo "Indexer failed." >&2
      exit 1
      ;;
  esac
  sleep 15
done
echo "Timed out waiting for the indexer." >&2
exit 1
