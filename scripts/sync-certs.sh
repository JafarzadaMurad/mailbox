#!/usr/bin/env bash
# =============================================================================
#  sync-certs.sh
#  Caddy-nin MAIL_HOSTNAME üçün aldığı real Let's Encrypt sertifikatını
#  Mailcow-un mail servislərinə (postfix/dovecot) köçürür və dəyişiklik varsa
#  həmin konteynerləri restart edir.
#
#  Niyə lazımdır: Mailcow-da daxili Let's Encrypt söndürülüb (SKIP_LETS_ENCRYPT=y),
#  çünki 80/443 portları Caddy-dədir. Odur ki, SMTP/IMAP üçün etibarlı
#  sertifikatı Caddy-dən götürüb Mailcow-a veririk.
#
#  Bu skript systemd timer ilə gündə bir dəfə (və reboot-dan sonra) işləyir.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../config.env"

SSL_DIR="$MAILCOW_DIR/data/assets/ssl"

# --- Caddy-nin sertifikat qovluğunu tap ----------------------------------
# Caddy quraşdırma üsulundan asılı olaraq fərqli yerdə ola bilər.
CADDY_SEARCH_ROOTS=(
  "/var/lib/caddy/.local/share/caddy"
  "/root/.local/share/caddy"
  "/home/caddy/.local/share/caddy"
  "${CADDY_DATA:-}"
)

CRT=""
for root in "${CADDY_SEARCH_ROOTS[@]}"; do
  [[ -z "$root" || ! -d "$root" ]] && continue
  found="$(find "$root" -type f -name "${MAIL_HOSTNAME}.crt" 2>/dev/null | head -n1 || true)"
  if [[ -n "$found" ]]; then CRT="$found"; break; fi
done

if [[ -z "$CRT" ]]; then
  echo "XƏTA: Caddy-nin '${MAIL_HOSTNAME}.crt' sertifikatı tapılmadı." >&2
  echo "      Caddy bu domeni bir dəfə servis etməlidir ki, sertifikat yaransın." >&2
  echo "      Əl ilə axtar:  sudo find / -name '${MAIL_HOSTNAME}.crt' 2>/dev/null" >&2
  echo "      Tapılan qovluğun kökünü config.env-də CADDY_DATA= kimi əlavə et." >&2
  exit 1
fi
KEY="${CRT%.crt}.key"
[[ -f "$KEY" ]] || { echo "XƏTA: açar tapılmadı: $KEY" >&2; exit 1; }

# --- Dəyişiklik varmı? ----------------------------------------------------
mkdir -p "$SSL_DIR"
if cmp -s "$CRT" "$SSL_DIR/cert.pem" && cmp -s "$KEY" "$SSL_DIR/key.pem"; then
  echo "Sertifikat artıq günceldir, dəyişiklik yoxdur."
  exit 0
fi

echo "Yeni sertifikat aşkarlandı, köçürülür..."
cp "$CRT" "$SSL_DIR/cert.pem"
cp "$KEY" "$SSL_DIR/key.pem"
chmod 600 "$SSL_DIR/key.pem"

echo "Mail servisləri restart edilir..."
cd "$MAILCOW_DIR"
docker compose restart postfix-mailcow dovecot-mailcow nginx-mailcow
echo "Tamamlandı."
