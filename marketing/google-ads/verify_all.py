"""End-to-end verification of every video deliverable.

Decodes each file in full (a truncated MP4 passes ffprobe but fails this),
checks the canvas, the runtime, and that the audio actually carries signal.
"""
import os, subprocess
import build_videos as bv

HERE = os.path.dirname(os.path.abspath(__file__))
EXPECT = {"16x9": (1920, 1080), "9x16": (1080, 1920), "1x1": (1080, 1080)}


def decodes(p):
    r = subprocess.run(["ffmpeg", "-v", "error", "-i", p, "-f", "null", "-"],
                       capture_output=True, text=True)
    return r.returncode == 0 and not r.stderr.strip()


def peak(p):
    r = subprocess.run(["ffmpeg", "-i", p, "-af", "volumedetect", "-f", "null", "-"],
                       capture_output=True, text=True)
    for line in r.stderr.splitlines():
        if "max_volume:" in line:
            return float(line.split("max_volume:")[1].strip().split()[0])
    return None


def dims(p):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                          "-show_entries", "stream=width,height",
                          "-show_entries", "format=duration",
                          "-of", "csv=p=0", p], capture_output=True, text=True).stdout.split()
    return out


def main():
    problems, n = [], 0
    for cid in bv.CONCEPTS:
        for total in bv.DURATIONS:
            for ratio in bv.RATIOS:
                p = os.path.join(bv.OUT, f"concept-{cid}", f"{total}s-{ratio}.mp4")
                rel = os.path.relpath(p, HERE)
                n += 1
                if not os.path.exists(p):
                    problems.append(f"MISSING {rel}")
                    continue
                if not decodes(p):
                    problems.append(f"BROKEN (does not decode) {rel}")
                    continue
                info = dims(p)
                if info:
                    wh = info[0].split(",")
                    if (int(wh[0]), int(wh[1])) != EXPECT[ratio]:
                        problems.append(f"SIZE {rel} is {wh[0]}x{wh[1]}")
                    dur = float(info[-1])
                    if abs(dur - total) > 0.35:
                        problems.append(f"DURATION {rel} is {dur:.2f}s, expected {total}")
                pk = peak(p)
                if pk is None:
                    problems.append(f"NO AUDIO {rel}")
                elif pk <= -30:
                    problems.append(f"SILENT {rel} (peak {pk} dB)")
    print(f"verified {n} videos, {len(problems)} problem(s)")
    for x in problems:
        print("  !", x)
    return len(problems)


if __name__ == "__main__":
    raise SystemExit(1 if main() else 0)
