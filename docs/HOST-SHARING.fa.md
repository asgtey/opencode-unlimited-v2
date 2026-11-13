<h1 dir="rtl" align="right">پروژهٔ روی ویندوز را داخل ماشین مجازی باز کن</h1>

<p dir="rtl" align="right">
پروژه روی ویندوز (یا مک) است و OpenCode داخل لینوکسِ ماشین مجازی نصب شده. برای
اینکه OpenCode همان فایل‌ها را ویرایش کند، فقط باید پوشه را از ویندوز به ماشین
مجازی وصل کنی. بقیه‌اش مثل همیشه است.
</p>

<h2 dir="rtl" align="right">۱. در VMware پوشه را Share کن</h2>

<p dir="rtl" align="right">
ماشین مجازی را <b>کامل خاموش</b> کن (Suspend نه). بعد:
</p>

<ol dir="rtl">
  <li><code>VM → Settings → Options → Shared Folders</code></li>
  <li>گزینهٔ <b>Always enabled</b> را انتخاب کن</li>
  <li><b>Add…</b> را بزن:
    <ul>
      <li>Host path: مسیر پروژه در ویندوز، مثلاً <code>C:\Users\you\my-project</code></li>
      <li>Name: <code>my-project</code></li>
      <li>تیک <b>Read-only</b> را نزن</li>
    </ul>
  </li>
  <li>OK، بعد ماشین را روشن کن</li>
</ol>

<h2 dir="rtl" align="right">۲. داخل مینت پوشه را ببین</h2>

<pre dir="ltr" align="left"><code>sudo apt install -y open-vm-tools open-vm-tools-desktop
vmware-hgfsclient</code></pre>

<p dir="rtl" align="right">
اسمی که چاپ شد (مثلاً <code>my-project</code>) یعنی اشتراک درست است. حالا وصلش کن:
</p>

<pre dir="ltr" align="left"><code>sudo mkdir -p /mnt/hgfs
sudo vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other,uid=$(id -u),gid=$(id -g)
ls /mnt/hgfs</code></pre>

<p dir="rtl" align="right">
آن <code>uid</code> و <code>gid</code> مهم‌اند؛ وگرنه فایل‌ها مال root می‌شوند و
OpenCode نمی‌تواند ذخیره کند.
</p>

<p dir="rtl" align="right">
اگر می‌خواهی بعد از ریبوت هم بماند:
</p>

<pre dir="ltr" align="left"><code>echo '.host:/ /mnt/hgfs fuse.vmhgfs-fuse allow_other,uid='"$(id -u)"',gid='"$(id -g)"',defaults 0 0' | sudo tee -a /etc/fstab
sudo mount -a</code></pre>

<p dir="rtl" align="right">
اگر <code>/mnt/hgfs</code> خالی بود، ماشین را کامل خاموش و روشن کن (Suspend معمولاً
اشتراک را نمی‌آورد) و مطمئن شو <code>open-vm-tools</code> نصب است.
</p>

<h2 dir="rtl" align="right">۳. در OpenCode بازش کن</h2>

<p dir="rtl" align="right">
یا اول برو داخل پوشه:
</p>

<pre dir="ltr" align="left"><code>cd /mnt/hgfs/my-project
opencode</code></pre>

<p dir="rtl" align="right">
یا مسیر را مستقیم بده:
</p>

<pre dir="ltr" align="left"><code>opencode /mnt/hgfs/my-project</code></pre>

<p dir="rtl" align="right">
همین. فایل‌ها را می‌خواند و ذخیره می‌کند، مستقیم روی ویندوز.
</p>

<h2 dir="rtl" align="right">دو اصلاح که احتمالاً لازم می‌شود</h2>

<p dir="rtl" align="right">
git روی پوشه‌ای که مال uid دیگری است گیر می‌دهد:
</p>

<pre dir="ltr" align="left"><code>git config --global --add safe.directory /mnt/hgfs/my-project</code></pre>

<p dir="rtl" align="right">
و چون در پوشهٔ مشترک همهٔ فایل‌ها «اجرایی» دیده می‌شوند، git پر از تغییر mode
می‌شود:
</p>

<pre dir="ltr" align="left"><code>git -C /mnt/hgfs/my-project config core.filemode false</code></pre>

<h2 dir="rtl" align="right">محدودیت‌های پوشهٔ مشترک</h2>

<table>
  <thead>
    <tr><th align="right">مورد</th><th align="right">نتیجه</th></tr>
  </thead>
  <tbody>
    <tr><td align="right">symlink</td><td align="right">پشتیبانی نمی‌شود</td></tr>
    <tr><td align="right">اعلام تغییر فایل</td><td align="right">ندارد؛ ابزارها polling می‌کنند</td></tr>
    <tr><td align="right">سرعت</td><td align="right">۳ تا ۱۰ برابر کندتر از دیسک ماشین</td></tr>
    <tr><td align="right"><code>node_modules</code> و <code>venv</code></td><td align="right">کند و اغلب خراب می‌شود</td></tr>
  </tbody>
</table>

<p dir="rtl" align="right">
برای فایل‌های متنی، اسکریپت، تنظیمات و مارک‌داون عالی است. اگر پروژه وابستگی
زیادی دارد، نسخهٔ اصلی را روی دیسک ماشین نگه دار و با git سینک کن.
</p>

<h2 dir="rtl" align="right">روش‌های دیگر</h2>

<p dir="rtl" align="right"><b>SMB (سریع‌تر از پوشهٔ مشترک):</b></p>

<pre dir="ltr" align="left"><code>sudo apt install -y cifs-utils
sudo mount -t cifs //HOST-IP/my-project /mnt/project -o username=YOUR-WINDOWS-USER,uid=$(id -u),gid=$(id -g),vers=3.0</code></pre>

<p dir="rtl" align="right"><b>SSHFS (روی ویندوز باید OpenSSH Server روشن باشد):</b></p>

<pre dir="ltr" align="left"><code>sudo apt install -y sshfs
sshfs you@HOST-IP:C:/Users/you/my-project ~/host-project
cd ~/host-project && opencode</code></pre>

<p dir="rtl" align="right"><b>VirtualBox:</b> Settings → Shared Folders → Add، بعد
<code>virtualbox-guest-utils</code> را نصب کن و با
<code>sudo mount -t vboxsf -o uid=$(id -u),gid=$(id -g) my-project /mnt/project</code>
وصلش کن.
</p>
