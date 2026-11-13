<h1 dir="rtl" align="right">OpenCode Unlimited — نسخهٔ ۲</h1>

<p dir="rtl" align="right">
دور زدن محدودیت سهمیهٔ رایگان OpenCode روی لینوکس، با <b>یک دستور نصب</b>.<br>
وقتی محدودیت می‌خورد، هویت شبکه‌ات خودکار عوض می‌شود و به کارت ادامه می‌دهی.
</p>

<p dir="rtl" align="right">
<a href="README.md">English</a> ·
<a href="docs/TROUBLESHOOTING.md">عیب‌یابی</a> ·
<a href="docs/PAIRING.md">اتصال از دستگاه دیگر</a> ·
<a href="docs/ARCHITECTURE.md">طرز کار</a> ·
<a href="SECURITY.md">امنیت</a>
</p>

<hr>

<blockquote dir="rtl">
<p align="right">
⚠️ <b>غیررسمی است.</b> به OpenCode یا Cloudflare وابستگی ندارد. عوض کردن هویت شبکه
برای دور زدن سهمیهٔ رایگان ممکن است خلاف شرایط استفادهٔ سرویس باشد. مسئولیتش با خودت است.
</p>
</blockquote>

<h2 dir="rtl" align="right">نصب با یک دستور</h2>

<p dir="rtl" align="right">
این مخزن عمومی است؛ به هیچ کد دسترسی یا حساب گیت‌هاب نیاز نداری. فقط این را بزن:
</p>

<pre dir="ltr" align="left"><code>curl -fsSL https://raw.githubusercontent.com/asgtey/opencode-unlimited-v2/main/get.sh | bash</code></pre>

<p dir="rtl" align="right">
بعد ترمینال را ببند و باز کن، و مثل همیشه بنویس <code>opencode</code>.
</p>

<p dir="rtl" align="right">
این دستور کل پروژه را در یک پوشهٔ موقت دانلود می‌کند، <code>install.sh</code> را اجرا
می‌کند (رمز sudo را می‌پرسد) و بعد پوشه را پاک می‌کند. به <code>git</code> نیازی نیست.
</p>

<p dir="rtl" align="right"><b>پیش‌نیازها:</b></p>

<ul dir="rtl">
  <li>لینوکس با systemd — تست‌شده روی Linux Mint 22.3 و Ubuntu 24.04</li>
  <li>دسترسی <code>sudo</code> و <code>python3</code></li>
  <li>شبکه‌ای که Cloudflare WARP در آن وصل شود</li>
</ul>

<p dir="rtl" align="right">
اگر دانلود انجام نشد، یعنی مشکل شبکه است؛ همان دستور را دوباره بزن. راه دستی:
</p>

<pre dir="ltr" align="left"><code>git clone https://github.com/asgtey/opencode-unlimited-v2.git
cd opencode-unlimited-v2 && ./install.sh</code></pre>

<h3 dir="rtl" align="right">با root اجرا کنی، خودش کاربر می‌سازد</h3>

<p dir="rtl" align="right">
همه‌چیز داخل پوشهٔ کاربر نصب می‌شود و guard یک سرویس <b>کاربر</b> است، پس داخل
<code>/root</code> کار نمی‌کند. اگر با root اجرا کنی، نصب‌کننده دو چیز می‌پرسد —
نام کاربر و رمز عبور (دو بار، و چیزی روی صفحه نشان داده نمی‌شود) — بعد آن حساب را
می‌سازد، به گروه <code>sudo</code> اضافه‌اش می‌کند و نصب را با همان کاربر ادامه
می‌دهد. همان رمزی که خودت نوشتی رمز ورودت است؛ رمز تصادفی چاپ نمی‌شود.
</p>

<p dir="rtl" align="right">
اگر کاربر عادی هستی، دستور را با <code>sudo</code> اجرا نکن؛ خودش هرجا لازم شد
رمز می‌پرسد.
</p>

<h2 dir="rtl" align="right">وقتی محدودیت خورد</h2>

<ol dir="rtl">
  <li>هیچ کاری نکن.</li>
  <li>۱۵ تا ۹۰ ثانیه صبر کن — <code>zen-guard</code> دارد آی‌پی را عوض می‌کند.</li>
  <li>همان پیام را دوباره بفرست.</li>
</ol>

<p dir="rtl" align="right">
اگر همین حالا هویت تازه می‌خواهی:
</p>

<pre dir="ltr" align="left"><code>opencode-unlimited-hop</code></pre>

<p dir="rtl" align="right">
گزارش سلامت:
</p>

<pre dir="ltr" align="left"><code>opencode-unlimited-doctor</code></pre>

<h2 dir="rtl" align="right">چه چیزهایی نصب می‌شود</h2>

<ul dir="rtl">
  <li><code>zen-lane</code> — <code>opencode</code> را با یک edge تصادفی Cloudflare و یک سرور خصوصی اجرا می‌کند</li>
  <li><code>zen-guard</code> — خطای محدودیت را می‌بیند و WARP را روی یک <code>/64</code> تازه می‌برد</li>
  <li><code>warp-keeper</code> — سرویس root: تونل را زنده و kill-switch را نصب‌شده نگه می‌دارد</li>
  <li><code>zen-hop</code> — چرخش دستی، «همین حالا یک <code>/64</code> تازه بده»</li>
  <li><code>doctor</code> — گزارش سلامت، فقط‌خواندنی</li>
</ul>

<p dir="rtl" align="right">
همه‌چیز داخل <code>~/.local/share/opencode-unlimited/</code> است. تنها جاهایی که به
سیستم دست می‌زند: دو یونیت systemd، یک فایل sudoers و یک زنجیرهٔ فایروال — که
<code>uninstall.sh</code> همه را برمی‌دارد.
</p>

<h3 dir="rtl" align="right">لاگ‌ها</h3>

<p dir="rtl" align="right">
اگر چیزی درست کار نکرد، آخرین خطوط لاگ guard معمولاً می‌گوید چرا:
</p>

<pre dir="ltr" align="left"><code>tail -n 20 ~/.local/share/opencode-unlimited/guard/guard.log</code></pre>

<p dir="rtl" align="right">
<code>opencode-unlimited-doctor</code> همان تصویر را در یک صفحه نشان می‌دهد. فایل
کم‌کم بزرگ می‌شود، پس <code>-n 20</code> معمولاً کافی است؛ بعد از یک روز شلوغ
<code>-n 100</code> بزن.
</p>

<h2 dir="rtl" align="right">چرا این نسخه ساخته شد</h2>

<p dir="rtl" align="right">
OpenCode 2 دو چیز را عوض کرد که اسکریپت‌های نسخهٔ ۱ را از کار می‌انداخت:
</p>

<ol dir="rtl">
  <li>
    <b>درخواست‌ها به یک سرور پس‌زمینه منتقل شدند.</b> TUI فقط کلاینت است. پس این
    پروژه در هر اجرا یک سرور خصوصی می‌سازد (<code>--standalone</code>) و همان
    سرور خصوصی است که edge پین‌شده را می‌گیرد.
  </li>
  <li>
    <b>خطای محدودیت به دیتابیس رفت.</b> V2 آن را در
    <code>~/.local/share/opencode/opencode.db</code> ذخیره می‌کند، نه در لاگ. guard
    آن دیتابیس را فقط‌خواندنی می‌خواند و لاگ را به‌عنوان پشتیبان نگه می‌دارد.
  </li>
</ol>

<p dir="rtl" align="right">
خود ترفند WARP، چرخش <code>/64</code> و kill-switch دست‌نخورده مانده‌اند.
</p>

<h2 dir="rtl" align="right">امنیت</h2>

<ul dir="rtl">
  <li>kill-switch در حالت <b>fail-closed</b> است: اگر تونل قطع شود، ترافیک هیچ‌جا نمی‌رود و آی‌پی واقعی‌ات لو نمی‌رود.</li>
  <li>اگر namespace یا pin کردن <code>/etc/hosts</code> شکست بخورد، لین بالا نمی‌آید.</li>
  <li>اگر زنجیرهٔ kill-switch نباشد، چرخش انجام نمی‌شود.</li>
  <li>خروج اضطراری و ریسک‌های باقی‌مانده: <a href="SECURITY.md">SECURITY.md</a></li>
</ul>

<h2 dir="rtl" align="right">پروژه‌ای که روی ویندوز یا مک است</h2>

<p dir="rtl" align="right">
لینوکس داخل ماشین مجازی است و پروژه روی ویندوز؛ پوشه را به ماشین وصل کن و داخلش
<code>opencode</code> را بزن. بقیه‌اش مثل همیشه است.
</p>

<p dir="rtl" align="right">
<b>۱. روی ویندوز (VMware):</b> ماشین را کامل خاموش کن، بعد
<code>VM → Settings → Options → Shared Folders</code>، گزینهٔ <b>Always enabled</b> و
<b>Add…</b> (مسیر پوشه و یک اسم؛ تیک Read-only را نزن).
</p>

<p dir="rtl" align="right"><b>۲. داخل مینت:</b></p>

<pre dir="ltr" align="left"><code>sudo apt install -y open-vm-tools open-vm-tools-desktop
sudo mkdir -p /mnt/hgfs
sudo vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other,uid=$(id -u),gid=$(id -g)</code></pre>

<p dir="rtl" align="right">
آن <code>uid</code> و <code>gid</code> مهم‌اند؛ وگرنه فایل‌ها مال root می‌شوند و
<code>opencode</code> نمی‌تواند ذخیره کند.
</p>

<p dir="rtl" align="right"><b>۳. بازش کن:</b></p>

<pre dir="ltr" align="left"><code>cd /mnt/hgfs/my-project
opencode</code></pre>

<p dir="rtl" align="right">
دو دستور git هم احتمالاً لازم می‌شود:
</p>

<pre dir="ltr" align="left"><code>git config --global --add safe.directory /mnt/hgfs/my-project
git -C /mnt/hgfs/my-project config core.filemode false</code></pre>

<p dir="rtl" align="right">
پوشهٔ مشترک symlink ندارد، تغییر فایل را فوری نمی‌فهمد و برای
<code>node_modules</code> کند است. روش‌های SMB، SSHFS، VirtualBox و توضیح pair:
<a href="docs/HOST-SHARING.fa.md">docs/HOST-SHARING.fa.md</a>
</p>

<h2 dir="rtl" align="right">اتصال از گوشی یا کامپیوتر دیگر (pair)</h2>

<p dir="rtl" align="right">
pair از قبل آماده است. فقط این را بزن:
</p>

<pre dir="ltr" align="left"><code>opencode pair</code></pre>

<p dir="rtl" align="right">
لینک یا QR را روی دستگاه دیگر باز کن. یک بار کار می‌کند و ۵ دقیقه اعتبار دارد.
</p>

<p dir="rtl" align="right">
شبکهٔ دیگر؟ <code>opencode pair --remote</code> — از راه SSH؟ اول پورت را فوروارد کن:
</p>

<pre dir="ltr" align="left"><code>ssh -L 49374:127.0.0.1:49374 asghar@your-server</code></pre>

<p dir="rtl" align="right">
در مدتی که pair هستی، ترافیک باز هم از WARP می‌رود و <code>/64</code> عوض می‌شود،
فقط edge تصادفی نداری. اگر هیچ‌وقت pair نمی‌کنی، سرور مشترک را خاموش کن:
<code>opencode service set disabled true</code> — ترمینال همان‌طور کار می‌کند.
جزئیات: <a href="docs/PAIRING.md">docs/PAIRING.md</a>
</p>

<h2 dir="rtl" align="right">حذف</h2>

<pre dir="ltr" align="left"><code>curl -fsSL https://raw.githubusercontent.com/asgtey/opencode-unlimited-v2/main/get.sh | bash -s -- --uninstall</code></pre>

<p dir="rtl" align="right">
نشست‌ها، ورودها و بکاپ‌هایت دست‌نخورده می‌مانند.
</p>

<h2 dir="rtl" align="right">مستندات</h2>

<ul dir="rtl">
  <li><a href="docs/TROUBLESHOOTING.md">docs/TROUBLESHOOTING.md</a> — همهٔ خطاها و راه‌حلشان</li>
  <li><a href="docs/PAIRING.md">docs/PAIRING.md</a> — اتصال از دستگاه دیگر با <code>opencode pair</code></li>
  <li><a href="docs/ARCHITECTURE.md">docs/ARCHITECTURE.md</a> — جزئیات فنی namespace، دیتابیس و فایروال</li>
  <li><a href="docs/V1-V2.md">docs/V1-V2.md</a> — تفاوت خط‌به‌خط با نسخهٔ اصلی</li>
  <li><a href="docs/HOST-SHARING.fa.md">docs/HOST-SHARING.fa.md</a> — باز کردن پروژهٔ روی ویندوز داخل ماشین مجازی</li>
  <li><a href="CONTRIBUTING.md">CONTRIBUTING.md</a> · <a href="CHANGELOG.md">CHANGELOG.md</a></li>
</ul>

<h2 dir="rtl" align="right">اعتبار و مجوز</h2>

<p dir="rtl" align="right">
پروژهٔ اصلی: <a href="https://github.com/ElectronBreach/opencode-unlimited-usage">ElectronBreach/opencode-unlimited-usage</a> (MIT).<br>
سازگارسازی V2: همین مخزن. مجوز MIT — فایل <a href="LICENSE">LICENSE</a>.
</p>
