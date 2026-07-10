#!/usr/bin/env bash
# =============================================================================
#  lib.sh — digər skriptlərin ortaq funksiyaları. Birbaşa işlədilmir.
# =============================================================================

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$_LIB_DIR/.." && pwd)"

die() { echo "XƏTA: $*" >&2; exit 1; }
info() { echo "==> $*"; }

[[ -f "$ROOT_DIR/config.env" ]] || die "config.env tapılmadı"
# shellcheck disable=SC1091
source "$ROOT_DIR/config.env"

[[ -f "$ROOT_DIR/secrets.env" ]] || die "secrets.env tapılmadı. Yarat:
    cp $ROOT_DIR/secrets.env.example $ROOT_DIR/secrets.env
    chmod 600 $ROOT_DIR/secrets.env
    nano $ROOT_DIR/secrets.env"
# shellcheck disable=SC1091
source "$ROOT_DIR/secrets.env"

[[ -n "${MAILCOW_API_KEY:-}" ]] || die "secrets.env-də MAILCOW_API_KEY boşdur"
command -v jq   >/dev/null || die "jq lazımdır:  sudo apt install -y jq"
command -v curl >/dev/null || die "curl lazımdır"
command -v dig  >/dev/null || die "dig lazımdır:  sudo apt install -y dnsutils"

API_BASE="https://${MAIL_HOSTNAME}/api/v1"

# api <METHOD> <path> [json-body]
# Cavab gövdəsini stdout-a yazır. HTTP xətasında dayanır.
api() {
  local method="$1" path="$2" body="${3:-}"
  local args=(-sS --fail-with-body -X "$method"
              -H "X-API-Key: ${MAILCOW_API_KEY}"
              -H "Content-Type: application/json")
  [[ -n "$body" ]] && args+=(-d "$body")
  curl "${args[@]}" "${API_BASE}${path}" || die "API sorğusu uğursuz: $method $path
Ehtimal olunan səbəb: API açarı yanlışdır və ya IP icazəsi yoxdur.
Yoxla:  bash scripts/api-test.sh"
}

# expect_success <api-cavabı> <kontekst>
# Mailcow add/* endpoint-ləri [{"type":"success"|"danger", "msg":[...]}] qaytarır.
expect_success() {
  local resp="$1" ctx="$2" type
  type="$(jq -r 'if type=="array" then .[0].type else .type end // "unknown"' <<<"$resp" 2>/dev/null || echo unknown)"
  if [[ "$type" != "success" ]]; then
    echo "XƏTA ($ctx): Mailcow API uğursuz cavab verdi:" >&2
    jq . <<<"$resp" >&2 2>/dev/null || echo "$resp" >&2
    exit 1
  fi
}

# genpass — güclü parol yaradır
genpass() { openssl rand -base64 24 | tr -d '/+=\n' | cut -c1-20; }
