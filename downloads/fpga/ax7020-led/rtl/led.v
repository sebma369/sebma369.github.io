// 本实验使用 50 MHz 时钟，每个周期为 20 ns。
// AX7020 的 PL LED 低电平点亮：0000 为四灯全亮，1111 为四灯全灭。
// 本代码直接使用异步按键复位，未加入复位释放同步链和机械消抖。
// 实物测试时按住 PL KEY1 再松开，检查复位与重新计时的行为。
// 后续复杂设计需考虑复位同步和按键消抖；行为仿真不能证明硬件无亚稳态。
module led (
    // 接收板载 50 MHz 时钟，电路在每个上升沿更新时序逻辑。
    input sys_clk,
    // 低有效复位，连接 PL KEY1：按下为 0，松开为 1。
    input rst_n,
    // 四个位分别驱动 4 个 PL LED，保存当前亮灭状态。
    output reg [3:0] led
    );

// 32 位计数器，用于累计时钟周期，能够容纳终值 49,999,999。
reg[31:0] timer_cnt;

// 时钟上升沿触发更新；复位下降沿可异步触发，无需等待时钟沿。
// 下方 <= 是非阻塞赋值，同一时钟沿的条件判断使用更新前的寄存器值。
always@ (posedge sys_clk or negedge rst_n)
begin
    if (!rst_n)
    begin
        // 复位时 LED 输出全 0，四灯全亮，同时清零计数器。
        led <= 4'd0 ;
        timer_cnt <= 32'd0 ;
    end
    // 从 0 数到 49,999,999，共 50,000,000 个周期，切换间隔为 1 秒。
    else if(timer_cnt >= 32'd49_999_999)
    begin
        // 四位一起取反：0000 与 1111 交替，四灯同时亮灭。
        led <= ~led;
        // 切换后重新计数，使亮、灭各保持约 1 秒，完整周期约 2 秒。
        timer_cnt <= 32'd0;
    end
    else
    begin
        // 未计满时保持 LED 状态，计数器每个时钟周期加 1。
        led <= led;
        timer_cnt <= timer_cnt + 32'd1;
    end

end

endmodule
