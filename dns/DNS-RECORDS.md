# DNS və PTR qeydləri

İki hissə var:
1. **Bir dəfəlik** — mail serverin özü (`MAIL_HOSTNAME`) üçün.
2. **Hər müştəri domeni üçün** — panelə domen əlavə edəndə təkrarlanır.

Aşağıda `mail.example.com` = sənin `MAIL_HOSTNAME`, `<SERVER_IP>` = serverin public IPv4-ü,
`musteri.com` = əlavə etdiyin hər hansı domen.

---

## 1) Bir dəfəlik — mail serverin infrastruktur qeydləri

`mail.example.com`-un DNS zonasında (bu domeni sən idarə edirsən):

| Tip | Ad             | Dəyər         |
|-----|----------------|---------------|
| A   | mail           | `<SERVER_IP>` |

### PTR (reverse DNS) — Hostinger paneli
Videodakı kimi: **VPS → Ayarlar → IP → Reverse DNS**.
`<SERVER_IP>` üçün PTR-i `mail.example.com` et.
IPv6 varsa, onun da PTR-ni eyni ada qur.
> PTR düzgün olmasa, Gmail/Outlook maillərini rədd edə və ya spama atar. Ən vacib addımlardan biridir.

---

## 2) Hər müştəri domeni üçün (`musteri.com`)

Panelə domen əlavə edəndən sonra `musteri.com`-un DNS-inə bunları yaz.
Mailcow admin paneli **hazır dəyərləri göstərir** (Configuration → Mail setup → DNS),
xüsusən DKIM açarını — onu birbaşa oradan kopyala.

| Tip   | Ad                    | Dəyər (nümunə)                                              |
|-------|-----------------------|------------------------------------------------------------|
| MX    | `@`                   | `mail.example.com` (priority 10)                           |
| A     | (yalnız `mail.example.com` üçün, yuxarıda) | —                                     |
| TXT   | `@`  (SPF)            | `v=spf1 mx a:mail.example.com -all`                        |
| TXT   | `dkim._domainkey`     | *(Mailcow paneldən verdiyi uzun DKIM açarı)*               |
| TXT   | `_dmarc`              | `v=DMARC1; p=quarantine; rua=mailto:postmaster@musteri.com`|

### Qeydlər
- **MX** həmişə `mail.example.com`-a işarə edir — müştəri domeninin öz altında mail hostu yaratma.
- **SPF** (`-all`) yalnız sənin serverindən mail getməsinə icazə verir.
- **DKIM** açarını mütləq paneldən götür — hər domen üçün fərqlidir.
- **DMARC** başlanğıcda `p=quarantine`; hər şey oturuşandan sonra `p=reject`-ə keçə bilərsən.
- **Autodiscover/autoconfig** (istəyə görə, Outlook/Thunderbird avtomatik qurulması üçün):
  `CNAME  autoconfig.musteri.com  ->  mail.example.com`
  `CNAME  autodiscover.musteri.com  ->  mail.example.com`

---

## Yoxlama
Qeydləri yazandan sonra (yayılma 10–60 dəq çəkə bilər):

```bash
dig +short MX musteri.com
dig +short TXT musteri.com          # SPF
dig +short TXT dkim._domainkey.musteri.com
dig +short -x <SERVER_IP>           # PTR
```

Mailcow admin paneli də **System → DNS check** ilə hər domenin qeydlərini yoxlayır —
hamısı yaşıl olmalıdır.
