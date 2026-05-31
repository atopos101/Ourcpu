module axi_ram(
    input         s_aclk,
    input         s_aresetn,

    input  [ 3:0] s_axi_awid,
    input  [31:0] s_axi_awaddr,
    input  [ 7:0] s_axi_awlen,
    input  [ 2:0] s_axi_awsize,
    input  [ 1:0] s_axi_awburst,
    input         s_axi_awvalid,
    output        s_axi_awready,
    input  [31:0] s_axi_wdata,
    input  [ 3:0] s_axi_wstrb,
    input         s_axi_wlast,
    input         s_axi_wvalid,
    output        s_axi_wready,
    output [ 3:0] s_axi_bid,
    output [ 1:0] s_axi_bresp,
    output        s_axi_bvalid,
    input         s_axi_bready,

    input  [ 3:0] s_axi_arid,
    input  [31:0] s_axi_araddr,
    input  [ 7:0] s_axi_arlen,
    input  [ 2:0] s_axi_arsize,
    input  [ 1:0] s_axi_arburst,
    input         s_axi_arvalid,
    output        s_axi_arready,
    output [ 3:0] s_axi_rid,
    output [31:0] s_axi_rdata,
    output [ 1:0] s_axi_rresp,
    output        s_axi_rlast,
    output        s_axi_rvalid,
    input         s_axi_rready
);

reg [31:0] mem [0:262143];

reg        rvalid_r;
reg [ 3:0] rid_r;
reg [31:0] rdata_r;

reg        bvalid_r;
reg [ 3:0] bid_r;
reg        aw_pending;
reg [31:0] awaddr_r;
reg [ 3:0] awid_r;

wire [17:0] ar_index = s_axi_araddr[19:2];
wire [17:0] aw_index = aw_pending ? awaddr_r[19:2] : s_axi_awaddr[19:2];
wire        ar_hs = s_axi_arvalid && s_axi_arready;
wire        aw_hs = s_axi_awvalid && s_axi_awready;
wire        w_hs  = s_axi_wvalid  && s_axi_wready;
wire        b_hs  = s_axi_bvalid  && s_axi_bready;

initial begin
    $readmemb("../../../../../../../../func/obj/inst_ram.mif", mem);
end

assign s_axi_arready = s_aresetn && !rvalid_r;
assign s_axi_rvalid  = rvalid_r;
assign s_axi_rid     = rid_r;
assign s_axi_rdata   = rdata_r;
assign s_axi_rresp   = 2'b00;
assign s_axi_rlast   = rvalid_r;

assign s_axi_awready = s_aresetn && !aw_pending && !bvalid_r;
assign s_axi_wready  = s_aresetn && !bvalid_r && (aw_pending || s_axi_awvalid);
assign s_axi_bvalid  = bvalid_r;
assign s_axi_bid     = bid_r;
assign s_axi_bresp   = 2'b00;

always @(posedge s_aclk) begin
    if (!s_aresetn) begin
        rvalid_r <= 1'b0;
        rid_r    <= 4'b0;
        rdata_r  <= 32'b0;
    end
    else begin
        if (ar_hs) begin
            rvalid_r <= 1'b1;
            rid_r    <= s_axi_arid;
            rdata_r  <= mem[ar_index];
        end
        else if (s_axi_rvalid && s_axi_rready) begin
            rvalid_r <= 1'b0;
        end
    end
end

always @(posedge s_aclk) begin
    if (!s_aresetn) begin
        aw_pending <= 1'b0;
        awaddr_r   <= 32'b0;
        awid_r     <= 4'b0;
        bvalid_r   <= 1'b0;
        bid_r      <= 4'b0;
    end
    else begin
        if (aw_hs && !w_hs) begin
            aw_pending <= 1'b1;
            awaddr_r   <= s_axi_awaddr;
            awid_r     <= s_axi_awid;
        end

        if (w_hs) begin
            if (s_axi_wstrb[0]) mem[aw_index][ 7: 0] <= s_axi_wdata[ 7: 0];
            if (s_axi_wstrb[1]) mem[aw_index][15: 8] <= s_axi_wdata[15: 8];
            if (s_axi_wstrb[2]) mem[aw_index][23:16] <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) mem[aw_index][31:24] <= s_axi_wdata[31:24];
            bvalid_r   <= 1'b1;
            bid_r      <= aw_pending ? awid_r : s_axi_awid;
            aw_pending <= 1'b0;
        end
        else if (b_hs) begin
            bvalid_r <= 1'b0;
        end
    end
end

endmodule
