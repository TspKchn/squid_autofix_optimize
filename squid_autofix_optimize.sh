#!/bin/bash
# squid_autofix_optimize.sh
# Universal Squid Optimizer & Auto-Fixer
# Version 1.0
# By ChatGPT

set -e

LOG_FILE="/var/log/squid_autofix.log"
CACHE_DIR="/var/spool/squid"
CRON_CMD="*/5 * * * * /usr/local/bin/squid_autofix_optimize.sh >> $LOG_FILE 2>&1"

echo "=== $(date) ===" >> "$LOG_FILE"
echo "=== squid_autofix_optimize started ===" >> "$LOG_FILE"

# Detect public IP
PUBLIC_IP=$(curl -s ifconfig.me || echo "0.0.0.0")
echo ">>> Detected public IP: $PUBLIC_IP" >> "$LOG_FILE"

# Detect Squid version and path
SQUID_PATH=$(which squid || which squid3 || echo "/usr/sbin/squid")
SQUID_VERSION=$($SQUID_PATH -v | grep Version | awk '{print $2}')
echo ">>> Detected Squid version: $SQUID_VERSION (using $CACHE_DIR)" >> "$LOG_FILE"

# Backup current squid.conf
SQUID_CONF="/etc/squid/squid.conf"
BACKUP_CONF="/etc/squid/squid.conf.bak.$(date +%s)"
cp "$SQUID_CONF" "$BACKUP_CONF"

# Function: optimize squid.conf
optimize_squid_conf() {
    echo ">>> Optimizing squid.conf..." >> "$LOG_FILE"

    # ลบ 4 บรรทัดนี้จาก squid.conf
    sed -i '/^acl any_host src all/d' "$SQUID_CONF"
    sed -i '/^acl all_dst dst all/d' "$SQUID_CONF"
    sed -i '/^http_access allow any_host/d' "$SQUID_CONF"
    sed -i '/^http_access allow all_dst/d' "$SQUID_CONF"

    # ตั้งค่าหน่วยความจำ
    sed -i '/^cache_mem /d' "$SQUID_CONF"
    echo "cache_mem 32 MB" >> "$SQUID_CONF"

    sed -i '/^maximum_object_size /d' "$SQUID_CONF"
    echo "maximum_object_size 10 MB" >> "$SQUID_CONF"

    # แก้ cache_dir
    sed -i "s|^cache_dir .*$|cache_dir ufs $CACHE_DIR 100 16 256|" "$SQUID_CONF"

    # แก้ coredump_dir ให้ตรงกับ /var/spool/squid
    sed -i "s|^coredump_dir .*$|coredump_dir $CACHE_DIR|" "$SQUID_CONF"

    echo ">>> squid.conf optimized successfully." >> "$LOG_FILE"
}

# Function: check RAM usage
check_ram() {
    RAM_USAGE=$(free -m | awk '/Mem:/ {printf("%d",$3/$2*100)}')
    echo ">>> RAM usage: $RAM_USAGE%" >> "$LOG_FILE"
    if [ "$RAM_USAGE" -gt 75 ]; then
        echo ">>> [WARNING] RAM usage high!" >> "$LOG_FILE"
    else
        echo ">>> RAM usage OK." >> "$LOG_FILE"
    fi
}

# Function: create missing cache directory
create_cache_dir() {
    if [ ! -d "$CACHE_DIR" ]; then
        echo ">>> Creating missing cache directory..." >> "$LOG_FILE"
        mkdir -p "$CACHE_DIR"
        chown -R proxy:proxy "$CACHE_DIR"
        $SQUID_PATH -z
    fi
}

# Function: configure logrotate
setup_logrotate() {
    LOGROTATE_FILE="/etc/logrotate.d/squid_autofix"
    if [ ! -f "$LOGROTATE_FILE" ]; then
        echo ">>> Setting up logrotate for squid..." >> "$LOG_FILE"
        cat <<EOF > "$LOGROTATE_FILE"
/var/log/squid/*.log {
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    postrotate
        systemctl reload squid >/dev/null 2>&1 || true
    endscript
}
EOF
        echo ">>> Logrotate configured." >> "$LOG_FILE"
    else
        echo ">>> Logrotate already configured." >> "$LOG_FILE"
    fi
}

# Function: verify cron job
verify_cron() {
    crontab -l 2>/dev/null | grep -F "$CRON_CMD" >/dev/null || (
        (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
        echo ">>> Cron job created (every 5 minutes)" >> "$LOG_FILE"
    )
    echo ">>> Cron job verified (every 5 minutes)." >> "$LOG_FILE"
}

# Function: check squid process
check_squid() {
    SQUID_PID=$(pgrep -x squid || true)
    if [ -z "$SQUID_PID" ]; then
        echo ">>> Squid not running, starting..." >> "$LOG_FILE"
        $SQUID_PATH -NCd1
    else
        echo ">>> Squid is already running!  Process ID $SQUID_PID" >> "$LOG_FILE"
    fi
}

# Run all functions
optimize_squid_conf
check_ram
create_cache_dir
setup_logrotate
verify_cron
check_squid

echo ">>> [OK] Squid running normally." >> "$LOG_FILE"
echo "=== squid_autofix_optimize completed ===" >> "$LOG_FILE"
