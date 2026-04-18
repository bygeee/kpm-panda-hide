# panda-hide

[English](./README.en.md)

KernelPatch KPM 模块，用于隐藏调试器和反调试检测。

## 功能特性

- 调试器检测隐藏
- Frida 检测隐藏
- openat 系统调用劫持
- 网络检测隐藏
- 内存检测隐藏

## 编译要求

- `aarch64-none-elf-` 交叉编译工具链
- KernelPatch 源码目录

### 获取 ARM 交叉工具链

请从 Arm 官方下载页获取交叉工具链：

https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads

需要选择 `AArch64 bare-metal target (aarch64-none-elf)`。

#### macOS

你也可以使用 Homebrew 安装：

```bash
brew install aarch64-none-elf-gcc
```

#### Linux

下载官方预编译工具链后，将其 `bin` 目录加入 `PATH`，例如：

```bash
tar -xf arm-gnu-toolchain-*.tar.xz
export PATH=$PATH:$(pwd)/arm-gnu-toolchain-*/bin
```

## 编译

```bash
make TARGET_COMPILE=aarch64-none-elf- KP_DIR=/path/to/KernelPatch
```

如果你使用的是本地解压的工具链，也可以显式指定前缀路径：

```bash
make TARGET_COMPILE=/path/to/arm-gnu-toolchain/bin/aarch64-none-elf- KP_DIR=/path/to/KernelPatch
```

## 需要的内核符号

模块会通过 `kallsyms_lookup_name()` 动态解析一部分内核符号，并依赖 KernelPatch 的 syscall hook 能力。

如果下列表格中的符号在目标内核中不存在，请不要直接放弃；应根据对应功能点寻找替代实现，例如改 hook 相邻导出函数、改 hook syscall wrapper、改拦截更上层 `/proc` 输出函数，或退回到更通用的进程名 / 路径 / 内存特征过滤方案。

| 符号 / 接口 | 用途 | 当前模块 | 不存在时的替代方向 |
| --- | --- | --- | --- |
| `kallsyms_lookup_name` | 动态查找内核符号地址 | 全部功能 | 通过 KernelPatch 预置偏移、手动符号表、设备内核符号数据库或静态分析定位目标地址 |
| `seq_put_decimal_ull` | 将 `/proc/[pid]/status` 中 `TracerPid` 改写为 `0` | 调试器隐藏 | 改 hook `proc_pid_status`、`task_state`、`do_task_stat` 或更高层的 seq 输出路径 |
| `seq_puts` | 将 tracing stop 状态文本改写为正常状态 | 调试器隐藏 | 改 hook `task_state`、`do_task_stat`、`proc_pid_status` 等更接近状态拼接的位置 |
| `proc_pid_wchan` | 将 `/proc/[pid]/wchan` 中的 `ptrace_stop` 改为 `0` | 调试器隐藏 | 改 hook `get_wchan`、对应 proc show 函数，或直接在更上层 seq 输出阶段过滤 |
| `do_task_stat` | 修改 `/proc/[pid]/stat` 中的进程状态字符 | 调试器隐藏 | 改 hook `proc_pid_stat`、`task_state` 或相关 stat 输出包装函数 |
| `show_map_vma` | 从 `/proc/[pid]/maps` 中移除 Frida 相关映射 | Frida 隐藏 | 改 hook `show_map`、`seq_path`、VMA 遍历输出函数，或转为针对 maps 文本后处理 |
| `__get_task_comm` | 重写线程名，隐藏 Frida 特征线程名 | Frida 隐藏、网络拦截日志 | 改 hook `get_task_comm`、直接读取 `task->comm` 的上层调用点，或在 `/proc` 输出阶段统一过滤 |
| `access_remote_vm` | 擦除 `/proc/[pid]/mem` 读取结果中的 Frida 特征字符串 | 内存隐藏 | 改 hook `mem_rw`、`process_vm_readv` 路径、ptrace 读内存路径，或针对用户态读取缓冲区做后处理 |
| `__arch_copy_from_user` | 在 `connect()` hook 中读取用户态 `sockaddr` | 网络隐藏 | 改用 `copy_from_user`、`_copy_from_user`、`raw_copy_from_user`，或直接 hook 更下层 socket/connect 实现 |
| `__NR_connect` | hook `connect()`，阻断对 Frida 常见端口的连接 | 网络隐藏 | 改 hook `__sys_connect`、`__arm64_sys_connect`、`sys_connect` 或 socket 层实现 |
| `__NR_openat` | hook `openat()`，屏蔽 Frida 相关路径访问 | 路径隐藏 | 改 hook `do_filp_open`、`path_openat`、`do_sys_openat2`、`__arm64_sys_openat` 等更接近文件打开路径的函数 |
| `__NR_faccessat` | hook `faccessat()`，伪装目标路径不存在 | 路径隐藏 | 改 hook `do_faccessat`、`vfs_faccessat`、`__arm64_sys_faccessat` 或统一转到路径解析层过滤 |
| `fp_hook_syscalln` / `fp_unhook_syscalln` | KernelPatch 提供的 syscall hook API | `openat` / `faccessat` / `connect` | 若函数指针 hook 不可用，可改用 `hook_syscalln`、`inline_hook_syscalln`，或直接 inline hook 目标 syscall handler |
| `compat_strncpy_from_user` | 从用户态安全复制字符串参数 | `openat` / `faccessat` | 改用 `strncpy_from_user`、`copy_from_user + NUL` 终止，或其他等价用户态拷贝封装 |
| `compat_copy_to_user` | KPM 控制接口向用户态返回数据 | 模块控制接口 | 改用 `copy_to_user` 或 KernelPatch 其他用户态数据返回封装 |

### 替代方案建议

- 如果 `/proc` 相关符号缺失，优先找更高层的 proc 输出函数，而不是强依赖某个具体内核版本的私有 helper。
- 如果 syscall 号可用但 `fp_hook_syscalln` 不稳定，优先尝试 `hook_syscalln` 或 `inline_hook_syscalln`。
- 如果某个 helper 名称在新内核里改了，先查是否存在 `__arm64_sys_*`、`ksys_*`、`do_*`、`vfs_*` 等同链路函数。
- 如果内核启用了裁剪、LTO、CFI 或符号隐藏，建议结合设备内核映像、`kallsyms`、反汇编结果和运行时日志重新确认真实落点。

## 如何查看内核导出了哪些符号？

可以直接在设备上查看 `kallsyms`：

```bash
cat /proc/kallsyms | grep 符号名
```

也可以在 IDA 中导入内核符号后，再交叉分析目标函数是否存在、名称是否变化、以及真实调用链落点。

## `load failed` 怎么查看原因？

可以通过 KernelPatch 相关日志定位原因：

```bash
adb shell logcat | grep KP
```

比较常见的原因是某些必需符号没有导入，例如 `memset`，或者目标内核上的符号名、调用路径与当前模块预期不一致。

## 推送到设备

```bash
make push
```

## 清理

```bash
make clean
```

## 致谢

- 感谢 KernelPatch 项目提供 KPM 模块运行与内核补丁能力。
- 感谢 Frida 项目推动动态分析、调试与逆向工程生态的发展。
