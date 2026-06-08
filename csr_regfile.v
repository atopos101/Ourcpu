`include "mycpu.vh"

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
    // LL/SC control
    input         reservation_valid,
    output        llbctl_klo,
    output        wcllb_commit,
    // interrupt interface
    input  [7:0]  hw_int_in,
    output        has_int,
    // stable counter read (for rdcntv instructions)
    output [31:0] cnt_low,
    output [31:0] cnt_high,
    // TID read (for rdcntid instruction)
    output [31:0] tid_val,
    // Address translation CSR values
    output [31:0] csr_crmd,
    output [31:0] csr_dmw0,
    output [31:0] csr_dmw1,
    // TLB CSR values used by TLB instructions
    output [31:0] csr_tlbidx,
    output [31:0] csr_tlbehi,
    output [31:0] csr_tlbelo0,
    output [31:0] csr_tlbelo1,
    output [ 9:0] csr_asid,
    output [ 4:0] csr_tlbidx_index,
    output [ 5:0] csr_tlbidx_ps,
    output        csr_tlbidx_ne,
    // TLB instruction side effects
    input         tlbsrch_en,
    input         tlbsrch_found,
    input  [ 4:0] tlbsrch_index,
    input         tlbrd_en,
    input         tlbrd_e,
    input  [18:0] tlbrd_vppn,
    input  [ 5:0] tlbrd_ps,
    input  [ 9:0] tlbrd_asid,
    input         tlbrd_g,
    input  [19:0] tlbrd_ppn0,
    input  [ 1:0] tlbrd_plv0,
    input  [ 1:0] tlbrd_mat0,
    input         tlbrd_d0,
    input         tlbrd_v0,
    input  [19:0] tlbrd_ppn1,
    input  [ 1:0] tlbrd_plv1,
    input  [ 1:0] tlbrd_mat1,
    input         tlbrd_d1,
    input         tlbrd_v1
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
localparam CSR_TLBIDX = 14'h10;
localparam CSR_TLBEHI = 14'h11;
localparam CSR_TLBELO0= 14'h12;
localparam CSR_TLBELO1= 14'h13;
localparam CSR_ASID   = 14'h18;
localparam CSR_SAVE0  = 14'h30;
localparam CSR_SAVE1  = 14'h31;
localparam CSR_SAVE2  = 14'h32;
localparam CSR_SAVE3  = 14'h33;
localparam CSR_TID    = 14'h40;
localparam CSR_TCFG   = 14'h41;
localparam CSR_TVAL   = 14'h42;
localparam CSR_TICLR  = 14'h44;
localparam CSR_LLBCTL = 14'h60;
localparam CSR_TLBRENTRY = 14'h88;
localparam CSR_DMW0   = 14'h180;
localparam CSR_DMW1   = 14'h181;

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
reg [31:0] tlbidx;
reg [31:0] tlbehi;
reg [31:0] tlbelo0;
reg [31:0] tlbelo1;
reg [ 9:0] asid;
reg [31:0] save0;
reg [31:0] save1;
reg [31:0] save2;
reg [31:0] save3;
reg [31:0] tid;
reg [31:0] tcfg;
reg [31:0] tval;
reg        llbctl_klo_r;
reg [31:0] tlbrentry;
reg [31:0] dmw0;
reg [31:0] dmw1;

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
assign ex_entry = (wb_ecode == `ECODE_TLBR) ? tlbrentry : eentry;
assign ertn_pc  = era;
assign llbctl_klo = llbctl_klo_r;
assign csr_crmd         = crmd;
assign csr_dmw0         = dmw0;
assign csr_dmw1         = dmw1;
assign csr_tlbidx       = tlbidx;
assign csr_tlbehi       = tlbehi;
assign csr_tlbelo0      = tlbelo0;
assign csr_tlbelo1      = tlbelo1;
assign csr_asid         = asid;
assign csr_tlbidx_index = tlbidx[4:0];
assign csr_tlbidx_ps    = tlbidx[29:24];
assign csr_tlbidx_ne    = tlbidx[31];
assign wcllb_commit = csr_inst_we && (csr_num == CSR_LLBCTL) &&
                      csr_wmask[1] && csr_wvalue[1];

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
            CSR_TLBIDX: csr_rvalue_reg = tlbidx;
            CSR_TLBEHI: csr_rvalue_reg = tlbehi;
            CSR_TLBELO0:csr_rvalue_reg = tlbelo0;
            CSR_TLBELO1:csr_rvalue_reg = tlbelo1;
            CSR_ASID:   csr_rvalue_reg = {8'b0, 8'd10, 6'b0, asid};
            CSR_SAVE0:  csr_rvalue_reg = save0;
            CSR_SAVE1:  csr_rvalue_reg = save1;
            CSR_SAVE2:  csr_rvalue_reg = save2;
            CSR_SAVE3:  csr_rvalue_reg = save3;
            CSR_TID:    csr_rvalue_reg = tid;
            CSR_TCFG:   csr_rvalue_reg = tcfg;
            CSR_TVAL:   csr_rvalue_reg = tval;
            CSR_TICLR:  csr_rvalue_reg = 32'b0;  // write-only, reads as 0
            CSR_LLBCTL: csr_rvalue_reg = {29'b0, llbctl_klo_r, 1'b0,
                                          reservation_valid};
            CSR_TLBRENTRY: csr_rvalue_reg = tlbrentry;
            CSR_DMW0:   csr_rvalue_reg = dmw0;
            CSR_DMW1:   csr_rvalue_reg = dmw1;
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
wire [31:0] tlbidx_wdata = (tlbidx & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] tlbehi_wdata = (tlbehi & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] tlbelo0_wdata = (tlbelo0 & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] tlbelo1_wdata = (tlbelo1 & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] asid_wdata   = ({22'b0, asid} & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] save0_wdata  = (save0  & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] save1_wdata  = (save1  & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] save2_wdata  = (save2  & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] save3_wdata  = (save3  & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] tid_wdata    = (tid    & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] tcfg_wdata   = (tcfg   & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] tlbrentry_wdata = (tlbrentry & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] dmw0_wdata   = (dmw0   & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire [31:0] dmw1_wdata   = (dmw1   & ~csr_wmask) | (csr_wvalue & csr_wmask);

wire wb_tlb_ex = wb_ecode == `ECODE_TLBR ||
                 wb_ecode == `ECODE_PIL  ||
                 wb_ecode == `ECODE_PIS  ||
                 wb_ecode == `ECODE_PIF  ||
                 wb_ecode == `ECODE_PME  ||
                 wb_ecode == `ECODE_PPI;

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
        tlbidx <= 32'b0;
        tlbehi <= 32'b0;
        tlbelo0 <= 32'b0;
        tlbelo1 <= 32'b0;
        asid   <= 10'b0;
        save0  <= 32'b0;
        save1  <= 32'b0;
        save2  <= 32'b0;
        save3  <= 32'b0;
        tid    <= 32'b0;
        tcfg   <= 32'b0;
        tval   <= 32'b0;
        llbctl_klo_r <= 1'b0;
        tlbrentry <= 32'b0;
        dmw0   <= 32'b0;
        dmw1   <= 32'b0;
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
                CSR_CRMD:   crmd   <= crmd_wdata & 32'h000001ff;
                CSR_PRMD:   prmd   <= prmd_wdata;
                CSR_ECFG:   ecfg   <= ecfg_legal_wdata;
                CSR_ESTAT:  estat[1:0] <= (estat[1:0] & ~csr_wmask[1:0]) | (csr_wvalue[1:0] & csr_wmask[1:0]);
                CSR_ERA:    era    <= era_wdata;
                CSR_BADV:   badv   <= badv_wdata;
                CSR_EENTRY: eentry <= eentry_wdata;
                CSR_TLBIDX: tlbidx <= tlbidx_wdata & 32'hbf00001f;
                CSR_TLBEHI: tlbehi <= tlbehi_wdata & 32'hffffe000;
                CSR_TLBELO0:tlbelo0 <= tlbelo0_wdata & 32'h0fffffff;
                CSR_TLBELO1:tlbelo1 <= tlbelo1_wdata & 32'h0fffffff;
                CSR_ASID:   asid <= asid_wdata[9:0];
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
                CSR_LLBCTL: begin
                    if (csr_wmask[2]) begin
                        llbctl_klo_r <= csr_wvalue[2];
                    end
                end
                CSR_TLBRENTRY: tlbrentry <= tlbrentry_wdata;
                CSR_DMW0:   dmw0 <= dmw0_wdata & 32'hee000039;
                CSR_DMW1:   dmw1 <= dmw1_wdata & 32'hee000039;
                default: ;
            endcase
        end

        if (tlbsrch_en) begin
            if (tlbsrch_found) begin
                tlbidx <= {1'b0, tlbidx[30:5], tlbsrch_index};
            end
            else begin
                tlbidx <= {1'b1, tlbidx[30:0]};
            end
        end

        if (tlbrd_en) begin
            if (tlbrd_e) begin
                tlbidx  <= {2'b0, tlbrd_ps, 19'b0, tlbidx[4:0]};
                tlbehi  <= {tlbrd_vppn, 13'b0};
                tlbelo0 <= {4'b0, tlbrd_ppn0, 1'b0, tlbrd_g, tlbrd_mat0, tlbrd_plv0, tlbrd_d0, tlbrd_v0};
                tlbelo1 <= {4'b0, tlbrd_ppn1, 1'b0, tlbrd_g, tlbrd_mat1, tlbrd_plv1, tlbrd_d1, tlbrd_v1};
                asid    <= tlbrd_asid;
            end
            else begin
                tlbidx  <= 32'h80000000 | {27'b0, tlbidx[4:0]};
                tlbehi  <= 32'b0;
                tlbelo0 <= 32'b0;
                tlbelo1 <= 32'b0;
                asid    <= 10'b0;
            end
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
            if (wb_ecode == `ECODE_TLBR) begin
                crmd[3] <= 1'b1;
                crmd[4] <= 1'b0;
            end
            era       <= wb_pc;
            estat[21:16] <= wb_ecode;
            estat[30:22] <= wb_esubcode;
            if (wb_ecode == `ECODE_ADEF || wb_ecode == `ECODE_ALE || wb_tlb_ex) begin
                badv <= wb_badv;
            end
            if (wb_tlb_ex) begin
                tlbehi <= {wb_badv[31:13], 13'b0};
            end
        end

        // ====================================================
        // ERTN: restore CRMD from PRMD
        // ====================================================
        if (ertn_flush) begin
            crmd[1:0] <= prmd[1:0];
            crmd[2]   <= prmd[2];
            llbctl_klo_r <= 1'b0;
            if (estat[21:16] == `ECODE_TLBR) begin
                crmd[3] <= 1'b0;
                crmd[4] <= 1'b1;
            end
        end

        // ====================================================
        // Update ESTAT.IS hardware bits every cycle (IS[12:2])
        // IS[1:0] only updated via CSR write above
        // ====================================================
        estat[12:2] <= estat_is_hw[12:2];
    end
end

endmodule
