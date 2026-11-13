# OpenCode Unlimited — نسخهٔ V2

پورت غیررسمی پروژهٔ [`opencode-unlimited-usage`](https://github.com/ElectronBreach/opencode-unlimited-usage)
برای **OpenCode 2.x**: انتخاب تصادفی یک edge از Cloudflare در هر اجرا، چرخش خودکار
`/64` آی‌پی‌وی‌6 با WARP، و یک kill-switch که در صورت قطع تونل، ترافیک را بیرون نمی‌فرستد.

[English](README.md) · [معماری](docs/ARCHITECTURE.md) · [عیب‌یابی](docs/TROUBLESHOOTING.md) · [تفاوت V1/V2](docs/V1-V2.md) · [امنیت](SECURITY.md)

> [!WARNING]
> این پروژه غیررسمی است و به OpenCode یا Cloudflare وابستگی ندارد. عوض کردن هویت شبکه
> برای دور زدن سهمیهٔ رایگان ممکن است خلاف شرایط استفادهٔ سرویس باشد و به محدود شدن
> حساب منجر شود. مسئولیتش با خودت است.

---

## چرا این نسخه ساخته شد

OpenCode 2 دو چیز را عوض کرد که اسکریپت‌های V1 را از کار می‌انداخت:

1. **درخواست‌ها به سرور پس‌زمینه منتقل شدند.** در V2 یک سرور مشترک برای هر کاربر
   اجرا می‌شود و TUI فقط کلاینت است. اگر سرور بیرون از namespace لین باشد، pin کردن
   `/etc/hosts` فایده‌ای ندارد. پس لین یک **سرور خصوصی** (`--standalone`) می‌سازد و
   نصب‌کننده سرور مشترک را خاموش می‌کند (`opencode service set disabled true`).
2. **خطای سهمیه به SQLite منتقل شد.** V2 خطای `provider.free-limit` را قابل‌اعتماد در
   `opencode.log` نمی‌نویسد؛ آن را در `session_message.data` داخل
   `~/.local/share/opencode/opencode.db` ذخیره می‌کند. guard حالا این دیتابیس را
   فقط‌خواندنی می‌خواند و اسکن log به‌عنوان fallback می‌ماند.

بقیهٔ طرح (WARP TUN، چرخش `/64`، kill-switch، keeper) همان نسخهٔ اصلی است.

---

## چطور کار می‌کند

```text
opencode (wrapper) ──► zen-lane.sh
                       ├─ unshare -rm            (namespace خصوصی)
                       ├─ /etc/hosts             (opencode.ai = یک edge تصادفی Cloudflare)
                       ├─ /etc/machine-id        (تصادفی)
                       └─ opencode --standalone  (سرور خصوصی، داخل همان namespace)

Cloudflare WARP ──► برای هر registration یک IPv6 /64 تازه

keeper (سرویس root)              zen-guard (سرویس کاربر)
├─ TUN mode را تحمیل می‌کند      ├─ DB را برای provider.free-limit می‌خواند
├─ تونل را برمی‌گرداند            ├─ /64 سوخته را blacklist می‌کند
└─ OUC_LEAKGUARD را می‌سازد      ├─ WARP را دوباره register می‌کند
                                 └─ keeper را برمی‌گرداند

zen-hop = چرخش دستی              doctor = گزارش سلامت فقط‌خواندنی
```

بعد از هر لیمیت لازم نیست OpenCode را ببندی؛ guard آی‌پی خروجی میزبان را عوض می‌کند و
درخواست بعدی از `/64` جدید می‌رود. فقط **پیام را دوباره بفرست**.

---

## پیش‌نیازها

- لینوکس با systemd (تست‌شده روی **Linux Mint 22.3** و **Ubuntu 24.04**)
- Python 3.10+، `curl`، `iptables`/`ip6tables`، `/dev/net/tun`
- user namespace غیررایگان (`unshare -rm`)
- شبکه‌ای که WARP در آن وصل شود
- `~/.local/bin` **قبل از** `~/.opencode/bin` در `PATH` (نصب‌کننده یک بلوک قابل‌حذف
  اضافه می‌کند)

## نصب

```bash
git clone https://github.com/asgtey/opencode-unlimited-v2.git
cd opencode-unlimited-v2
chmod +x install.sh uninstall.sh scripts/*.sh
./install.sh
exec $SHELL
opencode
```

نصب‌کننده به ترتیب:

1. systemd، Python، curl، TUN و `unshare` را بررسی می‌کند؛
2. OpenCode 2.x را نصب/ارتقا می‌دهد — **قبلش از دادهٔ V1 بکاپ می‌گیرد**؛
3. `opencode service set disabled true` را اجرا می‌کند؛
4. WARP را نصب می‌کند (با کدنام پایهٔ Ubuntu، پس روی Mint هم کار می‌کند)؛
5. سرویس root به نام `opencode-unlimited-keeper` را نصب می‌کند؛
6. سرویس کاربر `opencode-unlimited-guard` را نصب می‌کند؛
7. فایل `~/.local/bin/opencode` را به لین وصل می‌کند و بلوک PATH می‌نویسد؛
8. خروجی IPv6 را تست می‌کند.

> با `sudo` اجرا نکن. خودش هرجا لازم باشد رمز می‌پرسد.

## بررسی سلامت

```bash
opencode --version                  # باید 2.x
opencode-unlimited-doctor           # همه سبز، یا راه‌حل کنار هر خط قرمز
opencode debug paths db             # دیتابیس واقعی V2
curl -6 -s https://api64.ipify.org  # باید 2606:... یا 2a09:... باشد
```

## استفادهٔ روزمره

- وقتی لیمیت دیدی، **۱۵ تا ۹۰ ثانیه صبر کن** و **پیام را دوباره بفرست**.
- چرخش دستی: `opencode-unlimited-hop` (اگر گفت `same /64` دوباره اجرا کن).
- گزارش: `opencode-unlimited-doctor`.
- لاگ‌ها: `~/.local/share/opencode-unlimited/guard/guard.log` و
  `journalctl --user -u opencode-unlimited-guard -f`.

## تنظیمات

نصب‌کننده این‌ها را در یونیت guard می‌نویسد؛ همه اختیاری‌اند:

| متغیر | معنی |
|---|---|
| `OUC_REAL_BIN` | باینری واقعی OpenCode (هرگز wrapper) |
| `OUC_WARP_BIN` | مسیر `warp-cli` |
| `OUC_KEEPER_UNIT` | نام یونیت keeper |
| `OUC_IPTABLES` / `OUC_IP6TABLES` | مسیر ابزارهای فایروال |
| `OUC_SYSTEMCTL` | مسیر `systemctl` |

مسیرهای مهم:

| مسیر | کاربرد |
|---|---|
| `~/.local/share/opencode-unlimited/scripts/` | اسکریپت‌های نصب‌شده |
| `~/.local/share/opencode-unlimited/guard/state.json` | blacklist و شمارنده‌ها |
| `~/.local/share/opencode/opencode.db` | دیتابیس نشست V2 (فقط‌خواندنی) |
| `~/.local/share/opencode/log/` | fallback لاگ |
| `~/.local/share/opencode-unlimited-backups/` | بکاپ قبل از مهاجرت V1 |

## عیب‌یابی

راهنمای کامل: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md). پنج مورد رایج:

| نشانه | راه‌حل |
|---|---|
| `unshare -rm` خطا می‌دهد | `kernel.apparmor_restrict_unprivileged_userns=0` |
| `apt` مخزن WARP را رد می‌کند (`zena`) | خط مخزن باید `noble` باشد (نصب‌کننده انجام می‌دهد) |
| `opencode` از لین عبور نمی‌کند | `source ~/.config/opencode-unlimited/path.sh` |
| خروجی IPv6 ندارد | WARP وصل نیست؛ `warp-cli status` |
| اینترنت بعد از نصب قطع شد | WARP در دسترس نیست → بخش «خروج اضطراری» در [SECURITY.md](SECURITY.md) |

## حذف

```bash
cd opencode-unlimited-v2
./uninstall.sh
```

هر دو سرویس را متوقف و حذف می‌کند، زنجیرهٔ `OUC_LEAKGUARD` را پاک می‌کند، فایل
sudoers و بلوک PATH را برمی‌دارد، `~/.local/bin/opencode` را به باینری اصلی برمی‌گرداند
و سرویس مشترک V2 را دوباره فعال می‌کند. داده، نشست‌ها، auth و بکاپ V1 دست‌نخورده
می‌مانند.

## امنیت (خلاصه)

- kill-switch فقط loopback، LAN، اتصال‌های established، محدودهٔ کنترل WARP و اینترفیس
  WARP را عبور می‌دهد. اگر تونل قطع باشد، ترافیک **جایی نمی‌رود**.
- لین اگر `unshare` یا bind روی `/etc/hosts` شکست بخورد، fail-closed می‌کند.
- guard/hop اگر `OUC_LEAKGUARD` نباشد، تونل را پایین نمی‌آورند.
- ریسک باقی‌مانده: قاعدهٔ `2606:4700::/32` برای صفحهٔ کنترل WARP لازم است ولی broad
  است. راه سخت‌گیرانه‌تر در [SECURITY.md](SECURITY.md) آمده است.
- `NOPASSWD` برای `warp-cli` لازم است؛ فرض پروژه، سیستم شخصی تک‌کاربره است.

## سازگاری

- OpenCode **2.x** (توسعه با 2.2.7). برای V1 fallback جزئی وجود دارد (تشخیص از log،
  بدون `--standalone`) اما نصب‌کننده V2 را هدف گرفته است.
- **اپ دسکتاپ و IDEها** wrapper را دور می‌زنند و از pin کردن edge استفاده نمی‌کنند.
  فقط `opencode` ترمینالی از لین عبور می‌کند.
- در حالت غیرفعال بودن سرویس مشترک، Pairing در V2 کار نمی‌کند.

## اعتبار

- پروژهٔ اصلی: [ElectronBreach/opencode-unlimited-usage](https://github.com/ElectronBreach/opencode-unlimited-usage) (MIT).
- سازگارسازی V2: همین مخزن.
- وابسته به OpenCode یا Cloudflare نیست.

## مجوز

MIT — فایل [LICENSE](LICENSE). اطلاعیهٔ کپی‌رایت اصلی حفظ شده است.
