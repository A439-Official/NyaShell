function nyafetch {
    $fetchType = 0
    $fetchPic = ""
    $fetchText = ""

    if ($NyaConfig -and $NyaConfig.nyafetch) {
        $fetchType = $NyaConfig.nyafetch.type
        if (-not $fetchType) { $fetchType = 0 }
        $fetchPic = $NyaConfig.nyafetch.pic
        if (-not $fetchPic) { $fetchPic = "" }
        $fetchText = $NyaConfig.nyafetch.text
        if (-not $fetchText) { $fetchText = "" }
    }

    if ($isWin) {
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        $cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name

        $gpus = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch "Microsoft Basic" })
        $gpu = ($gpus | Sort-Object AdapterRAM -Descending | Select-Object -First 1).Name

        $userName = $cs.UserName
        $osCaption = $os.Caption
        $memFreeKB = $os.FreePhysicalMemory
        $memTotalKB = $os.TotalVisibleMemorySize

        $disksize = 0
        $diskused = 0
        $disks = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null -and $_.Free -ne $null }
        foreach ($disk in $disks) {
            $disksize += $disk.Used + $disk.Free
            $diskused += $disk.Used
        }

        $ipCfg = Get-NetIPConfiguration |
        Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4DefaultGateway } |
        Select-Object -First 1
        $ip = if ($ipCfg) { $ipCfg.IPv4Address.IPAddress } else { '' }
    }
    else {
        $userName = [Environment]::UserName

        if (Test-Path /etc/os-release) {
            $osRelease = Get-Content /etc/os-release -Raw
            if ($osRelease -match 'PRETTY_NAME="?([^"\r\n]+)"?') {
                $osCaption = $Matches[1]
            }
            else {
                $osCaption = (uname -srm)
            }
        }
        else {
            $osCaption = (uname -srm)
        }

        if (Test-Path /proc/cpuinfo) {
            $cpuLine = Get-Content /proc/cpuinfo | Where-Object { $_ -match '^model name' } | Select-Object -First 1
            if ($cpuLine) {
                $cpu = ($cpuLine -replace '^.*:\s*', '').Trim()
            }
            else {
                $cpu = (uname -m)
            }
        }
        else {
            $cpu = (sysctl -n machdep.cpu.brand_string 2>$null)
            if (-not $cpu) { $cpu = (uname -m) }
        }

        if (Get-Command lspci -ErrorAction SilentlyContinue) {
            $gpuLine = lspci | Where-Object { $_ -match 'VGA|3D|Display' } | Select-Object -First 1
            if ($gpuLine -match '(?:VGA compatible controller|3D controller|Display controller):\s*(.+)$') {
                $gpu = $Matches[1].Trim()
            }
            elseif ($gpuLine) {
                $gpu = $gpuLine.Trim()
            }
            else {
                $gpu = 'Unknown'
            }
        }
        elseif (Get-Command system_profiler -ErrorAction SilentlyContinue) {
            $gpuLine = system_profiler SPDisplaysDataType | Where-Object { $_ -match 'Chipset Model' } | Select-Object -First 1
            $gpu = if ($gpuLine) { ($gpuLine -replace '^.*:\s*', '').Trim() } else { 'Unknown' }
        }
        else {
            $gpu = 'Unknown'
        }

        if (Test-Path /proc/meminfo) {
            $memInfo = Get-Content /proc/meminfo
            $memTotalKB = [int64]((($memInfo | Where-Object { $_ -match '^MemTotal:' }) -split '\s+')[1])

            $memAvailLine = $memInfo | Where-Object { $_ -match '^MemAvailable:' } | Select-Object -First 1
            if ($memAvailLine) {
                $memFreeKB = [int64](($memAvailLine -split '\s+')[1])
            }
            else {
                $memFreeLine = $memInfo | Where-Object { $_ -match '^MemFree:' } | Select-Object -First 1
                $memFreeKB = [int64](($memFreeLine -split '\s+')[1])
            }
        }
        else {
            $memTotalBytes = [int64](sysctl -n hw.memsize)
            $memTotalKB = $memTotalBytes / 1KB

            $vmStat = vm_stat
            $pageSize = 4096
            if ($vmStat -match 'page size of (\d+) bytes') { $pageSize = [int]$Matches[1] }

            $freePages = 0
            $inactivePages = 0
            if ($vmStat -match 'Pages free:\s+(\d+)') { $freePages = [int]$Matches[1] }
            if ($vmStat -match 'Pages inactive:\s+(\d+)') { $inactivePages = [int]$Matches[1] }

            $memFreeKB = (($freePages + $inactivePages) * $pageSize) / 1KB
        }

        $disksize = 0
        $diskused = 0
        $drives = [System.IO.DriveInfo]::GetDrives() |
        Where-Object { $_.IsReady -and $_.DriveType -eq 'Fixed' }
        foreach ($drive in $drives) {
            $disksize += $drive.TotalSize
            $diskused += ($drive.TotalSize - $drive.AvailableFreeSpace)
        }

        $ip = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
        Where-Object { $_.OperationalStatus -eq 'Up' -and $_.NetworkInterfaceType -ne 'Loopback' } |
        ForEach-Object { $_.GetIPProperties().UnicastAddresses } |
        Where-Object {
            $_.Address.AddressFamily -eq 'InterNetwork' -and
            $_.Address.IPAddressToString -notmatch '^169\.254\.'
        } |
        Select-Object -First 1 -ExpandProperty Address |
        ForEach-Object { $_.IPAddressToString }

        if (-not $ip) { $ip = '' }
    }

    $messages = @(
        [string]$userName
        "-" * 16
        "OS: $osCaption"
        "CPU: $cpu"
        "GPU: $gpu"
        "Memory: $([math]::Round($memFreeKB / 1MB, 1)) / $([math]::Round($memTotalKB / 1MB, 1)) GB"
        "Disk: $([math]::Round($diskused / 1GB, 1)) / $([math]::Round($disksize / 1GB, 1)) GB"
        "IP: $ip"
    )

    if ($fetchType -eq 0) {
        $imgW = 32
        $imgH = 16

        $defaultImg = Join-Path (Join-Path $NyaDir "res") "137508504_p0_cut.png"
        $imgPath = if ($fetchPic -ne "" -and (Test-Path $fetchPic)) { $fetchPic } else { $defaultImg }

        Show-Image $imgPath $imgW $imgH
        Write-Host "$([char]27)[$($imgH)A" -NoNewline
        $messages | ForEach-Object {
            Write-Host "$([char]27)[$($imgW)C" -NoNewline
            Write-Host " | " -NoNewline
            [Console]::WriteLine($_)
        }

        for ($i = 0; $i -lt ($imgH - $messages.Count); $i++) {
            Write-Host ""
        }
    }
    elseif ($fetchType -eq 1 -and (Get-Command ConvertTo-Sixel -ErrorAction SilentlyContinue)) {
        $imgW = 32
        $imgH = 16

        $defaultImg = Join-Path (Join-Path $NyaDir "res") "137508504_p0_cut.png"
        $imgPath = if ($fetchPic -ne "" -and (Test-Path $fetchPic)) { $fetchPic } else { $defaultImg }

        Show-SixelImage $imgPath $imgW $imgH
        Write-Host "$([char]27)[$($imgH)A" -NoNewline
        $messages | ForEach-Object {
            Write-Host "$([char]27)[$($imgW)C" -NoNewline
            Write-Host " | " -NoNewline
            [Console]::WriteLine($_)
        }

        for ($i = 0; $i -lt ($imgH - $messages.Count); $i++) {
            Write-Host ""
        }
    }
    else {
        $asciiPath = Join-Path (Join-Path $NyaDir "res") "ascii.txt"
        $asciiArt = Get-Content $asciiPath -Raw -Encoding UTF8
        $asciiLines = $asciiArt -split "`n"

        $asciiMaxWidth = 0
        foreach ($line in $asciiLines) {
            if ($line.Length -gt $asciiMaxWidth) {
                $asciiMaxWidth = $line.Length
            }
        }

        $totalLines = [Math]::Max($asciiLines.Count, $messages.Count)
        for ($i = 0; $i -lt $totalLines; $i++) {
            $line = if ($i -lt $asciiLines.Count) { $asciiLines[$i] } else { "" }
            $line = $line.PadRight($asciiMaxWidth)

            if ($i -lt $messages.Count) {
                $line = "$line    | $($messages[$i])"
            }

            Write-Host $line
        }
    }
}