`timescale 1ns / 1ps

module dcache (
    input  wire        clk,
    input  wire        resetn,

    input  wire        valid,
    input  wire        op,        // 1: write, 0: read
    input  wire [ 7:0] index,
    input  wire [19:0] tag,
    input  wire [ 3:0] offset,
    input  wire [ 3:0] wstrb,
    input  wire [31:0] wdata,

    output wire        addr_ok,
    output reg         data_ok,
    output reg  [31:0] rdata,

    input  wire        cacop_valid,
    input  wire [ 1:0] cacop_op,
    input  wire [ 7:0] cacop_index,
    input  wire        cacop_way,
    input  wire [19:0] cacop_tag,
    input  wire        cacop_clean_only,
    output reg         cacop_ok,
    output wire        idle,
    output reg         line_inv_valid,
    output reg  [27:0] line_inv_addr,

    output reg         rd_req,
    output wire [ 2:0] rd_type,
    output wire [31:0] rd_addr,
    input  wire        rd_rdy,
    input  wire        ret_valid,
    input  wire        ret_last,
    input  wire [31:0] ret_data,

    output reg         wr_req,
    output wire [ 2:0] wr_type,
    output wire [31:0] wr_addr,
    output wire [ 3:0] wr_wstrb,
    output wire [127:0] wr_data,
    input  wire        wr_rdy
);

localparam S_IDLE   = 3'd0;
localparam S_LOOKUP = 3'd1;
localparam S_MISS   = 3'd2;
localparam S_REFILL = 3'd3;
localparam S_CACOP  = 3'd4;
localparam S_CACOP_WB = 3'd5;

localparam REQ_READ_LINE = 3'b100;
localparam REQ_WRITE_LINE = 3'b100;

reg [2:0] state;

reg        req_op;
reg [ 7:0] req_index;
reg [19:0] req_tag;
reg [ 3:0] req_offset;
reg [ 3:0] req_wstrb;
reg [31:0] req_wdata;
reg [ 1:0] req_cacop_op;
reg        req_cacop_way;
reg        req_cacop_clean_only;

wire [1:0] req_bank;
assign req_bank = req_offset[3:2];

wire [20:0] tagv_rdata [0:1];
reg  [20:0] tagv_wdata [0:1];
reg         tagv_we    [0:1];
reg  [ 7:0] tagv_addr  [0:1];

wire [31:0] bank_rdata [0:1][0:3];
reg  [31:0] bank_wdata [0:1][0:3];
reg         bank_we    [0:1][0:3];
reg  [ 7:0] bank_addr  [0:1][0:3];

reg d_table [0:1][0:255];
reg lru     [0:255];          // value is the next victim when both ways are valid

wire        way0_v;
wire        way1_v;
wire [19:0] way0_tag;
wire [19:0] way1_tag;
wire        way0_hit;
wire        way1_hit;
wire        cache_hit;
wire        hit_way;

assign way0_v   = tagv_rdata[0][0];
assign way1_v   = tagv_rdata[1][0];
assign way0_tag = tagv_rdata[0][20:1];
assign way1_tag = tagv_rdata[1][20:1];
assign way0_hit = way0_v && (way0_tag == req_tag);
assign way1_hit = way1_v && (way1_tag == req_tag);
assign cache_hit = way0_hit || way1_hit;
assign hit_way = way1_hit;

wire        cacop_hit_mode;
wire        cacop_target_way;
wire        cacop_target_valid;
wire        cacop_target_dirty;
wire [19:0] cacop_target_tag;
wire [ 7:0] lookup_index;
assign cacop_hit_mode     = (req_cacop_op == 2'b10);
assign cacop_target_way   = cacop_hit_mode ? hit_way : req_cacop_way;
assign cacop_target_valid = cacop_hit_mode ? cache_hit :
                            (req_cacop_way ? way1_v : way0_v);
assign cacop_target_dirty = cacop_target_way ? d_table[1][req_index] :
                                                d_table[0][req_index];
assign cacop_target_tag   = cacop_target_way ? way1_tag : way0_tag;
assign lookup_index       = cacop_valid ? cacop_index : index;

reg        replace_way;
reg [19:0] replace_old_tag;
reg        replace_dirty;
reg [31:0] replace_word0;
reg [31:0] replace_word1;
reg [31:0] replace_word2;
reg [31:0] replace_word3;
reg        wr_issued;
reg        rd_issued;
reg [1:0]  refill_cnt;

wire [31:0] hit_word;
assign hit_word = hit_way ? bank_rdata[1][req_bank] : bank_rdata[0][req_bank];

wire victim_way = (!way0_v) ? 1'b0 :
                  (!way1_v) ? 1'b1 :
                              lru[req_index];
wire victim_valid = victim_way ? way1_v : way0_v;
wire [19:0] victim_tag = victim_way ? way1_tag : way0_tag;

function [31:0] merge_word;
    input [31:0] old_word;
    input [31:0] new_word;
    input [ 3:0] byte_en;
begin
    merge_word[ 7: 0] = byte_en[0] ? new_word[ 7: 0] : old_word[ 7: 0];
    merge_word[15: 8] = byte_en[1] ? new_word[15: 8] : old_word[15: 8];
    merge_word[23:16] = byte_en[2] ? new_word[23:16] : old_word[23:16];
    merge_word[31:24] = byte_en[3] ? new_word[31:24] : old_word[31:24];
end
endfunction

wire [31:0] refill_word;
assign refill_word = (req_op && (refill_cnt == req_bank)) ?
                     merge_word(ret_data, req_wdata, req_wstrb) : ret_data;

assign addr_ok = (state == S_IDLE) && valid && !cacop_valid;
assign idle = (state == S_IDLE) && !rd_req && !wr_req;

assign rd_type = REQ_READ_LINE;
assign rd_addr = {req_tag, req_index, 4'b0000};

assign wr_type  = REQ_WRITE_LINE;
assign wr_addr  = {replace_old_tag, req_index, 4'b0000};
assign wr_wstrb = 4'b1111;
assign wr_data  = {replace_word3, replace_word2, replace_word1, replace_word0};

integer i;
integer wi;
integer bi;

always @(*) begin
    for (wi = 0; wi < 2; wi = wi + 1) begin
        tagv_we[wi]    = 1'b0;
        tagv_wdata[wi] = {req_tag, 1'b1};
        tagv_addr[wi]  = (state == S_IDLE) ? lookup_index : req_index;
        for (bi = 0; bi < 4; bi = bi + 1) begin
            bank_we[wi][bi]    = 1'b0;
            bank_wdata[wi][bi] = 32'b0;
            bank_addr[wi][bi]  = (state == S_IDLE) ? lookup_index : req_index;
        end
    end

    if (state == S_LOOKUP && cache_hit && req_op) begin
        bank_we[hit_way][req_bank]    = 1'b1;
        bank_wdata[hit_way][req_bank] = merge_word(hit_word, req_wdata, req_wstrb);
    end

    if (state == S_REFILL && ret_valid) begin
        bank_we[replace_way][refill_cnt]    = 1'b1;
        bank_wdata[replace_way][refill_cnt] = refill_word;
        if (ret_last) begin
            tagv_we[replace_way]    = 1'b1;
            tagv_wdata[replace_way] = {req_tag, 1'b1};
        end
    end

    if (state == S_CACOP && cacop_target_valid && !req_cacop_clean_only) begin
        tagv_we[cacop_target_way]    = 1'b1;
        tagv_wdata[cacop_target_way] = 21'b0;
    end
end

always @(posedge clk) begin
    if (!resetn) begin
        state      <= S_IDLE;
        data_ok    <= 1'b0;
        rdata      <= 32'b0;
        rd_req     <= 1'b0;
        wr_req     <= 1'b0;
        wr_issued  <= 1'b0;
        rd_issued  <= 1'b0;
        refill_cnt <= 2'b00;
        cacop_ok   <= 1'b0;
        req_cacop_clean_only <= 1'b0;
        line_inv_valid <= 1'b0;
        line_inv_addr  <= 28'b0;
        for (i = 0; i < 256; i = i + 1) begin
            d_table[0][i] = 1'b0;
            d_table[1][i] = 1'b0;
            lru[i]        = 1'b0;
        end
    end
    else begin
        data_ok <= 1'b0;
        cacop_ok <= 1'b0;
        line_inv_valid <= 1'b0;

        case (state)
        S_IDLE: begin
            rd_req <= 1'b0;
            wr_req <= 1'b0;
            if (cacop_valid) begin
                req_index     <= cacop_index;
                req_tag       <= cacop_tag;
                req_cacop_op  <= cacop_op;
                req_cacop_way <= cacop_way;
                req_cacop_clean_only <= cacop_clean_only;
                state         <= S_CACOP;
            end
            else if (valid) begin
                req_op     <= op;
                req_index  <= index;
                req_tag    <= tag;
                req_offset <= offset;
                req_wstrb  <= wstrb;
                req_wdata  <= wdata;
                state      <= S_LOOKUP;
            end
        end

        S_LOOKUP: begin
            if (cache_hit) begin
                data_ok <= 1'b1;
                if (!req_op) begin
                    rdata <= hit_word;
                end
                else begin
                    d_table[hit_way][req_index] <= 1'b1;
                end
                lru[req_index] <= ~hit_way;
                state <= S_IDLE;
            end
            else begin
                replace_way <= victim_way;
                replace_old_tag <= victim_tag;
                replace_dirty <= (!way0_v) ? 1'b0 :
                                 (!way1_v) ? 1'b0 :
                                 (lru[req_index] ? d_table[1][req_index]
                                                 : d_table[0][req_index]);
                replace_word0 <= ((!way0_v) ? 1'b0 :
                                  (!way1_v) ? 1'b1 :
                                              lru[req_index]) ? bank_rdata[1][0] : bank_rdata[0][0];
                replace_word1 <= ((!way0_v) ? 1'b0 :
                                  (!way1_v) ? 1'b1 :
                                              lru[req_index]) ? bank_rdata[1][1] : bank_rdata[0][1];
                replace_word2 <= ((!way0_v) ? 1'b0 :
                                  (!way1_v) ? 1'b1 :
                                              lru[req_index]) ? bank_rdata[1][2] : bank_rdata[0][2];
                replace_word3 <= ((!way0_v) ? 1'b0 :
                                  (!way1_v) ? 1'b1 :
                                              lru[req_index]) ? bank_rdata[1][3] : bank_rdata[0][3];
                wr_issued  <= 1'b0;
                rd_issued  <= 1'b0;
                refill_cnt <= 2'b00;
                if (victim_valid) begin
                    line_inv_valid <= 1'b1;
                    line_inv_addr  <= {victim_tag, req_index};
                end
                state      <= S_MISS;
            end
        end

        S_MISS: begin
            if (replace_dirty && !wr_issued) begin
                if (!wr_req) begin
                    wr_req <= 1'b1;
                end
                else if (wr_rdy) begin
                    wr_req    <= 1'b0;
                    wr_issued <= 1'b1;
                end
            end
            else begin
                wr_req    <= 1'b0;
                wr_issued <= 1'b1;
            end

            if ((!replace_dirty || wr_issued) && !rd_issued) begin
                if (!rd_req) begin
                    rd_req <= 1'b1;
                end
                else if (rd_rdy) begin
                    rd_req    <= 1'b0;
                    rd_issued <= 1'b1;
                    state     <= S_REFILL;
                end
            end
            else begin
                rd_req <= 1'b0;
            end
        end

        S_REFILL: begin
            rd_req <= 1'b0;
            wr_req <= 1'b0;
            if (ret_valid) begin
                if (!req_op && (refill_cnt == req_bank)) begin
                    rdata   <= ret_data;
                    data_ok <= 1'b1;
                end

                if (ret_last) begin
                    if (req_op) begin
                        data_ok <= 1'b1;
                    end
                    d_table[replace_way][req_index] <= req_op;
                    lru[req_index] <= ~replace_way;
                    state <= S_IDLE;
                end
                refill_cnt <= refill_cnt + 2'b01;
            end
        end

        S_CACOP: begin
            rd_req <= 1'b0;
            wr_req <= 1'b0;
            if (cacop_target_valid) begin
                d_table[cacop_target_way][req_index] <= 1'b0;
                if (!req_cacop_clean_only) begin
                    line_inv_valid <= 1'b1;
                    line_inv_addr  <= {cacop_target_tag, req_index};
                end
            end
            if ((req_cacop_op != 2'b00) && cacop_target_valid && cacop_target_dirty) begin
                replace_way     <= cacop_target_way;
                replace_old_tag <= cacop_target_tag;
                replace_word0   <= cacop_target_way ? bank_rdata[1][0] : bank_rdata[0][0];
                replace_word1   <= cacop_target_way ? bank_rdata[1][1] : bank_rdata[0][1];
                replace_word2   <= cacop_target_way ? bank_rdata[1][2] : bank_rdata[0][2];
                replace_word3   <= cacop_target_way ? bank_rdata[1][3] : bank_rdata[0][3];
                state           <= S_CACOP_WB;
            end
            else begin
                cacop_ok <= 1'b1;
                state    <= S_IDLE;
            end
        end

        S_CACOP_WB: begin
            rd_req <= 1'b0;
            if (!wr_req) begin
                wr_req <= 1'b1;
            end
            else if (wr_rdy) begin
                wr_req   <= 1'b0;
                cacop_ok <= 1'b1;
                state    <= S_IDLE;
            end
        end

        default: begin
            state <= S_IDLE;
        end
        endcase
    end
end

genvar way;
genvar bank;
generate
    for (way = 0; way < 2; way = way + 1) begin : gen_tagv_ram
        ram_256x21 u_tagv_ram (
            .clka  (clk),
            .ena   (1'b1),
            .wea   (tagv_we[way]),
            .addra (tagv_addr[way]),
            .dina  (tagv_wdata[way]),
            .douta (tagv_rdata[way])
        );
    end
endgenerate

generate
    for (way = 0; way < 2; way = way + 1) begin : gen_way_banks
        for (bank = 0; bank < 4; bank = bank + 1) begin : gen_bank_rams
            ram_256x32 u_bank_ram (
                .clka  (clk),
                .ena   (1'b1),
                .wea   (bank_we[way][bank]),
                .addra (bank_addr[way][bank]),
                .dina  (bank_wdata[way][bank]),
                .douta (bank_rdata[way][bank])
            );
        end
    end
endgenerate

endmodule
