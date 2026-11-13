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

<h3 dir="rtl" align="right">با root اجرا نکن</h3>

<p dir="rtl" align="right">
<code>install.sh</code> اگر با root اجرا شود با پیام
<code>run me as your normal user, not root</code> متوقف می‌شود. این عمدی است:
همه‌چیز داخل پوشهٔ کاربر نصب می‌شود، guard یک سرویس <b>کاربر</b> است و قواعد
sudoers به همان حساب گره خورده‌اند. با root همه‌چیز داخل <code>/root</code>
نصب می‌شود و به درد نمی‌خورد.
</p>

<p dir="rtl" align="right">
فقط سه مرحله به root نیاز دارد و خود نصب‌کننده با <code>sudo</code> می‌پرسد. پس
<code>sudo bash get.sh</code> یا <code>sudo ./install.sh</code> اجرا نکن.
</p>

<p dir="rtl" align="right">
اگر با root وارد شده‌ای (روی VPS تازه یا داخل کانتینر رایج است)، اول یک کاربر
عادی بساز:
</p>

<pre dir="ltr" align="left"><code>adduser asghar
usermod -aG sudo asghar
su - asghar</code></pre>

<p dir="rtl" align="right">
روی Fedora یا Arch خط دوم می‌شود <code>usermod -aG wheel asghar</code>.
بعد دوباره دستور نصب را اجرا کن، این بار بدون <code>sudo</code>.
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

<h2 dir="rtl" align="right">چرا این نسخه ساخته شد</h2>

<p dir="rtl" align="right">
OpenCode 2 دو چیز را عوض کرد که اسکریپت‌های نسخهٔ ۱ را از کار می‌انداخت:
</p>

<ol dir="rtl">
  <li>
    <b>درخواست‌ها به یک سرور پس‌زمینه منتقل شدند.</b> TUI فقط کلاینت است. پس این
    پروژه یک سرور خصوصی می‌سازد (<code>--standalone</code>) و سرور مشترک را خاموش
    می‌کند.
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

<h2 dir="rtl" align="right">اتصال از یک دستگاه دیگر (opencode pair)</h2>

<p dir="rtl" align="right">
<code>opencode pair</code> یک لینک یک‌بارمصرف و یک QR می‌سازد که مرورگر یا اپ
OpenCode را به <b>سرور مشترک</b> وصل می‌کند. لینک‌ها ۵ دقیقه اعتبار دارند و فقط
یک بار کار می‌کنند.
</p>

<p dir="rtl" align="right">
مهم: pair به سرویس مشترک نیاز دارد و این پروژه آن را خاموش کرده است. پس برای
pair کردن موقتاً روشنش کن:
</p>

<pre dir="ltr" align="left"><code>opencode service unset disabled
opencode service start
opencode pair</code></pre>

<p dir="rtl" align="right">
لینک را روی دستگاه دیگر باز کن. اگر از راه SSH وصل می‌شوی، اول پورت را فوروارد کن:
</p>

<pre dir="ltr" align="left"><code>ssh -L 49374:127.0.0.1:49374 asghar@your-server</code></pre>

<p dir="rtl" align="right">
بعد از تمام شدن کار، حتماً دوباره خاموشش کن — همین کار لین ترمینال را سالم
نگه می‌دارد:
</p>

<pre dir="ltr" align="left"><code>opencode service set disabled true</code></pre>

<p dir="rtl" align="right">
نشست‌هایی که از مرورگر یا اپ pair شده باز می‌شوند روی سرور مشترک اجرا می‌شوند:
ترافیکشان باز هم از WARP می‌رود و <code>/64</code> باز هم عوض می‌شود، ولی edge
تصادفی مخصوص هر اجرا را ندارند.
</p>

<p dir="rtl" align="right">
راهنمای کامل (شبکهٔ محلی، تونل SSH و <code>--remote</code>) و نکات امنیتی:
<a href="docs/PAIRING.md">docs/PAIRING.md</a>
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
  <li><a href="CONTRIBUTING.md">CONTRIBUTING.md</a> · <a href="CHANGELOG.md">CHANGELOG.md</a></li>
</ul>

<h2 dir="rtl" align="right">اعتبار و مجوز</h2>

<p dir="rtl" align="right">
پروژهٔ اصلی: <a href="https://github.com/ElectronBreach/opencode-unlimited-usage">ElectronBreach/opencode-unlimited-usage</a> (MIT).<br>
سازگارسازی V2: همین مخزن. مجوز MIT — فایل <a href="LICENSE">LICENSE</a>.
</p>
