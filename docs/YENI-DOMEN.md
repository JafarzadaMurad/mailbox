# Yeni domen əlavə etmə — runbook

Hər yeni müştəri domeni üçün bu addımlar. Ümumi vaxt: **~10 dəqiqə** (üstəgəl DNS yayılması).

Bir dəfəlik hazırlıq: [API açarı](#bir-dəfəlik-api-açarı) qurulmalıdır.

---

## 1. Domeni yarat və DNS sənədini al

```bash
cd /opt/MailBox
bash scripts/add-domain.sh musteri.com
```

Bu:
- Mailcow-da domeni yaradır (kvotalar `config.env`-dən)
- DKIM açarını generasiya edir
- `dns/generated/musteri.com.md` faylını yazır — **hazır, müştəriyə göndəriləcək sənəd**

## 2. Sənədi müştəriyə göndər

Fayl MX, SPF, DKIM, DMARC qeydlərini cədvəl şəklində izah edir.

⚠️ Sənəddəki iki xəbərdarlığı müştəriyə xüsusi vurğula:
- **Köhnə MX qeydləri silinməlidir** (yoxsa mail köhnə provayderə gedir)
- **Mövcud SPF varsa, əvəz yox, birləşdirilməlidir** (bir domendə yalnız bir SPF ola bilər)

## 3. DNS yayılandan sonra yoxla

```bash
bash scripts/check-dns.sh musteri.com
```

Bu, MX/SPF/DKIM/DMARC/PTR-i yoxlayır və **panelin göstərmədiyi** iki səssiz sındırıcını da tutur:
- birdən çox SPF qeydi
- DNS-dəki DKIM açarının Mailcow-dakı ilə uyğunsuzluğu

Hamısı ✅ olana qədər mailbox yaratma — yaratsan, gələn maillər itə bilər.

## 4. Mailbox-ları yarat

```bash
bash scripts/add-mailbox.sh musteri.com postmaster
bash scripts/add-mailbox.sh musteri.com info
bash scripts/add-mailbox.sh musteri.com support 2048 "Dəstək Xidməti"
```

Parol hər dəfə generasiya olunur və **yalnız bir dəfə** göstərilir.

> `postmaster@` mütləq yaradılsın — DMARC hesabatları oraya gəlir.

## 5. Domain admin təyin et

```bash
bash scripts/add-domain-admin.sh musteri musteri.com
```

Bundan sonra müştəri `https://mailbox.tural.ai/` ünvanına həmin istifadəçi adı və parolla girir və **yalnız öz domenində** mailbox/alias idarə edir.

**Domain admin yeni domen əlavə edə bilmir** — bu, Mailcow-un rol modelidir. Domen əlavə etmək həmişə səndən (super-admin) keçir.

## 6. Test

```bash
# Göndərmə: webmail-dən mail-tester.com-a mail at
# https://mailbox.tural.ai/SOGo/  →  hədəf: 9-10/10
```

Yeni domenin ilk maillərinin spama düşməsi normaldır — IP reputasiyası bir neçə gündə oturur.

---

## Bir dəfəlik: API açarı

Skriptlər Mailcow API-si ilə işləyir.

1. Paneldə: **System → Configuration → Access → API**
2. `Activate API` işarələ, **Read-Write access** seç
3. `Allow API access from these IPs` sahəsinə serverin IP-sini yaz
4. Açarı kopyala, serverdə:

```bash
cd /opt/MailBox
cp secrets.env.example secrets.env
chmod 600 secrets.env
nano secrets.env          # MAILCOW_API_KEY=... yaz
bash scripts/api-test.sh  # ✅ görməlisən
```

`secrets.env` `.gitignore`-dadır — git-ə düşmür.

403 alsan, `api-test.sh` serverin xaricə görünən IP-sini yazır; onu icazə siyahısına əlavə et.

---

## Qeydlər

- **DNS avtomatik yazılmır.** Müştəri domenlərinin DNS-i bizdə olmadığı üçün skript qeydləri yalnız **yaradır və yoxlayır**. Gələcəkdə DNS-i bizim Cloudflare hesabımızda olan domenlər üçün avtomatik yazma əlavə edilə bilər.
- **Kvotalar** `config.env`-dədir. Disk vəziyyətinə görə tənzimlə.
- **Mailcow yeniləməsi** həmişə `sudo bash scripts/mailcow-update.sh` ilə (birbaşa `./update.sh` Docker daemon-u restart etməyə çalışır).
