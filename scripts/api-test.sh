#!/usr/bin/env bash
# =============================================================================
#  api-test.sh — Mailcow API açarının işlədiyini yoxlayır.
#  İşlət:  bash scripts/api-test.sh
#
#  403 alsan, API açarının "Allow API access from these IPs" siyahısına
#  aşağıda göstərilən IP-ni əlavə et.
# =============================================================================
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

info "API ünvanı: $API_BASE"
info "Serverin xaricə görünən IP-si:"
curl -sS https://api.ipify.org 2>/dev/null && echo || echo "  (təyin edilə bilmədi)"
echo

info "Sorğu: GET /get/status/version"
if resp="$(curl -sS -w '\n%{http_code}' \
      -H "X-API-Key: ${MAILCOW_API_KEY}" \
      "${API_BASE}/get/status/version")"; then
  code="$(tail -n1 <<<"$resp")"
  body="$(sed '$d' <<<"$resp")"
  echo "HTTP $code"
  jq . <<<"$body" 2>/dev/null || echo "$body"
  echo
  case "$code" in
    200) info "✅ API açarı işləyir." ;;
    401|403)
      echo "❌ İcazə yoxdur. Paneldə: System → Configuration → Access → API" >&2
      echo "   - 'Activate API' işarəli olsun, 'Read-Write access' seçilsin" >&2
      echo "   - 'Allow API access from these IPs' sahəsinə yuxarıdakı IP-ni əlavə et" >&2
      echo "   - Caddy arxasında olduğumuz üçün 127.0.0.1-i də əlavə etməyə dəyər" >&2
      exit 1 ;;
    *) echo "❌ Gözlənilməz cavab." >&2; exit 1 ;;
  esac
else
  die "API-yə çatmaq mümkün olmadı: $API_BASE"
fi
