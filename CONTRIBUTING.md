# Contributing

Thanks for taking an interest in the RISC-V CPU and FPGA SoC. Changes to RTL,
firmware, tests, and documentation are welcome.

## Before You Start

- For a large architectural change, open an issue first and describe the
  intended behavior and how it will be verified.
- Keep changes focused. Do not commit generated Vivado run directories,
  bitstreams, firmware binaries, WAD files, credentials, or board-specific
  local settings.
- Preserve upstream copyright notices and license terms when working with
  DoomGeneric or other third-party code.

## Testing

Run the tests relevant to your change and include the commands and results in
your pull request. Useful entry points include:

```powershell
make -C riscv_processor_cpu/phase8/tb all
make -C riscv_processor_cpu/phase8/tb portable
```

For changes to the DDR video protocol or host viewer, run from
`riscv_processor_cpu/phase8/software`:

```powershell
make doom_stream_test doom_stream_detail_test doom_viewer_test
```

For FPGA-facing changes, simulation alone is not timing signoff. Record the
Vivado version, target project/profile, timing result, and whether the change
was tested on physical hardware. Keep experimental DDR/DOOM projects separate
from the established QSPI/Snake baseline.

## Pull Requests

Please include:

- A concise description of the behavior changed and why.
- Tests run, including failures or tests that could not be run.
- Timing/resource changes for synthesized RTL, where available.
- Hardware model and exact bitstream/profile for any board result.
- Updated documentation when commands, interfaces, or measured results change.

Small, reviewable changes are easier to validate against the RTL and board
flows. Do not present simulation results as hardware measurements.
