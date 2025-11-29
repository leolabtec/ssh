# 执行服务器安全检查命令
  
  ```
bash <(curl -fsSL https://raw.githubusercontent.com/leolabtec/ssh/refs/heads/main/ssh.sh)
  ```
# 查看 Fail2Ban 服务是否正在运行
```
systemctl status fail2ban
```

# 查看所有 jail（包括 sshd）状态
```
fail2ban-client status
```

# 查看 sshd jail 的详细状态
```
fail2ban-client status sshd
```

# 查看 Fail2Ban 当前 ban 掉的所有 IP
```
fail2ban-client banned
```

# 手动封禁某个 IP空格+IP
```
fail2ban-client set sshd banip
```

# 手动解除封禁某个 IP后面跟空格+IP
```
fail2ban-client set sshd unbanip
```

# 重新加载 Fail2Ban 配置（修改 jail.local 后需要）
```
fail2ban-client reload
```
#  查看 Fail2Ban 自身日志
```
tail -n 50 /var/log/fail2ban.log
```

