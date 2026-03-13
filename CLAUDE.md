# CLAUDE.md

## Project Overview

VMPacker is a **Virtual Machine Protection (VMP)** system for ARM64/ARM32 Linux ELF binaries. It translates native ARM instructions into custom VM bytecode and injects a VM interpreter stub, making reverse engineering significantly harder.

## Build Commands

```bash
# Full build (ARM64 + ARM32 stubs + Go packer)
make all

# Build individual components
make stub      # ARM64 VM interpreter only
make stub32    # ARM32 VM interpreter only
make packer    # Go packer CLI (requires stub + stub32 first)

# Run Go unit tests
make test

# Build test programs (requires cross-compilation toolchain)
make test-build       # Build ARM64 test binary in test/
cd test && make arm64 # Alternative: build from test directory

# Build and protect test program
cd test && make protect   # Protect ARM64 version
cd test && make protect32 # Protect ARM32 version

# Run protected binary with QEMU
cd test && make run       # Run ARM64 protected
cd test && make run32     # Run ARM32 protected
```

## Cross-Compilation Toolchains

**Pre-installed toolchains are available in `scripts/toolchains/`:**
- ARM64: `scripts/toolchains/aarch64-unknown-linux-gnu/`
- ARM32: `scripts/toolchains/armv7-unknown-linux-gnueabihf/`

**Usage with pre-installed toolchains:**
```bash
# ARM64
make stub CROSS=scripts/toolchains/aarch64-unknown-linux-gnu/bin/aarch64-unknown-linux-gnu-

# ARM32
make stub32 CROSS_ARM32=scripts/toolchains/armv7-unknown-linux-gnueabihf/bin/armv7-unknown-linux-gnueabihf-
```

**Alternative system toolchains:**
- ARM64: `aarch64-linux-gnu-` (standard on most Linux distros)
- ARM32: `arm-linux-gnueabihf-` (Linux) or install via `brew install messense/macos-cross-toolchains/armv7-unknown-linux-gnueabihf` (macOS)

## CLI Usage

```bash
# Protect by function name
./build/vmpacker.exe -func check_license -v -o protected.elf original.elf

# Protect multiple functions
./build/vmpacker.exe -func "check_license,verify_token" -o protected.elf original.elf

# Protect by address range
./build/vmpacker.exe -addr "0x4006AC-0x400790:main" -o protected.elf original.elf

# Print ELF info (symbol table, segments)
./build/vmpacker.exe -info input.elf

# Key flags
-strip    # Strip symbol table (default: true)
-debug    # Generate ARM64 → VM bytecode mapping file
-token    # Enable tokenized entry mode (default: true)
```

## Architecture

### Directory Structure

```
cmd/vmpacker/           # CLI entry point (main.go)
  ├── vm_interp.bin     # ARM64 VM interpreter (embedded)
  └── vm_interp_arm32.bin # ARM32 VM interpreter (embedded)

pkg/
  ├── arch/arm64/       # ARM64 decoder + translator
  │   ├── decoder.go    # Table-driven instruction decoder
  │   ├── decode_*.go   # Pattern tables (DP-IMM/DP-REG/Branch/LdSt)
  │   ├── translator.go # ARM64 → VM bytecode
  │   └── tr_*.go       # Instruction category translators
  ├── arch/arm32/       # ARM32 decoder + translator (same pattern)
  ├── vm/               # VM ISA definitions
  │   ├── types.go      # Core interfaces (Decoder, Translator, Packer)
  │   ├── opcodes.go    # VM opcode constants (randomly mapped values)
  │   └── disasm.go     # VM bytecode disassembler
  └── binary/elf/       # ELF manipulation
      ├── packer.go     # PT_NOTE → PT_LOAD injection
      └── trampoline.go # Trampoline code generation

stub/                   # C VM interpreter (compiled to flat binary)
  ├── vm_interp_clean.c # Main interpreter loop
  ├── vm_*.h            # Headers (opcodes, types, dispatch, etc.)
  ├── arm32/            # ARM32-specific interpreter
  └── vm_handlers/      # Modular instruction handlers

test/                   # Test programs
  └── simple_app.cpp    # Test application with log2Console function
```

### Core Interfaces (pkg/vm/types.go)

The codebase uses interface-driven design for extensibility:

```go
type Decoder interface {
    Decode(raw uint32, offset int) Instruction
    InstName(op int) string
}

type Translator interface {
    Translate(instructions []Instruction) (*TranslateResult, error)
}

type Packer interface {
    Process() error
}
```

### Protection Pipeline

1. **Locate Function** - Parse ELF symbols or use address range
2. **Decode** - ARM64/ARM32 native instructions → `vm.Instruction`
3. **Translate** - Native instructions → Custom VM bytecode
4. **Encrypt** - XOR bytecode with key derived from PC
5. **Inject** - Append VM interpreter + bytecode to ELF
6. **Trampoline** - Replace original function entry with jump to VM

### VM Opcode Synchronization

VM opcodes are defined in **two places** and must stay in sync:
- Go: `pkg/vm/opcodes.go`
- C: `stub/vm_opcodes.h`

Values are deliberately non-sequential (randomly mapped) to hinder reverse engineering.

## Development Notes

### Adding New ARM64 Instructions

1. Add opcode constant in `pkg/arch/arm64/decoder.go`
2. Add decode pattern in appropriate `decode_*.go` file
3. Add translation logic in `pkg/arch/arm64/translator.go` or `tr_*.go`
4. If new VM opcode needed: add to both `pkg/vm/opcodes.go` AND `stub/vm_opcodes.h`
5. Add handler in `stub/vm_handlers/` for new VM opcodes
6. Run `make stub && make packer` to rebuild

### Stack Machine Opcodes

The codebase uses both register-based (`OP_*`) and stack-based (`OP_S_*`) VM opcodes. Stack-based opcodes operate on `eval_stk[]` and eliminate register allocation conflicts.

### ARM32 vs ARM64 Differences

- ARM32 uses Thumb mode for user code, ARM mode for stub/trampoline
- ARM32 stub requires separate assembly file (`stub/arm32/token_table_va.S`)
- Cross-compilation toolchains differ (see Build Commands above)
