`timescale 1ns/1ps
// 视频时钟源，直接例化 Zynq-7000/7系列时钟原语，不需要额外生成 IP 文件。
// 输入50 MHz；MMCM内部先做 50/5×63=630 MHz，再除25和5得到两路输出。
// pixel_clk=25.2 MHz；serial_clk=126 MHz，两者同源且频率比严格为1:5。
// locked=1 表示 MMCM 已锁定，顶层据此控制像素域逻辑何时退出复位。
module clock_gen(input wire sys_clk, input wire reset,
                 output wire pixel_clk, output wire serial_clk, output wire locked);
    wire clk_in, feedback, feedback_buf, pixel_raw, serial_raw;
    // IBUF 接收芯片外部晶振信号；BUFG 将反馈和输出送入专用全局时钟网络。
    // 不使用普通组合逻辑、翻转寄存器或按键信号来替代全局时钟缓冲。
    IBUF in_buf(.I(sys_clk), .O(clk_in));
    BUFG fb_buf(.I(feedback), .O(feedback_buf));
    BUFG pix_buf(.I(pixel_raw), .O(pixel_clk));
    BUFG ser_buf(.I(serial_raw), .O(serial_clk));
    // CLKIN1_PERIOD 以ns为单位，是输入时钟周期，不是输出时钟频率。
    // DIVCLK_DIVIDE 为输入分频，CLKFBOUT_MULT_F 为倍频，CLKOUT*_DIVIDE 为输出分频。
    // serial_clk 用双沿DDR发送数据，因此126 MHz时钟可发送252 Mbit/s。
    MMCME2_BASE #(
        .CLKIN1_PERIOD(20.0), .DIVCLK_DIVIDE(5), .CLKFBOUT_MULT_F(63.0),
        .CLKOUT0_DIVIDE_F(25.0), .CLKOUT1_DIVIDE(5), .STARTUP_WAIT("FALSE")
    ) mmcm (
        // 专用反馈闭环必须接回 CLKFBIN，不能把反馈输出悬空。
        .CLKIN1(clk_in), .CLKFBIN(feedback_buf), .CLKFBOUT(feedback),
        .CLKOUT0(pixel_raw), .CLKOUT1(serial_raw), .LOCKED(locked),
        // PWRDWN=0 表示正常供电工作，RST 为外部高有效复位请求。
        // 未列出的其他时钟输出不参与本实验，保持未连接。
        .PWRDWN(1'b0), .RST(reset)
    );
endmodule
