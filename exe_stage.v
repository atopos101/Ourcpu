`include "mycpu.vh"

module ex1_stage(
    input                          clk           ,
    input                          reset         ,
    input                          flush         ,
    input                          ertn_flush    ,
    input                          ibar_flush    ,
    input                          ex2_empty     ,
    input                          ex2_allowin   ,
    output                         ex1_allowin   ,
    input                          id_to_ex1_valid,
    input  [`ID_TO_EX1_BUS_WD -1:0] id_to_ex1_bus,
    output                         ex1_to_ex2_valid,
    output [`EX1_TO_EX2_BUS_WD -1:0] ex1_to_ex2_bus,
    output [4:0]                  ex1_to_ds_dest,
    output                        ex1_to_ds_result_ready,
    output [31:0]                 ex1_to_ds_result,
    output                        ex1_csr_we,
    output [13:0]                 ex1_csr_num,
    output                        ex1_is_ertn
);

reg         ex1_valid;
reg [`ID_TO_EX1_BUS_WD -1:0] id_to_ex1_bus_r;

wire        ds_ex;
wire [ 5:0] ds_ecode;
wire [ 8:0] ds_esubcode;
wire [31:0] ds_inst;
wire        inst_ll_w;
wire        inst_sc_w;
wire        inst_dbar;
wire        inst_ibar;
wire        inst_idle;
wire        ds_rdcntv;
wire        ds_rdcntv_hi;
wire        ds_rdcntid;
wire [ 2:0] tlb_op;
wire [ 4:0] invtlb_op;
wire        inst_cacop;
wire [ 4:0] cacop_code;
wire [18:0] alu_op;
wire        load_op;
wire [ 1:0] mem_size;
wire        mem_unsigned;
wire        src1_is_pc;
wire        src2_is_imm;
wire        src2_is_4;
wire        gr_we;
wire        mem_we;
wire [ 4:0] dest;
wire [31:0] imm;
wire [31:0] rj_value;
wire [31:0] rkd_value;
wire [31:0] ex1_pc;
wire        res_from_mem;
wire [ 1:0] csr_op;
wire [13:0] csr_num;
wire        inst_syscall;
wire        inst_ertn;

assign {ds_ex,
        ds_ecode,
        ds_esubcode,
        ds_inst,
        inst_ll_w,
        inst_sc_w,
        inst_dbar,
        inst_ibar,
        inst_idle,
        ds_rdcntv,
        ds_rdcntv_hi,
        ds_rdcntid,
        tlb_op,
        invtlb_op,
        inst_cacop,
        cacop_code,
        alu_op,
        load_op,
        mem_size,
        mem_unsigned,
        src1_is_pc,
        src2_is_imm,
        src2_is_4,
        gr_we,
        mem_we,
        dest,
        imm,
        rj_value,
        rkd_value,
        ex1_pc,
        res_from_mem,
        csr_op,
        csr_num,
        inst_syscall,
        inst_ertn} = id_to_ex1_bus_r;

wire [31:0] alu_src1 = src1_is_pc  ? ex1_pc : rj_value;
wire [31:0] alu_src2 = src2_is_imm ? imm    : rkd_value;
wire [31:0] alu_result;
wire [31:0] mem_addr = rj_value + imm;

alu u_alu(
    .alu_op     (alu_op    ),
    .alu_src1   (alu_src1  ),
    .alu_src2   (alu_src2  ),
    .alu_result (alu_result)
);

wire [3:0] st_b_we    = 4'b0001 << mem_addr[1:0];
wire [3:0] st_h_we    = mem_addr[1] ? 4'b1100 : 4'b0011;
wire [3:0] st_w_we    = 4'b1111;
wire [31:0] st_b_wdata = {4{rkd_value[7:0]}} << {mem_addr[1:0], 3'b000};
wire [31:0] st_h_wdata = mem_addr[1] ? {rkd_value[15:0], 16'b0} : {16'b0, rkd_value[15:0]};
wire [31:0] st_w_wdata = rkd_value;
wire [3:0] store_wstrb = (mem_size == 2'b00) ? st_b_we :
                         (mem_size == 2'b01) ? st_h_we : st_w_we;
wire [31:0] store_wdata = (mem_size == 2'b00) ? st_b_wdata :
                           (mem_size == 2'b01) ? st_h_wdata : st_w_wdata;

assign ex1_to_ex2_valid = ex1_valid;
assign ex1_to_ex2_bus   = {alu_result, mem_addr, store_wdata, store_wstrb, id_to_ex1_bus_r};

assign ex1_allowin = !ex1_valid && ex2_empty;

always @(posedge clk) begin
    if (reset || flush || ertn_flush || ibar_flush) begin
        ex1_valid <= 1'b0;
    end
    else if (ex1_valid && ex2_allowin) begin
        ex1_valid <= 1'b0;
    end
    else if (ex1_allowin) begin
        ex1_valid <= id_to_ex1_valid;
    end

    if (id_to_ex1_valid && ex1_allowin && !flush && !ertn_flush && !ibar_flush) begin
        id_to_ex1_bus_r <= id_to_ex1_bus;
    end
end

assign ex1_to_ds_dest    = dest & {5{ex1_valid}} & {5{gr_we}};
assign ex1_to_ds_result_ready = ex1_valid && gr_we &&
                                !res_from_mem &&
                                !mem_we &&
                                (csr_op == 2'b00) &&
                                !ds_rdcntv &&
                                !ds_rdcntid &&
                                !alu_op[13] &&
                                !alu_op[14] &&
                                !alu_op[15] &&
                                !alu_op[12] &&
                                !alu_op[16] &&
                                !alu_op[17] &&
                                !alu_op[18] &&
                                !ds_ex;
assign ex1_to_ds_result  = alu_result;
assign ex1_csr_we        = (csr_op == 2'b10 || csr_op == 2'b11) && ex1_valid;
assign ex1_csr_num       = csr_num;
assign ex1_is_ertn       = inst_ertn && ex1_valid;

endmodule

module ex3_stage(
    input                          clk,
    input                          reset,
    input                          ms_allowin,
    input                          older_pipe_empty,
    output                         ex3_allowin,
    output                         ex3_empty,
    input                          ex2_to_ex3_valid,
    input  [`EX2_TO_EX3_BUS_WD -1:0] ex2_to_ex3_bus,
    output                         ex3_to_mem_valid,
    output [`EX3_TO_MEM_BUS_WD -1:0] ex3_to_mem_bus,
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
    output        ibar_flush,
    output [31:0] ibar_target,
    output        idle_wait,
    output [4:0]  ex3_to_ds_dest,
    output        ex3_to_ds_result_ready,
    output [31:0] ex3_to_ds_result,
    output        flush,
    input  [31:0] ex_entry_in,
    output [31:0] ex_entry,
    output        ex3_wb_ex,
    output [ 5:0] ex3_wb_ecode,
    output [ 8:0] ex3_wb_esubcode,
    output [31:0] ex3_wb_pc,
    output [31:0] ex3_wb_badv,
    output        ertn_flush,
    input  [31:0] ertn_pc_in,
    output [31:0] ertn_pc,
    output        ex3_csr_we,
    output [13:0] ex3_csr_num,
    output        ex3_is_ertn,
    input  [31:0] cnt_low_now,
    input  [31:0] cnt_high_now,
    input  [31:0] tid_now,
    input         has_int_now
);

reg         ex3_valid;
reg [`EX2_TO_EX3_BUS_WD -1:0] ex2_to_ex3_bus_r;
reg [31:0] cnt_low_sample;
reg [31:0] cnt_high_sample;
reg [31:0] tid_sample;

wire [`EX1_TO_EX2_BUS_WD -1:0] ex1_to_ex2_bus_saved;
wire [31:0] side_data_paddr;
wire [ 1:0] side_data_mat;
wire        side_data_access_cached;
wire        side_actual_mem_we;
wire        side_sc_success_pre;
wire [31:0] side_exe_result;
wire        side_ex_ipe;
wire        side_ex_sys;
wire        side_ex_ale;
wire        side_ex_data_tlb;
wire [ 5:0] side_data_tlb_ecode;
wire [31:0] side_wb_pc;
wire [31:0] side_csr_rvalue;
wire [31:0] side_csr_wmask;
wire [31:0] side_csr_wvalue;
wire        side_s1_found;
wire [ 4:0] side_s1_index;
wire        side_tlbrd_e;
wire [18:0] side_tlbrd_vppn;
wire [ 5:0] side_tlbrd_ps;
wire [ 9:0] side_tlbrd_asid;
wire        side_tlbrd_g;
wire [19:0] side_tlbrd_ppn0;
wire [ 1:0] side_tlbrd_plv0;
wire [ 1:0] side_tlbrd_mat0;
wire        side_tlbrd_d0;
wire        side_tlbrd_v0;
wire [19:0] side_tlbrd_ppn1;
wire [ 1:0] side_tlbrd_plv1;
wire [ 1:0] side_tlbrd_mat1;
wire        side_tlbrd_d1;
wire        side_tlbrd_v1;
wire        side_ex_int_pre;
wire [ 4:0] side_tlb_write_index;

assign {side_data_paddr,
        side_data_mat,
        side_data_access_cached,
        side_actual_mem_we,
        side_sc_success_pre,
        side_exe_result,
        side_ex_ipe,
        side_ex_sys,
        side_ex_ale,
        side_ex_data_tlb,
        side_data_tlb_ecode,
        side_wb_pc,
        side_csr_rvalue,
        side_csr_wmask,
        side_csr_wvalue,
        side_s1_found,
        side_s1_index,
        side_tlbrd_e,
        side_tlbrd_vppn,
        side_tlbrd_ps,
        side_tlbrd_asid,
        side_tlbrd_g,
        side_tlbrd_ppn0,
        side_tlbrd_plv0,
        side_tlbrd_mat0,
        side_tlbrd_d0,
        side_tlbrd_v0,
        side_tlbrd_ppn1,
        side_tlbrd_plv1,
        side_tlbrd_mat1,
        side_tlbrd_d1,
        side_tlbrd_v1,
        side_ex_int_pre,
        side_tlb_write_index,
        ex1_to_ex2_bus_saved} = ex2_to_ex3_bus_r;

wire        ds_ex;
wire [ 5:0] ds_ecode;
wire [ 8:0] ds_esubcode;
wire [31:0] es_inst;
wire        inst_ll_w;
wire        inst_sc_w;
wire        inst_dbar;
wire        inst_ibar;
wire        inst_idle;
wire        ds_rdcntv;
wire        ds_rdcntv_hi;
wire        ds_rdcntid;
wire [ 2:0] tlb_op;
wire [ 4:0] invtlb_op;
wire        inst_cacop;
wire [ 4:0] cacop_code;
wire [18:0] alu_op;
wire        es_load_op;
wire [ 1:0] mem_size;
wire        mem_unsigned;
wire        src1_is_pc;
wire        src2_is_imm;
wire        src2_is_4;
wire        res_from_mem;
wire        gr_we;
wire        es_mem_we;
wire [ 4:0] dest;
wire [31:0] imm;
wire [31:0] rj_value;
wire [31:0] rkd_value;
wire [31:0] es_pc;
wire [ 1:0] csr_op;
wire [13:0] csr_num;
wire        inst_syscall;
wire        inst_ertn;
wire [31:0] ex1_alu_result;
wire [31:0] ex1_mem_addr;
wire [31:0] ex1_store_wdata;
wire [ 3:0] ex1_store_wstrb;

assign {ex1_alu_result,
        ex1_mem_addr,
        ex1_store_wdata,
        ex1_store_wstrb,
        ds_ex,
        ds_ecode,
        ds_esubcode,
        es_inst,
        inst_ll_w,
        inst_sc_w,
        inst_dbar,
        inst_ibar,
        inst_idle,
        ds_rdcntv,
        ds_rdcntv_hi,
        ds_rdcntid,
        tlb_op,
        invtlb_op,
        inst_cacop,
        cacop_code,
        alu_op,
        es_load_op,
        mem_size,
        mem_unsigned,
        src1_is_pc,
        src2_is_imm,
        src2_is_4,
        gr_we,
        es_mem_we,
        dest,
        imm,
        rj_value,
        rkd_value,
        es_pc,
        res_from_mem,
        csr_op,
        csr_num,
        inst_syscall,
        inst_ertn} = ex1_to_ex2_bus_saved;

localparam TLB_OP_FILL = 3'd4;

wire is_csr     = csr_op != 2'b00;
wire is_csrwr   = csr_op == 2'b10;
wire is_csrxchg = csr_op == 2'b11;
wire csr_we_req = is_csrwr | is_csrxchg;
wire barrier_op = inst_dbar || inst_ibar;
wire ex_ds      = ds_ex && ex3_valid;
wire ex_brk     = ex_ds && (ds_ecode == `ECODE_BRK);
wire ex_ine     = ex_ds && (ds_ecode == `ECODE_INE);
wire ex_ipe     = side_ex_ipe && ex3_valid && !ex_ds;
wire ex_sys     = side_ex_sys && ex3_valid && !ex_ds && !ex_ipe;
wire ex_ale     = side_ex_ale && !ex_ds && !ex_ipe && !ex_sys;
wire ex_data_tlb = side_ex_data_tlb && !ex_ds && !ex_ipe && !ex_sys && !ex_ale;
wire ex_sync    = ex_ds || ex_ipe || ex_sys || ex_ale || ex_data_tlb;
wire ex3_has_int = inst_idle ? has_int_now : side_ex_int_pre;
wire ex_int     = ex3_has_int && ex3_valid && !ex_sync &&
                  !(barrier_op && !barrier_done);
wire ex_pending = ex_sync || ex_int;
wire ertn_pending = inst_ertn && ex3_valid && !ex_pending;
wire sc_success = side_sc_success_pre && !ex_pending;
wire actual_mem_we = side_actual_mem_we && (!inst_sc_w || sc_success);
wire mem_access_ok = ex3_valid && !ex_pending;
wire es_mem_access = (res_from_mem || actual_mem_we) && mem_access_ok;
wire privileged_state_op = csr_we_req || (tlb_op != 3'b0) ||
                           ex_pending || ertn_pending;
wire privileged_state_ready = !privileged_state_op || older_pipe_empty ||
                              (ex_int && !inst_idle);
wire final_operation_ready =
    inst_cacop ? (ex_pending || cacop_ok) :
    barrier_op ? (ex_pending || barrier_done) :
    inst_idle  ? ex_pending :
                 (!es_mem_access || data_sram_addr_ok);
wire ex3_ready_go = final_operation_ready && privileged_state_ready;
wire ex3_commit = ex3_valid && ex3_ready_go && ms_allowin;

reg  [5:0]  wb_ecode;
reg  [8:0]  wb_esubcode;
reg  [31:0] wb_badv;
wire        wb_ex = ex3_commit && ex_pending;
wire [31:0] wb_pc = (inst_idle && ex_int) ? (es_pc + 32'd4) : side_wb_pc;
wire [31:0] data_vaddr = ex1_mem_addr;
wire [31:0] data_paddr = side_data_paddr;
wire [31:0] csr_rvalue = side_csr_rvalue;
wire [31:0] rdcntv_result_sample = ds_rdcntv_hi ? cnt_high_sample : cnt_low_sample;
wire [31:0] exe_result = ds_rdcntid ? tid_sample :
                         ds_rdcntv  ? rdcntv_result_sample :
                                      side_exe_result;
wire        tlbfill_fire = ex3_commit && !ex_pending && !ertn_pending &&
                           (tlb_op == TLB_OP_FILL);
wire [4:0]  tlb_write_index = side_tlb_write_index;

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
    else if (ex_ipe) begin
        wb_ecode    = `ECODE_IPE;
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
        wb_ecode    = side_data_tlb_ecode;
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

assign flush      = wb_ex;
assign ex_entry   = ex_entry_in;
assign ex3_wb_ex       = wb_ex;
assign ex3_wb_ecode    = wb_ecode;
assign ex3_wb_esubcode = wb_esubcode;
assign ex3_wb_pc       = wb_pc;
assign ex3_wb_badv     = wb_badv;
assign ertn_flush = ex3_commit && ertn_pending;
assign ertn_pc    = ertn_pc_in;
assign ibar_flush = ex3_commit && inst_ibar && !ex_pending;
assign ibar_target = es_pc + 32'd4;
assign idle_wait  = ex3_valid && inst_idle && !wb_ex;

assign data_sram_req      = ex3_valid && es_mem_access && ms_allowin;
assign data_sram_wr       = actual_mem_we && mem_access_ok;
assign data_sram_size     = mem_size;
assign data_sram_wstrb    = actual_mem_we && mem_access_ok ? ex1_store_wstrb : 4'h0;
assign data_sram_addr     = data_paddr;
assign data_sram_wdata    = ex1_store_wdata;
assign data_sram_uncached = (side_data_mat == 2'b00);

assign cacop_valid     = ex3_valid && inst_cacop && !ex_pending && ms_allowin;
assign cacop_is_dcache = (cacop_code[2:0] == 3'b001);
assign cacop_op        = cacop_code[4:3];
assign cacop_index     = (inst_cacop && (cacop_code[4:3] == 2'b10)) ?
                         data_paddr[11:4] : data_vaddr[11:4];
assign cacop_way       = data_vaddr[0];
assign cacop_tag       = data_paddr[31:12];

assign barrier_req     = ex3_valid && barrier_op && !ex_sync && !ertn_pending;
assign barrier_is_ibar = inst_ibar;

assign ex3_to_mem_valid = ex3_valid && ex3_ready_go;
assign ex3_to_mem_bus = {inst_ll_w && !ex_pending && !ertn_pending,
                         inst_sc_w && !ex_pending && !ertn_pending,
                         sc_success,
                         side_data_access_cached,
                         data_paddr[31:4],
                         es_mem_access,
                         res_from_mem,
                         mem_size,
                         mem_unsigned,
                         (ex_pending || ertn_pending) ? 1'b0 : gr_we,
                         dest,
                         exe_result,
                         es_pc};

assign ex3_to_ds_dest = dest & {5{ex3_valid}} & {5{gr_we}};
assign ex3_to_ds_result_ready = ex3_valid && gr_we &&
                                final_operation_ready &&
                                !res_from_mem &&
                                !inst_sc_w &&
                                !ex_pending &&
                                !ertn_pending;
assign ex3_to_ds_result = exe_result;

assign ex3_csr_we  = csr_we_req && ex3_valid;
assign ex3_csr_num = csr_num;
assign ex3_is_ertn = inst_ertn && ex3_valid;

assign ex3_allowin = !ex3_valid || (ex3_ready_go && ms_allowin);
assign ex3_empty   = !ex3_valid;

always @(posedge clk) begin
    if (reset || flush || ertn_flush || ibar_flush) begin
        ex3_valid <= 1'b0;
        cnt_low_sample <= 32'b0;
        cnt_high_sample <= 32'b0;
        tid_sample <= 32'b0;
    end
    else if (ex3_allowin) begin
        ex3_valid <= ex2_to_ex3_valid;
    end

    if (ex2_to_ex3_valid && ex3_allowin && !flush && !ertn_flush && !ibar_flush) begin
        ex2_to_ex3_bus_r <= ex2_to_ex3_bus;
        cnt_low_sample <= cnt_low_now;
        cnt_high_sample <= cnt_high_now;
        tid_sample <= tid_now;
    end
end

endmodule

module ex2_stage(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          ex3_allowin   ,
    input                          older_pipe_empty,
    output                         ex2_allowin   ,
    output                         ex2_empty     ,
    //from ex1
    input                          ex1_to_ex2_valid,
    input  [`EX1_TO_EX2_BUS_WD -1:0] ex1_to_ex2_bus,
    //to ms
    output                         ex2_to_ex3_valid,
    output [`EX2_TO_EX3_BUS_WD -1:0] ex2_to_ex3_bus,
    // data sram interface
    output        data_sram_req    ,
    output        data_sram_wr     ,
    output [ 1:0] data_sram_size   ,
    output [ 3:0] data_sram_wstrb  ,
    output [31:0] data_sram_addr   ,
    output [31:0] data_sram_wdata  ,
    output        data_sram_uncached,
    input         data_sram_addr_ok,
    input         data_sram_data_ok,
    input  [31:0] data_sram_rdata  ,
    // cache maintenance interface
    output        cacop_valid,
    output        cacop_is_dcache,
    output [ 1:0] cacop_op,
    output [ 7:0] cacop_index,
    output        cacop_way,
    output [19:0] cacop_tag,
    input         cacop_ok,
    // memory barrier controller
    output        barrier_req,
    output        barrier_is_ibar,
    input         barrier_done,
    input         ibar_flush,
    output [31:0] ibar_target,
    output        idle_wait,
    // forward to id
    output [4:0] es_to_ds_dest,
    output es_to_ds_result_ready,
    output [31:0] es_to_ds_result,
    // exception interface
    input         flush,
    input         ex3_wb_ex,
    input  [ 5:0] ex3_wb_ecode,
    input  [ 8:0] ex3_wb_esubcode,
    input  [31:0] ex3_wb_pc,
    input  [31:0] ex3_wb_badv,
    output [31:0] ex_entry,
    // ertn interface
    input         ertn_flush,
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
    output [31:0] cnt_low_out,
    output [31:0] cnt_high_out,
    output [31:0] tid_out,
    output        has_int_out,
    // LL/SC reservation query and control
    output [27:0] sc_query_line,
    output        sc_query_cached,
    input         sc_can_store,
    input         reservation_valid,
    output        llbctl_klo,
    output        wcllb_commit,
    // interrupt / csr interface
    input  [7:0]  hw_int_in
);

reg         es_valid      ;
wire        es_ready_go   ;

reg  [`EX1_TO_EX2_BUS_WD -1:0] ex1_to_ex2_bus_r;

// ============================================================
// Unpack ds_to_es_bus
// ============================================================
wire        ds_ex;
wire [ 5:0] ds_ecode;
wire [ 8:0] ds_esubcode;
wire [31:0] es_inst;
wire        inst_ll_w;
wire        inst_sc_w;
wire        inst_dbar;
wire        inst_ibar;
wire        inst_idle;
wire        ds_rdcntv;
wire        ds_rdcntv_hi;
wire        ds_rdcntid;
wire [ 2:0] tlb_op;
wire [ 4:0] invtlb_op;
wire        inst_cacop;
wire [ 4:0] cacop_code;

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
wire [31:0] ex1_alu_result;
wire [31:0] ex1_mem_addr;
wire [31:0] ex1_store_wdata;
wire [ 3:0] ex1_store_wstrb;

assign {ex1_alu_result,
        ex1_mem_addr,
        ex1_store_wdata,
        ex1_store_wstrb,
        ds_ex,              // 1  (198)
        ds_ecode,           // 6  (197:192)
        ds_esubcode,        // 9  (191:183)
        es_inst,
        inst_ll_w,
        inst_sc_w,
        inst_dbar,
        inst_ibar,
        inst_idle,
        ds_rdcntv,          // 1  (182)
        ds_rdcntv_hi,       // 1  (181)
        ds_rdcntid,         // 1  (180)
        tlb_op,
        invtlb_op,
        inst_cacop,
        cacop_code,
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
       } = ex1_to_ex2_bus_r;

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
wire        mul_op;
wire        mul_signed_hi;
wire        mul_high_result;
wire        mul_start;
wire        mul_cancel;
wire        mul_busy;
wire        mul_done;
wire [31:0] mul_result;

// ============================================================
// ALU
// ============================================================
assign alu_src1 = src1_is_pc  ? es_pc  : rj_value;
assign alu_src2 = src2_is_imm ? imm : rkd_value;
assign mem_addr = ex1_mem_addr;
assign div_op     = !ds_ex && (alu_op[12] || alu_op[16] || alu_op[17] || alu_op[18]);
assign div_signed = alu_op[12] || alu_op[16];
assign div_is_mod = alu_op[16] || alu_op[18];
assign div_start  = es_valid && div_op && !div_busy && !div_done;
assign div_cancel = flush || ertn_flush || (es_valid && div_op && div_done && ex3_allowin);
assign div_result = div_is_mod ? div_remainder : div_quotient;
assign mul_op     = alu_op[13] || alu_op[14] || alu_op[15];
assign mul_signed_hi = alu_op[14];
assign mul_high_result = alu_op[14] || alu_op[15];
assign mul_start  = es_valid && mul_op && !mul_busy && !mul_done;
assign mul_cancel = flush || ertn_flush || ibar_flush ||
                    (es_valid && mul_op && mul_done && ex3_allowin);

assign alu_result = ex1_alu_result;

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

piped_multiplier u_piped_multiplier(
    .clk         (clk            ),
    .reset       (reset          ),
    .cancel      (mul_cancel     ),
    .start       (mul_start      ),
    .src1        (alu_src1       ),
    .src2        (alu_src2       ),
    .signed_hi   (mul_signed_hi  ),
    .high_result (mul_high_result),
    .busy        (mul_busy       ),
    .done        (mul_done       ),
    .result      (mul_result     )
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
wire        ex_int;
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

assign es_commit    = es_valid && es_ready_go && ex3_allowin;
assign ertn_pending = inst_ertn && es_valid && !ex_pending;
assign csr_re       = is_csr && es_valid && !ex_pending && !ertn_pending;
assign csr_wmask  = is_csrwr ? 32'hFFFFFFFF : rj_value;
assign csr_wvalue = rkd_value;
assign wb_pc      = (inst_idle && ex_int) ? (es_pc + 32'd4) : es_pc;

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
wire [ 4:0] csr_tlbidx_index;
wire [ 5:0] csr_tlbidx_ps;
wire        csr_tlbidx_ne;

reg  [4:0]  tlbfill_index;
wire [4:0]  tlb_write_index = inst_tlbfill ? tlbfill_index : csr_tlbidx_index;
wire        tlb_we          = tlb_commit && (inst_tlbwr || inst_tlbfill);
wire        tlbfill_fire    = tlb_commit && inst_tlbfill;
wire        invtlb_valid    = tlb_commit && inst_invtlb;

wire        s0_found;
wire [ 4:0] s0_index;
wire [19:0] s0_ppn;
wire [ 5:0] s0_ps;
wire [ 1:0] s0_plv;
wire [ 1:0] s0_mat;
wire        s0_d;
wire        s0_v;

wire        s1_found;
wire [ 4:0] s1_index;
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

tlb #(.TLBNUM(32)) u_tlb(
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
    .w_e          (inst_tlbfill || ~csr_tlbidx_ne),
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
        tlbfill_index <= 5'b0;
    end
    else if (tlbfill_fire) begin
        tlbfill_index <= tlbfill_index + 5'b1;
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
    .wb_ex      (ex3_wb_ex       ),
    .wb_ecode   (ex3_wb_ecode    ),
    .wb_esubcode(ex3_wb_esubcode ),
    .wb_pc      (ex3_wb_pc       ),
    .wb_badv    (ex3_wb_badv     ),
    .ex_entry   (ex_entry   ),
    .ertn_flush (ertn_flush ),
    .ertn_pc    (ertn_pc    ),
    .reservation_valid(reservation_valid),
    .llbctl_klo(llbctl_klo),
    .wcllb_commit(wcllb_commit),
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
assign es_csr_we  = csr_we_req && es_valid;
assign es_csr_num = csr_num;
assign es_is_ertn = inst_ertn && es_valid;
assign cnt_low_out  = cnt_low;
assign cnt_high_out = cnt_high;
assign tid_out      = tid_val;
assign has_int_out  = has_int;

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
wire [31:0] inst_tlb_paddr = (s0_ps == 6'd21) ? {s0_ppn[19:9], inst_vaddr[20:0]} :
                               (s0_ps == 6'd22) ? {s0_ppn[19:10], inst_vaddr[21:0]} :
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
wire [31:0] data_tlb_paddr = (s1_ps == 6'd21) ? {s1_ppn[19:9], data_vaddr[20:0]} :
                               (s1_ps == 6'd22) ? {s1_ppn[19:10], data_vaddr[21:0]} :
                                                 {s1_ppn[19:0],  data_vaddr[11:0]};
wire [31:0] data_paddr = !csr_pg      ? data_vaddr :
                         data_dmw_hit ? data_dmw_paddr :
                                        data_tlb_paddr;
wire [ 1:0] data_mat = !csr_pg       ? csr_crmd[8:7] :
                       data_dmw0_hit ? csr_dmw0[5:4] :
                       data_dmw1_hit ? csr_dmw1[5:4] :
                                       s1_mat;
wire data_access_cached = data_mat != 2'b00;
assign sc_query_line   = data_paddr[31:4];
assign sc_query_cached = data_access_cached;
wire cacop_hit_op = inst_cacop && (cacop_code[4:3] == 2'b10);
wire data_mem_op  = es_load_op || es_mem_we || cacop_hit_op;
wire data_use_tlb = csr_pg && !data_dmw_hit;
wire data_tlbr_ex = es_valid && data_mem_op && data_use_tlb && !s1_found;
wire data_pil_ex  = es_valid && (es_load_op || cacop_hit_op) && data_use_tlb && s1_found && !s1_v;
wire data_pis_ex  = es_valid && es_mem_we  && data_use_tlb && s1_found && !s1_v;
wire data_ppi_ex  = es_valid && data_mem_op && data_use_tlb && s1_found && s1_v
                    && (csr_plv > s1_plv);
wire data_pme_ex  = es_valid && es_mem_we && data_use_tlb && s1_found && s1_v
                    && (csr_plv <= s1_plv) && !s1_d;
wire data_tlb_ex  = data_tlbr_ex || data_pil_ex || data_pis_ex || data_ppi_ex || data_pme_ex;
wire [5:0] data_tlb_ecode = data_tlbr_ex ? `ECODE_TLBR :
                             data_pil_ex  ? `ECODE_PIL  :
                             data_pis_ex  ? `ECODE_PIS  :
                             data_ppi_ex  ? `ECODE_PPI  :
                                            `ECODE_PME;

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
wire privileged_inst = is_csr ||
                       (inst_cacop && !cacop_hit_op) ||
                       (tlb_op != 3'b0) ||
                       inst_ertn || inst_idle;
wire ex_ipe   = es_valid && !ex_ds && privileged_inst &&
                (csr_plv != 2'b00);
wire ex_sys   = inst_syscall && es_valid && !ex_ds && !ex_ipe;
wire ex_ale   = ale_detected && !ex_ds && !ex_ipe && !ex_sys;
wire ex_data_tlb = data_tlb_ex && !ex_ds && !ex_ipe && !ex_sys && !ex_ale;

// Any synchronous exception
wire ex_sync  = ex_ds || ex_ipe || ex_sys || ex_ale || ex_data_tlb;

// Interrupt (asynchronous): only when no sync exception
wire barrier_op = inst_dbar || inst_ibar;
assign ex_int = has_int && es_valid && !ex_sync &&
                !(barrier_op && !barrier_done);

// Combined exception.  Side effects are committed only when ES can leave,
// so older memory operations cannot be bypassed by a later exception.
assign ex_pending = ex_sync || ex_int;
assign wb_ex = es_commit && ex_pending;

wire sc_success = inst_sc_w && sc_can_store && !ex_pending;
wire actual_mem_we = es_mem_we && (!inst_sc_w || sc_success);
wire privileged_state_op = csr_we_req || (tlb_op != 3'b0) ||
                           ex_pending || ertn_pending;
wire privileged_state_ready = !privileged_state_op || older_pipe_empty;

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
    else if (ex_ipe) begin
        wb_ecode    = `ECODE_IPE;
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
        wb_ecode    = data_tlb_ecode;
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

// Flush/ERTN redirects are generated by EX3, the architectural commit point.

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
    else if (mul_op === 1'b1)
        exe_result = mul_result;
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

// Suppress memory access on exceptions.
wire mem_access_ok = es_valid && !ex_pending;
wire es_mem_access = (res_from_mem || actual_mem_we) && mem_access_ok;

assign data_sram_req    = 1'b0;
assign data_sram_wr     = actual_mem_we && mem_access_ok;
assign data_sram_size   = mem_size;
assign data_sram_wstrb  = actual_mem_we && mem_access_ok ?
                            ex1_store_wstrb : 4'h0;
assign data_sram_addr   = data_paddr;
assign data_sram_wdata  = ex1_store_wdata;
assign data_sram_uncached = (data_mat == 2'b00);

// ============================================================
// Cache maintenance interface
// ============================================================
assign cacop_valid     = 1'b0;
assign cacop_is_dcache = (cacop_code[2:0] == 3'b001);
assign cacop_op        = cacop_code[4:3];
assign cacop_index     = cacop_hit_op ? data_paddr[11:4] : data_vaddr[11:4];
assign cacop_way       = data_vaddr[0];
assign cacop_tag       = data_paddr[31:12];

assign barrier_req     = es_valid && barrier_op && !ex_sync && !ertn_pending;
assign barrier_is_ibar = inst_ibar;
// IBAR redirect is generated by EX3, the architectural commit point.
assign ibar_target     = es_pc + 32'd4;
assign idle_wait       = es_valid && inst_idle && !wb_ex;

// ============================================================
// Pipeline control
// ============================================================
wire es_operation_ready = div_op ? div_done :
                          mul_op ? mul_done :
                                   1'b1;
assign es_ready_go    = es_operation_ready && privileged_state_ready;
assign ex2_allowin    = !es_valid || es_ready_go && ex3_allowin;
assign ex2_empty      = !es_valid;
assign ex2_to_ex3_valid = es_valid && es_ready_go;

always @(posedge clk) begin
    if (reset) begin
        es_valid <= 1'b0;
    end
    else if (flush || ertn_flush || ibar_flush) begin
        es_valid <= 1'b0;
    end
    else if (ex2_allowin) begin
        es_valid <= ex1_to_ex2_valid;
    end

    if (ex1_to_ex2_valid && ex2_allowin && !flush && !ertn_flush && !ibar_flush) begin
        ex1_to_ex2_bus_r <= ex1_to_ex2_bus;
    end
end

// ============================================================
// Bus output
// ============================================================
assign ex2_to_ex3_bus = {data_paddr,
                         data_mat,
                         data_access_cached,
                         actual_mem_we,
                         sc_success,
                         exe_result,
                         ex_ipe,
                         ex_sys,
                         ex_ale,
                         ex_data_tlb,
                         data_tlb_ecode,
                         wb_pc,
                         csr_rvalue,
                         csr_wmask,
                         csr_wvalue,
                         s1_found,
                         s1_index,
                         tlbrd_e,
                         tlbrd_vppn,
                         tlbrd_ps,
                         tlbrd_asid,
                         tlbrd_g,
                         tlbrd_ppn0,
                         tlbrd_plv0,
                         tlbrd_mat0,
                         tlbrd_d0,
                         tlbrd_v0,
                         tlbrd_ppn1,
                         tlbrd_plv1,
                         tlbrd_mat1,
                         tlbrd_d1,
                         tlbrd_v1,
                         ex_int,
                         tlb_write_index,
                         ex1_to_ex2_bus_r};

// ============================================================
// Forward to ID
// ============================================================
assign es_to_ds_dest = dest & {5{es_valid}} & {5{gr_we}};
assign es_to_ds_result_ready = 1'b0;
assign es_to_ds_result = exe_result;

endmodule
