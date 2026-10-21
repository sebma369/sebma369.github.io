# AX7020约束参考：指导文档的主流程是在交互窗口填写，再保存为XDC。
# 自动构建脚本读取本文件；若GUI工程已有同样约束，不要再重复导入。
# 第一组：50 MHz晶振的物理管脚、电平与20 ns输入时钟约束。
set_property PACKAGE_PIN U18 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
create_clock -name sys_clk -period 20.000 [get_ports sys_clk]

# 第二组：PL KEY1～KEY4。管脚来自本目录手册，按下时为低电平。
# 端口名含方括号时加大括号，避免Tcl将方括号当成命令替换。
set_property PACKAGE_PIN N15 [get_ports {key_n[0]}]
set_property PACKAGE_PIN N16 [get_ports {key_n[1]}]
set_property PACKAGE_PIN T17 [get_ports {key_n[2]}]
set_property PACKAGE_PIN R17 [get_ports {key_n[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key_n[*]}]
# 原始机械按键与时钟异步：仅排除“从这些原始输入出发”的路径。
# RTL仍通过专用同步链处理输入和复位释放，不能把false path当成同步电路。
# 不排除像素域内部或串化器内部的数据路径，避免掩盖真正的时序违例。
set_false_path -from [get_ports {key_n[*]}]

# 第三组：四个低有效PL用户LED，使用3.3 V LVCMOS电平。
set_property PACKAGE_PIN M14 [get_ports {led_n[0]}]
set_property PACKAGE_PIN M15 [get_ports {led_n[1]}]
set_property PACKAGE_PIN K16 [get_ports {led_n[2]}]
set_property PACKAGE_PIN J16 [get_ports {led_n[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_n[*]}]

# 第四组：TMDS时钟及三路数据差分对，P/N必须与手册一一对应。
# 这里是TMDS_33，不能把所有端口统一设为普通LVCMOS33。
# D0/D1/D2分别发送蓝/绿/红，通道或P/N接反会造成无信号或颜色错误。
set_property PACKAGE_PIN N18 [get_ports hdmi_clk_p]
set_property PACKAGE_PIN P19 [get_ports hdmi_clk_n]
set_property PACKAGE_PIN V20 [get_ports {hdmi_data_p[0]}]
set_property PACKAGE_PIN W20 [get_ports {hdmi_data_n[0]}]
set_property PACKAGE_PIN T20 [get_ports {hdmi_data_p[1]}]
set_property PACKAGE_PIN U20 [get_ports {hdmi_data_n[1]}]
set_property PACKAGE_PIN N20 [get_ports {hdmi_data_p[2]}]
set_property PACKAGE_PIN P20 [get_ports {hdmi_data_n[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_clk_p hdmi_clk_n hdmi_data_p[*] hdmi_data_n[*]}]
# 最后一位是板卡HDMI输出端供电使能，属于普通控制信号，使用LVCMOS33。
set_property PACKAGE_PIN V16 [get_ports hdmi_out_en]
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_out_en]
