# 自动综合实现入口：vivado -mode batch -source scripts/build.tcl -tclargs 0
# 参数0生成游戏，参数1生成彩条；输出写入本实验build目录，不覆盖原LED工程。
# 本脚本使用内存工程，不保存可双击的.xpr；需要GUI工程时按指导文档新建。
# 从脚本自身位置定位实验根目录，避免调用者当前目录不同导致源文件路径失效。
set lab_root [file normalize [file join [file dirname [info script]] ..]]
set out_dir [file join $lab_root build]
file mkdir $out_dir
# 对参数做范围检查，防止误把其他字符串当成硬件参数。
set pattern 0
if {[llength $argv] > 0} {set pattern [lindex $argv 0]}
if {$pattern ni {0 1}} {error "TEST_PATTERN must be 0 or 1"}
set name [expr {$pattern ? "colour_bars" : "pong"}]
# 装载目标器件、全部RTL和板卡约束；TEST_PATTERN是综合时参数而非运行时按键。
create_project -in_memory -part xc7z020clg400-2
read_verilog [glob [file join $lab_root rtl *.v]]
read_xdc [file join $lab_root reference ax7020_pong.xdc]
synth_design -top pong_top -part xc7z020clg400-2 -generic TEST_PATTERN=$pattern
report_utilization -file [file join $out_dir ${name}_synth_util.rpt]
# 依次执行网表优化、资源放置、物理优化和布线，得到可分析实际延迟的电路。
opt_design
place_design
phys_opt_design
route_design
# 保存时序、资源、DRC、方法学与时钟报告，不能只凭“运行结束”判断全部通过。
report_timing_summary -report_unconstrained -file [file join $out_dir ${name}_timing.rpt]
report_utilization -file [file join $out_dir ${name}_util.rpt]
report_drc -file [file join $out_dir ${name}_drc.rpt]
report_methodology -file [file join $out_dir ${name}_methodology.rpt]
report_clocks -file [file join $out_dir ${name}_clocks.rpt]
# max路径检查建立时间，min路径检查保持时间；没有路径或裕量为负时直接中止。
# 这不表示测量了显示屏和线缆的模拟电气特性，检查范围以报告为准。
foreach delay_type {max min} {
    set path [get_timing_paths -delay_type $delay_type -max_paths 1]
    if {[llength $path] == 0} {error "No $delay_type timing path"}
    if {[get_property SLACK $path] < 0} {error "Timing violation: $delay_type"}
}
# 检查通过后保存布局布线检查点与比特流；-force允许更新本目录的旧生成结果。
write_checkpoint -force [file join $out_dir ${name}_routed.dcp]
write_bitstream -force [file join $out_dir ${name}.bit]
# 只有走到这里才宣告软件构建通过；真实板卡与显示屏仍需人工上板验收。
puts "BUILD PASS: $name (timing checked, bitstream generated; hardware not tested)"
