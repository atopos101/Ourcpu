`timescale 1ns/1ps
`default_nettype wire
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

wire reservation_global_clear = sc_commit_valid || wcllb_commit || ertn_clear;

// A concurrent coherence/invalidation event for the line loaded by LL must
// prevent a new reservation from being established in that cycle.
wire ll_line_invalidated = ll_commit_valid &&
                           (external_store_valid &&
                            (external_store_line == ll_commit_line));

// This signal is also observed by the simulation retirement snapshot.  It
// describes the next-state clear decision after accounting for a concurrent
// LL that establishes a reservation on a different, unaffected line.
wire reservation_clear = reservation_global_clear || ll_line_invalidated ||
                         (!ll_commit_valid && reservation_valid_r &&
                          external_store_hit);

// Reservation queries must depend only on registered state.  Feeding
// same-cycle retirement events into these outputs creates a combinational
// path from ES through MEM/CSR and back into the SC request decision.
assign reservation_valid = reservation_valid_r;
assign reservation_current = reservation_valid_r;
wire current_reservation_match = reservation_valid_r &&
                                 (reservation_line_r == sc_query_line);
assign sc_can_store = current_reservation_match;

// The current single-core model keys reservations by physical cache line for
// both cached and uncached accesses.  Keep the cacheability input in the
// frozen interface for a future coherent implementation.
wire unused_sc_query_cached = sc_query_cached;
wire unused_local_store = local_store_commit_valid |
                          (|local_store_commit_line);
wire unused_dcache_inv = dcache_inv_valid | (|dcache_inv_line);

always @(posedge clk) begin
    if (reset) begin
        reservation_valid_r <= 1'b0;
        reservation_line_r  <= 28'b0;
    end
    else if (reservation_clear || ll_line_invalidated) begin
        reservation_valid_r <= 1'b0;
    end
    else if (ll_commit_valid) begin
        reservation_valid_r <= 1'b1;
        reservation_line_r  <= ll_commit_line;
    end
end

endmodule
