#!/usr/bin/env bash
# =============================================================================
#  add-mailbox.sh — mailbox yaradır və parolu BİR DƏFƏ göstərir.
#
#  İşlət:  bash scripts/add-mailbox.sh musteri.com info [kvota_MiB] ["Ad Soyad"]
#
#  Parol avtomatik generasiya olunur. Ekranda göstərilir və HEÇ BİR YERDƏ
#  saxlanılmır — dərhal parol menecerinə köçür.
# =============================================================================
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

DOMAIN="${1:-}"
LOCAL="${2:-}"
QUOTA="${3:-$DOMAIN_DEFAULT_QUOTA}"
FULLNAME="${4:-$LOCAL}"

[[ -n "$DOMAIN" && -n "$LOCAL" ]] || die "İstifadə: bash scripts/add-mailbox.sh <domen> <ad> [kvota_MiB] [\"Tam Ad\"]"

PASS="$(genpass)"

info "Mailbox yaradılır: ${LOCAL}@${DOMAIN}  (kvota ${QUOTA} MiB)"
payload="$(jq -n \
  --arg lp "$LOCAL" --arg d "$DOMAIN" --arg n "$FULLNAME" \
  --arg p "$PASS" --arg q "$QUOTA" \
  '{local_part:$lp, domain:$d, name:$n, password:$p, password2:$p,
    quota:$q, active:"1", force_pw_update:"0",
    tls_enforce_in:"0", tls_enforce_out:"0"}')"

expect_success "$(api POST /add/mailbox "$payload")" "mailbox yaratma"

cat <<EOF

============================================================
  Mailbox yaradıldı
============================================================
  Ünvan:  ${LOCAL}@${DOMAIN}
  Parol:  ${PASS}

  Webmail:  https://${MAIL_HOSTNAME}/SOGo/

  IMAP:  ${MAIL_HOSTNAME}  port 993  (SSL/TLS)
  SMTP:  ${MAIL_HOSTNAME}  port 587  (STARTTLS)
============================================================
  ⚠️  Bu parol bir daha göstərilməyəcək. İndi köçür.
============================================================
EOF
