module alu(
  input  wire [18:0] alu_op,
  input  wire [31:0] alu_src1,
  input  wire [31:0] alu_src2,
  output wire [31:0] alu_result
);

wire op_add;   //add operation
wire op_sub;   //sub operation
wire op_slt;   //signed compared and set less than
wire op_sltu;  //unsigned compared and set less than
wire op_and;   //bitwise and
wire op_nor;   //bitwise nor
wire op_or;    //bitwise or
wire op_xor;   //bitwise xor
wire op_sll;   //logic left shift
wire op_srl;   //logic right shift
wire op_sra;   //arithmetic right shift
wire op_lui;   //Load Upper Immediate

// control code decomposition
assign op_add  = alu_op[ 0];
assign op_sub  = alu_op[ 1];
assign op_slt  = alu_op[ 2];
assign op_sltu = alu_op[ 3];
assign op_and  = alu_op[ 4];
assign op_nor  = alu_op[ 5];
assign op_or   = alu_op[ 6];
assign op_xor  = alu_op[ 7];
assign op_sll  = alu_op[ 8];
assign op_srl  = alu_op[ 9];
assign op_sra  = alu_op[10];
assign op_lui  = alu_op[11];

wire [31:0] add_sub_result;
wire [31:0] slt_result;
wire [31:0] sltu_result;
wire [31:0] and_result;
wire [31:0] nor_result;
wire [31:0] or_result;
wire [31:0] xor_result;
wire [31:0] lui_result;
wire [31:0] sll_result;
wire [63:0] sr64_result;
wire [31:0] sr_result;

// 32-bit adder
wire [31:0] adder_a;
wire [31:0] adder_b;
wire        adder_cin;
wire [31:0] adder_result;
wire        adder_cout;

assign adder_a   = alu_src1;
assign adder_b   = (op_sub | op_slt | op_sltu) ? ~alu_src2 : alu_src2;  //src1 - src2 rj-rk
assign adder_cin = (op_sub | op_slt | op_sltu) ? 1'b1      : 1'b0;
assign {adder_cout, adder_result} = adder_a + adder_b + adder_cin;

// ADD, SUB result
assign add_sub_result = adder_result;

// SLT result
assign slt_result[31:1] = 31'b0;   //rj < rk 1
assign slt_result[0]    = (alu_src1[31] & ~alu_src2[31])
                        | ((alu_src1[31] ~^ alu_src2[31]) & adder_result[31]);

// SLTU result
assign sltu_result[31:1] = 31'b0;
assign sltu_result[0]    = ~adder_cout;

// bitwise operation
assign and_result = alu_src1 & alu_src2;
assign or_result  = alu_src1 | alu_src2;
assign nor_result = ~or_result;
assign xor_result = alu_src1 ^ alu_src2;
assign lui_result = alu_src2;

// SLL result
assign sll_result = alu_src1 << alu_src2[4:0];   //rj << ui5

// SRL, SRA result
assign sr64_result = {{32{op_sra & alu_src1[31]}}, alu_src1[31:0]} >> alu_src2[4:0]; //rj >> i5

assign sr_result   = sr64_result[31:0];

// final result mux
assign alu_result = ({32{op_add|op_sub}} & add_sub_result)
                  | ({32{op_slt       }} & slt_result)
                  | ({32{op_sltu      }} & sltu_result)
                  | ({32{op_and       }} & and_result)
                  | ({32{op_nor       }} & nor_result)
                  | ({32{op_or        }} & or_result)
                  | ({32{op_xor       }} & xor_result)
                  | ({32{op_lui       }} & lui_result)
                  | ({32{op_sll       }} & sll_result)
                  | ({32{op_srl|op_sra}} & sr_result);

endmodule

module piped_multiplier(
    input             clk,
    input             reset,
    input             cancel,
    input             start,
    input      [31:0] src1,
    input      [31:0] src2,
    input             signed_hi,
    input             high_result,
    output reg        busy,
    output reg        done,
    output reg [31:0] result
);

wire signed [32:0] signed_src1 = {signed_hi && src1[31], src1};
wire signed [32:0] signed_src2 = {signed_hi && src2[31], src2};
wire signed [65:0] full_result = signed_src1 * signed_src2;
wire [31:0] next_result = high_result ? full_result[63:32] :
                                         full_result[31:0];

always @(posedge clk) begin
    if (reset || cancel) begin
        busy   <= 1'b0;
        done   <= 1'b0;
        result <= 32'b0;
    end
    else if (start && !busy && !done) begin
        busy   <= 1'b1;
        done   <= 1'b0;
        result <= next_result;
    end
    else if (busy) begin
        busy <= 1'b0;
        done <= 1'b1;
    end
end

endmodule

module iter_divider(
    input             clk,
    input             reset,
    input             cancel,
    input             start,
    input             signed_div,
    input      [31:0] dividend,
    input      [31:0] divisor,
    output reg        busy,
    output reg        done,
    output reg [31:0] quotient,
    output reg [31:0] remainder
);

reg [31:0] dividend_abs;
reg [31:0] divisor_abs;
reg [31:0] dividend_shift;
reg [31:0] quotient_work;
reg [32:0] remainder_work;
reg [5:0]  count;
reg        quotient_neg;
reg        remainder_neg;

wire [32:0] remainder_shift = {remainder_work[31:0], dividend_shift[31]};
wire [32:0] divisor_ext     = {1'b0, divisor_abs};
wire        subtract_en     = remainder_shift >= divisor_ext;
wire [32:0] remainder_next  = subtract_en ? (remainder_shift - divisor_ext) :
                                            remainder_shift;
wire [31:0] quotient_next   = {quotient_work[30:0], subtract_en};

wire [31:0] dividend_abs_in = (signed_div && dividend[31]) ? (~dividend + 32'b1) : dividend;
wire [31:0] divisor_abs_in  = (signed_div && divisor[31])  ? (~divisor  + 32'b1) : divisor;

always @(posedge clk) begin
    if (reset || cancel) begin
        busy      <= 1'b0;
        done      <= 1'b0;
        quotient  <= 32'b0;
        remainder <= 32'b0;
    end
    else if (start && !busy && !done) begin
        if (divisor == 32'b0) begin
            busy      <= 1'b0;
            done      <= 1'b1;
            quotient  <= 32'hffffffff;
            remainder <= dividend;
        end
        else begin
            busy           <= 1'b1;
            done           <= 1'b0;
            dividend_abs   <= dividend_abs_in;
            divisor_abs    <= divisor_abs_in;
            dividend_shift <= dividend_abs_in;
            quotient_work  <= 32'b0;
            remainder_work <= 33'b0;
            count          <= 6'b0;
            quotient_neg   <= signed_div && (dividend[31] ^ divisor[31]);
            remainder_neg  <= signed_div && dividend[31];
        end
    end
    else if (busy) begin
        dividend_shift <= {dividend_shift[30:0], 1'b0};
        quotient_work  <= quotient_next;
        remainder_work <= remainder_next;

        if (count == 6'd31) begin
            busy <= 1'b0;
            done <= 1'b1;
            quotient  <= quotient_neg  ? (~quotient_next + 32'b1) : quotient_next;
            remainder <= remainder_neg ? (~remainder_next[31:0] + 32'b1) :
                                          remainder_next[31:0];
        end
        else begin
            count <= count + 6'b1;
        end
    end
end

endmodule
