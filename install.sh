#!/usr/bin/env bash
# =============================================================================
#  MailBox — Mailcow quraşdırma bootstrap skripti
#  Serverdə işlədilir:  sudo bash install.sh
#
#  Nə edir:
#   1) config.env oxuyur
#   2) mailcow-dockerized reposunu klonlayır (yoxdursa)
#   3) mailcow.conf generasiya edir (hostname + timezone avtomatik)
#   4) mailcow.conf-u Caddy ilə yanaşı işləmək üçün patch edir
#      (web UI 127.0.0.1-ə bağlanır, daxili Let's Encrypt söndürülür)
#   5) növbəti addımları göstərir
#
#  Bu skript "docker compose up" ETMİR — bilərəkdən. Konfiqi yoxla, sonra
#  README-dəki əmrlə özün qaldır.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f config.env ]]; then
  echo "XƏTA: config.env tapılmadı. Əvvəlcə onu redaktə et." >&2
  exit 1
fi
# shellcheck disable=SC1091
source config.env

# --- Sanity yoxlamaları ---------------------------------------------------
if [[ "$MAIL_HOSTNAME" == "mail.example.com" || "$SERVER_IP" == "0.0.0.0" ]]; then
  echo "XƏTA: config.env-də MAIL_HOSTNAME və SERVER_IP hələ doldurulmayıb." >&2
  exit 1
fi
if [[ $EUID -ne 0 ]]; then
  echo "XƏTA: bu skript root icazəsi ilə işləməlidir:  sudo bash install.sh" >&2
  exit 1
fi
command -v docker >/dev/null || { echo "XƏTA: docker tapılmadı." >&2; exit 1; }
command -v git    >/dev/null || { echo "XƏTA: git tapılmadı." >&2; exit 1; }

echo "==> MAIL_HOSTNAME = $MAIL_HOSTNAME"
echo "==> SERVER_IP     = $SERVER_IP"
echo "==> MAILCOW_DIR   = $MAILCOW_DIR"
echo

# --- 1) Mailcow reposunu klonla ------------------------------------------
if [[ ! -d "$MAILCOW_DIR/.git" ]]; then
  echo "==> Mailcow reposu klonlanır -> $MAILCOW_DIR"
  git clone https://github.com/mailcow/mailcow-dockerized "$MAILCOW_DIR"
else
  echo "==> Mailcow reposu artıq mövcuddur, ötürülür."
fi

# --- 2) mailcow.conf generasiya et ---------------------------------------
cd "$MAILCOW_DIR"
if [[ ! -f mailcow.conf ]]; then
  echo "==> mailcow.conf generasiya olunur (IPv6 shim ilə — bax scripts/no-ipv6.sh)"
  # no-ipv6.sh olmadan mailcow Docker daemon-u restart etməyə çalışır və
  # serverdəki bütün digər konteynerləri yıxardı.
  MAILCOW_HOSTNAME="$MAIL_HOSTNAME" MAILCOW_TZ="$TIMEZONE" \
    bash "$SCRIPT_DIR/scripts/no-ipv6.sh" ./generate_config.sh
else
  echo "==> mailcow.conf artıq var, yenidən generasiya edilmir."
fi

# --- 3) mailcow.conf-u patch et ------------------------------------------
set_conf() {
  local key="$1" val="$2"
  if grep -qE "^#?${key}=" mailcow.conf; then
    sed -i -E "s|^#?${key}=.*|${key}=${val}|" mailcow.conf
  else
    echo "${key}=${val}" >> mailcow.conf
  fi
  echo "    ${key}=${val}"
}

echo "==> mailcow.conf Caddy ilə yanaşı işləmək üçün tənzimlənir:"
set_conf HTTP_PORT        "$MAILCOW_HTTP_PORT"
set_conf HTTP_BIND        "127.0.0.1"
set_conf HTTPS_PORT       "$MAILCOW_HTTPS_PORT"
set_conf HTTPS_BIND       "127.0.0.1"
# Sertifikatı Caddy alır və sync-certs.sh onu mail servislərinə köçürür,
# ona görə Mailcow-un öz Let's Encrypt-i söndürülür (80 portu Caddy-dədir).
set_conf SKIP_LETS_ENCRYPT "y"
# Docker daemon-da IPv6 aktiv DEYİL (daemon.json-a toxunmadıq, çünki onu
# dəyişmək Docker-i restart edib serverdəki bütün digər konteynerləri yıxardı).
# mailbox hostname-inin yalnız A qeydi var, ona görə IPv4-only işləyirik.
set_conf ENABLE_IPV6 "false"

echo
echo "============================================================"
echo " Konfiqurasiya hazırdır. NÖVBƏTİ ADDIMLAR:"
echo "============================================================"
echo " 1) DNS: mail hostname üçün A qeydi yarat:"
echo "        $MAIL_HOSTNAME  ->  $SERVER_IP"
echo
echo " 2) Firewall-da mail portlarını aç (README-yə bax): 25,465,587,143,993,110,995,4190"
echo
echo " 3) Mailcow-u qaldır:"
echo "        cd $MAILCOW_DIR && docker compose pull && docker compose up -d"
echo
echo " 4) Caddy blokunu əlavə et (caddy/mail.Caddyfile) və Caddy-ni reload et."
echo
echo " 5) Sertifikat sinxronizasiyasını qur (README: 'Sertifikat' bölməsi):"
echo "        sudo bash $SCRIPT_DIR/scripts/install-cert-sync.sh"
echo
echo " 6) https://$MAIL_HOSTNAME -> admin panelinə gir (admin / moohoo),"
echo "    parolu dəyiş, domen əlavə et, DKIM-i DNS-ə yaz."
echo "============================================================"
