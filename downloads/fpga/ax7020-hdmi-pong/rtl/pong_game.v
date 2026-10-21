`timescale 1ns/1ps
// 游戏规则核心：四状态控制器 + 挡板/球坐标寄存器 + 碰撞和计分逻辑。
// 位置表示矩形左上角；x 向右增大，y 向下增大，单位均为可见区域像素。
// clk 是 25.2 MHz 像素时钟，但物理运动只在每帧一次的 frame_tick 时提交。
module pong_game(
    // reset 高有效；frame_tick 是单周期使能，不是另一根时钟。
    input wire clk, input wire reset, input wire frame_tick,
    // 左右使用消抖后的持续电平；动作键使用消抖后的单周期按下脉冲。
    input wire left_down, input wire right_down, input wire action_press,
    // state：0等待、1运行、2暂停、3结束；挡板只改变水平方向的位置。
    output reg [1:0] state, output reg [9:0] paddle_x,
    output reg [9:0] ball_x, output reg [9:0] ball_y,
    output reg [6:0] score, output reg [1:0] lives,
    // 接球指示灯的剩余点亮帧数；10 帧在 60 Hz 下约为 0.167 秒。
    output reg [3:0] hit_flash
);
    // 2 位状态寄存器编码；使用有名字的常量，使跳转规则更易阅读。
    localparam READY=2'd0, RUN=2'd1, PAUSE=2'd2, OVER=2'd3;
    // RIGHT 是球场右侧的排他边界；球和挡板的左坐标上限需减去自身宽度。
    // 挡板顶边 y=438、宽104；球宽高均为10；上边界 y=64 给计分栏留空间。
    localparam LEFT=16, RIGHT=624, TOP=64, PAD_Y=438, PAD_W=104, BALL=10;
    // 方向位：1 向左/向上，0 向右/向下；事件暂存位负责跨越帧间隔。
    reg dir_left, dir_up, action_pending;
    // 临时下一位置用整数表达计算结果，再在提交时写入 10 位位置寄存器。
    integer px_next, bx_next, by_next;
    reg dx_next, dy_next, hit_next;

    // 组合计算块：根据“当前寄存器值”推导“下一次帧更新应使用的值”。
    // 这里用阻塞赋值 =，后面的判断立即使用本组合块刚算出的中间结果。
    // 先给默认值，保证各分支都能得到结果，不会因漏赋值推断锁存器。
    always @* begin
        px_next = paddle_x;
        // 只有单独按左或单独按右才移动；同时按住或都松开时保持原位置。
        // 每帧7像素；靠边时钳位到边界，避免直接加减后越界。
        if (left_down && !right_down) begin
            if (paddle_x < LEFT+7) px_next = LEFT;
            else px_next = paddle_x-7;
        end
        else if (right_down && !left_down) begin
            if (paddle_x > RIGHT-PAD_W-7) px_next = RIGHT-PAD_W;
            else px_next = paddle_x+7;
        end
        bx_next = ball_x;
        by_next = ball_y;
        dx_next = dir_left;
        dy_next = dir_up;
        hit_next = 1'b0;
        // 只有运行状态才计算球的运动；每个方向的速度为4像素/帧。
        if (state == RUN) begin
            if (dir_left) bx_next = ball_x-4; else bx_next = ball_x+4;
            if (dir_up)   by_next = ball_y-4; else by_next = ball_y+4;
            // 撞左右墙或顶边时，将球移回合法位置，并翻到离开墙面的方向。
            if (bx_next < LEFT) begin bx_next=LEFT; dx_next=1'b0; end
            if (bx_next > RIGHT-BALL) begin bx_next=RIGHT-BALL; dx_next=1'b1; end
            if (by_next < TOP) begin by_next=TOP; dy_next=1'b0; end
            // 接球要同时满足：正在下降、球底本来在挡板顶面上方、下一步越过顶面，
            // 并且下一步球的水平范围与下一步挡板范围有重叠。
            // 使用“穿过顶面”而非任意重叠，可避免球在挡板内连续反弹、重复计分。
            if (!dir_up && ball_y+BALL <= PAD_Y && by_next+BALL >= PAD_Y &&
                bx_next+BALL > px_next && bx_next < px_next+PAD_W) begin
                by_next = PAD_Y-BALL;
                // 球底紧贴挡板顶面后改为上行，本次只产生一次接球事件。
                dy_next = 1'b1;
                hit_next = 1'b1;
            end
        end
    end

    // 时序提交块：只有此块写游戏寄存器，避免同一寄存器出现多个驱动源。
    // <= 是非阻塞赋值：这一时钟沿的判断都看旧值，各新值在该沿之后一起生效。
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // 挡板居中；球位于其上方。分数清零、3次机会，从等待发球开始。
            state<=READY; paddle_x<=268; ball_x<=315; ball_y<=428;
            dir_left<=0; dir_up<=1; score<=0; lives<=3;
            hit_flash<=0; action_pending<=0;
        end
        else begin
            // 动作脉冲可能落在任意像素周期，先记下来，不能只在 frame_tick 时采样。
            if (action_press) action_pending <= 1'b1;
            if (frame_tick) begin
                // 每帧消费至多一次动作；若脉冲恰好本周期出现，下面的 || 仍能处理。
                // 同一块内对 action_pending 的后一次赋值优先，因此消费后清零。
                action_pending <= 1'b0;
                if (hit_flash != 0) hit_flash <= hit_flash-1'b1;
                // 动作优先于本帧运动：暂停/继续/发球的这一帧不额外移动球。
                if (action_pending || action_press) begin
                    case (state)
                        READY: begin state<=RUN; dir_up<=1; end
                        RUN:   state<=PAUSE;
                        PAUSE: state<=RUN;
                        OVER: begin
                            // 结束后的第一次动作只创建新一局；再按一次才从 READY 发球。
                            state<=READY; paddle_x<=268; ball_x<=315; ball_y<=428;
                            dir_left<=0; dir_up<=1; score<=0; lives<=3; hit_flash<=0;
                        end
                    endcase
                end
                else if (state == READY) begin
                    // 等待发球时仍能移动挡板，球的水平中心跟随挡板中心。
                    paddle_x <= px_next;
                    ball_x <= px_next+(PAD_W-BALL)/2;
                    ball_y <= PAD_Y-BALL;
                end
                else if (state == RUN) begin
                    paddle_x <= px_next;
                    if (by_next >= 480) begin
                        // 球的左上角已进入画面底部之外，视为漏接。
                        // lives==1 判断的是扣减前的旧值，所以这一次会变为0并结束。
                        lives <= lives-1'b1;
                        ball_x <= px_next+(PAD_W-BALL)/2;
                        ball_y <= PAD_Y-BALL;
                        dir_up <= 1'b1;
                        if (lives == 1) state <= OVER;
                        else            state <= READY;
                    end
                    else begin
                        // 未漏接时，统一提交组合块给出的位置和方向。
                        ball_x<=bx_next; ball_y<=by_next;
                        dir_left<=dx_next; dir_up<=dy_next;
                        if (hit_next) begin
                            // 只在接球事件中加分，99后饱和；重置指示灯倒计时。
                            if (score < 99) score <= score+1'b1;
                            hit_flash <= 10;
                        end
                    end
                end
                // PAUSE 和 OVER 不写位置寄存器，所以位置保持；视频电路不受此暂停影响。
                // hit_flash 位于公共帧逻辑中，即使暂停，它仍会按帧减到0。
            end
        end
    end
endmodule
