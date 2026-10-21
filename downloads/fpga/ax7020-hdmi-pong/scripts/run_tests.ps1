# 自动仿真入口。Vivado安装位置不同时，用-VivadoBin指定对应bin目录。
# 本脚本只编译、运行测试和导出参考图，不负责连接板卡或下载比特流。
param([string]$VivadoBin = 'D:\vivado\2025.2\Vivado\bin')
$ErrorActionPreference = 'Stop'
$labRoot = Split-Path $PSScriptRoot -Parent
$testDir = Join-Path $labRoot 'build\sim'
# 固定在build/sim执行，让缓存和日志集中保存，并保证相对路径能找到参考向量。
New-Item -ItemType Directory -Force -Path $testDir | Out-Null
Copy-Item -LiteralPath (Join-Path $labRoot 'sim\tmds_vectors.mem') -Destination $testDir -Force
$rtlFiles = @(Get-ChildItem -LiteralPath (Join-Path $labRoot 'rtl') -Filter '*.v' | ForEach-Object FullName)
$simFiles = @(Get-ChildItem -LiteralPath (Join-Path $labRoot 'sim') -Filter '*.sv' | ForEach-Object FullName)
# glbl是Vivado原语模型所需的上电全局信号模型，不是待综合的用户电路。
$glblFile = Join-Path (Split-Path $VivadoBin -Parent) 'data\verilog\src\glbl.v'
Push-Location $testDir
try {
    # xvlog编译源码；xelab按选定顶层展开；xsim运行展开后的仿真快照。
    & (Join-Path $VivadoBin 'xvlog.bat') --sv --work work @rtlFiles @simFiles $glblFile
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
    foreach ($top in @('tb_all','tb_render')) {
        $snapshot = "${top}_sim"
        # OSERDES需要unisims_ver和secureip库，否则可能找不到B_OSERDESE2模型。
        & (Join-Path $VivadoBin 'xelab.bat') "work.$top" work.glbl -L unisims_ver -L secureip -s $snapshot --debug typical
        if ($LASTEXITCODE -ne 0) { throw "xelab failed: $top" }
        'run all', 'quit' | Set-Content -Encoding ASCII -LiteralPath 'run.tcl'
        & (Join-Path $VivadoBin 'xsim.bat') $snapshot -tclbatch run.tcl -log "${top}.log"
        if ($LASTEXITCODE -ne 0) { throw "xsim failed: $top" }
        # 除进程返回码外再检查PASS标志，防止测试没有真正完成却被误当成成功。
        $logText = Get-Content -Raw -LiteralPath "${top}.log"
        if ($top -eq 'tb_all' -and $logText -notmatch 'PASS ALL:') { throw 'Tests did not finish successfully' }
        if ($top -eq 'tb_render' -and $logText -notmatch 'PASS render:') { throw 'Renderer did not finish successfully' }
    }
# 无论中途是否抛出错误，都恢复调用脚本前的工作目录。
} finally { Pop-Location }
Write-Output "Tests complete. Logs and PPM frames: $testDir"
