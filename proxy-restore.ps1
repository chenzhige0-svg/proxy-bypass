# 还原用：把两份绕过清单恢复到最初的最小状态
#   pwsh -File .\proxy-restore.ps1

[Environment]::SetEnvironmentVariable('NO_PROXY','localhost,127.0.0.1,::1','User')
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name ProxyOverride -Value 'localhost;127.0.0.1;::1;<local>'

# 通知 WinINET 重读设置（39 = SETTINGS_CHANGED，37 = REFRESH）
if (-not ("Win32.WinInet" -as [type])) {
    Add-Type -Namespace Win32 -Name WinInet -MemberDefinition @"
[DllImport("wininet.dll", SetLastError = true)]
public static extern bool InternetSetOption(IntPtr h, int opt, IntPtr buf, int len);
"@
}
[Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
[Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
