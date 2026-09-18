function Get-DamerauLevenshteinDistance {
    param(
        [string]$A,
        [string]$B
    )
    $A = $A.ToLowerInvariant()
    $B = $B.ToLowerInvariant()
    $n = $A.Length
    $m = $B.Length
    if ($n -eq 0) { return $m }
    if ($m -eq 0) { return $n }
    $d = New-Object 'int[,]' -ArgumentList ($n + 1), ($m + 1)
    for ($i = 0; $i -le $n; $i++) {
        $d.SetValue($i, $i, 0)
    }
    for ($j = 0; $j -le $m; $j++) {
        $d.SetValue($j, 0, $j)
    }
    for ($i = 1; $i -le $n; $i++) {
        for ($j = 1; $j -le $m; $j++) {
            $c = if ($A[$i - 1] -ne $B[$j - 1]) { 1 } else { 0 }
            $del = ([int]$d.GetValue($i - 1, $j)) + 1
            $ins = ([int]$d.GetValue($i, $j - 1)) + 1
            $sub = ([int]$d.GetValue($i - 1, $j - 1)) + $c
            $val = [Math]::Min([Math]::Min($del, $ins), $sub)
            $d.SetValue($val, $i, $j)
            if (
                $i -gt 1 -and $j -gt 1 -and
                $A[$i - 1] -eq $B[$j - 2] -and
                $A[$i - 2] -eq $B[$j - 1]
            ) {
                $trans = ([int]$d.GetValue($i - 2, $j - 2)) + 1
                if ($trans -lt [int]$d.GetValue($i, $j)) {
                    $d.SetValue($trans, $i, $j)
                }
            }
        }
    }
    return [int]$d.GetValue($n, $m)
}

function Find-FuzzyCommand {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name,
        [int]$MaxDistance = 3,
        [int]$Top = 10
    )

    $commands = Get-Command * -CommandType All -ErrorAction SilentlyContinue |
    ForEach-Object {
        [PSCustomObject]@{
            Name        = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            CommandType = $_.CommandType
            Source      = $_.Source
        }
    } |
    Sort-Object Name -Unique

    $results = foreach ($command in $commands) {

        $distance = Get-DamerauLevenshteinDistance $Name $command.Name

        if ($distance -le $MaxDistance) {
            [PSCustomObject]@{
                Distance = $distance
                Command  = $command.Name
                Type     = $command.CommandType
                Source   = $command.Source
            }
        }
    }

    $results |
    Sort-Object Distance, Command |
    Select-Object -First $Top
}

class NyaColor {
    [byte]$R
    [byte]$G
    [byte]$B

    NyaColor([byte]$r, [byte]$g, [byte]$b) {
        $this.R = $r
        $this.G = $g
        $this.B = $b
    }

    NyaColor([string]$hex) {
        $hex = $hex.TrimStart('#')
        if ($hex.Length -eq 6) {
            $this.R = [Convert]::ToByte($hex.Substring(0, 2), 16)
            $this.G = [Convert]::ToByte($hex.Substring(2, 2), 16)
            $this.B = [Convert]::ToByte($hex.Substring(4, 2), 16)
        }
        else { throw "颜色必须是 #RRGGBB" }
    }

    [string] ToHex() {
        return "#{0:X2}{1:X2}{2:X2}" -f $this.R, $this.G, $this.B
    }

    [System.ConsoleColor] ToConsoleColor() {
        $palette = @(
            @([System.ConsoleColor]::Black, 0, 0, 0),
            @([System.ConsoleColor]::DarkBlue, 0, 0, 128),
            @([System.ConsoleColor]::DarkGreen, 0, 128, 0),
            @([System.ConsoleColor]::DarkCyan, 0, 128, 128),
            @([System.ConsoleColor]::DarkRed, 128, 0, 0),
            @([System.ConsoleColor]::DarkMagenta, 128, 0, 128),
            @([System.ConsoleColor]::DarkYellow, 128, 128, 0),
            @([System.ConsoleColor]::Gray, 192, 192, 192),
            @([System.ConsoleColor]::DarkGray, 128, 128, 128),
            @([System.ConsoleColor]::Blue, 0, 0, 255),
            @([System.ConsoleColor]::Green, 0, 255, 0),
            @([System.ConsoleColor]::Cyan, 0, 255, 255),
            @([System.ConsoleColor]::Red, 255, 0, 0),
            @([System.ConsoleColor]::Magenta, 255, 0, 255),
            @([System.ConsoleColor]::Yellow, 255, 255, 0),
            @([System.ConsoleColor]::White, 255, 255, 255)
        )
        $best = [System.ConsoleColor]::Black
        $bestDistance = [double]::PositiveInfinity
        foreach ($item in $palette) {
            $cr = [int]$item[1]
            $cg = [int]$item[2]
            $cb = [int]$item[3]
            $dr = [int]$this.R - $cr
            $dg = [int]$this.G - $cg
            $db = [int]$this.B - $cb
            $distance = $dr * $dr + $dg * $dg + $db * $db
            if ($distance -lt $bestDistance) {
                $bestDistance = $distance
                $best = $item[0]
            }
        }
        return $best
    }
}

function Format-Text {
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Text,
        [Parameter(Position = 1)]
        [object] $Foreground,
        [Parameter(Position = 2)]
        [object] $Background
    )

    function Convert-HexToRgb([string] $Color) {
        $Color = $Color.TrimStart('#')
        if ($Color -notmatch '^[0-9a-fA-F]{6}$') {
            throw "Invalid color: #$Color"
        }
        @(
            [Convert]::ToInt32($Color.Substring(0, 2), 16)
            [Convert]::ToInt32($Color.Substring(2, 2), 16)
            [Convert]::ToInt32($Color.Substring(4, 2), 16)
        )
    }

    function Get-RgbFromColor([object] $Color) {
        if ($Color -is [NyaColor]) {
            return @($Color.R, $Color.G, $Color.B)
        }
        elseif ($Color -is [string]) {
            return Convert-HexToRgb $Color
        }
        elseif ($Color -is [System.ConsoleColor]) {
            $consoleColorMap = @{
                Black       = @(0, 0, 0)
                DarkBlue    = @(0, 0, 128)
                DarkGreen   = @(0, 128, 0)
                DarkCyan    = @(0, 128, 128)
                DarkRed     = @(128, 0, 0)
                DarkMagenta = @(128, 0, 128)
                DarkYellow  = @(128, 128, 0)
                Gray        = @(192, 192, 192)
                DarkGray    = @(128, 128, 128)
                Blue        = @(0, 0, 255)
                Green       = @(0, 255, 0)
                Cyan        = @(0, 255, 255)
                Red         = @(255, 0, 0)
                Magenta     = @(255, 0, 255)
                Yellow      = @(255, 255, 0)
                White       = @(255, 255, 255)
            }
            return $consoleColorMap[$($Color.ToString())]
        }
        else {
            throw "Invalid color type: $($Color.GetType().Name)"
        }
    }
    $esc = [char]27
    $codes = @()
    if ($Foreground) {
        $rgb = Get-RgbFromColor $Foreground
        $codes += "38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])"
    }
    if ($Background) {
        $rgb = Get-RgbFromColor $Background
        $codes += "48;2;$($rgb[0]);$($rgb[1]);$($rgb[2])"
    }
    if ($codes.Count -eq 0) {
        return $Text
    }
    return "${esc}[$($codes -join ';')m$Text${esc}[0m"
}

function Save-Cache {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] $Data
    )

    $dir = Split-Path -Parent $Path
    if ($dir -and !(Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $tmp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $json = $Data | ConvertTo-Json -Depth 20 -Compress
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-Cache {
    param([Parameter(Mandatory)] [string]$Path)

    if (!(Test-Path -LiteralPath $Path)) { return $null }

    $json = [System.IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($json)) { return $null }

    return $json | ConvertFrom-Json
}


function JoinPath {
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [Parameter(Mandatory, Position = 1, ValueFromRemainingArguments)]
        [string[]]$ChildPath
    )

    $result = $Path
    foreach ($p in $ChildPath) {
        $result = [IO.Path]::Combine($result, $p)
    }
    return $result
}
