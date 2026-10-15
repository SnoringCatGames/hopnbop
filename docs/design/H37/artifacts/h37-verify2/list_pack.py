"""H37 phase 2b (h37-verify2, item 4, LG-1): list a Godot 4 pack's files.

Usage: python -I list_pack.py <file.pck|file.zip> [<file> ...]

For each pack prints the entry count, every entry under legal/, every .txt
entry, and whether legal_doc_screen.gd (the reader) is inside. Reads the
PCK directory (format 2 or 3, file_access_pack.cpp) or a zip's listing.
"""

import struct
import sys
import zipfile

PACK_DIR_ENCRYPTED = 1
PACK_REL_FILEBASE = 2


def pck_entries(path):
    with open(path, "rb") as f:
        data = f.read()
    start = data.find(b"GDPC")
    if start < 0:
        raise ValueError("no GDPC header")
    (version, major, minor, patch, flags, file_base) = struct.unpack_from(
        "<IIIIIQ", data, start + 4)
    pos = start + 4 + 4 * 5 + 8
    if version >= 3:
        (dir_offset,) = struct.unpack_from("<Q", data, pos)
        pos += 8
        pos += 16 * 4
        if flags & PACK_REL_FILEBASE:
            dir_offset += start
        pos = dir_offset
    else:
        pos += 16 * 4
    if flags & PACK_DIR_ENCRYPTED:
        raise ValueError("directory is encrypted")
    (count,) = struct.unpack_from("<I", data, pos)
    pos += 4
    names = []
    for _ in range(count):
        (length,) = struct.unpack_from("<I", data, pos)
        pos += 4
        name = data[pos:pos + length].rstrip(b"\0").decode("utf-8")
        pos += length
        pos += 8 + 8 + 16 + 4  # offset, size, md5, flags
        names.append(name)
    header = "PCK v%d, Godot %d.%d.%d" % (version, major, minor, patch)
    return header, names


def zip_entries(path):
    with zipfile.ZipFile(path) as z:
        return "zip", z.namelist()


def main():
    for path in sys.argv[1:]:
        if path.endswith(".zip"):
            header, names = zip_entries(path)
        else:
            header, names = pck_entries(path)
        norm = [n.replace("res://", "") for n in names]
        legal = [n for n in norm if n.startswith("legal/")]
        txt = [n for n in norm if n.endswith(".txt")]
        reader = [n for n in norm if "legal_doc_screen" in n]
        print("%s: %s, %d entries" % (path, header, len(norm)))
        print("  legal/ entries: %s" % (legal or "none"))
        print("  .txt entries: %s" % (txt or "none"))
        print("  legal_doc_screen: %s" % (reader or "none"))


if __name__ == "__main__":
    main()
