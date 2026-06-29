# PasarGuard Easy Restore

اسکریپت ساده و خودکار برای ریستور کردن بکاپ PasarGuard روی سرور خام Ubuntu.

این اسکریپت برای زمانی ساخته شده که شما یک فایل بکاپ ZIP از PasarGuard دارید و می‌خواهید خیلی راحت روی یک سرور جدید یا خام، پنل را دوباره بالا بیاورید.

---

## امکانات اسکریپت

این اسکریپت به صورت خودکار این کارها را انجام می‌دهد:

* نصب پکیج‌های مورد نیاز
* نصب Docker اگر روی سرور نصب نباشد
* پیدا کردن فایل بکاپ ZIP در مسیر `/root`
* امکان وارد کردن مسیر فایل بکاپ به صورت دستی
* استخراج فایل بکاپ
* برگرداندن فایل‌های اصلی PasarGuard
* ریستور دیتابیس TimescaleDB
* تنظیم IP یا دامنه پنل
* تنظیم پورت پنل
* اجرای پنل PasarGuard
* نصب دستور `pasarguard`
* امکان فعال‌سازی بکاپ خودکار تلگرام

---

## این اسکریپت برای چه چیزی مناسب است؟

این اسکریپت مناسب است برای:

* انتقال PasarGuard به سرور جدید
* بالا آوردن بکاپ روی سرور خام
* ریستور سریع بعد از تعویض سرور
* راه‌اندازی آسان بدون نیاز به انجام دستی مراحل Docker و دیتابیس

---

## نکته مهم

این اسکریپت باید روی **سرور لینوکس** اجرا شود، نه روی ویندوز.

یعنی اول باید وارد سرور شوید:

```bash
ssh root@SERVER_IP
```

بعد دستورات نصب و اجرا را داخل همان سرور بزنید.

اگر دستورهایی مثل `chmod` یا `bash` را داخل CMD ویندوز بزنید، خطا می‌گیرید.

---

## مرحله 1: ارسال فایل بکاپ به سرور

اول فایل بکاپ ZIP را از کامپیوتر خودتان به سرور بفرستید.

مثال:

```bash
scp backup.zip root@SERVER_IP:/root/
```

مثلاً:

```bash
scp backup_20260624.zip root@143.14.59.226:/root/
```

فایل بکاپ باید داخل مسیر `/root` سرور قرار بگیرد.

---

## مرحله 2: ورود به سرور

بعد وارد سرور شوید:

```bash
ssh root@SERVER_IP
```

مثال:

```bash
ssh root@143.14.59.226
```

---

## مرحله 3: اجرای اسکریپت

داخل سرور این دستورها را بزنید:

```bash
curl -fsSL https://raw.githubusercontent.com/amirjrha/pasarguard-easy-restore/main/pg-restore-wizard.sh -o pg-restore-wizard.sh
chmod +x pg-restore-wizard.sh
bash pg-restore-wizard.sh
```

---

## مرحله 4: سوال‌هایی که اسکریپت می‌پرسد

اسکریپت هنگام اجرا چند سوال ساده می‌پرسد.

### مسیر فایل بکاپ

اگر فایل بکاپ داخل `/root` باشد، فقط Enter بزنید.

اگر فایل جای دیگری است، مسیر کامل آن را وارد کنید.

مثال:

```text
/root/backup.zip
```

---

### IP یا دامنه پنل

اینجا IP سرور یا دامنه خودتان را وارد کنید.

مثال:

```text
143.14.59.226
```

یا اگر دامنه دارید:

```text
panel.example.com
```

---

### پورت پنل

اگر می‌خواهید پنل روی پورت پیش‌فرض HTTPS بالا بیاید، عدد زیر را بزنید:

```text
443
```

اگر می‌خواهید روی پورت دلخواه بالا بیاید، مثلاً:

```text
2056
```

بعد پنل با این آدرس باز می‌شود:

```text
https://SERVER_IP:2056/
```

یا:

```text
https://SERVER_IP:2056/dashboard/
```

---

### تایید حذف فایل‌های قبلی

اسکریپت برای امنیت از شما می‌خواهد تایید کنید.

باید دقیقاً بنویسید:

```text
YES
```

با حروف بزرگ.

---

### بکاپ خودکار تلگرام

در پایان، اسکریپت می‌پرسد آیا بکاپ خودکار تلگرام می‌خواهید یا نه.

اگر نمی‌خواهید، بزنید:

```text
n
```

اگر می‌خواهید، بزنید:

```text
y
```

بعد از شما می‌پرسد:

* Telegram Bot Token
* Telegram Chat ID
* هر چند ساعت بکاپ بگیرد

مثلاً برای بکاپ هر یک ساعت:

```text
1
```

---

## بعد از پایان نصب

بعد از پایان کار، اسکریپت آدرس پنل را نمایش می‌دهد.

مثلاً:

```text
https://143.14.59.226:2056/dashboard/
```

اگر مرورگر اخطار SSL داد، گزینه زیر را بزنید:

```text
Advanced
Proceed
```

این طبیعی است چون معمولاً SSL روی IP معتبر نیست.

---

## دستورات کاربردی بعد از نصب

برای دیدن وضعیت کانتینرها:

```bash
cd /opt/pasarguard
docker compose ps
```

برای دیدن لاگ پنل:

```bash
cd /opt/pasarguard
docker compose logs --tail=100 pasarguard
```

برای ریستارت پنل:

```bash
cd /opt/pasarguard
docker compose restart pasarguard
```

یا:

```bash
pasarguard restart
```

برای دیدن وضعیت PasarGuard:

```bash
pasarguard status
```

---

## مسیرهای مهم

فایل‌های اصلی پنل:

```text
/opt/pasarguard
```

دیتا و فایل‌های PasarGuard:

```text
/var/lib/pasarguard
```

فایل بکاپ ریستور شده:

```text
/root
```

---


* فایل‌های دیتابیس

این ریپو فقط برای اسکریپت است، نه برای بکاپ‌ها و اطلاعات خصوصی.

---

## حذف بکاپ خودکار تلگرام

اگر بعداً خواستید بکاپ خودکار تلگرام را حذف کنید، روی سرور بزنید:

```bash
(crontab -l 2>/dev/null | grep -v auto-pasarguard-backup.sh) | crontab -
rm -f /root/auto-pasarguard-backup.sh
rm -f /root/.pgbackup.env
rm -f /var/log/pasarguard-backup.log
```

---

## جمع‌بندی سریع

روی کامپیوتر خودتان:

```bash
scp backup.zip root@SERVER_IP:/root/
```

بعد وارد سرور شوید:

```bash
ssh root@SERVER_IP
```

بعد داخل سرور بزنید:

```bash
curl -fsSL https://raw.githubusercontent.com/amirjrha/pasarguard-easy-restore/main/pg-restore-wizard.sh -o pg-restore-wizard.sh
chmod +x pg-restore-wizard.sh
bash pg-restore-wizard.sh
```

تمام.
