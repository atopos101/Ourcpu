module ex_mem_reg(
    input  wire        clk,
    input  wire        reset,

    // 控制信号
    input  wire        stall,
    input  wire        flush,

    // 来自 EX 阶段
    input  wire [31:0] ex_pc,
    input  wire [31:0] ex_alu_result,
    input  wire [31:0] ex_rkd_value,
    input  wire        ex_mem_we,
    input  wire        ex_gr_we,
    input  wire        ex_res_from_mem,
    input  wire [4:0]  ex_dest,

    // 输出到 MEM 阶段
    output reg  [31:0] mem_pc,
    output reg  [31:0] mem_alu_result,
    output reg  [31:0] mem_rkd_value,
    output reg         mem_mem_we,
    output reg         mem_gr_we,
    output reg         mem_res_from_mem,
    output reg  [4:0]  mem_dest
);

always @(posedge clk) begin
    if (reset || flush) begin
        mem_pc           <= 32'b0;
        mem_alu_result   <= 32'b0;
        mem_rkd_value    <= 32'b0;
        mem_mem_we       <= 1'b0;
        mem_gr_we        <= 1'b0;
        mem_res_from_mem <= 1'b0;
        mem_dest         <= 5'b0;
    end
    else if (!stall) begin
        mem_pc           <= ex_pc;
        mem_alu_result   <= ex_alu_result;
        mem_rkd_value    <= ex_rkd_value;
        mem_mem_we       <= ex_mem_we;
        mem_gr_we        <= ex_gr_we;
        mem_res_from_mem <= ex_res_from_mem;
        mem_dest         <= ex_dest;
    end
end

endmodule