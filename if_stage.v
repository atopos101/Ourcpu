`include "mycpu.vh"

module if1_stage(
    input                          clk            ,
    input                          reset          ,
    //allowin
    input                          if2_allowin    ,
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
    input                          inst_sram_addr_ok
);

reg  [31:0] fetch_pc;
reg         if1_req;
reg  [31:0] req_pc;
reg         req_cancel;
reg         redirect_pending;
reg  [31:0] redirect_pending_pc;

wire        fetch_adef;
wire        fetch_ex;
wire [ 5:0] fetch_ecode;
wire [ 8:0] fetch_esubcode;
wire        inst_addr_hs;
wire        new_req_ready;
wire        redirect_blocked;

assign redirect_blocked = redirect_valid && if1_req && !inst_addr_hs;

assign fetch_adef     = if1_req && (req_pc[1:0] != 2'b00);
assign fetch_ex       = fetch_adef || (if1_req && inst_trans_ex);
assign fetch_ecode    = fetch_adef ? `ECODE_ADEF : inst_trans_ecode;
assign fetch_esubcode = fetch_adef ? 9'h000      : inst_trans_esubcode;

assign inst_addr_hs     = if2_allowin &&
                          (fetch_ex || (inst_sram_req && inst_sram_addr_ok));
assign if1_to_if2_valid = inst_addr_hs;
assign if1_to_if2_bus   = {req_pc,
                           req_cancel || redirect_valid,
                           fetch_ex,
                           fetch_ecode,
                           fetch_esubcode};

assign inst_vaddr = if1_req ? req_pc : fetch_pc;

assign inst_sram_req   = if1_req && if2_allowin && !fetch_ex && !idle_wait;
assign inst_sram_wr    = 1'b0;
assign inst_sram_size  = 2'b10;
assign inst_sram_wstrb = 4'b0000;
assign inst_sram_addr  = inst_paddr;
assign inst_sram_wdata = 32'b0;

assign new_req_ready = !if1_req && if2_allowin && !idle_wait;

always @(posedge clk) begin
    if (reset) begin
        fetch_pc <= 32'h1c000000;
    end
    else if (redirect_valid) begin
        fetch_pc <= redirect_pc;
    end
    else if (inst_addr_hs && req_cancel && redirect_pending) begin
        fetch_pc <= redirect_pending_pc;
    end
    else if (inst_addr_hs && !req_cancel) begin
        fetch_pc <= req_pc + 3'h4;
    end
end

always @(posedge clk) begin
    if (reset) begin
        if1_req            <= 1'b0;
        req_pc             <= 32'b0;
        req_cancel         <= 1'b0;
        redirect_pending   <= 1'b0;
        redirect_pending_pc<= 32'b0;
    end
    else begin
        if (inst_addr_hs) begin
            if1_req    <= 1'b0;
            req_cancel <= 1'b0;
        end

        if (redirect_blocked) begin
            req_cancel          <= 1'b1;
            redirect_pending    <= 1'b1;
            redirect_pending_pc <= redirect_pc;
        end
        else if (redirect_valid) begin
            redirect_pending <= 1'b0;
            if (new_req_ready || inst_addr_hs) begin
                if1_req    <= 1'b1;
                req_pc     <= redirect_pc;
                req_cancel <= 1'b0;
            end
        end
        else if (inst_addr_hs && req_cancel && redirect_pending) begin
            if1_req          <= 1'b1;
            req_pc           <= redirect_pending_pc;
            req_cancel       <= 1'b0;
            redirect_pending <= 1'b0;
        end
        else if (new_req_ready) begin
            if1_req    <= 1'b1;
            req_pc     <= fetch_pc;
            req_cancel <= 1'b0;
        end
    end
end

wire unused_redirect_cause = |redirect_cause;

endmodule

module if2_stage(
    input                          clk            ,
    input                          reset          ,
    //allowin
    input                          ds_allowin     ,
    output                         if2_allowin    ,
    // redirects squash current or pending responses
    input                          redirect       ,
    //from if1
    input                          if1_to_if2_valid,
    input  [`IF1_TO_IF2_BUS_WD -1:0] if1_to_if2_bus,
    //to ds
    output                         fs_to_ds_valid ,
    output [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus   ,
    // inst sram response interface
    input                          inst_sram_data_ok,
    input  [31:0]                  inst_sram_rdata
);

reg         if2_valid;
reg  [31:0] if2_inst;
reg  [31:0] if2_pc;
reg         if2_ex;
reg  [ 5:0] if2_ecode;
reg  [ 8:0] if2_esubcode;

reg         resp_pending;
reg  [31:0] resp_pc;
reg         resp_cancel;
reg         resp_ex;
reg  [ 5:0] resp_ecode;
reg  [ 8:0] resp_esubcode;

wire [31:0] if1_pc;
wire        if1_req_cancel;
wire        if1_ex;
wire [ 5:0] if1_ecode;
wire [ 8:0] if1_esubcode;
wire        if2_handoff;
wire        accept_if1;
wire        inst_data_hs;

assign {if1_pc,
        if1_req_cancel,
        if1_ex,
        if1_ecode,
        if1_esubcode} = if1_to_if2_bus;

assign fs_to_ds_valid = if2_valid;
assign fs_to_ds_bus   = {if2_inst,
                         if2_pc,
                         if2_ex,
                         if2_ecode,
                         if2_esubcode};

assign if2_handoff = fs_to_ds_valid && ds_allowin;
assign if2_allowin = (!if2_valid || if2_handoff) && !resp_pending;
assign accept_if1  = if1_to_if2_valid && if2_allowin;
assign inst_data_hs = resp_pending && inst_sram_data_ok;

always @(posedge clk) begin
    if (reset) begin
        if2_valid <= 1'b0;
    end
    else begin
        if (if2_handoff || redirect) begin
            if2_valid <= 1'b0;
        end

        if (accept_if1 && if1_ex && !if1_req_cancel && !redirect) begin
            if2_valid <= 1'b1;
        end

        if (inst_data_hs && !resp_cancel && !redirect) begin
            if2_valid <= 1'b1;
        end
    end
end

always @(posedge clk) begin
    if (reset) begin
        if2_inst     <= 32'b0;
        if2_pc       <= 32'h1c000000;
        if2_ex       <= 1'b0;
        if2_ecode    <= 6'b0;
        if2_esubcode <= 9'b0;
    end
    else begin
        if (accept_if1 && if1_ex && !if1_req_cancel && !redirect) begin
            if2_inst     <= 32'b0;
            if2_pc       <= if1_pc;
            if2_ex       <= if1_ex;
            if2_ecode    <= if1_ecode;
            if2_esubcode <= if1_esubcode;
        end

        if (inst_data_hs && !resp_cancel && !redirect) begin
            if2_inst     <= inst_sram_rdata;
            if2_pc       <= resp_pc;
            if2_ex       <= resp_ex;
            if2_ecode    <= resp_ecode;
            if2_esubcode <= resp_esubcode;
        end
    end
end

always @(posedge clk) begin
    if (reset) begin
        resp_pending  <= 1'b0;
        resp_pc       <= 32'b0;
        resp_cancel   <= 1'b0;
        resp_ex       <= 1'b0;
        resp_ecode    <= 6'b0;
        resp_esubcode <= 9'b0;
    end
    else begin
        if (accept_if1) begin
            resp_pending  <= !if1_ex;
            resp_pc       <= if1_pc;
            resp_cancel   <= if1_req_cancel || redirect;
            resp_ex       <= if1_ex;
            resp_ecode    <= if1_ecode;
            resp_esubcode <= if1_esubcode;
        end

        if (inst_data_hs) begin
            resp_pending <= 1'b0;
            resp_cancel  <= 1'b0;
        end

        if (redirect) begin
            resp_cancel <= resp_pending || (accept_if1 && !if1_ex);
        end
    end
end

endmodule

module if_stage(
    input                          clk            ,
    input                          reset          ,
    //allowin
    input                          ds_allowin     ,
    //brbus
    input  [`BR_BUS_WD       -1:0] br_bus         ,
    // exception interface
    input                          flush          ,
    input  [31:0]                  ex_entry       ,
    // ertn interface
    input                          ertn_flush     ,
    input  [31:0]                  ertn_pc        ,
    // IBAR completion redirect
    input                          ibar_flush     ,
    input  [31:0]                  ibar_target    ,
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
    input                          inst_sram_addr_ok,
    input                          inst_sram_data_ok,
    input  [31:0]                  inst_sram_rdata
);

wire        if2_allowin;
wire        if1_to_if2_valid;
wire [`IF1_TO_IF2_BUS_WD -1:0] if1_to_if2_bus;
wire        br_stall;
wire        br_taken;
wire [31:0] br_target;
wire        redirect_valid;
wire [31:0] redirect_pc;
wire [ 1:0] redirect_cause;

assign {br_stall, br_taken, br_target} = br_bus;
assign redirect_valid = ertn_flush || flush || ibar_flush || br_taken;
assign redirect_pc    = ertn_flush ? ertn_pc     :
                        flush      ? ex_entry    :
                        ibar_flush ? ibar_target :
                                     br_target;
assign redirect_cause = ertn_flush ? `REDIRECT_CAUSE_ERTN :
                        flush      ? `REDIRECT_CAUSE_EXCP :
                        ibar_flush ? `REDIRECT_CAUSE_IBAR :
                                     `REDIRECT_CAUSE_BRANCH;

if1_stage u_if1_stage(
    .clk                 (clk                 ),
    .reset               (reset               ),
    .if2_allowin         (if2_allowin         ),
    .redirect_valid      (redirect_valid      ),
    .redirect_pc         (redirect_pc         ),
    .redirect_cause      (redirect_cause      ),
    .idle_wait           (idle_wait           ),
    .inst_vaddr          (inst_vaddr          ),
    .inst_paddr          (inst_paddr          ),
    .inst_trans_ex       (inst_trans_ex       ),
    .inst_trans_ecode    (inst_trans_ecode    ),
    .inst_trans_esubcode (inst_trans_esubcode ),
    .if1_to_if2_valid    (if1_to_if2_valid    ),
    .if1_to_if2_bus      (if1_to_if2_bus      ),
    .inst_sram_req       (inst_sram_req       ),
    .inst_sram_wr        (inst_sram_wr        ),
    .inst_sram_size      (inst_sram_size      ),
    .inst_sram_wstrb     (inst_sram_wstrb     ),
    .inst_sram_addr      (inst_sram_addr      ),
    .inst_sram_wdata     (inst_sram_wdata     ),
    .inst_sram_addr_ok   (inst_sram_addr_ok   )
);

if2_stage u_if2_stage(
    .clk                 (clk                 ),
    .reset               (reset               ),
    .ds_allowin          (ds_allowin          ),
    .if2_allowin         (if2_allowin         ),
    .redirect            (redirect_valid      ),
    .if1_to_if2_valid    (if1_to_if2_valid    ),
    .if1_to_if2_bus      (if1_to_if2_bus      ),
    .fs_to_ds_valid      (fs_to_ds_valid      ),
    .fs_to_ds_bus        (fs_to_ds_bus        ),
    .inst_sram_data_ok   (inst_sram_data_ok   ),
    .inst_sram_rdata     (inst_sram_rdata     )
);

endmodule
