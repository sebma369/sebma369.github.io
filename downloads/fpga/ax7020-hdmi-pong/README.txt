AX7020 HDMI Pong 实验附件

目标器件：xc7z020clg400-2；RTL 顶层：pong_top。
rtl/：9 个设计源文件；sim/：自检、渲染测试与参考向量。
reference/：引脚与时序约束；scripts/：构建、仿真和参考图转换。
在本目录使用 Vivado Tcl 命令：vivado -mode batch -source scripts/build.tcl -tclargs 0
参数 0 生成游戏，参数 1 生成彩条。也可按正文新建 GUI 工程。
运行仿真：powershell -ExecutionPolicy Bypass -File scripts/run_tests.ps1
安装目录不同时，传入 -VivadoBin 指定路径。
build/ 中为 2026-10-20 已有构建产物与报告，不是本次重新编译。外部板卡、显示屏和线缆需另行验证。
