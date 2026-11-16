"""Bounded child processes for optional local audio; never loaded by the game."""
import ctypes
from ctypes import wintypes
import os
import subprocess
import threading


class Child:
    def __init__(self, args, *, stdin=None, stdout=None, stderr=None, memory=512 << 20):
        if os.name != 'nt':
            raise OSError('本地音频仅支持 Windows')
        self._close_lock=threading.Lock();self._closed=False
        k = ctypes.WinDLL('kernel32', use_last_error=True)
        class Basic(ctypes.Structure):
            _fields_ = [('user', ctypes.c_int64), ('job', ctypes.c_int64), ('flags', wintypes.DWORD),
                        ('min', ctypes.c_size_t), ('max', ctypes.c_size_t), ('active', wintypes.DWORD),
                        ('affinity', ctypes.c_size_t), ('priority', wintypes.DWORD), ('scheduling', wintypes.DWORD)]
        class IO(ctypes.Structure):
            _fields_ = [(x, ctypes.c_uint64) for x in ('ro', 'wo', 'oo', 'rt', 'wt', 'ot')]
        class Limits(ctypes.Structure):
            _fields_ = [('basic', Basic), ('io', IO), ('processMemory', ctypes.c_size_t),
                        ('jobMemory', ctypes.c_size_t), ('peakProcess', ctypes.c_size_t), ('peakJob', ctypes.c_size_t)]
        k.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR];k.CreateJobObjectW.restype = wintypes.HANDLE
        k.SetInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
        k.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
        k.CloseHandle.argtypes = [wintypes.HANDLE]
        self.k, self.job, self.process = k, k.CreateJobObjectW(None, None), None
        try:
            limits = Limits();limits.basic.flags = 0x2000 | 0x100 | 0x8 | 0x20
            limits.basic.active = 1;limits.basic.priority = 0x4000;limits.processMemory = memory
            if not self.job or not k.SetInformationJobObject(self.job, 9, ctypes.byref(limits), ctypes.sizeof(limits)):
                raise OSError('音频进程隔离不可用，已跳过')
            self.process = subprocess.Popen(args, stdin=stdin, stdout=stdout, stderr=stderr,
                                            creationflags=subprocess.CREATE_NO_WINDOW | subprocess.BELOW_NORMAL_PRIORITY_CLASS,
                                            close_fds=True)
            if not k.AssignProcessToJobObject(self.job, int(self.process._handle)):
                raise OSError('音频进程隔离未确认，已跳过')
        except BaseException:
            self.close();raise

    def close(self):
        with self._close_lock:
            if self._closed:return
            self._closed=True;job=self.job;self.job=None;process=self.process
        if job:self.k.CloseHandle(job)
        if process:
            if process.poll() is None:
                try:process.kill()
                except OSError:pass
            try:process.wait(timeout=1)
            except (OSError,subprocess.TimeoutExpired):pass
            for pipe in (process.stdin,process.stdout,process.stderr):
                if pipe:
                    try:pipe.close()
                    except OSError:pass
