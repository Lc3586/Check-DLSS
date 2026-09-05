# 支持传入目标路径参数，默认为脚本所在目录
param (
    [string]$TargetDir = $PSScriptRoot
)

# 清除尾部斜杠
$TargetDir = $TargetDir.TrimEnd('\', '/')

# 定义 ANSI 转义字符及颜色
$e = [char]27
$C_RESET = "$e[0m"
$C_GREEN = "$e[92m"
$C_CYAN = "$e[96m"
$C_GRAY = "$e[90m"
$C_YELLOW = "$e[93m"
$C_RED = "$e[91m"
$C_BOLD = "$e[1m"

# 设置控制台输出为 UTF-8，确保进度条块字符与符号正确显示
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ============ 显示宽度辅助函数（正确处理中文等全角字符的对齐） ============
function Get-DisplayWidth {
    param([string]$Text)
    $width = 0
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int]$ch
        if (($code -ge 0x1100 -and $code -le 0x115F) -or
            ($code -ge 0x2E80 -and $code -le 0xA4CF) -or
            ($code -ge 0xAC00 -and $code -le 0xD7A3) -or
            ($code -ge 0xF900 -and $code -le 0xFAFF) -or
            ($code -ge 0xFE30 -and $code -le 0xFE4F) -or
            ($code -ge 0xFF00 -and $code -le 0xFF60) -or
            ($code -ge 0xFFE0 -and $code -le 0xFFE6)) {
            $width += 2
        }
        else {
            $width += 1
        }
    }
    return $width
}

# 按显示宽度右侧补齐空格
function Pad-DisplayRight {
    param([string]$Text, [int]$Width)
    $pad = $Width - (Get-DisplayWidth $Text)
    if ($pad -lt 0) { $pad = 0 }
    return $Text + (' ' * $pad)
}

# 按显示宽度左侧补齐空格
function Pad-DisplayLeft {
    param([string]$Text, [int]$Width)
    $pad = $Width - (Get-DisplayWidth $Text)
    if ($pad -lt 0) { $pad = 0 }
    return (' ' * $pad) + $Text
}

Clear-Host
Write-Host ""
Write-Host "${C_CYAN}  +-------------------------------------------------------------+${C_RESET}"
Write-Host "${C_CYAN}  |                      NVIDIA DLSS 组件检测                    |${C_RESET}"
Write-Host "${C_CYAN}  +-------------------------------------------------------------+${C_RESET}"
Write-Host "${C_CYAN}  |${C_RESET} 目标目录:"
Write-Host "${C_CYAN}  |${C_RESET} ${C_YELLOW}${TargetDir}${C_RESET}"
Write-Host "${C_CYAN}  +-------------------------------------------------------------+${C_RESET}"
Write-Host ""

# 检查目标文件夹是否存在
if (-not (Test-Path -Path $TargetDir -PathType Container)) {
    Write-Host "[!] 目录不存在" -ForegroundColor Red
    Write-Host ""
    Read-Host "按任意键退出检测..."
    exit
}

# 获取指定目录下的所有子文件夹
$folders = Get-ChildItem -Path $TargetDir -Directory

if ($folders.Count -eq 0) {
    Write-Host "[!] 在指定目录下未找到任何文件夹。" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "按任意键退出检测..."
    exit
}

Write-Host ""
Write-Host "${C_CYAN}  +-------------------------------------------------------------+${C_RESET}"
Write-Host "${C_CYAN}  |开始扫描所有子目录下的 DLSS 组件...                      ${C_RESET}"
Write-Host "${C_CYAN}  |共找到文件夹数量: $($folders.Count)                     ${C_RESET}"
Write-Host "${C_CYAN}  +-------------------------------------------------------------+${C_RESET}"
Write-Host ""

# 定义需要检查的 DLSS 组件清单
$components = @(
    @{ File = "nvngx_dlss.dll"; Name = "超分辨率" },
    @{ File = "nvngx_dlssd.dll"; Name = "光线重构" },
    @{ File = "nvngx_dlssg.dll"; Name = "帧生成" },
    @{ File = "nvngx_dlssnr.dll"; Name = "神经渲染模型（DLSS5）" },
    @{ File = "nvngx_deepdvc.dll"; Name = "动态数字色彩/饱和度增强控制" }
)

# 进度条宽度（字符数）
$barWidth = 30
# 进度条上显示目录名的列宽
$nameColW = 40

# 存储扫描结果（仅保留有匹配的目录）
$results = @()

# 在同一行绘制/刷新进度条
function Write-ScanProgress {
    param([int]$completed, [int]$total, [string]$label, [string]$name)
    $percent = if ($total -gt 0) { [math]::Round(($completed / $total) * 100) } else { 100 }
    $filled = [math]::Floor($barWidth * $completed / $total)
    $empty = $barWidth - $filled
    $bar = ("█" * $filled) + ("░" * $empty)

    $shortName = if ($name.Length -gt 20) { $name.Substring(0, 20) + "…" } else { $name }
    $progressLine = "  ${C_CYAN}[${C_RESET}${C_GREEN}${bar}${C_RESET}${C_CYAN}]${C_RESET} " +
                    "${C_YELLOW}$(Pad-DisplayLeft ($percent.ToString() + '%') 4)${C_RESET} " +
                    "${C_GRAY}($($completed.ToString().PadLeft($total.ToString().Length))/$total)${C_RESET}  " +
                    "${C_GRAY}${label}: ${C_RESET}${C_CYAN}$(Pad-DisplayRight $shortName $nameColW)${C_RESET}"
    Write-Host "`r$progressLine" -NoNewline
}

$index = 0
foreach ($folder in $folders) {
    $index++
    $folderName = $folder.Name
    $folderPath = $folder.FullName

    # 开始扫描该目录：进度条先更新为"正在扫描"
    Write-ScanProgress -completed ($index - 1) -total $folders.Count -label "正在扫描" -name $folderName

    # 递归检查各组件：在目录任意层级中找到即算命中
    $hits = @()
    foreach ($item in $components) {
        $filePath = Join-Path -Path $folderPath -ChildPath $item.File
        $matchedPath = $null
        if (Test-Path -Path $filePath -PathType Leaf) {
            $matchedPath = $filePath
        }
        else {
            # 递归查找（-Recurse 会深入所有子目录）
            $foundItem = Get-ChildItem -Path $folderPath -Filter $item.File -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($foundItem) {
                $matchedPath = $foundItem.FullName
            }
        }
        
        # 将找到的完整路径（或 $null）存入数组
        $hits += $matchedPath
    }

    # 过滤掉 $null 和空字符串，获取所有找到的有效路径
    $validHits = $hits | Where-Object { $_ }
    
    # 只要找到至少一个有效路径就添加结果
    if ($validHits.Count -gt 0) {
        $results += [PSCustomObject]@{
            Name  = $folderName
            Hits  = $validHits      # 如果想保留原始对应关系（含 $null），也可以直接写 $hits
            Count = $validHits.Count
        }
    }

    # 扫描完成：进度条更新为"扫描完成"并推进一格
    Write-ScanProgress -completed $index -total $folders.Count -label "扫描完成" -name $folderName
}

# 进度条完成后换行
Write-Host ""
Write-Host ""

# ============ 汇总报告（仅显示匹配目录，逐行展示各组件） ============
Write-Host "${C_CYAN}  +-------------------------------------------------------------+${C_RESET}"
Write-Host "${C_CYAN}  |${C_BOLD}                      扫描完成汇总报告${C_RESET}${C_CYAN}                    |${C_RESET}"
Write-Host "${C_CYAN}  +-------------------------------------------------------------+${C_RESET}"
Write-Host ""

if ($results.Count -eq 0) {
    Write-Host "  ${C_YELLOW}[!] 未在任何目录中找到 DLSS 组件。${C_RESET}"
    Write-Host ""
    Read-Host "按任意键退出..."
    exit
}

Write-Host "  ${C_GREEN}共 $($results.Count) / $($folders.Count) 个目录检测到 DLSS 组件：${C_RESET}"
Write-Host ""

# 按目录分组，逐行展示各组件匹配情况
$dirIndex = 0
foreach ($r in $results) {
    $dirIndex++
    Write-Host ""
    Write-Host "${C_BOLD}${C_CYAN}  [$dirIndex/$($results.Count)] 目录: ${C_RESET}${C_BOLD}${C_YELLOW}$($r.Name)${C_RESET}${C_BOLD}${C_CYAN}  (命中 $($r.Count) / $($components.Count))${C_RESET}"

    for ($i = 0; $i -lt $components.Count; $i++) {
        $item = $components[$i]
        $fileName = $item.File.PadRight(18)
        $hitPath = $r.Hits[$i]
        if ($hitPath) {
            Write-Host "     ${C_GREEN}[✅] ${C_RESET}$($item.Name) ${C_GRAY}$hitPath"
        }
        else {
            Write-Host "     ${C_GRAY}[❌] ${C_RESET}$($item.Name) ${C_GRAY}$hitPath"
        }
    }
}

Write-Host ""
Write-Host "${C_GRAY}  " + ("-" * 60) + "${C_RESET}"
Write-Host ""
Write-Host ""
Read-Host "按任意键退出..."
