function Get-WallpaperPath {
    $wtSettingsPath = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (Test-Path $wtSettingsPath) {
        try {
            $wtSettings = Get-Content -Path $wtSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $bgImage = $wtSettings.profiles.defaults.backgroundImage
            if (-not $bgImage) {
                foreach ($profile in $wtSettings.profiles.list) {
                    if ($profile.backgroundImage) {
                        $bgImage = $profile.backgroundImage
                        break
                    }
                }
            }
            if ($bgImage -and (Test-Path $bgImage)) {
                return $bgImage
            }
        }
        catch {
        }
    }
    return (Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallPaper).WallPaper
}

function Get-MainColors {
    param(
        [string]$CachePath = "$NyaDir/cache/colors.json",
        [int]$ColorCount = 8
    )
    $wallpaperPath = Get-WallpaperPath
    $cacheFile = $CachePath
    $cache = Get-Cache -Path $cacheFile
    $colorHexes = $null

    if ($cache -and $cache.wallpaper -eq $wallpaperPath) {
        try {
            $lastModified = (Get-Item -LiteralPath $wallpaperPath -ErrorAction Stop).LastWriteTime.ToString('o')
            if ($cache.lastModified -eq $lastModified) {
                $colorHexes = $cache.colors
            }
        }
        catch {}
    }

    if (-not $colorHexes) {
        $output = & get_colors $wallpaperPath $ColorCount 2>&1
        if ($LASTEXITCODE -eq 0) {
            $colorHexes = @($output | ForEach-Object {
                    if ($_ -match '^#([0-9A-F]{6})') { "#$($Matches[1])" }
                })
        }
        if ($colorHexes.Count -gt 0) {
            try { $lastModified = (Get-Item -LiteralPath $wallpaperPath -ErrorAction Stop).LastWriteTime.ToString('o') }
            catch { $lastModified = [DateTime]::Now.ToString('o') }
            Save-Cache -Path $cacheFile -Data ([PSCustomObject]@{
                    wallpaper    = $wallpaperPath
                    lastModified = $lastModified
                    colors       = $colorHexes
                })
        }
    }

    $colors = [ordered]@{}
    $i = 0
    foreach ($colorHex in $colorHexes) {
        $colors["_$i"] = [NyaColor]::new($colorHex)
        $i++
    }

    return $colors
}
