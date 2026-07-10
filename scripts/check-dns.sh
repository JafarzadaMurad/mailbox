#!/usr/bin/env bash
# =============================================================================
#  check-dns.sh — bir domenin mail üçün DNS qeydlərini yoxlayır.
#  İşlət:  bash scripts/check-dns.sh musteri.com
#
#  Mailcow panelindəki "DNS" düyməsinin terminal versiyası, üstəlik SPF/DMARC
#  təkrarlanma yoxlaması (panel bunu göstərmir, amma mail-i səssizcə sındırır).
# =============================================================================
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

DOMAIN="${1:-}"
[[ -n "$DOMAIN" ]] || die "İstifadə: bash scripts/check-dns.sh <domen>"

FAIL=0
ok()   { echo "  ✅ $*"; }
bad()  { echo "  ❌ $*"; FAIL=1; }
warn() { echo "  ⚠️  $*"; }

echo "=== $DOMAIN — DNS yoxlaması ==="
echo

# --- MX --------------------------------------------------------------------
echo "MX:"
mx="$(dig +short MX "$DOMAIN" | sort)"
if [[ -z "$mx" ]]; then
  bad "MX qeydi yoxdur"
elif grep -qi "[[:space:]]${MAIL_HOSTNAME}\.\?$" <<<"$mx"; then
  ok "$(tr '\n' ' ' <<<"$mx")"
  extra="$(grep -vi "[[:space:]]${MAIL_HOSTNAME}\.\?$" <<<"$mx" || true)"
  [[ -n "$extra" ]] && warn "başqa MX qeydləri də var (mail onlara gedə bilər): $(tr '\n' ' ' <<<"$extra")"
else
  bad "MX bizə işarə etmir: $(tr '\n' ' ' <<<"$mx")  (gözlənilən: $MAIL_HOSTNAME)"
fi
echo

# --- SPF -------------------------------------------------------------------
echo "SPF:"
spf="$(dig +short TXT "$DOMAIN" | tr -d '"' | grep -i '^v=spf1' || true)"
spf_count="$(grep -c . <<<"$spf" || true)"
if [[ -z "$spf" ]]; then
  bad "SPF qeydi yoxdur"
elif (( spf_count > 1 )); then
  bad "BİRDƏN ÇOX SPF qeydi var — SPF tamamilə etibarsız sayılır. Birləşdir:"
  sed 's/^/       /' <<<"$spf"
else
  if grep -qE '(^| )(mx|a:'"${MAIL_HOSTNAME//./\\.}"'|ip4:'"${SERVER_IP//./\\.}"')( |$)' <<<"$spf"; then
    ok "$spf"
  else
    bad "SPF bizim serveri icazələndirmir: $spf"
    echo "       'mx' mexanizmi və ya 'a:${MAIL_HOSTNAME}' əlavə et."
  fi
fi
echo

# --- DKIM ------------------------------------------------------------------
echo "DKIM (dkim._domainkey):"
dkim="$(dig +short TXT "dkim._domainkey.${DOMAIN}" | tr -d '"' | tr -d ' ')"
if [[ -z "$dkim" ]]; then
  bad "DKIM qeydi yoxdur"
elif [[ "$dkim" == v=DKIM1* ]]; then
  # DNS-dəki açarı Mailcow-dakı ilə tutuşdur
  live_p="$(grep -o 'p=[A-Za-z0-9+/=]*' <<<"$dkim" | head -1)"
  mc_p="$(api GET "/get/dkim/${DOMAIN}" | jq -r '.dkim_txt // empty' | tr -d ' ' | grep -o 'p=[A-Za-z0-9+/=]*' | head -1 || true)"
  if [[ -n "$mc_p" && "$live_p" == "$mc_p" ]]; then
    ok "mövcuddur və Mailcow-dakı açarla eynidir"
  elif [[ -n "$mc_p" ]]; then
    bad "DNS-dəki DKIM açarı Mailcow-dakından FƏRQLİDİR — imza yoxlanmayacaq"
  else
    warn "DNS-də var, amma Mailcow-dakı açarı oxumaq alınmadı"
  fi
else
  bad "DKIM qeydi düzgün formatda deyil"
fi
echo

# --- DMARC -----------------------------------------------------------------
echo "DMARC (_dmarc):"
dmarc="$(dig +short TXT "_dmarc.${DOMAIN}" | tr -d '"' | grep -i '^v=DMARC1' || true)"
dmarc_count="$(grep -c . <<<"$dmarc" || true)"
if [[ -z "$dmarc" ]]; then
  warn "DMARC qeydi yoxdur (məcburi deyil, amma tövsiyə olunur)"
elif (( dmarc_count > 1 )); then
  bad "BİRDƏN ÇOX DMARC qeydi var — DMARC etibarsız sayılır"
else
  ok "$dmarc"
fi
echo

# --- PTR (server üçün, domendən asılı deyil) -------------------------------
echo "PTR (server):"
ptr="$(dig +short -x "$SERVER_IP" || true)"
if [[ "$ptr" == "${MAIL_HOSTNAME}." ]]; then
  ok "$ptr"
else
  bad "PTR '$ptr' — gözlənilən '${MAIL_HOSTNAME}.'  (Hostinger paneldən düzəlt)"
fi
echo

if (( FAIL )); then
  echo "=== Nəticə: problemlər var (yuxarıdakı ❌ sətirlərinə bax) ==="
  echo "DNS dəyişikliyi təzə edilibsə, 10-60 dəqiqə gözləyib təkrar yoxla."
  exit 1
fi
echo "=== Nəticə: hər şey qaydasındadır ✅ ==="
echo "İndi mailbox yarada bilərsən:  bash scripts/add-mailbox.sh $DOMAIN info"
