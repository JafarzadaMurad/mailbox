#!/usr/bin/env bash
# =============================================================================
#  mailcow-update.sh — Mailcow-u TƏHLÜKƏSİZ yenilə.
#
#  İşlət:  sudo bash scripts/mailcow-update.sh
#
#  Mailcow-un öz update.sh-i də configure_ipv6() çağırır və host-da IPv6
#  aşkarlasa, Docker daemon-u restart etməyə çalışır (serverdəki bütün digər
#  konteynerləri yıxardı). Ona görə update.sh-i də no-ipv6.sh wrapper-i ilə
#  işlədirik. Ətraflı izah: scripts/no-ipv6.sh
#
#  Mailcow-u BİRBAŞA `./update.sh` ilə yeniləmə — həmişə bu skripti işlət.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../config.env"

if [[ $EUID -ne 0 ]]; then
  echo "root icazəsi lazımdır:  sudo bash scripts/mailcow-update.sh" >&2
  exit 1
fi

cd "$MAILCOW_DIR"
echo "==> Mailcow yenilənir (IPv6 shim ilə, Docker daemon toxunulmur)"
bash "$SCRIPT_DIR/no-ipv6.sh" ./update.sh

echo
echo "==> Yeniləmədən sonra sertifikatları yenidən sinxronla:"
echo "    sudo systemctl start mailcow-cert-sync.service"
