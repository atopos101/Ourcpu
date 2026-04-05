module alu(
    input  [31:0] a,
    input  [31:0] b,
    input  [3:0]  alu_op,    // MIPS ALU 控制信号
    output reg [31:0] result,
    output         zero       // 零标志，用于 beq/bne
);

always @(*) begin
    case (alu_op)
        4'b0000: result = a & b;    // AND
        4'b0001: result = a | b;    // OR
        4'b0010: result = a + b;    // ADD / LW / SW
        4'b0110: result = a - b;    // SUB
        4'b0111: result = (a < b) ? 32'h1 : 32'h0; // SLT
        4'b1100: result = ~(a | b); // NOR
        default: result = 32'h0;
    endcase
end

assign zero = (result == 32'h0);

endmodule
