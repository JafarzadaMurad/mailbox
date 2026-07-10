#!/usr/bin/env bash
# =============================================================================
#  add-domain-admin.sh — domain admin yaradır.
#
#  İşlət:  bash scripts/add-domain-admin.sh <istifadeci_adi> <domen> [domen2 ...]
#  Məsələn: bash scripts/add-domain-admin.sh tural tural.ai
#
#  Domain admin panelə girib YALNIZ ona təyin olunan domen(lər)də mailbox və
#  alias yarada/idarə edə bilər. Yeni DOMEN əlavə edə bilməz — bunu yalnız
#  super-admin (sən) edirsən. Mailcow-un rol modeli belədir.
# =============================================================================
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

USERNAME="${1:-}"
shift || true
DOMAINS=("$@")

[[ -n "$USERNAME" && ${#DOMAINS[@]} -gt 0 ]] || \
  die "İstifadə: bash scripts/add-domain-admin.sh <istifadeci_adi> <domen> [domen2 ...]"

PASS="$(genpass)"

info "Domain admin yaradılır: ${USERNAME}  →  ${DOMAINS[*]}"
payload="$(jq -n \
  --arg u "$USERNAME" --arg p "$PASS" \
  --argjson d "$(printf '%s\n' "${DOMAINS[@]}" | jq -R . | jq -s .)" \
  '{username:$u, password:$p, password2:$p, domains:$d, active:"1"}')"

expect_success "$(api POST /add/domain-admin "$payload")" "domain admin yaratma"

cat <<EOF

============================================================
  Domain admin yaradıldı
============================================================
  İstifadəçi adı:  ${USERNAME}      (email DEYİL)
  Parol:           ${PASS}
  Domenlər:        ${DOMAINS[*]}

  Giriş:  https://${MAIL_HOSTNAME}/
============================================================
  Bu istifadəçi yalnız yuxarıdakı domen(lər)i görür və orada
  mailbox/alias yarada bilər. Yeni domen əlavə edə bilməz.
============================================================
  ⚠️  Parol bir daha göstərilməyəcək. İndi köçür.
============================================================
EOF
