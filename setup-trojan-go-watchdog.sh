#!/bin/bash
# ============================================================
# trojan-go 看门狗 —— 安装脚本 v2
# 适用系统：Debian / Ubuntu（需 systemd）
#
# 执行逻辑：
#   [开机后] 等待 5 分钟 → 每 10 秒执行一次 start，持续 1 分钟（共约 7 次）
#   [每日]   UTC 20:00 执行一次 start
#
# 用法：以 root 身份执行
#   bash setup-trojan-go-watchdog.sh
# ============================================================

set -e

# ── 路径配置 ────────────────────────────────────────────────
MAIN_SCRIPT_SRC="$(dirname "$(realpath "$0")")/trojan-go_mod1.sh"
MAIN_SCRIPT_DST="/usr/local/bin/trojan-go_mod1.sh"
WATCHDOG_SCRIPT="/usr/local/bin/trojan-go-watchdog.sh"
SERVICE_FILE="/etc/systemd/system/trojan-go-watchdog.service"
LOG_FILE="/var/log/trojan-go-watchdog.log"

# ── 检查 root ────────────────────────────────────────────────
if [[ "$(id -u)" -ne 0 ]]; then
    echo "[错误] 请以 root 身份执行本脚本！" >&2
    exit 1
fi

if ! command -v systemctl &>/dev/null; then
    echo "[错误] 未找到 systemctl，本脚本仅支持 systemd 系统！" >&2
    exit 1
fi

# ── 1. 安装主脚本 ────────────────────────────────────────────
echo "[1/4] 安装主脚本 → $MAIN_SCRIPT_DST"
if [[ -f "$MAIN_SCRIPT_SRC" ]]; then
    cp "$MAIN_SCRIPT_SRC" "$MAIN_SCRIPT_DST"
elif [[ ! -f "$MAIN_SCRIPT_DST" ]]; then
    echo "[错误] 找不到主脚本：$MAIN_SCRIPT_SRC"
    echo "       请将 trojan-go_mod1.sh 与本脚本放在同一目录后重试。"
    exit 1
else
    echo "       主脚本已存在，跳过复制。"
fi
chmod +x "$MAIN_SCRIPT_DST"

# ── 2. 创建看门狗脚本 ────────────────────────────────────────
echo "[2/4] 创建看门狗脚本 → $WATCHDOG_SCRIPT"

cat > "$WATCHDOG_SCRIPT" << 'EOF'
#!/bin/bash
# trojan-go 看门狗 v2
#
# 逻辑一：开机后等待 5 分钟，然后每 10 秒执行一次 start，持续 1 分钟
# 逻辑二：之后保持运行，每天 UTC 20:00 执行一次 start

MAIN_SCRIPT="/usr/local/bin/trojan-go_mod1.sh"
LOG_FILE="/var/log/trojan-go-watchdog.log"

log() {
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" >> "$LOG_FILE"
}

# 日志超过 5MB 时轮转
rotate_log() {
    if [[ -f "$LOG_FILE" ]]; then
        local size
        size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [[ $size -gt 5242880 ]]; then
            mv "$LOG_FILE" "${LOG_FILE}.bak"
            log "日志已轮转（旧文件备份为 ${LOG_FILE}.bak）"
        fi
    fi
}

do_start() {
    local reason="$1"
    rotate_log
    log ">>> 执行 start【原因：$reason】"
    bash "$MAIN_SCRIPT" start >> "$LOG_FILE" 2>&1
    log "<<< 执行完毕"
}

# ──────────────────────────────────────────────
# 逻辑一：开机序列
# ──────────────────────────────────────────────
log "========================================"
log "看门狗启动，等待 300 秒（5 分钟）..."
log "========================================"
sleep 300

log "--- 开机启动序列开始（每 10 秒一次，持续 1 分钟）---"
BURST_END=$(( $(date +%s) + 60 ))
while [[ $(date +%s) -le $BURST_END ]]; do
    do_start "开机序列"
    [[ $(( BURST_END - $(date +%s) )) -lt 10 ]] && break
    sleep 10
done
log "--- 开机启动序列结束 ---"

# ──────────────────────────────────────────────
# 逻辑二：每日 UTC 20:00 执行
# ──────────────────────────────────────────────
log "进入每日定时模式（UTC 20:00 触发）..."
LAST_RUN_DATE=""

while true; do
    CURRENT_HOUR=$(date -u +%H)
    CURRENT_MIN=$(date -u +%M)
    CURRENT_DATE=$(date -u +%Y-%m-%d)

    if [[ "$CURRENT_HOUR" == "20" && "$CURRENT_MIN" == "00" && "$CURRENT_DATE" != "$LAST_RUN_DATE" ]]; then
        do_start "每日 UTC 20:00"
        LAST_RUN_DATE="$CURRENT_DATE"
    fi

    sleep 30
done
EOF

chmod +x "$WATCHDOG_SCRIPT"

# ── 3. 创建 systemd 服务 ─────────────────────────────────────
echo "[3/4] 注册 systemd 服务 → $SERVICE_FILE"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Trojan-Go Watchdog v2
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$WATCHDOG_SCRIPT
Restart=on-failure
RestartSec=10
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF

# ── 4. 启用并启动服务 ────────────────────────────────────────
echo "[4/4] 启用并启动服务..."
systemctl daemon-reload
systemctl enable trojan-go-watchdog.service
systemctl restart trojan-go-watchdog.service

echo ""
echo "============================================================"
echo " 安装完成！"
echo "============================================================"
echo " 开机行为 : 等待 5 分钟 → 每 10 秒执行 start，持续 1 分钟"
echo " 每日定时 : UTC 20:00 执行一次 start"
echo " 日志文件 : $LOG_FILE"
echo ""
echo " 常用命令："
echo "   查看服务状态 : systemctl status trojan-go-watchdog"
echo "   实时查看日志 : tail -f $LOG_FILE"
echo "   停止看门狗   : systemctl stop trojan-go-watchdog"
echo "   禁用开机自启 : systemctl disable trojan-go-watchdog"
echo "============================================================"
