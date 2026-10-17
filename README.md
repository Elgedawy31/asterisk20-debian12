# Asterisk 20 LTS on Debian 12

One script that builds and installs **Asterisk 20.21.0** (LTS) on a clean
**Debian 12 (bookworm) amd64** from the official source release, and runs it
as a systemd service.

```sh
git clone https://github.com/Elgedawy31/asterisk20-debian12.git
cd asterisk20-debian12
sudo ./install-asterisk20.sh
```

It needs internet access and takes about 10-20 minutes (mostly compiling).

## What it does

1. Installs the build dependencies with `apt`.
2. Downloads `asterisk-20.21.0.tar.gz` from `downloads.asterisk.org` and
   **refuses to build unless its SHA-256 matches** the one pinned in the script
   (the same as the release's `.sha256`; the release is also GPG-signed by the
   Asterisk Development Team, key `F2FC 93DB 7587 BD1F B49E 045A 5D98 4BE3 3719 1CE7`).
3. Builds it (bundled pjproject) and installs it under `/usr`, plus headers
   for out-of-tree channel drivers and logrotate.
4. Installs the sample configs into `/etc/asterisk` **only if there are none**
   (an existing configuration is never overwritten).
5. Runs it as the unprivileged user `asterisk` with the upstream systemd unit
   (`contrib/systemd/asterisk.service`).

It does not change the firewall, the network or any other service.

## After installing

| | |
| --- | --- |
| Configs | `/etc/asterisk/` |
| CLI | `sudo asterisk -rvvv` |
| Service | `sudo systemctl status asterisk` (also `restart`, `stop`) |
| Logs | `/var/log/asterisk/`, `journalctl -u asterisk` |
| Build log | `/var/log/asterisk-build.log` |
| Source tree | `/usr/src/asterisk-20.21.0` |

The stock sample `pjsip.conf` defines no transport: add one (e.g. UDP on
5060) before endpoints can register.

Options: `REINSTALL=1` builds over an existing install; `ALLOW_UNSUPPORTED=1`
tries on a system other than Debian 12 amd64.

To remove: `sudo systemctl disable --now asterisk`, then
`cd /usr/src/asterisk-20.21.0 && sudo make uninstall` (`make uninstall-all`
also deletes configs, logs and spool).

---

## بالعربي

سكريبت واحد بيبني ويثبّت **Asterisk 20.21.0** (إصدار LTS) على **Debian 12 (bookworm) 64-bit** نضيف، من المصدر الرسمي، وبيشغّله كخدمة.

```sh
git clone https://github.com/Elgedawy31/asterisk20-debian12.git
cd asterisk20-debian12
sudo ./install-asterisk20.sh
```

- محتاج **نت**، وبياخد من 10 لـ 20 دقيقة، أغلبها في البناء.
- بيتأكد من الـ **checksum** بتاع الملف الرسمي قبل البناء، ولو مش مطابق يوقف.
- **ملفات الإعدادات النموذجية** بتتحط في `/etc/asterisk` بس لو المجلد فاضي، يعني مش هيمسح إعدادات موجودة.
- **الخدمة شغالة بمستخدم `asterisk`** مش root.
- **مش بيغيّر** الـ firewall ولا الشبكة ولا أي خدمة تانية.

الدخول على الـ CLI: `sudo asterisk -rvvv`، والإعدادات في `/etc/asterisk/`.

ملحوظة: ملف `pjsip.conf` النموذجي مافيهوش transport، لازم تضيف واحد (مثلًا UDP على 5060) قبل ما أي جهاز يقدر يسجّل.
