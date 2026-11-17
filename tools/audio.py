"""Re-synthesize TIC-80 sound from the register log written by tests/t_audio.lua.

The log holds the waveform RAM once ("WAVES <hex>") and, per frame, the four
sound registers exactly as the emulator computed them ("R" lines, grouped by
"SEG <name> <frames>"). This script reproduces TIC-80 1.3's synthesis
(src/core/sound.c: 32-step waveforms, 17-bit / short LFSR noise, volume x
stereo / 15 / 5 per channel) so the result can be listened to and inspected
without a window.

Outputs in <outdir>:
  <seg>.png           piano roll (per channel colour, brightness = loudness)
                      with a spectrogram underneath
  <seg>.mp3           music_*, jingle_*, mix_* previews
  sfx_tour.mp3        every sfx_* segment back to back (0.25 s gaps)
  report.txt          per-segment length, peak, RMS, audible duration

MP3s need `lame` and are boosted by --gain (default 3.5: TIC-80 caps each of
its 4 channels at 1/5 of full scale, so the raw output is quiet). --wav keeps
unboosted 16-bit 44.1 kHz WAVs of every segment instead of deleting them.

usage: audio.py <log> <outdir> [--wav] [--gain G]
"""
import os
import re
import subprocess
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw

SR = 44100
FPS = 60
CLOCKRATE = 255 << 13
RATE = CLOCKRATE * 2 // 32
COLORS = [(240, 200, 90), (120, 200, 255), (240, 110, 120), (170, 255, 140)]


def lfsr(fb, n=1 << 18):
    out = np.zeros(n, dtype=np.uint8)
    s = 1
    for i in range(n):
        out[i] = s & 1
        s = ((s & 1) * fb) ^ (s >> 1)
    return out


def parse(path):
    text = open(path, errors="replace").read()
    m = re.search(r"WAVES ([0-9a-f]{512})", text)
    raw = bytes.fromhex(m.group(1))
    waves = []
    for i in range(16):
        b = raw[i * 16:(i + 1) * 16]
        smp = []
        for x in b:
            smp += [x & 15, x >> 4]
        waves.append(smp)
    segs = []
    cur = None
    for line in text.split("\n"):
        if line.startswith("SEG "):
            _, name, _n = line.split()
            cur = {"name": name, "frames": []}
            segs.append(cur)
        elif line.startswith("R ") and cur is not None and len(line) >= 30:
            body = line[2:30]
            fr = []
            for c in range(4):
                h = body[c * 7:(c + 1) * 7]
                fr.append((int(h[0:3], 16), int(h[3], 16), int(h[4], 16), int(h[5], 16), int(h[6], 16)))
            cur["frames"].append(fr)
    return waves, segs


def synth(waves, frames, lf_long, lf_short):
    spf = SR // FPS
    n = len(frames) * spf
    out = np.zeros((n, 2), dtype=np.float64)
    noise_kind = []
    for w in waves:
        flat = all(v == w[0] for v in w)
        noise_kind.append(("long" if w[0] == 0 else "short") if flat and w[0] in (0, 15) else None)
    for c in range(4):
        phase = 0.0
        npos = 0.0
        for fi, fr in enumerate(frames):
            freq, vol, wi, left, right = fr[c]
            if vol == 0:
                continue
            a0 = fi * spf
            kind = noise_kind[wi]
            if kind:
                period = min(max(RATE // max(freq, 1) - 1, 10), 4096) if freq else 4096
                step = CLOCKRATE / period / SR
                idx = (npos + step * np.arange(spf)).astype(np.int64)
                npos += step * spf
                bits = (lf_long if kind == "long" else lf_short)[idx % len(lf_long)]
                sig = bits.astype(np.float64) * 15
            else:
                period = min(max(RATE // max(freq * 2, 1) - 1, 10), 4096) if freq else 4096
                step = CLOCKRATE / period / SR
                os_ = 4
                ph = phase + step * np.arange(spf * os_) / os_
                phase += step * spf
                smp = np.array(waves[wi], dtype=np.float64)[ph.astype(np.int64) % 32]
                sig = smp.reshape(spf, os_).mean(axis=1)
            amp = sig / 15.0 * vol / 15.0 / 5.0
            out[a0:a0 + spf, 0] += amp * left / 15.0
            out[a0:a0 + spf, 1] += amp * right / 15.0
    # DC blocker: subtract a ~40 ms moving average (TIC-80's blip buffer is AC coupled)
    k = 1764
    for ch in range(2):
        x = out[:, ch]
        cs = np.cumsum(np.concatenate([np.zeros(1), x]))
        lo = np.clip(np.arange(n) - k // 2, 0, n)
        hi = np.clip(np.arange(n) + k // 2, 0, n)
        avg = (cs[hi] - cs[lo]) / np.maximum(hi - lo, 1)
        out[:, ch] = x - avg
    return out


def write_wav(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def note_of(freq):
    if freq <= 0:
        return None
    return 12 * np.log2(freq / 16.3516)


def picture(path, frames, audio, title):
    nfr = len(frames)
    xs = max(1, 1200 // max(nfr, 1))
    width = min(max(nfr * xs, 200), 4000)
    sc = width / max(nfr, 1)
    lo_n, hi_n = 24, 96
    roll_h = (hi_n - lo_n) * 4
    spec_h = 200
    img = Image.new("RGB", (width, roll_h + spec_h + 16), (12, 12, 20))
    d = ImageDraw.Draw(img)
    for octv in range(2, 9):
        y = roll_h - (octv * 12 - lo_n) * 4
        d.line([(0, y), (width, y)], fill=(40, 40, 60))
        d.text((2, y - 10), "C%d" % octv, fill=(90, 90, 120))
    for fi, fr in enumerate(frames):
        x0 = int(fi * sc)
        x1 = max(x0 + 1, int((fi + 1) * sc))
        for c in range(4):
            freq, vol, wi, l, r = fr[c]
            if vol == 0:
                continue
            nn = note_of(freq)
            if nn is None:
                continue
            if wi in (0, 1):
                y = roll_h - 6 - c * 5
                col = tuple(int(v * vol / 15) for v in COLORS[c])
                d.rectangle([x0, y, x1, y + 3], fill=col)
                continue
            y = roll_h - int((nn - lo_n) * 4)
            col = tuple(int(v * (0.25 + 0.75 * vol / 15)) for v in COLORS[c])
            d.rectangle([x0, y - 1, x1, y + 1], fill=col)
    mono = audio.mean(axis=1)
    win = 2048
    hop = max(256, len(mono) // width)
    cols = []
    hann = np.hanning(win)
    for i in range(0, max(len(mono) - win, 1), hop):
        seg = mono[i:i + win]
        if len(seg) < win:
            seg = np.pad(seg, (0, win - len(seg)))
        cols.append(np.abs(np.fft.rfft(seg * hann)))
    if cols:
        S = np.array(cols).T
        freqs = np.fft.rfftfreq(win, 1 / SR)
        rows = np.geomspace(50, 8000, spec_h)
        idx = np.searchsorted(freqs, rows)
        S = S[np.clip(idx, 0, len(freqs) - 1)]
        S = 20 * np.log10(S + 1e-6)
        S = np.clip((S + 10) / 60, 0, 1)
        spec = Image.fromarray((S[::-1] * 255).astype(np.uint8), "L").resize((width, spec_h))
        img.paste(Image.merge("RGB", (spec, spec.point(lambda v: v * 0.7), spec.point(lambda v: v * 0.4))), (0, roll_h + 16))
    d.text((4, roll_h + 2), title, fill=(220, 220, 220))
    img.save(path)


def to_mp3(wav, gain):
    try:
        subprocess.run(["lame", "--quiet", "--scale", str(gain), "-V", "4", wav, wav[:-4] + ".mp3"], check=False)
    except FileNotFoundError:
        print("lame not found: no mp3 for", wav)


def main():
    log, outdir = sys.argv[1], sys.argv[2]
    keep = "--wav" in sys.argv
    gain = float(sys.argv[sys.argv.index("--gain") + 1]) if "--gain" in sys.argv else 3.5
    os.makedirs(outdir, exist_ok=True)
    waves, segs = parse(log)
    lf_long = lfsr(0x12000)
    lf_short = lfsr(0x14, 1 << 18)
    rep = []
    tour = []
    for s in segs:
        fr = s["frames"]
        if not fr:
            continue
        a = synth(waves, fr, lf_long, lf_short)
        wav = os.path.join(outdir, s["name"] + ".wav")
        write_wav(wav, a)
        picture(os.path.join(outdir, s["name"] + ".png"), fr, a, "%s  %.1fs" % (s["name"], len(fr) / FPS))
        last = max((i for i, f in enumerate(fr) if any(ch[1] for ch in f)), default=-1)
        first = min((i for i, f in enumerate(fr) if any(ch[1] for ch in f)), default=-1)
        peak = float(np.abs(a).max())
        rms = float(np.sqrt((a ** 2).mean()))
        rep.append("%-28s %6.2fs  sound %4d-%4d frames  peak %.2f  rms %.3f" % (s["name"], len(fr) / FPS, first, last, peak, rms))
        if s["name"].startswith("sfx_") and last >= 0:
            tour.append(a[:(last + 6) * (SR // FPS)])
            tour.append(np.zeros((SR // 4, 2)))
        if s["name"].startswith(("music_", "jingle_", "mix_")):
            to_mp3(wav, gain)
        if not keep:
            os.remove(wav)
    if tour:
        wav = os.path.join(outdir, "sfx_tour.wav")
        write_wav(wav, np.concatenate(tour))
        to_mp3(wav, gain)
        if not keep:
            os.remove(wav)
    open(os.path.join(outdir, "report.txt"), "w").write("\n".join(rep) + "\n")
    print("\n".join(rep))


if __name__ == "__main__":
    main()
