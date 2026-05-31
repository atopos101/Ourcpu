`include "mycpu.vh"

module exe_stage(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          ms_allowin    ,
    output                         es_allowin    ,
    //from ds
    input                          ds_to_es_valid,
    input  [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus  ,
    //to ms
    output                         es_to_ms_valid,
    output [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus  ,
    // data sram interface
    output        data_sram_req    ,
    output        data_sram_wr     ,
    output [ 1:0] data_sram_size   ,
    output [ 3:0] data_sram_wstrb  ,
    output [31:0] data_sram_addr   ,
    output [31:0] data_sram_wdata  ,
    input         data_sram_addr_ok,
    input         data_sram_data_ok,
    input  [31:0] data_sram_rdata  ,
    // forward to id
    output [4:0] es_to_ds_dest,
    output es_to_ds_load_op,
    output [31:0] es_to_ds_result,
    // exception interface
    output        flush,
    output [31:0] ex_entry,
    // ertn interface
    output        ertn_flush,
    output [31:0] ertn_pc,
    // instruction address translation
    input  [31:0] inst_vaddr,
    output [31:0] inst_paddr,
    output        inst_trans_ex,
    output [ 5:0] inst_trans_ecode,
    output [ 8:0] inst_trans_esubcode,
    // csr hazard tracking -> id
    output        es_csr_we,
    output [13:0] es_csr_num,
    output        es_is_ertn,
    // interrupt / csr interface
    input  [7:0]  hw_int_in
);

reg         es_valid      ;
wire        es_ready_go   ;

reg  [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus_r;

// ============================================================
// Unpack ds_to_es_bus (207 bits)
// ============================================================
wire        ds_ex;
wire [ 5:0] ds_ecode;
wire [ 8:0] ds_esubcode;
wire        ds_rdcntv;
wire        ds_rdcntv_hi;
wire        ds_rdcntid;
wire [ 2:0] tlb_op;
wire [ 4:0] invtlb_op;

wire [18:0] alu_op      ;
wire        es_load_op;
wire [ 1:0] mem_size;
wire        mem_unsigned;
wire        src1_is_pc;
wire        src2_is_imm;
wire        src2_is_4;
wire        res_from_mem;
wire        gr_we;
wire        es_mem_we;
wire [4: 0] dest;
wire [31:0] rj_value;
wire [31:0] rkd_value;
wire [31:0] imm;
wire [31:0] es_pc;
wire [ 1:0] csr_op;
wire [13:0] csr_num;
wire        inst_syscall;
wire        inst_ertn;

assign {ds_ex,              // 1  (198)
        ds_ecode,           // 6  (197:192)
        ds_esubcode,        // 9  (191:183)
        ds_rdcntv,          // 1  (182)
        ds_rdcntv_hi,       // 1  (181)
        ds_rdcntid,         // 1  (180)
        tlb_op,
        invtlb_op,
        // original 180-bit payload
        alu_op,             // 19 (179:161)
        es_load_op,         // 1  (160)
        mem_size,           // 2  (159:158)
        mem_unsigned,       // 1  (157)
        src1_is_pc,         // 1  (156)
        src2_is_imm,        // 1  (155)
        src2_is_4,          // 1  (154)
        gr_we,              // 1  (153)
        es_mem_we,          // 1  (152)
        dest,               // 5  (151:147)
        imm,                // 32 (146:115)
        rj_value,           // 32 (114:83)
        rkd_value,          // 32 (82:51)
        es_pc,              // 32 (50:19)
        res_from_mem,       // 1  (18)
        csr_op,             // 2  (17:16)
        csr_num,            // 14 (15:2)
        inst_syscall,       // 1  (1)
        inst_ertn           // 1  (0)
       } = ds_to_es_bus_r;

wire [31:0] alu_src1   ;
wire [31:0] alu_src2   ;
wire [31:0] alu_result ;
wire [31:0] mem_addr   ;
wire        div_op     ;
wire        div_signed ;
wire        div_is_mod ;
wire        div_start  ;
wire        div_cancel ;
wire        div_busy   ;
wire        div_done   ;
wire [31:0] div_quotient;
wire [31:0] div_remainder;
wire [31:0] div_result ;

// ============================================================
// ALU
// ============================================================
assign alu_src1 = src1_is_pc  ? es_pc  : rj_value;
assign alu_src2 = src2_is_imm ? imm : rkd_value;
assign mem_addr = rj_value + imm;
assign div_op     = !ds_ex && (alu_op[12] || alu_op[16] || alu_op[17] || alu_op[18]);
assign div_signed = alu_op[12] || alu_op[16];
assign div_is_mod = alu_op[16] || alu_op[18];
assign div_start  = es_valid && div_op && !div_busy && !div_done;
assign div_cancel = flush || ertn_flush || (es_valid && div_op && div_done && ms_allowin);
assign div_result = div_is_mod ? div_remainder : div_quotient;

alu u_alu(
    .alu_op     (alu_op    ),
    .alu_src1   (alu_src1  ),
    .alu_src2   (alu_src2  ),
    .alu_result (alu_result)
    );

iter_divider u_iter_divider(
    .clk        (clk          ),
    .reset      (reset        ),
    .cancel     (div_cancel   ),
    .start      (div_start    ),
    .signed_div (div_signed   ),
    .dividend   (alu_src1     ),
    .divisor    (alu_src2     ),
    .busy       (div_busy     ),
    .done       (div_done     ),
    .quotient   (div_quotient ),
    .remainder  (div_remainder)
    );

// ============================================================
// CSR access
// ============================================================
wire is_csr     = csr_op != 2'b00;
wire is_csrwr   = csr_op == 2'b10;
wire is_csrxchg = csr_op == 2'b11;
wire csr_we_req = is_csrwr | is_csrxchg;

wire        csr_re;
wire [31:0] csr_rvalue;
wire [31:0] csr_wmask;
wire [31:0] csr_wvalue;
wire        has_int;
wire        wb_ex;  // any exception (sync or int)
reg  [5:0]  wb_ecode;
reg  [8:0]  wb_esubcode;
wire [31:0] wb_pc;
reg  [31:0] wb_badv;
wire [31:0] cnt_low;
wire [31:0] cnt_high;
wire [31:0] tid_val;
wire        ex_pending;
wire        ertn_pending;
wire        es_commit;

assign es_commit    = es_valid && es_ready_go && ms_allowin;
assign ertn_pending = inst_ertn && es_valid && !ex_pending;
assign csr_re       = is_csr && es_valid && !ex_pending && !ertn_pending;
assign csr_wmask  = is_csrwr ? 32'hFFFFFFFF : rj_value;
assign csr_wvalue = rkd_value;
assign wb_pc      = es_pc;

// ============================================================
// TLB instruction support
// ============================================================
localparam TLB_OP_SRCH = 3'd1;
localparam TLB_OP_RD   = 3'd2;
localparam TLB_OP_WR   = 3'd3;
localparam TLB_OP_FILL = 3'd4;
localparam TLB_OP_INV  = 3'd5;

wire inst_tlbsrch = tlb_op == TLB_OP_SRCH;
wire inst_tlbrd   = tlb_op == TLB_OP_RD;
wire inst_tlbwr   = tlb_op == TLB_OP_WR;
wire inst_tlbfill = tlb_op == TLB_OP_FILL;
wire inst_invtlb  = tlb_op == TLB_OP_INV;
wire tlb_commit   = es_commit && !ex_pending && !ertn_pending;

wire [31:0] csr_tlbidx;
wire [31:0] csr_tlbehi;
wire [31:0] csr_tlbelo0;
wire [31:0] csr_tlbelo1;
wire [31:0] csr_crmd;
wire [31:0] csr_dmw0;
wire [31:0] csr_dmw1;
wire [ 9:0] csr_asid;
wire [ 3:0] csr_tlbidx_index;
wire [ 5:0] csr_tlbidx_ps;
wire        csr_tlbidx_ne;

reg  [3:0]  tlbfill_index;
wire [3:0]  tlb_write_index = inst_tlbfill ? tlbfill_index : csr_tlbidx_index;
wire        tlb_we          = tlb_commit && (inst_tlbwr || inst_tlbfill);
wire        tlbfill_fire    = tlb_commit && inst_tlbfill;
wire        invtlb_valid    = tlb_commit && inst_invtlb;

wire        s0_found;
wire [ 3:0] s0_index;
wire [19:0] s0_ppn;
wire [ 5:0] s0_ps;
wire [ 1:0] s0_plv;
wire [ 1:0] s0_mat;
wire        s0_d;
wire        s0_v;

wire        s1_found;
wire [ 3:0] s1_index;
wire [19:0] s1_ppn;
wire [ 5:0] s1_ps;
wire [ 1:0] s1_plv;
wire [ 1:0] s1_mat;
wire        s1_d;
wire        s1_v;

wire [31:0] data_vaddr = mem_addr;
wire [18:0] s1_vppn = inst_tlbsrch ? csr_tlbehi[31:13] :
                       inst_invtlb  ? rkd_value[31:13]  : data_vaddr[31:13];
wire        s1_va_bit12 = inst_tlbsrch ? csr_tlbehi[12] :
                          inst_invtlb  ? rkd_value[12]  : data_vaddr[12];
wire [ 9:0] s1_asid = inst_invtlb ? rj_value[9:0] : csr_asid;

wire        tlbrd_e;
wire [18:0] tlbrd_vppn;
wire [ 5:0] tlbrd_ps;
wire [ 9:0] tlbrd_asid;
wire        tlbrd_g;
wire [19:0] tlbrd_ppn0;
wire [ 1:0] tlbrd_plv0;
wire [ 1:0] tlbrd_mat0;
wire        tlbrd_d0;
wire        tlbrd_v0;
wire [19:0] tlbrd_ppn1;
wire [ 1:0] tlbrd_plv1;
wire [ 1:0] tlbrd_mat1;
wire        tlbrd_d1;
wire        tlbrd_v1;

tlb #(.TLBNUM(16)) u_tlb(
    .clk          (clk),
    .s0_vppn      (inst_vaddr[31:13]),
    .s0_va_bit12  (inst_vaddr[12]),
    .s0_asid      (csr_asid),
    .s0_found     (s0_found),
    .s0_index     (s0_index),
    .s0_ppn       (s0_ppn),
    .s0_ps        (s0_ps),
    .s0_plv       (s0_plv),
    .s0_mat       (s0_mat),
    .s0_d         (s0_d),
    .s0_v         (s0_v),
    .s1_vppn      (s1_vppn),
    .s1_va_bit12  (s1_va_bit12),
    .s1_asid      (s1_asid),
    .s1_found     (s1_found),
    .s1_index     (s1_index),
    .s1_ppn       (s1_ppn),
    .s1_ps        (s1_ps),
    .s1_plv       (s1_plv),
    .s1_mat       (s1_mat),
    .s1_d         (s1_d),
    .s1_v         (s1_v),
    .invtlb_valid (invtlb_valid),
    .invtlb_op    (invtlb_op),
    .we           (tlb_we),
    .w_index      (tlb_write_index),
    .w_e          (~csr_tlbidx_ne),
    .w_vppn       (csr_tlbehi[31:13]),
    .w_ps         (csr_tlbidx_ps),
    .w_asid       (csr_asid),
    .w_g          (csr_tlbelo0[6] & csr_tlbelo1[6]),
    .w_ppn0       (csr_tlbelo0[27:8]),
    .w_plv0       (csr_tlbelo0[3:2]),
    .w_mat0       (csr_tlbelo0[5:4]),
    .w_d0         (csr_tlbelo0[1]),
    .w_v0         (csr_tlbelo0[0]),
    .w_ppn1       (csr_tlbelo1[27:8]),
    .w_plv1       (csr_tlbelo1[3:2]),
    .w_mat1       (csr_tlbelo1[5:4]),
    .w_d1         (csr_tlbelo1[1]),
    .w_v1         (csr_tlbelo1[0]),
    .r_index      (csr_tlbidx_index),
    .r_e          (tlbrd_e),
    .r_vppn       (tlbrd_vppn),
    .r_ps         (tlbrd_ps),
    .r_asid       (tlbrd_asid),
    .r_g          (tlbrd_g),
    .r_ppn0       (tlbrd_ppn0),
    .r_plv0       (tlbrd_plv0),
    .r_mat0       (tlbrd_mat0),
    .r_d0         (tlbrd_d0),
    .r_v0         (tlbrd_v0),
    .r_ppn1       (tlbrd_ppn1),
    .r_plv1       (tlbrd_plv1),
    .r_mat1       (tlbrd_mat1),
    .r_d1         (tlbrd_d1),
    .r_v1         (tlbrd_v1)
);

always @(posedge clk) begin
    if (reset) begin
        tlbfill_index <= 4'b0;
    end
    else if (tlbfill_fire) begin
        tlbfill_index <= tlbfill_index + 4'b1;
    end
end

csr_regfile u_csr_regfile(
    .clk        (clk        ),
    .reset      (reset      ),
    .csr_re     (csr_re     ),
    .csr_num    (csr_num    ),
    .csr_rvalue (csr_rvalue ),
    .csr_we     (csr_we_req && es_commit && !ex_pending && !ertn_pending),
    .csr_wmask  (csr_wmask  ),
    .csr_wvalue (csr_wvalue ),
    .wb_ex      (wb_ex ),
    .wb_ecode   (wb_ecode   ),
    .wb_esubcode(wb_esubcode),
    .wb_pc      (wb_pc      ),
    .wb_badv    (wb_badv    ),
    .ex_entry   (ex_entry   ),
    .ertn_flush (ertn_flush ),
    .ertn_pc    (ertn_pc    ),
    .hw_int_in  (hw_int_in  ),
    .has_int    (has_int    ),
    .cnt_low    (cnt_low    ),
    .cnt_high   (cnt_high   ),
    .tid_val    (tid_val    ),
    .csr_crmd   (csr_crmd   ),
    .csr_dmw0   (csr_dmw0   ),
    .csr_dmw1   (csr_dmw1   ),
    .csr_tlbidx (csr_tlbidx ),
    .csr_tlbehi (csr_tlbehi ),
    .csr_tlbelo0(csr_tlbelo0),
    .csr_tlbelo1(csr_tlbelo1),
    .csr_asid   (csr_asid   ),
    .csr_tlbidx_index(csr_tlbidx_index),
    .csr_tlbidx_ps(csr_tlbidx_ps),
    .csr_tlbidx_ne(csr_tlbidx_ne),
    .tlbsrch_en (tlb_commit && inst_tlbsrch),
    .tlbsrch_found(s1_found),
    .tlbsrch_index(s1_index),
    .tlbrd_en   (tlb_commit && inst_tlbrd),
    .tlbrd_e    (tlbrd_e),
    .tlbrd_vppn (tlbrd_vppn),
    .tlbrd_ps   (tlbrd_ps),
    .tlbrd_asid (tlbrd_asid),
    .tlbrd_g    (tlbrd_g),
    .tlbrd_ppn0 (tlbrd_ppn0),
    .tlbrd_plv0 (tlbrd_plv0),
    .tlbrd_mat0 (tlbrd_mat0),
    .tlbrd_d0   (tlbrd_d0),
    .tlbrd_v0   (tlbrd_v0),
    .tlbrd_ppn1 (tlbrd_ppn1),
    .tlbrd_plv1 (tlbrd_plv1),
    .tlbrd_mat1 (tlbrd_mat1),
    .tlbrd_d1   (tlbrd_d1),
    .tlbrd_v1   (tlbrd_v1)
);

// CSR hazard tracking for ID stage
assign es_csr_we  = csr_we_req && es_valid && !ex_pending && !ertn_pending;
assign es_csr_num = csr_num;
assign es_is_ertn = inst_ertn && es_valid;

// ============================================================
// Virtual to physical address translation
// ============================================================
wire [1:0] csr_plv = csr_crmd[1:0];
wire       csr_pg  = csr_crmd[4];

wire inst_dmw0_hit = csr_pg &&
                     (((csr_plv == 2'd0) && csr_dmw0[0]) ||
                      ((csr_plv == 2'd3) && csr_dmw0[3])) &&
                     (inst_vaddr[31:29] == csr_dmw0[31:29]);
wire inst_dmw1_hit = csr_pg &&
                     (((csr_plv == 2'd0) && csr_dmw1[0]) ||
                      ((csr_plv == 2'd3) && csr_dmw1[3])) &&
                     (inst_vaddr[31:29] == csr_dmw1[31:29]);
wire inst_dmw_hit  = inst_dmw0_hit || inst_dmw1_hit;
wire [31:0] inst_dmw_paddr = inst_dmw0_hit ? {csr_dmw0[27:25], inst_vaddr[28:0]} :
                                             {csr_dmw1[27:25], inst_vaddr[28:0]};
wire [31:0] inst_tlb_paddr = (s0_ps == 6'd22) ? {s0_ppn[19:10], inst_vaddr[21:0]} :
                                                 {s0_ppn[19:0],  inst_vaddr[11:0]};
wire inst_use_tlb = csr_pg && !inst_dmw_hit;
wire inst_tlbr_ex = inst_use_tlb && !s0_found;
wire inst_pif_ex  = inst_use_tlb &&  s0_found && !s0_v;
wire inst_ppi_ex  = inst_use_tlb &&  s0_found &&  s0_v && (csr_plv > s0_plv);

assign inst_paddr = !csr_pg       ? inst_vaddr :
                    inst_dmw_hit  ? inst_dmw_paddr :
                                    inst_tlb_paddr;
assign inst_trans_ex = inst_tlbr_ex || inst_pif_ex || inst_ppi_ex;
assign inst_trans_ecode = inst_tlbr_ex ? `ECODE_TLBR :
                          inst_pif_ex  ? `ECODE_PIF  :
                          inst_ppi_ex  ? `ECODE_PPI  : 6'h00;
assign inst_trans_esubcode = 9'h000;

wire data_dmw0_hit = csr_pg &&
                     (((csr_plv == 2'd0) && csr_dmw0[0]) ||
                      ((csr_plv == 2'd3) && csr_dmw0[3])) &&
                     (data_vaddr[31:29] == csr_dmw0[31:29]);
wire data_dmw1_hit = csr_pg &&
                     (((csr_plv == 2'd0) && csr_dmw1[0]) ||
                      ((csr_plv == 2'd3) && csr_dmw1[3])) &&
                     (data_vaddr[31:29] == csr_dmw1[31:29]);
wire data_dmw_hit  = data_dmw0_hit || data_dmw1_hit;
wire [31:0] data_dmw_paddr = data_dmw0_hit ? {csr_dmw0[27:25], data_vaddr[28:0]} :
                                             {csr_dmw1[27:25], data_vaddr[28:0]};
wire [31:0] data_tlb_paddr = (s1_ps == 6'd22) ? {s1_ppn[19:10], data_vaddr[21:0]} :
                                                 {s1_ppn[19:0],  data_vaddr[11:0]};
wire [31:0] data_paddr = !csr_pg      ? data_vaddr :
                         data_dmw_hit ? data_dmw_paddr :
                                        data_tlb_paddr;
wire data_mem_op  = es_load_op || es_mem_we;
wire data_use_tlb = csr_pg && !data_dmw_hit;
wire data_tlbr_ex = es_valid && data_mem_op && data_use_tlb && !s1_found;
wire data_pil_ex  = es_valid && es_load_op && data_use_tlb && s1_found && !s1_v;
wire data_pis_ex  = es_valid && es_mem_we  && data_use_tlb && s1_found && !s1_v;
wire data_ppi_ex  = es_valid && data_mem_op && data_use_tlb && s1_found && s1_v
                    && (csr_plv > s1_plv);
wire data_pme_ex  = es_valid && es_mem_we && data_use_tlb && s1_found && s1_v
                    && (csr_plv <= s1_plv) && !s1_d;
wire data_tlb_ex  = data_tlbr_ex || data_pil_ex || data_pis_ex || data_ppi_ex || data_pme_ex;

// ============================================================
// ALE detection (address alignment error)
// ============================================================
wire ale_ld = es_load_op;
wire ale_st = es_mem_we;

wire ale_w = (ale_ld || ale_st) && (mem_size == 2'b10);  // word access
wire ale_h = (ale_ld || ale_st) && (mem_size == 2'b01);  // halfword access
wire ale_b = (ale_ld || ale_st) && (mem_size == 2'b00);  // byte access

// ALE: word must be 4-byte aligned, halfword must be 2-byte aligned
wire ale_detected = es_valid && (
    (ale_w && (data_vaddr[1:0] != 2'b00)) ||
    (ale_h && (data_vaddr[0]   != 1'b0))
);

// ============================================================
// Unified exception detection
// ============================================================
// Synchronous exceptions from earlier stages (passed via ds_to_es_bus)
wire ex_ds    = ds_ex && es_valid;
wire ex_adef  = ex_ds && (ds_ecode == `ECODE_ADEF);
wire ex_brk   = ex_ds && (ds_ecode == `ECODE_BRK);
wire ex_ine   = ex_ds && (ds_ecode == `ECODE_INE);

// Synchronous exceptions from this stage
wire ex_sys   = inst_syscall && es_valid && !ex_ds;
wire ex_ale   = ale_detected && !ex_ds && !ex_sys;
wire ex_data_tlb = data_tlb_ex && !ex_ds && !ex_sys && !ex_ale;

// Any synchronous exception
wire ex_sync  = ex_ds || ex_sys || ex_ale || ex_data_tlb;

// Interrupt (asynchronous): only when no sync exception
wire ex_int   = has_int && es_valid && !ex_sync;

// Combined exception.  Side effects are committed only when ES can leave,
// so older memory operations cannot be bypassed by a later exception.
assign ex_pending = ex_sync || ex_int;
assign wb_ex = es_commit && ex_pending;

// ============================================================
// Exception info for CSR
// ============================================================
always @(*) begin
    if (ex_ds) begin
        wb_ecode    = ds_ecode;
        wb_esubcode = ds_esubcode;
        wb_badv     = (ds_ecode == `ECODE_ADEF ||
                       ds_ecode == `ECODE_TLBR ||
                       ds_ecode == `ECODE_PIF  ||
                       ds_ecode == `ECODE_PPI) ? es_pc : 32'b0;
    end
    else if (ex_brk) begin
        wb_ecode    = `ECODE_BRK;
        wb_esubcode = 9'h000;
        wb_badv     = 32'b0;
    end
    else if (ex_ine) begin
        wb_ecode    = `ECODE_INE;
        wb_esubcode = 9'h000;
        wb_badv     = 32'b0;
    end
    else if (ex_sys) begin
        wb_ecode    = `ECODE_SYSCALL;
        wb_esubcode = 9'h000;
        wb_badv     = 32'b0;
    end
    else if (ex_ale) begin
        wb_ecode    = `ECODE_ALE;
        wb_esubcode = 9'h000;
        wb_badv     = data_vaddr;
    end
    else if (ex_data_tlb) begin
        wb_ecode    = data_tlbr_ex ? `ECODE_TLBR :
                      data_pil_ex  ? `ECODE_PIL  :
                      data_pis_ex  ? `ECODE_PIS  :
                      data_ppi_ex  ? `ECODE_PPI  :
                                      `ECODE_PME;
        wb_esubcode = 9'h000;
        wb_badv     = data_vaddr;
    end
    else if (ex_int) begin
        wb_ecode    = `ECODE_INT;
        wb_esubcode = 9'h000;
        wb_badv     = 32'b0;
    end
    else begin
        wb_ecode    = 6'h00;
        wb_esubcode = 9'h000;
        wb_badv     = 32'b0;
    end
end

// Flush: exception or ertn
assign flush = wb_ex;

// ERTN
assign ertn_flush = es_commit && ertn_pending;

// ============================================================
// rdcntv / rdcntid result
// ============================================================
wire [31:0] rdcntv_result;
assign rdcntv_result = ds_rdcntv_hi ? cnt_high : cnt_low;

// Use always_comb to prevent X propagation in result mux
// (if-else treats X conditions as false, vs ?: which merges both branches)
reg [31:0] exe_result;
wire       exe_csr_sel = is_csr && !wb_ex && !ertn_flush;
always @(*) begin
    if (ds_rdcntid === 1'b1)
        exe_result = tid_val;
    else if (ds_rdcntv === 1'b1)
        exe_result = rdcntv_result;
    else if (exe_csr_sel === 1'b1)
        exe_result = csr_rvalue;
    else if (div_op === 1'b1)
        exe_result = div_result;
    else if (res_from_mem === 1'b1 || es_mem_we === 1'b1)
        exe_result = mem_addr;
    else
        exe_result = alu_result;
end

reg exe_gr_we;
always @(*) begin
    if (ex_pending === 1'b1 || ertn_pending === 1'b1)
        exe_gr_we = 1'b0;
    else
        exe_gr_we = gr_we;
end

// ============================================================
// Data SRAM interface
// ============================================================
wire [3:0] st_b_we;
wire [3:0] st_h_we;
wire [3:0] st_w_we;
wire [31:0] st_b_wdata;
wire [31:0] st_h_wdata;
wire [31:0] st_w_wdata;

assign st_b_we    = 4'b0001 << data_vaddr[1:0];
assign st_h_we    = data_vaddr[1] ? 4'b1100 : 4'b0011;
assign st_w_we    = 4'b1111;
assign st_b_wdata = {4{rkd_value[7:0]}} << {data_vaddr[1:0], 3'b000};
assign st_h_wdata = data_vaddr[1] ? {rkd_value[15:0], 16'b0} : {16'b0, rkd_value[15:0]};
assign st_w_wdata = rkd_value;

// Suppress memory access on exceptions.
wire mem_access_ok = es_valid && !ex_pending;
wire es_mem_access = (res_from_mem || es_mem_we) && mem_access_ok;

assign data_sram_req    = es_valid && es_mem_access && ms_allowin;
assign data_sram_wr     = es_mem_we && mem_access_ok;
assign data_sram_size   = mem_size;
assign data_sram_wstrb  = es_mem_we && mem_access_ok ?
                            ((mem_size == 2'b00) ? st_b_we :
                             (mem_size == 2'b01) ? st_h_we : st_w_we) : 4'h0;
assign data_sram_addr   = data_paddr;
assign data_sram_wdata  = (mem_size == 2'b00) ? st_b_wdata :
                         (mem_size == 2'b01) ? st_h_wdata : st_w_wdata;

// ============================================================
// Pipeline control
// ============================================================
assign es_ready_go    = div_op ? div_done : (!es_mem_access || data_sram_addr_ok);
assign es_allowin     = !es_valid || es_ready_go && ms_allowin;
assign es_to_ms_valid = es_valid && es_ready_go;

always @(posedge clk) begin
    if (reset) begin
        es_valid <= 1'b0;
    end
    else if (flush || ertn_flush) begin
        es_valid <= 1'b0;
    end
    else if (es_allowin) begin
        es_valid <= ds_to_es_valid;
    end

    if (ds_to_es_valid && es_allowin && !flush && !ertn_flush) begin
        ds_to_es_bus_r <= ds_to_es_bus;
    end
end

// ============================================================
// Bus output
// ============================================================
assign es_to_ms_bus = {es_mem_access, //74:74 1
                       res_from_mem,  //73:73 1
                       mem_size    ,  //72:71 2
                       mem_unsigned,  //70:70 1
                       exe_gr_we   ,  //69:69 1
                       dest        ,  //68:64 5
                       exe_result  ,  //63:32 32
                       es_pc          //31:0  32
                      };

// ============================================================
// Forward to ID
// ============================================================
assign es_to_ds_dest = dest & {5{es_valid}} & {5{gr_we}};
assign es_to_ds_load_op = es_valid && gr_we;
assign es_to_ds_result = 32'b0;

endmodule
