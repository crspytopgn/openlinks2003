"""encode.py in.png out.(webp|jpg) quality: re-encode a rendered PNG."""
import sys

from PIL import Image

src, dst, quality = sys.argv[1], sys.argv[2], int(sys.argv[3])
img = Image.open(src)
if dst.endswith(".jpg"):
	img.convert("RGB").save(dst, quality=quality, optimize=True, progressive=True)
else:
	img.save(dst, quality=quality, method=6)
