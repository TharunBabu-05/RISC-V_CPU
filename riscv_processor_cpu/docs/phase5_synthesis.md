# Phase 5 Synthesis Handoff

## Measured result (FPGA)

The FPGA design (`phase8/rtl/soc_top.sv`, Arty S7-50, Vivado 2020.2) meets all timing constraints at 25 MHz:
worst setup slack +14.6 ns, 0 failing setup/hold endpoints; 3,749 LUTs, 3,674 flip-flops, 4 DSPs, 16 BRAM tiles.
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

Current simulation models (`memory.sv`, cache/MMU path) are behavioral.
For implementation:

- **FPGA path**
  - Replace inferred arrays with vendor BRAM primitives/IP.
  - Keep byte-enable behavior aligned with store semantics.
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
