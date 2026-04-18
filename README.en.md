# panda-hide

[中文](./README.md)

KernelPatch KPM module for hiding debugger presence and anti-debugging checks.

## Features

- Hide debugger detection
- Hide Frida detection
- Hook the `openat` syscall
- Hide network-based detection
- Hide memory-based detection

## Build Requirements

- `aarch64-none-elf-` cross toolchain
- KernelPatch source tree

### Get the ARM cross toolchain

Download the toolchain from Arm's official page:

https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads

Choose the `AArch64 bare-metal target (aarch64-none-elf)`.

#### macOS

You can also install it with Homebrew:

```bash
brew install aarch64-none-elf-gcc
```

#### Linux

After downloading the official prebuilt toolchain, add its `bin` directory to `PATH`, for example:

```bash
tar -xf arm-gnu-toolchain-*.tar.xz
export PATH=$PATH:$(pwd)/arm-gnu-toolchain-*/bin
```

## Build

```bash
make TARGET_COMPILE=aarch64-none-elf- KP_DIR=/path/to/KernelPatch
```

If you are using a locally extracted toolchain, you can also pass the full prefix path explicitly:

```bash
make TARGET_COMPILE=/path/to/arm-gnu-toolchain/bin/aarch64-none-elf- KP_DIR=/path/to/KernelPatch
```

## Required Kernel Symbols

This module resolves part of its targets dynamically through `kallsyms_lookup_name()` and also relies on KernelPatch syscall hook support.

If any symbol in the table below is missing on the target kernel, do not stop at that point. You should look for an equivalent hook point for the same feature, such as a nearby exported function, a syscall wrapper, a higher-level `/proc` formatter, or a more generic process-name / path / memory filtering path.

| Symbol / API | Purpose | Used By | Fallback Direction If Missing |
| --- | --- | --- | --- |
| `kallsyms_lookup_name` | Resolve kernel symbol addresses dynamically | All features | Use KernelPatch preset offsets, a device-specific symbol database, manual symbol recovery, or static analysis to locate targets |
| `seq_put_decimal_ull` | Rewrite `TracerPid` to `0` in `/proc/[pid]/status` | Debugger hiding | Hook `proc_pid_status`, `task_state`, `do_task_stat`, or a higher-level seq output path instead |
| `seq_puts` | Rewrite tracing-stop text to a normal task state | Debugger hiding | Hook `task_state`, `do_task_stat`, `proc_pid_status`, or another state formatting path |
| `proc_pid_wchan` | Replace `ptrace_stop` with `0` in `/proc/[pid]/wchan` | Debugger hiding | Hook `get_wchan`, the proc show handler, or filter the seq output at a higher level |
| `do_task_stat` | Modify the task state character in `/proc/[pid]/stat` | Debugger hiding | Hook `proc_pid_stat`, `task_state`, or another stat formatting wrapper |
| `show_map_vma` | Remove Frida-related mappings from `/proc/[pid]/maps` | Frida hiding | Hook `show_map`, `seq_path`, VMA formatting helpers, or apply post-processing to maps output |
| `__get_task_comm` | Rewrite suspicious thread names | Frida hiding, network filtering logs | Hook `get_task_comm`, filter direct `task->comm` consumers, or sanitize `/proc` output instead |
| `access_remote_vm` | Scrub Frida strings from `/proc/[pid]/mem` read results | Memory hiding | Hook `mem_rw`, `process_vm_readv`, ptrace memory-read paths, or sanitize the copied buffer later in the read chain |
| `__arch_copy_from_user` | Copy user `sockaddr` inside the `connect()` hook | Network hiding | Switch to `copy_from_user`, `_copy_from_user`, `raw_copy_from_user`, or hook a lower socket/connect implementation |
| `__NR_connect` | Hook `connect()` and block known Frida ports | Network hiding | Hook `__sys_connect`, `__arm64_sys_connect`, `sys_connect`, or lower socket-layer handlers |
| `__NR_openat` | Hook `openat()` and hide Frida-related paths | Path hiding | Hook `do_filp_open`, `path_openat`, `do_sys_openat2`, `__arm64_sys_openat`, or another file-open path |
| `__NR_faccessat` | Hook `faccessat()` and pretend target paths do not exist | Path hiding | Hook `do_faccessat`, `vfs_faccessat`, `__arm64_sys_faccessat`, or move filtering to path resolution |
| `fp_hook_syscalln` / `fp_unhook_syscalln` | KernelPatch syscall hook API | `openat` / `faccessat` / `connect` | Use `hook_syscalln`, `inline_hook_syscalln`, or inline hook the target syscall handler directly |
| `compat_strncpy_from_user` | Safely copy string arguments from user space | `openat` / `faccessat` | Use `strncpy_from_user`, `copy_from_user` with explicit NUL termination, or an equivalent helper |
| `compat_copy_to_user` | Return control data to user space from KPM | Module control interface | Use `copy_to_user` or another KernelPatch user-copy helper |

### Fallback Notes

- If a `/proc` symbol is missing, prefer a higher-level proc formatter over hard-binding to one private helper from a single kernel version.
- If syscall numbers are usable but `fp_hook_syscalln` is not stable, try `hook_syscalln` or `inline_hook_syscalln` first.
- If helper names changed on newer kernels, check for equivalents under `__arm64_sys_*`, `ksys_*`, `do_*`, and `vfs_*`.
- If the kernel uses trimming, LTO, CFI, or symbol hiding, confirm the real hook points with the kernel image, kallsyms output, disassembly, and runtime logging.

## How to Check Which Kernel Symbols Are Exported?

You can inspect `kallsyms` directly on the device:

```bash
cat /proc/kallsyms | grep symbol_name
```

You can also import kernel symbols into IDA and verify whether the target function exists, whether its name changed, and where the real call path lands.

## How to Diagnose `load failed`?

Check the KernelPatch-related logs:

```bash
adb shell logcat | grep KP
```

A common cause is that some required symbols were not imported, for example `memset`, or that the symbol names and call paths on the target kernel do not match what this module expects.

## Push to Device

```bash
make push
```

## Clean

```bash
make clean
```

## Acknowledgements

- Thanks to the KernelPatch project for providing the KPM module framework and kernel patching capabilities.
- Thanks to the Frida project for advancing the ecosystem around dynamic analysis, debugging, and reverse engineering.
