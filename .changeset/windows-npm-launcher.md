---
"gitbash": patch
---

Windows: `gitbash` now works in PowerShell and cmd after `npm i -g gitbash` (it ran WSL's bash instead of Git's). The PowerShell integration is one line in your `$PROFILE`: `gitbash --init --shell=pwsh | Out-String | Invoke-Expression`
