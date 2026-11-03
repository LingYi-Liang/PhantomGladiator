"""Minimal minidump parser: exception code/address + module mapping.
Usage: python -I parse_dump.py <dumpfile>
"""
import struct
import sys

data = open(sys.argv[1], "rb").read()
assert data[:4] == b"MDMP", "not a minidump"
num_streams, dir_rva = struct.unpack_from("<II", data, 8)

streams = {}
for i in range(num_streams):
    stype, size, rva = struct.unpack_from("<III", data, dir_rva + i * 12)
    streams[stype] = (size, rva)

# ModuleListStream = 4
modules = []
if 4 in streams:
    _, rva = streams[4]
    (count,) = struct.unpack_from("<I", data, rva)
    off = rva + 4
    for i in range(count):
        base, size_img = struct.unpack_from("<QI", data, off)
        (name_rva,) = struct.unpack_from("<I", data, off + 0x14)
        (name_len,) = struct.unpack_from("<I", data, name_rva)
        name = data[name_rva + 4:name_rva + 4 + name_len].decode("utf-16-le")
        modules.append((base, size_img, name))
        off += 108  # sizeof(MINIDUMP_MODULE)

def locate(addr):
    for base, size_img, name in modules:
        if base <= addr < base + size_img:
            return f"{name}+0x{addr - base:X}"
    return "unknown module"

# ExceptionStream = 6
if 6 in streams:
    _, rva = streams[6]
    tid, = struct.unpack_from("<I", data, rva)
    code, flags = struct.unpack_from("<II", data, rva + 8)
    addr, = struct.unpack_from("<Q", data, rva + 8 + 16)
    nparams, = struct.unpack_from("<I", data, rva + 8 + 24)
    params = struct.unpack_from(f"<{max(nparams,1)}Q", data, rva + 8 + 32)
    print(f"thread: {tid}")
    print(f"exception code: 0x{code:08X}")
    print(f"exception addr: 0x{addr:X}  ({locate(addr)})")
    if code == 0xC0000005 and nparams >= 2:
        kind = {0: "read", 1: "write", 8: "execute"}.get(params[0], params[0])
        print(f"access violation: {kind} at 0x{params[1]:X} ({locate(params[1])})")
else:
    print("no exception stream")
