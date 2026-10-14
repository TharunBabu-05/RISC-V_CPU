# Phase 5 Synthesis Handoff

## Measured result (FPGA)

The FPGA design (`phase8/rtl/soc_top.sv`, Arty S7-50, Vivado 2020.2) meets all timing constraints at 25 MHz:
worst setup slack +6.802 ns, worst hold slack +0.028 ns, 0 failing endpoints; 6,367 LUTs, 3,870 flip-flops,
4 DSPs, and 32 BRAM tiles. The logical 64KB memory uses duplicated even/odd word banks so an unaligned
32-bit access can read or write adjacent words in one cycle.
The first implementation missed timing by 61 ns because of single-cycle combinational dividers; see the main
README ("Timing Closure"). Board screenshots: `proof/`.

The generic guidance below applies to other targets; only the Vivado flow has been run.

## 1) Clock/Reset and Timing Constraints

Use a single synchronous core clock and active-low reset at top level.

Example baseline constraints for handoff:

```tcl
# 100 MHz target
create_clock -name core_clk -period 10.000 [get_ports clk]

# Input/output delay assumptions (board/SoC integration dependent)
set_input_delay  2.0 -clock core_clk [all_inputs]
set_output_delay 2.0 -clock core_clk [all_outputs]

# Reset path is asynchronous assertion, synchronous release (handled in integration)
set_false_path -from [get_ports rst_n]
```

## 2) Memory Macro Replacement

The research-core memory and cache/MMU path are synthesizable behavioral models. The FPGA SoC uses the
inferred true dual-port block-RAM wrapper in `phase8/rtl/bram.sv`. For other implementations:

- **FPGA path**
  - Keep the inferred arrays or replace them with equivalent vendor BRAM primitives/IP.
  - Preserve the parity-bank mapping and sequential byte-enable behavior.
- **ASIC path**
  - Replace arrays with foundry SRAM macros.
  - Add wrapper modules for read/write latency alignment.

## 3) Timing Closure Checklist

1. Synthesize with target process/library and PVT corners.
2. Constrain `clk` and IO paths.
3. Review worst negative slack (setup/hold).
4. Pipeline or retime long EX/MEM paths if needed.
5. Re-run post-fix STA and confirm non-negative slack.
6. Preserve simulation equivalence for functional regressions.

## Exit Criteria

- Clean synthesis (no unresolved black-boxes).
- STA passes setup/hold at target frequency.
- Directed regressions still pass on the synthesized netlist flow.

## Checklist Link

See [Phase 5 checklist](phase5_checklist.md) for the consolidated repo handoff status.
