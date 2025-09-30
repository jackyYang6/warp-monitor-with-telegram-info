#!/usr/bin/env bash

# ============================
# 🌐 WARP 自愈 + Telegram 通知脚本
# 适用于 IPv4 加 IPv6 / IPv6 加 IPv4 的 VPS
# ============================

LOG_FILE="/var/log/warp_monitor.log"
LOGROTATE_CONF="/etc/logrotate.d/warp_monitor"
MAX_RETRIES=2
SCRIPT_PATH=$(realpath "$0")
LOCK_FILE="/var/run/warp_monitor.lock"

# ✅ Telegram 通知配置
BOT_TOKEN=$1  # ← Bot Token
CHAT_ID=$2    # ← Chat ID
LAST_IP_FILE="/var/run/warp_last_ipv6.txt"

# Telegram 通知函数
send_telegram() {
    local message="$1"
    if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            -d "chat_id=${CHAT_ID}" \
            -d "text=${message}" >/dev/null
    fi
}

# Root 权限检查
if [ "$(id -u)" -ne 0 ]; then
   echo "❌ 必须使用 root 权限运行此脚本。"
   exit 1
fi

# flock 检查（防止重复执行）
if ! command -v flock >/dev/null 2>&1; then
    apt-get update && apt-get install -y util-linux >/dev/null 2>&1
fi

log_and_echo() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# 获取当前 WARP 出口 IP
get_warp_ip_details() {
    local ip_version="$1"
    local extra_curl_opts="$2"
    local trace_info warp_status warp_ip ip_json country asn_org
    trace_info=$(curl -s -L -${ip_version} ${extra_curl_opts} --retry 2 --max-time 10 https://www.cloudflare.com/cdn-cgi/trace)
    warp_status=$(echo "$trace_info" | grep -oP '^warp=\K(on|plus)')
    if [[ "$warp_status" == "on" || "$warp_status" == "plus" ]]; then
        warp_ip=$(echo "$trace_info" | grep -oP '^ip=\K.*')
        ip_json=$(curl -s -L -${ip_version} ${extra_curl_opts} --retry 2 --max-time 10 "https://ipinfo.io/${warp_ip}/json")
        country=$(echo "$ip_json" | grep -oP '"country":\s*"\K[^"]+')
        asn_org=$(echo "$ip_json" | grep -oP '"org":\s*"\K[^"]+')
        echo "$warp_ip $country $asn_org"
    else
        echo "N/A"
    fi
}

# 配置 logrotate
setup_log_rotation() {
    if [ ! -f "$LOGROTATE_CONF" ]; then
        cat << EOF > "$LOGROTATE_CONF"
/var/log/warp_monitor.log {
    daily
    rotate 30
    size 2M
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
EOF
    fi
}

# 配置 crontab（默认每小时）
setup_cron_job() {
    local cron_comment="# WARP_MONITOR_CRON"
    local cron_job="0 * * * * timeout 20m ${SCRIPT_PATH} ${cron_comment}"

    if ! crontab -l 2>/dev/null | grep -qF "$cron_comment"; then
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    fi
}

# 状态检测
check_status() {
    IPV4="N/A"; IPV6="N/A"; extra_opts=""
    expected_stack="双栈 (Dual-Stack)"; actual_stack="已断开 (Disconnected)"
    RECONNECT_CMD=""; needs_reconnect=0

    if wg show warp &> /dev/null; then
        if grep -q '^Table' /etc/wireguard/warp.conf; then
            extra_opts="--interface warp"
        fi
        RECONNECT_CMD="/usr/bin/warp n"
    fi

    IPV4=$(get_warp_ip_details 4 "$extra_opts")
    IPV6=$(get_warp_ip_details 6 "$extra_opts")

    if [[ "$IPV4" != "N/A" && "$IPV6" != "N/A" ]]; then actual_stack="双栈 (Dual-Stack)"; fi
    if [[ "$IPV4" != "N/A" && "$IPV6" == "N/A" ]]; then actual_stack="仅 IPv4 (IPv4-Only)"; fi
    if [[ "$IPV4" == "N/A" && "$IPV6" != "N/A" ]]; then actual_stack="仅 IPv6 (IPv6-Only)"; fi

    if [[ "$actual_stack" == "已断开 (Disconnected)" ]]; then
        needs_reconnect=1
    elif [[ "$actual_stack" != "$expected_stack" ]]; then
        needs_reconnect=1
    fi
}

# 主逻辑
main() {
    echo "--- $(date '+%Y-%m-%d %H:%M:%S') ---" >> "$LOG_FILE"
    setup_log_rotation
    setup_cron_job
    check_status

    log_and_echo "📊 当前 IPv4: $IPV4"
    log_and_echo "📡 当前 IPv6: $IPV6"
    log_and_echo "📶 当前状态: $actual_stack"
    log_and_echo "🎯 预期状态: $expected_stack"

    # 检查出口 IP 变化（仅 IPv6）
    CURRENT_IP=$(echo "$IPV6" | awk '{print $1}')
    if [ -n "$CURRENT_IP" ]; then
        if [ -f "$LAST_IP_FILE" ]; then
            LAST_IP=$(cat "$LAST_IP_FILE")
            if [ "$LAST_IP" != "$CURRENT_IP" ]; then
                send_telegram "🌐 出口 IPv6 变化：从 $LAST_IP → $CURRENT_IP"
            fi
        fi
        echo "$CURRENT_IP" > "$LAST_IP_FILE"
    fi

    # 自动重连逻辑
    if [[ $needs_reconnect -eq 1 && -n "$RECONNECT_CMD" ]]; then
        send_telegram "⚠️ $(hostname) 检测到 WARP 状态异常（$actual_stack），开始自动重连..."
        for i in $(seq 1 $MAX_RETRIES); do
            log_and_echo "[重连尝试 $i/$MAX_RETRIES] 执行: $RECONNECT_CMD"
            $RECONNECT_CMD >> "$LOG_FILE" 2>&1
            sleep 15
            check_status
            if [[ $needs_reconnect -eq 0 ]]; then
                send_telegram "✅ $(hostname) WARP 已恢复。IPv4: $IPV4 / IPv6: $IPV6"
                break
            fi
            if [[ $i -eq $MAX_RETRIES ]]; then
                send_telegram "❌ $(hostname) WARP 在 $MAX_RETRIES 次尝试后仍未恢复，请手动检查！"
            fi
        done
    else
        log_and_echo "✅ 状态正常，无需操作。"
    fi
}

(
    flock -n 200 || { echo "[$(date '+%Y-%m-%d %H:%M:%S')] - 已有 warp_monitor 进程在运行。" | tee -a "$LOG_FILE"; exit 1; }
    main
) 200>"$LOCK_FILE"
