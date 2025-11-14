#!/usr/bin/env bash
# enable-root-password-ssh.sh
# 说明: 一键启用 root 密码登录，并禁用公钥登录（Debian/Ubuntu 兼容）
# 用法:
#   交互式： sudo ./enable-root-password-ssh.sh
#   非交互： ROOT_PASSWORD='YourP@ssw0rd' sudo ./enable-root-password-ssh.sh
# 注意: 请以 root 或 sudo 运行

set -euo pipefail

SSHD_CONF="/etc/ssh/sshd_config"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/root/ssh-config-backups"
BACKUP_FILE="${BACKUP_DIR}/sshd_config.${TIMESTAMP}.bak"

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
  echo "错误：请以 root 身份运行此脚本 (sudo ./enable-root-password-ssh.sh)"
  exit 1
fi

# 备份配置
mkdir -p "$BACKUP_DIR"
cp -a "$SSHD_CONF" "$BACKUP_FILE"
echo "已备份 sshd_config -> $BACKUP_FILE"

# 处理 root 密码（优先使用环境变量 ROOT_PASSWORD）
if [ -n "${ROOT_PASSWORD:-}" ]; then
  ROOT_PW="${ROOT_PASSWORD}"
else
  echo "请输入要为 root 设置的新密码（不会回显）："
  read -r -s ROOT_PW
  echo
  if [ -z "$ROOT_PW" ]; then
    echo "错误：密码不能为空。"
    exit 1
  fi
fi

# 设置 root 密码
# 使用 chpasswd 以兼容性更好且可接收 stdin 的方法
echo "root:${ROOT_PW}" | chpasswd
if [ $? -ne 0 ]; then
  echo "警告：设置 root 密码失败，请手动检查。"
else
  echo "已设置 root 密码。"
fi

# 修改 sshd_config 的函数（保留注释行替换，若不存在则追加）
ensure_sshd_option() {
  local key="$1"
  local val="$2"
  if grep -Eq "^[#[:space:]]*${key}[[:space:]]+" "$SSHD_CONF"; then
    sed -ri "s|^[#[:space:]]*(${key})[[:space:]]+.*$|\\1 ${val}|g" "$SSHD_CONF"
  else
    echo -e "\n${key} ${val}" >> "$SSHD_CONF"
  fi
}

# 设置必须项：允许 root 密码登录，启用密码认证，禁用公钥认证
ensure_sshd_option "PermitRootLogin" "yes"
ensure_sshd_option "PasswordAuthentication" "yes"
ensure_sshd_option "PubkeyAuthentication" "no"
# 为保证 PAM 工作（多数 Debian 系统需要）
ensure_sshd_option "UsePAM" "yes"

# 重启 SSH 服务（兼容 systemd & sysv）
if command -v systemctl >/dev/null 2>&1; then
  # 尝试常见服务名
  if systemctl list-units --type=service --all | grep -qE 'ssh\.service|sshd\.service'; then
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
  else
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
  fi
else
  service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || true
fi

echo
echo "================ 完成 ================="
echo "备份文件： $BACKUP_FILE"
echo
echo "sshd_config 当前关键项："
grep -E "^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|UsePAM)" "$SSHD_CONF" || true
echo
echo "请立即从本地或另一台机器测试登录："
echo "  ssh root@你的服务器IP"
echo
cat <<'WARNING'
安全警告：
- 直接允许 root 密码登录会显著增加被暴力破解的风险。
- 强烈建议至少做以下任意一项保护：
  * 在防火墙上限制允许登录的 IP（ufw/iptables），或只在私有网络使用；
  * 修改 SSH 端口，或使用 Fail2Ban 等工具限制尝试次数；
  * 使用强复杂密码并尽快在操作完成后恢复为只允许公钥登录（PubkeyAuthentication yes, PasswordAuthentication no）。
- 若需要我也可以为你生成一个“恢复脚本”，将 sshd_config 回滚到备份并恢复为禁止密码登录的状态。
WARNING

# 清理内存中保存的明文密码变量（尽最大努力）
ROOT_PW=""
unset ROOT_PW
