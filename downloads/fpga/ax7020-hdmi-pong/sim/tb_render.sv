`timescale 1ns/1ps
// 画面导出仿真：直接调用真实RTL渲染器，将四个状态的像素保存为PPM图片。
// 只验证渲染布局，不经过TMDS编码、串化或真实显示屏，不能当作上板成功证据。
// 本文件位于Simulation Sources；文件读写、#延时、$finish不能综合进FPGA。
module tb_render;
    reg [9:0] x=0,y=0;
    reg [1:0] state=0;
    wire [7:0] r,g,b;
    integer out_file,xx,yy,s;
    // 全部采样点都在640×480可见区，故de固定为1；测试位置与分数是演示场景。
    // READY/OVER让球贴近挡板；RUN/PAUSE把球放在空中，方便观察不同状态。
    video_render dut(.x(x),.y(y),.de(1'b1),.state(state),.paddle_x(10'd268),
        .ball_x((state==0 || state==3)?10'd315:10'd350),
        .ball_y((state==0 || state==3)?10'd428:10'd360),
        .score((state==0)?7'd0:7'd12),.lives((state==3)?2'd0:2'd3),.red(r),.green(g),.blue(b));
    initial begin
        for(s=0;s<4;s=s+1) begin
            // 状态编码0/1/2/3依次为等待/运行/暂停/结束，每种状态写一张图。
            state=s;
            case(s)
                0:out_file=$fopen("frame_ready.ppm","wb");
                1:out_file=$fopen("frame_run.ppm","wb");
                2:out_file=$fopen("frame_pause.ppm","wb");
                3:out_file=$fopen("frame_over.ppm","wb");
            endcase
            // 检查文件确实打开；"wb"是二进制写入，避免换行转换破坏像素字节。
            if(!out_file) $fatal(1,"Cannot write image");
            // P6头部指定PPM二进制RGB格式、宽高和每个颜色分量的最大值255。
            $fwrite(out_file,"P6\n640 480\n255\n");
            // 外层遍历行、内层遍历列。#1让组合逻辑在坐标改变后充分稳定，
            // 随后按R/G/B顺序各写一个字节；这不是实际扫描时钟，也不模拟刷新率。
            for(yy=0;yy<480;yy=yy+1)
                for(xx=0;xx<640;xx=xx+1) begin
                    x=xx;y=yy;#1;$fwrite(out_file,"%c%c%c",r,g,b);
                end
            // 完成一个状态后关闭文件，确保写出的数据能被后续Python程序完整读取。
            $fclose(out_file);
        end
        $display("PASS render: four RGB reference frames exported");$finish;
    end
endmodule
