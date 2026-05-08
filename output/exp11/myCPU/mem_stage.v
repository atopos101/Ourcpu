`include "mycpu.vh"

module mem_stage(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          ws_allowin    ,
    output                         ms_allowin    ,
    //from es
    input                          es_to_ms_valid,
    input  [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus  ,
    //to ws
    output                         ms_to_ws_valid,
    output [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus  ,
    
    //from data-sram
    input  [31                 :0] data_sram_rdata,
    // ????????????
    output [4:0] ms_to_ds_dest,
    // ????
    output [31:0] ms_to_ds_result
);

reg         ms_valid;
wire        ms_ready_go;

reg [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus_r;
wire        ms_res_from_mem;
wire [ 1:0] ms_mem_size;
wire        ms_mem_unsigned;
wire        ms_gr_we;
wire [ 4:0] ms_dest;
wire [31:0] ms_alu_result;
wire [31:0] ms_pc;

wire [31:0] mem_result;
wire [31:0] ms_final_result;


assign {ms_res_from_mem,  //73:73
        ms_mem_size    ,  //72:71
        ms_mem_unsigned,  //70:70
        ms_gr_we       ,  //69:69
        ms_dest        ,  //68:64
        ms_alu_result  ,  //63:32
        ms_pc             //31:0
       } = es_to_ms_bus_r;

assign ms_to_ws_bus = {ms_gr_we       ,  //69:69
                       ms_dest        ,  //68:64
                       ms_final_result,  //63:32
                       ms_pc             //31:0
                      };

assign ms_ready_go    = 1'b1;
assign ms_allowin     = !ms_valid || ms_ready_go && ws_allowin;
assign ms_to_ws_valid = ms_valid && ms_ready_go;
always @(posedge clk) begin
    if (reset) begin
        ms_valid <= 1'b0;
    end
    else if (ms_allowin) begin
        ms_valid <= es_to_ms_valid;
    end

    if (es_to_ms_valid && ms_allowin) begin
        es_to_ms_bus_r <= es_to_ms_bus;
    end
end

wire [ 7:0] load_byte;
wire [15:0] load_half;

assign load_byte = (ms_alu_result[1:0] == 2'b00) ? data_sram_rdata[ 7: 0] :
                   (ms_alu_result[1:0] == 2'b01) ? data_sram_rdata[15: 8] :
                   (ms_alu_result[1:0] == 2'b10) ? data_sram_rdata[23:16] :
                                                    data_sram_rdata[31:24] ;
assign load_half = ms_alu_result[1] ? data_sram_rdata[31:16] : data_sram_rdata[15:0];

assign mem_result = (ms_mem_size == 2'b00) ? {{24{~ms_mem_unsigned & load_byte[7]}}, load_byte} :
                    (ms_mem_size == 2'b01) ? {{16{~ms_mem_unsigned & load_half[15]}}, load_half} :
                                             data_sram_rdata;
assign ms_final_result = ms_res_from_mem ? mem_result : ms_alu_result;

assign ms_to_ds_dest = ms_dest & {5{ms_valid}} & {5{ms_gr_we}};
assign ms_to_ds_result = ms_final_result;

endmodule

