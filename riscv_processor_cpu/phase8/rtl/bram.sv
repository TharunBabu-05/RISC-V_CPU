// ============================================================
//  bram.sv  —  Synthesizable Block RAM (Xilinx BRAM inference)
//
//  Dual-port True BRAM:
//    Port A = Instruction fetch (read-only, 32-bit word aligned)
//    Port B = Data load/store   (read/write, byte-enable)
//
//  Synthesis notes (Vivado 2020.2):
//    - Uses (* ram_style = "block" *) to force BRAM inference
//    - $readmemh inside generate if is elaboration-time — OK
//    - Byte address >>2 used for word index (avoids $clog2 in bit-select)
//    - No for-loop init (Vivado can't synthesize that with $readmemh)
// ============================================================
`timescale 1ns/1ps

module bram #(
    parameter  SIZE_BYTES = 65536,          // 64 KB default
    parameter  INIT_FILE  = ""              // .hex / .vmem firmware file
) (
    input  logic        clk,

    // ---- Port A: Instruction Fetch (Read Only) ----
    input  logic [31:0] a_addr,     // Byte address
    output logic [31:0] a_rdata,    // 32-bit instruction word

    // ---- Port B: Data Load/Store (Read/Write) ----
    input  logic [31:0] b_addr,     // Byte address
    input  logic [31:0] b_wdata,    // Write data
    input  logic [3:0]  b_we,       // Byte-enables (1 bit per byte)
    input  logic        b_re,       // Read enable
    output logic [31:0] b_rdata     // Read data
);

    localparam integer WORDS = SIZE_BYTES / 4;  // Number of 32-bit words

    // Force Xilinx BRAM inference (not distributed LUT RAM)
    (* ram_style = "block" *)
    logic [31:0] mem [0:WORDS-1];

    // -------------------------------------------------------
    //  Memory initialization
    //  Use generate-if so the condition is evaluated at
    //  elaboration time — Vivado can synthesize this as BRAM init.
    //  No for-loop: uninitialized words default to 0 in synthesis.
    // -------------------------------------------------------
    generate
        if (INIT_FILE != "")
            initial $readmemh(INIT_FILE, mem);
    endgenerate

    // -------------------------------------------------------
    //  Port A — Instruction Fetch (synchronous, read-only)
    //  Word index = byte address >> 2 (drop the 2 LSBs)
    // -------------------------------------------------------
    always_ff @(posedge clk) begin
        a_rdata <= mem[a_addr >> 2];
    end

    // -------------------------------------------------------
    //  Port B — Data Memory (synchronous read/write)
    //  Byte-enables allow SB/SH/SW at any alignment
    // -------------------------------------------------------
    always_ff @(posedge clk) begin
        // Write with byte enables
        if (b_we[0]) mem[b_addr >> 2][7:0]   <= b_wdata[7:0];
        if (b_we[1]) mem[b_addr >> 2][15:8]  <= b_wdata[15:8];
        if (b_we[2]) mem[b_addr >> 2][23:16] <= b_wdata[23:16];
        if (b_we[3]) mem[b_addr >> 2][31:24] <= b_wdata[31:24];

        // Read (registered output — standard BRAM behavior)
        if (b_re)
            b_rdata <= mem[b_addr >> 2];
    end

endmodule
