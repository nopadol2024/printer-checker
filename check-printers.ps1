param(
    [string]$ConfigPath = "config.json",
    [string]$PrintersPath = "printers.csv"
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Split-Path -IsAbsolute $ConfigPath)) { $ConfigPath = Join-Path $ScriptDir $ConfigPath }
if (-not (Split-Path -IsAbsolute $PrintersPath)) { $PrintersPath = Join-Path $ScriptDir $PrintersPath }

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

function Test-PrinterPort {
    param([string]$IP, [int]$Port = 9100, [int]$TimeoutMs = 3000)

    $pingOk = $false
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $reply = $ping.Send($IP, 2000)
        $pingOk = ($reply.Status -eq "Success")
    } catch {
        $pingOk = $false
    }

    if ($pingOk) {
        return @{ Status = "Online"; Ping = $true; Port = $false }
    } else {
        return @{ Status = "Offline"; Ping = $false; Port = $false }
    }
}

function Get-OrCreateLabel {
    param(
        [string]$BaseUrl,
        [string]$Ws,
        [string]$ProjId,
        [string]$ApiKey,
        [string]$LabelName,
        [string]$LabelColor
    )

    $headers = @{ "X-API-Key" = $ApiKey }
    $listUrl = "$BaseUrl/api/v1/workspaces/$Ws/projects/$ProjId/labels/"

    try {
        $existing = Invoke-RestMethod -Uri $listUrl -Headers $headers -Method Get
        $match = $existing.results | Where-Object { $_.name -eq $LabelName }
        if ($match) {
            Write-Log "Found existing label '$LabelName' (ID: $($match.id))"
            return $match.id
        }
    } catch {
        Write-Log "Warning: Could not list labels, will try to create anyway"
    }

    $body = @{ name = $LabelName; color = $LabelColor } | ConvertTo-Json
    try {
        $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $req = [System.Net.WebRequest]::Create($listUrl)
        $req.Method = "POST"
        $req.ContentType = "application/json; charset=utf-8"
        $req.Headers.Add("X-API-Key", $ApiKey)
        $reqStream = $req.GetRequestStream()
        $reqStream.Write($utf8Bytes, 0, $utf8Bytes.Length)
        $reqStream.Close()
        $resp = $req.GetResponse()
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $resultJson = $reader.ReadToEnd()
        $reader.Close()
        $result = $resultJson | ConvertFrom-Json
        Write-Log "Created label '$LabelName' (ID: $($result.id))"
        return $result.id
    } catch {
        Write-Log "Error creating label: $_"
        return $null
    }
}

function Get-TypeIcon {
    param([string]$Type)
    $icons = @{
        printer    = [char]0xD83D + [char]0xDDB6
        cctv       = [char]0xD83D + [char]0xDCF7
        "access point" = [char]0xD83D + [char]0xDCE1
        "ip phone"  = [char]0x260E
        server     = [char]0xD83D + [char]0xDCC1
        iot        = [char]0xD83D + [char]0xDCF6
        isp        = [char]0xD83C + [char]0xDF10
        cloud      = [char]0x2601
    }
    if ($icons.ContainsKey($Type.ToLower())) { return $icons[$Type.ToLower()] }
    return [char]0x2753
}

function Get-BranchName {
    param([string]$Code)
    $names = @{ S01 = "Head Office"; S02 = "Home Expert"; S03 = "Stock9"; CLOUD = "Cloud Services" }
    if ($names.ContainsKey($Code.ToUpper())) { return $names[$Code.ToUpper()] }
    return $Code
}

function ConvertTo-HtmlTable {
    param([array]$Results, [string]$DateStr, [string]$TimeStr)

    $branchGroups = $Results | Group-Object Branch

    $sections = ""
    foreach ($bg in $branchGroups) {
        $branchName = Get-BranchName -Code $bg.Name
        $sections += "<tr style=`"background:#e5e7eb`"><td colspan=`"3`" style=`"padding:10px 12px;border:1px solid #d1d5db;font-weight:800;font-size:15px`">[ $($bg.Name) ] $branchName ($($bg.Count))</td></tr>"

        $typeGroups = $bg.Group | Group-Object Type
        foreach ($tg in $typeGroups) {
            $typeIcon = Get-TypeIcon -Type $tg.Name
            $sections += "<tr style=`"background:#f3f4f6`"><td colspan=`"3`" style=`"padding:6px 12px 6px 28px;border:1px solid #e5e7eb;font-weight:600;font-size:13px`">$typeIcon $($tg.Name.ToUpper()) ($($tg.Count))</td></tr>"

            foreach ($r in $tg.Group) {
                $statusIcon = switch ($r.Status) {
                    "Online"    { '<div style="display:inline-flex;align-items:center;gap:6px;background:#ecfdf5;color:#059669;padding:4px 12px;border-radius:20px;font-size:13px;font-weight:600">' + [char]0x2705 + ' Online</div>' }
                    "PortError" { '<div style="display:inline-flex;align-items:center;gap:6px;background:#fffbeb;color:#d97706;padding:4px 12px;border-radius:20px;font-size:13px;font-weight:600">' + [char]0x26A0 + [char]0xFE0F + ' Port Error</div>' }
                    "Offline"   { '<div style="display:inline-flex;align-items:center;gap:6px;background:#fef2f2;color:#dc2626;padding:4px 12px;border-radius:20px;font-size:13px;font-weight:600">' + [char]0x274C + ' Offline</div>' }
                    default     { '<div style="display:inline-flex;align-items:center;gap:6px;background:#f3f4f6;color:#6b7280;padding:4px 12px;border-radius:20px;font-size:13px;font-weight:600">Unknown</div>' }
                }
                $sections += @"
<tr>
    <td style="padding:6px 12px;border:1px solid #e5e7eb">$($r.Name)</td>
    <td style="padding:6px 12px;border:1px solid #e5e7eb"><code>$($r.IP)</code></td>
    <td style="padding:6px 12px;border:1px solid #e5e7eb">$statusIcon</td>
</tr>
"@
            }
        }
    }

    return @"
<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;padding:16px">
    <h2 style="margin-bottom:16px">Device Status Report - $DateStr</h2>
    <p style="color:#6b7280;margin-bottom:16px">Checked at: $TimeStr</p>
    <table style="border-collapse:collapse;width:100%;max-width:750px;border:1px solid #d1d5db">
        <thead>
            <tr style="background:#f9fafb">
                <th style="padding:8px 12px;border:1px solid #d1d5db;text-align:left">Device Name</th>
                <th style="padding:8px 12px;border:1px solid #d1d5db;text-align:left">IP Address</th>
                <th style="padding:8px 12px;border:1px solid #d1d5db;text-align:left">Status</th>
            </tr>
        </thead>
        <tbody>
            $sections
        </tbody>
    </table>
    <hr style="margin:16px 0;border:none;border-top:1px solid #e5e7eb">
    <p style="color:#6b7280;font-size:12px">Auto-generated by Device Checker Script</p>
</div>
"@
}

function Invoke-PlanePost {
    param([string]$Url, [string]$ApiKey, [string]$JsonBody)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonBody)
    $req = [System.Net.WebRequest]::Create($Url)
    $req.Method = "POST"
    $req.ContentType = "application/json; charset=utf-8"
    $req.Headers.Add("X-API-Key", $ApiKey)
    $reqStream = $req.GetRequestStream()
    $reqStream.Write($bytes, 0, $bytes.Length)
    $reqStream.Close()
    $resp = $req.GetResponse()
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
    $resultJson = $reader.ReadToEnd()
    $reader.Close()
    return $resultJson | ConvertFrom-Json
}

function Get-PlaneGet {
    param([string]$Url, [string]$ApiKey)

    $req = [System.Net.WebRequest]::Create($Url)
    $req.Method = "GET"
    $req.Headers.Add("X-API-Key", $ApiKey)
    $resp = $req.GetResponse()
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
    $resultJson = $reader.ReadToEnd()
    $reader.Close()
    return $resultJson | ConvertFrom-Json
}

function Get-CurrentCycleId {
    param([string]$BaseUrl, [string]$Ws, [string]$ProjId, [string]$ApiKey)

    $today = Get-Date
    $url = "$BaseUrl/api/v1/workspaces/$Ws/projects/$ProjId/cycles/"
    $data = Get-PlaneGet -Url $url -ApiKey $ApiKey
    foreach ($cycle in $data.results) {
        if ($cycle.start_date -and $cycle.end_date) {
            $start = [DateTime]$cycle.start_date
            $end = [DateTime]$cycle.end_date
            if ($today -ge $start -and $today -le $end) {
                Write-Log "Auto-detected cycle: '$($cycle.name)' (ID: $($cycle.id))"
                return $cycle.id
            }
        }
    }
    Write-Log "Warning: No active cycle found for today"
    return $null
}

# --- MAIN ---
Write-Log "Starting Printer Check..."

# Load config
if (-not (Test-Path $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$configJson = Get-Content $ConfigPath -Raw -Encoding UTF8
$cfg = $configJson | ConvertFrom-Json
Write-Log "Loaded config"

# Load printers
if (-not (Test-Path $PrintersPath)) { throw "Printers file not found: $PrintersPath" }
$printers = Import-Csv $PrintersPath -Encoding UTF8
Write-Log "Loaded $($printers.Count) printer(s) from $PrintersPath"

# Check each printer
$results = @()
foreach ($p in $printers) {
    Write-Log "Checking $($p.name) ($($p.ip))..."
    $check = Test-PrinterPort -IP $p.ip
    $results += [PSCustomObject]@{
        Name   = $p.name
        IP     = $p.ip
        Type   = if ($p.type) { $p.type } else { "printer" }
        Branch = if ($p.branch) { $p.branch.ToUpper() } else { "S01" }
        Status = $check.Status
        Ping   = $check.Ping
        Port   = $check.Port
    }
    Write-Log "  -> $($check.Status)"
}

# Summary
$onlineCount = ($results | Where-Object { $_.Status -eq "Online" }).Count
$portErrorCount = ($results | Where-Object { $_.Status -eq "PortError" }).Count
$offlineCount = ($results | Where-Object { $_.Status -eq "Offline" }).Count
$total = $results.Count

Write-Log "--- Summary ---"
Write-Log "  Online: $onlineCount/$total"
if ($portErrorCount -gt 0) { Write-Log "  Port Error: $portErrorCount/$total" }
if ($offlineCount -gt 0)  { Write-Log "  Offline: $offlineCount/$total" }
$branchStats = $results | Group-Object Branch | ForEach-Object { "$($_.Name): $($_.Count)" }
Write-Log "  By branch: $($branchStats -join ', ')"
$typeStats = $results | Group-Object Type | ForEach-Object { "$($_.Name): $($_.Count)" }
Write-Log "  By type: $($typeStats -join ', ')"

# Determine priority
$priority = if ($offlineCount -gt 0 -or $portErrorCount -gt 0) { "high" } else { "none" }
Write-Log "Card priority: $priority"

# --- Plane API ---
$base   = $cfg.plane.base_url
$ws     = $cfg.plane.workspace_slug
$projId = $cfg.plane.project_id
$key    = $cfg.plane.api_key

# 1. Get or create printer label
Write-Log "Ensuring label '$($cfg.plane.label_name)' exists..."
$labelId = Get-OrCreateLabel -BaseUrl $base -Ws $ws -ProjId $projId -ApiKey $key -LabelName $cfg.plane.label_name -LabelColor $cfg.plane.label_color

# 2. Create work item
$today = Get-Date -Format "yyyy-MM-dd"
$dateStr = Get-Date -Format "dd/MM/yyyy"
$timeStr = Get-Date -Format "HH:mm:ss"
$wiName = "Device Status Report - $(Get-Date -Format 'dd-MM-yyyy')"
$wiDesc = ConvertTo-HtmlTable -Results $results -DateStr $dateStr -TimeStr $timeStr

$wiBodyParams = @{
    name             = $wiName
    description_html = $wiDesc
    priority         = $priority
    state            = $cfg.plane.state_todo
    start_date       = $today
}
if ($labelId) {
    $wiBodyParams.labels = @($labelId)
}
$wiJson = $wiBodyParams | ConvertTo-Json -Depth 10

$wiUrl = "$base/api/v1/workspaces/$ws/projects/$projId/work-items/"
Write-Log "Creating work item: '$wiName'..."
try {
    $wiResult = Invoke-PlanePost -Url $wiUrl -ApiKey $key -JsonBody $wiJson
    $wiId = $wiResult.id
    Write-Log "Work item created! ID: $wiId"
} catch {
    Write-Log "ERROR creating work item: $_"
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $errBody = $reader.ReadToEnd()
        Write-Log "Response: $errBody"
    }
    exit 1
}

# 3. Add to module
if ($cfg.plane.module_id) {
    $modUrl = "$base/api/v1/workspaces/$ws/projects/$projId/modules/$($cfg.plane.module_id)/module-issues/"
    Write-Log "Adding to module 'daily'..."
    try {
        $modJson = @{ issues = @($wiId) } | ConvertTo-Json
        Invoke-PlanePost -Url $modUrl -ApiKey $key -JsonBody $modJson | Out-Null
        Write-Log "Added to module OK"
    } catch {
        Write-Log "Warning: Could not add to module: $_"
    }
}

# 4. Add to cycle (auto-detect)
$cycleId = Get-CurrentCycleId -BaseUrl $base -Ws $ws -ProjId $projId -ApiKey $key
if ($cycleId) {
    $cycUrl = "$base/api/v1/workspaces/$ws/projects/$projId/cycles/$cycleId/cycle-issues/"
    Write-Log "Adding to cycle..."
    try {
        $cycJson = @{ issues = @($wiId) } | ConvertTo-Json
        Invoke-PlanePost -Url $cycUrl -ApiKey $key -JsonBody $cycJson | Out-Null
        Write-Log "Added to cycle OK"
    } catch {
        Write-Log "Warning: Could not add to cycle: $_"
    }
}

Write-Log "Done! Card created successfully."
