#!/bin/sh
# Install Asterisk 20 LTS on Debian 12 (bookworm), built from the official
# source release.
#
#   sudo ./install-asterisk20.sh
#
# Downloads the pinned release from downloads.asterisk.org, refuses to build
# unless its SHA-256 matches, builds and installs it (sample configs only when
# /etc/asterisk has none), and runs it as a systemd service under the
# unprivileged user "asterisk". It does not touch the firewall or any other
# service. Build log: /var/log/asterisk-build.log
#
# Environment:
#   REINSTALL=1          build and install over an existing Asterisk
#   ALLOW_UNSUPPORTED=1  try on something other than Debian 12 amd64
set -eu

ASTERISK_VERSION=20.21.0
ASTERISK_SHA256=13fd6e8f1fbb19a3174af82a388dd72c87eb2c92d32fca83c4d51bfab03f686a
URL="https://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-${ASTERISK_VERSION}.tar.gz"
SRC="/usr/src/asterisk-${ASTERISK_VERSION}"
LOG=/var/log/asterisk-build.log

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
# Quiet console, everything in the log; on failure show its tail.
run() { "$@" >>"$LOG" 2>&1 || { tail -n 40 "$LOG" >&2; die "failed: $* (full log: $LOG)"; }; }

[ "$(id -u)" -eq 0 ] || die "run as root: sudo $0"
. /etc/os-release
if [ "${ALLOW_UNSUPPORTED:-0}" != 1 ]; then
    [ "${ID:-}" = debian ] && [ "${VERSION_ID:-}" = 12 ] || \
        die "this script supports Debian 12 (bookworm); found ${PRETTY_NAME:-unknown}. ALLOW_UNSUPPORTED=1 to try anyway."
    [ "$(dpkg --print-architecture)" = amd64 ] || die "amd64 only. ALLOW_UNSUPPORTED=1 to try anyway."
fi
if command -v asterisk >/dev/null 2>&1 && [ "${REINSTALL:-0}" != 1 ]; then
    die "Asterisk is already installed ($(asterisk -V 2>/dev/null || echo unknown)). REINSTALL=1 to build over it."
fi
: >"$LOG"

log "installing build dependencies"
export DEBIAN_FRONTEND=noninteractive
run apt-get update
# libsystemd-dev: the systemd unit is Type=notify; without it Asterisk never
# reports "ready" and systemd restarts it in a loop.
run apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl bzip2 patch pkg-config file python3 \
    libedit-dev libjansson-dev libsqlite3-dev libssl-dev libxml2-dev uuid-dev libsystemd-dev \
    libsrtp2-dev libcurl4-openssl-dev libnewt-dev libspeexdsp-dev libogg-dev libvorbis-dev

log "downloading Asterisk ${ASTERISK_VERSION}"
mkdir -p /usr/src
cd /usr/src
run curl -fSL --retry 3 -o "asterisk-${ASTERISK_VERSION}.tar.gz" "$URL"
echo "${ASTERISK_SHA256}  asterisk-${ASTERISK_VERSION}.tar.gz" | sha256sum -c - >/dev/null 2>&1 || \
    die "SHA-256 mismatch for asterisk-${ASTERISK_VERSION}.tar.gz - refusing to build it"
echo "SHA-256 verified"
rm -rf "$SRC"
tar -xzf "asterisk-${ASTERISK_VERSION}.tar.gz"
cd "$SRC"

log "configuring (pjproject is downloaded by the build)"
run ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
    --with-pjproject-bundled --with-jansson-bundled=no
grep -q '^#define HAVE_SYSTEMD 1' include/asterisk/autoconfig.h || die "systemd support was not detected by configure"
run make menuselect.makeopts
# Portable binary: safe if the disk ever moves to another x86-64 machine.
run menuselect/menuselect --disable BUILD_NATIVE menuselect.makeopts

log "building with $(nproc) CPU(s) - this takes several minutes"
run make -j"$(nproc)"

log "installing"
run make install
# Headers, for channel drivers built out of tree later (chan_dongle, ...).
run make install-headers
run make install-logrotate
if [ -e /etc/asterisk/asterisk.conf ]; then
    echo "existing /etc/asterisk kept (no sample configs installed)"
else
    run make samples
    echo "sample configs installed in /etc/asterisk"
fi
run ldconfig

log "service user and permissions"
getent group asterisk >/dev/null || run addgroup --system asterisk
getent passwd asterisk >/dev/null || run adduser --system --ingroup asterisk --home /var/lib/asterisk \
    --no-create-home --shell /usr/sbin/nologin --gecos "Asterisk PBX" asterisk
chown -R asterisk:asterisk /etc/asterisk /var/lib/asterisk /var/log/asterisk /var/spool/asterisk

log "systemd service"
install -m 0644 contrib/systemd/asterisk.service /etc/systemd/system/asterisk.service
mkdir -p /etc/systemd/system/asterisk.service.d
cat >/etc/systemd/system/asterisk.service.d/runtime-dir.conf <<'EOF'
[Service]
# /run/asterisk (astrundir: control socket and pid), owned by the service user.
RuntimeDirectory=asterisk
EOF
systemctl daemon-reload
systemctl enable asterisk >/dev/null 2>&1
systemctl restart asterisk

i=0
until asterisk -rx 'core show version' >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -le 30 ] || { journalctl -u asterisk -n 30 --no-pager >&2; die "Asterisk did not come up"; }
    sleep 1
done

log "done"
asterisk -rx 'core show version'
echo "service: $(systemctl is-active asterisk) / $(systemctl is-enabled asterisk)"
echo "CLI:     sudo asterisk -rvvv"
