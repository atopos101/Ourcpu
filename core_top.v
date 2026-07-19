`include "mycpu.vh"

module core_top #(
    parameter integer ENABLE_BP = 1
)(
    input           aclk,
    input           aresetn,
    input    [ 7:0] intrpt, 
    //AXI interface 
    //read reqest
    output   [ 3:0] arid,
    output   [31:0] araddr,
    output   [ 7:0] arlen,
    output   [ 2:0] arsize,
    output   [ 1:0] arburst,
    output   [ 1:0] arlock,
    output   [ 3:0] arcache,
    output   [ 2:0] arprot,
    output          arvalid,
    input           arready,
    //read back
    input    [ 3:0] rid,
    input    [31:0] rdata,
    input    [ 1:0] rresp,
    input           rlast,
    input           rvalid,
    output          rready,
    //write request
    output   [ 3:0] awid,
    output   [31:0] awaddr,
    output   [ 7:0] awlen,
    output   [ 2:0] awsize,
    output   [ 1:0] awburst,
    output   [ 1:0] awlock,
    output   [ 3:0] awcache,
    output   [ 2:0] awprot,
    output          awvalid,
    input           awready,
    //write data
    output   [ 3:0] wid,
    output   [31:0] wdata,
    output   [ 3:0] wstrb,
    output          wlast,
    output          wvalid,
    input           wready,
    //write back
    input    [ 3:0] bid,
    input    [ 1:0] bresp,
    input           bvalid,
    output          bready,

    //debug
    input           break_point,
    input           infor_flag,
    input  [ 4:0]   reg_num,
    output          ws_valid,
    output [31:0]   rf_rdata,

    //debug info
    output [31:0] debug0_wb_pc,
    output [ 3:0] debug0_wb_rf_wen,
    output [ 4:0] debug0_wb_rf_wnum,
    output [31:0] debug0_wb_rf_wdata
`ifdef CPU_2CMT
    ,
    output [31:0] debug1_wb_pc,
    output [ 3:0] debug1_wb_rf_wen,
    output [ 4:0] debug1_wb_rf_wnum,
    output [31:0] debug1_wb_rf_wdata
`endif
);

wire        core_inst_req;
wire        core_inst_wr;
wire [ 1:0] core_inst_size;
wire [ 3:0] core_inst_wstrb;
wire [31:0] core_inst_addr;
wire [31:0] core_inst_wdata;
wire [31:0] core_inst_req_pc;
wire [`FETCH_EPOCH_WD-1:0] core_inst_req_epoch;
wire        core_inst_addr_ok;
wire        core_inst_data_ok;
wire [63:0] core_inst_resp_data;
wire [31:0] core_inst_resp_pc;
wire [ 1:0] core_inst_resp_word_valid;
wire [`FETCH_EPOCH_WD-1:0] core_inst_resp_epoch;

wire        icache_rd_req;
wire [ 2:0] icache_rd_type;
wire [31:0] icache_rd_addr;
wire        icache_rd_rdy;
wire        icache_ret_valid;
wire        icache_ret_last;
wire [31:0] icache_ret_data;

wire        core_data_req;
wire        core_data_wr;
wire [ 1:0] core_data_size;
wire [ 3:0] core_data_wstrb;
wire [31:0] core_data_addr;
wire [31:0] core_data_wdata;
wire        core_data_uncached;
wire        core_data_addr_ok;
wire        core_data_data_ok;
wire [31:0] core_data_rdata;

wire        core_cacop_valid;
wire        core_cacop_is_dcache;
wire [ 1:0] core_cacop_op;
wire [ 7:0] core_cacop_index;
wire        core_cacop_way;
wire [19:0] core_cacop_tag;
wire        core_cacop_ok;
wire        icache_cacop_ok;
wire        dcache_cacop_ok;
wire        icache_idle;
wire        dcache_idle;
wire        icache_miss_event;
wire        dcache_miss_event;

wire        core_barrier_req;
wire        core_barrier_is_ibar;
wire        core_barrier_done;
wire        barrier_busy;
wire        barrier_dcache_valid;
wire [ 7:0] barrier_dcache_index;
wire        barrier_dcache_way;
wire        barrier_icache_valid;
wire [ 7:0] barrier_icache_index;
wire        barrier_icache_way;
wire        bridge_data_busy;

wire        dcache_addr_ok;
wire        dcache_data_ok;
wire [31:0] dcache_rdata;
wire        dcache_rd_req;
wire [ 2:0] dcache_rd_type;
wire [31:0] dcache_rd_addr;
wire        dcache_rd_rdy;
wire        dcache_ret_valid;
wire        dcache_ret_last;
wire [31:0] dcache_ret_data;
wire        dcache_wr_req;
wire [ 2:0] dcache_wr_type;
wire [31:0] dcache_wr_addr;
wire [ 3:0] dcache_wr_wstrb;
wire [127:0] dcache_wr_data;
wire        dcache_wr_rdy;
wire        dcache_line_inv_valid;
wire [27:0] dcache_line_inv_addr;

wire        uncache_req;
wire        uncache_wr;
wire [ 1:0] uncache_size;
wire [ 3:0] uncache_wstrb;
wire [31:0] uncache_addr;
wire [31:0] uncache_wdata;
wire        uncache_addr_ok;
wire        uncache_data_ok;
wire [31:0] uncache_rdata;

mycpu_core #(
    .ENABLE_BP(ENABLE_BP)
) u_core(
    .clk                (aclk                ),
    .resetn             (aresetn             ),
    .hw_int_in          (intrpt              ),
    .icache_miss_event  (icache_miss_event   ),
    .dcache_miss_event  (dcache_miss_event   ),
    .inst_sram_req      (core_inst_req       ),
    .inst_sram_wr       (core_inst_wr        ),
    .inst_sram_size     (core_inst_size      ),
    .inst_sram_wstrb    (core_inst_wstrb     ),
    .inst_sram_addr     (core_inst_addr      ),
    .inst_sram_wdata    (core_inst_wdata     ),
    .inst_sram_req_pc   (core_inst_req_pc    ),
    .inst_sram_req_epoch(core_inst_req_epoch ),
    .inst_sram_addr_ok  (core_inst_addr_ok   ),
    .inst_sram_data_ok  (core_inst_data_ok   ),
    .inst_sram_resp_data(core_inst_resp_data ),
    .inst_sram_resp_pc  (core_inst_resp_pc   ),
    .inst_sram_resp_word_valid(core_inst_resp_word_valid),
    .inst_sram_resp_epoch(core_inst_resp_epoch),
    .data_sram_req      (core_data_req       ),
    .data_sram_wr       (core_data_wr        ),
    .data_sram_size     (core_data_size      ),
    .data_sram_wstrb    (core_data_wstrb     ),
    .data_sram_addr     (core_data_addr      ),
    .data_sram_wdata    (core_data_wdata     ),
    .data_sram_uncached (core_data_uncached  ),
    .data_sram_addr_ok  (core_data_addr_ok   ),
    .data_sram_data_ok  (core_data_data_ok   ),
    .data_sram_rdata    (core_data_rdata     ),
    .cacop_valid        (core_cacop_valid    ),
    .cacop_is_dcache    (core_cacop_is_dcache),
    .cacop_op           (core_cacop_op       ),
    .cacop_index        (core_cacop_index    ),
    .cacop_way          (core_cacop_way      ),
    .cacop_tag          (core_cacop_tag      ),
    .cacop_ok           (core_cacop_ok       ),
    .barrier_req        (core_barrier_req    ),
    .barrier_is_ibar    (core_barrier_is_ibar),
    .barrier_done       (core_barrier_done   ),
    .dcache_inv_valid   (dcache_line_inv_valid),
    .dcache_inv_line    (dcache_line_inv_addr),
    .debug_wb_pc        (debug0_wb_pc        ),
    .debug_wb_rf_we     (debug0_wb_rf_wen    ),
    .debug_wb_rf_wnum   (debug0_wb_rf_wnum   ),
    .debug_wb_rf_wdata  (debug0_wb_rf_wdata  )
);

assign ws_valid = u_core.wb_stage.ws_valid;
assign rf_rdata = (reg_num == 5'b0) ? 32'b0
                                    : u_core.id_stage.u_regfile.rf[reg_num];
`ifdef CPU_2CMT
assign debug1_wb_pc       = u_core.lane1_wb_pc;
assign debug1_wb_rf_wen   = {4{u_core.lane1_wb_rf_we}};
assign debug1_wb_rf_wnum  = u_core.lane1_wb_rf_waddr;
assign debug1_wb_rf_wdata = u_core.lane1_wb_rf_wdata;
`endif

assign core_data_addr_ok = core_data_uncached ? uncache_addr_ok : dcache_addr_ok;
assign core_data_data_ok = uncache_data_ok || dcache_data_ok;
assign core_data_rdata   = uncache_data_ok ? uncache_rdata : dcache_rdata;
assign core_cacop_ok     = core_cacop_valid ?
                           (core_cacop_is_dcache ? dcache_cacop_ok : icache_cacop_ok) :
                           1'b0;

assign uncache_req   = core_data_req && core_data_uncached && !barrier_busy;
assign uncache_wr    = core_data_wr;
assign uncache_size  = core_data_size;
assign uncache_wstrb = core_data_wstrb;
assign uncache_addr  = core_data_addr;
assign uncache_wdata = core_data_wdata;

barrier_ctrl u_barrier_ctrl(
    .clk                  (aclk                  ),
    .reset                (!aresetn              ),
    .barrier_req          (core_barrier_req      ),
    .barrier_is_ibar      (core_barrier_is_ibar  ),
    .barrier_done         (core_barrier_done     ),
    .barrier_busy         (barrier_busy          ),
    .data_side_idle       (dcache_idle && !bridge_data_busy && !uncache_req),
    .icache_idle          (icache_idle           ),
    .dcache_maint_valid   (barrier_dcache_valid  ),
    .dcache_maint_index   (barrier_dcache_index  ),
    .dcache_maint_way     (barrier_dcache_way    ),
    .dcache_maint_ok      (dcache_cacop_ok       ),
    .icache_maint_valid   (barrier_icache_valid  ),
    .icache_maint_index   (barrier_icache_index  ),
    .icache_maint_way     (barrier_icache_way    ),
    .icache_maint_ok      (icache_cacop_ok       )
);

icache u_icache(
    .clk                (aclk                ),
    .resetn             (aresetn             ),
    .valid              (core_inst_req && !barrier_busy),
    .op                 (1'b0                ),
    .index              (core_inst_addr[11:4]),
    .tag                (core_inst_addr[31:12]),
    .offset             (core_inst_addr[3:0] ),
    .wstrb              (4'b0                ),
    .wdata              (32'b0               ),
    .req_pc             (core_inst_req_pc    ),
    .req_epoch          (core_inst_req_epoch ),
    .addr_ok            (core_inst_addr_ok   ),
    .data_ok            (core_inst_data_ok   ),
    .resp_data          (core_inst_resp_data ),
    .resp_pc            (core_inst_resp_pc   ),
    .resp_word_valid    (core_inst_resp_word_valid),
    .resp_epoch         (core_inst_resp_epoch),
    .cacop_valid        (barrier_icache_valid ||
                         (core_cacop_valid && !core_cacop_is_dcache)),
    .cacop_op           (barrier_icache_valid ? 2'b00 : core_cacop_op),
    .cacop_index        (barrier_icache_valid ? barrier_icache_index : core_cacop_index),
    .cacop_way          (barrier_icache_valid ? barrier_icache_way : core_cacop_way),
    .cacop_tag          (barrier_icache_valid ? 20'b0 : core_cacop_tag),
    .cacop_ok           (icache_cacop_ok     ),
    .idle               (icache_idle         ),
    .miss_event         (icache_miss_event   ),
    .rd_req             (icache_rd_req       ),
    .rd_type            (icache_rd_type      ),
    .rd_addr            (icache_rd_addr      ),
    .rd_rdy             (icache_rd_rdy       ),
    .ret_valid          (icache_ret_valid    ),
    .ret_last           (icache_ret_last     ),
    .ret_data           (icache_ret_data     ),
    .wr_req             (                    ),
    .wr_type            (                    ),
    .wr_addr            (                    ),
    .wr_wstrb           (                    ),
    .wr_data            (                    ),
    .wr_rdy             (1'b0                )
);

dcache u_dcache(
    .clk                (aclk                ),
    .resetn             (aresetn             ),
    .valid              (core_data_req && !core_data_uncached && !barrier_busy),
    .op                 (core_data_wr        ),
    .index              (core_data_addr[11:4]),
    .tag                (core_data_addr[31:12]),
    .offset             (core_data_addr[3:0] ),
    .wstrb              (core_data_wstrb     ),
    .wdata              (core_data_wdata     ),
    .addr_ok            (dcache_addr_ok      ),
    .data_ok            (dcache_data_ok      ),
    .rdata              (dcache_rdata        ),
    .cacop_valid        (barrier_dcache_valid ||
                         (core_cacop_valid && core_cacop_is_dcache)),
    .cacop_op           (barrier_dcache_valid ? 2'b01 : core_cacop_op),
    .cacop_index        (barrier_dcache_valid ? barrier_dcache_index : core_cacop_index),
    .cacop_way          (barrier_dcache_valid ? barrier_dcache_way : core_cacop_way),
    .cacop_tag          (barrier_dcache_valid ? 20'b0 : core_cacop_tag),
    .cacop_clean_only   (barrier_dcache_valid),
    .cacop_ok           (dcache_cacop_ok     ),
    .idle               (dcache_idle         ),
    .miss_event         (dcache_miss_event   ),
    .line_inv_valid     (dcache_line_inv_valid),
    .line_inv_addr      (dcache_line_inv_addr),
    .rd_req             (dcache_rd_req       ),
    .rd_type            (dcache_rd_type      ),
    .rd_addr            (dcache_rd_addr      ),
    .rd_rdy             (dcache_rd_rdy       ),
    .ret_valid          (dcache_ret_valid    ),
    .ret_last           (dcache_ret_last     ),
    .ret_data           (dcache_ret_data     ),
    .wr_req             (dcache_wr_req       ),
    .wr_type            (dcache_wr_type      ),
    .wr_addr            (dcache_wr_addr      ),
    .wr_wstrb           (dcache_wr_wstrb     ),
    .wr_data            (dcache_wr_data      ),
    .wr_rdy             (dcache_wr_rdy       )
);

sram_axi_bridge_2x1 u_sram_axi_bridge(
    .clk                (aclk                ),
    .resetn             (aresetn             ),
    .icache_rd_req      (icache_rd_req       ),
    .icache_rd_type     (icache_rd_type      ),
    .icache_rd_addr     (icache_rd_addr      ),
    .icache_rd_rdy      (icache_rd_rdy       ),
    .icache_ret_valid   (icache_ret_valid    ),
    .icache_ret_last    (icache_ret_last     ),
    .icache_ret_data    (icache_ret_data     ),
    .dcache_rd_req      (dcache_rd_req       ),
    .dcache_rd_type     (dcache_rd_type      ),
    .dcache_rd_addr     (dcache_rd_addr      ),
    .dcache_rd_rdy      (dcache_rd_rdy       ),
    .dcache_ret_valid   (dcache_ret_valid    ),
    .dcache_ret_last    (dcache_ret_last     ),
    .dcache_ret_data    (dcache_ret_data     ),
    .dcache_wr_req      (dcache_wr_req       ),
    .dcache_wr_type     (dcache_wr_type      ),
    .dcache_wr_addr     (dcache_wr_addr      ),
    .dcache_wr_wstrb    (dcache_wr_wstrb     ),
    .dcache_wr_data     (dcache_wr_data      ),
    .dcache_wr_rdy      (dcache_wr_rdy       ),
    .uncache_req        (uncache_req         ),
    .uncache_wr         (uncache_wr          ),
    .uncache_size       (uncache_size        ),
    .uncache_wstrb      (uncache_wstrb       ),
    .uncache_addr       (uncache_addr        ),
    .uncache_wdata      (uncache_wdata       ),
    .uncache_addr_ok    (uncache_addr_ok     ),
    .uncache_data_ok    (uncache_data_ok     ),
    .uncache_rdata      (uncache_rdata       ),
    .data_busy          (bridge_data_busy    ),
    .arid               (arid                ),
    .araddr             (araddr              ),
    .arlen              (arlen               ),
    .arsize             (arsize              ),
    .arburst            (arburst             ),
    .arlock             (arlock              ),
    .arcache            (arcache             ),
    .arprot             (arprot              ),
    .arvalid            (arvalid             ),
    .arready            (arready             ),
    .rid                (rid                 ),
    .rdata              (rdata               ),
    .rresp              (rresp               ),
    .rlast              (rlast               ),
    .rvalid             (rvalid              ),
    .rready             (rready              ),
    .awid               (awid                ),
    .awaddr             (awaddr              ),
    .awlen              (awlen               ),
    .awsize             (awsize              ),
    .awburst            (awburst             ),
    .awlock             (awlock              ),
    .awcache            (awcache             ),
    .awprot             (awprot              ),
    .awvalid            (awvalid             ),
    .awready            (awready             ),
    .wid                (wid                 ),
    .wdata              (wdata               ),
    .wstrb              (wstrb               ),
    .wlast              (wlast               ),
    .wvalid             (wvalid              ),
    .wready             (wready              ),
    .bid                (bid                 ),
    .bresp              (bresp               ),
    .bvalid             (bvalid              ),
    .bready             (bready              )
);

endmodule

module sram_axi_bridge_2x1(
    input         clk,
    input         resetn,

    input         icache_rd_req,
    input  [ 2:0] icache_rd_type,
    input  [31:0] icache_rd_addr,
    output        icache_rd_rdy,
    output        icache_ret_valid,
    output        icache_ret_last,
    output [31:0] icache_ret_data,

    input         dcache_rd_req,
    input  [ 2:0] dcache_rd_type,
    input  [31:0] dcache_rd_addr,
    output        dcache_rd_rdy,
    output        dcache_ret_valid,
    output        dcache_ret_last,
    output [31:0] dcache_ret_data,

    input         dcache_wr_req,
    input  [ 2:0] dcache_wr_type,
    input  [31:0] dcache_wr_addr,
    input  [ 3:0] dcache_wr_wstrb,
    input  [127:0] dcache_wr_data,
    output        dcache_wr_rdy,

    input         uncache_req,
    input         uncache_wr,
    input  [ 1:0] uncache_size,
    input  [ 3:0] uncache_wstrb,
    input  [31:0] uncache_addr,
    input  [31:0] uncache_wdata,
    output        uncache_addr_ok,
    output        uncache_data_ok,
    output [31:0] uncache_rdata,
    output        data_busy,

    output [ 3:0] arid,
    output [31:0] araddr,
    output [ 7:0] arlen,
    output [ 2:0] arsize,
    output [ 1:0] arburst,
    output [ 1:0] arlock,
    output [ 3:0] arcache,
    output [ 2:0] arprot,
    output        arvalid,
    input         arready,
    input  [ 3:0] rid,
    input  [31:0] rdata,
    input  [ 1:0] rresp,
    input         rlast,
    input         rvalid,
    output        rready,

    output [ 3:0] awid,
    output [31:0] awaddr,
    output [ 7:0] awlen,
    output [ 2:0] awsize,
    output [ 1:0] awburst,
    output [ 1:0] awlock,
    output [ 3:0] awcache,
    output [ 2:0] awprot,
    output        awvalid,
    input         awready,
    output [ 3:0] wid,
    output [31:0] wdata,
    output [ 3:0] wstrb,
    output        wlast,
    output        wvalid,
    input         wready,
    input  [ 3:0] bid,
    input  [ 1:0] bresp,
    input         bvalid,
    output        bready
);

localparam ST_IDLE    = 3'd0;
localparam ST_RD_ADDR = 3'd1;
localparam ST_RD_RESP = 3'd2;
localparam ST_WR_ADDR = 3'd3;
localparam ST_WR_DATA = 3'd4;
localparam ST_WR_RESP = 3'd5;

reg [2:0] state;
reg [1:0] rd_source;
reg [ 7:0] rd_len_r;
reg [31:0] rd_addr_r;
reg [ 1:0] rd_size_r;
reg [127:0] wr_data_r;
reg [ 3:0] wr_strb_r;
reg [31:0] wr_addr_r;
reg [ 1:0] wr_size_r;
reg [ 7:0] wr_len_r;
reg [ 1:0] wr_cnt;
reg        wr_is_uncache;

wire sel_uncache_wr = uncache_req && uncache_wr;
wire sel_uncache_rd = uncache_req && !uncache_wr;
wire sel_dcache_wr  = !uncache_req && dcache_wr_req;
wire sel_dcache_rd  = !uncache_req && !dcache_wr_req && dcache_rd_req;
wire sel_icache_rd  = !uncache_req && !dcache_wr_req && !dcache_rd_req && icache_rd_req;

wire sel_rd = sel_uncache_rd || sel_dcache_rd || sel_icache_rd;
wire sel_wr = sel_uncache_wr || sel_dcache_wr;

wire [1:0] req_size = sel_uncache_rd ? uncache_size : 2'b10;
wire [31:0] req_addr = sel_uncache_rd ? uncache_addr :
                       sel_dcache_rd  ? dcache_rd_addr :
                                        icache_rd_addr;
wire [7:0] req_len = sel_uncache_rd ? 8'd0 : 8'd3;
wire [1:0] req_source = sel_uncache_rd ? 2'd2 :
                        sel_dcache_rd  ? 2'd1 : 2'd0;

wire rd_addr_hs = arvalid && arready;
wire rd_data_hs = rvalid && rready;
wire aw_hs      = awvalid && awready;
wire w_hs       = wvalid && wready;
wire wr_resp_hs = bvalid && bready;

always @(posedge clk) begin
    if (!resetn) begin
        state       <= ST_IDLE;
        rd_source   <= 2'b0;
        rd_len_r    <= 8'b0;
        rd_addr_r   <= 32'b0;
        rd_size_r   <= 2'b0;
        wr_data_r   <= 128'b0;
        wr_strb_r   <= 4'b0;
        wr_addr_r   <= 32'b0;
        wr_size_r   <= 2'b0;
        wr_len_r    <= 8'b0;
        wr_cnt      <= 2'b0;
        wr_is_uncache <= 1'b0;
    end
    else begin
        case (state)
        ST_IDLE: begin
            wr_cnt <= 2'b0;
            if (sel_wr) begin
                wr_data_r     <= sel_uncache_wr ? {96'b0, uncache_wdata} : dcache_wr_data;
                wr_strb_r     <= sel_uncache_wr ? uncache_wstrb : dcache_wr_wstrb;
                wr_addr_r     <= sel_uncache_wr ? uncache_addr  : dcache_wr_addr;
                wr_size_r     <= sel_uncache_wr ? uncache_size  : 2'b10;
                wr_len_r      <= sel_uncache_wr ? 8'd0 : 8'd3;
                wr_is_uncache <= sel_uncache_wr;
                state         <= ST_WR_ADDR;
            end
            else if (sel_rd) begin
                rd_addr_r   <= req_addr;
                rd_size_r   <= req_size;
                rd_len_r    <= req_len;
                rd_source   <= req_source;
                state       <= ST_RD_ADDR;
            end
        end
        ST_RD_ADDR: begin
            if (rd_addr_hs) begin
                state <= ST_RD_RESP;
            end
        end
        ST_RD_RESP: begin
            if (rd_data_hs && rlast) begin
                state <= ST_IDLE;
            end
        end
        ST_WR_ADDR: begin
            if (aw_hs) begin
                state <= ST_WR_DATA;
            end
        end
        ST_WR_DATA: begin
            if (w_hs) begin
                if (wlast) begin
                    state <= ST_WR_RESP;
                end
                else begin
                    wr_cnt <= wr_cnt + 2'b01;
                end
            end
        end
        ST_WR_RESP: begin
            if (wr_resp_hs) begin
                state <= ST_IDLE;
            end
        end
        default: begin
            state <= ST_IDLE;
        end
        endcase
    end
end

assign arid     = (rd_source == 2'd0) ? 4'd0 : 4'd1;
assign araddr   = rd_addr_r;
assign arlen    = rd_len_r;
assign arsize   = {1'b0, rd_size_r};
assign arburst  = 2'b01;
assign arlock   = 2'b00;
assign arcache  = 4'b0000;
assign arprot   = 3'b000;
assign arvalid  = (state == ST_RD_ADDR);
assign rready   = (state == ST_RD_RESP);

assign awid     = 4'd1;
assign awaddr   = wr_addr_r;
assign awlen    = wr_len_r;
assign awsize   = {1'b0, wr_size_r};
assign awburst  = 2'b01;
assign awlock   = 2'b00;
assign awcache  = 4'b0000;
assign awprot   = 3'b000;
assign awvalid  = (state == ST_WR_ADDR);

assign wid      = 4'd1;
assign wdata    = (wr_cnt == 2'd0) ? wr_data_r[ 31: 0] :
                  (wr_cnt == 2'd1) ? wr_data_r[ 63:32] :
                  (wr_cnt == 2'd2) ? wr_data_r[ 95:64] :
                                      wr_data_r[127:96];
assign wstrb    = wr_strb_r;
assign wlast    = wr_is_uncache || (wr_cnt == 2'd3);
assign wvalid   = (state == ST_WR_DATA);
assign bready   = (state == ST_WR_RESP);

assign uncache_addr_ok  = (state == ST_IDLE) && uncache_req;
assign uncache_data_ok  = ((state == ST_RD_RESP) && (rd_source == 2'd2) && rd_data_hs)
                        || ((state == ST_WR_RESP) && wr_is_uncache && wr_resp_hs);
assign uncache_rdata    = rdata;

assign dcache_wr_rdy    = (state == ST_IDLE) && sel_dcache_wr;
assign dcache_rd_rdy    = (state == ST_IDLE) && sel_dcache_rd;
assign dcache_ret_valid = (state == ST_RD_RESP) && (rd_source == 2'd1) && rd_data_hs;
assign dcache_ret_last  = dcache_ret_valid && rlast;
assign dcache_ret_data  = rdata;

assign icache_rd_rdy    = (state == ST_IDLE) && sel_icache_rd;
assign icache_ret_valid = (state == ST_RD_RESP) && (rd_source == 2'd0) && rd_data_hs;
assign icache_ret_last  = icache_ret_valid && rlast;
assign icache_ret_data  = rdata;

assign data_busy = (state == ST_WR_ADDR) ||
                   (state == ST_WR_DATA) ||
                   (state == ST_WR_RESP) ||
                   (((state == ST_RD_ADDR) || (state == ST_RD_RESP)) &&
                    (rd_source != 2'd0));

endmodule

module mycpu_core #(
    parameter integer ENABLE_BP = 1
)(
    input         clk,
    input         resetn,
    // 8 external hardware interrupt lines (tie to 0 if unused)
    input  [7:0]  hw_int_in,
    input         icache_miss_event,
    input         dcache_miss_event,
    // inst sram interface (bus-style)
    output        inst_sram_req,
    output        inst_sram_wr,
    output [ 1:0] inst_sram_size,
    output [ 3:0] inst_sram_wstrb,
    output [31:0] inst_sram_addr,
    output [31:0] inst_sram_wdata,
    output [31:0] inst_sram_req_pc,
    output [`FETCH_EPOCH_WD-1:0] inst_sram_req_epoch,
    input         inst_sram_addr_ok,
    input         inst_sram_data_ok,
    input  [63:0] inst_sram_resp_data,
    input  [31:0] inst_sram_resp_pc,
    input  [ 1:0] inst_sram_resp_word_valid,
    input  [`FETCH_EPOCH_WD-1:0] inst_sram_resp_epoch,
    // data sram interface (bus-style)
    output        data_sram_req,
    output        data_sram_wr,
    output [ 1:0] data_sram_size,
    output [ 3:0] data_sram_wstrb,
    output [31:0] data_sram_addr,
    output [31:0] data_sram_wdata,
    output        data_sram_uncached,
    input         data_sram_addr_ok,
    input         data_sram_data_ok,
    input  [31:0] data_sram_rdata,
    // cache maintenance interface
    output        cacop_valid,
    output        cacop_is_dcache,
    output [ 1:0] cacop_op,
    output [ 7:0] cacop_index,
    output        cacop_way,
    output [19:0] cacop_tag,
    input         cacop_ok,
    output        barrier_req,
    output        barrier_is_ibar,
    input         barrier_done,
    input         dcache_inv_valid,
    input  [27:0] dcache_inv_line,
    // trace debug interface
    output [31:0] debug_wb_pc,
    output [ 3:0] debug_wb_rf_we,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata
);

reg         reset;
always @(posedge clk) begin
    if (!resetn) begin
        reset <= 1'b1;
    end
    else begin
        reset <= 1'b0;
    end
end

wire         fetch_queue_to_decode_ready;
wire         lane0_decode_ready;
wire [`ARCH_LANE_COUNT-1:0] decode_to_issue_ready;
wire         issue_to_ex1_ready;
wire         ex1_to_ex2_ready;
wire         ex2_to_ex3_ready;
wire         ex3_to_mem_ready;
wire         mem_to_wb_ready;
wire         fs_to_ds_valid;
wire         ds_to_es_valid;
wire         ms_to_ws_valid;
wire         ms_empty;
wire         ws_empty;
wire [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus;
wire [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus;
wire [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus;
wire [`WS_TO_RF_BUS_WD -1:0] ws_to_rf_bus;
wire [`WS_TO_RF_BUS_WD -1:0] ws1_to_rf_bus;

// Target-architecture decoupling boundaries.
wire         f2_to_fetch_queue_valid;
wire         fetch_queue_to_decode_valid;
wire         fetch_queue_in_ready;
wire [`FS_TO_DS_BUS_WD-1:0] f2_to_fetch_queue_bus;
wire                         f2_to_fetch_queue_slot1_valid;
wire [`FS_TO_DS_BUS_WD-1:0] f2_to_fetch_queue_slot1_bus;
wire [`FS_TO_DS_BUS_WD-1:0] fetch_queue_to_decode_bus;
wire         fetch_queue_slot1_valid;
wire         fetch_queue_packet_valid;
wire [`FS_TO_DS_BUS_WD-1:0] fetch_queue_slot1_bus;
wire [2:0]   fetch_queue_occupancy;
wire [`ARCH_LANE_COUNT-1:0] decode_to_issue_valid;
wire [`ARCH_LANE_COUNT*`ID_TO_EX1_BUS_WD-1:0] decode_to_issue_bus;
wire [`ARCH_LANE_COUNT-1:0] issue_lane_valid;
wire [`ARCH_LANE_COUNT-1:0] issue_lane_ready;
wire [`ARCH_LANE_COUNT*`ID_TO_EX1_BUS_WD-1:0] issue_lane_bus;
wire issue_lane0_valid = issue_lane_valid[0];
wire [`ID_TO_EX1_BUS_WD-1:0] issue_lane0_bus =
    issue_lane_bus[0 +: `ID_TO_EX1_BUS_WD];
wire [4:0]   issue_to_ds_dest;
wire         issue_csr_we;
wire [13:0]  issue_csr_num;
wire         issue_is_ertn;
wire         issue_tlb_pending;
wire [`PRODUCER_PACKET_WD-1:0] issue_producer_packet;
wire [`PRODUCER_PACKET_WD-1:0] ex1_producer_packet;
wire [`PRODUCER_PACKET_WD-1:0] ex2_producer_packet;
wire [`PRODUCER_PACKET_WD-1:0] ex3_producer_packet;
wire [`PRODUCER_PACKET_WD-1:0] mem_producer_packet;
wire [`PRODUCER_PACKET_WD-1:0] wb_producer_packet;
wire [`PRODUCER_PACKET_WD-1:0] lane1_ex1_producer_packet;
wire [`PRODUCER_PACKET_WD-1:0] lane1_ex2_producer_packet;
wire [`PRODUCER_PACKET_WD-1:0] lane1_ex3_producer_packet;
wire [`PRODUCER_PACKET_WD-1:0] lane1_mem_producer_packet;
wire [`PRODUCER_PACKET_WD-1:0] lane1_wb_producer_packet;
wire lane1_wb_valid;
wire [31:0] lane1_wb_pc;
wire [31:0] lane1_wb_instr;
wire        lane1_wb_rf_we;
wire [4:0]  lane1_wb_rf_waddr;
wire [31:0] lane1_wb_rf_wdata;
wire issue_stall_data;
wire issue_stall_struct;
wire branch_resolve_fire;
wire [`ARCH_LANE_COUNT-1:0] commit_lane_valid;
wire [`ARCH_LANE_COUNT*32-1:0] commit_lane_seq_id;
wire [`ARCH_LANE_COUNT-1:0] commit_lane_id;
wire lane1_decode_ready;
wire lane1_decode_valid;
wire [`ID_TO_EX1_BUS_WD-1:0] lane1_decode_bus;
wire lane1_issue_valid = issue_lane_valid[1];
wire [`ID_TO_EX1_BUS_WD-1:0] issue_lane1_bus =
    issue_lane_bus[`ID_TO_EX1_BUS_WD +: `ID_TO_EX1_BUS_WD];
reg [31:0] next_instruction_seq_id;

// Every pipeline boundary is an explicit valid/ready pair.
wire         if1_to_if2_ready;
wire         if1_to_if2_valid;
wire         if2_to_id_valid;
wire         id_to_ex1_valid;
wire         ex1_to_ex2_valid;
wire         ex2_to_ex3_valid;
wire         ex3_to_mem_valid;
wire         mem_to_wb_valid;
wire         ex2_empty;
wire         ex3_empty;
wire [`IF1_TO_IF2_BUS_WD -1:0] if1_to_if2_bus;
wire [`FETCH_EPOCH_WD-1:0] current_fetch_epoch;
wire [`IF2_TO_ID_BUS_WD  -1:0] if2_to_id_bus;
wire [`ID_TO_EX1_BUS_WD  -1:0] id_to_ex1_bus;
wire [`EX1_TO_EX2_BUS_WD -1:0] ex1_to_ex2_bus;
wire [`EX2_TO_EX3_BUS_WD -1:0] ex2_to_ex3_bus;
wire [`EX3_TO_MEM_BUS_WD -1:0] ex3_to_mem_bus;
wire        ex1_redirect_valid;
wire [31:0] ex1_redirect_target;
wire [31:0] ex1_redirect_seq_id;
wire [`FETCH_EPOCH_WD-1:0] ex1_redirect_epoch;
wire        redirect_valid;
wire        branch_redirect_valid;
wire [31:0] branch_redirect_target;
wire [31:0] branch_redirect_seq_id;
wire [`FETCH_EPOCH_WD-1:0] branch_redirect_epoch;

assign if2_to_id_valid  = fetch_queue_to_decode_valid;
// A JIRL resolves in EX1.  The sequential instruction may already be waiting
// in Issue at that point; do not let it enter EX1 on the redirect edge.
assign id_to_ex1_valid  = issue_lane0_valid && !ex1_redirect_valid &&
                          !branch_redirect_valid && !redirect_valid;
assign mem_to_wb_valid  = ms_to_ws_valid;
assign if2_to_id_bus    = fetch_queue_to_decode_bus;
assign id_to_ex1_bus    = issue_lane0_bus;

wire [31:0] inst_vaddr;
wire [31:0] inst_paddr;
wire        inst_trans_ex;
wire [ 5:0] inst_trans_ecode;
wire [ 8:0] inst_trans_esubcode;

// exception interface
wire        flush;
wire [31:0] ex_entry;
wire [31:0] ex_entry_from_ex2;
wire        ex3_wb_ex;
wire [ 5:0] ex3_wb_ecode;
wire [ 8:0] ex3_wb_esubcode;
wire [31:0] ex3_wb_pc;
wire [31:0] ex3_wb_badv;

// ertn interface
wire        ertn_flush;
wire [31:0] ertn_pc;
wire [31:0] ertn_pc_from_ex2;

wire        ibar_flush;
wire [31:0] ibar_target;
wire        idle_wait;
wire [31:0] redirect_pc;
wire [ 1:0] redirect_cause;
wire [31:0] redirect_seq_id;
wire [`FETCH_EPOCH_WD-1:0] redirect_epoch;
wire [`REDIRECT_PACKET_WD-1:0] redirect_packet;
wire [31:0] commit_redirect_seq_id;
wire [`FETCH_EPOCH_WD-1:0] commit_redirect_epoch;
// Commit-to-predictor training boundary.
wire        bp_update_valid;
wire [31:0] bp_update_pc;
wire        bp_update_taken;
wire [31:0] bp_update_target;
wire [2:0]  bp_update_type;
wire [15:0] bp_update_meta;
wire        bp_update_was_predicted;
wire        bp_update_mispredict;

assign redirect_pc = redirect_packet[`REDIRECT_TARGET_HI:`REDIRECT_TARGET_LO];
assign redirect_cause = redirect_packet[`REDIRECT_REASON_HI:`REDIRECT_REASON_LO];
assign redirect_seq_id = redirect_packet[`REDIRECT_SEQ_HI:`REDIRECT_SEQ_LO];
assign redirect_epoch = redirect_packet[`REDIRECT_EPOCH_HI:`REDIRECT_EPOCH_LO];

branch_resolve_register u_branch_resolve_register(
    .clk(clk), .reset(reset),
    .kill(flush || ertn_flush || ibar_flush),
    .in_valid(ex1_redirect_valid), .in_target(ex1_redirect_target),
    .in_seq_id(ex1_redirect_seq_id), .in_epoch(ex1_redirect_epoch),
    .out_valid(branch_redirect_valid), .out_target(branch_redirect_target),
    .out_seq_id(branch_redirect_seq_id), .out_epoch(branch_redirect_epoch)
);

redirect_register u_redirect_register(
    .clk(clk), .reset(reset),
    .branch_valid(branch_redirect_valid),
    .branch_target(branch_redirect_target),
    .branch_seq_id(branch_redirect_seq_id),
    .branch_epoch(branch_redirect_epoch),
    .ibar_valid(ibar_flush), .ibar_target(ibar_target),
    .ibar_seq_id(commit_redirect_seq_id),
    .ibar_epoch(commit_redirect_epoch),
    .exception_valid(flush), .exception_target(ex_entry),
    .exception_seq_id(commit_redirect_seq_id),
    .exception_epoch(commit_redirect_epoch),
    .ertn_valid(ertn_flush), .ertn_target(ertn_pc),
    .ertn_seq_id(commit_redirect_seq_id),
    .ertn_epoch(commit_redirect_epoch),
    .redirect_valid(redirect_valid),
    .redirect_packet(redirect_packet)
);

// csr hazard tracking
wire        ex1_csr_we;
wire [13:0] ex1_csr_num;
wire        ex1_is_ertn;
wire        ex2_csr_we;
wire [13:0] ex2_csr_num;
wire        ex2_is_ertn;
wire        ex3_csr_we;
wire [13:0] ex3_csr_num;
wire        ex3_is_ertn;
wire        ex1_tlb_pending;
wire        ex2_tlb_pending;
wire        ex3_tlb_pending;
wire [`EX3_PRIV_COMMIT_BUS_WD-1:0] priv_commit_bus;
wire [31:0] ex2_cnt_low;
wire [31:0] ex2_cnt_high;
wire [31:0] ex2_tid;
wire        ex2_has_int;

// LL/SC reservation state and retirement events
wire [27:0] sc_query_line;
wire        sc_query_cached;
wire        sc_can_store;
wire        reservation_current;
wire        reservation_valid;
wire        llbctl_klo;
wire        wcllb_commit;
wire        ll_commit_valid;
wire        sc_commit_valid;
wire        local_store_commit_valid;
wire [27:0] mem_commit_line;
wire        wrong_epoch_drop_event;

wire        predictor_lookup_hit;
wire        predictor_lookup_taken;
wire [31:0] predictor_lookup_target;
wire [2:0]  predictor_lookup_type;
wire [15:0] predictor_lookup_meta;
wire [63:0] predictor_update_count;
wire        fetch_pred_valid = (ENABLE_BP != 0) ? predictor_lookup_hit : 1'b0;
wire        fetch_pred_taken = (ENABLE_BP != 0) ? predictor_lookup_taken : 1'b0;
wire [31:0] fetch_pred_target = (ENABLE_BP != 0) ? predictor_lookup_target :
                                                   (inst_vaddr + 32'd4);
wire [2:0]  fetch_pred_type = (ENABLE_BP != 0) ? predictor_lookup_type :
                                                 `PRED_TYPE_NONE;
wire [15:0] fetch_pred_meta = (ENABLE_BP != 0) ? predictor_lookup_meta : 16'b0;

wire [7:0] hw_int_in_safe;
assign hw_int_in_safe = {
    (hw_int_in[7] === 1'b1),
    (hw_int_in[6] === 1'b1),
    (hw_int_in[5] === 1'b1),
    (hw_int_in[4] === 1'b1),
    (hw_int_in[3] === 1'b1),
    (hw_int_in[2] === 1'b1),
    (hw_int_in[1] === 1'b1),
    (hw_int_in[0] === 1'b1)
};

llsc_unit u_llsc_unit(
    .clk                     (clk                     ),
    .reset                   (reset                   ),
    .ll_commit_valid         (ll_commit_valid         ),
    .ll_commit_line          (mem_commit_line         ),
    .sc_commit_valid         (sc_commit_valid         ),
    .local_store_commit_valid(local_store_commit_valid),
    .local_store_commit_line (mem_commit_line         ),
    .dcache_inv_valid        (dcache_inv_valid        ),
    .dcache_inv_line         (dcache_inv_line         ),
    .external_store_valid    (1'b0                    ),
    .external_store_line     (28'b0                   ),
    .wcllb_commit            (wcllb_commit            ),
    .ertn_commit             (ertn_flush              ),
    .llbctl_klo              (llbctl_klo              ),
    .sc_query_line           (sc_query_line           ),
    .sc_query_cached         (sc_query_cached         ),
    .sc_can_store            (sc_can_store            ),
    .reservation_current     (reservation_current     ),
    .reservation_valid       (reservation_valid       )
);

branch_predictor u_branch_predictor(
    .clk(clk), .reset(reset),
    .lookup_valid(1'b1), .lookup_pc(inst_vaddr),
    .lookup_epoch(current_fetch_epoch),
    .lookup_hit(predictor_lookup_hit),
    .lookup_taken(predictor_lookup_taken),
    .lookup_target(predictor_lookup_target),
    .lookup_type(predictor_lookup_type),
    .lookup_meta(predictor_lookup_meta),
    .update_valid(bp_update_valid), .update_pc(bp_update_pc),
    .update_taken(bp_update_taken), .update_target(bp_update_target),
    .update_type(bp_update_type), .update_meta(bp_update_meta),
    .update_was_predicted(bp_update_was_predicted),
    .update_mispredict(bp_update_mispredict),
    .update_count(predictor_update_count)
);

// F0/F1: next-PC selection followed by the registered translation/request
// descriptor boundary implemented inside if1_stage.
if1_stage if1_stage(
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
    .current_epoch       (current_fetch_epoch ),
    .pred_valid          (fetch_pred_valid    ),
    .pred_taken          (fetch_pred_taken    ),
    .pred_target         (fetch_pred_target   ),
    .pred_type           (fetch_pred_type     ),
    .pred_meta           (fetch_pred_meta     ),
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

// F2: ICache response wait/filtering.  Its ready input terminates at the
// Fetch Queue rather than propagating Decode backpressure into the cache.
if2_stage if2_stage(
    .clk                 (clk                 ),
    .reset               (reset               ),
    .if2_to_queue_ready  (fetch_queue_in_ready),
    .if1_to_if2_ready    (if1_to_if2_ready    ),
    .redirect            (redirect_valid      ),
    .current_epoch       (current_fetch_epoch ),
    .if1_to_if2_valid    (if1_to_if2_valid    ),
    .if1_to_if2_bus      (if1_to_if2_bus      ),
    .if2_to_queue_valid  (f2_to_fetch_queue_valid),
    .if2_to_queue_packet (f2_to_fetch_queue_bus),
    .if2_to_queue_slot1_valid(f2_to_fetch_queue_slot1_valid),
    .if2_to_queue_slot1_packet(f2_to_fetch_queue_slot1_bus),
    .inst_sram_data_ok   (inst_sram_data_ok   ),
    .inst_sram_resp_data (inst_sram_resp_data ),
    .inst_sram_resp_pc   (inst_sram_resp_pc   ),
    .inst_sram_resp_word_valid(inst_sram_resp_word_valid),
    .inst_sram_resp_epoch(inst_sram_resp_epoch),
    .wrong_epoch_drop    (wrong_epoch_drop_event)
);

fetch_packet_queue #(.DEPTH(4), .PTR_W(2)) u_fetch_queue(
    .clk          (clk                         ),
    .reset        (reset                       ),
    .flush        (redirect_valid              ),
    .in_valid     (f2_to_fetch_queue_valid     ),
    .in_ready     (fetch_queue_in_ready        ),
    .slot0_in_valid(f2_to_fetch_queue_valid    ),
    .slot0_in_packet(f2_to_fetch_queue_bus     ),
    .slot1_in_valid(f2_to_fetch_queue_slot1_valid),
    .slot1_in_packet(f2_to_fetch_queue_slot1_bus),
    .out_valid    (fetch_queue_packet_valid    ),
    .out_ready    (fetch_queue_to_decode_ready ),
    .slot0_out_valid(fetch_queue_to_decode_valid),
    .slot0_out_packet(fetch_queue_to_decode_bus),
    .slot1_out_valid(fetch_queue_slot1_valid   ),
    .slot1_out_packet(fetch_queue_slot1_bus    ),
    .occupancy    (fetch_queue_occupancy       )
);

wire fetch_decode_accept = fetch_queue_packet_valid &&
                           fetch_queue_to_decode_ready;
assign fetch_queue_to_decode_ready =
    lane0_decode_ready &&
    (!fetch_queue_slot1_valid || lane1_decode_ready);
assign fs_to_ds_valid = fetch_queue_to_decode_valid && fetch_decode_accept;
assign fs_to_ds_bus   = fetch_queue_to_decode_bus;

// ID stage
id_stage id_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    .flush          (flush          ),
    .ibar_flush     (ibar_flush     ),
    .ex1_redirect   (ex1_redirect_valid || branch_redirect_valid ||
                     redirect_valid),
    .ds_to_es_ready (decode_to_issue_ready[0]),
    .fs_to_ds_ready (lane0_decode_ready),
    //from fs
    .fs_to_ds_valid (fs_to_ds_valid ),
    .fs_to_ds_bus   (fs_to_ds_bus   ),
    .fs_seq_id      (next_instruction_seq_id),
    .lane_id        (1'b0           ),
    //to es
    .ds_to_es_valid (ds_to_es_valid ),
    .ds_to_es_bus   (ds_to_es_bus   ),
    //to rf: for write back
    .ws_to_rf_bus   (ws_to_rf_bus   ),
    .ws1_to_rf_bus  (ws1_to_rf_bus  ),
    .ertn_flush     (ertn_flush     )
);

id_stage id_stage_lane1(
    .clk            (clk            ),
    .reset          (reset          ),
    .flush          (flush          ),
    .ibar_flush     (ibar_flush     ),
    .ex1_redirect   (ex1_redirect_valid || branch_redirect_valid ||
                     redirect_valid),
    .ds_to_es_ready (decode_to_issue_ready[1]),
    .fs_to_ds_ready (lane1_decode_ready),
    .fs_to_ds_valid (fetch_queue_slot1_valid && fetch_decode_accept),
    .fs_to_ds_bus   (fetch_queue_slot1_bus),
    .fs_seq_id      (next_instruction_seq_id + 32'd1),
    .lane_id        (1'b1           ),
    .ds_to_es_valid (lane1_decode_valid),
    .ds_to_es_bus   (lane1_decode_bus),
    .ws_to_rf_bus   (ws_to_rf_bus   ),
    .ws1_to_rf_bus  (ws1_to_rf_bus  ),
    .ertn_flush     (ertn_flush     )
);

always @(posedge clk) begin
    if (reset)
        next_instruction_seq_id <= 32'b0;
    else if (fetch_decode_accept)
        next_instruction_seq_id <= next_instruction_seq_id +
                                   (fetch_queue_slot1_valid ? 32'd2 : 32'd1);
end

assign decode_to_issue_valid = {lane1_decode_valid, ds_to_es_valid};
assign decode_to_issue_bus   = {lane1_decode_bus, ds_to_es_bus};
assign issue_lane_ready      = {issue_to_ex1_ready, issue_to_ex1_ready};

// Issue is lane-shaped from the outset; only lane0 is enabled in this phase.
issue_stage issue_stage(
    .clk             (clk                    ),
    .reset           (reset                  ),
    .kill            (flush || ertn_flush || ibar_flush ||
                      ex1_redirect_valid || branch_redirect_valid ||
                      redirect_valid),
    .decode_valid    (decode_to_issue_valid  ),
    .decode_ready    (decode_to_issue_ready  ),
    .decode_packet   (decode_to_issue_bus    ),
    .issue_lane_valid(issue_lane_valid       ),
    .issue_lane_ready(issue_lane_ready       ),
    .issue_lane_packet(issue_lane_bus        ),
    .producer_set    ({wb_producer_packet, lane1_wb_producer_packet,
                       mem_producer_packet, lane1_mem_producer_packet,
                       ex3_producer_packet, lane1_ex3_producer_packet,
                       ex2_producer_packet, lane1_ex2_producer_packet,
                       ex1_producer_packet, lane1_ex1_producer_packet}),
    .serialize_pending(ex1_csr_we || ex2_csr_we || ex3_csr_we ||
                       ex1_is_ertn || ex2_is_ertn || ex3_is_ertn ||
                       ex1_tlb_pending || ex2_tlb_pending || ex3_tlb_pending),
    .producer_packet (issue_producer_packet  ),
    .stall_data      (issue_stall_data       ),
    .stall_struct    (issue_stall_struct     ),
    .pending_dst     (issue_to_ds_dest       ),
    .pending_csr_we  (issue_csr_we           ),
    .pending_csr_num (issue_csr_num          ),
    .pending_ertn    (issue_is_ertn          ),
    .pending_tlb     (issue_tlb_pending      )
);

// EX1 stage: early ALU, virtual address, and store-data preparation.
ex1_stage ex1_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    .flush          (flush          ),
    .ertn_flush     (ertn_flush     ),
    .ibar_flush     (ibar_flush     ),
    .ex2_empty      (ex2_empty      ),
    .ex1_to_ex2_ready(ex1_to_ex2_ready),
    .id_to_ex1_ready(issue_to_ex1_ready),
    .id_to_ex1_valid(id_to_ex1_valid),
    .id_to_ex1_bus  (id_to_ex1_bus  ),
    .ex1_to_ex2_valid(ex1_to_ex2_valid),
    .ex1_to_ex2_bus (ex1_to_ex2_bus ),
    .ex1_producer_packet(ex1_producer_packet),
    .branch_resolve_fire(branch_resolve_fire),
    .ex1_redirect_valid(ex1_redirect_valid),
    .ex1_redirect_target(ex1_redirect_target),
    .ex1_redirect_seq_id(ex1_redirect_seq_id),
    .ex1_redirect_epoch(ex1_redirect_epoch),
    .ex1_csr_we     (ex1_csr_we     ),
    .ex1_csr_num    (ex1_csr_num    ),
    .ex1_is_ertn    (ex1_is_ertn    ),
    .ex1_tlb_pending(ex1_tlb_pending)
);

// EX2 stage: privileged state, exceptions, translation, and memory requests.
ex2_stage ex2_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    .ex2_to_ex3_ready(ex2_to_ex3_ready),
    .older_pipe_empty(ex3_empty && ms_empty && ws_empty),
    .priv_commit_bus(priv_commit_bus),
    .ex1_to_ex2_ready(ex1_to_ex2_ready),
    .ex2_empty      (ex2_empty      ),
    .ex2_tlb_pending(ex2_tlb_pending),
    //from ex1
    .ex1_to_ex2_valid(ex1_to_ex2_valid),
    .ex1_to_ex2_bus (ex1_to_ex2_bus ),
    //to ex3
    .ex2_to_ex3_valid(ex2_to_ex3_valid),
    .ex2_to_ex3_bus(ex2_to_ex3_bus),
    // data sram interface
    .data_sram_req    (),
    .data_sram_wr     (),
    .data_sram_size   (),
    .data_sram_wstrb  (),
    .data_sram_addr   (),
    .data_sram_wdata  (),
    .data_sram_uncached(),
    .data_sram_addr_ok(data_sram_addr_ok),
    .data_sram_data_ok(data_sram_data_ok),
    .data_sram_rdata  (data_sram_rdata ),
    .cacop_valid      (),
    .cacop_is_dcache  (),
    .cacop_op         (),
    .cacop_index      (),
    .cacop_way        (),
    .cacop_tag        (),
    .cacop_ok         (cacop_ok         ),
    .barrier_req      (),
    .barrier_is_ibar  (),
    .barrier_done     (barrier_done     ),
    .ibar_flush       (ibar_flush       ),
    .ibar_target      (),
    .idle_wait        (),
    .ex2_producer_packet(ex2_producer_packet),
    // exception interface
    .flush          (flush          ),
    .ex3_wb_ex      (ex3_wb_ex      ),
    .ex3_wb_ecode   (ex3_wb_ecode   ),
    .ex3_wb_esubcode(ex3_wb_esubcode),
    .ex3_wb_pc      (ex3_wb_pc      ),
    .ex3_wb_badv    (ex3_wb_badv    ),
    .ex_entry       (ex_entry_from_ex2),
    // ertn interface
    .ertn_flush     (ertn_flush     ),
    .ertn_pc        (ertn_pc_from_ex2),
    // instruction address translation
    .inst_vaddr     (inst_vaddr     ),
    .inst_paddr     (inst_paddr     ),
    .inst_trans_ex  (inst_trans_ex  ),
    .inst_trans_ecode(inst_trans_ecode),
    .inst_trans_esubcode(inst_trans_esubcode),
    // csr hazard tracking
    .es_csr_we      (ex2_csr_we     ),
    .es_csr_num     (ex2_csr_num    ),
    .es_is_ertn     (ex2_is_ertn    ),
    .cnt_low_out    (ex2_cnt_low     ),
    .cnt_high_out   (ex2_cnt_high    ),
    .tid_out        (ex2_tid         ),
    .has_int_out    (ex2_has_int     ),
    .sc_query_line  (),
    .sc_query_cached(),
    .sc_can_store   (1'b0          ),
    .reservation_valid(reservation_current),
    .llbctl_klo     (llbctl_klo     ),
    .wcllb_commit   (wcllb_commit   ),
    // interrupt / csr interface
    .hw_int_in      (hw_int_in_safe )
);

// Commit (legacy module name ex3_stage): ordered exception/redirect and
// architectural side-effect arbitration, followed by the MEM request boundary.
ex3_stage ex3_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    .ex3_to_mem_ready(ex3_to_mem_ready),
    .older_pipe_empty(ms_empty && ws_empty),
    .ex2_to_ex3_ready(ex2_to_ex3_ready),
    .ex3_empty      (ex3_empty      ),
    .ex2_to_ex3_valid(ex2_to_ex3_valid),
    .ex2_to_ex3_bus (ex2_to_ex3_bus ),
    .ex3_to_mem_valid(ex3_to_mem_valid),
    .ex3_to_mem_bus (ex3_to_mem_bus ),
    .data_sram_req    (data_sram_req   ),
    .data_sram_wr     (data_sram_wr    ),
    .data_sram_size   (data_sram_size  ),
    .data_sram_wstrb  (data_sram_wstrb ),
    .data_sram_addr   (data_sram_addr  ),
    .data_sram_wdata  (data_sram_wdata ),
    .data_sram_uncached(data_sram_uncached),
    .data_sram_addr_ok(data_sram_addr_ok),
    .data_sram_data_ok(data_sram_data_ok),
    .data_sram_rdata  (data_sram_rdata ),
    .cacop_valid      (cacop_valid      ),
    .cacop_is_dcache  (cacop_is_dcache  ),
    .cacop_op         (cacop_op         ),
    .cacop_index      (cacop_index      ),
    .cacop_way        (cacop_way        ),
    .cacop_tag        (cacop_tag        ),
    .cacop_ok         (cacop_ok         ),
    .barrier_req      (barrier_req      ),
    .barrier_is_ibar  (barrier_is_ibar  ),
    .barrier_done     (barrier_done     ),
    .ibar_flush       (ibar_flush       ),
    .ibar_target      (ibar_target      ),
    .idle_wait        (idle_wait        ),
    .ex3_producer_packet(ex3_producer_packet),
    .commit_lane_valid(commit_lane_valid),
    .commit_lane_seq_id(commit_lane_seq_id),
    .commit_lane_id(commit_lane_id),
    .flush            (flush            ),
    .ex_entry_in      (ex_entry_from_ex2 ),
    .ex_entry         (ex_entry         ),
    .ex3_wb_ex        (ex3_wb_ex        ),
    .ex3_wb_ecode     (ex3_wb_ecode     ),
    .ex3_wb_esubcode  (ex3_wb_esubcode  ),
    .ex3_wb_pc        (ex3_wb_pc        ),
    .ex3_wb_badv      (ex3_wb_badv      ),
    .ertn_flush       (ertn_flush       ),
    .ertn_pc_in       (ertn_pc_from_ex2  ),
    .ertn_pc          (ertn_pc          ),
    .redirect_seq_id  (commit_redirect_seq_id),
    .redirect_epoch   (commit_redirect_epoch),
    .ex3_csr_we       (ex3_csr_we       ),
    .ex3_csr_num      (ex3_csr_num      ),
    .ex3_is_ertn      (ex3_is_ertn      ),
    .cnt_low_now      (ex2_cnt_low      ),
    .cnt_high_now     (ex2_cnt_high     ),
    .tid_now          (ex2_tid          ),
    .has_int_now      (ex2_has_int      ),
    .sc_query_line    (sc_query_line    ),
    .sc_query_cached  (sc_query_cached  ),
    .sc_can_store     (sc_can_store     ),
    .priv_commit_bus  (priv_commit_bus  ),
    .ex3_tlb_pending  (ex3_tlb_pending  ),
    .bp_update_valid  (bp_update_valid  ),
    .bp_update_pc     (bp_update_pc     ),
    .bp_update_taken  (bp_update_taken  ),
    .bp_update_target (bp_update_target ),
    .bp_update_type   (bp_update_type   ),
    .bp_update_meta   (bp_update_meta   ),
    .bp_update_was_predicted(bp_update_was_predicted),
    .bp_update_mispredict(bp_update_mispredict)
);

// MEM stage
mem_stage mem_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    .ms_to_ws_ready (mem_to_wb_ready),
    .ex3_to_mem_ready(ex3_to_mem_ready),
    .ms_empty       (ms_empty       ),
    // from Commit/EX3
    .ex3_to_mem_valid(ex3_to_mem_valid),
    .ex3_to_mem_bus (ex3_to_mem_bus ),
    //to ws
    .ms_to_ws_valid (ms_to_ws_valid ),
    .ms_to_ws_bus   (ms_to_ws_bus   ),
    //from data-sram
    .data_sram_data_ok(data_sram_data_ok),
    .data_sram_rdata(data_sram_rdata),
    .ll_commit_valid(ll_commit_valid),
    .sc_commit_valid(sc_commit_valid),
    .local_store_commit_valid(local_store_commit_valid),
    .mem_commit_line(mem_commit_line),
    .mem_producer_packet(mem_producer_packet)
);

// WB stage
wb_stage wb_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    .ms_to_ws_ready (mem_to_wb_ready),
    .ws_empty       (ws_empty       ),
    //from ms
    .ms_to_ws_valid (ms_to_ws_valid ),
    .ms_to_ws_bus   (ms_to_ws_bus   ),
    //to rf: for write back
    .ws_to_rf_bus   (ws_to_rf_bus   ),
    .wb_producer_packet(wb_producer_packet),
    // trace debug interface
    .debug_wb_pc      (debug_wb_pc      ),
    .debug_wb_rf_we   (debug_wb_rf_we   ),
    .debug_wb_rf_wnum (debug_wb_rf_wnum ),
    .debug_wb_rf_wdata(debug_wb_rf_wdata)
);

companion_lane u_companion_lane(
    .clk               (clk),
    .reset             (reset),
    .kill_execute      (flush || ertn_flush || ibar_flush),
    .issue_valid       (lane1_issue_valid && id_to_ex1_valid),
    .issue_packet      (issue_lane1_bus),
    .issue_to_ex1_ready(issue_to_ex1_ready),
    .lane0_ex1_valid   (ex1_to_ex2_valid),
    .ex1_to_ex2_ready  (ex1_to_ex2_ready),
    .lane0_ex2_valid   (ex2_to_ex3_valid),
    .ex2_to_ex3_ready  (ex2_to_ex3_ready),
    .lane0_ex3_valid   (ex3_to_mem_valid),
    .ex3_to_mem_ready  (ex3_to_mem_ready),
    .lane0_mem_valid   (ms_to_ws_valid),
    .mem_to_wb_ready   (mem_to_wb_ready),
    .ws_to_rf_bus      (ws1_to_rf_bus),
    .ex1_producer      (lane1_ex1_producer_packet),
    .ex2_producer      (lane1_ex2_producer_packet),
    .ex3_producer      (lane1_ex3_producer_packet),
    .mem_producer      (lane1_mem_producer_packet),
    .wb_producer       (lane1_wb_producer_packet),
    .wb_valid          (lane1_wb_valid),
    .wb_pc             (lane1_wb_pc),
    .wb_instr          (lane1_wb_instr),
    .wb_rf_we          (lane1_wb_rf_we),
    .wb_rf_waddr       (lane1_wb_rf_waddr),
    .wb_rf_wdata       (lane1_wb_rf_wdata)
);

/*
// Baseline performance counters.  They are intentionally kept inside
// mycpu_core so simulation, ILA or a later CSR mapping can observe the same
// definitions without changing the architectural interface.
(* keep = "true" *) reg [63:0] cycle_count;
(* keep = "true" *) reg [63:0] commit_count;
(* keep = "true" *) reg [63:0] frontend_empty_cycles;
(* keep = "true" *) reg [63:0] fetch_queue_full_cycles;
(* keep = "true" *) reg [63:0] issue_stall_data_cycles;
(* keep = "true" *) reg [63:0] issue_stall_struct_cycles;
(* keep = "true" *) reg [63:0] dual_issue_count;
(* keep = "true" *) reg [63:0] branch_count;
(* keep = "true" *) reg [63:0] mispredict_count;
(* keep = "true" *) reg [63:0] icache_miss_count;
(* keep = "true" *) reg [63:0] dcache_miss_count;
(* keep = "true" *) reg [63:0] fetch_request_count;
(* keep = "true" *) reg [63:0] fetch_response_count;
(* keep = "true" *) reg [63:0] redirect_count;
(* keep = "true" *) reg [63:0] wrong_epoch_drop_count;
(* keep = "true" *) reg [63:0] bp_update_count;
// Register cache events before the wide counters.  This prevents synthesis
// from sharing the 64-bit increment enable with the cache hit/LRU cone.
reg icache_miss_event_d;
reg dcache_miss_event_d;

always @(posedge clk) begin
    if (reset) begin
        cycle_count              <= 64'b0;
        commit_count             <= 64'b0;
        frontend_empty_cycles    <= 64'b0;
        fetch_queue_full_cycles  <= 64'b0;
        issue_stall_data_cycles  <= 64'b0;
        issue_stall_struct_cycles<= 64'b0;
        dual_issue_count          <= 64'b0;
        branch_count             <= 64'b0;
        mispredict_count         <= 64'b0;
        icache_miss_count        <= 64'b0;
        dcache_miss_count        <= 64'b0;
        fetch_request_count      <= 64'b0;
        fetch_response_count     <= 64'b0;
        redirect_count           <= 64'b0;
        wrong_epoch_drop_count   <= 64'b0;
        bp_update_count          <= 64'b0;
        icache_miss_event_d      <= 1'b0;
        dcache_miss_event_d      <= 1'b0;
    end
    else begin
        icache_miss_event_d <= icache_miss_event;
        dcache_miss_event_d <= dcache_miss_event;
        cycle_count <= cycle_count + 64'd1;
        if (!ws_empty || lane1_wb_valid)
            commit_count <= commit_count +
                            ((!ws_empty && lane1_wb_valid) ? 64'd2 : 64'd1);
        if (!fetch_queue_to_decode_valid)
            frontend_empty_cycles <= frontend_empty_cycles + 64'd1;
        if (fetch_queue_occupancy == 3'd4)
            fetch_queue_full_cycles <= fetch_queue_full_cycles + 64'd1;
        if (issue_stall_data)
            issue_stall_data_cycles <= issue_stall_data_cycles + 64'd1;
        if (issue_stall_struct)
            issue_stall_struct_cycles <= issue_stall_struct_cycles + 64'd1;
        if (issue_lane_valid == 2'b11 && issue_lane_ready == 2'b11)
            dual_issue_count <= dual_issue_count + 64'd1;
        if (branch_resolve_fire)
            branch_count <= branch_count + 64'd1;
        if (ex1_redirect_valid)
            mispredict_count <= mispredict_count + 64'd1;
        if (icache_miss_event_d)
            icache_miss_count <= icache_miss_count + 64'd1;
        if (dcache_miss_event_d)
            dcache_miss_count <= dcache_miss_count + 64'd1;
        if (inst_sram_req && inst_sram_addr_ok)
            fetch_request_count <= fetch_request_count + 64'd1;
        if (inst_sram_data_ok)
            fetch_response_count <= fetch_response_count + 64'd1;
        if (redirect_valid)
            redirect_count <= redirect_count + 64'd1;
        if (wrong_epoch_drop_event)
            wrong_epoch_drop_count <= wrong_epoch_drop_count + 64'd1;
        if (bp_update_valid)
            bp_update_count <= bp_update_count + 64'd1;
    end
end*/

`ifdef SIMU
// Keep the instruction and side-effect information beside the normal
// pipeline. The architectural state is reported one cycle after WB so that
// the register-file nonblocking write has already taken effect.
reg [31:0] diff_ms_instr;
reg        diff_ms_valid;
reg [31:0] diff_ms_paddr;
reg [31:0] diff_ms_vaddr;
reg [63:0] diff_ms_store_data;
reg [ 7:0] diff_ms_store_valid;
reg [ 7:0] diff_ms_load_valid;
reg        diff_ms_excp;
reg        diff_ms_ertn;
reg [ 5:0] diff_ms_ecode;
reg [31:0] diff_ms_estat;
reg        diff_ms_tlbfill;
reg [ 4:0] diff_ms_tlbfill_index;
reg        diff_ms_cntinst;
reg [63:0] diff_ms_timer;
reg        diff_ms_csr_rstat;
reg [31:0] diff_ms_csr_data;

reg [31:0] diff_ws_instr;
reg        diff_ws_valid;
reg [31:0] diff_ws_paddr;
reg [31:0] diff_ws_vaddr;
reg [63:0] diff_ws_store_data;
reg [ 7:0] diff_ws_store_valid;
reg [ 7:0] diff_ws_load_valid;
reg        diff_ws_excp;
reg        diff_ws_ertn;
reg [ 5:0] diff_ws_ecode;
reg [31:0] diff_ws_estat;
reg        diff_ws_tlbfill;
reg [ 4:0] diff_ws_tlbfill_index;
reg        diff_ws_cntinst;
reg [63:0] diff_ws_timer;
reg        diff_ws_csr_rstat;
reg [31:0] diff_ws_csr_data;
reg [ 2:0] diff_ws_llbctl;

reg        diff_commit_valid;
reg [31:0] diff_commit_pc;
reg [31:0] diff_commit_instr;
reg        diff_commit_wen;
reg [ 4:0] diff_commit_wdest;
reg [31:0] diff_commit_wdata;
reg        diff_commit_tlbfill;
reg [ 4:0] diff_commit_tlbfill_index;
reg [ 2:0] diff_commit_llbctl;
reg        diff_commit_cntinst;
reg [63:0] diff_commit_timer;
reg        diff_commit_csr_rstat;
reg [31:0] diff_commit_csr_data;
reg        diff_commit1_valid;
reg [31:0] diff_commit1_pc;
reg [31:0] diff_commit1_instr;
reg        diff_commit1_wen;
reg [ 4:0] diff_commit1_wdest;
reg [31:0] diff_commit1_wdata;
reg [ 5:0] diff_excp_ecode;
reg [31:0] diff_excp_pc;
reg [31:0] diff_excp_instr;
reg [31:0] diff_excp_estat;
reg [10:0] diff_excp_intr;
reg        diff_excp_pending;
reg        diff_excp_wait_commit;
reg [ 7:0] diff_store_valid;
reg [31:0] diff_store_paddr;
reg [31:0] diff_store_vaddr;
reg [63:0] diff_store_data;
reg [ 7:0] diff_load_valid;
reg [31:0] diff_load_paddr;
reg [31:0] diff_load_vaddr;

wire [31:0] diff_ex2_current_instr = ex3_stage.es_inst;
wire [5:0] diff_mem_opcode = diff_ex2_current_instr[31:26];
wire [3:0] diff_mem_subop  = diff_ex2_current_instr[25:22];
wire       diff_is_ld_b    = (diff_mem_opcode == 6'h0a) && (diff_mem_subop == 4'h0);
wire       diff_is_ld_h    = (diff_mem_opcode == 6'h0a) && (diff_mem_subop == 4'h1);
wire       diff_is_ld_w    = (diff_mem_opcode == 6'h0a) && (diff_mem_subop == 4'h2);
wire       diff_is_st_b    = (diff_mem_opcode == 6'h0a) && (diff_mem_subop == 4'h4);
wire       diff_is_st_h    = (diff_mem_opcode == 6'h0a) && (diff_mem_subop == 4'h5);
wire       diff_is_st_w    = (diff_mem_opcode == 6'h0a) && (diff_mem_subop == 4'h6);
wire       diff_is_ld_bu   = (diff_mem_opcode == 6'h0a) && (diff_mem_subop == 4'h8);
wire       diff_is_ld_hu   = (diff_mem_opcode == 6'h0a) && (diff_mem_subop == 4'h9);
wire       diff_is_ll_w    = diff_ex2_current_instr[31:24] == 8'h20;
wire       diff_is_sc_w    = diff_ex2_current_instr[31:24] == 8'h21;
wire       diff_ex2_idle   = (diff_ex2_current_instr[31:15] == 17'h0c91);
wire       diff_ws_idle    = (diff_ws_instr[31:15] == 17'h0c91);
wire       diff_ex2_idle_int = diff_ex2_idle && ex3_stage.ex_int;
wire       diff_ws_idle_int  = diff_ws_idle && (diff_ws_ecode == `ECODE_INT);
wire       diff_is_store = diff_is_st_b || diff_is_st_h || diff_is_st_w ||
                           (diff_is_sc_w && ex3_stage.sc_success);
wire       diff_is_load  = diff_is_ld_b || diff_is_ld_h || diff_is_ld_w ||
                           diff_is_ld_bu || diff_is_ld_hu || diff_is_ll_w;
wire [3:0] diff_ex2_store_wstrb =
           diff_is_st_b ? (4'b0001 << ex3_stage.data_vaddr[1:0]) :
           diff_is_st_h ? (ex3_stage.data_vaddr[1] ? 4'b1100 : 4'b0011) :
           (diff_is_st_w || (diff_is_sc_w && ex3_stage.sc_success)) ? 4'b1111 :
                                                                       4'b0000;
wire [31:0] diff_ex2_store_data32 =
            ex3_stage.data_sram_wdata &
            {{8{diff_ex2_store_wstrb[3]}},
             {8{diff_ex2_store_wstrb[2]}},
             {8{diff_ex2_store_wstrb[1]}},
             {8{diff_ex2_store_wstrb[0]}}};
wire [63:0] diff_ex2_store_data =
            {32'b0, diff_ex2_store_data32};
wire [3:0] diff_ex2_load_wstrb =
           (diff_is_ld_b || diff_is_ld_bu) ? (4'b0001 << ex3_stage.data_vaddr[1:0]) :
           (diff_is_ld_h || diff_is_ld_hu) ? (ex3_stage.data_vaddr[1] ? 4'b1100 : 4'b0011) :
           (diff_is_ld_w || diff_is_ll_w)  ? 4'b1111 :
                                             4'b0000;
wire       diff_ex2_store_fire = diff_is_store && ex3_stage.es_mem_access &&
                                 ex3_stage.actual_mem_we;
wire       diff_ex2_load_fire  = diff_is_load && ex3_stage.es_mem_access &&
                                 ex3_stage.res_from_mem;
wire [7:0] diff_ex2_store_valid = diff_ex2_store_fire ? (ex3_stage.data_paddr[2] ?
                                                        {diff_ex2_store_wstrb, 4'b0} :
                                                        {4'b0, diff_ex2_store_wstrb}) : 8'b0;
wire [7:0] diff_ex2_load_valid  = diff_ex2_load_fire  ? (ex3_stage.data_paddr[2] ?
                                                        {diff_ex2_load_wstrb, 4'b0} :
                                                        {4'b0, diff_ex2_load_wstrb}) : 8'b0;
wire       diff_excp_fire = diff_excp_pending && !diff_excp_wait_commit;
wire       diff_wb_side_valid = wb_stage.ws_valid && diff_ws_valid;
wire [31:0] diff_event_pc;
wire [31:0] diff_event_instr;
wire       diff_reservation_valid_after_mem =
           ll_commit_valid               ? 1'b1 :
           u_llsc_unit.reservation_clear ? 1'b0 :
                                           reservation_valid;
// The privileged-state write and the difftest snapshot retire on the same
// edge.  Include an LLBCTL write in the value reported for that instruction;
// sampling llbctl_klo alone would expose the pre-commit value for one cycle.
wire       diff_llbctl_klo_after_mem =
           ex2_stage.csr_write_fire &&
           (ex2_stage.commit_csr_num == 14'h60) &&
           ex2_stage.commit_csr_wmask[2] ? ex2_stage.commit_csr_wvalue[2] :
                                           llbctl_klo;

always @(posedge clk) begin
    if (reset) begin
        diff_ms_instr          <= 32'b0;
        diff_ms_valid          <= 1'b0;
        diff_ms_paddr          <= 32'b0;
        diff_ms_vaddr          <= 32'b0;
        diff_ms_store_data     <= 32'b0;
        diff_ms_store_valid    <= 8'b0;
        diff_ms_load_valid     <= 8'b0;
        diff_ms_excp           <= 1'b0;
        diff_ms_ertn           <= 1'b0;
        diff_ms_ecode          <= 6'b0;
        diff_ms_estat          <= 32'b0;
        diff_ms_tlbfill        <= 1'b0;
        diff_ms_tlbfill_index  <= 5'b0;
        diff_ms_cntinst        <= 1'b0;
        diff_ms_timer          <= 64'b0;
        diff_ms_csr_rstat      <= 1'b0;
        diff_ms_csr_data       <= 32'b0;
        diff_ws_instr          <= 32'b0;
        diff_ws_valid          <= 1'b0;
        diff_ws_paddr          <= 32'b0;
        diff_ws_vaddr          <= 32'b0;
        diff_ws_store_data     <= 32'b0;
        diff_ws_store_valid    <= 8'b0;
        diff_ws_load_valid     <= 8'b0;
        diff_ws_excp           <= 1'b0;
        diff_ws_ertn           <= 1'b0;
        diff_ws_ecode          <= 6'b0;
        diff_ws_estat          <= 32'b0;
        diff_ws_tlbfill        <= 1'b0;
        diff_ws_tlbfill_index  <= 5'b0;
        diff_ws_cntinst        <= 1'b0;
        diff_ws_timer          <= 64'b0;
        diff_ws_csr_rstat      <= 1'b0;
        diff_ws_csr_data       <= 32'b0;
        diff_ws_llbctl         <= 3'b0;
        diff_commit_valid      <= 1'b0;
        diff_commit_pc         <= 32'b0;
        diff_commit_instr      <= 32'b0;
        diff_commit_wen        <= 1'b0;
        diff_commit_wdest      <= 5'b0;
        diff_commit_wdata      <= 32'b0;
        diff_commit_tlbfill    <= 1'b0;
        diff_commit_tlbfill_index <= 5'b0;
        diff_commit_llbctl     <= 3'b0;
        diff_commit_cntinst    <= 1'b0;
        diff_commit_timer      <= 64'b0;
        diff_commit_csr_rstat  <= 1'b0;
        diff_commit_csr_data   <= 32'b0;
        diff_commit1_valid     <= 1'b0;
        diff_commit1_pc        <= 32'b0;
        diff_commit1_instr     <= 32'b0;
        diff_commit1_wen       <= 1'b0;
        diff_commit1_wdest     <= 5'b0;
        diff_commit1_wdata     <= 32'b0;
        diff_excp_ecode        <= 6'b0;
        diff_excp_pc           <= 32'b0;
        diff_excp_instr        <= 32'b0;
        diff_excp_estat        <= 32'b0;
        diff_excp_intr         <= 11'b0;
        diff_excp_pending      <= 1'b0;
        diff_excp_wait_commit  <= 1'b0;
        diff_store_valid       <= 8'b0;
        diff_store_paddr       <= 32'b0;
        diff_store_vaddr       <= 32'b0;
        diff_store_data        <= 32'b0;
        diff_load_valid        <= 8'b0;
        diff_load_paddr        <= 32'b0;
        diff_load_vaddr        <= 32'b0;
    end
    else begin
        if (ex3_to_mem_valid && ex3_to_mem_ready) begin
            diff_ms_valid         <= 1'b1;
            diff_ms_instr         <= diff_ex2_current_instr;
            diff_ms_paddr         <= ex3_stage.data_paddr;
            diff_ms_vaddr         <= ex3_stage.data_vaddr;
            diff_ms_store_data    <= diff_ex2_store_data;
            diff_ms_store_valid   <= diff_ex2_store_valid;
            diff_ms_load_valid    <= diff_ex2_load_valid;
            diff_ms_excp          <= ex3_stage.wb_ex;
            diff_ms_ertn          <= ex3_stage.ertn_flush;
            diff_ms_ecode         <= ex3_stage.wb_ecode;
            diff_ms_estat         <= ex2_stage.u_csr_regfile.estat;
            diff_ms_tlbfill       <= ex3_stage.tlbfill_fire;
            diff_ms_tlbfill_index <= ex3_stage.tlb_write_index;
            diff_ms_cntinst       <= ex3_stage.ds_rdcntv || ex3_stage.ds_rdcntid;
            diff_ms_timer         <= {ex3_stage.cnt_high_sample,
                                      ex3_stage.cnt_low_sample};
            diff_ms_csr_rstat     <= ex3_stage.is_csr &&
                                     (ex3_stage.csr_num == 14'h005);
            diff_ms_csr_data      <= ex3_stage.csr_rvalue;
        end
        else if (ex3_to_mem_ready) begin
            diff_ms_valid         <= 1'b0;
        end

        if (ms_to_ws_valid && mem_to_wb_ready) begin
            diff_ws_valid         <= diff_ms_valid;
            diff_ws_instr         <= diff_ms_instr;
            diff_ws_paddr         <= diff_ms_paddr;
            diff_ws_vaddr         <= diff_ms_vaddr;
            diff_ws_store_data    <= diff_ms_store_data;
            diff_ws_store_valid   <= diff_ms_store_valid;
            diff_ws_load_valid    <= diff_ms_load_valid;
            diff_ws_excp          <= diff_ms_excp;
            diff_ws_ertn          <= diff_ms_ertn;
            diff_ws_ecode         <= diff_ms_ecode;
            diff_ws_estat         <= diff_ms_estat;
            diff_ws_tlbfill       <= diff_ms_tlbfill;
            diff_ws_tlbfill_index <= diff_ms_tlbfill_index;
            diff_ws_cntinst       <= diff_ms_cntinst;
            diff_ws_timer         <= diff_ms_timer;
            diff_ws_csr_rstat     <= diff_ms_csr_rstat;
            diff_ws_csr_data      <= diff_ms_csr_data;
            diff_ws_llbctl        <= {diff_llbctl_klo_after_mem, 1'b0,
                                      diff_reservation_valid_after_mem};
        end
        else if (mem_to_wb_ready) begin
            diff_ws_valid         <= 1'b0;
        end

        // IDLE retires before its wake-up interrupt is reported. Without this
        // commit, the reference model takes the interrupt at the IDLE PC and
        // observes ERA four bytes behind the DUT.
        diff_commit_valid         <= diff_wb_side_valid &&
                                     (!diff_ws_excp || diff_ws_idle_int);
        diff_commit_pc            <= wb_stage.ws_pc;
        diff_commit_instr         <= diff_ws_instr;
        diff_commit_wen           <= wb_stage.rf_we;
        diff_commit_wdest         <= wb_stage.rf_waddr;
        diff_commit_wdata         <= wb_stage.rf_wdata;
        diff_commit_tlbfill       <= diff_ws_tlbfill;
        diff_commit_tlbfill_index <= diff_ws_tlbfill_index;
        diff_commit_llbctl        <= diff_ws_llbctl;
        diff_commit_cntinst       <= diff_ws_cntinst;
        diff_commit_timer         <= diff_ws_timer;
        diff_commit_csr_rstat     <= diff_ws_csr_rstat;
        diff_commit_csr_data      <= diff_ws_csr_data;
        diff_commit1_valid        <= lane1_wb_valid;
        diff_commit1_pc           <= lane1_wb_pc;
        diff_commit1_instr        <= lane1_wb_instr;
        diff_commit1_wen          <= lane1_wb_rf_we;
        diff_commit1_wdest        <= lane1_wb_rf_waddr;
        diff_commit1_wdata        <= lane1_wb_rf_wdata;

        if (ex3_stage.wb_ex) begin
            diff_excp_pending     <= 1'b1;
            diff_excp_wait_commit <= diff_ex2_idle_int;
            diff_excp_ecode       <= ex3_stage.wb_ecode;
            diff_excp_pc          <= ex3_stage.wb_pc;
            diff_excp_instr       <= diff_ex2_current_instr;
            diff_excp_estat       <= ex2_stage.u_csr_regfile.estat;
            diff_excp_intr        <= ex3_stage.ex_int ?
                                     ex2_stage.u_csr_regfile.estat_is_hw[12:2] :
                                     ex2_stage.u_csr_regfile.estat[12:2];
        end
        else if (diff_excp_pending && diff_excp_wait_commit &&
                 diff_wb_side_valid && diff_ws_excp && diff_ws_idle_int) begin
            diff_excp_wait_commit <= 1'b0;
        end
        else if (diff_excp_fire) begin
            diff_excp_pending     <= 1'b0;
            diff_excp_wait_commit <= 1'b0;
        end

        diff_store_valid <= (diff_wb_side_valid && !diff_ws_excp)
                          ? diff_ws_store_valid : 8'b0;
        diff_store_paddr <= diff_ws_paddr;
        diff_store_vaddr <= diff_ws_vaddr;
        diff_store_data  <= diff_ws_store_data;
        diff_load_valid  <= (diff_wb_side_valid && !diff_ws_excp)
                          ? diff_ws_load_valid : 8'b0;
        diff_load_paddr  <= diff_ws_paddr;
        diff_load_vaddr  <= diff_ws_vaddr;
    end
end

DifftestExcpEvent u_difftest_excp_event(
    .clock         (clk),
    .coreid        (8'd0),
    .excp_valid    (diff_excp_fire),
    .eret          (1'b0),
    .intrNo        ({21'b0, diff_excp_intr}),
    .cause         ({26'b0, diff_excp_ecode}),
    .exceptionPC   ({32'b0, diff_event_pc}),
    .exceptionInst (diff_event_instr)
);

assign diff_event_pc    = diff_excp_pc;
assign diff_event_instr = diff_excp_instr;

DifftestInstrCommit u_difftest_instr_commit(
    .clock          (clk),
    .coreid         (8'd0),
    .index          (8'd0),
    .valid          (diff_commit_valid),
    .pc             ({32'b0, diff_commit_pc}),
    .instr          (diff_commit_instr),
    .skip           (1'b0),
    .is_TLBFILL     (diff_commit_tlbfill),
    .TLBFILL_index  (diff_commit_tlbfill_index),
    .is_CNTinst     (diff_commit_cntinst),
    .timer_64_value (diff_commit_timer),
    .wen            (diff_commit_wen),
    .wdest          ({3'b0, diff_commit_wdest}),
    .wdata          ({32'b0, diff_commit_wdata}),
    .csr_rstat      (diff_commit_csr_rstat),
    .csr_data       (diff_commit_csr_data)
);

DifftestInstrCommit u_difftest_instr_commit_lane1(
    .clock          (clk),
    .coreid         (8'd0),
    .index          (8'd1),
    .valid          (diff_commit1_valid),
    .pc             ({32'b0, diff_commit1_pc}),
    .instr          (diff_commit1_instr),
    .skip           (1'b0),
    .is_TLBFILL     (1'b0),
    .TLBFILL_index  (5'b0),
    .is_CNTinst     (1'b0),
    .timer_64_value (64'b0),
    .wen            (diff_commit1_wen),
    .wdest          ({3'b0, diff_commit1_wdest}),
    .wdata          ({32'b0, diff_commit1_wdata}),
    .csr_rstat      (1'b0),
    .csr_data       (32'b0)
);

DifftestTrapEvent u_difftest_trap_event(
    .clock    (clk),
    .coreid   (8'd0),
    .valid    (1'b0),
    .code     (3'b0),
    .pc       (64'b0),
    .cycleCnt (64'b0),
    .instrCnt (64'b0)
);

DifftestStoreEvent u_difftest_store_event(
    .clock      (clk),
    .coreid     (8'd0),
    .index      (8'd0),
    .valid      (diff_store_valid),
    .storePAddr ({32'b0, diff_store_paddr}),
    .storeVAddr ({32'b0, diff_store_vaddr}),
    .storeData  (diff_store_data)
);

DifftestLoadEvent u_difftest_load_event(
    .clock  (clk),
    .coreid (8'd0),
    .index  (8'd0),
    .valid  (diff_load_valid),
    .paddr  ({32'b0, diff_load_paddr}),
    .vaddr  ({32'b0, diff_load_vaddr})
);

DifftestCSRRegState u_difftest_csr_state(
    .clock      (clk),
    .coreid     (8'd0),
    .crmd       ({32'b0, ex2_stage.u_csr_regfile.crmd}),
    .prmd       ({32'b0, ex2_stage.u_csr_regfile.prmd}),
    .euen       (64'b0),
    .ecfg       ({32'b0, ex2_stage.u_csr_regfile.ecfg}),
    .estat      ({32'b0, ex2_stage.u_csr_regfile.estat}),
    .era        ({32'b0, ex2_stage.u_csr_regfile.era}),
    .badv       ({32'b0, ex2_stage.u_csr_regfile.badv}),
    .eentry     ({32'b0, ex2_stage.u_csr_regfile.eentry}),
    .tlbidx     ({32'b0, ex2_stage.u_csr_regfile.tlbidx}),
    .tlbehi     ({32'b0, ex2_stage.u_csr_regfile.tlbehi}),
    .tlbelo0    ({32'b0, ex2_stage.u_csr_regfile.tlbelo0}),
    .tlbelo1    ({32'b0, ex2_stage.u_csr_regfile.tlbelo1}),
    .asid       ({32'b0, 8'b0, 8'd10, 6'b0, ex2_stage.u_csr_regfile.asid}),
    .pgdl       ({32'b0, ex2_stage.u_csr_regfile.pgdl}),
    .pgdh       ({32'b0, ex2_stage.u_csr_regfile.pgdh}),
    .save0      ({32'b0, ex2_stage.u_csr_regfile.save0}),
    .save1      ({32'b0, ex2_stage.u_csr_regfile.save1}),
    .save2      ({32'b0, ex2_stage.u_csr_regfile.save2}),
    .save3      ({32'b0, ex2_stage.u_csr_regfile.save3}),
    .tid        ({32'b0, ex2_stage.u_csr_regfile.tid}),
    .tcfg       ({32'b0, ex2_stage.u_csr_regfile.tcfg}),
    .tval       ({32'b0, ex2_stage.u_csr_regfile.tval}),
    .ticlr      (64'b0),
    // LLBCTL[0] is the architectural LLBit and can change on LL/SC,
    // invalidation, exception return, or WCLLB without a GPR writeback.
    // Report the live committed reservation state instead of a WB-delayed
    // snapshot, which can miss those transitions in difftest.
    .llbctl     ({61'b0, llbctl_klo, 1'b0, reservation_valid}),
    .tlbrentry  ({32'b0, ex2_stage.u_csr_regfile.tlbrentry}),
    .dmw0       ({32'b0, ex2_stage.u_csr_regfile.dmw0}),
    .dmw1       ({32'b0, ex2_stage.u_csr_regfile.dmw1})
);

// The testbench may sample difftest only once every several clocks.  Export
// the architectural state at retirement instead of the speculative live
// register file, which can already contain younger dual-issue writebacks.
reg [31:0] diff_retired_gpr [0:31];
integer diff_gpr_i;
always @(posedge clk) begin
    if (reset) begin
        for (diff_gpr_i = 0; diff_gpr_i < 32;
             diff_gpr_i = diff_gpr_i + 1)
            diff_retired_gpr[diff_gpr_i] <= 32'b0;
    end
    else begin
        diff_retired_gpr[0] <= 32'b0;
        if (diff_wb_side_valid && (!diff_ws_excp || diff_ws_idle_int) &&
            wb_stage.rf_we && (wb_stage.rf_waddr != 5'b0))
            diff_retired_gpr[wb_stage.rf_waddr] <= wb_stage.rf_wdata;
        // Lane1 is younger, so it wins a same-cycle WAW pair.
        if (lane1_wb_valid && lane1_wb_rf_we &&
            (lane1_wb_rf_waddr != 5'b0))
            diff_retired_gpr[lane1_wb_rf_waddr] <= lane1_wb_rf_wdata;

    end
end

DifftestGRegState u_difftest_gpr_state(
    .clock (clk), .coreid(8'd0),
    .gpr_0 (64'b0),
    .gpr_1 ({32'b0, diff_retired_gpr[1]}),
    .gpr_2 ({32'b0, diff_retired_gpr[2]}),
    .gpr_3 ({32'b0, diff_retired_gpr[3]}),
    .gpr_4 ({32'b0, diff_retired_gpr[4]}),
    .gpr_5 ({32'b0, diff_retired_gpr[5]}),
    .gpr_6 ({32'b0, diff_retired_gpr[6]}),
    .gpr_7 ({32'b0, diff_retired_gpr[7]}),
    .gpr_8 ({32'b0, diff_retired_gpr[8]}),
    .gpr_9 ({32'b0, diff_retired_gpr[9]}),
    .gpr_10({32'b0, diff_retired_gpr[10]}),
    .gpr_11({32'b0, diff_retired_gpr[11]}),
    .gpr_12({32'b0, diff_retired_gpr[12]}),
    .gpr_13({32'b0, diff_retired_gpr[13]}),
    .gpr_14({32'b0, diff_retired_gpr[14]}),
    .gpr_15({32'b0, diff_retired_gpr[15]}),
    .gpr_16({32'b0, diff_retired_gpr[16]}),
    .gpr_17({32'b0, diff_retired_gpr[17]}),
    .gpr_18({32'b0, diff_retired_gpr[18]}),
    .gpr_19({32'b0, diff_retired_gpr[19]}),
    .gpr_20({32'b0, diff_retired_gpr[20]}),
    .gpr_21({32'b0, diff_retired_gpr[21]}),
    .gpr_22({32'b0, diff_retired_gpr[22]}),
    .gpr_23({32'b0, diff_retired_gpr[23]}),
    .gpr_24({32'b0, diff_retired_gpr[24]}),
    .gpr_25({32'b0, diff_retired_gpr[25]}),
    .gpr_26({32'b0, diff_retired_gpr[26]}),
    .gpr_27({32'b0, diff_retired_gpr[27]}),
    .gpr_28({32'b0, diff_retired_gpr[28]}),
    .gpr_29({32'b0, diff_retired_gpr[29]}),
    .gpr_30({32'b0, diff_retired_gpr[30]}),
    .gpr_31({32'b0, diff_retired_gpr[31]})
);
`endif

endmodule
