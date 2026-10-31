# Proxy bypass for Windows — 一次写入两份清单
# 真源只有下面的 $domains / $hosts；改完重跑本脚本，NO_PROXY 与 ProxyOverride 一起更新。
#
#   pwsh -File .\apply-bypass.ps1
#
# 回滚：pwsh -File .\proxy-restore.ps1
# 每次运行前的旧值快照：.\backups\proxy-restore-<时间戳>.ps1

$ErrorActionPreference = "Stop"

$reg  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
$here = $PSScriptRoot
$bak  = Join-Path $here "backups"

# ---------- 清单 ----------

# 域名：自动展开成 ".example.com"（NO_PROXY）和 "example.com;*.example.com"（ProxyOverride）
$domains = @(
  "qq.com","tencent.com","gtimg.com","qpic.cn","servicewechat.com",
  "163.com","126.com","126.net","127.net","netease.com",
  "bilibili.com","hdslb.com","bilivideo.com","b23.tv",
  "taobao.com","tmall.com","alicdn.com","alipay.com","alipayobjects.com","aliyun.com","aliyuncs.com","alibaba.com","1688.com",
  "jd.com","360buyimg.com",
  "weibo.com","sinaimg.cn","sina.com.cn",
  "iqiyi.com","qiyipic.com","youku.com","tudou.com",
  "xiaohongshu.com","xhscdn.com","ctrip.com","qunar.com","trip.com",
  "douyin.com","byteimg.com","bytedance.com","toutiao.com","ixigua.com","feishu.cn",
  "meituan.com","dianping.com","meituan.net",
  "pinduoduo.com","yangkeduo.com","pddpic.com",
  "zhihu.com","zhimg.com","csdn.net","cnblogs.com","gitee.com","oschina.net",
  "baidu.com","bdstatic.com","sohu.com","58.com","kuaishou.com","gifshow.com",
  "douban.com","doubanio.com","huawei.com","hicloud.com","mi.com","miui.com","xiaomi.com",
  "autodl.com",
  "gpugeek.com"
)

# 裸主机（IP 或精确域名）：原样写入两处，不加 . 前缀也不加 *. 通配
$hosts = @(
  # "10.0.0.12"
)

# 本机私货：同目录放 local-extra.ps1（已在 .gitignore 里），里面写
#   $extraDomains = @("example.com")
#   $extraHosts   = @("172.16.0.10")
$extraDomains = @()
$extraHosts   = @()
$localExtra = Join-Path $here "local-extra.ps1"
if (Test-Path $localExtra) { . $localExtra }

$domains = @($domains) + @($extraDomains)
$hosts   = @($hosts)   + @($extraHosts)

# ---------- 展开成两处各自的语法 ----------

$noProxyList = @("localhost","127.0.0.1","::1",".cn") +
               ($domains | ForEach-Object { ".$_" }) +
               $hosts
$noProxy = $noProxyList -join ","

$overrideList = @("<local>","localhost","127.*","::1") +
                ($domains | ForEach-Object { $_, "*.$_" }) +
                $hosts
$override = $overrideList -join ";"

# ---------- 备份当前值 ----------

$oldNoProxy  = [Environment]::GetEnvironmentVariable("NO_PROXY","User")
$oldOverride = (Get-ItemProperty $reg -Name ProxyOverride -ErrorAction SilentlyContinue).ProxyOverride
$stamp       = Get-Date -Format "yyyyMMdd-HHmmss"

function Quote([string]$v) {
  if ($null -eq $v) { return '$null' }
  "'" + ($v -replace "'", "''") + "'"
}

$refreshBlock = @'
# 通知 WinINET 重读设置（39 = SETTINGS_CHANGED，37 = REFRESH）
if (-not ("Win32.WinInet" -as [type])) {
    Add-Type -Namespace Win32 -Name WinInet -MemberDefinition @"
[DllImport("wininet.dll", SetLastError = true)]
public static extern bool InternetSetOption(IntPtr h, int opt, IntPtr buf, int len);
"@
}
[Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
[Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
'@

$restore = @(
  "# 还原到 $stamp 之前的状态",
  '$ErrorActionPreference = "Stop"',
  "`$reg = '$reg'"
)
if ($null -eq $oldNoProxy) {
  $restore += "[Environment]::SetEnvironmentVariable('NO_PROXY',`$null,'User')"
} else {
  $restore += "[Environment]::SetEnvironmentVariable('NO_PROXY',$(Quote $oldNoProxy),'User')"
}
if ($null -eq $oldOverride) {
  $restore += "Remove-ItemProperty `$reg -Name ProxyOverride -ErrorAction SilentlyContinue"
} else {
  $restore += "Set-ItemProperty `$reg -Name ProxyOverride -Value $(Quote $oldOverride)"
}
$restore += $refreshBlock

New-Item -ItemType Directory -Force -Path $bak | Out-Null
$snapshot = Join-Path $bak "proxy-restore-$stamp.ps1"
$restore | Set-Content -Path $snapshot -Encoding UTF8

# 稳定入口只在缺失时写一次，避免把最初的干净状态覆盖成“已改过”的值
$main = Join-Path $here "proxy-restore.ps1"
if (-not (Test-Path $main)) {
  $restore | Set-Content -Path $main -Encoding UTF8
}

# ---------- 写入两个位置 ----------

[Environment]::SetEnvironmentVariable("NO_PROXY", $noProxy, "User")
Set-ItemProperty $reg -Name ProxyOverride -Value $override
Invoke-Expression $refreshBlock

"NO_PROXY  entries: {0}  chars: {1}" -f $noProxyList.Count, $noProxy.Length
"Override  entries: {0}  chars: {1}" -f $overrideList.Count, $override.Length
"snapshot  -> $snapshot"
"restore   -> $main"
