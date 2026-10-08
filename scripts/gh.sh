#!/bin/zsh
# 本仓库专用：gh 需要通过系统代理访问 github.com。
# 这台机器直连 github.com:443 不通（浏览器同样走 127.0.0.1:7890），
# 所以只在调用 gh 时临时注入代理变量，不改动 shell 配置，也不影响其他项目。
# 用法与 gh 完全一致，例如：./scripts/gh.sh release view v0.1.0
set -euo pipefail
export HTTPS_PROXY="${HTTPS_PROXY:-http://127.0.0.1:7890}"
export HTTP_PROXY="${HTTP_PROXY:-http://127.0.0.1:7890}"
exec gh "$@"
