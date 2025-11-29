#!/usr/bin/env bash
# SSH 安全加固脚本（适用 Debian 11/12/13）
# 功能：
# 1. 创建一个新的管理员用户（加入 sudo 组）
# 2. 禁用 root SSH 登录
# 3. 修改 SSH 端口（从 22 改为你指定的安全端口）
# 4. 可选：安装并配置 Fail2Ban，自动封禁暴力破解 IP
# 5. 不在磁盘上保存用户名/密码等敏感信息

set -u

SSHD_CONFIG="/etc/ssh/sshd_config"

#-----------------------------#
# 基本检查与备份
#-----------------------------#

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 身份运行本脚本。"
  exit 1
fi

if [ ! -f "$SSHD_CONFIG" ]; then
  echo "未找到 $SSHD_CONFIG，无法继续。"
  exit 1
fi

BACKUP="${SSHD_CONFIG}.backup.$(date +%Y%m%d%H%M%S)"
cp "$SSHD_CONFIG" "$BACKUP" || {
  echo "备份 $SSHD_CONFIG 失败，已停止操作。"
  exit 1
}
echo "已备份 ssh 配置到: $BACKUP"
echo

#-----------------------------#
# 读取当前 SSH 配置信息
#-----------------------------#

CURRENT_PORTS=$(grep -E '^[[:space:]]*Port[[:space:]]+[0-9]+' "$SSHD_CONFIG" || true)
if [ -z "$CURRENT_PORTS" ]; then
  CURRENT_PORTS="(未显式设置，默认 22)"
fi

CURRENT_ROOT_LOGIN=$(grep -E '^[[:space:]]*PermitRootLogin' "$SSHD_CONFIG" || echo "(未显式设置，默认 yes)")
echo "当前 SSH 端口配置:"
echo "$CURRENT_PORTS"
echo
echo "当前 root 登录策略:"
echo "$CURRENT_ROOT_LOGIN"
echo

#-----------------------------#
# 创建新的系统管理员用户
#-----------------------------#

echo "=== 创建新的管理员用户（例如 ht） ==="
while :; do
  read -rp "请输入要创建的管理员用户名: " NEW_USER
  # 简单校验用户名
  if [[ -z "$NEW_USER" ]]; then
    echo "用户名不能为空。"
    continue
  fi
  if ! [[ "$NEW_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    echo "用户名不合法，仅允许小写字母、数字、下划线、短横线，且不能以数字开头。"
    continue
  fi
  break
done

if id "$NEW_USER" >/dev/null 2>&1; then
  echo "用户 $NEW_USER 已存在，将为该用户重设密码并添加 sudo 权限。"
else
  echo "正在创建用户 $NEW_USER ..."
  adduser "$NEW_USER"
fi

echo
echo "现在为 $NEW_USER 设置密码（不会回显）："
passwd "$NEW_USER"

# 安装 sudo（如果不存在）
if ! command -v sudo >/dev/null 2>&1; then
  echo "未检测到 sudo，正在安装 sudo..."
  apt update && apt install -y sudo
fi

# 将用户加入 sudo 组
echo "正在将 $NEW_USER 加入 sudo 组..."
usermod -aG sudo "$NEW_USER"

echo
echo "管理员用户 $NEW_USER 已创建并加入 sudo 组。"
echo

#-----------------------------#
# 选择新的 SSH 端口
#-----------------------------#

echo "=== 设置 SSH 新端口 ==="
echo "建议使用 20000~60000 之间的非标准端口。"

NEW_PORT=""
while :; do
  read -rp "请输入新的 SSH 端口（例如 22888）: " NEW_PORT
  if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]]; then
    echo "端口必须是数字。"
    continue
  fi
  if [ "$NEW_PORT" -lt 1024 ] || [ "$NEW_PORT" -gt 65535 ]; then
    echo "端口必须在 1024~65535 之间。"
    continue
  fi

  # 检查端口是否被占用
  if ss -tln | awk '{print $4}' | grep -q ":$NEW_PORT$"; then
    echo "端口 $NEW_PORT 已被占用，请换一个端口。"
    continue
  fi

  break
done

echo "将把 SSH 端口修改为: $NEW_PORT"
echo

#-----------------------------#
# 修改 sshd_config：端口 & root 登录
#-----------------------------#

echo "=== 修改 /etc/ssh/sshd_config ==="

# 1. 注释掉所有已有的 Port 行
sed -i -E 's/^[[:space:]]*Port[[:space:]]+[0-9]+/#&/' "$SSHD_CONFIG"

# 2. 追加新的 Port 行
echo "Port $NEW_PORT" >> "$SSHD_CONFIG"

# 3. 设置 PermitRootLogin no（禁止 root 通过 SSH 登录）
if grep -qE '^[[:space:]]*PermitRootLogin' "$SSHD_CONFIG"; then
  sed -i -E 's/^[[:space:]]*PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
else
  echo "PermitRootLogin no" >> "$SSHD_CONFIG"
fi

# 4. 确保允许密码登录（先保证新用户能登录，后续你可以手动改成密钥登录）
if grep -qE '^[[:space:]]*PasswordAuthentication' "$SSHD_CONFIG"; then
  sed -i -E 's/^[[:space:]]*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
else
  echo "PasswordAuthentication yes" >> "$SSHD_CONFIG"
fi

echo "sshd_config 修改完成。"
echo

#-----------------------------#
# 重启 SSH 服务
#-----------------------------#

echo "正在重启 ssh 服务..."
if systemctl restart ssh; then
  echo "ssh 已重启。"
else
  echo "⚠️ ssh 重启失败，已保留备份文件: $BACKUP"
  echo "请检查 /etc/ssh/sshd_config 语法。"
  exit 1
fi

echo
echo "=== SSH 基础加固完成，请务必立即测试新登录 ==="
echo "在新的终端/窗口中使用以下信息登录："
echo
echo "  用户名: $NEW_USER"
echo "  端口:   $NEW_PORT"
echo
echo "登录命令示例："
echo "  ssh ${NEW_USER}@你的服务器IP -p $NEW_PORT"
echo
echo "⚠️ 在确认可以用新用户登录之前，不要关闭当前 root 会话。"
echo

#-----------------------------#
# 询问是否安装并配置 Fail2Ban
#-----------------------------#

read -rp "是否安装并配置 Fail2Ban 自动封禁暴力 SSH 攻击？[y/N]: " INSTALL_F2B

case "$INSTALL_F2B" in
  y|Y)
    echo
    echo "=== 安装并配置 Fail2Ban ==="

    if ! command -v fail2ban-client >/dev/null 2>&1; then
      echo "正在安装 fail2ban..."
      apt update && apt install -y fail2ban
    else
      echo "已检测到 fail2ban，跳过安装步骤。"
    fi

    JAIL_LOCAL="/etc/fail2ban/jail.local"
    if [ -f "$JAIL_LOCAL" ]; then
      JAIL_BACKUP="${JAIL_LOCAL}.backup.$(date +%Y%m%d%H%M%S)"
      cp "$JAIL_LOCAL" "$JAIL_BACKUP"
      echo "已备份原有 $JAIL_LOCAL 到: $JAIL_BACKUP"
    fi

    cat > "$JAIL_LOCAL" <<EOF
[DEFAULT]
bantime  = 10m
findtime = 10m
maxretry = 5
ignoreip = 127.0.0.1/8

[sshd]
enabled  = true
backend  = systemd
EOF

    systemctl enable --now fail2ban

    echo
    echo "Fail2Ban 已安装并启用 SSH 防暴力破解。当前状态："
    fail2ban-client status sshd || true
    echo
    echo "说明："
    echo "  - 同一 IP 在 10 分钟内连续失败 5 次，将被封禁 10 分钟。"
    echo "  - 你可以用： fail2ban-client status sshd 查看被封的 IP。"
    echo "  - 如需修改封禁时长等，可编辑 /etc/fail2ban/jail.local。"
    echo
    ;;
  *)
    echo "已跳过 Fail2Ban 安装配置步骤。"
    ;;
esac

echo "全部操作结束。请确认："
echo "  1) 新用户 ${NEW_USER} 可以通过端口 ${NEW_PORT} 登录；"
echo "  2) root 已无法通过 SSH 登录；"
echo "  3) 如已安装 Fail2Ban，它正在保护你的 SSH。"
echo
