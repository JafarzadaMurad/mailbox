# Web panel — quraşdırma

Admin üçün onboarding interfeysi: domen əlavə et, DNS qeydlərini al və yoxla,
mailbox və domain admin yarat. Skriptlərdəki məntiqin brauzer versiyası.

**Bu panel Mailcow-un panelini əvəz etmir** — onu tamamlayır. Gündəlik mailbox
idarəetməsini domain admin-lər Mailcow panelində edir.

---

## Təhlükəsizlik modeli — əvvəlcə bunu oxu

Tətbiqin **öz girişi yoxdur**. O:
- yalnız `127.0.0.1:8095`-ə bağlanır (xaricdən əlçatan deyil),
- Mailcow API açarını mühit dəyişəni kimi saxlayır,
- həmin açarla domen/mailbox yaratmaq səlahiyyətinə malikdir.

Yeganə qoruyucu **Caddy-nin `basic_auth`-udur**. Onsuz paneli açsan, hər kəs
sənin bütün mail infrastrukturunu idarə edə bilər. Aşağıdakı 2-ci addımı atlama.

---

## 1. DNS

Cloudflare-də A qeydi (**DNS only / boz bulud**):
```
mailadmin.tural.ai  →  168.231.108.200
```

## 2. Caddy — parol qoy

Parol hash-i yarat:
```bash
caddy hash-password
```
Parolu yaz, çıxan `$2a$14$...` sətrini kopyala.

`caddy/mailadmin.Caddyfile` faylındakı `BURAYA_BCRYPT_HASH_YAPISDIR` yerinə onu qoy,
sonra bloku əsas Caddyfile-a əlavə et:

```bash
cd /opt/MailBox
nano caddy/mailadmin.Caddyfile          # hash-i yapışdır
sudo cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak.mailadmin
sudo tee -a /etc/caddy/Caddyfile < caddy/mailadmin.Caddyfile > /dev/null
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

> `caddy validate` `basic_auth` direktivini tanımasa, Caddy-n köhnədir —
> faylda `basic_auth` yerinə `basicauth` yaz və təkrar sına.

## 3. Paneli qaldır

`secrets.env` artıq mövcud olmalıdır (API açarı ilə).

```bash
cd /opt/MailBox/web
sudo docker compose up -d --build
sudo docker compose logs -f mailbox-web   # Ctrl+C ilə çıx
```

Yoxla:
```bash
curl -s http://127.0.0.1:8095/api/domains          # domen siyahısı (JSON)
curl -sI https://mailadmin.tural.ai/ | head -1     # HTTP/2 401 (basic_auth işləyir)
```

`401` **doğru** cavabdır — brauzerdən açanda istifadəçi adı/parol soruşacaq.

> `curl -I` (HEAD) tətbiqin `/` marşrutuna `405` qaytarır — bu normaldır, marşrut
> yalnız GET qəbul edir. Sağlamlıq yoxlaması üçün `/api/domains` işlət.

### Mailcow API-yə çatmır (502)?

Panel API-yə **daxili Docker şəbəkəsi** üzərindən müraciət edir
(`http://mailcowdockerized-nginx-mailcow-1:8090`), public URL ilə yox — belə olanda
sorğu Caddy-yə toxunmur və mənbə IP həmişə Mailcow-un şəbəkəsindən (`172.22.1.0/24`) olur.

Yoxla:
```bash
docker network ls | grep mailcow          # şəbəkə adı düzdürmü?
docker inspect mailbox-web --format '{{json .NetworkSettings.Networks}}' | jq keys
```
Mailcow API açarının IP icazə siyahısında **`172.22.1.0/24`** olmalıdır.

## 4. İstifadə

`https://mailadmin.tural.ai` → `admin` + təyin etdiyin parol.

| Tab | İş |
|-----|-----|
| **Domenlər** | mövcud domenlərin siyahısı |
| **Domen əlavə et** | domen + DKIM yaradır, DNS qeydlərini cədvəl kimi göstərir (köçürmə düymələri ilə) |
| **DNS yoxla** | MX/SPF/DKIM/DMARC/PTR canlı yoxlama |
| **Mailbox** | mailbox yarat (parol bir dəfə göstərilir), siyahıla |
| **Domain admin** | müştəriyə öz domenini idarə etmə səlahiyyəti ver |

## Yeniləmə

```bash
cd /opt/MailBox && git pull
cd web && sudo docker compose up -d --build
```

## Dayandırma

```bash
cd /opt/MailBox/web && sudo docker compose down
```
Mail serverinə təsir etmir — bu, ondan tamamilə ayrı konteynerdir.

---

## Bilinən məhdudiyyətlər

- **DNS avtomatik yazılmır.** Müştəri domenlərinin zonaları bizdə deyil. Panel
  qeydləri yaradır, göstərir və yoxlayır — yazmaq müştərinin işidir.
- **Tək istifadəçi.** `basic_auth` bir parol deməkdir. Çox admin lazım olsa,
  Caddy-də əlavə istifadəçi sətirləri əlavə et.
- **Parollar saxlanılmır.** Yaradılan mailbox/domain admin parolu yalnız bir dəfə
  ekranda görünür. Parol menecerinə köçür.
