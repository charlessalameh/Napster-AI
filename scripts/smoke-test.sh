#!/usr/bin/env bash
# Smoke test: wait for the web app, then ask the demo questions from CLAUDE.md.
# Usage: ./scripts/smoke-test.sh https://<web-app>.azurewebsites.net
set -euo pipefail

BASE="${1:?Usage: $0 <web-app-url>}"
BASE="${BASE%/}"

echo "Waiting for $BASE/health ..."
for i in $(seq 1 40); do
  if curl -fsS -o /dev/null --max-time 10 "$BASE/health"; then
    echo "  app is up"
    break
  fi
  if [[ $i -eq 40 ]]; then echo "App did not become healthy in time" >&2; exit 1; fi
  echo "  [$i] not ready, retrying in 15 s ..."
  sleep 15
done

# With Easy Auth on, nobody can call the chat API without signing in. Check that it is
# protected (redirect to login or 401) instead of testing the answers. Test those by hand.
if [[ "${EXPECT_AUTH:-false}" == "true" ]]; then
  echo "Easy Auth is on: checking the site is protected"
  for path in / /api/chat; do
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 -X POST "$BASE$path" -H 'Content-Type: application/json' --data '{"question":"hi"}')"
    echo "  $path without login -> HTTP $code"
    [[ "$code" == "302" || "$code" == "401" ]] || { echo "FAIL: $path should require sign-in" >&2; exit 1; }
  done
  echo "Protected. Sign in in a browser to try the agent."
  exit 0
fi

ask() { # ask "<question>" -> prints the JSON reply (retries: first call can be slow)
  local n=0 out
  until out="$(curl -fsS --max-time 60 -X POST "$BASE/api/chat" \
    -H 'Content-Type: application/json' \
    --data "$(python3 -c 'import json,sys; print(json.dumps({"question": sys.argv[1]}))' "$1")")"; do
    n=$((n + 1))
    if [[ $n -ge 6 ]]; then echo "Request failed: $1" >&2; return 1; fi
    echo "  request failed, retry $n/6 in 20 s (role assignments may still be propagating) ..." >&2
    sleep 20
  done
  echo "$out"
}

field() { python3 -c 'import json,sys; d=json.load(sys.stdin); v=d[sys.argv[1]]; print(" ".join(v) if isinstance(v,list) else v)' "$1"; }

fail() { echo "FAIL: $1" >&2; exit 1; }

echo "Test 1: school bus price"
r="$(ask 'How much is the school bus?')"
answer="$(echo "$r" | field answer)"; sources="$(echo "$r" | field sources)"
echo "  answer:  $answer"
echo "  sources: $sources"
grep -Eq '7,?000' <<<"$answer" || fail "expected AED 7,000 in the answer"
grep -q 'fees-transport.txt' <<<"$sources" || fail "expected fees-transport.txt as a source"

echo "Test 2: admission documents"
r="$(ask 'What documents do I need for admission?')"
answer="$(echo "$r" | field answer)"
echo "  answer:  $answer"
grep -qi 'passport' <<<"$answer" || fail "expected the document list (passport)"

echo "Test 3: question not covered by the documents"
r="$(ask 'Do you have a swimming pool?')"
answer="$(echo "$r" | field answer)"
echo "  answer:  $answer"
grep -Eqi "admissions|don't have|do not have|not sure|no information" <<<"$answer" \
  || fail "expected a refusal that suggests contacting admissions"
if grep -Eqi 'yes, we have|we have a (swimming )?pool' <<<"$answer"; then fail "agent invented a pool"; fi

echo "All smoke tests passed."
