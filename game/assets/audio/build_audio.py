"""Render original music and effects using only Python's standard library.

No samples, recordings, external music, or third-party melodies are used.
Run this file to regenerate the adjacent 24 kHz, 16-bit mono WAV assets.
"""
from array import array
from pathlib import Path
import math
import random
import wave

RATE = 24000
TAU = 2 * math.pi
ROOT = Path(__file__).resolve().parent
RNG = random.Random(7319)


def hz(midi):
    return 440 * 2 ** ((midi - 69) / 12)


def empty(seconds):
    return array('f', [0.0]) * round(seconds * RATE)


def mix(target, source, start, gain=1.0, wrap=False):
    offset = round(start * RATE)
    for i, sample in enumerate(source):
        index = offset + i
        if wrap:
            index %= len(target)
        elif index >= len(target):
            break
        target[index] += sample * gain


def note(midi, duration, voice='pluck'):
    result = empty(duration)
    frequency = hz(midi)
    for i in range(len(result)):
        t = i / RATE
        attack = min(1, t / (0.09 if voice == 'pad' else 0.009))
        release = min(1, (duration - t) / (0.17 if voice == 'pad' else 0.045))
        phase = TAU * frequency * t
        if voice == 'pad':
            sample = math.sin(phase) + 0.2 * math.sin(phase * 2 + 0.09 * math.sin(TAU * t))
            envelope = attack * release * 0.6
        elif voice == 'bass':
            sample = math.sin(phase) + 0.22 * math.sin(phase * 2)
            envelope = attack * release * math.exp(-2.4 * t)
        else:
            sample = math.sin(phase) + 0.25 * math.sin(phase * 2) + 0.07 * math.sin(phase * 3)
            envelope = attack * release * math.exp(-5.5 * t)
        result[i] = sample * envelope
    return result


def percussion(kind):
    duration = {'kick': 0.25, 'snare': 0.16, 'hat': 0.055}[kind]
    result = empty(duration)
    phase = 0
    previous_noise = 0
    for i in range(len(result)):
        t = i / RATE
        noise = RNG.uniform(-1, 1)
        attack = min(1.0, t / 0.0015)
        release = min(1.0, (duration - t) / 0.02)
        if kind == 'kick':
            phase += TAU * (48 + 65 * math.exp(-35 * t)) / RATE
            value = math.sin(phase) * math.exp(-15 * t)
        elif kind == 'snare':
            value = (noise * 0.62 + math.sin(TAU * 170 * t) * 0.38) * math.exp(-25 * t)
        else:
            value = (noise - previous_noise) * 0.35 * math.exp(-75 * t)
        previous_noise = noise
        result[i] = value * attack * release
    return result


def write(name, samples, peak_limit=0.8):
    peak = max(abs(x) for x in samples)
    scale = min(1, peak_limit / max(peak, 0.000001))
    pcm = array('h', (round(max(-1, min(1, x * scale)) * 32767) for x in samples))
    with wave.open(str(ROOT / (name + '.wav')), 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(pcm.tobytes())
    rms = math.sqrt(sum((x / 32767) ** 2 for x in pcm) / len(pcm))
    print(f'{name:8} {len(pcm)/RATE:6.2f}s peak={max(abs(x) for x in pcm)/32767:.3f} rms={rms:.3f}')


def music(name, bpm, energetic):
    beat = 60 / bpm
    result = empty(32 * beat)
    # Original eight-bar D-minor / B-flat / F / C motif, with a suspended resolution.
    chords = [(50, 57, 65), (50, 57, 64), (46, 53, 62), (46, 53, 65),
              (53, 60, 69), (53, 60, 67), (48, 55, 64), (48, 55, 62)]
    melody = [[74, 77, 76, 69], [72, 69, 65, 69], [70, 74, 77, 74], [72, 70, 65, 62],
              [69, 72, 77, 76], [72, 69, 67, 65], [67, 72, 76, 74], [72, 67, 69, 72]]
    kick, snare, hat = [percussion(kind) for kind in ('kick', 'snare', 'hat')]
    for bar, chord in enumerate(chords):
        start = bar * 4 * beat
        for pitch in chord:
            mix(result, note(pitch + 12, 4.2 * beat, 'pad'), start, 0.04, True)
        for step in range(8):
            pitch = chord[step % 3] + (12 if step % 4 == 3 else 0)
            mix(result, note(pitch + 12, 0.75, 'pluck'), start + step * beat / 2,
                0.065 if energetic else 0.085, True)
            if energetic:
                mix(result, hat, start + step * beat / 2, 0.052 if step % 2 else 0.025, True)
        for step, pitch in enumerate(melody[bar]):
            mix(result, note(pitch, 0.85, 'pluck'), start + (step + 0.25) * beat,
                0.09 if energetic else 0.075, True)
        for step in (0, 2) if not energetic else (0, 1.5, 2, 3.5):
            mix(result, note(chord[0] - 12, 0.8 * beat, 'bass'), start + step * beat, 0.16, True)
        if energetic:
            for step in (0, 2, 2.75):
                mix(result, kick, start + step * beat, 0.23 if step != 2.75 else 0.11, True)
            for step in (1, 3):
                mix(result, snare, start + step * beat, 0.065, True)
        else:
            for step in (1, 3):
                mix(result, hat, start + step * beat, 0.025, True)
    write(name, result, 0.7)


def whoosh(name, duration, rising=False, impact=False):
    result = empty(duration)
    filtered = 0.0
    phase = 0.0
    for i in range(len(result)):
        t = i / RATE
        fraction = t / duration
        noise = RNG.uniform(-1, 1)
        filtered += (noise - filtered) * (0.07 + fraction * 0.23)
        envelope = math.sin(math.pi * fraction) ** 1.3
        if impact:
            envelope = min(1, t / 0.002) * math.exp(-25 * t) * min(1, (duration - t) / 0.05)
            phase += TAU * (52 + 65 * math.exp(-20 * t)) / RATE
            result[i] = envelope * (0.75 * math.sin(phase) + 0.45 * filtered)
        elif rising:
            phase += TAU * (180 + 410 * fraction) / RATE
            result[i] = envelope * (0.2 * math.sin(phase) + 0.35 * filtered)
        else:
            result[i] = envelope * filtered * 0.8
    write(name, result, 0.8)


def chime(name, pitches, spacing, gain=0.3):
    result = empty(len(pitches) * spacing + 0.55)
    for index, pitch in enumerate(pitches):
        mix(result, note(pitch, 0.55, 'pluck'), index * spacing, gain)
    write(name, result, 0.7)


if __name__ == '__main__':
    music('menu', 96, False)
    music('arena', 120, True)
    chime('click', [79], 0.0, 0.26)
    chime('success', [74, 77, 81], 0.09)
    whoosh('jump', 0.24, rising=True)
    whoosh('land', 0.19, impact=True)
    whoosh('swing', 0.15)
    whoosh('hit', 0.25, impact=True)
    chime('blocked', [78, 67], 0.025, 0.4)
    chime('defeat', [62, 58, 50], 0.13, 0.4)
    chime('respawn', [62, 69, 74, 77], 0.11, 0.3)
