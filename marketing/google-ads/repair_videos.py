"""Find creatives that do not fully decode and rebuild them.

Runs that were interrupted mid-write leave truncated MP4s behind. They look
present on disk, ffprobe half-reads them, and the audio pass then dies on the
first one it meets. This decodes every deliverable end to end and rebuilds
whatever fails.
"""
import os, subprocess, sys
import build_videos as bv

HERE = os.path.dirname(os.path.abspath(__file__))


def decodes(path):
    r = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "null", "-"],
                       capture_output=True, text=True)
    return r.returncode == 0 and not r.stderr.strip()


def main():
    broken = []
    for cid in bv.CONCEPTS:
        for total, n in bv.DURATIONS.items():
            for ratio in bv.RATIOS:
                p = os.path.join(bv.OUT, f"concept-{cid}", f"{total}s-{ratio}.mp4")
                if not os.path.exists(p) or not decodes(p):
                    broken.append((cid, total, n, ratio, p))
    print(f"{len(broken)} file(s) need rebuilding")
    for cid, total, n, ratio, p in broken:
        print(f"  rebuilding {os.path.relpath(p, HERE)}")
        bv.build(cid, total, ratio, bv.CONCEPTS[cid]["beats"][:n], p)
    print("repair complete")


if __name__ == "__main__":
    main()
