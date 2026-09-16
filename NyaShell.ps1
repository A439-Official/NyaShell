$isWin = if ($PSVersionTable.PSEdition -eq 'Desktop') { $true } else { $IsWindows }

if ($isWin) {
    # set code page to UTF-8
    chcp 65001 > $null
    [Console]::OutputEncoding = [Console]::InputEncoding
}


$NyaDir = $PSScriptRoot


# read config
if (-not( Test-Path "$NyaDir/config.psd1" -PathType Leaf)) {
    Copy-Item "$NyaDir/res/config.psd1" "$NyaDir/config.psd1" 
}
$NyaConfig = Get-Content -Path "$NyaDir/config.psd1" -Encoding UTF8 -Raw | Import-PowerShellDataFile 

# import modules
if ($isWin) {
    $env:Path = $env:Path + [IO.Path]::PathSeparator + "$NyaDir/tools"
}
Get-ChildItem -Path "$NyaDir/src" -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

function Out-Default {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [System.Management.Automation.PSObject]$InputObject
    )
    begin {
        $errs = [System.Collections.Generic.List[object]]::new()
        $others = [System.Collections.Generic.List[object]]::new()
    }
    process {
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $errs.Add($_)
        }
        elseif ($null -ne $InputObject) {
            $others.Add($InputObject)
        }
    }
    end {
        if ($others.Count) {
            $others | Microsoft.PowerShell.Core\Out-Default
        }
        foreach ($e in $errs) {

            $msg = $e.Exception.Message
            $loc = $e.InvocationInfo
            $where = if ($loc.ScriptName) {
                "$([IO.Path]::GetFileName($loc.ScriptName)):$($loc.ScriptLineNumber)"
            }
            elseif ($loc.MyCommand) {
                $loc.MyCommand.Name
            }
            else { 'interactive' }

            switch ($e.Exception) {
                { $_ -is [System.Management.Automation.CommandNotFoundException] } {
                    $badCmd = $e.Exception.CommandName

                    # $rightCmds = Find-FuzzyCommand $badCmd -Top 5
                    # if (-not $rightCmds.Count -eq 0) {
                    #     Write-Host (Format-Text "可能的:" $NyaColors._4)
                    #     foreach ($rightCmd in $rightCmds) {
                    #         Write-Host (Format-Text "- $($rightCmd.Command)" $NyaColors._4)
                    #     }
                    # }

                    # Write-Host ""

                    $e | Microsoft.PowerShell.Core\Out-Default
                }
                default {
                    $e | Microsoft.PowerShell.Core\Out-Default
                }
            }
        }
    }
}

function prompt {
    $path = $PWD.Path
    $homePath = [Environment]::GetFolderPath("UserProfile")
    if ($path -eq $homePath) {
        $path = "~"
    }
    elseif ($path.StartsWith($homePath + "\")) {
        $path = "~" + $path.Substring($homePath.Length)
    }
    (Format-Text "Nya" $NyaColors._1) + " $path> "
}

# Clear hook
function Clear-Host {
    [Console]::Clear()

    foreach ($color in $NyaColors.Values) {
        Write-Host (Format-Text " " "#000000" $color) -NoNewline
    }
    Write-Host ""

    Write-Host ""
    Write-Host (Format-Text "=^･ω･^=" $NyaColors._2) -NoNewline
    Write-Host (Format-Text " Nya Shell" $NyaColors._3)
    Write-Host ""
}

$NyaColors = @{
    _0 = [NyaColor]::new("#ffffff")
    _1 = [NyaColor]::new("#ffffff")
    _2 = [NyaColor]::new("#ffffff")
    _3 = [NyaColor]::new("#ffffff")
    _4 = [NyaColor]::new("#ffffff")
    _5 = [NyaColor]::new("#ffffff")
    _6 = [NyaColor]::new("#ffffff")
    _7 = [NyaColor]::new("#ffffff")
}

if ($isWin) {
    $NyaColors = Get-MainColors
}


Set-PSReadLineOption -Colors @{
    "Command" = $NyaColors._1.ToHex()
    "Comment" = $NyaColors._2.ToHex()
    # "ContinuationPrompt"
    # "Default"
    # "Emphasis"
    "Error"   = $NyaColors._4.ToHex()
    # "Keyword"
    # "Member"
    # "Number"
    # "Operator"
    # "Parameter"
    # "Selection"
    "String"  = $NyaColors._3.ToHex()
    # "Type"
    # "Variable"
}

Clear-Host
