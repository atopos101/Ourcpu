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
    output        data_sram_en   ,
    output [ 3:0] data_sram_we   ,
    output [31:0] data_sram_addr ,
    output [31:0] data_sram_wdata,
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
// Unpack ds_to_es_bus (199 bits)
// ============================================================
wire        ds_ex;
wire [ 5:0] ds_ecode;
wire [ 8:0] ds_esubcode;
wire        ds_rdcntv;
wire        ds_rdcntv_hi;
wire        ds_rdcntid;

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

// ============================================================
// ALU
// ============================================================
assign alu_src1 = src1_is_pc  ? es_pc  : rj_value;
assign alu_src2 = src2_is_imm ? imm : rkd_value;

alu u_alu(
    .alu_op     (alu_op    ),
    .alu_src1   (alu_src1  ),
    .alu_src2   (alu_src2  ),
    .alu_result (alu_result)
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

assign csr_re     = is_csr && es_valid && !wb_ex && !ertn_flush;
assign csr_wmask  = is_csrwr ? 32'hFFFFFFFF : rj_value;
assign csr_wvalue = rkd_value;
assign wb_pc      = es_pc;

csr_regfile u_csr_regfile(
    .clk        (clk        ),
    .reset      (reset      ),
    .csr_re     (csr_re     ),
    .csr_num    (csr_num    ),
    .csr_rvalue (csr_rvalue ),
    .csr_we     (csr_we_req && es_valid && !wb_ex && !ertn_flush),
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
    .tid_val    (tid_val    )
);

// CSR hazard tracking for ID stage
assign es_csr_we  = csr_we_req && es_valid && !wb_ex && !ertn_flush;
assign es_csr_num = csr_num;
assign es_is_ertn = inst_ertn && es_valid;

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
    (ale_w && (alu_result[1:0] != 2'b00)) ||
    (ale_h && (alu_result[0]   != 1'b0))
);

// ============================================================
// Unified exception detection
// ============================================================
// Synchronous exceptions from earlier stages (passed via ds_to_es_bus)
wire ex_adef  = ds_ex && (ds_ecode == `ECODE_ADEF) && es_valid;
wire ex_brk   = ds_ex && (ds_ecode == `ECODE_BRK)  && es_valid;
wire ex_ine   = ds_ex && (ds_ecode == `ECODE_INE)  && es_valid;

// Synchronous exceptions from this stage
wire ex_sys   = inst_syscall && es_valid && !ex_adef && !ex_brk && !ex_ine;
wire ex_ale   = ale_detected && !ex_adef && !ex_brk && !ex_ine && !ex_sys;

// Any synchronous exception
wire ex_sync  = ex_adef || ex_brk || ex_ine || ex_sys || ex_ale;

// Interrupt (asynchronous): only when no sync exception
wire ex_int   = has_int && es_valid && !ex_sync;

// Combined exception (for CSR update and flush logic)
assign wb_ex = ex_sync || ex_int;

// ============================================================
// Exception info for CSR
// ============================================================
always @(*) begin
    if (ex_adef) begin
        wb_ecode    = `ECODE_ADEF;
        wb_esubcode = 9'h000;
        wb_badv     = es_pc;
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
        wb_badv     = alu_result;
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
assign ertn_flush = inst_ertn && es_valid && !wb_ex;

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
    else
        exe_result = alu_result;
end

reg exe_gr_we;
always @(*) begin
    if (wb_ex === 1'b1 || ertn_flush === 1'b1)
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

assign st_b_we    = 4'b0001 << alu_result[1:0];
assign st_h_we    = alu_result[1] ? 4'b1100 : 4'b0011;
assign st_w_we    = 4'b1111;
assign st_b_wdata = {4{rkd_value[7:0]}} << {alu_result[1:0], 3'b000};
assign st_h_wdata = alu_result[1] ? {rkd_value[15:0], 16'b0} : {16'b0, rkd_value[15:0]};
assign st_w_wdata = rkd_value;

// Suppress memory access on ALE
wire mem_access_ok = es_valid && !ale_detected;

assign data_sram_en    = 1'b1;
assign data_sram_we    = es_mem_we && mem_access_ok ?
                            ((mem_size == 2'b00) ? st_b_we :
                             (mem_size == 2'b01) ? st_h_we : st_w_we) : 4'h0;
assign data_sram_addr  = alu_result;
assign data_sram_wdata = (mem_size == 2'b00) ? st_b_wdata :
                         (mem_size == 2'b01) ? st_h_wdata : st_w_wdata;

// ============================================================
// Pipeline control
// ============================================================
assign es_ready_go    = 1'b1;
assign es_allowin     = !es_valid || es_ready_go && ms_allowin;
assign es_to_ms_valid = es_valid && es_ready_go;

always @(posedge clk) begin
    if (reset) begin
        es_valid <= 1'b0;
    end
    else if (es_allowin) begin
        es_valid <= ds_to_es_valid;
    end

    if (ds_to_es_valid && es_allowin) begin
        ds_to_es_bus_r <= ds_to_es_bus;
    end
end

// ============================================================
// Bus output
// ============================================================
assign es_to_ms_bus = {res_from_mem,  //73:73 1
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
assign es_to_ds_load_op = res_from_mem & es_valid;
assign es_to_ds_result = exe_result;

endmodule
