`timescale 1ns/1ps
// 顶层：把按键输入、游戏规则、像素绘制和 HDMI 输出连接成完整硬件。
// 各个子模块同时工作，不是像软件函数一样按书写顺序依次执行。
// TEST_PATTERN=1：输出彩条，先排查显示通路；=0：输出完整游戏。
// 参数在综合时确定，修改后必须重新生成并下载比特流。
module pong_top #(parameter TEST_PATTERN=0)(
    // sys_clk 为板载 50 MHz；key_n[0]～key_n[3] 对应低有效 PL KEY1～KEY4。
    input wire sys_clk, input wire [3:0] key_n,
    // 四盏板载灯均低有效，具体含义见文件末尾的拼接赋值。
    output wire [3:0] led_n,
    // 一对 TMDS 时钟线、三对 TMDS 数据线；p/n 是物理差分正负端。
    output wire hdmi_clk_p, output wire hdmi_clk_n,
    output wire [2:0] hdmi_data_p, output wire [2:0] hdmi_data_n,
    // AX7020 的 HDMI 输出端 5 V 供电使能，电路中高电平有效。
    output wire hdmi_out_en
);
    // pixel_clk=25.2 MHz：按键、扫描、游戏和编码使用的时钟。
    // serial_clk=126 MHz：DDR 串化使用的 5 倍频时钟，两者由同一个 MMCM 产生。
    wire pixel_clk, serial_clk, locked, reset;
    clock_gen clocks(.sys_clk(sys_clk), .reset(!key_n[0]),
        .pixel_clk(pixel_clk),.serial_clk(serial_clk),.locked(locked));
    // KEY1 直接复位 MMCM；MMCM 失锁时，再由 !locked 请求像素域逻辑复位。
    // 锁定恢复后等待两个像素时钟沿释放复位，避免在无稳定时钟时启动游戏。
    // 此处不把 KEY1 与 locked 再组合成多输入异步复位网络。
    reset_sync resetter(.clk(pixel_clk),.request(!locked),.reset(reset));
    // down 保存稳定按下电平；press 只在一次稳定按下时产生一个周期的事件。
    wire [2:0] down, press;
    genvar k;
    // generate 在综合展开时复制三套独立电路，并非运行时轮流扫描三个按键。
    // KEY2/KEY3 用 down 连续移动；KEY4 用 press 进行一次开始/暂停/重开动作。
    generate for(k=0;k<3;k=k+1) begin: keys
        key_filter filter(.clk(pixel_clk),.reset(reset),.key_n(key_n[k+1]),
                          .down(down[k]),.press(press[k]));
    end endgenerate
    // x/y 是正在输出的扫描坐标；paddle_x、ball_x/ball_y 是游戏物体坐标。
    // de 为有效画面标志，hsync/vsync 为行场同步，frame_tick 为每帧一次的使能。
    wire [9:0] x,y,paddle_x,ball_x,ball_y;
    wire de,hsync,vsync,frame_tick;
    wire [1:0] state,lives;
    wire [6:0] score;
    wire [3:0] hit_flash;
    wire [7:0] red,green,blue;
    // 扫描器始终运行，即使游戏暂停也必须持续输出视频时序。
    video_timing timing(.clk(pixel_clk),.reset(reset),.x(x),.y(y),.de(de),
        .hsync(hsync),.vsync(vsync),.frame_tick(frame_tick));
    // 游戏寄存器主要在 frame_tick 时更新，使一个可见帧内的物体位置保持稳定。
    pong_game game(.clk(pixel_clk),.reset(reset),.frame_tick(frame_tick),
        .left_down(down[0]),.right_down(down[1]),.action_press(press[2]),
        .state(state),.paddle_x(paddle_x),.ball_x(ball_x),.ball_y(ball_y),
        .score(score),.lives(lives),.hit_flash(hit_flash));
    // 渲染器根据当前像素坐标直接计算 RGB，不保存完整帧图，也不依赖 DDR。
    video_render #(.TEST_PATTERN(TEST_PATTERN)) render(.x(x),.y(y),.de(de),
        .state(state),.paddle_x(paddle_x),.ball_x(ball_x),.ball_y(ball_y),
        .score(score),.lives(lives),.red(red),.green(green),.blue(blue));
    // 三个颜色通道独立编码：每个通道把 8 位颜色变成一个 10 位符号。
    // 通道顺序固定：0=蓝、1=绿、2=红，必须与板上 HDMI D0/D1/D2 对应。
    wire [9:0] symbols [0:2];
    wire [3:0] serial;
    // 消隐期只有蓝通道携带行/场同步，绿、红通道的控制位固定为 0。
    tmds_encoder enc_b(.clk(pixel_clk),.reset(reset),.data(blue),.de(de),
        .c0(hsync),.c1(vsync),.symbol(symbols[0]));
    tmds_encoder enc_g(.clk(pixel_clk),.reset(reset),.data(green),.de(de),
        .c0(1'b0),.c1(1'b0),.symbol(symbols[1]));
    tmds_encoder enc_r(.clk(pixel_clk),.reset(reset),.data(red),.de(de),
        .c0(1'b0),.c1(1'b0),.symbol(symbols[2]));
    // 再复制三套串化器与差分输出缓冲器；每通道串行速率为 252 Mbit/s。
    generate for(k=0;k<3;k=k+1) begin: channels
        tmds_serial serializer(.pixel_clk(pixel_clk),.serial_clk(serial_clk),
            .reset(reset),.symbol(symbols[k]),.serial(serial[k]));
        OBUFDS #(.IOSTANDARD("TMDS_33")) out_buf(
            .I(serial[k]),.O(hdmi_data_p[k]),.OB(hdmi_data_n[k]));
    end endgenerate
    // 时钟通道也通过同类型串化器，与数据通道保持相同的串化延迟。
    // bit0 最先发送，因此此常量依次输出五个 1、五个 0，构成像素时钟波形。
    tmds_serial clock_serializer(.pixel_clk(pixel_clk),.serial_clk(serial_clk),
        .reset(reset),.symbol(10'b0000011111),.serial(serial[3]));
    OBUFDS #(.IOSTANDARD("TMDS_33")) clock_out(
        .I(serial[3]),.O(hdmi_clk_p),.OB(hdmi_clk_n));
    // 手册第 32 页：高电平开启 HDMI 输出供电，并使本板 HPD 输出缓冲处于释放状态。
    // 本实现固定输出视频，不使用 EDID、CEC 或音频协议。
    assign hdmi_out_en=1'b1;
    // 拼接从高位到低位是 LED4、LED3、LED2、LED1；外层 ~ 将正逻辑变成低有效。
    // LED1=时钟锁定，LED2=暂停，LED3=最近接球，LED4=游戏结束。
    assign led_n=~{(state==3),(hit_flash!=0),(state==2),locked};
endmodule
