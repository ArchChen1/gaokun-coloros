# 构建入口。全部在 WSL/Ubuntu 里执行（make 需要 bash + 挂载权限 → 用 root 或带 sudo）。
#
#   make deps                 # 安装/检查依赖
#   make fetch                # 抓取输入（Release inputs-v1 的分片；要 root：解包树恢复 SELinux 标签）
#                              #   sudo -E make fetch
#   make verify               # 基座断言
#   make parts VERSION=v54    # 固化基座 + 重打 system/odm
#   make pack                 # 出 super + 发布
#   make all VERSION=v54      # parts + pack
#   make clean                # 清中间产物

VERSION ?= dev
SHELL := /bin/bash
BUILD := build

.PHONY: all deps fetch verify parts pack clean

all: parts pack

deps:
	bash $(BUILD)/deps.sh

fetch:
	bash $(BUILD)/fetch.sh

verify:
	bash $(BUILD)/current_verify.sh

parts:
	bash $(BUILD)/current_build.sh $(VERSION)

pack:
	bash $(BUILD)/current_pack.sh

clean:
	bash $(BUILD)/current_cleanup.sh
