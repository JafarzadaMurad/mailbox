# MailBox — öz VPS-imizdə çox-domenli mail serveri (Mailcow)

Mövcud Hostinger VPS-də (Caddy + digər layihələrlə **yanaşı**) pulsuz, açıq mənbəli
mail serveri qurmaq üçün. Panel üzərindən **domen əlavə et → mailbox yarat**, və
hər istifadəçiyə **yalnız öz domenini** idarə etmə səlahiyyəti ver (Mailcow "domain admin").

## Nə əldə edirik
- İstənilən qədər domen və mailbox (`info@musteri.com`, `support@...` və s.)
- Roundcube webmail (Gmail bənzəri arayüz) + admin panel
- Antispam (Rspamd) + antivirus (ClamAV)
- Domain-admin rolu ilə çox-istifadəçili idarəetmə
- Hər şey pulsuz (yalnız artıq sahib olduğun VPS + domenlər)

## Necə işləyir (dizayn qərarı)
- **Portlar:** Mail portları (25, 465, 587, 143, 993, 110, 995, 4190) Caddy-nin
  80/443-ünə toxunmur — konflikt yoxdur.
- **Web UI:** Mailcow-un web paneli `127.0.0.1`-ə (8090/8453) bağlanır, **Caddy**
  onu `https://mail.example.com` kimi xaricə verir və TLS sertifikatını alır.
- **Mail TLS:** Mailcow-un daxili Let's Encrypt-i söndürülüb (80 portu Caddy-də olduğu üçün).
  `scripts/sync-certs.sh` Caddy-nin aldığı sertifikatı SMTP/IMAP servislərinə köçürür
  və systemd timer ilə avtomatik yeniləyir.

---

## Ön şərtlər (yoxla)
- [x] RAM: Supabase dayandırıldıqdan sonra ~9.7 GB boş — kifayətdir.
- [x] Mail portları serverdə boşdur.
- [ ] **Outbound port 25** — Hostinger AI "bloklanmır" dedi; qurulumdan sonra
      real testlə təsdiqlə (aşağıda).
- [ ] `MAIL_HOSTNAME` üçün istifadə edəcəyin domenin DNS-inə giriş.
- [ ] Serverin public IP-si.

---

## Quraşdırma addımları

### 0) Repo-nu serverə çək
```bash
sudo git clone <SƏNİN_GIT_REPON> /opt/MailBox
cd /opt/MailBox
```

### 1) config.env-i redaktə et
`MAIL_HOSTNAME`, `SERVER_IP`, `TIMEZONE` doldur. (Portları dəyişmə.)
```bash
nano config.env
```

### 2) DNS: A qeydi + PTR
- `mail.example.com  ->  <SERVER_IP>` (A qeydi).
- Hostinger paneldən **reverse DNS (PTR)**-i `mail.example.com` et (IPv4 və varsa IPv6).
- Ətraflı: [dns/DNS-RECORDS.md](dns/DNS-RECORDS.md).

### 3) install.sh işlət
```bash
sudo bash install.sh
```
Bu: Mailcow-u klonlayır, `mailcow.conf` generasiya edir və Caddy ilə yanaşı işləmək
üçün patch edir (127.0.0.1 bind, daxili LE söndürülür). Konteynerləri **qaldırmır** —
bilərəkdən; əvvəlcə konfiqi yoxla.

### 4) Firewall — mail portlarını aç
`ufw` aktivdirsə:
```bash
sudo ufw allow 25,465,587,143,993,110,995,4190/tcp
```
(80/443 onsuz da Caddy üçün açıqdır.) `ufw status` ilə yoxla. Hostinger-in öz
panelində firewall varsa, orada da eyni portları aç.

### 5) Mailcow-u qaldır
```bash
cd /opt/mailcow-dockerized
docker compose pull
docker compose up -d
```
İlk dəfə image-lər çəkilir, bir neçə dəqiqə çəkə bilər.

### 6) Caddy blokunu əlavə et
[caddy/mail.Caddyfile](caddy/mail.Caddyfile) içindəki bloku əsas Caddyfile-ına köçür
(və ya `import`), `mail.example.com`-u öz hostname-inlə əvəz et, sonra:
```bash
sudo caddy reload --config /etc/caddy/Caddyfile
```
İndi `https://mail.example.com` açılmalıdır (Caddy sertifikatı bir neçə saniyəyə alır).

### 7) Sertifikat sinxronizasiyasını qur
```bash
sudo bash scripts/install-cert-sync.sh
```
Bu, Caddy-nin sertifikatını mail servislərinə köçürən systemd timer qurur və dərhal
bir dəfə işlədir. Xəta versə (sertifikat tapılmadı), Caddy-nin `mail.example.com`-u
ən azı bir dəfə servis etməsini gözlə, sonra təkrar işlət.

### 8) Panelə gir və konfiqurasiya et
- `https://mail.example.com` → default giriş: **admin / moohoo** → **parolu dərhal dəyiş**.
- **Configuration → Domains → Add domain**: müştəri domenini əlavə et.
- **Configuration → Mailbox → Add mailbox**: `info@musteri.com` və s. yarat.
- **Mail setup / DNS** bölməsindən **DKIM** və digər qeydləri götürüb domenin DNS-inə yaz
  ([dns/DNS-RECORDS.md](dns/DNS-RECORDS.md)).
- Webmail: `https://mail.example.com/SOGo/` (Mailcow-un webmail-i SOGo-dur;
  Roundcube istəsən onu da aktiv etmək olar).

### 9) Çox-istifadəçili idarəetmə (domain admin)
İstədiyin ki, hər istifadəçi öz domenini idarə etsin:
- **Access → Domain admins → Add**: yeni domain-admin yarat, ona yalnız müvafiq
  domen(lər)i təyin et. O, panelə girib **yalnız** həmin domenin mailbox-larını
  yarada/idarə edə bilər, başqa domenlərə toxuna bilməz.

---

## Port 25 testi (mütləq et)
Mailcow qalxandan sonra kənar mail serverə çıxışı yoxla:
```bash
# Postfix konteynerindən 25 portuna çıxış varmı?
docker exec -it $(docker ps -qf name=postfix-mailcow) bash -lc \
  'timeout 5 bash -c "cat < /dev/null > /dev/tcp/gmail-smtp-in.l.google.com/25" && echo ACIQ || echo BAGLI'
```
`ACIQ` görsən — mail göndərə bilərsən. `BAGLI` görsən — Hostinger support-a
"outbound port 25 açılsın" sorğusu göndər (adətən qısa müddətdə açırlar).

Sonra webmail-dən şəxsi Gmail-inə test maili at və spama düşüb-düşmədiyinə bax.
Deliverability üçün [mail-tester.com](https://www.mail-tester.com) ilə skor yoxla —
hədəf 9-10/10.

---

## Baxım
- **Yeniləmə:** `cd /opt/mailcow-dockerized && ./update.sh`
- **Backup:** `./helper-scripts/backup_restore.sh backup all`
- **Loglar:** `docker compose logs -f postfix-mailcow`
- Öz mail serverinin təhlükəsizliyi/yeniləmələri **sənin məsuliyyətindədir**
  (videonun sonunda da vurğulanır).

## Fayl strukturu
```
MailBox/
├── README.md                  # bu fayl
├── config.env                 # redaktə etdiyin yeganə konfiq
├── install.sh                 # bootstrap (Mailcow klon + konfiq patch)
├── caddy/mail.Caddyfile       # Caddy reverse-proxy bloku
├── scripts/
│   ├── sync-certs.sh          # Caddy sertifikatını mail servislərinə köçürür
│   └── install-cert-sync.sh   # yuxarıdakını systemd timer kimi qurur
└── dns/DNS-RECORDS.md         # MX/SPF/DKIM/DMARC + PTR təlimatı
```

## Geri qaytarma
Bir şey səhv getsə, mail stack-ini tamamilə söndür (digər layihələrə təsir etmir):
```bash
cd /opt/mailcow-dockerized && docker compose down
```
Supabase-i geri qaytarmaq (lazım olsa):
```bash
docker start $(docker ps -aq --filter "name=supabase" --filter "name=realtime-dev")
```
