`timescale 1ns/1ps
`default_nettype wire
`include "mycpu.vh"

module if1_stage(
    input                          clk            ,
    input                          reset          ,
    // valid/ready pipeline handshake
    input                          if1_to_if2_ready,
    // redirect interface
    input                          redirect_valid ,
    input  [31:0]                  redirect_pc    ,
    input  [ 1:0]                  redirect_cause ,
    // IDLE wait state
    input                          idle_wait      ,
    // address translation
    output [31:0]                  inst_vaddr     ,
    input  [31:0]                  inst_paddr     ,
    input                          inst_trans_ex  ,
    input  [ 5:0]                  inst_trans_ecode,
    input  [ 8:0]                  inst_trans_esubcode,
    output [`FETCH_EPOCH_WD-1:0]   current_epoch  ,
    // predictor lookup result for req_pc
    input                          pred_valid     ,
    input                          pred_taken     ,
    input  [31:0]                  pred_target    ,
    input  [ 2:0]                  pred_type      ,
    input  [15:0]                  pred_meta      ,
    //to if2
    output                         if1_to_if2_valid,
    output [`IF1_TO_IF2_BUS_WD -1:0] if1_to_if2_bus,
    // inst sram request interface
    output                         inst_sram_req  ,
    output                         inst_sram_wr   ,
    output [ 1:0]                  inst_sram_size ,
    output [ 3:0]                  inst_sram_wstrb,
    output [31:0]                  inst_sram_addr ,
    output [31:0]                  inst_sram_wdata,
    output [31:0]                  inst_sram_req_pc,
    output [`FETCH_EPOCH_WD-1:0]   inst_sram_req_epoch,
    input                          inst_sram_addr_ok
);

reg  [31:0] fetch_pc;
reg  [`FETCH_EPOCH_WD-1:0] fetch_epoch;
reg         if1_req;
reg  [31:0] req_pc;
reg  [`FETCH_EPOCH_WD-1:0] req_epoch;

reg         if1b_valid;
reg  [31:0] if1b_pc;
reg  [`FETCH_EPOCH_WD-1:0] if1b_epoch;
reg  [31:0] if1b_paddr;
reg         if1b_ex;
reg  [ 5:0] if1b_ecode;
reg  [ 8:0] if1b_esubcode;
reg  [31:0] if1b_pc_next;
reg         if1b_pred_valid;
reg         if1b_pred_taken;
reg  [31:0] if1b_pred_target;
reg  [ 2:0] if1b_pred_type;
reg  [15:0] if1b_pred_meta;

wire        fetch_adef;
wire        fetch_ex;
wire [ 5:0] fetch_ecode;
wire [ 8:0] fetch_esubcode;
wire        if1a_hs;
wire        if1_out_fire;
wire [31:0] predicted_next_pc;

assign fetch_adef     = if1_req && (req_pc[1:0] != 2'b00);
assign fetch_ex       = fetch_adef || (if1_req && inst_trans_ex);
assign fetch_ecode    = fetch_adef ? `ECODE_ADEF : inst_trans_ecode;
assign fetch_esubcode = fetch_adef ? 9'h000      : inst_trans_esubcode;

assign if1a_hs          = if1_req && (!if1b_valid || if1_out_fire) &&
                          !idle_wait;
assign if1_to_if2_valid = if1b_valid &&
                          (if1b_ex || (inst_sram_req && inst_sram_addr_ok));
assign if1_out_fire      = if1_to_if2_valid && if1_to_if2_ready;
assign if1_to_if2_bus   = {if1b_pc,
                           if1b_epoch,
                           if1b_ex,
                           if1b_ecode,
                           if1b_esubcode,
                           if1b_pc_next,
                           if1b_pred_valid,
                           if1b_pred_taken,
                           if1b_pred_target,
                           if1b_pred_type,
                           if1b_pred_meta};

assign inst_vaddr = if1_req ? req_pc : fetch_pc;

assign inst_sram_req   = if1b_valid && if1_to_if2_ready && !if1b_ex && !idle_wait;
assign inst_sram_wr    = 1'b0;
assign inst_sram_size  = 2'b10;
assign inst_sram_wstrb = 4'b0000;
assign inst_sram_addr  = if1b_paddr;
assign inst_sram_wdata = 32'b0;
assign inst_sram_req_pc = if1b_pc;
assign inst_sram_req_epoch = if1b_epoch;
assign current_epoch = fetch_epoch;
// A 64-bit response contains two instructions only when the request starts
// at the lower word of its aligned eight-byte block.  From an address ending
// in ...4, advancing by eight would skip the next sequential instruction.
wire [31:0] sequential_next_pc = req_pc + (req_pc[2] ? 32'd4 : 32'd8);
assign predicted_next_pc = (pred_valid && pred_taken) ? pred_target :
                                                       sequential_next_pc;

always @(posedge clk) begin
    if (reset) begin
        fetch_pc <= 32'h1c000000;
        fetch_epoch <= {`FETCH_EPOCH_WD{1'b0}};
    end
    else if (redirect_valid) begin
        fetch_pc <= redirect_pc;
        fetch_epoch <= fetch_epoch + 1'b1;
    end
    else if (if1a_hs) begin
        fetch_pc <= predicted_next_pc;
    end
end

always @(posedge clk) begin
    if (reset) begin
        if1_req            <= 1'b1;
        req_pc             <= 32'h1c000000;
        req_epoch          <= {`FETCH_EPOCH_WD{1'b0}};
    end
    else begin
        if (redirect_valid) begin
            if1_req    <= 1'b1;
            req_pc     <= redirect_pc;
            req_epoch  <= fetch_epoch + 1'b1;
        end
        else if (if1a_hs) begin
            if1_req    <= 1'b1;
            req_pc     <= predicted_next_pc;
            req_epoch  <= fetch_epoch;
        end
    end
end

always @(posedge clk) begin
    if (reset) begin
        if1b_valid    <= 1'b0;
        if1b_pc       <= 32'b0;
        if1b_epoch    <= {`FETCH_EPOCH_WD{1'b0}};
        if1b_paddr    <= 32'b0;
        if1b_ex       <= 1'b0;
        if1b_ecode    <= 6'b0;
        if1b_esubcode <= 9'b0;
        if1b_pc_next  <= 32'b0;
        if1b_pred_valid <= 1'b0;
        if1b_pred_taken <= 1'b0;
        if1b_pred_target <= 32'b0;
        if1b_pred_type <= `PRED_TYPE_NONE;
        if1b_pred_meta <= 16'b0;
    end
    else begin
        if (redirect_valid) begin
            if1b_valid <= 1'b0;
        end
        else if (if1a_hs) begin
            if1b_valid    <= 1'b1;
            if1b_pc       <= req_pc;
            if1b_epoch    <= req_epoch;
            if1b_paddr    <= inst_paddr;
            if1b_ex       <= fetch_ex;
            if1b_ecode    <= fetch_ecode;
            if1b_esubcode <= fetch_esubcode;
            if1b_pc_next  <= req_pc + 32'd4;
            if1b_pred_valid <= pred_valid;
            if1b_pred_taken <= pred_valid && pred_taken;
            if1b_pred_target <= pred_valid ? pred_target : (req_pc + 32'd4);
            if1b_pred_type <= pred_valid ? pred_type : `PRED_TYPE_NONE;
            // gshare metadata is meaningful even on a BTB miss: a newly
            // discovered conditional branch must train the lookup-time BHT
            // entry rather than an entry selected several stages later.
            if1b_pred_meta <= pred_meta;
        end
        else if (if1_out_fire) begin
            if1b_valid <= 1'b0;
        end
    end
end

wire unused_redirect_cause = |redirect_cause;

endmodule

module if2_stage_legacy(
    input                          clk            ,
    input                          reset          ,
    // valid/ready pipeline handshake
    input                          if2_to_queue_ready,
    output                         if1_to_if2_ready,
    // redirects squash current or pending responses
    input                          redirect       ,
    input  [`FETCH_EPOCH_WD-1:0]   current_epoch  ,
    //from if1
    input                          if1_to_if2_valid,
    input  [`IF1_TO_IF2_BUS_WD -1:0] if1_to_if2_bus,
    // to Fetch Queue
    output                         if2_to_queue_valid,
    output [`FS_TO_DS_BUS_WD -1:0] if2_to_queue_packet,
    // inst sram response interface
    input                          inst_sram_data_ok,
    input  [63:0]                  inst_sram_resp_data,
    input  [31:0]                  inst_sram_resp_pc,
    input  [ 1:0]                  inst_sram_resp_word_valid,
    input  [`FETCH_EPOCH_WD-1:0]   inst_sram_resp_epoch
);

reg         if2_valid;
reg  [31:0] if2_inst;
reg  [31:0] if2_pc;
reg  [`FETCH_EPOCH_WD-1:0] if2_epoch;
reg         if2_ex;
reg  [ 5:0] if2_ecode;
reg  [ 8:0] if2_esubcode;

reg         resp_pending;
wire [31:0] if1_pc;
wire [`FETCH_EPOCH_WD-1:0] if1_epoch;
wire        if1_ex;
wire [ 5:0] if1_ecode;
wire [ 8:0] if1_esubcode;
wire        if2_out_fire;
wire        if2_in_fire;
wire        inst_data_hs;

assign {if1_pc,
        if1_epoch,
        if1_ex,
        if1_ecode,
        if1_esubcode} = if1_to_if2_bus;

assign if2_to_queue_valid = if2_valid;
assign if2_to_queue_packet = {if2_inst,
                         if2_pc,
                         if2_epoch,
                         if2_ex,
                         if2_ecode,
                         if2_esubcode};

assign if2_out_fire = if2_to_queue_valid && if2_to_queue_ready;
assign if1_to_if2_ready = (!if2_valid || if2_out_fire) && !resp_pending;
assign if2_in_fire = if1_to_if2_valid && if1_to_if2_ready;
assign inst_data_hs = resp_pending && inst_sram_data_ok;

always @(posedge clk) begin
    if (reset) begin
        if2_valid <= 1'b0;
    end
    else begin
        if (if2_out_fire || redirect) begin
            if2_valid <= 1'b0;
        end

        if (if2_in_fire && if1_ex && (if1_epoch == current_epoch) && !redirect) begin
            if2_valid <= 1'b1;
        end

        if (inst_data_hs && inst_sram_resp_word_valid[0] &&
            (inst_sram_resp_epoch == current_epoch) && !redirect) begin
            if2_valid <= 1'b1;
        end
    end
end

always @(posedge clk) begin
    if (reset) begin
        if2_inst     <= 32'b0;
        if2_pc       <= 32'h1c000000;
        if2_epoch    <= {`FETCH_EPOCH_WD{1'b0}};
        if2_ex       <= 1'b0;
        if2_ecode    <= 6'b0;
        if2_esubcode <= 9'b0;
    end
    else begin
        if (if2_in_fire && if1_ex && (if1_epoch == current_epoch) && !redirect) begin
            if2_inst     <= 32'b0;
            if2_pc       <= if1_pc;
            if2_epoch    <= if1_epoch;
            if2_ex       <= if1_ex;
            if2_ecode    <= if1_ecode;
            if2_esubcode <= if1_esubcode;
        end

        if (inst_data_hs && inst_sram_resp_word_valid[0] &&
            (inst_sram_resp_epoch == current_epoch) && !redirect) begin
            if2_inst     <= inst_sram_resp_data[31:0];
            if2_pc       <= inst_sram_resp_pc;
            if2_epoch    <= inst_sram_resp_epoch;
            if2_ex       <= 1'b0;
            if2_ecode    <= 6'b0;
            if2_esubcode <= 9'b0;
        end
    end
end

always @(posedge clk) begin
    if (reset) begin
        resp_pending  <= 1'b0;
    end
    else begin
        if (if2_in_fire) begin
            resp_pending  <= !if1_ex;
        end

        if (inst_data_hs) begin
            resp_pending <= 1'b0;
        end
    end
end

`ifndef SYNTHESIS
reg                        if2_stalled_last;
reg [`FS_TO_DS_BUS_WD-1:0] if2_payload_last;
reg [`FETCH_EPOCH_WD:0]    redirects_while_pending;
always @(posedge clk) begin
    if (reset || inst_data_hs)
        redirects_while_pending <= {(`FETCH_EPOCH_WD+1){1'b0}};
    else if (if2_in_fire && !if1_ex)
        redirects_while_pending <= redirect ?
                                   {{`FETCH_EPOCH_WD{1'b0}}, 1'b1} :
                                   {(`FETCH_EPOCH_WD+1){1'b0}};
    else if (redirect && resp_pending)
        redirects_while_pending <= redirects_while_pending + 1'b1;

    if (!reset && redirect && resp_pending &&
        (&redirects_while_pending[`FETCH_EPOCH_WD-1:0]))
        $error("fetch epoch wrapped while an old ICache response was pending");

    if (reset || redirect) begin
        if2_stalled_last <= 1'b0;
    end
    else begin
        if (if2_stalled_last && (!if2_to_queue_valid ||
                                 if2_to_queue_packet !== if2_payload_last))
            $error("IF2 payload changed while stalled");
        if2_stalled_last <= if2_to_queue_valid && !if2_to_queue_ready;
        if2_payload_last <= if2_to_queue_packet;
    end
end
`endif

endmodule

// Pipelined IF2: request metadata and returned instructions are buffered
// independently.  Capacity is reserved when a request is accepted, so an
// ICache response never needs a ready signal and cannot overflow the queue.
module if2_stage(
    input                          clk,
    input                          reset,
    input                          if2_to_queue_ready,
    output                         if1_to_if2_ready,
    input                          redirect,
    input  [`FETCH_EPOCH_WD-1:0]   current_epoch,
    input                          if1_to_if2_valid,
    input  [`IF1_TO_IF2_BUS_WD-1:0] if1_to_if2_bus,
    output                         if2_to_queue_valid,
    output [`FS_TO_DS_BUS_WD-1:0]  if2_to_queue_packet,
    output                         if2_to_queue_slot1_valid,
    output [`FS_TO_DS_BUS_WD-1:0]  if2_to_queue_slot1_packet,
    input                          inst_sram_data_ok,
    input  [63:0]                  inst_sram_resp_data,
    input  [31:0]                  inst_sram_resp_pc,
    input  [ 1:0]                  inst_sram_resp_word_valid,
    input  [`FETCH_EPOCH_WD-1:0]   inst_sram_resp_epoch,
    output reg                     wrong_epoch_drop
);

localparam QUEUE_DEPTH = 4;
localparam PTR_W = 2;

reg [`IF1_TO_IF2_BUS_WD-1:0] meta_entries [0:QUEUE_DEPTH-1];
reg [`FETCH_PACKET_WD-1:0]   resp_entries [0:QUEUE_DEPTH-1];
reg [PTR_W-1:0] meta_rd_ptr, meta_wr_ptr;
reg [PTR_W-1:0] resp_rd_ptr, resp_wr_ptr;
reg [PTR_W:0] meta_count, resp_count;

wire [31:0] in_pc;
wire [`FETCH_EPOCH_WD-1:0] in_epoch;
wire in_ex;
wire [5:0] in_ecode;
wire [8:0] in_esubcode;
wire [31:0] in_pc_next;
wire in_pred_valid, in_pred_taken;
wire [31:0] in_pred_target;
wire [2:0] in_pred_type;
wire [15:0] in_pred_meta;
assign {in_pc, in_epoch, in_ex, in_ecode, in_esubcode,
        in_pc_next, in_pred_valid, in_pred_taken, in_pred_target,
        in_pred_type, in_pred_meta} = if1_to_if2_bus;

wire [31:0] head_pc;
wire [`FETCH_EPOCH_WD-1:0] head_epoch;
wire head_ex;
wire [5:0] head_ecode;
wire [8:0] head_esubcode;
wire [31:0] head_pc_next;
wire head_pred_valid, head_pred_taken;
wire [31:0] head_pred_target;
wire [2:0] head_pred_type;
wire [15:0] head_pred_meta;
assign {head_pc, head_epoch, head_ex, head_ecode, head_esubcode,
        head_pc_next, head_pred_valid, head_pred_taken, head_pred_target,
        head_pred_type, head_pred_meta} = meta_entries[meta_rd_ptr];

wire resp_out_fire = if2_to_queue_valid && if2_to_queue_ready;
wire response_arrives = inst_sram_data_ok && (meta_count != 0);
wire [3:0] reserved_count = meta_count + resp_count;
// Keep the input ready path independent of the response consumer.  Allowing a
// same-cycle pop to create capacity formed a combinational backpressure path
// from EX3 through the issue/fetch stages and into the ICache response RAM.
// Refusing that one full-and-pop cycle is conservative and breaks the path.
wire capacity_available = (reserved_count < QUEUE_DEPTH);
// A translation/fetch exception completes locally, while an older memory
// fetch may still be waiting for ICache.  Letting that exception enter the
// response FIFO would allow it to overtake the older instruction (notably at
// a page boundary).  Hold local exceptions until every older memory response
// has been consumed from the metadata queue.
assign if1_to_if2_ready = !redirect && capacity_available &&
                          !(in_ex && (meta_count != 0));

wire if2_in_fire = if1_to_if2_valid && if1_to_if2_ready;
wire memory_accept = if2_in_fire && !in_ex;
wire exception_accept = if2_in_fire && in_ex &&
                        (in_epoch == current_epoch);
wire response_current = response_arrives &&
                        inst_sram_resp_word_valid[0] &&
                        (inst_sram_resp_epoch == head_epoch) &&
                        (head_epoch == current_epoch) && !redirect;
wire resp_push = exception_accept || response_current;

wire [`FS_TO_DS_BUS_WD-1:0] exception_packet =
    {32'b0, in_pc, in_epoch, 1'b1, in_ecode, in_esubcode,
     in_pc_next, in_pred_valid, in_pred_taken, in_pred_target,
     in_pred_type, in_pred_meta};
wire [`FS_TO_DS_BUS_WD-1:0] memory_packet =
    {inst_sram_resp_data[31:0], head_pc, head_epoch, 1'b0, 6'b0, 9'b0,
     head_pc_next, head_pred_valid, head_pred_taken, head_pred_target,
     head_pred_type, head_pred_meta};

wire [`FS_TO_DS_BUS_WD-1:0] memory_packet1 =
    {inst_sram_resp_data[63:32], head_pc + 32'd4, head_epoch,
     1'b0, 6'b0, 9'b0, head_pc + 32'd8,
     1'b0, 1'b0, head_pc + 32'd8, `PRED_TYPE_NONE, 16'b0};
wire memory_slot1_valid = response_current &&
                          inst_sram_resp_word_valid[1] &&
                          !head_pc[2] &&
                          // A taken prediction for slot0 redirects the
                          // architectural stream before slot1.  Keeping the
                          // sequential word would let a correctly predicted
                          // branch's fall-through instruction retire because
                          // no later mispredict flush is generated.
                          !(head_pred_valid && head_pred_taken);
wire [`FETCH_PACKET_WD-1:0] exception_fetch_packet =
    {{`FS_TO_DS_BUS_WD{1'b0}}, exception_packet, 2'b01};
wire [`FETCH_PACKET_WD-1:0] memory_fetch_packet =
    {memory_packet1, memory_packet, memory_slot1_valid, 1'b1};

assign if2_to_queue_valid = (resp_count != 0) && !redirect;
assign if2_to_queue_packet =
    resp_entries[resp_rd_ptr][2 +: `FS_TO_DS_BUS_WD];
assign if2_to_queue_slot1_valid =
    if2_to_queue_valid && resp_entries[resp_rd_ptr][1];
assign if2_to_queue_slot1_packet =
    resp_entries[resp_rd_ptr][2+`FS_TO_DS_BUS_WD +: `FS_TO_DS_BUS_WD];

always @(posedge clk) begin
    if (reset) begin
        meta_rd_ptr <= 0;
        meta_wr_ptr <= 0;
        meta_count <= 0;
        resp_rd_ptr <= 0;
        resp_wr_ptr <= 0;
        resp_count <= 0;
        wrong_epoch_drop <= 1'b0;
    end
    else begin
        wrong_epoch_drop <= response_arrives &&
                            (!inst_sram_resp_word_valid[0] ||
                             inst_sram_resp_epoch != head_epoch ||
                             head_epoch != current_epoch || redirect);

        if (memory_accept) begin
            meta_entries[meta_wr_ptr] <= if1_to_if2_bus;
            meta_wr_ptr <= meta_wr_ptr + 1'b1;
        end
        if (response_arrives)
            meta_rd_ptr <= meta_rd_ptr + 1'b1;
        case ({memory_accept, response_arrives})
            2'b10: meta_count <= meta_count + 1'b1;
            2'b01: meta_count <= meta_count - 1'b1;
            default: meta_count <= meta_count;
        endcase

        if (redirect) begin
            resp_rd_ptr <= 0;
            resp_wr_ptr <= 0;
            resp_count <= 0;
        end
        else begin
            if (resp_push) begin
                resp_entries[resp_wr_ptr] <= exception_accept ?
                    exception_fetch_packet : memory_fetch_packet;
                resp_wr_ptr <= resp_wr_ptr + 1'b1;
            end
            if (resp_out_fire)
                resp_rd_ptr <= resp_rd_ptr + 1'b1;
            case ({resp_push, resp_out_fire})
                2'b10: resp_count <= resp_count + 1'b1;
                2'b01: resp_count <= resp_count - 1'b1;
                default: resp_count <= resp_count;
            endcase
        end
    end
end

`ifndef SYNTHESIS
reg stalled_last;
reg [`FS_TO_DS_BUS_WD-1:0] stalled_payload;
always @(posedge clk) begin
    if (!reset && reserved_count > QUEUE_DEPTH)
        $error("IF2 reserved response capacity overflow");
    if (!reset && inst_sram_data_ok && meta_count == 0)
        $error("ICache response has no accepted request metadata");
    if (!reset && response_arrives &&
        (inst_sram_resp_pc != head_pc || inst_sram_resp_epoch != head_epoch))
        $error("ICache response PC/epoch does not match accepted request");
    if (reset || redirect)
        stalled_last <= 1'b0;
    else begin
        if (stalled_last && (!if2_to_queue_valid ||
                             if2_to_queue_packet !== stalled_payload))
            $error("IF2 payload changed while stalled");
        stalled_last <= if2_to_queue_valid && !if2_to_queue_ready;
        stalled_payload <= if2_to_queue_packet;
    end
end
wire unused_head_exception = head_ex | (|head_ecode) | (|head_esubcode);
`endif

endmodule

module if_stage(
    input                          clk            ,
    input                          reset          ,
    // valid/ready pipeline handshake
    input                          fs_to_ds_ready ,
    // Registered, unified redirect packet
    input                          redirect_valid ,
    input  [`REDIRECT_PACKET_WD-1:0] redirect_packet,
    // IDLE wait state
    input                          idle_wait      ,
    // address translation
    output [31:0]                  inst_vaddr     ,
    input  [31:0]                  inst_paddr     ,
    input                          inst_trans_ex  ,
    input  [ 5:0]                  inst_trans_ecode,
    input  [ 8:0]                  inst_trans_esubcode,
    //to ds
    output                         fs_to_ds_valid ,
    output [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus   ,
    // inst sram interface
    output                         inst_sram_req  ,
    output                         inst_sram_wr   ,
    output [ 1:0]                  inst_sram_size ,
    output [ 3:0]                  inst_sram_wstrb,
    output [31:0]                  inst_sram_addr ,
    output [31:0]                  inst_sram_wdata,
    output [31:0]                  inst_sram_req_pc,
    output [`FETCH_EPOCH_WD-1:0]   inst_sram_req_epoch,
    input                          inst_sram_addr_ok,
    input                          inst_sram_data_ok,
    input  [63:0]                  inst_sram_resp_data,
    input  [31:0]                  inst_sram_resp_pc,
    input  [ 1:0]                  inst_sram_resp_word_valid,
    input  [`FETCH_EPOCH_WD-1:0]   inst_sram_resp_epoch
);

wire        if1_to_if2_ready;
wire        if1_to_if2_valid;
wire [`IF1_TO_IF2_BUS_WD -1:0] if1_to_if2_bus;
wire [`FETCH_EPOCH_WD-1:0] current_epoch;
wire [31:0] redirect_pc;
wire [ 1:0] redirect_cause;

assign redirect_pc = redirect_packet[`REDIRECT_TARGET_HI:`REDIRECT_TARGET_LO];
assign redirect_cause = redirect_packet[`REDIRECT_REASON_HI:`REDIRECT_REASON_LO];

if1_stage u_if1_stage(
    .clk                 (clk                 ),
    .reset               (reset               ),
    .if1_to_if2_ready    (if1_to_if2_ready    ),
    .redirect_valid      (redirect_valid      ),
    .redirect_pc         (redirect_pc         ),
    .redirect_cause      (redirect_cause      ),
    .idle_wait           (idle_wait           ),
    .inst_vaddr          (inst_vaddr          ),
    .inst_paddr          (inst_paddr          ),
    .inst_trans_ex       (inst_trans_ex       ),
    .inst_trans_ecode    (inst_trans_ecode    ),
    .inst_trans_esubcode (inst_trans_esubcode ),
    .current_epoch       (current_epoch       ),
    .pred_valid          (1'b1               ),
    .pred_taken          (1'b0               ),
    .pred_target         (inst_vaddr + 32'd4 ),
    .pred_type           (`PRED_TYPE_NONE     ),
    .pred_meta           (16'b0               ),
    .if1_to_if2_valid    (if1_to_if2_valid    ),
    .if1_to_if2_bus      (if1_to_if2_bus      ),
    .inst_sram_req       (inst_sram_req       ),
    .inst_sram_wr        (inst_sram_wr        ),
    .inst_sram_size      (inst_sram_size      ),
    .inst_sram_wstrb     (inst_sram_wstrb     ),
    .inst_sram_addr      (inst_sram_addr      ),
    .inst_sram_wdata     (inst_sram_wdata     ),
    .inst_sram_req_pc    (inst_sram_req_pc    ),
    .inst_sram_req_epoch (inst_sram_req_epoch ),
    .inst_sram_addr_ok   (inst_sram_addr_ok   )
);

if2_stage u_if2_stage(
    .clk                 (clk                 ),
    .reset               (reset               ),
    .if2_to_queue_ready  (fs_to_ds_ready      ),
    .if1_to_if2_ready    (if1_to_if2_ready    ),
    .redirect            (redirect_valid      ),
    .current_epoch       (current_epoch       ),
    .if1_to_if2_valid    (if1_to_if2_valid    ),
    .if1_to_if2_bus      (if1_to_if2_bus      ),
    .if2_to_queue_valid  (fs_to_ds_valid      ),
    .if2_to_queue_packet (fs_to_ds_bus        ),
    .inst_sram_data_ok   (inst_sram_data_ok   ),
    .inst_sram_resp_data (inst_sram_resp_data ),
    .inst_sram_resp_pc   (inst_sram_resp_pc   ),
    .inst_sram_resp_word_valid(inst_sram_resp_word_valid),
    .inst_sram_resp_epoch(inst_sram_resp_epoch),
    .wrong_epoch_drop    ()
);

endmodule
