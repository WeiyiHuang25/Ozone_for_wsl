# Ozone for WSLg

适用于 Ubuntu 26.04 x86-64、WSL 2 原生 WSLg 和 SEGGER Ozone V3.52。
压缩包包含编译好的 QtGui、安装脚本和启动脚本。请先安装 SEGGER 的 Ozone V3.52。

## 安装

1. 下载文件名以 `ubuntu26.04-x86_64.tar.gz` 结尾的安装包，使用 `SHA256SUMS` 核对。
2. 在 Ubuntu 中解压，进入解压出来的目录，运行 `./install.sh`。可传入已安装 Ozone 的路径。
3. 运行 `~/.local/bin/ozone-wslg`。安装脚本会打印实际的启动路径。

安装使用当前用户的目录并保留隔离的 Ozone 配置。SEGGER 原安装继续通过原来的命令启动。
如果此前的 WSLg 会话已经残留 74×74 小块，保存工作并从 Windows 执行
`wsl --shutdown` 后再试用。该命令会结束正在运行的 WSL 会话。

本版修复浮窗不可操作和偶发消失。高 DPI 模糊和 WSLg 的 X11 关闭延迟仍然存在。
对应的 Qt 源码、补丁和构建脚本位于同一 Release 的 `qt-source.tar.gz` 资产中。
