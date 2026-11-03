"""Scan a running process's main module for UE4SS AOB signature candidates.

Usage: python -I aob_scan.py <process_name> <configs_dir>
Parses every GUObjectArray.lua / GNatives.lua under configs_dir, extracts the
Register() pattern, and reports how many times each pattern matches in the
target process's main module memory. A usable signature matches exactly once.
"""
import ctypes
import ctypes.wintypes as wt
import os
import re
import sys

k32 = ctypes.windll.kernel32
psapi = ctypes.windll.psapi

k32.OpenProcess.restype = wt.HANDLE
k32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
k32.VirtualQueryEx.restype = ctypes.c_size_t
k32.VirtualQueryEx.argtypes = [wt.HANDLE, ctypes.c_void_p,
                               ctypes.c_void_p, ctypes.c_size_t]
k32.ReadProcessMemory.restype = wt.BOOL
k32.ReadProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                  ctypes.c_size_t, ctypes.c_void_p]
psapi.EnumProcessModulesEx.restype = wt.BOOL
psapi.EnumProcessModulesEx.argtypes = [wt.HANDLE, ctypes.c_void_p, wt.DWORD,
                                       ctypes.c_void_p, wt.DWORD]
psapi.GetModuleFileNameExW.restype = wt.DWORD
psapi.GetModuleFileNameExW.argtypes = [wt.HANDLE, ctypes.c_void_p,
                                       ctypes.c_wchar_p, wt.DWORD]
psapi.GetModuleInformation.restype = wt.BOOL
psapi.GetModuleInformation.argtypes = [wt.HANDLE, ctypes.c_void_p,
                                       ctypes.c_void_p, wt.DWORD]

PROCESS_QUERY_INFORMATION = 0x0400
PROCESS_VM_READ = 0x0010
MEM_COMMIT = 0x1000
PAGE_GUARD = 0x100
READABLE = {0x02, 0x04, 0x08, 0x20, 0x40, 0x80}


class MODULEINFO(ctypes.Structure):
    _fields_ = [("lpBaseOfDll", ctypes.c_void_p),
                ("SizeOfImage", wt.DWORD),
                ("EntryPoint", ctypes.c_void_p)]


class MBI(ctypes.Structure):
    _fields_ = [("BaseAddress", ctypes.c_void_p),
                ("AllocationBase", ctypes.c_void_p),
                ("AllocationProtect", wt.DWORD),
                ("PartitionId", wt.WORD),
                ("RegionSize", ctypes.c_size_t),
                ("State", wt.DWORD),
                ("Protect", wt.DWORD),
                ("Type", wt.DWORD)]


def find_pid(name):
    import subprocess
    out = subprocess.check_output(
        ["tasklist", "/FO", "CSV", "/FI", f"IMAGENAME eq {name}"],
        text=True, errors="replace")
    for line in out.splitlines()[1:]:
        parts = [p.strip('"') for p in line.split('","')]
        if len(parts) >= 2 and parts[0].lower() == name.lower():
            return int(parts[1])
    return None


def parse_pattern(lua_path):
    text = open(lua_path, encoding="utf-8", errors="replace").read()
    m = re.search(r'return\s*"([0-9A-Fa-f?\s]+)"', text)
    if not m:
        return None
    toks = m.group(1).split()
    pat, mask = bytearray(), bytearray()
    for t in toks:
        if t in ("?", "??"):
            pat.append(0)
            mask.append(0)
        else:
            pat.append(int(t, 16))
            mask.append(1)
    return bytes(pat), bytes(mask)


def longest_fixed_run(pat, mask):
    best_s = best_len = 0
    s = None
    for i, mbit in enumerate(mask):
        if mbit and s is None:
            s = i
        if (not mbit or i == len(mask) - 1) and s is not None:
            end = i + 1 if mbit else i
            if end - s > best_len:
                best_s, best_len = s, end - s
            s = None
    return best_s, pat[best_s:best_s + best_len]


def verify(buf, pos, pat, mask):
    if pos < 0 or pos + len(pat) > len(buf):
        return False
    for i in range(len(pat)):
        if mask[i] and buf[pos + i] != pat[i]:
            return False
    return True


def scan_buffer(buf, base_va, pat, mask, hits, cap):
    anchor_off, anchor = longest_fixed_run(pat, mask)
    i = buf.find(anchor)
    while i != -1 and len(hits) < cap:
        start = i - anchor_off
        if verify(buf, start, pat, mask):
            hits.append(base_va + start)
        i = buf.find(anchor, i + 1)


def main():
    proc_name, configs_dir = sys.argv[1], sys.argv[2]
    pid = int(sys.argv[3]) if len(sys.argv) > 3 else find_pid(proc_name)
    if not pid:
        print(f"PROCESS NOT RUNNING: {proc_name}")
        sys.exit(2)
    h = k32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
    if not h:
        print(f"OpenProcess failed: {ctypes.GetLastError()}")
        sys.exit(1)

    mod = MODULEINFO()
    hmod = (ctypes.c_void_p * 1024)()
    needed = wt.DWORD()
    # LIST_MODULES_64BIT = 0x02
    psapi.EnumProcessModulesEx(h, hmod, ctypes.sizeof(hmod),
                               ctypes.byref(needed), 0x02)
    namebuf = ctypes.create_unicode_buffer(260)
    base = size = None
    for i in range(needed.value // ctypes.sizeof(ctypes.c_void_p)):
        psapi.GetModuleFileNameExW(h, hmod[i], namebuf, 260)
        if os.path.basename(namebuf.value).lower() == proc_name.lower():
            psapi.GetModuleInformation(h, hmod[i], ctypes.byref(mod),
                                       ctypes.sizeof(mod))
            base, size = mod.lpBaseOfDll, mod.SizeOfImage
            break
    if base is None:
        print("main module not found")
        sys.exit(1)
    print(f"pid={pid} module base=0x{base:X} size=0x{size:X}")

    sigs = []
    for root, _, files in os.walk(configs_dir):
        for f in files:
            if f.lower() in ("guobjectarray.lua", "gnatives.lua"):
                p = os.path.join(root, f)
                parsed = parse_pattern(p)
                if parsed:
                    rel = os.path.relpath(p, configs_dir)
                    sigs.append((rel, parsed[0], parsed[1]))
    print(f"{len(sigs)} candidate signatures")

    # Read the whole module image once, region by region.
    image = bytearray(size)
    have = bytearray(size)
    addr = base
    end = base + size
    mbi = MBI()
    while addr < end:
        if not k32.VirtualQueryEx(h, ctypes.c_void_p(addr),
                                  ctypes.byref(mbi), ctypes.sizeof(mbi)):
            break
        rbase = mbi.BaseAddress or 0
        rsize = mbi.RegionSize
        if (mbi.State == MEM_COMMIT and not (mbi.Protect & PAGE_GUARD)
                and (mbi.Protect & 0xFF) in READABLE):
            take = min(rbase + rsize, end) - max(rbase, base)
            off = max(rbase, base) - base
            buf = ctypes.create_string_buffer(take)
            got = ctypes.c_size_t()
            if k32.ReadProcessMemory(h, ctypes.c_void_p(base + off), buf,
                                     take, ctypes.byref(got)):
                image[off:off + got.value] = buf.raw[:got.value]
                for j in range(got.value):
                    have[off + j] = 1
        addr = rbase + rsize
    readable = sum(have)
    print(f"read {readable / 1048576:.1f} MiB of module memory")

    image = bytes(image)
    for rel, pat, mask in sigs:
        hits = []
        scan_buffer(image, base, pat, mask, hits, cap=5)
        status = {0: "no match", 1: "UNIQUE"}.get(len(hits),
                 f"{len(hits)}+ matches")
        addrs = " ".join(f"0x{a:X}" for a in hits[:3])
        print(f"[{status:>10}] {rel}  {addrs}")


if __name__ == "__main__":
    main()
