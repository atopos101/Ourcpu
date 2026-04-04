module sram (
    input  wire        clk,
    input  wire        we,      // write enable
    input  wire [31:0] addr,    // address
    input  wire [31:0] wdata,   // write data
    output reg  [31:0] rdata    // read data
);

    // Simple memory model: 1KB (256 words of 32-bit)
    reg [31:0] mem [0:255];

    // Initialize memory to zero (optional, for simulation)
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            mem[i] = 32'b0;
        end
    end

    // Synchronous read/write
    always @(posedge clk) begin
        if (we) begin
            mem[addr[9:2]] <= wdata;  // addr[9:2] for word alignment (4-byte words)
        end
        rdata <= mem[addr[9:2]];
    end

endmodule

//仿真