# 复制本文件为 local-extra.ps1 后修改。local-extra.ps1 已在 .gitignore 中，不会进仓库。
# 用途：把只属于本机/内网的域名和主机放在这里，保持 apply-bypass.ps1 与上游一致。

$extraDomains = @(
    # "example.com"
)

$extraHosts = @(
    # "10.0.0.12"
)
