# gitbash installer for Windows PowerShell - runs install.sh with Git for Windows' bash.
#
#   irm https://raw.githubusercontent.com/jaggli/gitbash/main/install.ps1 | iex
#
# Takes the same environment variables as install.sh, e.g.:
#   $env:GITBASH_VERSION = '2.0.1'; irm https://raw.githubusercontent.com/jaggli/gitbash/main/install.ps1 | iex
#
# No 'exit' in here: run with iex, it would close the PowerShell window.

$ErrorActionPreference = 'Stop'

# Git's bin\bash.exe (it puts git and the Unix tools on PATH, unlike usr\bin\bash.exe)
function Find-GitBash {
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($git) {
        # git.exe is in <Git>\cmd, <Git>\bin or <Git>\mingw64\bin
        $dir = Split-Path $git.Source
        foreach ($root in @((Split-Path $dir), (Split-Path (Split-Path $dir)))) {
            if ($root -and (Test-Path (Join-Path $root 'bin\bash.exe'))) {
                return Join-Path $root 'bin\bash.exe'
            }
        }
    }
    foreach ($key in 'HKLM:\SOFTWARE\GitForWindows', 'HKCU:\SOFTWARE\GitForWindows') {
        $root = (Get-ItemProperty $key -ErrorAction SilentlyContinue).InstallPath
        if ($root -and (Test-Path (Join-Path $root 'bin\bash.exe'))) {
            return Join-Path $root 'bin\bash.exe'
        }
    }
    return $null
}

$bash = Find-GitBash
if (-not $bash) {
    throw 'gitbash needs Git for Windows. Install it with: winget install Git.Git'
}

& $bash -c 'curl -fsSL https://raw.githubusercontent.com/jaggli/gitbash/main/install.sh | sh'
if ($LASTEXITCODE -ne 0) {
    throw 'gitbash install failed.'
}
Write-Host ''
Write-Host 'For the PowerShell integration, see https://github.com/jaggli/gitbash#windows'
