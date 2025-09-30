# 🌐 WARP Monitor with Telegram Notifications

这是一个自动监控 [Cloudflare WARP](https://1.1.1.1/) 网络状态的 Bash 脚本，适用于：

- IPv4 VPS + WARP IPv6  
- IPv6 VPS + WARP IPv4  
- 双栈 VPS 的自动自愈和告警场景  

📦 功能包括：

- ✅ 自动检测 WARP IPv4 / IPv6 出口状态  
- 🔁 自动重连 WARP（支持 warp-cli / wgcf / wireproxy）  
- 📊 出口 IP 变化检测（带地区信息）  
- 📲 Telegram 实时通知（掉线 / 重连成功 / 重连失败 / 出口变化）  
- 📜 日志自动记录与轮转  
- ⏱️ 自动定时任务配置（支持 cron）  

---

## 🚀 1. 克隆本仓库

```bash
wget -O /root/warp_monitor.sh https://raw.githubusercontent.com/jackyYang6/warp-monitor-with-telegram-info/main/warp-monitor.sh \
&& chmod +x /root/warp_monitor.sh && bash /root/warp_monitor.sh
```

## 📲 2. 获取 Telegram Bot Token & Chat ID

要让脚本能够发送通知，你需要准备两个值：

🧠 ① 获取 Bot Token
```
1.	打开 Telegram，搜索 @BotFather  
2.	输入命令：  
/start
/newbot
3.	按提示给你的机器人命名，例如 WARP Monitor Bot  
4.	创建成功后，BotFather 会返回一段类似这样的信息：
Done! Congratulations on your new bot.
Use this token to access the HTTP API:
👉 123456789:AAEabcDEfghIJklmNOPQRstuVWXYZ
```
✅ 复制这段 Token，就是你的 BOT_TOKEN。

🧑‍💻 ② 获取 Chat ID
```
1.	在 Telegram 搜索并启动 @userinfobot 或 @chatid_echo_bot
2.	它会返回类似：

Your chat ID: 123456789
```
✅ 复制这个数字，就是你的 CHAT_ID。


## ⚙️ 3. 运行脚本（传入参数）

该脚本支持通过命令行参数传入 BOT_TOKEN 和 CHAT_ID：

```
sudo /root/warp_monitor.sh <BOT_TOKEN> <CHAT_ID>
```

📌 示例：
```
sudo /root/warp_monitor.sh 123456789:AAEabcDEfghIJklmNOPQRstuVWXYZ 123456789
```
如果一切配置正确，你应该会立即在 Telegram 收到一条通知：
```

✅ WARP 已恢复：vps-us-01 IPv4: 203.0.113.45 / IPv6: 2606:4700:abcd::1234
```


## 🔍 Telegram 通知示例
```
•⚠️ 掉线时：
⚠️ vps-us-01 检测到 WARP 状态异常（已断开），开始自动重连...
•	✅ 恢复时：

✅ vps-us-01 WARP 已恢复。IPv4: 203.0.113.45 / IPv6: 2606:4700:abcd::1234

•	🌐 出口 IP 变化：
🌐 出口 IPv6 变化：从 2606:4700:abcd::1111 → 2606:4700:abcd::1234

•	❌ 多次重连失败：

❌ vps-us-01 WARP 在 2 次尝试后仍未恢复，请手动检查！
```

## ⚠️ 常见问题（FAQ）

1. 为什么收不到通知？
	•	检查是否正确填写了 BOT_TOKEN 和 CHAT_ID
	•	确保你已经向 Bot 发送过至少一条消息（Telegram 不允许机器人主动给“从未联系过”的用户发消息）

2. 脚本没有自动重连？
	•	检查 /usr/bin/warp 或 wg-quick 是否安装成功
	•	如果使用的是 wgcf，确保接口名称为 warp（默认是这样）

3. 日志太多了？
	•	默认日志每天切割，保留 30 天。如果磁盘紧张可以修改 /etc/logrotate.d/warp_monitor。


📦 建议部署频率（推荐）

场景	建议检测频率
普通 VPS	每小时一次（默认）
代理/转发服务器	每 10～15 分钟一次
高可用服务（如流媒体解锁）	每 5 分钟一次 ✅


🛠️ 高级用法（可选）
	•	✅ 检测出口 IP 变化并通知（已内置）
	•	✅ 多次重连失败自动提醒（已内置）
	•	✅ 支持 systemd 定时运行（可选）
	•	✅ 可在多个 VPS 部署，消息自动包含 $(hostname) 区分来源

⸻

📜 License

MIT License © 2025 jackyYang6
