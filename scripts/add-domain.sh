#!/usr/bin/env bash
# =============================================================================
#  add-domain.sh — Mailcow-a yeni domen əlavə edir və müştəriyə göndəriləcək
#                  DNS qeydləri sənədini yaradır.
#
#  İşlət:  bash scripts/add-domain.sh musteri.com
#
#  Nə edir:
#    1) Mailcow API ilə domeni yaradır (kvotalar config.env-dən)
#    2) DKIM açarını alır (yoxdursa yaradır)
#    3) dns/generated/<domen>.md faylına lazımi DNS qeydlərini yazır
#    4) Ekranda da göstərir
#
#  DNS qeydlərini AVTOMATİK YAZMIR — müştərinin DNS provayderi bizdə deyil.
#  Faylı müştəriyə göndər, o qeydləri əlavə etsin, sonra:
#      bash scripts/check-dns.sh musteri.com
# =============================================================================
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

DOMAIN="${1:-}"
[[ -n "$DOMAIN" ]] || die "İstifadə: bash scripts/add-domain.sh <domen>"
[[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || die "Domen adı düzgün görünmür: $DOMAIN"

# --- 1) Domeni yarat -------------------------------------------------------
info "Domen yaradılır: $DOMAIN"
payload="$(jq -n \
  --arg d "$DOMAIN" \
  --arg aliases "$DOMAIN_MAX_ALIASES" \
  --arg mailboxes "$DOMAIN_MAX_MAILBOXES" \
  --arg defquota "$DOMAIN_DEFAULT_QUOTA" \
  --arg maxquota "$DOMAIN_MAX_MAILBOX_QUOTA" \
  --arg quota "$DOMAIN_TOTAL_QUOTA" \
  '{domain:$d, description:"", aliases:$aliases, mailboxes:$mailboxes,
    defquota:$defquota, maxquota:$maxquota, quota:$quota,
    active:"1", backupmx:"0", relay_all_recipients:"0",
    dkim_selector:"dkim", key_size:"2048", gal:"1"}')"

resp="$(api POST /add/domain "$payload")"
if grep -qi 'domain_exists\|already exists' <<<"$resp"; then
  info "Domen artıq mövcuddur — davam edilir."
else
  expect_success "$resp" "domen yaratma"
  info "Domen yaradıldı."
fi

# --- 2) DKIM açarını al ----------------------------------------------------
info "DKIM açarı alınır"
dkim="$(api GET "/get/dkim/${DOMAIN}")"
dkim_txt="$(jq -r '.dkim_txt // empty' <<<"$dkim")"

if [[ -z "$dkim_txt" ]]; then
  info "DKIM açarı yoxdur, yaradılır"
  gen="$(jq -n --arg d "$DOMAIN" '{domains:$d, dkim_selector:"dkim", key_size:"2048"}')"
  expect_success "$(api POST /add/dkim "$gen")" "DKIM yaratma"
  dkim="$(api GET "/get/dkim/${DOMAIN}")"
  dkim_txt="$(jq -r '.dkim_txt // empty' <<<"$dkim")"
fi
[[ -n "$dkim_txt" ]] || die "DKIM açarı alınmadı. Paneldə yoxla."

# --- 3) DNS sənədini yaz ---------------------------------------------------
OUT_DIR="$ROOT_DIR/dns/generated"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/${DOMAIN}.md"

cat > "$OUT" <<EOF
# ${DOMAIN} — DNS qeydləri

Bu qeydləri **${DOMAIN}** domeninin DNS provayderində yaradın.
Mail serveri: \`${MAIL_HOSTNAME}\` (${SERVER_IP})

> Cloudflare istifadə edirsinizsə, bütün qeydlər **DNS only (boz bulud)** olmalıdır.

> **Qeyd — subdomen üçün.** Aşağıdakı "Ad" sütunu **tam DNS adıdır (FQDN)**.
> Domen zonanın kökü olsa (məs. \`${DOMAIN}\` = \`example.com\`), DNS provayderində
> \`@\` yaza bilərsiniz. Amma subdomen olsa (məs. \`chatbot.example.com\`), \`@\` YOX,
> tam adı işlədin — əks halda qeyd səhv yerə düşər. Cloudflare tam adı qəbul edir.

## 1. MX — gələn maili yönləndirir

| Tip | Ad (FQDN) | Dəyər | Prioritet |
|-----|-----------|-------|-----------|
| MX | \`${DOMAIN}\` | \`${MAIL_HOSTNAME}\` | 10 |

⚠️ Domenin köhnə MX qeydləri varsa **silin** — əks halda mail köhnə provayderə gedər.

## 2. SPF — kimin bu domendən mail göndərə biləcəyi

| Tip | Ad (FQDN) | Dəyər |
|-----|-----------|-------|
| TXT | \`${DOMAIN}\` | \`v=spf1 mx ~all\` |

⚠️ **Domenin artıq SPF qeydi varsa, onu ƏVƏZ ETMƏYİN — birləşdirin.**
Məsələn mövcud qeyd \`v=spf1 include:_spf.example.com ~all\` idisə, yenisi belə olmalıdır:
\`v=spf1 mx include:_spf.example.com ~all\`
(Bir domendə yalnız **bir** SPF qeydi ola bilər.)

## 3. DKIM — maili imzalayır

| Tip | Ad (FQDN) | Dəyər |
|-----|-----------|-------|
| TXT | \`dkim._domainkey.${DOMAIN}\` | (aşağıdakı uzun sətir) |

\`\`\`
${dkim_txt}
\`\`\`

## 4. DMARC — siyasət və hesabatlar

| Tip | Ad (FQDN) | Dəyər |
|-----|-----------|-------|
| TXT | \`_dmarc.${DOMAIN}\` | \`v=DMARC1; p=none; pct=100; rua=mailto:postmaster@${DOMAIN}\` |

⚠️ Bir domendə yalnız **bir** \`_dmarc\` qeydi ola bilər.
\`p=none\` ilə başlayın; hər şey oturuşandan sonra \`p=quarantine\`, sonra \`p=reject\`.

## 5. (İstəyə görə) Outlook avtomatik quraşdırma

| Tip | Ad (FQDN) | Dəyər |
|-----|-----------|-------|
| SRV | \`_autodiscover._tcp.${DOMAIN}\` | prioritet 0, çəki 1, port 443, hədəf \`${MAIL_HOSTNAME}\` |

## Yoxlama

Qeydlər yayılandan sonra (10–60 dəqiqə):
\`\`\`bash
bash scripts/check-dns.sh ${DOMAIN}
\`\`\`
EOF

info "DNS sənədi yazıldı: dns/generated/${DOMAIN}.md"
echo
cat "$OUT"
echo
info "Növbəti addımlar:"
echo "  1) Yuxarıdakı sənədi müştəriyə göndər, DNS qeydlərini yaratsın."
echo "  2) Yayılandan sonra:  bash scripts/check-dns.sh ${DOMAIN}"
echo "  3) Mailbox yarat:     bash scripts/add-mailbox.sh ${DOMAIN} postmaster"
echo "  4) Domain admin təyin et: bash scripts/add-domain-admin.sh <istifadeci> ${DOMAIN}"
