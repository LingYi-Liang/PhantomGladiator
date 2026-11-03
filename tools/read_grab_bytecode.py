"""Read only the reported live grab UFunction Script arrays; never write process memory.

Raw game bytecode belongs in an ignored external evidence directory, not the repo.
Offsets come from this build's checked GameConfig/MemberVariableLayout.ini.
"""
import argparse
import csv
import ctypes
from ctypes import wintypes
import hashlib
import json
from pathlib import Path
import re
import struct

EXPECTED_EXE=Path(r'C:\Program Files (x86)\Steam\steamapps\common\PBZ\platform\steam\PBZ.exe')

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--pid',required=True,type=int)
    parser.add_argument('--report',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    repo=Path(__file__).resolve().parents[1]
    output=args.output.resolve()
    if output.is_relative_to(repo):raise SystemExit('Game bytecode output must stay outside the source repository')
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.OpenProcess.argtypes=[wintypes.DWORD,wintypes.BOOL,wintypes.DWORD]
    kernel.OpenProcess.restype=wintypes.HANDLE
    kernel.ReadProcessMemory.argtypes=[wintypes.HANDLE,ctypes.c_void_p,ctypes.c_void_p,ctypes.c_size_t,ctypes.POINTER(ctypes.c_size_t)]
    kernel.ReadProcessMemory.restype=wintypes.BOOL
    kernel.QueryFullProcessImageNameW.argtypes=[wintypes.HANDLE,wintypes.DWORD,wintypes.LPWSTR,ctypes.POINTER(wintypes.DWORD)]
    kernel.CloseHandle.argtypes=[wintypes.HANDLE]
    handle=kernel.OpenProcess(0x1000|0x0010,False,args.pid) # QUERY_LIMITED_INFORMATION | VM_READ only
    if not handle:raise ctypes.WinError(ctypes.get_last_error())
    try:
        size=wintypes.DWORD(32768);image=ctypes.create_unicode_buffer(size.value)
        if not kernel.QueryFullProcessImageNameW(handle,0,image,ctypes.byref(size)):raise ctypes.WinError(ctypes.get_last_error())
        if Path(image.value).resolve()!=EXPECTED_EXE.resolve():raise SystemExit('PID is not the identified game executable')
        def read(address,count):
            if not 0x10000<=address<2**48 or not 0<count<=512*1024:raise ValueError('Out-of-range targeted read')
            result=ctypes.create_string_buffer(count);done=ctypes.c_size_t()
            if not kernel.ReadProcessMemory(handle,ctypes.c_void_p(address),result,count,ctypes.byref(done)) or done.value!=count:
                raise ctypes.WinError(ctypes.get_last_error())
            return result.raw
        with args.report.open(encoding='utf-8-sig',newline='') as file:rows=list(csv.DictReader(file,delimiter='\t'))
        functions=[r for r in rows if r['kind']=='function' and r['address']]
        symbols={int(r['address']):r['name'] for r in rows if r['address'] and r['kind'] in ['function','class','property']}
        output.mkdir(parents=True,exist_ok=True)
        findings=[]
        for item in functions:
            if not item['label'].startswith('/SGameExecution/'):continue
            address=int(item['address'])
            expected=int(item['value'].removeprefix('flags='))
            flags=struct.unpack('<I',read(address+0x100,4))[0]
            if flags!=expected:raise SystemExit('Function flags changed; refresh the in-game report before reading')
            pointer,num,capacity=struct.unpack('<Qii',read(address+0xb0,16))
            if not 0<num<=capacity<=512*1024:raise SystemExit('Invalid or empty Script array; do not guess another offset')
            data=read(pointer,num)
            # Re-read the header/bytes to reject a concurrently replaced script buffer.
            if read(address+0xb0,16)!=struct.pack('<Qii',pointer,num,capacity) or read(pointer,num)!=data:
                raise SystemExit('Script changed during read; no mutation or retry performed')
            name=re.sub(r'[^A-Za-z0-9_]+','_',item['label'].rsplit('/',1)[-1])
            (output/(name+'.bin')).write_bytes(data)
            refs=[]
            for symbol_address,symbol in symbols.items():
                needle=struct.pack('<Q',symbol_address);offset=data.find(needle)
                while offset>=0:
                    refs.append({'offset':offset,'symbol':symbol,'address':symbol_address})
                    offset=data.find(needle,offset+1)
            finding={'function':item['label'],'address':address,'script_address':pointer,'size':num,
                'sha256':hashlib.sha256(data).hexdigest(),'references':sorted(refs,key=lambda r:r['offset'])}
            findings.append(finding)
            print(json.dumps(finding,ensure_ascii=False))
        (output/'script-index.json').write_text(json.dumps(findings,ensure_ascii=False,indent=2),encoding='utf-8')
    finally:kernel.CloseHandle(handle)

if __name__=='__main__':main()
