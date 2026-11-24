# Ozone for WSLg

给 SEGGER Ozone V3.52 的 Linux x86-64 版提供 Qt 4.8.7 补丁，在原生 WSLg 下
修正停靠面板拖出后无法操作、偶发消失，以及 Weston 留下 74×74 空外框的问题。
仓库包含源码补丁、构建脚本和隔离试用脚本。Ozone 本体从 SEGGER 获取。

## 下载预编译版

Ubuntu 26.04 x86-64 的安装包和对应 Qt 源码见 [GitHub Releases](https://github.com/WeiyiHuang25/Ozone_for_wsl/releases)。
解压安装包后运行 `./install.sh`，再运行 `~/.local/bin/ozone-wslg`。
安装脚本使用当前用户的目录，并读取本机已安装的 SEGGER Ozone V3.52。

## 补丁

1. 修复 Qt4 的 `Q_FOREACH` 与新版 GCC 的兼容问题，保留 `break` 和 `continue` 语义。
2. 在原生 WSLg 下，将 Ozone 的正式浮窗在 X11 中声明为 `NORMAL`，保留 Qt 的
   `Qt::Tool` 和 `WM_TRANSIENT_FOR`。补丁通过 X11 socket 确认当前连接是 WSLg。
3. 拖拽结束时，如果旧临时窗口已位于目标 X11 根窗口下，直接走原有销毁流程。
   这样可以避免 Weston 因重复挂接而保留旧窗口记录。

## 构建和试用

基线是 SEGGER 的 Qt 4.8.7 Rev18。下载并解压
[SEGGER Qt4 源码](https://download.segger.com/3rdParty/SEGGER_Qt487_Src.7z)。
已验证的源码归档 SHA-256 为
`09a32c0d0292c128f91f045ac129b0418d99f2936a6e08b22797f72d73e5f6bd`。

准备 GCC/G++、GNU Make、Python 3、GNU patch、pkg-config，以及 X11、Xext、Xfixes、
Xcursor、Xrandr、Xrender、SM、ICE、FreeType 和 Fontconfig 的开发头文件及库。
构建脚本沿用 SEGGER 的 x86-64 release 配置，在 `build/` 中复制源码、应用补丁并构建。
可以通过 `JOBS` 指定并行数。如果使用解压到本地的开发包，通过 `QT4_SDK` 传入其中的
`usr` 目录。

```bash
./scripts/build-qtgui.sh /path/to/SEGGER-qt-4.8.7
```

脚本成功后打印 `QtGui:` 和产物路径。将该路径作为第一个参数传给试用脚本。

```bash
./scripts/run-test.sh /path/to/build/lib/libQtGui.so.4.8.7
```

试用脚本默认从 `/opt/SEGGER/Ozone_V352` 取已安装的 Ozone，使用原版 QtCore，
并为测试进程加载补丁版 QtGui。可用 `OZONE_DIR` 指定其他安装路径，库路径之后可附
Ozone 的命令行参数。测试实例使用独立的临时配置，系统安装继续指向原库。

## 验证结果

- Ubuntu 26.04 x86-64、GCC 15、WSLg 1.0.73.2。Ozone 所用的 1617 个 QtGui 符号
  均存在，链接检查通过。
- 重启 WSLg 后，重开测试版 Ozone 三轮。`Functions` 和 `Watched Data` 各完成 15 次脱出
  和回停靠，覆盖主窗口最大化和还原。Windows 侧 18 次抽查均能看见浮窗，退出后也没有
  新增可见空外框。
- 老会话里遗留的窗口记录可能继续影响新实例。保存工作后，从 Windows 执行
  `wsl --shutdown` 可清空这些记录。此命令会结束正在运行的 WSL 会话。

约 1 秒的 X11 窗口关闭延迟来自 WSLg。高 DPI 绘制与缩放也属于独立问题。
[WSLg 问题 #1443](https://github.com/microsoft/wslg/issues/1443) 记录了关闭延迟。

Qt 补丁随 SEGGER 源码包中的 Qt 许可使用，见 [Qt 源码许可](LICENSE.LGPLv21)。
Ozone 本体、原版库和其他 SEGGER 文件适用原始安装包所附条款。
