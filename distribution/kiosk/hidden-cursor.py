#!/usr/bin/env python3
"""Writes the cursor theme puffer-hidden into the folder given as argument: one transparent Xcursor image of one pixel, under every name that cage, GTK and Flutter ask for, so the pointer never shows on a touchscreen."""

import pathlib
import struct
import sys

IMAGE = 0xFFFD0002
NAMES = """default left_ptr arrow top_left_arrow pointer hand hand1 hand2 pointing_hand
text xterm ibeam vertical-text grab grabbing openhand closedhand dnd-move fleur move all-scroll
not-allowed no-drop crossed_circle forbidden wait watch progress left_ptr_watch half-busy
help question_arrow whats_this crosshair cross tcross context-menu cell copy alias dnd-copy dnd-link
col-resize row-resize sb_h_double_arrow sb_v_double_arrow ew-resize ns-resize nesw-resize nwse-resize
size_hor size_ver size_bdiag size_fdiag n-resize s-resize e-resize w-resize ne-resize nw-resize
se-resize sw-resize top_side bottom_side left_side right_side top_left_corner top_right_corner
bottom_left_corner bottom_right_corner zoom-in zoom-out""".split()


def cursor():
    # The file header and one table entry, then one image chunk: width, height, hot spot and delay, then one transparent ARGB pixel.
    header = struct.pack("<4sIII", b"Xcur", 16, 0x10000, 1)
    toc = struct.pack("<III", IMAGE, 1, 16 + 12)
    image = struct.pack("<IIIIIIIII", 36, IMAGE, 1, 1, 1, 1, 0, 0, 0) + struct.pack("<I", 0)
    return header + toc + image


def main():
    theme = pathlib.Path(sys.argv[1])
    cursors = theme / "cursors"
    cursors.mkdir(parents=True, exist_ok=True)
    (theme / "index.theme").write_text("[Icon Theme]\nName=puffer-hidden\nComment=A transparent pointer for the Puffer kiosk\n")
    (cursors / "default").write_bytes(cursor())
    for name in NAMES:
        if name != "default":
            link = cursors / name
            link.unlink(missing_ok=True)
            link.symlink_to("default")


if __name__ == "__main__":
    main()
