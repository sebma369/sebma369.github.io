`timescale 1ns/1ps
// 单个低有效机械按键的输入处理：两级同步 -> 连续稳定计数消抖 -> 按下事件。
// STABLE_CYCLES 必须为正数；默认 252000 / 25.2 MHz = 10 ms。
// down 用于长按移动，press 用于一次触发，两者用途不能混淆。
module key_filter #(parameter integer STABLE_CYCLES = 252000)(
    // clk 来自像素时钟域；reset 高有效；原始 key_n 松开为1、按下为0。
    input wire clk, input wire reset, input wire key_n,
    output wire down, output reg press
);
    // $clog2 求保存计数所需的位数；最少保留1位，防止参数为1时出现零宽向量。
    localparam integer CW = (STABLE_CYCLES < 2) ? 1 : $clog2(STABLE_CYCLES);
    // 原始按键与 clk 异步，先经过两级触发器，降低亚稳态继续传播的概率。
    // ASYNC_REG 帮助工具识别、保留同步链；并不能保证真实硬件“绝无亚稳态”。
    (* ASYNC_REG = "TRUE" *) reg meta_n, sync_n;
    // stable_n 是已经通过消抖的低有效稳定状态，初始按“未按下”处理。
    reg stable_n;
    // 只统计 sync_n 与 stable_n 不同时持续了多少周期。
    reg [CW-1:0] count;
    // 两级非阻塞赋值读取旧值：sync_n 得到上一周期的 meta_n，而非本周期的 key_n。
    always @(posedge clk or posedge reset) begin
        if (reset) begin meta_n <= 1'b1; sync_n <= 1'b1; end
        else begin meta_n <= key_n; sync_n <= meta_n; end
    end
    // 稳定判断与事件产生也都工作在同一个 clk 域，不把按键当作时钟使用。
    always @(posedge clk or posedge reset) begin
        if (reset) begin count <= 0; stable_n <= 1'b1; press <= 1'b0; end
        else begin
            // 每周期默认清零，只有确认从“松开”变为“按下”的这一周期会置1。
            press <= 1'b0;
            // 只要输入回到旧稳定状态，就取消尚未完成的状态切换并重新计数。
            if (sync_n == stable_n) count <= 0;
            else if (count == STABLE_CYCLES-1) begin
                // 连续稳定时间已达到阈值，接受新状态；松开时不产生 press 脉冲。
                count <= 0;
                stable_n <= sync_n;
                press <= !sync_n;
            end
            // 在确认新状态前，继续计数；未赋值 stable_n 时寄存器自然保持。
            else count <= count + 1'b1;
        end
    end
    // 模块外统一使用正逻辑“按下=1”，原始低有效极性只在输入处理内保留。
    assign down = !stable_n;
endmodule
