"""Check generated assets for silence, clipping and audible loop discontinuities."""
from array import array
from pathlib import Path
import math
import wave

root = Path(__file__).resolve().parents[1] / 'assets' / 'audio'
expected = {'menu', 'arena', 'click', 'success', 'jump', 'land', 'swing',
            'hit', 'blocked', 'defeat', 'respawn'}
assert {p.stem for p in root.glob('*.wav')} == expected
for name in sorted(expected):
    with wave.open(str(root / (name + '.wav')), 'rb') as wav:
        assert wav.getframerate() == 24000 and wav.getsampwidth() == 2
        assert wav.getnchannels() == 1
        pcm = array('h', wav.readframes(wav.getnframes()))
    peak = max(abs(x) for x in pcm) / 32767
    rms = math.sqrt(sum((x / 32767) ** 2 for x in pcm) / len(pcm))
    assert 0.03 < peak <= 0.81, (name, 'peak', peak)
    assert 0.01 < rms < 0.25, (name, 'rms', rms)
    if name in {'menu', 'arena'}:
        assert len(pcm) >= 16 * 24000
        seam = abs(pcm[-1] - pcm[0]) / 32767
        assert seam < 0.02, (name, 'seam', seam)
        # Every half-second contains actual music, including both sides of the loop.
        for offset in range(0, len(pcm), 12000):
            block = pcm[offset:offset + 12000]
            block_rms = math.sqrt(sum((x / 32767) ** 2 for x in block) / len(block))
            assert block_rms > 0.018, (name, offset, 'silent music window')
        print(f'PASS {name}: {len(pcm)/24000:g}s loop, seam={seam:.6f}, rms={rms:.3f}')
    else:
        assert abs(pcm[0]) <= 2 and abs(pcm[-1]) <= 2, (name, 'effect boundary')
        print(f'PASS {name}: nonzero bounded signal, clean start/end')
print('AUDIO SAMPLES RESULT: 11 assets passed')
