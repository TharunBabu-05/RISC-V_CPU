# RISC-V CPU External Compliance Testing Setup Guide

## Overview
This guide walks through setting up the external compliance testing environment for the RISC-V CPU project using the official riscv-tests test suite.

## Prerequisites

### System Requirements
- Windows 10+ with WSL2 or Git Bash
- Python 3.8+
- 2GB disk space for toolchain and tests

### Required Tools

#### 1. RISC-V Cross-Compiler Toolchain
The `riscv-tests` project requires the RISC-V GNU toolchain to build test executables.

**Installation Options:**

**Option A: Pre-built Binaries (Recommended for Windows)**
```bash
# Download from SiFive Freedom Tools
# https://www.sifive.com/boards

# Or use xpack-riscv-toolchain:
npm install --global @xpack-dev-tools/riscv-toolchain
```

**Option B: Build from Source**
```bash
git clone https://github.com/riscv-collab/riscv-gnu-toolchain
cd riscv-gnu-toolchain
./configure --prefix=/opt/riscv --with-arch=rv32im --with-abi=ilp32
make -j$(nproc)
export PATH=/opt/riscv/bin:$PATH
```

**Option C: WSL with apt (Easiest for Linux subsystem)**
```bash
wsl
sudo apt-get install -y gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
```

**Verification:**
```bash
riscv64-unknown-elf-gcc --version
```

#### 2. Additional Build Tools
- GNU Make
- Git (with submodules support)
- Bash (Git Bash on Windows or WSL)

### Project Setup

1. **Clone/Download riscv-tests Repository**
   ```bash
   cd C:\Users\tharu\RISC-V_CPU
   git clone https://github.com/riscv/riscv-tests.git
   cd riscv-tests
   git submodule update --init --recursive
   ```

2. **Configure riscv-tests**
   ```bash
   ./configure
   ```

3. **Build Test Suites**
   ```bash
   make
   ```

## Running Compliance Tests

### Command Syntax
```bash
cd C:\Users\tharu\RISC-V_CPU\riscv_cpu-2
python phase5/compliance/run_rv32_compliance.py [options]
```

### Options
- `--profile {rv32i|rv32im|rv64i|rv64im|all}` - ISA profile to test
- `--suite-root PATH` - Path to riscv-tests repository (auto-detected if not specified)
- `--output DIR` - Output directory for test signatures (default: phase5/compliance/signature)
- `--command-template CMD` - Custom make command template
- `--dry-run` - Show commands without executing
- `--verbose` - Enable verbose output

### Example Commands

**Test RV32I Profile**
```bash
python phase5/compliance/run_rv32_compliance.py --profile rv32i
```

**Test All Profiles**
```bash
python phase5/compliance/run_rv32_compliance.py --profile all
```

**Test with Custom riscv-tests Location**
```bash
python phase5/compliance/run_rv32_compliance.py --profile rv32i --suite-root C:\path\to\riscv-tests
```

**Dry Run (Show Commands)**
```bash
python phase5/compliance/run_rv32_compliance.py --profile rv32i --dry-run
```

## Understanding Test Output

### Signature Files
Tests generate execution signatures in `phase5/compliance/signature/{profile}/`:
- `rv32i_m/` - RV32I base ISA tests
- `rv32im_m/` - RV32I + M extension tests
- `rv64i_m/` - RV64I base ISA tests
- `rv64im_m/` - RV64I + M extension tests

Each signature file contains captured register states from test execution, used to verify correct CPU behavior.

### Test Pass/Fail Criteria
Tests pass when:
1. All instructions execute without errors
2. Final register states match expected values in signatures
3. All CSR modifications are correct
4. Memory operations produce correct results

### Example Output
```
Running RV32I compliance tests...
make -C C:/Users/tharu/RISC-V_CPU/riscv-tests ISA=rv32i XLEN=32 EXTENSIONS=i SIGNATURE_DIR=C:/Users/tharu/RISC-V_CPU/riscv_cpu-2/phase5/compliance/signature/rv32i_m
[Test Suite Output...]
Generated signature: C:/Users/tharu/RISC-V_CPU/riscv_cpu-2/phase5/compliance/signature/rv32i_m/*.sig
```

## Troubleshooting

### Error: "riscv64-unknown-elf-gcc: command not found"
**Solution:** Install the RISC-V toolchain as described in Prerequisites section.

### Error: "No targets specified and no makefile found"
**Solution:** Run `./configure` in the riscv-tests directory first.

### Error: "Permission denied" on configure/make
**Solution:** On Windows, run from Git Bash or WSL2, not PowerShell.

### Path-related errors on Windows
**Solution:** The compliance harness automatically converts paths to forward slashes for make compatibility. If issues persist:
1. Use WSL2 instead of native Windows
2. Use Git Bash instead of PowerShell
3. Specify paths with `--suite-root` explicitly

### Tests run but signatures are empty
**Solution:** Check that:
1. The CPU simulation compiled successfully
2. Test vectors were properly loaded into simulation
3. Output directory is writable

## Integration with CI/CD

The compliance harness can be integrated into continuous integration pipelines:

```bash
# In CI script:
python phase5/compliance/run_rv32_compliance.py --profile all --verbose
if [ $? -ne 0 ]; then
    echo "Compliance tests failed"
    exit 1
fi
echo "All compliance tests passed"
```

## Performance Notes

- RV32I tests typically complete in 2-5 minutes
- RV32I+M tests typically complete in 5-10 minutes
- RV64 tests are larger and may take longer
- Times vary based on simulation speed and machine performance

## Next Steps

1. Install RISC-V toolchain from Prerequisites
2. Configure riscv-tests with `./configure`
3. Build test suites with `make`
4. Run compliance tests using the commands above
5. Verify signatures are generated in signature directories
6. Review signatures against reference golden files

## Support

For issues with riscv-tests or toolchain setup, see:
- https://github.com/riscv/riscv-tests
- https://github.com/riscv-collab/riscv-gnu-toolchain

For CPU simulation issues, refer to:
- [Phase 5 Implementation Guide](phase5_implementation_guide.md)
- [Project README](../../README.md)
