AX7020 LED 实验附件

rtl/led.v 与 sim/vtf_led_test.v 摘自本篇笔记。
constraints/led.xdc 包含基础引脚和 50 MHz 时钟约束，不含 ILA。
debug/ 保存现有带调试标记的设计、ILA 约束，以及 2026-10-14 同次生成的 led.bit / led.ltx。
基础实验先使用 rtl、sim、constraints。添加 ILA 时按正文操作，以实际网表信号为准。
目标器件：xc7z020clg400-2。现有比特流不是本次重新编译的结果。
