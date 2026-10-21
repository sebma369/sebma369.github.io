`timescale 1ns/1ps
// 像素时钟域复位：异步进入复位、经过两个有效时钟沿后同步释放。
// request 高有效，顶层连接 MMCM 的 !locked；reset 也是高有效。
// 即使时钟暂时停止，request 上升沿仍能把同步链置为11并立即输出复位。
module reset_sync(input wire clk, input wire request, output wire reset);
    // 两级寄存器链需要被识别为同步结构，不能作为普通移位逻辑随意优化。
    (* ASYNC_REG = "TRUE" *) reg [1:0] sync_ff;
    always @(posedge clk or posedge request)
        if (request) sync_ff <= 2'b11;
        // request 解除后，连续时钟沿使寄存器依次经历 11 -> 10 -> 00。
        // 拼接右边是最低位；<= 使用上一周期的 sync_ff[0]。
        else         sync_ff <= {sync_ff[0], 1'b0};
    // 取第二级，避免把异步请求的解除直接送到整片像素逻辑。
    assign reset = sync_ff[1];
endmodule
