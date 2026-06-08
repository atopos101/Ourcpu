module tlb #(
    parameter TLBNUM = 16
)(
    input  wire                         clk,

    // search port 0
    input  wire [18:0]                  s0_vppn,
    input  wire                         s0_va_bit12,
    input  wire [ 9:0]                  s0_asid,
    output reg                          s0_found,
    output reg  [$clog2(TLBNUM)-1:0]    s0_index,
    output reg  [19:0]                  s0_ppn,
    output reg  [ 5:0]                  s0_ps,
    output reg  [ 1:0]                  s0_plv,
    output reg  [ 1:0]                  s0_mat,
    output reg                          s0_d,
    output reg                          s0_v,

    // search port 1
    input  wire [18:0]                  s1_vppn,
    input  wire                         s1_va_bit12,
    input  wire [ 9:0]                  s1_asid,
    output reg                          s1_found,
    output reg  [$clog2(TLBNUM)-1:0]    s1_index,
    output reg  [19:0]                  s1_ppn,
    output reg  [ 5:0]                  s1_ps,
    output reg  [ 1:0]                  s1_plv,
    output reg  [ 1:0]                  s1_mat,
    output reg                          s1_d,
    output reg                          s1_v,

    // invalidate port; op 4/5/6 reuse search port 1 as ASID/VPPN source
    input  wire                         invtlb_valid,
    input  wire [ 4:0]                  invtlb_op,

    // write port
    input  wire                         we,
    input  wire [$clog2(TLBNUM)-1:0]    w_index,
    input  wire                         w_e,
    input  wire [18:0]                  w_vppn,
    input  wire [ 5:0]                  w_ps,
    input  wire [ 9:0]                  w_asid,
    input  wire                         w_g,
    input  wire [19:0]                  w_ppn0,
    input  wire [ 1:0]                  w_plv0,
    input  wire [ 1:0]                  w_mat0,
    input  wire                         w_d0,
    input  wire                         w_v0,
    input  wire [19:0]                  w_ppn1,
    input  wire [ 1:0]                  w_plv1,
    input  wire [ 1:0]                  w_mat1,
    input  wire                         w_d1,
    input  wire                         w_v1,

    // read port
    input  wire [$clog2(TLBNUM)-1:0]    r_index,
    output wire                         r_e,
    output wire [18:0]                  r_vppn,
    output wire [ 5:0]                  r_ps,
    output wire [ 9:0]                  r_asid,
    output wire                         r_g,
    output wire [19:0]                  r_ppn0,
    output wire [ 1:0]                  r_plv0,
    output wire [ 1:0]                  r_mat0,
    output wire                         r_d0,
    output wire                         r_v0,
    output wire [19:0]                  r_ppn1,
    output wire [ 1:0]                  r_plv1,
    output wire [ 1:0]                  r_mat1,
    output wire                         r_d1,
    output wire                         r_v1
);

reg        tlb_e    [TLBNUM-1:0];
reg [18:0] tlb_vppn [TLBNUM-1:0];
reg [ 5:0] tlb_ps   [TLBNUM-1:0];
reg [ 9:0] tlb_asid [TLBNUM-1:0];
reg        tlb_g    [TLBNUM-1:0];
reg [19:0] tlb_ppn0 [TLBNUM-1:0];
reg [ 1:0] tlb_plv0 [TLBNUM-1:0];
reg [ 1:0] tlb_mat0 [TLBNUM-1:0];
reg        tlb_d0   [TLBNUM-1:0];
reg        tlb_v0   [TLBNUM-1:0];
reg [19:0] tlb_ppn1 [TLBNUM-1:0];
reg [ 1:0] tlb_plv1 [TLBNUM-1:0];
reg [ 1:0] tlb_mat1 [TLBNUM-1:0];
reg        tlb_d1   [TLBNUM-1:0];
reg        tlb_v1   [TLBNUM-1:0];

integer init_i;
initial begin
    for (init_i = 0; init_i < TLBNUM; init_i = init_i + 1) begin
        tlb_e   [init_i] = 1'b0;
        tlb_vppn[init_i] = 19'b0;
        tlb_ps  [init_i] = 6'b0;
        tlb_asid[init_i] = 10'b0;
        tlb_g   [init_i] = 1'b0;
        tlb_ppn0[init_i] = 20'b0;
        tlb_plv0[init_i] = 2'b0;
        tlb_mat0[init_i] = 2'b0;
        tlb_d0  [init_i] = 1'b0;
        tlb_v0  [init_i] = 1'b0;
        tlb_ppn1[init_i] = 20'b0;
        tlb_plv1[init_i] = 2'b0;
        tlb_mat1[init_i] = 2'b0;
        tlb_d1  [init_i] = 1'b0;
        tlb_v1  [init_i] = 1'b0;
    end
end

function vppn_match;
    input [18:0] search_vppn;
    input [18:0] entry_vppn;
    input [ 5:0] entry_ps;
    begin
        case (entry_ps)
            6'd21:  vppn_match = (search_vppn[18:9] == entry_vppn[18:9]);
            6'd22:  vppn_match = (search_vppn[18:10] == entry_vppn[18:10]);
            default:vppn_match = (search_vppn        == entry_vppn);
        endcase
    end
endfunction

function odd_page;
    input [18:0] search_vppn;
    input        va_bit12;
    input [ 5:0] entry_ps;
    begin
        odd_page = (entry_ps == 6'd21) ? search_vppn[8] :
                   (entry_ps == 6'd22) ? search_vppn[9] : va_bit12;
    end
endfunction

function inv_match;
    input [ 4:0] op;
    input [18:0] inv_vppn;
    input [ 9:0] inv_asid;
    input        entry_g;
    input [ 9:0] entry_asid;
    input [18:0] entry_vppn;
    input [ 5:0] entry_ps;
    begin
        case (op)
            5'd0,
            5'd1: inv_match = 1'b1;
            5'd2: inv_match =  entry_g;
            5'd3: inv_match = ~entry_g;
            5'd4: inv_match = ~entry_g && (entry_asid == inv_asid);
            5'd5: inv_match = ~entry_g && (entry_asid == inv_asid)
                                && vppn_match(inv_vppn, entry_vppn, entry_ps);
            5'd6: inv_match = (entry_g || (entry_asid == inv_asid))
                                && vppn_match(inv_vppn, entry_vppn, entry_ps);
            default: inv_match = 1'b0;
        endcase
    end
endfunction

integer s0_i;
always @(*) begin
    s0_found = 1'b0;
    s0_index = 0;
    s0_ppn   = 20'b0;
    s0_ps    = 6'b0;
    s0_plv   = 2'b0;
    s0_mat   = 2'b0;
    s0_d     = 1'b0;
    s0_v     = 1'b0;

    for (s0_i = 0; s0_i < TLBNUM; s0_i = s0_i + 1) begin
        if (!s0_found && tlb_e[s0_i]
            && (tlb_g[s0_i] || (tlb_asid[s0_i] == s0_asid))
            && vppn_match(s0_vppn, tlb_vppn[s0_i], tlb_ps[s0_i])) begin
            s0_found = 1'b1;
            s0_index = s0_i;
            s0_ps    = tlb_ps[s0_i];
            if (odd_page(s0_vppn, s0_va_bit12, tlb_ps[s0_i])) begin
                s0_ppn = tlb_ppn1[s0_i];
                s0_plv = tlb_plv1[s0_i];
                s0_mat = tlb_mat1[s0_i];
                s0_d   = tlb_d1  [s0_i];
                s0_v   = tlb_v1  [s0_i];
            end
            else begin
                s0_ppn = tlb_ppn0[s0_i];
                s0_plv = tlb_plv0[s0_i];
                s0_mat = tlb_mat0[s0_i];
                s0_d   = tlb_d0  [s0_i];
                s0_v   = tlb_v0  [s0_i];
            end
        end
    end
end

integer s1_i;
always @(*) begin
    s1_found = 1'b0;
    s1_index = 0;
    s1_ppn   = 20'b0;
    s1_ps    = 6'b0;
    s1_plv   = 2'b0;
    s1_mat   = 2'b0;
    s1_d     = 1'b0;
    s1_v     = 1'b0;

    for (s1_i = 0; s1_i < TLBNUM; s1_i = s1_i + 1) begin
        if (!s1_found && tlb_e[s1_i]
            && (tlb_g[s1_i] || (tlb_asid[s1_i] == s1_asid))
            && vppn_match(s1_vppn, tlb_vppn[s1_i], tlb_ps[s1_i])) begin
            s1_found = 1'b1;
            s1_index = s1_i;
            s1_ps    = tlb_ps[s1_i];
            if (odd_page(s1_vppn, s1_va_bit12, tlb_ps[s1_i])) begin
                s1_ppn = tlb_ppn1[s1_i];
                s1_plv = tlb_plv1[s1_i];
                s1_mat = tlb_mat1[s1_i];
                s1_d   = tlb_d1  [s1_i];
                s1_v   = tlb_v1  [s1_i];
            end
            else begin
                s1_ppn = tlb_ppn0[s1_i];
                s1_plv = tlb_plv0[s1_i];
                s1_mat = tlb_mat0[s1_i];
                s1_d   = tlb_d0  [s1_i];
                s1_v   = tlb_v0  [s1_i];
            end
        end
    end
end

integer inv_i;
always @(posedge clk) begin
    if (we) begin
        tlb_e   [w_index] <= w_e;
        tlb_vppn[w_index] <= w_vppn;
        tlb_ps  [w_index] <= w_ps;
        tlb_asid[w_index] <= w_asid;
        tlb_g   [w_index] <= w_g;
        tlb_ppn0[w_index] <= w_ppn0;
        tlb_plv0[w_index] <= w_plv0;
        tlb_mat0[w_index] <= w_mat0;
        tlb_d0  [w_index] <= w_d0;
        tlb_v0  [w_index] <= w_v0;
        tlb_ppn1[w_index] <= w_ppn1;
        tlb_plv1[w_index] <= w_plv1;
        tlb_mat1[w_index] <= w_mat1;
        tlb_d1  [w_index] <= w_d1;
        tlb_v1  [w_index] <= w_v1;
    end
    else if (invtlb_valid) begin
        for (inv_i = 0; inv_i < TLBNUM; inv_i = inv_i + 1) begin
            if (inv_match(invtlb_op, s1_vppn, s1_asid,
                          tlb_g[inv_i], tlb_asid[inv_i],
                          tlb_vppn[inv_i], tlb_ps[inv_i])) begin
                tlb_e[inv_i] <= 1'b0;
            end
        end
    end
end

assign r_e    = tlb_e   [r_index];
assign r_vppn = tlb_vppn[r_index];
assign r_ps   = tlb_ps  [r_index];
assign r_asid = tlb_asid[r_index];
assign r_g    = tlb_g   [r_index];
assign r_ppn0 = tlb_ppn0[r_index];
assign r_plv0 = tlb_plv0[r_index];
assign r_mat0 = tlb_mat0[r_index];
assign r_d0   = tlb_d0  [r_index];
assign r_v0   = tlb_v0  [r_index];
assign r_ppn1 = tlb_ppn1[r_index];
assign r_plv1 = tlb_plv1[r_index];
assign r_mat1 = tlb_mat1[r_index];
assign r_d1   = tlb_d1  [r_index];
assign r_v1   = tlb_v1  [r_index];

endmodule
