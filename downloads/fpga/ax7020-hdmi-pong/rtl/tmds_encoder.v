`timescale 1ns/1ps
// DVI 1.0 TMDS编码器：可见区将8位颜色编码为10位符号，消隐区发送控制码。
// 第一级选择XOR/XNOR，减少相邻位跳变；第二级选择是否翻转，平衡长期1/0数量。
// 三个颜色通道各需要一套独立编码器，不能共享运行偏差寄存器。
module tmds_encoder(
    input wire clk, input wire reset, input wire [7:0] data,
    input wire de, input wire c0, input wire c1, output reg [9:0] symbol
);
    // data：当前颜色字节；de=1为有效视频；de=0时使用控制位{c1,c0}。
    // symbol 为寄存后的编码结果，编码本身有1个像素时钟周期延迟。
    reg [8:0] qm;
    // qm[7:0]是第一级结果，qm[8]记录使用的是XOR(1)还是XNOR(0)。
    reg [9:0] next_symbol;
    // disparity 为此前发送符号累计的“1数量减0数量”，需要带符号运算。
    // next_* 为组合计算结果；只有末尾时序块负责保存到下一周期。
    reg signed [5:0] disparity, next_disparity;
    integer ones, balance, k;
    reg use_xnor;
    always @* begin
        // 统计输入字节中1的数量。for循环在综合中展开为逻辑，不是用8个时钟计算。
        ones=0;
        for(k=0;k<8;k=k+1) ones=ones+data[k];
        // 多数位为1，或正好4个1且最低位为0时，选择XNOR链。
        use_xnor=(ones>4)||((ones==4)&&!data[0]);
        // 最低位直接保留，后续位依赖本组合链前一位的结果，因此这里使用 =。
        qm[0]=data[0];
        for(k=1;k<8;k=k+1)
            if(use_xnor) qm[k]=~(qm[k-1]^data[k]);
            else         qm[k]=qm[k-1]^data[k];
        qm[8]=!use_xnor;
        // 重新统计第一级结果的1数量，balance=1数量-0数量，范围为-8～8。
        ones=0;
        for(k=0;k<8;k=k+1) ones=ones+qm[k];
        balance=2*ones-8;
        // 为全部组合输出给默认值，之后按分支覆盖，避免生成锁存器。
        next_disparity=disparity;
        next_symbol=10'd0;
        if(!de) begin
            // 消隐区发送四种专用控制码，同时将运行偏差清零。
            // 顶层蓝通道中 c0=行同步、c1=场同步，其他颜色通道都接0。
            next_disparity=0;
            case({c1,c0})
                2'b00: next_symbol=10'b1101010100;
                2'b01: next_symbol=10'b0010101011;
                2'b10: next_symbol=10'b0101010100;
                2'b11: next_symbol=10'b1010101011;
            endcase
        end
        else if(disparity==0 || balance==0) begin
            // 历史偏差为0，或本数据低8位本身平衡时，用qm[8]决定是否反相。
            // symbol[9]记录是否反相低8位，symbol[8]保留第一级模式位。
            next_symbol[9]=!qm[8]; next_symbol[8]=qm[8];
            if(qm[8]) begin next_symbol[7:0]=qm[7:0]; next_disparity=disparity+balance; end
            else begin next_symbol[7:0]=~qm[7:0]; next_disparity=disparity-balance; end
        end
        else if((disparity>0 && balance>0)||(disparity<0 && balance<0)) begin
            // 历史偏差与本数据同号：反相低8位，抵消而非继续放大已有偏差。
            // 更新公式同时计算低8位和额外2个位对总偏差的贡献。
            next_symbol={1'b1,qm[8],~qm[7:0]};
            next_disparity=disparity-balance+(qm[8]?2:0);
        end
        else begin
            // 两者方向相反，保留低8位即可使累计偏差向0靠近。
            next_symbol={1'b0,qm[8],qm[7:0]};
            next_disparity=disparity+balance-(qm[8]?0:2);
        end
    end
    // 每像素沿保存一个符号及新的偏差。reset置为合法控制码并清零历史偏差。
    // 三路RGB及同步控制均按同样的编码延迟传递，避免颜色和消隐错位。
    always @(posedge clk or posedge reset)
        if(reset) begin symbol<=10'b1101010100; disparity<=0; end
        else begin symbol<=next_symbol; disparity<=next_disparity; end
endmodule
