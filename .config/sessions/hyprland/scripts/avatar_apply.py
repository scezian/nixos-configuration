#!/usr/bin/env python3
"""Render a cropped square avatar and install it as the SDDM face icon.

Usage:
  avatar_apply.py <image> <zoom> <ox> <oy>   crop (same math as the popup preview) and install
  avatar_apply.py --remove                   delete the installed avatar

Installing goes through pkexec (needs a polkit agent running).
"""
import getpass
import os
import shutil
import subprocess
import sys
import tempfile

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PyQt6.QtCore import QRectF, Qt
from PyQt6.QtGui import QGuiApplication, QImage, QImageReader, QPainter

USER = getpass.getuser()
FACE_DIR = "/usr/share/sddm/faces"
FACE_PATH = f"{FACE_DIR}/{USER}.face.icon"
SIZE = 256


def load(path):
    reader = QImageReader(path)
    reader.setAutoTransform(True)
    img = reader.read()
    if img.isNull():
        raise RuntimeError(f"Couldn't read image: {reader.errorString()}")
    return img


def render(img, zoom, ox, oy, size=SIZE):
    w, h = img.width(), img.height()
    m = min(w, h)
    zoom = max(1.0, zoom)
    lim_x = max(0.0, (zoom * w / m - 1) / 2)
    lim_y = max(0.0, (zoom * h / m - 1) / 2)
    ox = max(-lim_x, min(lim_x, ox))
    oy = max(-lim_y, min(lim_y, oy))
    scale = zoom * size / m
    dw, dh = w * scale, h * scale
    x = size / 2 + ox * size - dw / 2
    y = size / 2 + oy * size - dh / 2
    out = QImage(size, size, QImage.Format.Format_ARGB32)
    out.fill(Qt.GlobalColor.transparent)
    p = QPainter(out)
    p.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform)
    p.drawImage(QRectF(x, y, dw, dh), img)
    p.end()
    return out


def run_root(cmd):
    try:
        r = subprocess.run(["pkexec", *cmd], capture_output=True, text=True, timeout=45)
    except FileNotFoundError:
        sys.exit("pkexec not found. Install polkit and start a polkit agent.")
    except subprocess.TimeoutExpired:
        sys.exit("Authentication timed out. Make the faces folder writable to skip it.")
    if r.returncode != 0:
        sys.exit(f"Failed (exit {r.returncode}). Is a polkit agent running? {r.stderr.strip()}")


def main():
    app = QGuiApplication(sys.argv)  # noqa: F841 (needed for image plugins)
    if len(sys.argv) == 2 and sys.argv[1] == "--remove":
        if os.access(FACE_DIR, os.W_OK):
            if os.path.exists(FACE_PATH):
                os.remove(FACE_PATH)
        else:
            run_root(["rm", "-f", FACE_PATH])
        return
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    src, zoom, ox, oy = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
    img = load(src)
    fd, tmp = tempfile.mkstemp(suffix=".png")
    os.close(fd)
    try:
        if not render(img, zoom, ox, oy).save(tmp, "PNG"):
            sys.exit("Couldn't write the temporary image.")
        if os.access(FACE_DIR, os.W_OK):
            part = FACE_PATH + ".part"
            shutil.copyfile(tmp, part)
            os.chmod(part, 0o644)
            os.replace(part, FACE_PATH)
        else:
            run_root(["install", "-D", "-m", "644", tmp, FACE_PATH])
    finally:
        os.unlink(tmp)


if __name__ == "__main__":
    main()
