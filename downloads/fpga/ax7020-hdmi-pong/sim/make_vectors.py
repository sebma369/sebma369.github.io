"""Independent integer TMDS reference, DVI 1.0 section 3.2.2.
Run only when regenerating the supplied test data; no extra Python packages.
"""
from pathlib import Path
import random

# 独立参考模型：输入颜色字节、控制码、有效视频标志和旧运行偏差，返回符号及新偏差。
# 仅在重新生成已提供的.mem向量时需要运行；上板游戏不需要Python。
def encode(value, control, active, rd):
    # 消隐时只发送四种控制码，并把运行偏差清零。
    if not active:
        return [0b1101010100, 0b0010101011, 0b0101010100, 0b1010101011][control], 0
    # 按最低位优先拆成8位，再构造第一阶段XOR/XNOR链。
    bits = [(value >> i) & 1 for i in range(8)]
    invert_xor = sum(bits) > 4 or (sum(bits) == 4 and bits[0] == 0)
    stage = [bits[0]]
    for bit in bits[1:]:
        stage.append(stage[-1] ^ bit ^ int(invert_xor))
    low = sum(bit << i for i, bit in enumerate(stage))
    mode = int(not invert_xor)
    # 根据旧运行偏差和本数据的偏差方向，决定是否翻转低8位。
    difference = 2 * sum(stage) - 8
    if rd == 0 or difference == 0:
        inv = 1 - mode
    else:
        inv = int((rd > 0) == (difference > 0))
    word = (inv << 9) | (mode << 8) | (low ^ (255 if inv else 0))
    # 独立计数最终10位符号中的1数量更新偏差，避免直接照搬RTL中的更新公式。
    rd += 2 * bin(word).count('1') - 10
    # 再对符号反向解码，确认能还原输入字节；同时限制偏差范围。
    recovered_low = (word & 255) ^ (255 if word & 512 else 0)
    result = recovered_low & 1
    for i in range(1, 8):
        bit = ((recovered_low >> i) ^ (recovered_low >> (i-1))) & 1
        bit ^= 1 - ((word >> 8) & 1)
        result |= bit << i
    assert result == value
    assert abs(rd) <= 8
    return word, rd

def main():
    # 固定随机种子使参考向量可重复生成；每64组中穿插四种控制码以重置偏差。
    rng = random.Random(7020)
    rd = 0
    rows = []
    seen = set()
    for i in range(8192):
        active = int(i % 64 >= 4)
        control = i % 4
        value = (i // 64) if i % 64 == 4 else rng.randrange(256)
        value &= 255
        word, rd = encode(value, control, active, rd)
        if active: seen.add(value)
        # 打包为21位：de、两位控制、8位输入、10位答案，与tb_all中的切片保持一致。
        packed = (active << 20) | (control << 18) | (value << 10) | word
        rows.append(f"{packed:06x}\n")
    # 必须覆盖全部256种视频数据，而不只是生成足够多的随机样本。
    assert len(seen) == 256
    out = Path(__file__).with_name('tmds_vectors.mem')
    out.write_text(''.join(rows), encoding='ascii')
    print(f'{len(rows)} reference vectors; all 256 video values and 4 control tokens covered.')

if __name__ == '__main__':
    main()
