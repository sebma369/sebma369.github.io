`timescale 1ns/1ps
// 自检总入口：六类测试并行执行，每个done表示该组断言已经全部完成。
// 仿真专用语法包括initial、#延时、task、$fatal和层次化寄存器赋值，均不在RTL中。
module tb_all;
    wire a,b,c,d,e,f;
    test_keys keys(a);
    test_game game(b);
    test_timing timing(c);
    test_encoder encoder(d);
    test_serializer serializer(e);
    test_clock clocks(f);
    initial begin
        // 所有子测试都完成才输出PASS ALL；任一断言失败会直接报错，不能只看局部PASS。
        wait(a && b && c && d && e && f);
        $display("PASS ALL: keys, game, timing, encoder, serializer, clocks");
        $finish;
    end
    // 20 ms仿真时间看门狗，防止等待条件永远不满足而让Run All一直运行。
    initial begin #20000000; $fatal(1,"TIMEOUT"); end
endmodule

// 按键测试：把稳定阈值缩短为4周期，快速验证消抖而不等待真实10 ms。
module test_keys(output reg done=0);
    reg clk=0,reset=1,key_n=1;
    wire down,press;
    integer presses=0;
    always #5 clk=~clk;
    key_filter #(.STABLE_CYCLES(4)) dut(clk,reset,key_n,down,press);
    // 对单周期事件计数，既检查漏报，也检查长按导致的重复事件。
    always @(posedge clk) if(press) presses=presses+1;
    task cycles(input integer n); repeat(n) @(negedge clk); endtask
    initial begin
        cycles(3); reset=0;
        // 先注入几次不足阈值的低电平抖动，稳定状态和事件数都应不变。
        cycles(3); key_n=0; cycles(1); key_n=1; cycles(2);
        key_n=0; cycles(1); key_n=1; cycles(10);
        if(down || presses!=0) $fatal(1,"bounce not filtered");
        // 再稳定按下，等待两级同步与消抖完成，然后验证长按只产生一次事件。
        key_n=0; cycles(12);
        if(!down || presses!=1) $fatal(1,"press not registered");
        cycles(30); if(presses!=1) $fatal(1,"held key repeated");
        // 松开并稳定之后再次按下，才应看到第二次press。
        key_n=1; cycles(12); if(down) $fatal(1,"release failed");
        key_n=0; cycles(12); if(presses!=2) $fatal(1,"second press failed");
        $display("PASS keys: bounce, hold, release, second press"); done=1;
    end
endmodule

// 游戏测试：直接驱动已消抖的按键输入及帧使能，专注于规则与状态机。
// 人为加快帧使能间隔，避免测试规则时还要逐个跑完整视频帧。
module test_game(output reg done=0);
    reg clk=0,reset=1,frame=0,left=0,right=0,action=0;
    wire [1:0] state,lives;
    wire [9:0] px,bx,by;
    wire [6:0] score;
    wire [3:0] flash;
    integer i;
    reg [9:0] hold_x,hold_y;
    always #5 clk=~clk;
    pong_game dut(clk,reset,frame,left,right,action,state,px,bx,by,score,lives,flash);
    // 在时钟下降沿改变激励，避免与DUT的上升沿采样产生仿真竞争。
    // frame只保持一个clk周期，模拟一次游戏帧更新。
    task tick;
        @(negedge clk); frame=1;
        @(negedge clk); frame=0;
    endtask
    // 先产生一个动作脉冲，隔几个周期再给frame，专门验证action_pending不会漏事件。
    task command;
        @(negedge clk); action=1;
        @(negedge clk); action=0;
        repeat(3) @(negedge clk);
        tick();
    endtask
    initial begin
        repeat(3) @(negedge clk); reset=0; tick();
        if(state!=0 || lives!=3 || score!=0) $fatal(1,"initial state");
        // 长时间分别按左、右，必须钳位到16与520，不能越过球场。
        left=1; repeat(100) tick(); left=0;
        if(px!=16) $fatal(1,"left clamp");
        right=1; repeat(100) tick(); right=0;
        if(px!=520) $fatal(1,"right clamp");
        // 依次检查开始、暂停、暂停期间位置不变、继续。
        command(); if(state!=1) $fatal(1,"start or event latch");
        command(); if(state!=2) $fatal(1,"pause");
        hold_x=bx; hold_y=by; repeat(4) tick();
        if(bx!=hold_x || by!=hold_y) $fatal(1,"paused movement");
        command(); if(state!=1) $fatal(1,"resume");
        // 定向场景：直接在Testbench中设置被测寄存器，快速到达墙边/挡板边界。
        // 这些层次化赋值只属于仿真，不代表上板逻辑有外部修改坐标的后门。
        @(negedge clk); dut.ball_x=17; dut.ball_y=100; dut.dir_left=1; dut.dir_up=1;
        tick(); if(bx!=16 || dut.dir_left!=0) $fatal(1,"left wall");
        @(negedge clk); dut.ball_y=65; dut.dir_up=1;
        tick(); if(by!=64 || dut.dir_up!=0) $fatal(1,"ceiling");
        @(negedge clk); dut.ball_x=550; dut.ball_y=426; dut.dir_up=0;
        tick(); if(by!=428 || dut.dir_up!=1 || score!=1 || flash!=10) $fatal(1,"catch");
        // 满分后再接球应保持99，不能回绕到0或溢出为100。
        @(negedge clk); dut.score=99; dut.ball_x=550; dut.ball_y=426; dut.dir_up=0;
        tick(); if(score!=99) $fatal(1,"score saturation");
        // 连续制造三次漏接；前两次可再发球，最后一次必须进入OVER。
        for(i=0;i<3;i=i+1) begin
            @(negedge clk); dut.ball_x=20; dut.ball_y=478; dut.dir_up=0;
            tick();
            if(lives!=2-i) $fatal(1,"life decrement");
            if(i<2) begin if(state!=0) $fatal(1,"serve after miss"); command(); end
        end
        if(state!=3) $fatal(1,"game over");
        command(); if(state!=0 || score!=0 || lives!=3) $fatal(1,"restart");
        command();
        // 随机按键回归：检查1500次帧更新中的坐标、分数和机会范围。
        // 这是不变量检查，不是穷尽证明，也不预先规定随机游戏轨迹。
        for(i=0;i<1500;i=i+1) begin
            @(negedge clk); left=$urandom_range(0,1); right=$urandom_range(0,1);
            if(state==0 || state==3) command();
            tick();
            if(px<16 || px>520 || bx<16 || bx>614 || by<64 || by>=480 || score>99 || lives>3)
                $fatal(1,"game invariant");
        end
        $display("PASS game: controls, bounds, catch, score, lives, restart, 1500 frames"); done=1;
    end
endmodule

// 扫描测试：遍历完整一帧，统计可见像素与低有效同步宽度，而不靠目测波形。
// 测试时钟为10 ns周期，仅验证计数结构；真实频率另由test_clock检查。
module test_timing(output reg done=0);
    reg clk=0,reset=1;
    wire [9:0] x,y;
    wire de,hs,vs,ft;
    integer n,active_count,hs_count,vs_count,frames;
    always #5 clk=~clk;
    video_timing dut(clk,reset,x,y,de,hs,vs,ft);
    initial begin
        repeat(3) @(negedge clk); reset=0;
        active_count=0;hs_count=0;vs_count=0;frames=0;
        // 与线性编号n换算得到的x=n%800、y=n/800逐点比较，包含所有消隐区域。
        for(n=0;n<800*525;n=n+1) begin
            if(x != n%800 || y != n/800) $fatal(1,"raster position");
            if(de) active_count=active_count+1;
            if(!hs) hs_count=hs_count+1;
            if(!vs) vs_count=vs_count+1;
            if(ft) frames=frames+1;
            @(negedge clk);
        end
        // 一圈结束后坐标归零；行同步每行96点，场同步2行，每帧仅一个frame_tick。
        if(x!=0 || y!=0 || active_count!=640*480 || hs_count!=96*525 || vs_count!=2*800 || frames!=1)
            $fatal(1,"video timing geometry");
        $display("PASS timing: 800x525 total, 640x480 active, sync widths, one frame tick");done=1;
    end
endmodule

// TMDS编码测试：参考向量由独立Python整数模型生成，不由DUT自己生成“答案”。
module test_encoder(output reg done=0);
    reg clk=0,reset=1,de=0,c0=0,c1=0;
    reg [7:0] data=0;
    wire [9:0] symbol;
    reg [20:0] vectors [0:8191];
    integer i;
    always #5 clk=~clk;
    tmds_encoder dut(clk,reset,data,de,c0,c1,symbol);
    initial begin
        // 每行21位：[20]=de，[19:18]={c1,c0}，[17:10]=颜色字节，[9:0]=预期符号。
        // 数据文件必须位于仿真工作目录；自动脚本会复制，GUI仿真需加入仿真数据。
        $readmemh("tmds_vectors.mem",vectors);
        repeat(3) @(negedge clk); reset=0;
        for(i=0;i<8192;i=i+1) begin
            {de,c1,c0,data}=vectors[i][20:10];
            // 上升沿后等1 ns，再比较非阻塞赋值更新后的寄存输出。
            @(posedge clk); #1;
            if(symbol !== vectors[i][9:0]) $fatal(1,"TMDS vector %0d got %h expected %h",i,symbol,vectors[i][9:0]);
            @(negedge clk);
        end
        $display("PASS encoder: 8192 independent reference vectors"); done=1;
    end
endmodule

// 串化器测试：使用Vivado的真实原语模型，验证主从扩展与bit0最先发送。
// 仅要求像素/高速时钟严格1:5，故这里使用40 ns和8 ns周期便于观察。
module test_serializer(output reg done=0);
    reg pixel_clk=0,serial_clk=0,reset=1;
    reg [9:0] word=10'b1101000101;
    wire serial;
    reg [99:0] samples;
    integer i,offset,j;
    reg found,match_word;
    always #20 pixel_clk=~pixel_clk;
    always #4 serial_clk=~serial_clk;
    tmds_serial dut(pixel_clk,serial_clk,reset,word,serial);
    // 等待串化器流水线稳定，再在高速时钟的每一个边沿采样，覆盖DDR双沿输出。
    task check_word;
        repeat(8) @(posedge pixel_clk);
        for(i=0;i<100;i=i+1) begin @(serial_clk); #0.1; samples[i]=serial; end
        found=0;
        // 静态测试字会重复发送。遍历10个可能的字边界偏移，检查连续80个位。
        // 这验证位序及级联，不用于宣称测出了精确流水线延迟或模拟电气性能。
        for(offset=0;offset<10;offset=offset+1) begin
            match_word=1;
            for(j=0;j<80;j=j+1) if(samples[offset+j]!==word[j%10]) match_word=0;
            if(match_word) found=1;
        end
        if(!found) $fatal(1,"OSERDES bit order/cascade %b",word);
    endtask
    initial begin
        // 避开glbl模型的上电全局复位区间，再解除用户复位。
        #220; @(negedge pixel_clk); reset=0;
        check_word();
        @(negedge pixel_clk); word=10'b0010111010; check_word();
        @(negedge pixel_clk); word=10'b0000011111; check_word();
        $display("PASS serializer: cascade and LSB-first serial order");done=1;
    end
endmodule

// 时钟与复位测试：输入真实50 MHz，等待MMCM模型锁定并测量两路输出周期。
module test_clock(output reg done=0);
    reg clk=0,reset=1;
    wire pixel,serial,locked,logic_reset;
    // realtime保留小数ns，避免用整数时间测量39.683 ns时产生过大舍入误差。
    realtime p0,p1,s0,s1;
    always #10 clk=~clk;
    clock_gen dut(clk,reset,pixel,serial,locked);
    reset_sync resetter(pixel,!locked,logic_reset);
    initial begin
        #200; reset=0; wait(locked);
        repeat(10) @(posedge pixel);
        p0=$realtime; @(posedge pixel); p1=$realtime;
        @(posedge serial); s0=$realtime; @(posedge serial); s1=$realtime;
        if(p1-p0<39.67 || p1-p0>39.70 || s1-s0<7.93 || s1-s0>7.95)
            $fatal(1,"MMCM frequency: pixel %f serial %f",p1-p0,s1-s0);
        if(logic_reset!==0) $fatal(1,"reset did not release after lock");
        // 再次复位MMCM，确认失锁使逻辑复位有效，重新锁定后按像素时钟同步释放。
        @(negedge clk); reset=1;
        wait(!locked); #1;
        if(logic_reset!==1) $fatal(1,"lock loss did not assert reset");
        repeat(4) @(negedge clk); reset=0;
        wait(locked); repeat(3) @(posedge pixel); #1;
        if(logic_reset!==0) $fatal(1,"reset did not release on relock");
        $display("PASS clocks: periods %f/%f ns; reset on lock loss and synchronous release",p1-p0,s1-s0);
        done=1;
    end
endmodule
