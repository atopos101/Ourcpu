`include "mycpu.vh"

module mycpu_top(
    input           aclk,
    input           aresetn,
    input    [ 7:0] intrpt,

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
    input    [ 3:0] rid,
    input    [31:0] rdata,
    input    [ 1:0] rresp,
    input           rlast,
    input           rvalid,
    output          rready,

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
    output   [ 3:0] wid,
    output   [31:0] wdata,
    output   [ 3:0] wstrb,
    output          wlast,
    output          wvalid,
    input           wready,
    input    [ 3:0] bid,
    input    [ 1:0] bresp,
    input           bvalid,
    output          bready,

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
wire        core_inst_addr_ok;
wire        core_inst_data_ok;
wire [31:0] core_inst_rdata;

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

wire        uncache_req;
wire        uncache_wr;
wire [ 1:0] uncache_size;
wire [ 3:0] uncache_wstrb;
wire [31:0] uncache_addr;
wire [31:0] uncache_wdata;
wire        uncache_addr_ok;
wire        uncache_data_ok;
wire [31:0] uncache_rdata;

mycpu_core u_core(
    .clk                (aclk                ),
    .resetn             (aresetn             ),
    .hw_int_in          (intrpt              ),
    .inst_sram_req      (core_inst_req       ),
    .inst_sram_wr       (core_inst_wr        ),
    .inst_sram_size     (core_inst_size      ),
    .inst_sram_wstrb    (core_inst_wstrb     ),
    .inst_sram_addr     (core_inst_addr      ),
    .inst_sram_wdata    (core_inst_wdata     ),
    .inst_sram_addr_ok  (core_inst_addr_ok   ),
    .inst_sram_data_ok  (core_inst_data_ok   ),
    .inst_sram_rdata    (core_inst_rdata     ),
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
    .debug_wb_pc        (debug0_wb_pc        ),
    .debug_wb_rf_we     (debug0_wb_rf_wen    ),
    .debug_wb_rf_wnum   (debug0_wb_rf_wnum   ),
    .debug_wb_rf_wdata  (debug0_wb_rf_wdata  )
);

`ifdef CPU_2CMT
assign debug1_wb_pc       = 32'b0;
assign debug1_wb_rf_wen   = 4'b0;
assign debug1_wb_rf_wnum  = 5'b0;
assign debug1_wb_rf_wdata = 32'b0;
`endif

assign core_data_addr_ok = core_data_uncached ? uncache_addr_ok : dcache_addr_ok;
assign core_data_data_ok = uncache_data_ok || dcache_data_ok;
assign core_data_rdata   = uncache_data_ok ? uncache_rdata : dcache_rdata;
assign core_cacop_ok     = core_cacop_is_dcache ? dcache_cacop_ok : icache_cacop_ok;

assign uncache_req   = core_data_req && core_data_uncached;
assign uncache_wr    = core_data_wr;
assign uncache_size  = core_data_size;
assign uncache_wstrb = core_data_wstrb;
assign uncache_addr  = core_data_addr;
assign uncache_wdata = core_data_wdata;

icache u_icache(
    .clk                (aclk                ),
    .resetn             (aresetn             ),
    .valid              (core_inst_req       ),
    .op                 (1'b0                ),
    .index              (core_inst_addr[11:4]),
    .tag                (core_inst_addr[31:12]),
    .offset             (core_inst_addr[3:0] ),
    .wstrb              (4'b0                ),
    .wdata              (32'b0               ),
    .addr_ok            (core_inst_addr_ok   ),
    .data_ok            (core_inst_data_ok   ),
    .rdata              (core_inst_rdata     ),
    .cacop_valid        (core_cacop_valid && !core_cacop_is_dcache),
    .cacop_op           (core_cacop_op       ),
    .cacop_index        (core_cacop_index    ),
    .cacop_way          (core_cacop_way      ),
    .cacop_tag          (core_cacop_tag      ),
    .cacop_ok           (icache_cacop_ok     ),
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
    .valid              (core_data_req && !core_data_uncached),
    .op                 (core_data_wr        ),
    .index              (core_data_addr[11:4]),
    .tag                (core_data_addr[31:12]),
    .offset             (core_data_addr[3:0] ),
    .wstrb              (core_data_wstrb     ),
    .wdata              (core_data_wdata     ),
    .addr_ok            (dcache_addr_ok      ),
    .data_ok            (dcache_data_ok      ),
    .rdata              (dcache_rdata        ),
    .cacop_valid        (core_cacop_valid && core_cacop_is_dcache),
    .cacop_op           (core_cacop_op       ),
    .cacop_index        (core_cacop_index    ),
    .cacop_way          (core_cacop_way      ),
    .cacop_tag          (core_cacop_tag      ),
    .cacop_ok           (dcache_cacop_ok     ),
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

endmodule

module mycpu_core(
    input         clk,
    input         resetn,
    // 8 external hardware interrupt lines (tie to 0 if unused)
    input  [7:0]  hw_int_in,
    // inst sram interface (bus-style)
    output        inst_sram_req,
    output        inst_sram_wr,
    output [ 1:0] inst_sram_size,
    output [ 3:0] inst_sram_wstrb,
    output [31:0] inst_sram_addr,
    output [31:0] inst_sram_wdata,
    input         inst_sram_addr_ok,
    input         inst_sram_data_ok,
    input  [31:0] inst_sram_rdata,
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

wire         ds_allowin;
wire         es_allowin;
wire         ms_allowin;
wire         ws_allowin;
wire         fs_to_ds_valid;
wire         ds_to_es_valid;
wire         es_to_ms_valid;
wire         ms_to_ws_valid;
wire [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus;
wire [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus;
wire [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus;
wire [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus;
wire [`WS_TO_RF_BUS_WD -1:0] ws_to_rf_bus;
wire [`BR_BUS_WD       -1:0] br_bus;
wire [4:0] es_to_ds_dest;
wire [4:0] ms_to_ds_dest;
wire [4:0] ws_to_ds_dest;
wire       es_to_ds_load_op;
wire       ms_to_ds_load_op;
wire [4:0] ms_to_ds_load_dest;
wire [31:0] es_to_ds_result;
wire [31:0] ms_to_ds_result;
wire [31:0] ws_to_ds_result;
wire [31:0] inst_vaddr;
wire [31:0] inst_paddr;
wire        inst_trans_ex;
wire [ 5:0] inst_trans_ecode;
wire [ 8:0] inst_trans_esubcode;

// exception interface
wire        flush;
wire [31:0] ex_entry;

// ertn interface
wire        ertn_flush;
wire [31:0] ertn_pc;

// csr hazard tracking
wire        es_csr_we;
wire [13:0] es_csr_num;
wire        es_is_ertn;

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

// IF stage
if_stage if_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ds_allowin     (ds_allowin     ),
    //brbus
    .br_bus         (br_bus         ),
    // exception
    .flush          (flush          ),
    .ex_entry       (ex_entry       ),
    // ertn
    .ertn_flush     (ertn_flush     ),
    .ertn_pc        (ertn_pc        ),
    // address translation
    .inst_vaddr     (inst_vaddr     ),
    .inst_paddr     (inst_paddr     ),
    .inst_trans_ex  (inst_trans_ex  ),
    .inst_trans_ecode(inst_trans_ecode),
    .inst_trans_esubcode(inst_trans_esubcode),
    //outputs
    .fs_to_ds_valid (fs_to_ds_valid ),
    .fs_to_ds_bus   (fs_to_ds_bus   ),
    // inst sram interface
    .inst_sram_req    (inst_sram_req   ),
    .inst_sram_wr     (inst_sram_wr    ),
    .inst_sram_size   (inst_sram_size  ),
    .inst_sram_wstrb  (inst_sram_wstrb ),
    .inst_sram_addr   (inst_sram_addr  ),
    .inst_sram_wdata  (inst_sram_wdata ),
    .inst_sram_addr_ok(inst_sram_addr_ok),
    .inst_sram_data_ok(inst_sram_data_ok),
    .inst_sram_rdata  (inst_sram_rdata )
);

// ID stage
id_stage id_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    .flush          (flush          ),
    //allowin
    .es_allowin     (es_allowin     ),
    .ds_allowin     (ds_allowin     ),
    //from fs
    .fs_to_ds_valid (fs_to_ds_valid ),
    .fs_to_ds_bus   (fs_to_ds_bus   ),
    //to es
    .ds_to_es_valid (ds_to_es_valid ),
    .ds_to_es_bus   (ds_to_es_bus   ),
    //to fs
    .br_bus         (br_bus         ),
    //to rf: for write back
    .ws_to_rf_bus   (ws_to_rf_bus   ),
    //hazard detect info
    .es_to_ds_dest  (es_to_ds_dest  ),
    .ms_to_ds_dest  (ms_to_ds_dest  ),
    .ws_to_ds_dest  (ws_to_ds_dest  ),
    .es_to_ds_load_op(es_to_ds_load_op),
    .ms_to_ds_load_op(ms_to_ds_load_op),
    .ms_to_ds_load_dest(ms_to_ds_load_dest),
    .es_to_ds_result(es_to_ds_result),
    .ms_to_ds_result(ms_to_ds_result),
    .ws_to_ds_result(ws_to_ds_result),
    // csr hazard tracking
    .es_csr_we      (es_csr_we      ),
    .es_csr_num     (es_csr_num     ),
    .es_is_ertn     (es_is_ertn     ),
    .ertn_flush     (ertn_flush     )
);

// EXE stage
exe_stage exe_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ms_allowin     (ms_allowin     ),
    .es_allowin     (es_allowin     ),
    //from ds
    .ds_to_es_valid (ds_to_es_valid ),
    .ds_to_es_bus   (ds_to_es_bus   ),
    //to ms
    .es_to_ms_valid (es_to_ms_valid ),
    .es_to_ms_bus   (es_to_ms_bus   ),
    // data sram interface
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
    // hazard detect info
    .es_to_ds_dest  (es_to_ds_dest  ),
    .es_to_ds_load_op(es_to_ds_load_op),
    .es_to_ds_result(es_to_ds_result),
    // exception interface
    .flush          (flush          ),
    .ex_entry       (ex_entry       ),
    // ertn interface
    .ertn_flush     (ertn_flush     ),
    .ertn_pc        (ertn_pc        ),
    // instruction address translation
    .inst_vaddr     (inst_vaddr     ),
    .inst_paddr     (inst_paddr     ),
    .inst_trans_ex  (inst_trans_ex  ),
    .inst_trans_ecode(inst_trans_ecode),
    .inst_trans_esubcode(inst_trans_esubcode),
    // csr hazard tracking
    .es_csr_we      (es_csr_we      ),
    .es_csr_num     (es_csr_num     ),
    .es_is_ertn     (es_is_ertn     ),
    // interrupt / csr interface
    .hw_int_in      (hw_int_in_safe )
);

// MEM stage
mem_stage mem_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ws_allowin     (ws_allowin     ),
    .ms_allowin     (ms_allowin     ),
    //from es
    .es_to_ms_valid (es_to_ms_valid ),
    .es_to_ms_bus   (es_to_ms_bus   ),
    //to ws
    .ms_to_ws_valid (ms_to_ws_valid ),
    .ms_to_ws_bus   (ms_to_ws_bus   ),
    //from data-sram
    .data_sram_data_ok(data_sram_data_ok),
    .data_sram_rdata(data_sram_rdata),
    // hazard detect info
    .ms_to_ds_dest  (ms_to_ds_dest  ),
    .ms_to_ds_load_op(ms_to_ds_load_op),
    .ms_to_ds_load_dest(ms_to_ds_load_dest),
    .ms_to_ds_result(ms_to_ds_result)
);

// WB stage
wb_stage wb_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ws_allowin     (ws_allowin     ),
    //from ms
    .ms_to_ws_valid (ms_to_ws_valid ),
    .ms_to_ws_bus   (ms_to_ws_bus   ),
    //to rf: for write back
    .ws_to_rf_bus   (ws_to_rf_bus   ),
    // hazard detect info
    .ws_to_ds_dest  (ws_to_ds_dest  ),
    .ws_to_ds_result(ws_to_ds_result),
    // trace debug interface
    .debug_wb_pc      (debug_wb_pc      ),
    .debug_wb_rf_we   (debug_wb_rf_we   ),
    .debug_wb_rf_wnum (debug_wb_rf_wnum ),
    .debug_wb_rf_wdata(debug_wb_rf_wdata)
);

endmodule
