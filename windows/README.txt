DSH Web 托盘控制器
===================
仓库：dsh-web-tray
位置：%LOCALAPPDATA%\DSH

启动
----
- 桌面快捷方式 "DSH Web Tray"
- 或开始菜单搜索 "DSH Web Tray"
首次启动后，通知区域会出现鲸鱼图标。若它被折叠在 ^ 溢出区，
点 ^ 把鲸鱼图标拖到任务栏即可常驻。

菜单
----
  打开 Web UI / 启动 / 停止 / 重启 / 查看日志
  托盘开机自启（勾选）
  dsh web 开机自启（勾选）
  退出托盘

两个自启开关
------------
托盘开机自启：
  Startup\DSH Web Tray.lnk -> dsh-web-tray.vbs
  登录 Windows 时启动托盘。

dsh web 开机自启：
  Startup\DSH Web Server.lnk -> dsh-web-autostart.vbs
  登录 Windows 时直接运行 WSL 里的 dsh-web start，不依赖托盘。

两者互相独立：
- 只开托盘自启：登录后托盘在，但 dsh web 要手动启动。
- 只开 web 自启：登录后 dsh web 自动启动，托盘可以不启动；
  需要管理时用桌面快捷方式打开托盘。
- 两个都开：登录后托盘和 dsh web 都启动。

切换开关会立即创建/删除 Startup 快捷方式，但“自动启动服务”
只在下一次 Windows 登录时发生。本次想立即启动，点托盘里的“启动”。

WSL 命令
--------
  ~/.local/bin/dsh-web start
  ~/.local/bin/dsh-web stop
  ~/.local/bin/dsh-web restart
  ~/.local/bin/dsh-web status
  ~/.local/bin/dsh-web logs

  日志：~/.local/state/dsh-web/web.log
  PID： ~/.local/state/dsh-web/web.pid

配置
----
  dsh-web-tray.config.ps1 记录本机的 WSL 发行版、用户名、dsh-web 路径和端口。
  由仓库里的 install.sh 生成，已存在时保留。
  换发行版/用户/端口：在仓库目录运行
    ./install.sh --refresh-config
  也可以直接编辑该文件，改完重启托盘生效。

外观与 DPI
----------
- 鲸鱼图标：蓝色=运行中，灰色=已停止，多尺寸 ICO（16/20/24/28/32/40/48/64/128/256）。
- 托盘按当前 DPI 选择图标尺寸；菜单是自绘圆角样式，跟随 Windows 浅色/深色主题。
- 菜单图标与文字已按视觉中心对齐。
- 若更改 Windows 显示缩放，退出托盘再启动会按新 DPI 重载图标。

文件
----
  dsh-web-tray.ps1       托盘主程序
  dsh-web-tray.vbs       无窗口启动托盘
  dsh-web-autostart.vbs  登录时启动 dsh web
  dsh-web-tray.config.ps1 本机配置（发行版/用户/端口）
  install.ps1            创建桌面/开始菜单/自启快捷方式
  dsh-web-running.ico    运行中图标
  dsh-web-stopped.ico    已停止图标

卸载
----
1. 托盘菜单 → 停止 → 退出托盘
2. 删除桌面和开始菜单里的 "DSH Web Tray"
3. 删除 Startup 里的 "DSH Web Tray.lnk" 和 "DSH Web Server.lnk"（如果存在）
4. 删除 %LOCALAPPDATA%\DSH
5. 可选：删除 ~/.local/bin/dsh-web 和 ~/.local/state/dsh-web

图标来源
--------
dsh 自带的前端 favicon.svg，用 sharp 渲染成 Windows ICO。
图标版权归 DeepSeek。重新生成（在仓库目录）：
  node tools/build-icons.js
