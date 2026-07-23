# Lima 上的 Fedora 伪 x86 VM

在 Apple Silicon 上运行完整的 Fedora x86_64 用户环境，而不模拟一台 x86
机器：原生 ARM64 Linux 内核 + Virtualization.framework 的 Rosetta 翻译 +
`systemd-nspawn`。

内核、模块、eBPF、KVM 和底层 ioctl 仍是 ARM64；shell、systemd、DNF 和普通
应用则是来自 Fedora 官方签名仓库的 x86_64 程序。

> [!WARNING]
> 内层不是安全边界：它共享外层的 ARM64 内核和网络命名空间，使用
> `PrivateUsers=no`，Lima 用户拥有免密 sudo——内层 root 等于外层 VM 的
> root。macOS 主机仍由虚拟机边界隔离，主机 home 默认只读挂载。

## 快速使用

```sh
brew install lima
softwareupdate --install-rosetta --agree-to-license

./lima-rosetta/kernel/build-with-lima.sh   # 在 Fedora ARM64 builder VM 中编译内核
./lima-rosetta/lima/install.sh             # 安装内核与模板

limactl start --name fedora-x86 template:fedora-x86
./lima-rosetta/lima/verify-runtime.sh fedora-x86
limactl shell fedora-x86
```

安装后的运行配置位于 `~/.lima/_kernels/6.18.39-rosetta-tso-lto/` 和
`~/.lima/_templates/fedora-x86.yaml`，不依赖源码仓库路径。

## systemd 兼容策略

Rosetta 是 JIT，无法跨 `execve()` 继承 `MemoryDenyWriteExecute=yes`；而
systemd syscall 过滤器默认返回的 `EPERM` 会让翻译中的服务反复 trap。模板
因此对 system 和 user manager 全局安装：

```ini
[Service]
MemoryDenyWriteExecute=no
SystemCallErrorNumber=ENOSYS
```

syscall 白名单仍然保留，只是拒绝时的 errno 改为 `ENOSYS`，让 Rosetta/glibc
走正常的“系统调用不存在”回退。内层 `systemd-binfmt.service` 被屏蔽，因为
内外两层共享同一个内核 `binfmt_misc` 注册表，只能由外层 Lima 维护 Rosetta
注册。

## 已知问题：journald 偶发 SIGTRAP

journald 读取 `/proc/<pid>/exe` 时可能撞上短生命周期进程退出的竞态；
Rosetta 会把这个普通的 readlink 失败变成内部断言（`BRK #1`）。systemd
会自动重启 journald，系统最终仍进入 `running`；目前没有干净、耐升级且
仅靠 systemd 配置实现的规避方案。

验证脚本区分对待：该特定断言自动恢复后只报告为 known-issue 警告，其他
服务或其他翻译进程的崩溃仍然判失败。`--strict` 模式连该警告也判失败，可
用于验证新版 macOS/Rosetta 是否已修复：

```sh
./lima-rosetta/lima/verify-runtime.sh --strict fedora-x86
```

注意：翻译进程的 coredump 记录在 ARM64 外层（内核看到的崩溃实体是
`/mnt/lima-rosetta/rosetta`），只看内层的 `coredumpctl` 会得到假阴性。

## TSO 内核接口

Apple 的补丁提供 `PR_SET_MEM_MODEL`，在 `DEFAULT` 与 `TSO` 内存模型之间按
线程切换。本移植用 ARM64 CPU capability 框架一次性检测 Apple TSO 能力：
不支持的系统上热路径被 alternatives 补丁掉，不会在上下文切换时读取 Apple
系统寄存器；支持的系统每次切换只读一次 `ACTLR_EL1`，仅在下一任务需要不同
模型时写回。

## 为什么 DNF 更新换不掉内核

内层没有安装内核包，外层 `/boot` 也不是启动来源：Lima 直接引导
`~/.lima/_kernels/` 下经 SHA-256 固定的 `Image`。`sudo dnf upgrade` 只更新
x86_64 用户环境。跨 Fedora 大版本升级是另一次的迁移，需先测试再改模板中
的 release 与 rootfs 标记。

## 交互终端

SSH 网关按连接是否带 TTY 选择方式：

```text
交互式 shell  -> systemd-run --pty
脚本和管道    -> systemd-run --pipe
```

避免 `cannot set terminal process group` / `no job control`，同时保持非交互
命令的管道语义。

更多细节：

- [架构与边界](architecture.md)
- [内核构建与来源](kernel.md)
- [systemd 与 Rosetta](systemd-rosetta.md)
- [维护和故障排查](troubleshooting.md)
