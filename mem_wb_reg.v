module mem_wb_reg(
    input  wire        clk,
    input  wire        reset,

    // 控制信号
    input  wire        stall,
    input  wire        flush,

    // 来自 MEM 阶段
    input  wire [31:0] mem_pc,
    input  wire [31:0] mem_alu_result,
    input  wire [31:0] mem_read_data,
    input  wire        mem_gr_we,
    input  wire        mem_res_from_mem,
    input  wire [4:0]  mem_dest,

    // 输出到 WB 阶段
    output reg  [31:0] wb_pc,
    output reg  [31:0] wb_result,
    output reg         wb_gr_we,
    output reg  [4:0]  wb_dest
);

always @(posedge clk) begin
    if (reset || flush) begin
        wb_pc     <= 32'b0;
        wb_result <= 32'b0;
        wb_gr_we  <= 1'b0;
        wb_dest   <= 5'b0;
    end
    else if (!stall) begin
        wb_pc     <= mem_pc;
        wb_result <= mem_res_from_mem ? mem_read_data
                                     : mem_alu_result;
        wb_gr_we  <= mem_gr_we;
        wb_dest   <= mem_dest;
    end
end

endmodule