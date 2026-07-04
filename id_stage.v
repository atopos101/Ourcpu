`include "mycpu.vh"

module id_stage(
    input                          clk           ,
    input                          reset         ,
    input                          flush         ,
    input                          ibar_flush    ,
    //allowin
    input                          es_allowin    ,
    output                         ds_allowin    ,
    //from fs
    input                          fs_to_ds_valid,
    input  [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus  ,
    //to es
    output                         ds_to_es_valid,
    output [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus  ,
    //to fs
    output [`BR_BUS_WD       -1:0] br_bus        ,
    //to rf: for write back
    input  [`WS_TO_RF_BUS_WD -1:0] ws_to_rf_bus  ,
    // hazard detect
    input [4:0] ex1_to_ds_dest,
    input [4:0] ex2_to_ds_dest,
    input [4:0] ms_to_ds_dest,
    input [4:0] ws_to_ds_dest,
    input       ex1_to_ds_result_ready,
    input       ex2_to_ds_result_ready,
    input       ms_to_ds_result_ready,
    input       ws_to_ds_result_ready,
    input [31:0] ex1_to_ds_result,
    input [31:0] ex2_to_ds_result,
    input [31:0] ms_to_ds_result,
    input [31:0] ws_to_ds_result,
    // csr hazard tracking from EX1/EX2
    input        ex1_csr_we,
    input [13:0] ex1_csr_num,
    input        ex1_is_ertn,
    input        ex2_csr_we,
    input [13:0] ex2_csr_num,
    input        ex2_is_ertn,
    // ertn flush
    input        ertn_flush
);

wire        br_taken;
wire [31:0] br_target;

wire [31:0] ds_pc;
wire [31:0] ds_inst;
wire        fs_ex;        // fetch exception from IF stage
wire [ 5:0] fs_ecode;
wire [ 8:0] fs_esubcode;

reg         ds_valid   ;
wire        ds_ready_go;

wire [18:0] alu_op;

wire        load_op;
wire [ 1:0] mem_size;
wire        mem_unsigned;
wire        store_op;
wire        branch_op;
wire        src1_is_pc;
wire        src2_is_imm;
wire        res_from_mem;
wire        dst_is_r1;
wire        gr_we;
wire        mem_we;
wire        src_reg_is_rd;
wire [4: 0] dest;
wire [31:0] rj_value;
wire [31:0] rkd_value;
wire [31:0] imm;
wire [31:0] br_offs;
wire [31:0] jirl_offs;

wire [ 5:0] op_31_26;
wire [ 3:0] op_25_22;
wire [ 1:0] op_21_20;
wire [ 4:0] op_19_15;
wire [ 4:0] rd;
wire [ 4:0] rj;
wire [ 4:0] rk;
wire [11:0] i12;
wire [19:0] i20;
wire [15:0] i16;
wire [25:0] i26;
wire [13:0] si14;

wire [63:0] op_31_26_d;
wire [15:0] op_25_22_d;
wire [ 3:0] op_21_20_d;
wire [31:0] op_19_15_d;

wire        inst_add_w;
wire        inst_sub_w;
wire        inst_slt;
wire        inst_sltu;
wire        inst_nor;
wire        inst_and;
wire        inst_or;
wire        inst_xor;
wire        inst_slli_w;
wire        inst_srli_w;
wire        inst_srai_w;
wire        inst_addi_w;
wire        inst_ld_b;
wire        inst_ld_h;
wire        inst_ld_w;
wire        inst_ld_bu;
wire        inst_ld_hu;
wire        inst_st_b;
wire        inst_st_h;
wire        inst_st_w;
wire        inst_ll_w;
wire        inst_sc_w;
wire        inst_dbar;
wire        inst_ibar;
wire        inst_idle;
wire        inst_jirl;
wire        inst_b;
wire        inst_bl;
wire        inst_beq;
wire        inst_bne;
wire        inst_blt;
wire        inst_bge;
wire        inst_bltu;
wire        inst_bgeu;
wire        inst_lu12i_w;
wire        inst_pcaddu12i;
wire        inst_slti;
wire        inst_sltui;
wire        inst_andi;
wire        inst_ori;
wire        inst_xori;
wire        inst_sll_w;
wire        inst_srl_w;
wire        inst_sra_w;
wire        inst_div_w;
wire        inst_mul_w;
wire        inst_mulh_w;
wire        inst_mulh_wu;
wire        inst_mod_w;
wire        inst_div_wu;
wire        inst_mod_wu;

wire        need_ui5;
wire        need_si12;
wire        need_ui12;
wire        need_si16;
wire        need_si20;
wire        need_si26;
wire        src2_is_4;

wire [ 4:0] rf_raddr1;
wire [31:0] rf_rdata1;
wire [ 4:0] rf_raddr2;
wire [31:0] rf_rdata2;

wire        rf_we   ;
wire [ 4:0] rf_waddr;
wire [31:0] rf_wdata;

wire [31:0] alu_src1   ;
wire [31:0] alu_src2   ;
wire [31:0] alu_result ;

wire [31:0] mem_result;
wire [31:0] final_result;

// hazard detection
wire inst_no_dest;
wire src_no_rj;
wire src_no_rk;
wire src_no_rd;
wire rj_wait;
wire rk_wait;
wire rd_wait;

wire br_stall;
wire producer_not_ready_stall;
wire rj_eq_rd;
wire rj_lt_rd;
wire rj_ltu_rd;

assign op_31_26  = ds_inst[31:26];
assign op_25_22  = ds_inst[25:22];
assign op_21_20  = ds_inst[21:20];
assign op_19_15  = ds_inst[19:15];

assign rd   = ds_inst[ 4: 0];
assign rj   = ds_inst[ 9: 5];
assign rk   = ds_inst[14:10];

assign i12  = ds_inst[21:10];
assign i20  = ds_inst[24: 5];
assign i16  = ds_inst[25:10];
assign i26  = {ds_inst[ 9: 0], ds_inst[25:10]};
assign si14 = ds_inst[23:10];

decoder_6_64 u_dec0(.in(op_31_26 ), .out(op_31_26_d ));
decoder_4_16 u_dec1(.in(op_25_22 ), .out(op_25_22_d ));
decoder_2_4  u_dec2(.in(op_21_20 ), .out(op_21_20_d ));
decoder_5_32 u_dec3(.in(op_19_15 ), .out(op_19_15_d ));

// ============================================================
// Arithmetic & logical
// ============================================================
assign inst_add_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
assign inst_sub_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
assign inst_slt    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
assign inst_sltu   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
assign inst_nor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
assign inst_and    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
assign inst_or     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
assign inst_xor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
assign inst_slli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
assign inst_srli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
assign inst_srai_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
assign inst_addi_w = op_31_26_d[6'h00] & op_25_22_d[4'ha];
assign inst_slti   = op_31_26_d[6'h00] & op_25_22_d[4'h8];
assign inst_sltui  = op_31_26_d[6'h00] & op_25_22_d[4'h9];
assign inst_andi   = op_31_26_d[6'h00] & op_25_22_d[4'hd];
assign inst_ori    = op_31_26_d[6'h00] & op_25_22_d[4'he];
assign inst_xori   = op_31_26_d[6'h00] & op_25_22_d[4'hf];
assign inst_lu12i_w= op_31_26_d[6'h05] & ~ds_inst[25];
assign inst_pcaddu12i = op_31_26_d[6'h07];

// ============================================================
// Shift (3R-type)
// ============================================================
assign inst_sll_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0e];
assign inst_srl_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0f];
assign inst_sra_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h10];

// ============================================================
// Multiply / Divide / Modulo
// ============================================================
assign inst_div_w   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h00];
assign inst_mul_w   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h18];
assign inst_mulh_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h19];
assign inst_mulh_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h1a];
assign inst_mod_w   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h01];
assign inst_div_wu  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h02];
assign inst_mod_wu  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h03];

// ============================================================
// Load / Store
// ============================================================
assign inst_ld_b  = op_31_26_d[6'h0a] & op_25_22_d[4'h0];
assign inst_ld_h  = op_31_26_d[6'h0a] & op_25_22_d[4'h1];
assign inst_ld_w  = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
assign inst_st_b  = op_31_26_d[6'h0a] & op_25_22_d[4'h4];
assign inst_st_h  = op_31_26_d[6'h0a] & op_25_22_d[4'h5];
assign inst_st_w  = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
assign inst_ld_bu = op_31_26_d[6'h0a] & op_25_22_d[4'h8];
assign inst_ld_hu = op_31_26_d[6'h0a] & op_25_22_d[4'h9];
wire inst_preld;
assign inst_preld = op_31_26_d[6'h0a] & op_25_22_d[4'hb];
assign inst_ll_w  = ds_inst[31:24] == 8'h20;
assign inst_sc_w  = ds_inst[31:24] == 8'h21;

// Barrier instructions: fixed bits [31:15], hint in [14:0].
assign inst_dbar = op_31_26_d[6'h0e] & op_25_22_d[4'h1] &
                   op_21_20_d[2'h3]  & op_19_15_d[5'h04];
assign inst_ibar = op_31_26_d[6'h0e] & op_25_22_d[4'h1] &
                   op_21_20_d[2'h3]  & op_19_15_d[5'h05];

// IDLE level: fixed bits [31:15] = 17'b00000110010010001.
assign inst_idle = op_31_26_d[6'h01] & op_25_22_d[4'h9] &
                   op_21_20_d[2'h0]  & op_19_15_d[5'h11];

// ============================================================
// Branch / Jump
// ============================================================
assign inst_jirl = op_31_26_d[6'h13];
assign inst_b    = op_31_26_d[6'h14];
assign inst_bl   = op_31_26_d[6'h15];
assign inst_beq  = op_31_26_d[6'h16];
assign inst_bne  = op_31_26_d[6'h17];
assign inst_blt  = op_31_26_d[6'h18];
assign inst_bge  = op_31_26_d[6'h19];
assign inst_bltu = op_31_26_d[6'h1a];
assign inst_bgeu = op_31_26_d[6'h1b];

// ============================================================
// CSR instructions
// ============================================================
wire        inst_csr;
wire        inst_csrrd;
wire        inst_csrwr;
wire        inst_csrxchg;
wire [ 1:0] csr_op;
wire [13:0] csr_num;

assign csr_num       = ds_inst[23:10];
assign inst_csr      = (ds_inst[31:24] == 8'b00000100);
assign inst_csrrd    = inst_csr & (rj == 5'b00000);
assign inst_csrwr    = inst_csr & (rj == 5'b00001);
assign inst_csrxchg  = inst_csr & (rj != 5'b00000) & (rj != 5'b00001);

assign csr_op = inst_csrrd   ? 2'b01 :
                inst_csrwr   ? 2'b10 :
                inst_csrxchg ? 2'b11 : 2'b00;

// ============================================================
// System instructions
// ============================================================
// SYSCALL: op_31_26=0, op_25_22=0, op_21_20=2, op_19_15=0x16
wire inst_syscall;
assign inst_syscall = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h16];

// ERTN / TLB: op_31_26=1, op_25_22=9, op_21_20=0.
wire inst_ertn;
wire inst_tlb_base;
wire inst_tlbsrch;
wire inst_tlbrd;
wire inst_tlbwr;
wire inst_tlbfill;
wire inst_invtlb_base;
wire inst_invtlb;
wire inst_cacop;
wire [2:0] tlb_op;
wire [4:0] invtlb_op;
wire [4:0] cacop_code;

assign inst_tlb_base = op_31_26_d[6'h01] & op_25_22_d[4'h9] & op_21_20_d[2'h0];
assign inst_tlbsrch  = inst_tlb_base & op_19_15_d[5'h10] & (ds_inst[14:10] == 5'h0a) & (rj == 5'b0) & (rd == 5'b0);
assign inst_tlbrd    = inst_tlb_base & op_19_15_d[5'h10] & (ds_inst[14:10] == 5'h0b) & (rj == 5'b0) & (rd == 5'b0);
assign inst_tlbwr    = inst_tlb_base & op_19_15_d[5'h10] & (ds_inst[14:10] == 5'h0c) & (rj == 5'b0) & (rd == 5'b0);
assign inst_tlbfill  = inst_tlb_base & op_19_15_d[5'h10] & (ds_inst[14:10] == 5'h0d) & (rj == 5'b0) & (rd == 5'b0);
assign inst_ertn     = inst_tlb_base & op_19_15_d[5'h10] & (ds_inst[14:10] == 5'h0e) & (rj == 5'b0) & (rd == 5'b0);

assign inst_invtlb_base = inst_tlb_base & op_19_15_d[5'h13];
assign inst_invtlb      = inst_invtlb_base & (rd <= 5'd6);
assign invtlb_op        = rd;
assign inst_cacop       = (ds_inst[31:22] == 10'b0000011000);
assign cacop_code       = rd;

assign tlb_op = inst_tlbsrch ? 3'd1 :
                inst_tlbrd   ? 3'd2 :
                inst_tlbwr   ? 3'd3 :
                inst_tlbfill ? 3'd4 :
                inst_invtlb  ? 3'd5 : 3'd0;

// BREAK: op_31_26=0, op_25_22=0, op_21_20=2, op_19_15=0x14
wire inst_break;
assign inst_break  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h14];

// ============================================================
// RDTIME / counter instructions
// ============================================================
// rdcntvl.w (RDTIMEL.W): op_31_26=0, op_25_22=0, op_21_20=0,
// op_19_15=0x00, bits[14:10]=0x18, rd!=0.  rd=0 encodes rdcntid.
wire inst_rdcntvl_w;
assign inst_rdcntvl_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h0]
                        & op_19_15_d[5'h00] & (ds_inst[14:10] == 5'h18) & (rd != 5'b0);

// rdcntvh.w (RDTIMEH.W): op_31_26=0, op_25_22=0, op_21_20=0,
// op_19_15=0x00, bits[14:10]=0x19.
wire inst_rdcntvh_w;
assign inst_rdcntvh_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h0]
                        & op_19_15_d[5'h00] & (ds_inst[14:10] == 5'h19);

// rdcntid: same base encoding as rdcntvl.w, with rd=0 and destination in rj.
wire inst_rdcntid;
assign inst_rdcntid   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h0]
                        & op_19_15_d[5'h00] & (ds_inst[14:10] == 5'h18) & (rd == 5'b0);

wire inst_rdcntv = inst_rdcntvl_w | inst_rdcntvh_w;

// ============================================================
// Instruction valid whitelist (for INE detection)
// ============================================================
wire inst_valid;
assign inst_valid = inst_add_w | inst_sub_w | inst_slt | inst_sltu |
                    inst_nor | inst_and | inst_or | inst_xor |
                    inst_slli_w | inst_srli_w | inst_srai_w |
                    inst_addi_w | inst_slti | inst_sltui | inst_andi | inst_ori | inst_xori |
                    inst_ld_b | inst_ld_h | inst_ld_w | inst_ld_bu | inst_ld_hu | inst_preld |
                    inst_st_b | inst_st_h | inst_st_w | inst_ll_w | inst_sc_w |
                    inst_jirl | inst_b | inst_bl |
                    inst_beq | inst_bne | inst_blt | inst_bge | inst_bltu | inst_bgeu |
                    inst_lu12i_w | inst_pcaddu12i |
                    inst_sll_w | inst_srl_w | inst_sra_w |
                    inst_div_w | inst_mul_w | inst_mulh_w | inst_mulh_wu |
                    inst_mod_w | inst_div_wu | inst_mod_wu |
                    inst_csrrd | inst_csrwr | inst_csrxchg |
                    inst_syscall | inst_ertn | inst_break |
                    inst_rdcntvl_w | inst_rdcntvh_w | inst_rdcntid |
                    inst_tlbsrch | inst_tlbrd | inst_tlbwr | inst_tlbfill | inst_invtlb |
                    inst_cacop | inst_dbar | inst_ibar | inst_idle;

// ============================================================
// Common decode helpers
// ============================================================
assign load_op      = inst_ld_b | inst_ld_h | inst_ld_w | inst_ld_bu | inst_ld_hu | inst_ll_w;
assign store_op     = inst_st_b | inst_st_h | inst_st_w | inst_sc_w;
assign branch_op    = inst_beq | inst_bne | inst_blt | inst_bge | inst_bltu | inst_bgeu;

assign mem_size     = (inst_ld_b | inst_ld_bu | inst_st_b) ? 2'b00 :
                      (inst_ld_h | inst_ld_hu | inst_st_h) ? 2'b01 : 2'b10;
assign mem_unsigned = inst_ld_bu | inst_ld_hu;

assign alu_op[ 0] = inst_add_w | inst_addi_w | load_op | store_op | inst_cacop
                    | inst_jirl | inst_bl | inst_pcaddu12i;
assign alu_op[ 1] = inst_sub_w;
assign alu_op[ 2] = inst_slt | inst_slti;
assign alu_op[ 3] = inst_sltu | inst_sltui;
assign alu_op[ 4] = inst_and | inst_andi;
assign alu_op[ 5] = inst_nor;
assign alu_op[ 6] = inst_or | inst_ori;
assign alu_op[ 7] = inst_xor | inst_xori;
assign alu_op[ 8] = inst_slli_w | inst_sll_w;
assign alu_op[ 9] = inst_srli_w | inst_srl_w;
assign alu_op[10] = inst_srai_w | inst_sra_w;
assign alu_op[11] = inst_lu12i_w;
assign alu_op[12] = inst_div_w;
assign alu_op[13] = inst_mul_w;
assign alu_op[14] = inst_mulh_w;
assign alu_op[15] = inst_mulh_wu;
assign alu_op[16] = inst_mod_w;
assign alu_op[17] = inst_div_wu;
assign alu_op[18] = inst_mod_wu;

assign need_ui5   = inst_slli_w | inst_srli_w | inst_srai_w;
assign need_si12  = inst_addi_w | load_op | store_op | inst_cacop | inst_slti | inst_sltui;
assign need_ui12  = inst_andi | inst_ori | inst_xori;
assign need_si16  = inst_jirl | branch_op;
assign need_si20  = inst_lu12i_w | inst_pcaddu12i;
assign need_si26  = inst_b | inst_bl;
assign src2_is_4  = inst_jirl | inst_bl;

assign imm = src2_is_4 ? 32'h4                      :
             need_si20 ? {i20[19:0], 12'b0}         :
             need_ui12 ? {20'b0, i12[11:0]}          :
             (inst_ll_w | inst_sc_w)
                       ? {{16{si14[13]}}, si14, 2'b0} :
            /*need_si12*/{{20{i12[11]}}, i12[11:0]} ;

assign br_offs = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                              {{14{i16[15]}}, i16[15:0], 2'b0} ;

assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

assign src_reg_is_rd = branch_op | store_op | inst_csrwr | inst_csrxchg;

assign src1_is_pc    = inst_jirl | inst_bl | inst_pcaddu12i;

assign src2_is_imm   = inst_slli_w |
                       inst_srli_w |
                       inst_srai_w |
                       inst_addi_w |
                       load_op     |
                       store_op    |
                       inst_cacop   |
                       inst_lu12i_w|
                       inst_pcaddu12i |
                       inst_slti    |
                       inst_sltui   |
                       inst_andi    |
                       inst_ori     |
                       inst_xori    |
                       inst_jirl   |
                       inst_bl     ;

assign res_from_mem  = load_op;
assign dst_is_r1     = inst_bl;

// gr_we: rdcntv and rdcntid write GR; break/syscall/ertn do not
assign gr_we = inst_rdcntv | inst_rdcntid |
               inst_sc_w |
               (~store_op & ~inst_preld & ~branch_op & ~inst_b & ~inst_syscall & ~inst_ertn & ~inst_break
                & ~inst_tlbsrch & ~inst_tlbrd & ~inst_tlbwr & ~inst_tlbfill & ~inst_invtlb_base
                & ~inst_cacop & ~inst_dbar & ~inst_ibar & ~inst_idle);
assign mem_we = store_op;

assign dest  = dst_is_r1    ? 5'd1 :
               inst_rdcntid ? rj   : rd;

// ============================================================
// Register file
// ============================================================
assign rf_raddr1 = rj;
assign rf_raddr2 = src_reg_is_rd ? rd : rk;

regfile u_regfile(
    .clk    (clk      ),
    .raddr1 (rf_raddr1),
    .rdata1 (rf_rdata1),
    .raddr2 (rf_raddr2),
    .rdata2 (rf_rdata2),
    .we     (rf_we    ),
    .waddr  (rf_waddr ),
    .wdata  (rf_wdata )
    );

wire rj_hit_ex1 = ~src_no_rj && (rj != 5'b00000) && (rj == ex1_to_ds_dest);
wire rj_hit_ex2 = ~src_no_rj && (rj != 5'b00000) && (rj == ex2_to_ds_dest);
wire rj_hit_ms  = ~src_no_rj && (rj != 5'b00000) && (rj == ms_to_ds_dest);
wire rj_hit_ws  = ~src_no_rj && (rj != 5'b00000) && (rj == ws_to_ds_dest);
wire rk_hit_ex1 = ~src_no_rk && (rk != 5'b00000) && (rk == ex1_to_ds_dest);
wire rk_hit_ex2 = ~src_no_rk && (rk != 5'b00000) && (rk == ex2_to_ds_dest);
wire rk_hit_ms  = ~src_no_rk && (rk != 5'b00000) && (rk == ms_to_ds_dest);
wire rk_hit_ws  = ~src_no_rk && (rk != 5'b00000) && (rk == ws_to_ds_dest);
wire rd_hit_ex1 = ~src_no_rd && (rd != 5'b00000) && (rd == ex1_to_ds_dest);
wire rd_hit_ex2 = ~src_no_rd && (rd != 5'b00000) && (rd == ex2_to_ds_dest);
wire rd_hit_ms  = ~src_no_rd && (rd != 5'b00000) && (rd == ms_to_ds_dest);
wire rd_hit_ws  = ~src_no_rd && (rd != 5'b00000) && (rd == ws_to_ds_dest);

wire [31:0] rj_forward_result = rj_hit_ex1 ? ex1_to_ds_result :
                                rj_hit_ex2 ? ex2_to_ds_result :
                                rj_hit_ms  ? ms_to_ds_result  :
                                             ws_to_ds_result;
wire [31:0] rk_forward_result = rk_hit_ex1 ? ex1_to_ds_result :
                                rk_hit_ex2 ? ex2_to_ds_result :
                                rk_hit_ms  ? ms_to_ds_result  :
                                             ws_to_ds_result;
wire [31:0] rd_forward_result = rd_hit_ex1 ? ex1_to_ds_result :
                                rd_hit_ex2 ? ex2_to_ds_result :
                                rd_hit_ms  ? ms_to_ds_result  :
                                             ws_to_ds_result;

assign rj_value  = rj_wait ? rj_forward_result : rf_rdata1;
assign rkd_value = rk_wait ? rk_forward_result :
                   rd_wait ? rd_forward_result :
                   rf_rdata2;

// ============================================================
// Branch logic
// ============================================================
assign rj_eq_rd  = (rj_value == rkd_value);
assign rj_lt_rd  = ($signed(rj_value) < $signed(rkd_value));
assign rj_ltu_rd = (rj_value < rkd_value);

assign br_taken = (   inst_beq  &&  rj_eq_rd
                   || inst_bne  && !rj_eq_rd
                   || inst_blt  &&  rj_lt_rd
                   || inst_bge  && !rj_lt_rd
                   || inst_bltu &&  rj_ltu_rd
                   || inst_bgeu && !rj_ltu_rd
                   || inst_jirl
                   || inst_bl
                   || inst_b
                  ) && ds_ready_go && es_allowin && (fs_ex !== 1'b1);

assign inst_no_dest = (store_op & ~inst_sc_w) | inst_preld | inst_b | branch_op | inst_tlbsrch | inst_tlbrd
                      | inst_tlbwr | inst_tlbfill | inst_invtlb_base | inst_cacop
                      | inst_dbar | inst_ibar | inst_idle;

// ============================================================
// Hazard detection
// ============================================================
assign src_no_rj = inst_b | inst_bl | inst_lu12i_w | inst_pcaddu12i
                   | inst_csrrd | inst_csrwr | inst_syscall | inst_ertn
                   | inst_rdcntv | inst_rdcntid
                   | inst_tlbsrch | inst_tlbrd | inst_tlbwr | inst_tlbfill
                   | inst_dbar | inst_ibar | inst_idle;
assign src_no_rk = inst_slli_w | inst_srli_w | inst_srai_w | inst_addi_w | load_op | store_op
                   | inst_jirl | inst_b | inst_bl | branch_op | inst_lu12i_w | inst_pcaddu12i
                   | inst_slti | inst_sltui | inst_andi | inst_ori | inst_xori
                   | inst_csrrd | inst_csrwr | inst_csrxchg | inst_syscall | inst_ertn
                   | inst_rdcntv | inst_rdcntid
                   | inst_tlbsrch | inst_tlbrd | inst_tlbwr | inst_tlbfill
                   | inst_dbar | inst_ibar | inst_idle;
assign src_no_rd = inst_dbar | inst_ibar | inst_idle |
                   (~store_op & ~branch_op & ~inst_csrwr & ~inst_csrxchg);

assign rj_wait = rj_hit_ex1 || rj_hit_ex2 || rj_hit_ms || rj_hit_ws;
assign rk_wait = rk_hit_ex1 || rk_hit_ex2 || rk_hit_ms || rk_hit_ws;
assign rd_wait = rd_hit_ex1 || rd_hit_ex2 || rd_hit_ms || rd_hit_ws;

assign br_target = (branch_op || inst_bl || inst_b) ? (ds_pc + br_offs) :
                                                   /*inst_jirl*/ (rj_value + jirl_offs);

wire rj_not_ready = rj_hit_ex1 ? !ex1_to_ds_result_ready :
                    rj_hit_ex2 ? !ex2_to_ds_result_ready :
                    rj_hit_ms  ? !ms_to_ds_result_ready  :
                    rj_hit_ws  ? !ws_to_ds_result_ready  : 1'b0;
wire rk_not_ready = rk_hit_ex1 ? !ex1_to_ds_result_ready :
                    rk_hit_ex2 ? !ex2_to_ds_result_ready :
                    rk_hit_ms  ? !ms_to_ds_result_ready  :
                    rk_hit_ws  ? !ws_to_ds_result_ready  : 1'b0;
wire rd_not_ready = rd_hit_ex1 ? !ex1_to_ds_result_ready :
                    rd_hit_ex2 ? !ex2_to_ds_result_ready :
                    rd_hit_ms  ? !ms_to_ds_result_ready  :
                    rd_hit_ws  ? !ws_to_ds_result_ready  : 1'b0;

assign producer_not_ready_stall = rj_not_ready || rk_not_ready || rd_not_ready;
assign br_stall = producer_not_ready_stall & br_taken & ds_valid;
assign br_bus = {br_stall, br_taken, br_target};

// ============================================================
// CSR hazard detection — writer monitor
// ============================================================
localparam CSR_CRMD_NO  = 14'h00;
localparam CSR_PRMD_NO  = 14'h01;
localparam CSR_ECFG_NO  = 14'h04;
localparam CSR_ERA_NO   = 14'h06;
localparam CSR_TCFG_NO  = 14'h41;
localparam CSR_TICLR_NO = 14'h44;

wire ex1_writes_int_csr;
assign ex1_writes_int_csr = ex1_csr_we && (
    ex1_csr_num == CSR_CRMD_NO  ||
    ex1_csr_num == CSR_ECFG_NO  ||
    ex1_csr_num == CSR_TCFG_NO  ||
    ex1_csr_num == CSR_TICLR_NO
);

wire ex2_writes_int_csr;
assign ex2_writes_int_csr = ex2_csr_we && (
    ex2_csr_num == CSR_CRMD_NO  ||
    ex2_csr_num == CSR_ECFG_NO  ||
    ex2_csr_num == CSR_TCFG_NO  ||
    ex2_csr_num == CSR_TICLR_NO
);

wire ex1_writes_ertn_csr;
assign ex1_writes_ertn_csr = ex1_csr_we && (
    ex1_csr_num == CSR_ERA_NO  ||
    ex1_csr_num == CSR_PRMD_NO
);

wire ex2_writes_ertn_csr;
assign ex2_writes_ertn_csr = ex2_csr_we && (
    ex2_csr_num == CSR_ERA_NO  ||
    ex2_csr_num == CSR_PRMD_NO
);

wire id_needs_int_csr  = 1'b1;
wire id_needs_ertn_csr = inst_ertn;

wire csr_stall;
assign csr_stall = ds_valid && (
    (id_needs_int_csr  && (ex1_writes_int_csr || ex2_writes_int_csr))   ||
    (id_needs_ertn_csr && (ex1_writes_ertn_csr || ex2_writes_ertn_csr)) ||
    (id_needs_int_csr  && (ex1_is_ertn || ex2_is_ertn))
);

// ============================================================
// Exception detection in ID stage
// ============================================================
// fs_ex comes from IF stage (ADEF)
wire inst_ine = ds_valid && (fs_ex !== 1'b1) && ~inst_valid;

// ID exception signals (passed to ES)
wire ds_ex = (fs_ex || inst_break || inst_ine) && ds_valid;

wire [5:0] ds_ecode =
    fs_ex      ? fs_ecode :
    inst_break ? `ECODE_BRK :
    inst_ine   ? `ECODE_INE :
    6'h00;

wire [8:0] ds_esubcode = fs_ex ? fs_esubcode : 9'h000;

// ============================================================
// FS -> DS bus register
// ============================================================
reg  [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus_r;

assign {ds_inst,
        ds_pc,
        fs_ex,
        fs_ecode,
        fs_esubcode} = fs_to_ds_bus_r;

// ============================================================
// Write-back bus unpack
// ============================================================
assign {rf_we   ,  //37:37
        rf_waddr,  //36:32
        rf_wdata   //31:0
       } = ws_to_rf_bus;

// ============================================================
// DS -> ES bus
// Format: {ds_ex, ds_ecode, ds_esubcode, rdcntv, rdcntvh, rdcntid,
//           tlb_op, invtlb_op, inst_cacop, cacop_code,
//           original 180-bit fields}
// ============================================================
assign ds_to_es_bus = {ds_ex,
                       ds_ecode,
                       ds_esubcode,
                       ds_inst,
                       inst_ll_w,
                       inst_sc_w,
                       inst_dbar,
                       inst_ibar,
                       inst_idle,
                       inst_rdcntv,
                       inst_rdcntvh_w,
                       inst_rdcntid,
                       tlb_op,
                       invtlb_op,
                       inst_cacop,
                       cacop_code,
                       // original 180-bit payload
                       alu_op       ,
                       load_op      ,
                       mem_size     ,
                       mem_unsigned ,
                       src1_is_pc   ,
                       src2_is_imm  ,
                       src2_is_4    ,
                       gr_we        ,
                       mem_we       ,
                       dest         ,
                       imm          ,
                       rj_value     ,
                       rkd_value    ,
                       ds_pc        ,
                       res_from_mem ,
                       csr_op       ,
                       csr_num      ,
                       inst_syscall ,
                       inst_ertn
                      };

// ============================================================
// Pipeline control
// ============================================================
assign ds_ready_go    = ds_valid && ~producer_not_ready_stall && ~csr_stall &&
                        !flush && !ertn_flush && !ibar_flush;
assign ds_allowin     = !ds_valid || ds_ready_go && es_allowin;
assign ds_to_es_valid = ds_valid && ds_ready_go;

always @(posedge clk) begin
    if (reset || flush || ertn_flush || ibar_flush || br_taken) begin
        ds_valid <= 1'b0;
    end
    else if (ds_allowin) begin
        ds_valid <= fs_to_ds_valid;
    end

    if (fs_to_ds_valid && ds_allowin && !flush && !ertn_flush &&
        !ibar_flush && !br_taken) begin
        fs_to_ds_bus_r <= fs_to_ds_bus;
    end
end

endmodule
