# test/Makefile - 编译 VMPacker 测试程序
#
# 用法:
#   make arm64   - 交叉编译 ARM64 可执行文件 (需 aarch64-linux-gnu-gcc)
#   make arm32   - 交叉编译 ARM32 可执行文件 (需 arm-linux-gnueabihf-gcc)
#   make protect - 对 ARM64 版本执行 VMP 保护 (需先 make arm64)
#   make run     - 使用 qemu 运行保护后的程序 (需 qemu-user)
#
# macOS 交叉编译 ARM32 可选:
#   brew install messense/macos-cross-toolchains/armv7-unknown-linux-gnueabihf
#   make arm32 CROSS_ARM32=/opt/homebrew/opt/armv7-unknown-linux-gnueabihf/bin/armv7-unknown-linux-gnueabihf-

CROSS        ?= aarch64-linux-gnu-
CROSS_ARM32  ?= arm-linux-gnueabihf-
CC_ARM64     = $(CROSS)gcc
CC_ARM32     = $(CROSS_ARM32)gcc

SRC       = simple_app.cpp
OUT_ARM64 = simple_app_arm64
OUT_ARM32 = simple_app_arm32
PROTECTED = simple_app_protected
VMPACKER  = go run ../cmd/vmpacker/

# 使用 -O1 避免过度优化导致函数被内联（保护时需要能定位到 log2Console）
# -fno-lto 避免 macOS 上 LTO 插件代码签名导致链接失败
CFLAGS = -O1 -fno-inline-functions -fno-lto

.PHONY: arm64 arm32 protect run clean

arm64: $(OUT_ARM64)
$(OUT_ARM64): $(SRC)
	$(CC_ARM64) $(CFLAGS) -o $@ $<
	@echo "[+] Built: $@"

arm32: $(OUT_ARM32)
$(OUT_ARM32): $(SRC)
	$(CC_ARM32) $(CFLAGS) -o $@ $<
	@echo "[+] Built: $@"

# 保护 ARM64 版本（与用户示例命令格式一致）
protect: $(OUT_ARM64)
	$(VMPACKER) -func log2Console -v -debug -o $(PROTECTED) $(OUT_ARM64)
	@echo "[+] Protected: $(PROTECTED)"

# 保护 ARM32 版本
protect32: $(OUT_ARM32)
	$(VMPACKER) -func log2Console -v -debug -o $(PROTECTED)_arm32 $(OUT_ARM32)
	@echo "[+] Protected: $(PROTECTED)_arm32"

# 使用 qemu-user 运行。本仓库工具链的 sysroot（供 -L 使用）
SYSROOT_ARM64 = $(shell cd $(dir $(MAKEFILE_LIST)).. && pwd)/scripts/toolchains/aarch64-unknown-linux-gnu/aarch64-unknown-linux-gnu/sysroot

run: protect
	@echo "[*] Running protected ARM64 binary with QEMU..."
	@if [ -d "$(SYSROOT_ARM64)" ]; then qemu-aarch64 -L "$(SYSROOT_ARM64)" $(PROTECTED); \
	else qemu-aarch64 -L /usr/aarch64-linux-gnu/ $(PROTECTED); fi

run-unprotected: $(OUT_ARM64)
	@if [ -d "$(SYSROOT_ARM64)" ]; then qemu-aarch64 -L "$(SYSROOT_ARM64)" $(OUT_ARM64); \
	else qemu-aarch64 -L /usr/aarch64-linux-gnu/ $(OUT_ARM64); fi

run32: protect32
	@echo "[*] Running protected ARM32 binary with QEMU..."
	qemu-arm -L /usr/arm-linux-gnueabihf/ $(PROTECTED)_arm32

clean:
	rm -f $(OUT_ARM64) $(OUT_ARM32) $(PROTECTED) $(PROTECTED)_arm32 *.vmp
