module llsc_unit(
    input         clk,
    input         reset,

    input         ll_commit_valid,
    input  [27:0] ll_commit_line,
    input         sc_commit_valid,
    input         local_store_commit_valid,
    input  [27:0] local_store_commit_line,
    input         dcache_inv_valid,
    input  [27:0] dcache_inv_line,
    input         external_store_valid,
    input  [27:0] external_store_line,
    input         wcllb_commit,
    input         ertn_commit,
    input         llbctl_klo,

    input  [27:0] sc_query_line,
    input         sc_query_cached,
    output        sc_can_store,
    output        reservation_current,
    output        reservation_valid
);

reg        reservation_valid_r;
reg [27:0] reservation_line_r;

wire external_store_hit = external_store_valid &&
                          (external_store_line == reservation_line_r);
wire ertn_clear = ertn_commit && !llbctl_klo;

wire reservation_clear = sc_commit_valid || wcllb_commit || ertn_clear ||
                         (reservation_valid_r && external_store_hit);

assign reservation_valid = reservation_clear ? 1'b0 :
                           ll_commit_valid ? 1'b1 :
                                             reservation_valid_r;
assign reservation_current = reservation_valid_r;
wire current_reservation_match = reservation_valid_r &&
                                 (reservation_line_r == sc_query_line);
wire retiring_ll_match = ll_commit_valid &&
                         (ll_commit_line == sc_query_line);
assign sc_can_store = !reservation_clear &&
                      (current_reservation_match || retiring_ll_match);

always @(posedge clk) begin
    if (reset) begin
        reservation_valid_r <= 1'b0;
        reservation_line_r  <= 28'b0;
    end
    else if (reservation_clear) begin
        reservation_valid_r <= 1'b0;
    end
    else if (ll_commit_valid) begin
        reservation_valid_r <= 1'b1;
        reservation_line_r  <= ll_commit_line;
    end
end

endmodule
