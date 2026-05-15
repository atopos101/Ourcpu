module csr_regfile(
    input         clk,
    input         reset,
    // instruction access interface
    input         csr_re,
    input  [13:0] csr_num,
    output [31:0] csr_rvalue,
    input         csr_we,
    input  [31:0] csr_wmask,
    input  [31:0] csr_wvalue,
    // hardware exception interface
    input         wb_ex,
    input  [ 5:0] wb_ecode,
    input  [ 8:0] wb_esubcode,
    input  [31:0] wb_pc,
    input  [31:0] wb_badv,
    output [31:0] ex_entry,
    // ERTN interface
    input         ertn_flush,
    output [31:0] ertn_pc,
    // interrupt interface
    input  [7:0]  hw_int_in,
    output        has_int,
    // stable counter read (for rdcntv instructions)
    output [31:0] cnt_low,
    output [31:0] cnt_high,
    // TID read (for rdcntid instruction)
    output [31:0] tid_val
);

// ============================================================
// CSR register numbers
// ============================================================
localparam CSR_CRMD   = 14'h00;
localparam CSR_PRMD   = 14'h01;
localparam CSR_ECFG   = 14'h04;
localparam CSR_ESTAT  = 14'h05;
localparam CSR_ERA    = 14'h06;
localparam CSR_BADV   = 14'h07;
localparam CSR_EENTRY = 14'h0C;
localparam CSR_SAVE0  = 14'h30;
localparam CSR_SAVE1  = 14'h31;
localparam CSR_SAVE2  = 14'h32;
localparam CSR_SAVE3  = 14'h33;
localparam CSR_TID    = 14'h40;
localparam CSR_TCFG   = 14'h41;
localparam CSR_TVAL   = 14'h42;
localparam CSR_TICLR  = 14'h44;

// ============================================================
// CSR register storage
// ============================================================
reg [31:0] crmd;
reg [31:0] prmd;
reg [31:0] ecfg;
reg [31:0] estat;
reg [31:0] era;
reg [31:0] badv;
reg [31:0] eentry;
reg [31:0] save0;
reg [31:0] save1;
reg [31:0] save2;
reg [31:0] save3;
reg [31:0] tid;
reg [31:0] tcfg;
reg [31:0] tval;

// ============================================================
// Stable counter (free-running, 64-bit)
// ============================================================
reg [63:0] stable_counter;
assign cnt_low  = stable_counter[31:0];
assign cnt_high = stable_counter[63:32];
assign tid_val  = tid;

// ============================================================
// Timer internal state
// ============================================================
wire        timer_en     = tcfg[0];
wire        timer_period = tcfg[1];
wire [29:0] timer_init   = tcfg[31:2];
reg         timer_pending;
wire        timer_eq_zero = (tval == 32'b0);
wire        timer_will_expire = timer_en && (tval == 32'h1);

// ============================================================
// Output assignments
// ============================================================
assign ex_entry = eentry;
assign ertn_pc  = era;

// ============================================================
// Interrupt logic
// ============================================================
// IS[12:0] = interrupt status bits
//   IS[1:0]   — SW interrupts (software writable)
//   IS[9:2]   — HW interrupts (from hw_int_in)
//   IS[10]    — Timer interrupt
//   IS[12:11] — 0 (not implemented)
wire [12:0] estat_is_hw;
assign estat_is_hw[12:0] = {
    1'b0,                           // IS[12] = 0
    timer_pending,                  // IS[11] = timer
    1'b0,                           // IS[10] = 0
    hw_int_in[7:0],                 // IS[9:2] = HW
    2'b0                            // IS[1:0] from software
};

// has_int = CRMD.IE && (any enabled interrupt is pending)
assign has_int = crmd[2] && |(estat[12:0] & ecfg[12:0]);

// ============================================================
// Instruction read: combinational
// ============================================================
reg [31:0] csr_rvalue_reg;
assign csr_rvalue = csr_rvalue_reg;

always @(*) begin
    if (csr_re) begin
        case (csr_num)
            CSR_CRMD:   csr_rvalue_reg = crmd;
            CSR_PRMD:   csr_rvalue_reg = prmd;
            CSR_ECFG:   csr_rvalue_reg = ecfg;
            CSR_ESTAT:  csr_rvalue_reg = estat;
            CSR_ERA:    csr_rvalue_reg = era;
            CSR_BADV:   csr_rvalue_reg = badv;
            CSR_EENTRY: csr_rvalue_reg = eentry;
            CSR_SAVE0:  csr_rvalue_reg = save0;
            CSR_SAVE1:  csr_rvalue_reg = save1;
            CSR_SAVE2:  csr_rvalue_reg = save2;
            CSR_SAVE3:  csr_rvalue_reg = save3;
            CSR_TID:    csr_rvalue_reg = tid;
            CSR_TCFG:   csr_rvalue_reg = tcfg;
            CSR_TVAL:   csr_rvalue_reg = tval;
            CSR_TICLR:  csr_rvalue_reg = 32'b0;  // write-only, reads as 0
            default:    csr_rvalue_reg = 32'b0;
        endcase
    end
    else begin
        csr_rvalue_reg = 32'b0;
    end
end

// ============================================================
// CSR write data (masked, for non-exception writes)
// ============================================================
wire csr_inst_we = csr_we && !wb_ex;
wire [31:0] crmd_wdata   = (crmd   & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] prmd_wdata   = (prmd   & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] ecfg_wdata   = (ecfg   & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] ecfg_legal_wdata = ecfg_wdata & 32'h00001bff;
wire [31:0] era_wdata    = (era    & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] badv_wdata   = (badv   & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] eentry_wdata = (eentry & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] save0_wdata  = (save0  & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] save1_wdata  = (save1  & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] save2_wdata  = (save2  & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] save3_wdata  = (save3  & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] tid_wdata    = (tid    & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] tcfg_wdata   = (tcfg   & ~csr_wmask) | (csr_wvalue & csr_wmask);

// ============================================================
// Main sequential logic
// ============================================================
always @(posedge clk) begin
    if (reset) begin
        crmd   <= 32'h8;
        prmd   <= 32'b0;
        ecfg   <= 32'b0;
        estat  <= 32'b0;
        era    <= 32'b0;
        badv   <= 32'b0;
        eentry <= 32'b0;
        save0  <= 32'b0;
        save1  <= 32'b0;
        save2  <= 32'b0;
        save3  <= 32'b0;
        tid    <= 32'b0;
        tcfg   <= 32'b0;
        tval   <= 32'b0;
        stable_counter <= 64'b0;
        timer_pending  <= 1'b0;
    end
    else begin
        // ====================================================
        // Stable counter: increment every cycle
        // ====================================================
        stable_counter <= stable_counter + 64'b1;

        // ====================================================
        // Timer countdown
        // ====================================================
        if (timer_en && !timer_eq_zero) begin
            tval <= tval - 32'b1;
        end

        // ====================================================
        // Timer interrupt pending
        // Set when timer counts down to 0; cleared by TICLR
        // ====================================================
        if (timer_will_expire) begin
            timer_pending <= 1'b1;
        end
        if (csr_inst_we && csr_num == CSR_TICLR && csr_wmask[0] && csr_wvalue[0]) begin
            timer_pending <= 1'b0;
        end

        // ====================================================
        // CSR instruction writes (before wb_ex to avoid override)
        // ====================================================
        if (csr_inst_we) begin
            case (csr_num)
                CSR_CRMD:   crmd   <= crmd_wdata;
                CSR_PRMD:   prmd   <= prmd_wdata;
                CSR_ECFG:   ecfg   <= ecfg_legal_wdata;
                CSR_ESTAT:  estat[1:0] <= (estat[1:0] & ~csr_wmask[1:0]) | (csr_wvalue[1:0] & csr_wmask[1:0]);
                CSR_ERA:    era    <= era_wdata;
                CSR_BADV:   badv   <= badv_wdata;
                CSR_EENTRY: eentry <= eentry_wdata;
                CSR_SAVE0:  save0  <= save0_wdata;
                CSR_SAVE1:  save1  <= save1_wdata;
                CSR_SAVE2:  save2  <= save2_wdata;
                CSR_SAVE3:  save3  <= save3_wdata;
                CSR_TID:    tid    <= tid_wdata;
                CSR_TCFG: begin
                    tcfg <= tcfg_wdata;
                    if (tcfg_wdata[0]) begin
                        tval <= {tcfg_wdata[31:2], 2'b0};
                        if ({tcfg_wdata[31:2], 2'b0} == 32'b0) begin
                            timer_pending <= 1'b1;
                        end
                    end
                    else begin
                        tval <= 32'b0;
                    end
                end
                CSR_TICLR:  ; // write-only, handled above via timer_pending clear
                default: ;
            endcase
        end

        // ====================================================
        // Reload on period (timer count hit 0)
        // ====================================================
        if (timer_will_expire) begin
            if (timer_period) begin
                tval <= {timer_init, 2'b0};
            end
            // else one-shot: tval stays 0
        end

        // ====================================================
        // Hardware exception save (overrides CSR writes)
        // ====================================================
        if (wb_ex) begin
            prmd[1:0] <= crmd[1:0];
            prmd[2]   <= crmd[2];
            crmd[1:0] <= 2'b00;
            crmd[2]   <= 1'b0;
            era       <= wb_pc;
            estat[21:16] <= wb_ecode;
            estat[30:22] <= wb_esubcode;
            if (wb_ecode == 6'h08 || wb_ecode == 6'h09) begin
                badv <= wb_badv;
            end
        end

        // ====================================================
        // ERTN: restore CRMD from PRMD
        // ====================================================
        if (ertn_flush) begin
            crmd[1:0] <= prmd[1:0];
            crmd[2]   <= prmd[2];
        end

        // ====================================================
        // Update ESTAT.IS hardware bits every cycle (IS[12:2])
        // IS[1:0] only updated via CSR write above
        // ====================================================
        estat[12:2] <= estat_is_hw[12:2];
    end
end

endmodule
