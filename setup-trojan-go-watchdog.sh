#!/bin/bash
# ============================================================
# trojan-go 开机自动启动看门狗 —— 安装脚本
# 适用系统：Debian / Ubuntu（需 systemd）
# 功能：服务器重启后第 5 分钟开始，每分钟执行一次「启动 trojan-go」
# 用法：以 root 身份执行本脚本
#       bash setup-trojan-go-watchdog.sh
# ============================================================

set -e

# ── 路径配置（如有需要可修改） ──────────────────────────────
MAIN_SCRIPT_SRC="$(dirname "$(realpath "$0")")/trojan-go_mod1.sh"  # 主脚本来源
MAIN_SCRIPT_DST="/usr/local/bin/trojan-go_mod1.sh"                  # 主脚本安装位置
WATCHDOG_SCRIPT="/usr/local/bin/trojan-go-watchdog.sh"              # 看门狗脚本
SERVICE_FILE="/etc/systemd/system/trojan-go-watchdog.service"       # systemd 服务文件
LOG_FILE="/var/log/trojan-go-watchdog.log"                          # 日志文件
DELAY_SECONDS=300   # 开机后等待秒数（5 分钟 = 300 秒）
INTERVAL_SECONDS=60 # 每次执行间隔（1 分钟 = 60 秒）

# ── 检查 root ────────────────────────────────────────────────
if [[ "$(id -u)" -ne 0 ]]; then
    echo "[错误] 请以 root 身份执行本脚本！" >&2
    exit 1
fi

# ── 检查 systemd ─────────────────────────────────────────────
if ! command -v systemctl &>/dev/null; then
    echo "[错误] 未找到 systemctl，本脚本仅支持 systemd 系统！" >&2
    exit 1
fi

# ── 1. 安装主脚本 ────────────────────────────────────────────
echo "[1/4] 安装主脚本 → $MAIN_SCRIPT_DST"

if [[ -f "$MAIN_SCRIPT_SRC" ]]; then
    cp "$MAIN_SCRIPT_SRC" "$MAIN_SCRIPT_DST"
else
    # 如果主脚本不在同目录，检查是否已安装
    if [[ ! -f "$MAIN_SCRIPT_DST" ]]; then
        echo "[错误] 找不到主脚本：$MAIN_SCRIPT_SRC"
        echo "       请将 trojan-go_mod1.sh 与本脚本放在同一目录后重试。"
        exit 1
    else
        echo "       主脚本已存在，跳过复制。"
    fi
fi
chmod +x "$MAIN_SCRIPT_DST"

# ── 2. 创建看门狗脚本 ────────────────────────────────────────
echo "[2/4] 创建看门狗脚本 → $WATCHDOG_SCRIPT"

cat > "$WATCHDOG_SCRIPT" << 'EOF'
#!/bin/bash
# trojan-go 看门狗：开机后等待 DELAY 秒，之后每隔 INTERVAL 秒执行一次 start

MAIN_SCRIPT="/usr/local/bin/trojan-go_mod1.sh"
LOG_FILE="/var/log/trojan-go-watchdog.log"
DELAY_SECONDS=__DELAY__
INTERVAL_SECONDS=__INTERVAL__

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# 日志文件大于 5MB 时轮转（避免无限增长）
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

log "=== 看门狗启动，等待 ${DELAY_SECONDS} 秒后开始执行 ==="
sleep "$DELAY_SECONDS"

while true; do
    rotate_log
    log "--- 执行：bash $MAIN_SCRIPT start ---"
    bash "$MAIN_SCRIPT" start >> "$LOG_FILE" 2>&1
    log "--- 执行完毕，等待 ${INTERVAL_SECONDS} 秒 ---"
    sleep "$INTERVAL_SECONDS"
done
EOF

# 替换占位符
sed -i "s/__DELAY__/${DELAY_SECONDS}/" "$WATCHDOG_SCRIPT"
sed -i "s/__INTERVAL__/${INTERVAL_SECONDS}/" "$WATCHDOG_SCRIPT"
chmod +x "$WATCHDOG_SCRIPT"

# ── 3. 创建 systemd 服务 ─────────────────────────────────────
echo "[3/4] 注册 systemd 服务 → $SERVICE_FILE"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Trojan-Go Watchdog（开机自动启动看门狗）
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
echo "[4/4] 启用并启动 trojan-go-watchdog 服务..."
systemctl daemon-reload
systemctl enable trojan-go-watchdog.service
systemctl restart trojan-go-watchdog.service

# ── 完成提示 ─────────────────────────────────────────────────
echo ""
echo "============================================================"
echo " 安装完成！"
echo "============================================================"
echo " 服务名称 : trojan-go-watchdog"
echo " 主脚本   : $MAIN_SCRIPT_DST"
echo " 看门狗   : $WATCHDOG_SCRIPT"
echo " 日志文件 : $LOG_FILE"
echo " 启动延迟 : ${DELAY_SECONDS} 秒（重启后第 5 分钟开始）"
echo " 执行间隔 : ${INTERVAL_SECONDS} 秒（每分钟执行一次）"
echo ""
echo " 常用命令："
echo "   查看服务状态 : systemctl status trojan-go-watchdog"
echo "   查看实时日志 : tail -f $LOG_FILE"
echo "   停止看门狗   : systemctl stop trojan-go-watchdog"
echo "   禁用开机自启 : systemctl disable trojan-go-watchdog"
echo "============================================================"
