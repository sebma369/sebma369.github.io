`timescale 1ns/1ps
// 组合像素渲染器：根据当前x/y坐标，判断它落在文字、球、挡板还是背景上。
// 这里没有时钟、帧缓存或“画完一整帧”的循环，颜色随输入坐标组合变化。
// TEST_PATTERN=1时优先显示彩条；=0时使用状态和游戏位置绘制游戏画面。
module video_render #(parameter TEST_PATTERN=0)(
    // x/y包含消隐区；只有de=1时允许输出可见颜色。
    input wire [9:0] x, input wire [9:0] y, input wire de,
    input wire [1:0] state, input wire [9:0] paddle_x,
    input wire [9:0] ball_x, input wire [9:0] ball_y,
    input wire [6:0] score, input wire [1:0] lives,
    // 输出reg表示在always块中赋值；本模块是组合逻辑，并不因此自动生成寄存器。
    output reg [7:0] red, output reg [7:0] green, output reg [7:0] blue
);
    // 5列×7行字符ROM，共35位。最高5位[34:30]为第一行，最低5位为最后一行。
    // 每行从高位到低位对应从左向右的像素，1表示笔画，0表示透明背景。
    // 例如数字0第一行01110表示中间3点亮；未定义字符（包括空格）返回全0。
    // function在这里综合为查找逻辑，不是运行时调用CPU中的字体库。
    function [34:0] font;
        input [7:0] ch;
        begin
            case(ch)
                "0":font={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
                "1":font={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                "2":font={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
                "3":font={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
                "4":font={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
                "5":font={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
                "6":font={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
                "7":font={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
                "8":font={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
                "9":font={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
                "A":font={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "C":font={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
                "D":font={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
                "E":font={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
                "F":font={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
                "G":font={5'b01111,5'b10000,5'b10000,5'b10111,5'b10001,5'b10001,5'b01111};
                "I":font={5'b01110,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                "K":font={5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
                "L":font={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
                "M":font={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
                "N":font={5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
                "O":font={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "P":font={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
                "R":font={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
                "S":font={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
                "T":font={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
                "U":font={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "V":font={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b00100};
                "W":font={5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b10101,5'b01010};
                "Y":font={5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
                default:font=35'd0;
            endcase
        end
    endfunction

    // character为当前字符的8位ASCII编码；message最多保存9个ASCII字符。
    reg [7:0] character;
    reg [71:0] message;
    reg [34:0] glyph;
    // gx/gy是相对当前文字区域的坐标；cell_index是第几个字符单元。
    // column/row是缩小回5×7原始字模后的坐标；text_on表示本像素是否命中笔画。
    integer gx, gy, cell_index, column, row;
    reg text_on;
    always @* begin
        // 全部临时量先给默认值，未落在任何文字区域时使用空格，避免锁存器。
        character=" "; message="         "; gx=0; gy=0; cell_index=0;
        column=0; row=0; glyph=0; text_on=0;
        // 每个字符单元宽32、高28；5×7字模放大4倍后，实际笔画区宽20、高28。
        // 剩余12列形成字符间距，32列单元便于用移位与位掩码计算位置。
        // 顶栏文字在y=16～43，不随READY/RUN/PAUSE/OVER状态消失。
        if(y>=16 && y<44) begin
            gy=y-16;
            if(x>=24 && x<184) begin
                // 文字串从高字节开始排列；gx>>5相当于整除32，得到字符编号。
                gx=x-24; message="SCORE    "; cell_index=gx>>5;
                // Verilog可变起点位选：从该字符的最高位向下取8位ASCII编码。
                character=message[71-cell_index*8 -: 8];
            end
            else if(x>=208 && x<272) begin
                // 两个数字单元显示十位和个位。ASCII数字0编码为48，故加上数值即可。
                // 除数和模数为常量10，综合器将其映射为组合电路，不会运行除法程序。
                gx=x-208;
                if(gx<32) character=8'd48+score/10;
                else      character=8'd48+score%10;
            end
            else if(x>=368 && x<528) begin
                // 右上方的LIVES标签与机会数字使用相同的字符绘制通路。
                gx=x-368; message="LIVES    "; cell_index=gx>>5;
                character=message[71-cell_index*8 -: 8];
            end
            else if(x>=560 && x<592) begin gx=x-560; character=8'd48+lives; end
        end
        else if(state!=1 && x>=176 && x<464) begin
            // 运行状态1不显示中央提示，避免遮住游戏；其他状态显示固定的三行文字。
            gx=x-176; cell_index=gx>>5;
            if(y>=180 && y<208) begin gy=y-180; message="FPGA PONG"; end
            else if(y>=236 && y<264) begin
                // 字符串中的前后空格用于在9字符区域中居中READY/PAUSE。
                gy=y-236;
                case(state)
                    0:message="  READY  ";
                    2:message="  PAUSE  ";
                    3:message="GAME OVER";
                    default:message="         ";
                endcase
            end
            else if(y>=292 && y<320) begin
                // 结束时提示新一局，等待和暂停时提示KEY4开始/继续。
                gy=y-292;
                if(state==3) message="KEY4 NEW ";
                else         message="KEY4 PLAY";
            end
            character=message[71-cell_index*8 -: 8];
        end
        // gx & 31取字符单元内偏移；再除4得到原始字模的列，gy除4得到行。
        // 宽度和缩放均是2的幂，所以这里直接使用位运算，不需要可变除法器。
        column=(gx & 31)>>2; row=gy>>2;
        glyph=font(character);
        // 只在5×7字模内部查询；单元右侧空隙不画字。索引从高位向低位逐行扫描。
        if(column<5 && row<7) text_on=glyph[34-row*5-column];

        // 按顺序覆盖颜色，越靠后的绘制层优先级越高：
        // 背景 -> 网格 -> 边框 -> 挡板 -> 球 -> 文字 -> 测试彩条 -> 消隐黑色。
        red=8'h08; green=8'h10; blue=8'h20;
        // 低6位全0即每64个像素一条淡网格线，方便识别画面方向与大小。
        if(x[5:0]==0 || y[5:0]==0) begin red=8'h10; green=8'h20; blue=8'h32; end
        // 只绘制左右墙与顶边，底部故意留空，供球掉出并触发漏接。
        if((x>=12 && x<16 && y>=60)||(x>=624 && x<628 && y>=60)||
           (y>=60 && y<64 && x>=12 && x<628)) begin red=8'h30; green=8'h60; blue=8'ha0; end
        // 矩形采用左闭右开范围：挡板104×12，球10×10，与规则模块的尺寸一致。
        if(x>=paddle_x && x<paddle_x+104 && y>=438 && y<450) begin red=8'h20; green=8'he0; blue=8'hd0; end
        if(x>=ball_x && x<ball_x+10 && y>=ball_y && y<ball_y+10) begin red=8'hff; green=8'he0; blue=8'h30; end
        // 字符笔画覆盖物体颜色；GAME OVER这一行使用浅红色强调结束状态。
        if(text_on) begin
            red=8'hf0; green=8'hf0; blue=8'hf0;
            if(state==3 && y>=236 && y<264) begin red=8'hff; green=8'h60; blue=8'h60; end
        end
        if(TEST_PATTERN) begin
            // 将640列等分成8组，每组80列；彩条用来先验证时钟、编码和接线。
            // 这里覆盖游戏颜色，但不会停止其他模块工作。
            case(x/80)
                0:{red,green,blue}=24'hffffff;
                1:{red,green,blue}=24'hffff00;
                2:{red,green,blue}=24'h00ffff;
                3:{red,green,blue}=24'h00ff00;
                4:{red,green,blue}=24'hff00ff;
                5:{red,green,blue}=24'hff0000;
                6:{red,green,blue}=24'h0000ff;
                default:{red,green,blue}=24'h000000;
            endcase
        end
        // 消隐优先级最高；TMDS编码器此时看de=0并发送控制码，不把黑色当视频发送。
        if(!de) begin red=0; green=0; blue=0; end
    end
endmodule
