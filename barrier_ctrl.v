`timescale 1ns/1ps
`default_nettype none
module barrier_ctrl (
    input  wire       clk,
    input  wire       reset,

    input  wire       barrier_req,
    input  wire       barrier_is_ibar,
    output wire       barrier_done,
    output wire       barrier_busy,

    input  wire       data_side_idle,
    input  wire       icache_idle,

    output wire       dcache_maint_valid,
    output wire [7:0] dcache_maint_index,
    output wire       dcache_maint_way,
    input  wire       dcache_maint_ok,

    output wire       icache_maint_valid,
    output wire [7:0] icache_maint_index,
    output wire       icache_maint_way,
    input  wire       icache_maint_ok
);

localparam ST_IDLE          = 3'd0;
localparam ST_WAIT_DATA     = 3'd1;
localparam ST_DCACHE_CLEAN  = 3'd2;
localparam ST_WAIT_WRITE    = 3'd3;
localparam ST_ICACHE_INV    = 3'd4;
localparam ST_DONE          = 3'd5;

reg [2:0] state;
reg       request_is_ibar;
reg [8:0] scan_entry;

wire scan_last = scan_entry == 9'h1ff;

assign barrier_done = state == ST_DONE;
assign barrier_busy = state != ST_IDLE;

assign dcache_maint_valid = (state == ST_DCACHE_CLEAN) && !dcache_maint_ok;
assign dcache_maint_index = scan_entry[7:0];
assign dcache_maint_way   = scan_entry[8];

assign icache_maint_valid = (state == ST_ICACHE_INV) && !icache_maint_ok;
assign icache_maint_index = scan_entry[7:0];
assign icache_maint_way   = scan_entry[8];

always @(posedge clk) begin
    if (reset) begin
        state           <= ST_IDLE;
        request_is_ibar <= 1'b0;
        scan_entry      <= 9'b0;
    end
    else begin
        case (state)
        ST_IDLE: begin
            scan_entry <= 9'b0;
            if (barrier_req) begin
                request_is_ibar <= barrier_is_ibar;
                state <= ST_WAIT_DATA;
            end
        end

        ST_WAIT_DATA: begin
            if (data_side_idle) begin
                if (request_is_ibar) begin
                    scan_entry <= 9'b0;
                    state <= ST_DCACHE_CLEAN;
                end
                else begin
                    state <= ST_DONE;
                end
            end
        end

        ST_DCACHE_CLEAN: begin
            if (dcache_maint_ok) begin
                if (scan_last) begin
                    scan_entry <= 9'b0;
                    state <= ST_WAIT_WRITE;
                end
                else begin
                    scan_entry <= scan_entry + 9'b1;
                end
            end
        end

        ST_WAIT_WRITE: begin
            if (data_side_idle && icache_idle) begin
                scan_entry <= 9'b0;
                state <= ST_ICACHE_INV;
            end
        end

        ST_ICACHE_INV: begin
            if (icache_maint_ok) begin
                if (scan_last) begin
                    state <= ST_DONE;
                end
                else begin
                    scan_entry <= scan_entry + 9'b1;
                end
            end
        end

        ST_DONE: begin
            if (!barrier_req) begin
                state <= ST_IDLE;
            end
        end

        default: begin
            state <= ST_IDLE;
        end
        endcase
    end
end

endmodule
