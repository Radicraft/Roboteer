"""Wave D: turn Godot --write-movie PNG sequences into short WebP clips for marshal.html.

    python3 docs/look/marshal/make_clips.py MOVIE_DIR LOG_FILE SCENARIO OUT.webp [max_s]

MOVIE_DIR holds clip00000000.png... written by `--write-movie MOVIE_DIR/clip.png
--fixed-fps 30`; LOG_FILE is the capture's stdout, whose `CLIP <scenario>_start N` and
`CLIP <scenario>_end N` lines give the frame range. The clip keeps the last `max_s` seconds
of the range, at 15 fps, 603 px wide.
"""
import glob
import os
import re
import sys

from PIL import Image

movie, log, scenario, out = sys.argv[1:5]
max_s = float(sys.argv[5]) if len(sys.argv) > 5 else 8.0
text = open(log).read()
start = int(re.search(r"CLIP %s_start (\d+)" % scenario, text).group(1))
end = int(re.search(r"CLIP %s_end (\d+)" % scenario, text).group(1))
files = sorted(glob.glob(os.path.join(movie, "clip*.png")))
end = min(end, len(files) - 1)
start = max(start, end - int(max_s * 30))
frames = []
for i in range(start, end + 1, 2):
    im = Image.open(files[i]).convert("RGB")
    frames.append(im.resize((603, int(603 * im.height / im.width)), Image.LANCZOS))
frames[0].save(out, save_all=True, append_images=frames[1:], duration=66, loop=0,
               quality=70, method=4)
print("%s: %d frames (%d..%d), %.0f KB" % (out, len(frames), start, end, os.path.getsize(out) / 1024))
