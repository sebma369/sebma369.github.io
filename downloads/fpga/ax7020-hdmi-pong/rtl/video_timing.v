`timescale 1ns/1ps
// 640×480 视频扫描器。x/y 表示当前扫描位置，含消隐区，不只是可见像素。
// 每个25.2 MHz像素周期前进1个位置；800×525个周期为1帧，刷新率60 Hz。
module video_timing(
    input wire clk, input wire reset,
    output reg [9:0] x, output reg [9:0] y,
    output wire de, output wire hsync, output wire vsync, output wire frame_tick
);
    // 一行：640可见 + 16前肩 + 96同步 + 48后肩 = 800，x范围0～799。
    // 一帧：480可见 + 10前肩 + 2同步 + 33后肩 = 525，y范围0～524。
    // 到行尾时 x 回零、y 加1；到帧尾时二者一起回零，实现逐行扫描。
    always @(posedge clk or posedge reset) begin
        if (reset) begin x <= 0; y <= 0; end
        else if (x == 799) begin
            x <= 0;
            if (y == 524) y <= 0;
            else          y <= y + 1'b1;
        end
        else x <= x + 1'b1;
    end
    // de=1 才是画面数据；其余周期用于发送同步控制码，而不是可见 RGB。
    assign de = (x < 640) && (y < 480);
    // 行同步区间为[656,752)，恰好96周期，采用低有效同步脉冲。
    assign hsync = !((x >= 656) && (x < 752));
    // 场同步在第490、491行有效，恰好2行；同样低有效。
    assign vsync = !((y >= 490) && (y < 492));
    // 最后一条可见行的行尾产生单周期使能，下一周期即进入垂直消隐。
    // 游戏此时更新坐标，下一帧扫描时坐标已稳定，避免在画面中途改变位置。
    // frame_tick 只是使能条件；它既不连接触发器的时钟端，也不是60 Hz新时钟。
    assign frame_tick = (x == 799) && (y == 479);
endmodule
