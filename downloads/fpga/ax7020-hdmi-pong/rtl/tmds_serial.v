`timescale 1ns/1ps
// 将每个像素周期的一组10位TMDS符号，按 bit0 -> bit9 的顺序串行发送。
// pixel_clk=25.2 MHz负责装载，serial_clk=126 MHz用上/下沿发送10个位。
// 这里的两路时钟必须同源、相位关系正确，不能用独立振荡器各产生一路。
module tmds_serial(
    input wire pixel_clk, input wire serial_clk, input wire reset,
    input wire [9:0] symbol, output wire serial
);
    wire shift1, shift2;
    // 单个7系列OSERDESE2直接容纳的并行数据不够10位，需要MASTER/SLAVE级联。
    // 两端 DATA_WIDTH 都为10。MASTER装低8位，SLAVE通过专用级联线补上高2位。
    // 这是芯片专用硬件原语，不能简单改成普通always块再期望同样的高速输出。
    OSERDESE2 #(.DATA_RATE_OQ("DDR"), .DATA_RATE_TQ("SDR"),
        .DATA_WIDTH(10), .SERDES_MODE("MASTER"), .TRISTATE_WIDTH(1)) master (
        // CLK接5倍频高速时钟，CLKDIV接像素时钟；OCE=1持续使能输出数据。
        .OQ(serial), .CLK(serial_clk), .CLKDIV(pixel_clk), .RST(reset), .OCE(1'b1),
        // D1最先发出，故依次连接符号bit0～bit7，不能按视觉上的高位顺序反接。
        .D1(symbol[0]),.D2(symbol[1]),.D3(symbol[2]),.D4(symbol[3]),
        .D5(symbol[4]),.D6(symbol[5]),.D7(symbol[6]),.D8(symbol[7]),
        // SHIFTIN是从SLAVE到MASTER的专用扩展通路，不是普通串行数据输入。
        .SHIFTIN1(shift1),.SHIFTIN2(shift2),.TCE(1'b0),
        // 本实验只发送数据，不使用三态串化控制；这些T端口固定为0。
        .T1(1'b0),.T2(1'b0),.T3(1'b0),.T4(1'b0),.TBYTEIN(1'b0)
    );
    // 10位扩展模式规定：SLAVE只能在D3/D4放入这两个扩展数据位。
    OSERDESE2 #(.DATA_RATE_OQ("DDR"), .DATA_RATE_TQ("SDR"),
        .DATA_WIDTH(10), .SERDES_MODE("SLAVE"), .TRISTATE_WIDTH(1)) slave (
        .SHIFTOUT1(shift1),.SHIFTOUT2(shift2),.CLK(serial_clk),.CLKDIV(pixel_clk),
        .RST(reset),.OCE(1'b1),.D1(1'b0),.D2(1'b0),.D3(symbol[8]),.D4(symbol[9]),
        .D5(1'b0),.D6(1'b0),.D7(1'b0),.D8(1'b0),.SHIFTIN1(1'b0),.SHIFTIN2(1'b0),
        .TCE(1'b0),.T1(1'b0),.T2(1'b0),.T3(1'b0),.T4(1'b0),.TBYTEIN(1'b0)
    );
endmodule
