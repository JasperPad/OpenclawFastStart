# OpenclawFastStart
# OpenclawFastStart 配置脚本说明

本项目包含一个 Bash 脚本，用于：
1. 通过 OpenClaw 官方安装脚本安装 OpenClaw
2. 写入/合并 `~/.openclaw/openclaw.json`，配置指定 Provider 与默认模型
3. 尝试重启 OpenClaw gateway（失败不影响配置写入）

---

## 文件

- `openclaw-setup.sh`：主脚本（安装 + 配置）

---

## 依赖

脚本运行前需要这些命令可用：

- `bash`
- `curl`
- `python3`

在 Debian/Ubuntu 上可安装：
```bash
sudo apt update
sudo apt install -y curl python3
