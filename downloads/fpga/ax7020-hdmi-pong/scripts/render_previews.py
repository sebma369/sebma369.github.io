"""Optional: convert testbench RGB exports into viewable reference PNGs.
Requires Pillow; source RTL and building the FPGA do not require Python/Pillow.
"""
from pathlib import Path
from PIL import Image
# 读取tb_render导出的二进制PPM，并转成文档能直接显示的PNG。
# Pillow仅用于这一步图片转换，不是RTL、仿真自检或构建FPGA的依赖。
root = Path(__file__).resolve().parents[1]
out = root / 'preview'
out.mkdir(exist_ok=True)
frames = []
for name in ['ready','run','pause','over']:
    # 检查尺寸，避免把未完整输出或选错模式的图片混入参考画面。
    im = Image.open(root / 'build' / 'sim' / f'frame_{name}.ppm').convert('RGB')
    assert im.size == (640, 480)
    im.save(out / f'{name}.png')
    frames.append(im)
# 保留每幅640×480原尺寸，按等待/运行/暂停/结束顺序组成2×2图。
grid = Image.new('RGB', (1280, 960))
for i, im in enumerate(frames):
    grid.paste(im, ((i % 2) * 640, (i // 2) * 480))
grid.save(out / 'states.png')
print(out / 'states.png')
