"""Dump process memory at an address: python -I dump_mem.py <pid> <hex_addr> <size>"""
import ctypes
import ctypes.wintypes as wt
import sys

k32 = ctypes.windll.kernel32
k32.OpenProcess.restype = wt.HANDLE
k32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
k32.ReadProcessMemory.restype = wt.BOOL
k32.ReadProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                  ctypes.c_size_t, ctypes.c_void_p]

pid = int(sys.argv[1])
addr = int(sys.argv[2], 16)
size = int(sys.argv[3], 0)

h = k32.OpenProcess(0x0410, False, pid)
buf = ctypes.create_string_buffer(size)
got = ctypes.c_size_t()
if not k32.ReadProcessMemory(h, ctypes.c_void_p(addr), buf, size,
                             ctypes.byref(got)):
    print(f"read failed at 0x{addr:X}: err={ctypes.GetLastError()}")
    sys.exit(1)
data = buf.raw[:got.value]
for off in range(0, len(data), 16):
    chunk = data[off:off + 16]
    qs = " ".join(f"{int.from_bytes(chunk[i:i+8], 'little'):016X}"
                  for i in range(0, len(chunk), 8))
    ds = " ".join(f"{int.from_bytes(chunk[i:i+4], 'little'):>10}"
                  for i in range(0, len(chunk), 4))
    print(f"+{off:04X}  {qs}   | {ds}")
