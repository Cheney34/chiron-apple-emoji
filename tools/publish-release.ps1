<#
publish-release.ps1

Creates (or reuses) the GitHub release for a tag, then uploads the three
distribution artifacts as release assets.

Why a local script: the 188 MB module zip cannot be pushed through the
connector API (text only) and this agent session cannot spawn processes.
Running here, in a real terminal, has neither limit.

Token resolution order:
  1. -Token parameter
  2. GH_TOKEN / GITHUB_TOKEN environment variable
  3. "git credential fill" -> whatever Git Credential Manager stored when you
     pushed. No PAT needed if that still works.
  4. interactive prompt (input hidden)

NOTE: this file is intentionally ASCII-only. Windows PowerShell 5.1 decodes
BOM-less .ps1 files with the ANSI code page, so non-ASCII literals would turn
into mojibake. File names containing Chinese are matched by wildcard instead.

Usage:
  powershell -ExecutionPolicy Bypass -File tools\publish-release.ps1
  powershell -ExecutionPolicy Bypass -File tools\publish-release.ps1 -Force   # re-upload
#>
[CmdletBinding()]
param(
    [string] $Repo      = 'Cheney34/chiron-apple-emoji',
    [string] $Tag       = 'v6.2',
    [string] $AssetsDir = (Join-Path $env:USERPROFILE 'Downloads'),
    [string] $NotesFile = '',
    [string] $Token     = '',
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

function Say  ($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "    OK   $m" -ForegroundColor Green }
function Warn2($m) { Write-Host "    !!   $m" -ForegroundColor Yellow }

# Invoke-RestMethod does not always populate ErrorDetails; fall back to reading
# the raw response stream so GitHub's own message is never swallowed.
# Windows PowerShell 5.1's ConvertTo-Json turns a long string into
# {"value": "...", ...} instead of a plain JSON string. GitHub then answers with
# 422: For 'properties/body', {"value" => ...} is not of type 'string'.
# So escape and assemble the payload by hand - deterministic, no surprises.
function New-JsonString([string] $s) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $s.ToCharArray()) {
        $code = [int] $ch
        if     ($ch -eq '"')   { [void]$sb.Append('\"') }
        elseif ($ch -eq '\')   { [void]$sb.Append('\\') }
        elseif ($code -eq 8)   { [void]$sb.Append('\b') }
        elseif ($code -eq 12)  { [void]$sb.Append('\f') }
        elseif ($code -eq 10)  { [void]$sb.Append('\n') }
        elseif ($code -eq 13)  { [void]$sb.Append('\r') }
        elseif ($code -eq 9)   { [void]$sb.Append('\t') }
        elseif ($code -lt 32)  { [void]$sb.Append(('\u{0:x4}' -f $code)) }
        else                   { [void]$sb.Append($ch) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Get-ErrorBody($record) {
    try {
        if ($record.ErrorDetails -and $record.ErrorDetails.Message) {
            return $record.ErrorDetails.Message
        }
    } catch { }
    try {
        $resp = $record.Exception.Response
        if ($resp) {
            $stream = $resp.GetResponseStream()
            if ($stream) {
                $reader = New-Object IO.StreamReader -ArgumentList $stream
                $text = $reader.ReadToEnd()
                $reader.Dispose()
                return $text
            }
        }
    } catch { }
    if ($record.Exception) { return $record.Exception.Message }
    return ''
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $NotesFile) { $NotesFile = Join-Path $repoRoot 'docs\release-notes.md' }

# Everything below also lands in release.log next to the repo, so the run can be
# inspected after the fact without copying text out of the console.
$logPath = Join-Path $repoRoot 'release.log'
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

# ---------------------------------------------------------------- assets ----
# Pattern matching keeps non-ASCII (the APK name uses a middle dot and a
# Chinese word) out of this file. Name is what shows up on the release page.
$plan = @(
    [pscustomobject]@{ Pattern = '*iosemoji-1.7.apk';           Name = 'AppleEmoji_Sogou_LSPosed_v1.7.apk' },
    [pscustomobject]@{ Pattern = '*_v6.2_AppleEmoji_*.mtz';     Name = 'Chiron-Merriweather_v6.2_AppleEmoji.mtz' },
    [pscustomobject]@{ Pattern = 'AppleEmoji_Chiron_v5.0_hd.zip'; Name = 'AppleEmoji_Chiron_v5.0_hd.zip' }
)

Say "looking for artifacts in $AssetsDir"
$resolved = @()
foreach ($p in $plan) {
    $hit = Get-ChildItem -LiteralPath $AssetsDir -Filter $p.Pattern -File -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $hit) { throw "missing artifact matching '$($p.Pattern)' in $AssetsDir" }
    $mb = [math]::Round($hit.Length / 1MB, 1)
    Ok ("{0,-46} {1,8} MB" -f $p.Name, $mb)
    $resolved += [pscustomobject]@{ Path = $hit.FullName; Name = $p.Name; Size = $hit.Length }
}

$totalMB = [math]::Round((($resolved | Measure-Object -Property Size -Sum).Sum) / 1MB, 1)
Say "total to upload: $totalMB MB"

# ----------------------------------------------------------------- token ----
function Resolve-Token {
    param([string] $Explicit)

    if ($Explicit) { return $Explicit }
    foreach ($n in @('GH_TOKEN', 'GITHUB_TOKEN')) {
        $v = [Environment]::GetEnvironmentVariable($n)
        if ($v) { Ok "using token from `$env:$n"; return $v }
    }

    Say "asking Git Credential Manager for a stored token"
    try {
        $probe = "protocol=https`nhost=github.com`n`n"
        $lines = $probe | & git credential fill 2>$null
        foreach ($line in @($lines)) {
            if ($line -match '^password=(.+)$') {
                Ok "got a credential from git ($($Matches[1].Substring(0,4))...)"
                return $Matches[1]
            }
        }
    } catch {
        Warn2 "git credential fill failed: $($_.Exception.Message)"
    }

    Warn2 "no stored credential. Paste a PAT with 'repo' scope (input is hidden)."
    Write-Host "    create one at https://github.com/settings/tokens" -ForegroundColor DarkGray
    $sec = Read-Host -Prompt '    token' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try   { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

$Token = Resolve-Token -Explicit $Token
if (-not $Token) { throw 'no token' }

$auth = @{
    Authorization = "token $Token"
    Accept        = 'application/vnd.github+json'
    'User-Agent'  = 'chiron-release-script'
}

Say 'verifying token'
try {
    $probeResp = Invoke-WebRequest -Uri 'https://api.github.com/user' -Headers $auth -UseBasicParsing -Method Get
    $me = $probeResp.Content | ConvertFrom-Json
    Ok "authenticated as $($me.login)"
    $scopes = $probeResp.Headers['x-oauth-scopes']
    if ($scopes) {
        $scopeStr = ($scopes -join ',').Trim()
        Ok "token scopes: $scopeStr"
        if ($scopeStr -notmatch 'repo' -and $scopeStr -notmatch 'public_repo') {
            Warn2 "this token has NO repo/public_repo scope - creating a release will fail."
            Warn2 "Git Credential Manager tokens are read/write only for git; you likely need a PAT."
        }
    } else {
        Warn2 'no x-oauth-scopes header (fine-grained PAT or GitHub App token)'
    }
} catch {
    $code = 'n/a'
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    $msg = ''
    $body = Get-ErrorBody $_
    if ($body) { $msg = ' :: ' + $body }
    throw "token rejected (HTTP $code)$msg"
}

# --------------------------------------------------------------- release ----
$bodyText = ''
if (Test-Path -LiteralPath $NotesFile) {
    $bodyText = Get-Content -LiteralPath $NotesFile -Raw -Encoding UTF8
    Ok "release body from $(Split-Path $NotesFile -Leaf) ($($bodyText.Length) chars)"
} else {
    Warn2 "no notes file at $NotesFile, release body will be empty"
}

Say "creating release $Tag"
$json = '{' +
    '"tag_name":'                + (New-JsonString $Tag)      + ',' +
    '"target_commitish":"main",' +
    '"name":'                    + (New-JsonString $Tag)      + ',' +
    '"body":'                    + (New-JsonString $bodyText) + ',' +
    '"draft":false,"prerelease":false}'
$bytes = [Text.Encoding]::UTF8.GetBytes($json)

Say "checking access to $Repo"
try {
    $repoInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo" -Headers $auth
    Ok ("repo: private={0}  default_branch={1}" -f $repoInfo.private, $repoInfo.default_branch)
    if ($repoInfo.permissions) {
        Ok ("permissions: push={0} admin={1} maintain={2}" -f `
            $repoInfo.permissions.push, $repoInfo.permissions.admin, $repoInfo.permissions.maintain)
        if (-not $repoInfo.permissions.push) { Warn2 'this token has NO push permission on the repo' }
    }
} catch {
    Warn2 "repo lookup failed: $($_.Exception.Message)"
}
Ok ("payload: tag_name={0} target_commitish=main body={1} chars" -f $Tag, $bodyText.Length)

$rel = $null
$createErr = ''
$createCode = ''
try {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases" -Method Post `
        -Headers $auth -ContentType 'application/json; charset=utf-8' -Body $bytes
    Ok "created release id=$($rel.id)"
} catch {
    if ($_.Exception.Response) { $createCode = [int]$_.Exception.Response.StatusCode }
    $createErr = Get-ErrorBody $_
    Warn2 ("POST /releases failed: HTTP " + $createCode)
    if ($createErr) { Warn2 ("github said: " + $createErr) } else { Warn2 ("error: " + $_.Exception.Message) }
}

if (-not $rel) {
    Say "looking up an existing release for tag $Tag"
    try {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag" -Headers $auth
        Ok "reusing release id=$($rel.id)"
    } catch {
        $c = 'n/a'
        if ($_.Exception.Response) { $c = [int]$_.Exception.Response.StatusCode }
        Warn2 "GET /releases/tags/$Tag -> HTTP $c"
    }
}

if (-not $rel) {
    Say 'scanning the release list'
    try {
        $all = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases?per_page=100" -Headers $auth
        foreach ($r in @($all)) {
            if ($r -and $r.tag_name -eq $Tag) { $rel = $r }
        }
        if ($rel) { Ok "found release id=$($rel.id) in the list" }
    } catch {
        Warn2 "release list failed: $($_.Exception.Message)"
    }
}

if (-not $rel) {
    if ($createErr -match 'already_exists') {
        Warn2 'GitHub says a release for this tag already exists, yet it is not readable.'
        Warn2 'That happens when it is a DRAFT and the token cannot list drafts.'
        Warn2 'Open https://github.com/' + $Repo + '/releases , switch the Drafts tab,'
        Warn2 'delete the v6.2 draft, then re-run this script.'
    } elseif ($createCode -eq 403 -or $createCode -eq 404) {
        Warn2 'no write access with this token.'
        Warn2 'Git Credential Manager tokens are accepted by git but may not be allowed to'
        Warn2 'create releases. Make a PAT with the repo scope and pass it explicitly:'
        Warn2 '  https://github.com/settings/tokens -> Generate new token (classic) -> repo'
        Warn2 '  $env:GH_TOKEN="ghp_xxx"; .\tools\publish-release.ps1'
    } elseif ($createCode -eq 422) {
        Warn2 'GitHub rejected the payload (422). The exact reason is the "github said:" line above.'
    } else {
        Warn2 "unexpected status ($createCode). Full text is in the 'github said:' line above."
    }
    throw "could not create or find a release for tag $Tag"
}

# ------------------------------------------------ publish draft / fix body ----
# A reused release may be a draft (the release page hides drafts, which is why
# GET /releases/tags/ returns 404 for them while POST returns 422 already_exists).
if ($rel.draft -eq $true) {
    Say 'this release is still a draft - publishing it'
} else {
    Say 'refreshing release name and body'
}
$patchJson = '{"name":' + (New-JsonString $Tag) + ',"body":' + (New-JsonString $bodyText) + ',"draft":false}'
try {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/$($rel.id)" -Method Patch `
        -Headers $auth -ContentType 'application/json; charset=utf-8' `
        -Body ([Text.Encoding]::UTF8.GetBytes($patchJson))
    Ok "release ready: draft=$($rel.draft)  url=$($rel.html_url)"
} catch {
    $c = 'n/a'
    if ($_.Exception.Response) { $c = [int]$_.Exception.Response.StatusCode }
    $m = ''
    $eb = Get-ErrorBody $_
    if ($eb) { $m = ' :: ' + $eb }
    Warn2 "could not update the release (HTTP $c)$m - continuing anyway"
}

# ---------------------------------------------------------------- upload ----
$existing = @{}
try {
    $list = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/$($rel.id)/assets?per_page=100" -Headers $auth
    foreach ($a in @($list)) { if ($a -and $a.name) { $existing[$a.name] = $a.id } }
} catch { }

Add-Type -AssemblyName System.Net.Http
$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromHours(3)
$client.DefaultRequestHeaders.Authorization =
    New-Object System.Net.Http.Headers.AuthenticationHeaderValue -ArgumentList 'token', $Token
[void]$client.DefaultRequestHeaders.UserAgent.ParseAdd('chiron-release-script/1.0')
[void]$client.DefaultRequestHeaders.Accept.ParseAdd('application/vnd.github+json')

$failed = @()

foreach ($item in $resolved) {
    $name = $item.Name
    $src  = $item.Path

    if ($existing.ContainsKey($name)) {
        if (-not $Force) {
            Say "skip $name (already uploaded; pass -Force to replace)"
            continue
        }
        Say "replacing existing asset $name"
        try {
            Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/assets/$($existing[$name])" `
                -Headers $auth -Method Delete | Out-Null
        } catch {
            Warn2 "could not delete old asset: $($_.Exception.Message)"
        }
    }

    $url = "https://uploads.github.com/repos/$Repo/releases/$($rel.id)/assets?name=" + [uri]::EscapeDataString($name)
    $mb  = [math]::Round($item.Size / 1MB, 1)
    Say "uploading $name ($mb MB)"

    $ok = $false
    $fs = $null
    try {
        $fs      = [IO.File]::OpenRead($src)
        $content = New-Object System.Net.Http.StreamContent -ArgumentList $fs
        $content.Headers.ContentType =
            New-Object System.Net.Http.Headers.MediaTypeHeaderValue -ArgumentList 'application/octet-stream'
        $total = $item.Size

        $task = $client.PostAsync($url, $content)
        $clock = [Diagnostics.Stopwatch]::StartNew()
        while (-not $task.IsCompleted) {
            Start-Sleep -Milliseconds 500
            $pos = 0
            try { $pos = $fs.Position } catch { }
            $pct = 0
            if ($total -gt 0) { $pct = [int](($pos / $total) * 100) }
            $nowMB = [math]::Round($pos / 1MB, 1)
            Write-Progress -Activity "uploading $name" `
                -Status ("$nowMB / $mb MB  ({0}%, {1}s)" -f $pct, [int]$clock.Elapsed.TotalSeconds) `
                -PercentComplete $pct
        }
        Write-Progress -Activity "uploading $name" -Completed

        $resp = $task.GetAwaiter().GetResult()
        $text = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) {
            Warn2 ("HTTP " + [int]$resp.StatusCode + " : " + $text)
        } else {
            $obj = $text | ConvertFrom-Json
            Ok ("uploaded -> " + $obj.browser_download_url)
            $ok = $true
        }
    } catch {
        Warn2 "HttpClient upload failed: $($_.Exception.Message)"
    } finally {
        if ($fs) { try { $fs.Dispose() } catch { } }
    }

    if (-not $ok) {
        $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
        if (Test-Path $curl) {
            Warn2 'retrying with curl.exe'
            & $curl -sS -X POST $url `
                -H "Authorization: token $Token" `
                -H 'Content-Type: application/octet-stream' `
                -H 'Accept: application/vnd.github+json' `
                --data-binary "@$src" -o "$env:TEMP\upload-result.json"
            if ($LASTEXITCODE -eq 0) {
                try {
                    $obj = Get-Content "$env:TEMP\upload-result.json" -Raw | ConvertFrom-Json
                    if ($obj.browser_download_url) { Ok ("uploaded -> " + $obj.browser_download_url); $ok = $true }
                } catch { }
            }
        }
    }

    if (-not $ok) { $failed += $name }
}

# --------------------------------------------------------------- summary ----
Write-Host ''
Say 'summary'
try {
    $final = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/$($rel.id)/assets?per_page=100" -Headers $auth
    foreach ($a in @($final)) {
        if ($a -and $a.name) {
            Ok ("{0,-46} {1,8} MB  {2}" -f $a.name, [math]::Round($a.size / 1MB, 1), $a.state)
        }
    }
} catch { }

Write-Host ''
Write-Host ("release page : https://github.com/$Repo/releases/tag/$Tag") -ForegroundColor White
Write-Host ("full log     : $logPath") -ForegroundColor DarkGray
try { Stop-Transcript | Out-Null } catch { }
if ($failed.Count -gt 0) {
    Warn2 ("these failed, re-run the script or drag them in the browser: " + ($failed -join ', '))
    exit 1
}
Ok 'all artifacts uploaded'
exit 0
