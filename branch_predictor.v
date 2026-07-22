`timescale 1ns/1ps
`include "mycpu.vh"

// Commit-trained branch predictor for the single-fetch front end:
//   * 256-entry, two-way set-associative BTB (128 sets)
//   * 256-entry gshare BHT with two-bit saturating counters
//   * eight-bit committed global history
//   * 16-entry return-address stack
//
// The lookup is asynchronous so IF1 can select its next PC in the same
// cycle.  State changes only at architectural commit, which prevents
// squashed instructions and exception paths from corrupting predictor state.
module branch_predictor #(
    parameter BTB_SET_BITS = 7,
    parameter RAS_PTR_BITS = 4
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        lookup_valid,
    input  wire [31:0] lookup_pc,
    input  wire [`FETCH_EPOCH_WD-1:0] lookup_epoch,
    output wire        lookup_hit,
    output wire        lookup_taken,
    output wire [31:0] lookup_target,
    output wire [ 2:0] lookup_type,
    output wire [15:0] lookup_meta,
    output wire        lookup1_hit,
    output wire        lookup1_taken,
    output wire [31:0] lookup1_target,
    output wire [ 2:0] lookup1_type,
    output wire [15:0] lookup1_meta,

    input  wire        update_valid,
    input  wire [31:0] update_pc,
    input  wire        update_taken,
    input  wire [31:0] update_target,
    input  wire [ 2:0] update_type,
    input  wire [15:0] update_meta,
    input  wire        update_was_predicted,
    input  wire        update_mispredict,
    output reg  [63:0] update_count
);

localparam BTB_SETS = (1 << BTB_SET_BITS);
localparam BHT_BITS = 8;
localparam BHT_ENTRIES = (1 << BHT_BITS);
localparam BTB_TAG_BITS = 30 - BTB_SET_BITS;
localparam RAS_DEPTH = (1 << RAS_PTR_BITS);

reg                         btb_valid0  [0:BTB_SETS-1];
reg                         btb_valid1  [0:BTB_SETS-1];
reg [BTB_TAG_BITS-1:0]      btb_tag0    [0:BTB_SETS-1];
reg [BTB_TAG_BITS-1:0]      btb_tag1    [0:BTB_SETS-1];
reg [31:0]                  btb_target0 [0:BTB_SETS-1];
reg [31:0]                  btb_target1 [0:BTB_SETS-1];
reg [2:0]                   btb_type0   [0:BTB_SETS-1];
reg [2:0]                   btb_type1   [0:BTB_SETS-1];
// The LRU bit names the next replacement way when both ways are valid.
reg                         btb_lru     [0:BTB_SETS-1];
reg [1:0]                   bht         [0:BHT_ENTRIES-1];
reg                         bht_valid   [0:BHT_ENTRIES-1];
reg [BHT_BITS-1:0]          global_history;
reg [31:0]                  ras         [0:RAS_DEPTH-1];
reg [RAS_PTR_BITS-1:0]      ras_sp;
reg [RAS_PTR_BITS:0]        ras_count;

wire [BTB_SET_BITS-1:0] lookup_set =
    lookup_pc[BTB_SET_BITS+1:2];
wire [BTB_TAG_BITS-1:0] lookup_tag =
    lookup_pc[31:BTB_SET_BITS+2];
wire lookup_way0_hit = btb_valid0[lookup_set] &&
                       (btb_tag0[lookup_set] == lookup_tag);
wire lookup_way1_hit = btb_valid1[lookup_set] &&
                       (btb_tag1[lookup_set] == lookup_tag);
wire lookup_btb_hit = lookup_way0_hit || lookup_way1_hit;
wire [2:0] lookup_btb_type = lookup_way0_hit ?
                             btb_type0[lookup_set] :
                             btb_type1[lookup_set];
wire [31:0] lookup_btb_target = lookup_way0_hit ?
                                btb_target0[lookup_set] :
                                btb_target1[lookup_set];
wire [BHT_BITS-1:0] lookup_pc_index =
    lookup_pc[BHT_BITS+1:2];
wire [BHT_BITS-1:0] lookup_bht_index =
    lookup_pc_index ^ global_history;
wire lookup_conditional_taken = bht_valid[lookup_bht_index] &&
                                bht[lookup_bht_index][1];
wire lookup_is_conditional =
    lookup_btb_type == `PRED_TYPE_CONDITIONAL;
wire lookup_is_return = lookup_btb_type == `PRED_TYPE_RETURN;
wire ras_available = ras_count != 0;
wire [RAS_PTR_BITS-1:0] ras_top_index = ras_sp - 1'b1;

assign lookup_hit = lookup_valid && lookup_btb_hit;
assign lookup_taken = lookup_hit &&
                      (!lookup_is_conditional || lookup_conditional_taken);
assign lookup_target = (lookup_hit && lookup_is_return && ras_available) ?
                       ras[ras_top_index] :
                       lookup_btb_target;
assign lookup_type = lookup_hit ? lookup_btb_type : `PRED_TYPE_NONE;
// The metadata is a lookup-time snapshot.  The public packet reserves eight
// bits each for committed global history and the actual gshare table index.
assign lookup_meta = {global_history, lookup_bht_index};

// The upper word of a 64-bit fetch block needs an independent lookup.
// This is a second read view of the same small tables; it adds no predictor
// state, update port, or pipeline stage.
wire [31:0] lookup1_pc = lookup_pc + 32'd4;
wire [BTB_SET_BITS-1:0] lookup1_set =
    lookup1_pc[BTB_SET_BITS+1:2];
wire [BTB_TAG_BITS-1:0] lookup1_tag =
    lookup1_pc[31:BTB_SET_BITS+2];
wire lookup1_way0_hit = btb_valid0[lookup1_set] &&
                        (btb_tag0[lookup1_set] == lookup1_tag);
wire lookup1_way1_hit = btb_valid1[lookup1_set] &&
                        (btb_tag1[lookup1_set] == lookup1_tag);
wire lookup1_btb_hit = lookup1_way0_hit || lookup1_way1_hit;
wire [2:0] lookup1_btb_type = lookup1_way0_hit ?
                              btb_type0[lookup1_set] :
                              btb_type1[lookup1_set];
wire [31:0] lookup1_btb_target = lookup1_way0_hit ?
                                 btb_target0[lookup1_set] :
                                 btb_target1[lookup1_set];
wire [BHT_BITS-1:0] lookup1_bht_index =
    lookup1_pc[BHT_BITS+1:2] ^ global_history;
wire lookup1_conditional_taken = bht_valid[lookup1_bht_index] &&
                                 bht[lookup1_bht_index][1];
wire lookup1_is_conditional =
    lookup1_btb_type == `PRED_TYPE_CONDITIONAL;
wire lookup1_is_return = lookup1_btb_type == `PRED_TYPE_RETURN;
assign lookup1_hit = lookup_valid && lookup1_btb_hit;
assign lookup1_taken = lookup1_hit &&
                       (!lookup1_is_conditional ||
                        lookup1_conditional_taken);
assign lookup1_target = (lookup1_hit && lookup1_is_return && ras_available) ?
                        ras[ras_top_index] : lookup1_btb_target;
assign lookup1_type = lookup1_hit ? lookup1_btb_type : `PRED_TYPE_NONE;
assign lookup1_meta = {global_history, lookup1_bht_index};

wire [BTB_SET_BITS-1:0] update_set =
    update_pc[BTB_SET_BITS+1:2];
wire [BTB_TAG_BITS-1:0] update_tag =
    update_pc[31:BTB_SET_BITS+2];
wire update_way0_hit = btb_valid0[update_set] &&
                       (btb_tag0[update_set] == update_tag);
wire update_way1_hit = btb_valid1[update_set] &&
                       (btb_tag1[update_set] == update_tag);
wire update_is_invalidate = update_type == `PRED_TYPE_NONE;
wire update_is_conditional = update_type == `PRED_TYPE_CONDITIONAL;
wire update_is_call = update_type == `PRED_TYPE_CALL;
wire update_is_return = update_type == `PRED_TYPE_RETURN;
wire [BHT_BITS-1:0] update_bht_index =
    update_meta[BHT_BITS-1:0];

integer i;

always @(posedge clk) begin
    if (reset) begin
        update_count <= 64'b0;
        global_history <= {BHT_BITS{1'b0}};
        ras_sp <= {RAS_PTR_BITS{1'b0}};
        ras_count <= {(RAS_PTR_BITS+1){1'b0}};
        for (i = 0; i < BTB_SETS; i = i + 1) begin
            btb_valid0[i] = 1'b0;
            btb_valid1[i] = 1'b0;
            btb_lru[i] = 1'b0;
        end
        for (i = 0; i < BHT_ENTRIES; i = i + 1)
            bht_valid[i] = 1'b0;
    end
    else if (update_valid) begin
        update_count <= update_count + 64'd1;

        if (update_is_invalidate) begin
            if (update_way0_hit)
                btb_valid0[update_set] <= 1'b0;
            if (update_way1_hit)
                btb_valid1[update_set] <= 1'b0;
        end
        else if (update_way0_hit) begin
            btb_target0[update_set] <= update_target;
            btb_type0[update_set] <= update_type;
            btb_lru[update_set] <= 1'b1;
        end
        else if (update_way1_hit) begin
            btb_target1[update_set] <= update_target;
            btb_type1[update_set] <= update_type;
            btb_lru[update_set] <= 1'b0;
        end
        else if (!btb_valid0[update_set] ||
                 (btb_valid1[update_set] && !btb_lru[update_set])) begin
            btb_valid0[update_set] <= 1'b1;
            btb_tag0[update_set] <= update_tag;
            btb_target0[update_set] <= update_target;
            btb_type0[update_set] <= update_type;
            btb_lru[update_set] <= 1'b1;
        end
        else begin
            btb_valid1[update_set] <= 1'b1;
            btb_tag1[update_set] <= update_tag;
            btb_target1[update_set] <= update_target;
            btb_type1[update_set] <= update_type;
            btb_lru[update_set] <= 1'b0;
        end

        if (update_is_conditional) begin
            if (!bht_valid[update_bht_index]) begin
                bht_valid[update_bht_index] <= 1'b1;
                bht[update_bht_index] <= update_taken ? 2'b10 : 2'b01;
            end
            else if (update_taken && bht[update_bht_index] != 2'b11)
                bht[update_bht_index] <= bht[update_bht_index] + 1'b1;
            else if (!update_taken && bht[update_bht_index] != 2'b00)
                bht[update_bht_index] <= bht[update_bht_index] - 1'b1;
            global_history <= {global_history[BHT_BITS-2:0],
                               update_taken};
        end

        if (update_is_call) begin
            ras[ras_sp] <= update_pc + 32'd4;
            ras_sp <= ras_sp + 1'b1;
            if (ras_count != RAS_DEPTH)
                ras_count <= ras_count + 1'b1;
        end
        else if (update_is_return && ras_count != 0) begin
            ras_sp <= ras_sp - 1'b1;
            ras_count <= ras_count - 1'b1;
        end
    end
end

wire unused_predictor_inputs = update_mispredict ^ lookup_epoch[0] ^
                               update_meta[15] ^ update_was_predicted ^
                               update_pc[0];

endmodule

// A committed control-flow instruction trains the predictor.  A committed
// non-control instruction that was falsely predicted taken emits a NONE-type
// update, which future BTB implementations must interpret as invalidation.
module branch_commit_update(
    input  wire        commit_fire,
    input  wire        exception_pending,
    input  wire        ertn_pending,
    input  wire        is_control_flow,
    input  wire [31:0] pc,
    input  wire        actual_taken,
    input  wire [31:0] actual_target,
    input  wire [ 2:0] resolved_type,
    input  wire [15:0] pred_meta,
    input  wire        was_predicted,
    input  wire        mispredict,
    output wire        update_valid,
    output wire [31:0] update_pc,
    output wire        update_taken,
    output wire [31:0] update_target,
    output wire [ 2:0] update_type,
    output wire [15:0] update_meta,
    output wire        update_was_predicted,
    output wire        update_mispredict
);

wire false_btb_invalidate = !is_control_flow && was_predicted && mispredict;
assign update_valid = commit_fire &&
                      (is_control_flow || false_btb_invalidate) &&
                      !exception_pending && !ertn_pending;
assign update_pc = pc;
assign update_taken = actual_taken;
assign update_target = actual_target;
assign update_type = resolved_type;
assign update_meta = pred_meta;
assign update_was_predicted = was_predicted;
assign update_mispredict = mispredict;

endmodule
