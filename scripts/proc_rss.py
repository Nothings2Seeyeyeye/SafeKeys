#!/usr/bin/env python3
"""读取 macOS 进程的真实内存占用与 RunLoop 唤醒频率。

沙箱环境下 ps / top 常被禁用，这里直接调 libproc 的 proc_pid_rusage，无需任何权限。

用法:
    proc_rss.py <pid>              # 单次快照
    proc_rss.py <pid> --watch 30   # 观察 30 秒，报告前后对比与每秒唤醒次数

注意: 脚本结束用 os._exit() 而非正常退出 —— libproc 的 ctypes 绑定在解释器
      清理阶段偶发 SIGSEGV，与测量本身无关，直接跳过清理即可。
"""
import ctypes
import ctypes.util
import os
import sys
import time

lib = ctypes.CDLL(ctypes.util.find_library("libproc") or "/usr/lib/libproc.dylib")


class rusage_info_v4(ctypes.Structure):
    _fields_ = [
        ("ri_uuid", ctypes.c_uint8 * 16),
        ("ri_user_time", ctypes.c_uint64),
        ("ri_system_time", ctypes.c_uint64),
        ("ri_pkg_idle_wkups", ctypes.c_uint64),
        ("ri_interrupt_wkups", ctypes.c_uint64),
        ("ri_pageins", ctypes.c_uint64),
        ("ri_wired_size", ctypes.c_uint64),
        ("ri_resident_size", ctypes.c_uint64),
        ("ri_phys_footprint", ctypes.c_uint64),
    ]


def memory_of(pid: int) -> tuple[float, float, int]:
    """返回 (RSS MB, 物理占用 MB, 中断唤醒累计次数)"""
    buf = rusage_info_v4()
    if lib.proc_pid_rusage(pid, 4, ctypes.byref(buf)) != 0:
        raise RuntimeError(f"proc_pid_rusage 失败 (pid={pid} 可能已退出)")
    return (
        buf.ri_resident_size / 1048576,
        buf.ri_phys_footprint / 1048576,
        buf.ri_interrupt_wkups,
    )


def main() -> None:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return

    pid = int(args[0])
    watch = None
    if "--watch" in args:
        watch = float(args[args.index("--watch") + 1])

    rss, footprint, wkups = memory_of(pid)
    print(f"pid={pid}  RSS={rss:.1f}MB  footprint={footprint:.1f}MB  唤醒累计={wkups}")

    if watch:
        time.sleep(watch)
        try:
            rss2, footprint2, wkups2 = memory_of(pid)
        except RuntimeError as exc:
            print(f"观察期结束: {exc}")
            return
        print(f"  +{watch:.0f}s后 RSS={rss2:.1f}MB  footprint={footprint2:.1f}MB")
        print(f"  内存增量: {footprint2 - footprint:+.2f}MB")
        print(f"  唤醒频率: {(wkups2 - wkups) / watch:.1f} 次/秒")


if __name__ == "__main__":
    main()
    os._exit(0)
