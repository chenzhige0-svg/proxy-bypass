# Windows 代理绕过清单（NO_PROXY + ProxyOverride）

把 Windows 上**两份互相独立**的"不走代理"清单一并维护：改一处脚本，两个注册表位置同时更新。

Windows keeps its proxy-bypass list in two unrelated places. This script turns them into one source of truth.

## 为什么需要它

Windows 把"哪些地址不走代理"存在两个地方，两者没有任何联动：

| 位置 | 键 | 谁在读 | 何时生效 |
|---|---|---|---|
| `HKCU\Environment` | `NO_PROXY` | curl / npm / pip / conda / scoop / gh / git | 环境变量，**只对新启动的进程生效** |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings` | `ProxyOverride` | Chrome / Edge / IE / `Invoke-WebRequest` | WinINET，改完即读 |

更麻烦的是两边语法不同，同一个域名写法不一样：

```
NO_PROXY        .qq.com
ProxyOverride   qq.com;*.qq.com
```

`NO_PROXY` 里的 `.qq.com` 是后缀匹配，管住整棵子树；`ProxyOverride` 里的 `qq.com` 只匹配这个主机本身，子域必须再写一条 `*.qq.com`。

于是手改的典型后果是：改了一处、漏了另一处。表现为浏览器正常但终端一直超时，或者反过来。这类问题很难一眼看出原因，因为"没登记"和"网络故障"在表面上完全一样。

## 用法

```powershell
git clone https://github.com/chenzhige0-svg/proxy-bypass.git
cd proxy-bypass
pwsh -File .\apply-bypass.ps1
```

输出会告诉你两处各写入了多少条：

```
NO_PROXY  entries: 75  chars: 882
Override  entries: 145  chars: 1673
snapshot  -> ...\backups\proxy-restore-20261031-162257.ps1
restore   -> ...\proxy-restore.ps1
```

不需要管理员权限，全部写 `HKCU`。

## 加一个地址

改一个文件，重跑一次，两处同时更新。按地址类型分三种：

**普通域名** —— 加进 `apply-bypass.ps1` 的 `$domains`，脚本自动展开成两边需要的写法：

```powershell
$domains = @(
  "baidu.com",
  "example.com"      # 新增
)
```

**IP 或精确主机名** —— 加进 `$hosts`。这类地址不做展开，原样写入：

```powershell
$hosts = @(
  "10.0.0.12"
)
```

不要图省事把 IP 写进 `$domains`：它会生成 `.10.0.0.12` 和 `*.10.0.0.12`，这两串在 WinINET 和 curl 里都匹配不到任何东西，只会让清单变长、并让人误以为已经生效。

**只属于本机的内网地址** —— 放进 `local-extra.ps1`（复制 `local-extra.example.ps1` 修改）。这个文件被 `.gitignore` 排除，不会进仓库：

```powershell
$extraDomains = @("intranet.example.com")
$extraHosts   = @("192.168.1.50")
```

## 展开规则

| 输入 | `NO_PROXY` | `ProxyOverride` |
|---|---|---|
| `qq.com` | `.qq.com` | `qq.com;*.qq.com` |
| `10.0.0.12` | `10.0.0.12` | `10.0.0.12` |
| 固定前缀 | `localhost,127.0.0.1,::1,.cn` | `<local>;localhost;127.*;::1` |

`.cn` 是整段后缀豁免，如果你不希望所有国内站点都直连，把它从脚本里删掉。

## 备份与回滚

脚本每次运行都会先读当前值，再写新的，并留下两份文件：

- `backups\proxy-restore-<时间戳>.ps1` —— 每次运行前的旧值，一层层往回退
- `proxy-restore.ps1` —— 稳定入口，**只在文件不存在时生成一次**，之后不再覆盖

第二条是有意为之。早期版本每次运行都用"当前值"重写它，于是第二次运行就把最初的干净状态覆盖成已改过的状态，回滚点名存实亡。

```powershell
# 退回上一次运行之前
pwsh -File .\backups\proxy-restore-20261031-162257.ps1

# 退回最小状态（三条例外，其余全部走代理）
pwsh -File .\proxy-restore.ps1
```

## 验证

```powershell
$np = [Environment]::GetEnvironmentVariable("NO_PROXY","User")
$ov = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings").ProxyOverride

($np -split ',').Count
($ov -split ';').Count
($ov -split ';')[-1]      # 最后一条，用来确认新加的主机进来了
```

要确认某个地址到底走不走代理，直接对比两个请求，不用改任何设置：

```powershell
curl.exe -o NUL -w "direct %{http_code}`n" --noproxy "*" https://example.com/
curl.exe -o NUL -w "proxy  %{http_code}`n" -x http://127.0.0.1:PORT https://example.com/
```

直连通、走代理不通，说明它确实需要被登记。

## 常见问题

**浏览器生效了，终端没有。**
`NO_PROXY` 是环境变量，只对新启动的进程生效。已经开着的终端拿到的是旧值，重开一个再试。脚本写完环境变量会广播 `WM_SETTINGCHANGE`，但已经运行的进程不会自己更新。

**终端生效了，浏览器没有。**
浏览器读的是 WinINET 缓存。脚本写完会调用 `InternetSetOption(39/37)` 强制重读，通常立刻生效；如果个别窗口还是老行为，重启浏览器，或在"Internet 选项 → 连接 → 局域网设置"里点两次确定。

**会不会影响同一局域网的其它设备？**
不会。两处都在 `HKCU` 下，属于当前用户的登录会话。别的设备读不到，本机别的用户也读不到。要让其它设备也生效，只能在那些设备上各跑一次。

**会不会改掉代理软件的设置？**
不会。脚本只写 `ProxyOverride`（例外列表）和 `NO_PROXY`，不碰 `ProxyEnable`、`ProxyServer`、`AutoConfigURL`。代理开关和服务器地址归代理客户端（Clash / Hiddify / v2rayN 等）管。

**能加多少条？**
`ProxyOverride` 实测 1700 字符工作正常，历史上 WinINET 对这一项的长度限制在 4 KB 左右。接近上限时不要继续堆，先考虑把若干子域合并成上级域，或者只保留真正必要的。

**没有安装代理也需要吗？**
不需要。这是给"已经开了系统代理，但希望部分地址直连"的场景用的。

## 环境要求

- Windows 10 / 11
- PowerShell 5.1 或 7+
- 不需要管理员权限

## 许可

MIT
