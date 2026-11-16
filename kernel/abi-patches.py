#!/usr/bin/env python3
"""Apply Droidspaces' kABI-preserving SYSVIPC / POSIX_MQUEUE changes to the Samsung 5.10.81 tree.
Same technique as Documentation/resources/kernel-patches/GKI/below-kernel-6.12 (variant 1_2_3 and 002),
re-anchored because this older tree's context lines differ. Idempotent."""
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
s = root / 'include/linux/sched.h'
t = s.read_text()
if 'ANDROID_KABI_USE(1, struct sysv_sem sysvsem)' not in t:
    old = '#ifdef CONFIG_SYSVIPC\n\tstruct sysv_sem\t\t\tsysvsem;\n\tstruct sysv_shm\t\t\tsysvshm;\n#endif\n'
    assert t.count(old) == 1, 'sysv fields not found exactly once'
    t = t.replace(old, '#ifdef CONFIG_SYSVIPC\n\t/* moved into ANDROID_KABI_RESERVE(1..3) below to keep the KMI */\n#endif\n')
    blk = '\tANDROID_KABI_RESERVE(1);\n\tANDROID_KABI_RESERVE(2);\n\tANDROID_KABI_RESERVE(3);\n\tANDROID_KABI_RESERVE(4);\n\tANDROID_KABI_RESERVE(5);\n\tANDROID_KABI_RESERVE(6);\n\tANDROID_KABI_RESERVE(7);\n\tANDROID_KABI_RESERVE(8);\n'
    assert t.count(blk) == 1, 'task_struct reserve block not found exactly once'
    new = ('#ifdef CONFIG_SYSVIPC\n\tANDROID_KABI_USE(1, struct sysv_sem sysvsem);\n'
           '\t_ANDROID_KABI_REPLACE(ANDROID_KABI_RESERVE(2); ANDROID_KABI_RESERVE(3), struct sysv_shm sysvshm);\n'
           '#else\n\tANDROID_KABI_RESERVE(1);\n\tANDROID_KABI_RESERVE(2);\n\tANDROID_KABI_RESERVE(3);\n#endif\n'
           '\tANDROID_KABI_RESERVE(4);\n\tANDROID_KABI_RESERVE(5);\n\tANDROID_KABI_RESERVE(6);\n\tANDROID_KABI_RESERVE(7);\n\tANDROID_KABI_RESERVE(8);\n')
    t = t.replace(blk, new)
    s.write_text(t); print('sched.h patched')
u = root / 'include/linux/sched/user.h'
t = u.read_text()
if 'ANDROID_KABI_USE(1, unsigned long mq_bytes)' not in t:
    old = '\tunsigned long mq_bytes;\t/* How many bytes can be allocated to mqueue? */\n'
    assert t.count(old) == 1, 'mq_bytes not found'
    t = t.replace(old, '\t/* mq_bytes moved into ANDROID_KABI_RESERVE(1) below to keep the KMI */\n')
    blk = '\tANDROID_KABI_RESERVE(1);\n\tANDROID_KABI_RESERVE(2);\n\tANDROID_OEM_DATA_ARRAY(1, 2);\n'
    assert t.count(blk) == 1, 'user_struct reserve block not found'
    t = t.replace(blk, '#if defined(CONFIG_POSIX_MQUEUE)\n\tANDROID_KABI_USE(1, unsigned long mq_bytes);\n#else\n\tANDROID_KABI_RESERVE(1);\n#endif\n\tANDROID_KABI_RESERVE(2);\n\tANDROID_OEM_DATA_ARRAY(1, 2);\n')
    u.write_text(t); print('user.h patched')
