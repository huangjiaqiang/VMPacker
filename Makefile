# ============================================================
# VMP 工具链 Makefile
# make all    → 编译 C stub → 嵌入 Go → 输出到 build/
# make stub   → 仅编译 VM 解释器 blob
# make packer → 仅编译 Go packer（需先 make stub）
# make demo   → 交叉编译 demo 程序
# make test   → 运行 Go 单元测试
# make test-build → 在 test/ 目录构建测试程序
# make clean  → 清理所有产物
# ============================================================

# 交叉编译工具链
# CROSS_ARM32: 支持 arm-linux-gnueabihf- (Linux) 或 armv7-unknown-linux-gnueabihf- (macOS messense)
# macOS 可用: make stub32 CROSS_ARM32=scripts/toolchains/armv7-unknown-linux-gnueabihf/bin/armv7-unknown-linux-gnueabihf-
CROSS       ?= aarch64-linux-gnu-
CROSS_ARM32 ?= arm-linux-gnueabihf-
CC           = $(CROSS)gcc
LD           = $(CROSS)ld
OBJCOPY      = $(CROSS)objcopy
CC_ARM32     = $(CROSS_ARM32)gcc
LD_ARM32     = $(CROSS_ARM32)ld
OBJCOPY_ARM32= $(CROSS_ARM32)objcopy
GO           = go

# 目录
STUB_DIR   = stub
CMD_DIR    = cmd/vmpacker
DEMO_DIR   = demo
BUILD_DIR  = build

# ------ VM 解释器 blob (ARM64) ------
STUB_SRC   = $(STUB_DIR)/vm_interp_clean.c
STUB_LDS   = $(STUB_DIR)/vm_interp.lds
STUB_O     = $(BUILD_DIR)/stub/vm_interp.o
STUB_ELF   = $(BUILD_DIR)/stub/vm_interp.elf
STUB_BIN   = $(CMD_DIR)/vm_interp.bin

# ------ VM 解释器 blob (ARM32) ------
STUB32_DIR   = $(STUB_DIR)/arm32
STUB32_SRC   = $(STUB32_DIR)/vm_interp_arm32.c
STUB32_ASM   = $(STUB32_DIR)/token_table_va.S
STUB32_LDS   = $(STUB32_DIR)/vm_interp_arm32.lds
STUB32_O     = $(BUILD_DIR)/stub/vm_interp_arm32.o
STUB32_VA_O  = $(BUILD_DIR)/stub/token_table_va.o
STUB32_ELF   = $(BUILD_DIR)/stub/vm_interp_arm32.elf
STUB32_BIN   = $(CMD_DIR)/vm_interp_arm32.bin

# ------ Go packer ------
PACKER     = $(BUILD_DIR)/vmpacker.exe

# ------ Demo ------
DEMO_LICENSE     = $(BUILD_DIR)/demo_license
DEMO_SIMPLE      = $(BUILD_DIR)/demo_simple

# 编译选项 (ARM64: 必须 -mcmodel=tiny，禁止 -fPIC)
STUB_CFLAGS = -c -Os -mcmodel=tiny -fno-stack-protector \
              -fno-builtin -nostdlib -march=armv8-a \
              -DVM_INDIRECT_DISPATCH -DVM_FUNC_SPLIT -DVM_TOKEN_ENTRY

# 编译选项 (ARM32: -marm 确保 stub 为 ARM 以匹配 trampoline 的 B 跳转，-mthumb-interwork 供 token_table_va.S)
# -fPIC is required: the stub blob is linked at VA 0 but loaded at a different runtime VA.
# Without -fPIC, GCC emits absolute addresses in literal pools and switch jump tables,
# causing crashes when the blob runs at a non-zero base address.
STUB32_CFLAGS = -c -Os -fno-stack-protector \
                -fno-builtin -nostdlib \
                -marm -march=armv7-a -mthumb-interwork -mfloat-abi=soft \
                -fPIC \
                -DVM_INDIRECT_DISPATCH -DVM_FUNC_SPLIT -DVM_TOKEN_ENTRY


DEMO_CFLAGS = -static -O0 -march=armv8-a

# ============================================================
.PHONY: all stub stub32 stub32-debug packer demo test clean help gui sync-public

all: stub stub32 packer
	@echo ""
	@echo "[+] Build complete: $(BUILD_DIR)/"

# ------ VM 解释器 blob (ARM64) ------
stub: $(STUB_BIN)

$(STUB_O): $(STUB_SRC) | $(BUILD_DIR)/stub
	$(CC) $(STUB_CFLAGS) $< -o $@

$(STUB_ELF): $(STUB_O) $(STUB_LDS)
	$(LD) -T $(STUB_LDS) -o $@ $(STUB_O)

$(STUB_BIN): $(STUB_ELF) | $(BUILD_DIR)
	$(OBJCOPY) -O binary $< $(BUILD_DIR)/vm_interp_raw.bin
	@powershell -Command "\
		$$nmOut = & '$(CROSS)nm' '$<';\
		$$l1 = $$nmOut | Select-String '\bvm_entry$$';\
		$$l2 = $$nmOut | Select-String '\bvm_entry_token$$';\
		$$l3 = $$nmOut | Select-String '\b_token_table_va$$';\
		if (!$$l1) { Write-Error 'vm_entry not found'; exit 1 };\
		if (!$$l2) { Write-Error 'vm_entry_token not found'; exit 1 };\
		if (!$$l3) { Write-Error '_token_table_va not found'; exit 1 };\
		$$off1 = [Convert]::ToUInt64($$l1.ToString().Split(' ')[0], 16);\
		$$off2 = [Convert]::ToUInt64($$l2.ToString().Split(' ')[0], 16);\
		$$off3 = [Convert]::ToUInt64($$l3.ToString().Split(' ')[0], 16);\
		$$hdr = [BitConverter]::GetBytes([UInt64]$$off1) + [BitConverter]::GetBytes([UInt64]$$off2) + [BitConverter]::GetBytes([UInt64]$$off3);\
		$$raw = [IO.File]::ReadAllBytes('$(BUILD_DIR)/vm_interp_raw.bin');\
		$$blob = $$hdr + $$raw;\
		[IO.File]::WriteAllBytes('$(STUB_BIN)', $$blob);\
		Write-Host ('[+] vm_interp.bin: ' + $$blob.Length + ' bytes (vm_entry=0x' + $$off1.ToString('X') + ' vm_entry_token=0x' + $$off2.ToString('X') + ' _token_table_va=0x' + $$off3.ToString('X') + ')')\
	"
	@copy /Y "$(subst /,\,$(STUB_BIN))" "$(subst /,\,$(BUILD_DIR))\vm_interp.bin" > nul

# ------ VM 解释器 blob (ARM32) ------
# stub32-debug: 带 VM_DEBUG，输出字符 1-9 到 stderr 追踪执行路径
stub32-debug:
	$(CC_ARM32) $(STUB32_CFLAGS) -DVM_DEBUG -I$(STUB_DIR) $(STUB32_SRC) -o $(STUB32_O)
	$(MAKE) -f $(MAKEFILE_LIST) $(STUB32_BIN)
	@echo "[+] stub32 built with VM_DEBUG (run protected binary, check stderr for 1-9)"

stub32: $(STUB32_BIN)

$(STUB32_O): $(STUB32_SRC) | $(BUILD_DIR)/stub
	$(CC_ARM32) $(STUB32_CFLAGS) -I$(STUB_DIR) $< -o $@

$(STUB32_VA_O): $(STUB32_ASM) | $(BUILD_DIR)/stub
	$(CC_ARM32) -c -marm -march=armv7-a -mthumb-interwork $< -o $@

$(STUB32_ELF): $(STUB32_O) $(STUB32_VA_O) $(STUB32_LDS)
	$(LD_ARM32) -T $(STUB32_LDS) -o $@ $(STUB32_O) $(STUB32_VA_O)

$(STUB32_BIN): $(STUB32_ELF) | $(BUILD_DIR)
	$(OBJCOPY_ARM32) -O binary $< $(BUILD_DIR)/vm_interp_arm32_raw.bin
	@if command -v powershell >/dev/null 2>&1; then \
		powershell -Command "$$nmOut = & '$(CROSS_ARM32)nm' '$<'; $$l1 = $$nmOut | Select-String '\bvm_entry$$'; $$l2 = $$nmOut | Select-String '\bvm_entry_token$$'; $$l3 = $$nmOut | Select-String '\b_token_table_va$$'; if (!$$l1) { Write-Error 'vm_entry not found'; exit 1 }; if (!$$l2) { Write-Error 'vm_entry_token not found'; exit 1 }; if (!$$l3) { Write-Error '_token_table_va not found'; exit 1 }; $$off1 = [Convert]::ToUInt32($$l1.ToString().Split(' ')[0], 16); $$off2 = [Convert]::ToUInt32($$l2.ToString().Split(' ')[0], 16); $$off3 = [Convert]::ToUInt32($$l3.ToString().Split(' ')[0], 16); $$hdr = [BitConverter]::GetBytes([UInt32]$$off1) + [BitConverter]::GetBytes([UInt32]$$off2) + [BitConverter]::GetBytes([UInt32]$$off3); $$raw = [IO.File]::ReadAllBytes('$(BUILD_DIR)/vm_interp_arm32_raw.bin'); $$blob = $$hdr + $$raw; [IO.File]::WriteAllBytes('$(STUB32_BIN)', $$blob); Write-Host ('[+] vm_interp_arm32.bin: ' + $$blob.Length + ' bytes')"; \
	else \
		chmod +x scripts/build_stub32_unix.sh 2>/dev/null; \
		./scripts/build_stub32_unix.sh '$<' '$(BUILD_DIR)/vm_interp_arm32_raw.bin' '$(STUB32_BIN)' '$(CROSS_ARM32)nm'; \
	fi
	@cp -f $(STUB32_BIN) $(BUILD_DIR)/vm_interp_arm32.bin 2>/dev/null || true

# stub32-sync: 将已生成的 stub32 复制到 vmp-gui (无需重新编译)
stub32-sync:
	@if [ -f $(STUB32_BIN) ]; then cp -f $(STUB32_BIN) vmp-gui/backend/api/vm_interp_arm32.bin; echo "[+] Synced"; else echo "Run 'make stub32' or 'make stub32-clang' first"; exit 1; fi

# ------ Go packer (embed vm_interp.bin + vm_interp_arm32.bin) ------
packer: $(STUB_BIN) $(STUB32_BIN) | $(BUILD_DIR)
	@powershell -Command "if (Test-Path '$(PACKER)') { Remove-Item -Force '$(PACKER)' -ErrorAction SilentlyContinue }"
	$(GO) build -o $(PACKER) ./$(CMD_DIR)/
	@echo "[+] packer: $(PACKER)"

# ------ Demo 程序 ------
demo: $(DEMO_LICENSE) $(DEMO_SIMPLE)

$(DEMO_LICENSE): $(DEMO_DIR)/demo_license.c | $(BUILD_DIR)
	$(CC) $(DEMO_CFLAGS) $< -o $@
	@echo "[+] demo: $@"

$(DEMO_SIMPLE): $(DEMO_DIR)/demo_simple.c | $(BUILD_DIR)
	$(CC) -static -O1 -nostdlib -march=armv8-a $< -o $@
	@echo "[+] demo: $@"

# ------ 测试 ------
test:
	$(GO) test ./...

# ------ 目录创建 ------
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/stub: | $(BUILD_DIR)
	@mkdir -p $(BUILD_DIR)/stub

# ------ 清理 ------
clean:
	@powershell -Command "Remove-Item -Recurse -Force -ErrorAction SilentlyContinue '$(BUILD_DIR)', '$(STUB_BIN)', '$(STUB32_BIN)'"
	@echo "[+] cleaned"

# ------ 测试程序构建与保护 ------
test-build: stub stub32
	@$(MAKE) -C test arm64

test-protect: test-build
	@go run ./cmd/vmpacker/ -func log2Console -v -debug -o test/simple_app_protected test/simple_app_arm64
	@echo "[+] Protected: test/simple_app_protected"

# ------ 帮助 ------
help:
	@echo "make all     - 编译 stub (ARM64+ARM32) + packer (输出到 build/)"
	@echo "make stub    - 仅编译 ARM64 VM 解释器 blob"
	@echo "make stub32  - 仅编译 ARM32 VM 解释器 blob (需 arm-linux-gnueabihf-gcc)"
	@echo "               macOS: 用 scripts/build_stub32_docker.sh 或 Linux/Windows 构建"
	@echo "make packer  - 编译 Go packer (自动嵌入 blob)"
	@echo "make gui     - 编译 GUI 版本 + NSIS 安装包"
	@echo "make demo    - 交叉编译 demo 程序"
	@echo "make test    - 运行单元测试"
	@echo "make test-build  - 构建 test/simple_app (需 aarch64-linux-gnu-gcc)"
	@echo "make test-protect - 构建并保护 test 程序"
	@echo "make clean        - 清理所有产物"
	@echo "make sync-public  - 同步到公开仓库 (vmpack remote)"

# ------ GUI 版本 (Wails + NSIS) ------
GUI_DIR = vmp-gui

gui: stub stub32
	@copy /Y "$(subst /,\,$(STUB_BIN))" "$(subst /,\,$(GUI_DIR))\backend\api\vm_interp.bin" > nul
	@copy /Y "$(subst /,\,$(STUB32_BIN))" "$(subst /,\,$(GUI_DIR))\backend\api\vm_interp_arm32.bin" > nul
	@powershell -Command "$$env:PATH = 'C:\Program Files (x86)\NSIS;' + $$env:PATH; cd '$(GUI_DIR)'; wails build -nsis"
	@echo "[+] GUI installer: $(GUI_DIR)/build/bin/"

# ------ 同步公开仓库 ------
sync-public:
	@powershell -ExecutionPolicy Bypass -File sync-public.ps1

