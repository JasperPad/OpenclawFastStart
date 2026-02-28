#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OpenClaw Installer + Provider Config Writer
# - Installs OpenClaw via official installer
# - Prompts for API key (or reads from env)
# - Writes ~/.openclaw/openclaw.json with provider + model
# - Restarts OpenClaw gateway (best-effort)
#
# Notes:
# - This script will BACKUP existing config before writing.
# - API key is stored in plaintext in the config file.
#   Protect your HOME directory permissions and avoid sharing the file.
# ============================================================

# ----------------------------
# Provider / Model settings
# ----------------------------
PROVIDER_ID="openai"
BASE_URL="https://openai.com/v1"
MODEL_ID="gpt-5.2"
SITE_NAME="openai.com"

# ----------------------------
# Config path
# ----------------------------
CFG_DIR="${HOME}/.openclaw"
CFG="${CFG_DIR}/openclaw.json"

# ----------------------------
# Small helpers
# ----------------------------
is_tty() { [[ -t 0 && -t 1 ]]; }
say() { printf "%s\n" "$*"; }

die() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"
}

pause_for_user() {
  local msg="${1:-Press Enter to continue...}"
  if [[ -r /dev/tty ]]; then
    printf "\n%s\n" "$msg" > /dev/tty
    read -r _ < /dev/tty || true
  fi
}

# 从任意输入里抽取 sk-xxxx
extract_sk_key() {
  local input="$1"
  printf "%s" "$input" \
    | tr -d '\r' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' \
    | grep -Eo 'sk-[A-Za-z0-9_-]+' \
    | head -n1 || true
}

# 读取 API Key：
# 1) 优先用环境变量 OPENCLAW_API_KEY
# 2) 否则从 /dev/tty 交互输入
prompt_api_key() {
  local key="${OPENCLAW_API_KEY:-}"
  if [[ -n "${key}" ]]; then
    printf "%s" "${key}"
    return 0
  fi

  [[ -r /dev/tty && -w /dev/tty ]] || die "no TTY available. Please set env var: OPENCLAW_API_KEY=sk-xxxx"

  printf "\nPaste API Key (supports: sk-... / Bearer sk-... / Authorization: Bearer sk-...)\n\n" > /dev/tty
  read -r -p "API Key: " raw < /dev/tty || true
  key="$(extract_sk_key "${raw:-}")"

  [[ -n "${key}" ]] || die "invalid API key (could not find sk-... in your input)."
  printf "%s" "${key}"
}

# 写入 OpenClaw 配置：
# - 备份旧文件（若存在）
# - 尽量“合并”写入：保留其他配置，只更新 provider/model/defaults
write_openclaw_config() {
  local api_key="$1"

  mkdir -p "${CFG_DIR}"

  # python 写 JSON 更安全（避免 bash 转义坑）
  OPENCLAW_CFG="${CFG}" \
  OPENCLAW_API_KEY="${api_key}" \
  PROVIDER_ID="${PROVIDER_ID}" \
  BASE_URL="${BASE_URL}" \
  MODEL_ID="${MODEL_ID}" \
  SITE_NAME="${SITE_NAME}" \
  python3 - <<'PY'
import json, os, time
from pathlib import Path

cfg_path = Path(os.environ["OPENCLAW_CFG"])
api_key = os.environ["OPENCLAW_API_KEY"]
provider_id = os.environ["PROVIDER_ID"]
base_url = os.environ["BASE_URL"]
model_id = os.environ["MODEL_ID"]
site_name = os.environ["SITE_NAME"]

cfg = {}

# 1) 读取旧配置（如存在）
if cfg_path.exists():
    raw = cfg_path.read_text(encoding="utf-8").strip()
    if raw:
        try:
            cfg = json.loads(raw)
        except Exception:
            # 旧文件损坏：备份原内容，重新生成
            backup = cfg_path.with_suffix(cfg_path.suffix + f".corrupt.{int(time.time())}.bak")
            backup.write_text(raw + "\n", encoding="utf-8")
            cfg = {}

# 2) 常规备份（写入前备份一次）
if cfg_path.exists():
    backup = cfg_path.with_suffix(cfg_path.suffix + f".bak.{int(time.time())}")
    backup.write_text(cfg_path.read_text(encoding="utf-8"), encoding="utf-8")

# 3) 写入 env（部分工具会从 env 节读取）
cfg.setdefault("env", {})["OPENCLAW_API_KEY"] = api_key

# 4) 写入 models/providers
models = cfg.setdefault("models", {})
models["mode"] = "merge"
providers = models.setdefault("providers", {})
providers[provider_id] = {
    "baseUrl": base_url,
    "apiKey": api_key,
    "api": "openai-responses",
    "models": [{"id": model_id, "name": f"{model_id} ({site_name})"}],
}

# 5) 设置默认 agent 模型
cfg.setdefault("agents", {}).setdefault("defaults", {}).setdefault("model", {})["primary"] = f"{provider_id}/{model_id}"

# 6) 输出
cfg_path.write_text(json.dumps(cfg, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")

print("OK: wrote", cfg_path)
print("Configured provider:", provider_id)
print("Configured model:", f"{provider_id}/{model_id}")
PY
}

# ----------------------------
# Main
# ----------------------------
need_cmd curl
need_cmd python3
need_cmd bash

say ""
say "=============================================="
say "OpenClaw setup (install + configure provider)"
say "Provider: ${PROVIDER_ID}"
say "Base URL : ${BASE_URL}"
say "Model    : ${MODEL_ID}"
say "Config   : ${CFG}"
say "=============================================="
say ""

# 1) 官方安装 OpenClaw
say "[1/3] Installing OpenClaw (official installer)..."
curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install.sh | bash

command -v openclaw >/dev/null 2>&1 || die "openclaw not found after install. Open a new shell or source your shell rc."

# 2) 语言选择（仅影响提示文本）
LANG_CHOICE="zh"
if is_tty; then
  say ""
  say "Choose language for prompts:"
  say "1) 中文（默认）"
  say "2) English"
  read -r -p "Select [1/2] (default 1): " ans || true
  ans="${ans:-1}"
  if [[ "${ans}" == "2" ]]; then LANG_CHOICE="en"; else LANG_CHOICE="zh"; fi
fi

# 3) 输入 API Key 并写入配置
say ""
if [[ "${LANG_CHOICE}" == "zh" ]]; then
  say "下一步：请输入你的 API Key（sk- 开头）。"
  say "提示：你也可以用环境变量方式：OPENCLAW_API_KEY=sk-xxxx bash openclaw-setup.sh"
  pause_for_user "准备好后按回车继续..."
else
  say "Next: provide your API key (starts with sk-)."
  say "Tip: you can also run with env var: OPENCLAW_API_KEY=sk-xxxx bash openclaw-setup.sh"
  pause_for_user "Press Enter to continue..."
fi

API_KEY="$(prompt_api_key)"

say ""
say "[2/3] Writing OpenClaw config..."
write_openclaw_config "${API_KEY}"

say ""
say "[3/3] Restarting gateway (best-effort)..."
openclaw gateway restart || true

say ""
if [[ "${LANG_CHOICE}" == "zh" ]]; then
  say "完成 ✅"
  say "验证：openclaw models status"
else
  say "Done ✅"
  say "Verify: openclaw models status"
fi
