`timescale 1ns/1ps
module tb_dual_issue #(parameter DUAL=1, CACHE=1);
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    wire iv, ir, iw, isv, isr, ise, dv, dr, dw, dsv, dsr;
    reg irq=0, irq_sent=0;
    reg [31:0] irq_pc;
    integer traps=0;
    wire [31:0] ia, idata, da, wd, rd, debug_pc;
    wire [3:0] strobe;
    wire [1:0] size;
    reg [31:0] instructions[0:1023];
    reg [31:0] data[0:255];
    reg [31:0] expected[0:31];
    reg [31:0] i_saved, d_saved, d_value;
    reg i_pending=0,d_pending=0;
    reg [31:0] i_result=0,d_result=0;
    reg i_valid=0,d_valid=0;
    integer i_delay=0,d_delay=0,cycles=0,pairs=0,fetches=0;
    reg d_write;
    reg [3:0] d_strobe;
    assign ir=!i_pending;
    assign dr=!d_pending;
    assign isv=i_valid;
    assign idata=i_result;
    assign ise=0;
    assign dsv=d_valid;
    assign rd=d_result;
    cpu_top_soc #(.ENABLE_MMU(0), .FAST_LOCAL_IMEM(0), .FAST_LOCAL_DMEM(0),
        .ENABLE_ICACHE(CACHE), .DUAL_ISSUE(DUAL)) dut (
        .clk(clk), .rst_n(rst_n), .ext_interrupt(irq), .timer_interrupt(1'b0),
        .software_interrupt(1'b0), .imem_rdata(32'b0), .dtcm_rdata(32'b0),
        .ibus_req_valid(iv), .ibus_req_ready(ir), .ibus_req_addr(ia),
        .ibus_req_write(iw), .ibus_rsp_valid(isv), .ibus_rsp_ready(isr),
        .ibus_rsp_rdata(idata), .ibus_rsp_err(ise),
        .dbus_req_valid(dv), .dbus_req_ready(dr), .dbus_req_addr(da),
        .dbus_req_write(dw), .dbus_req_wstrb(strobe), .dbus_req_wdata(wd),
        .dbus_req_size(size), .dbus_rsp_valid(dsv), .dbus_rsp_ready(dsr),
        .dbus_rsp_rdata(rd), .dbus_rsp_err(d_valid && d_saved[31:28]==9),
        .ptw_req_ready(1'b0), .ptw_rsp_valid(1'b0), .ptw_rsp_rdata(32'b0),
        .ptw_rsp_err(1'b0), .dbg_pc(debug_pc)
    );
    always @(negedge clk) if(rst_n) begin
        if (!irq_sent && dut.if_id_valid && dut.if_id_pc == irq_pc) begin
            irq=1; irq_sent=1;
        end else irq=0;
    end
    always @(posedge clk) if(rst_n) begin
        if ($test$plusargs("trace") && cycles < 80)
            $display("c=%0d pc=%h req=%b/%b rsp=%b/%b pending=%b buffered=%b stall=%b/%b",cycles,debug_pc,iv,ir,isv,isr,dut.ifetch_pending,dut.ifetch_valid,dut.mem_stall,dut.mmu_stall);
        cycles<=cycles+1;
        if(dut.trap_taken) traps<=traps+1;
        if(dut.wb_retire && dut.id_ex_pair) pairs<=pairs+1;
        if(iv && ir) begin
            i_pending<=1; i_saved<=ia; i_delay<=cycles%5+1; fetches<=fetches+1;
        end
        if(i_pending && !i_valid) begin
            if(i_delay==0) begin
                i_valid<=1;
                if(i_saved==0) i_result<=32'h800000b7; // lui ra,0x80000
                else if(i_saved==4) i_result<=32'h00008067; // jalr zero,ra
                else i_result<=instructions[i_saved[11:2]];
            end else i_delay<=i_delay-1;
        end
        if(i_valid && isr) begin i_valid<=0; i_pending<=0; end
        if(dv && dr) begin
            d_pending<=1; d_saved<=da; d_value<=wd; d_write<=dw;
            d_strobe<=strobe; d_delay<=cycles%7+2;
        end
        if(d_pending && !d_valid) begin
            if(d_delay==0) begin
                d_valid<=1; d_result<=data[d_saved[9:2]];
                if(d_write) begin
                    if(d_saved[31:28]==8)
                        instructions[d_saved[11:2]]<=d_value;
                    else for(integer b=0;b<4;b=b+1)
                        if(d_strobe[b]) data[d_saved[9:2]][b*8+:8]<=d_value[b*8+:8];
                end
            end else d_delay<=d_delay-1;
        end
        if(d_valid && dsr) begin
            d_valid<=0; d_pending<=0;
            if(d_write && d_saved==32'h1000) begin
                for(integer n=2;n<31;n=n+1)
                    if(dut.u_regfile.regs[n] !== expected[n])
                        $fatal(1,"x%0d expected=%h got=%h",n,expected[n],dut.u_regfile.regs[n]);
                if(DUAL && CACHE && pairs<10) $fatal(1,"No meaningful dual execution");
                if((!DUAL || !CACHE) && pairs!=0) $fatal(1,"paired when disabled");
                if(traps!=4 || !irq_sent) $fatal(1,"Missing traps: %0d",traps);
                $display("PASS dual=%0d cache=%0d cycles=%0d pairs=%0d bus_fetches=%0d",DUAL,CACHE,cycles,pairs,fetches);
                $finish;
            end
        end
        if(cycles>100000) $fatal(1,"CPU timeout pc=%h",debug_pc);
    end
    function automatic [31:0] imm(input integer rd_n, rs, value, f);
        imm={value[11:0],rs[4:0],f[2:0],rd_n[4:0],7'h13};
    endfunction
    function automatic [31:0] op(input integer rd_n, rs1, rs2, f, f7);
        op={f7[6:0],rs2[4:0],rs1[4:0],f[2:0],rd_n[4:0],7'h33};
    endfunction
    function automatic [31:0] jal(input integer rd_n, offset);
        jal={offset[20],offset[10:1],offset[11],offset[19:12],rd_n[4:0],7'h6f};
    endfunction
    function automatic [31:0] csr(input integer address, dst_n, src_n, f);
        csr={address[11:0],src_n[4:0],f[2:0],dst_n[4:0],7'h73};
    endfunction
    integer at=0, seed=32'h12345678, dst,s1,s2,f,kind;
    reg [31:0] a,b,result;
    task automatic emit(input [31:0] insn);
        instructions[at]=insn; at=at+1;
    endtask
    initial begin
        if ($value$plusargs("SEED=%d", seed)) $display("Random seed %0d",seed);
        for(integer n=0;n<1024;n=n+1) instructions[n]=32'h13;
        for(integer n=0;n<256;n=n+1) data[n]=0;
        for(integer n=0;n<32;n=n+1) expected[n]=0;
        expected[1]=32'h80000000;
        // Independent and dependent ALU pairs, WAW, x0 and WAR cases.
        for(integer n=2;n<31;n=n+1) begin
            emit(imm(n,0,n*3,0)); expected[n]=n*3;
        end
        for(integer n=0;n<300;n=n+1) begin
            dst=2+($random(seed)&32'h7fffffff)%29;
            s1=($random(seed)&32'h7fffffff)%31;
            s2=($random(seed)&32'h7fffffff)%31;
            f=($random(seed)&32'h7fffffff)%8;
            kind=($random(seed)&32'h7fffffff)%2;
            a=expected[s1]; b=expected[s2];
            case(f)
                0: result=kind ? a-b : a+b;
                1: result=a<<b[4:0];
                2: result={31'b0,$signed(a)<$signed(b)};
                3: result={31'b0,a<b};
                4: result=a^b;
                5: if(kind) result=$signed(a)>>>b[4:0]; else result=a>>b[4:0];
                6: result=a|b;
                7: result=a&b;
            endcase
            emit(op(dst,s1,s2,f,(kind && (f==0 || f==5)) ? 32 : 0));
            expected[dst]=result;
        end
        // Serial operations between pairs, with a load-use dependency.
        emit(32'h04202023); // sw x2,64(zero)
        emit(32'h04002183); // lw x3,64(zero)
        expected[3]=expected[2];
        emit(imm(4,3,7,0)); expected[4]=expected[3]+7;
        emit(op(5,4,3,0,1)); expected[5]=expected[4]*expected[3]; // mul
        // Taken branch must squash both instructions in a younger pair.
        emit(32'h00000663); // beq zero,zero,+12
        emit(imm(2,0,123,0));
        emit(imm(3,0,123,0));
        emit(32'h0000100f); // fence.i
        // Cache a leaf, modify its first instruction, and execute after FENCE.I.
        instructions['hc00/4]=imm(26,0,11,0);
        instructions['hc04/4]=imm(25,0,7,0);
        instructions['hc08/4]=32'h000f0067; // jalr zero,x30
        emit(jal(30,'hc00-at*4));
        emit(32'h80001e37); // lui x28,0x80001
        emit(imm(28,28,-1024,0));
        emit(32'h06301eb7); // lui x29,0x06301
        emit(imm(29,29,-749,0)); // 0x06300d13 = addi x26,zero,99
        emit(32'h01de2023); // sw x29,0(x28)
        emit(32'h0000100f);
        emit(jal(30,'hc00-at*4));
        emit(jal(30,'hc00-at*4)); // Re-enter without a fence to exercise hits.
        expected[25]=7; expected[26]=99; expected[30]=32'h80000000+at*4;
        // Precise exception handler plus an interrupt on a paired ALU bundle.
        instructions['he00/4]=csr('h342,27,0,2); // mcause
        instructions['he04/4]=csr('h341,28,0,2); // mepc
        instructions['he08/4]=imm(29,29,1,0); // trap count
        instructions['he0c/4]=32'h000dc663; // blt x27,zero,+12: IRQ resumes unchanged
        instructions['he10/4]=imm(28,28,4,0);
        instructions['he14/4]=csr('h341,0,28,1);
        instructions['he18/4]=32'h30200073;
        emit(32'h80001e37);
        emit(imm(28,28,-512,0));
        emit(csr('h305,0,28,1)); // mtvec = 0x80000e00
        emit(imm(29,0,0,0));
        emit(32'h00000073); // ecall
        emit(32'hffffffff); // illegal instruction
        emit(32'h90000db7); // lui x27,0x90000
        emit(32'h000da003); // lw zero,0(x27): older data access fault
        emit(imm(2,2,1,0)); expected[2]=expected[2]+1;
        emit(imm(3,3,1,0)); expected[3]=expected[3]+1;
        emit(32'h00001db7); // external interrupt enable bit 11
        emit(imm(27,27,-2048,0));
        emit(csr('h304,0,27,1));
        emit(csr('h300,0,8,6)); // csrsi mstatus,8
        if(at%2) emit(32'h13);
        irq_pc=32'h80000000+at*4;
        emit(imm(2,2,1,0)); expected[2]=expected[2]+1;
        emit(imm(3,3,1,0)); expected[3]=expected[3]+1;
        expected[27]=32'h8000000b; expected[28]=irq_pc+((DUAL && CACHE) ? 8 : 4); expected[29]=4;
        emit(32'h00001fb7); // lui x31,1
        emit(32'h000fa023); // sw zero,0(x31), completion
        repeat(5) @(negedge clk); rst_n=1;
    end
endmodule
