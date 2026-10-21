$ErrorActionPreference = 'Stop'
$inv = [System.Globalization.CultureInfo]::InvariantCulture

# --- Čas (Praha, hlídá letní/zimní čas) ---
try { $tz = [TimeZoneInfo]::FindSystemTimeZoneById('Europe/Prague') }
catch { $tz = [TimeZoneInfo]::FindSystemTimeZoneById('Central Europe Standard Time') }
$now      = [TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $tz)
$updated  = $now.ToString('dd.MM.yyyy HH:mm:ss', $inv)
$todayStr = $now.ToString('yyyy-MM-dd', $inv)

$historyFolder = 'stats_history'
$logsFolder    = 'logs'
$null = New-Item -ItemType Directory -Force -Path 'stats', $historyFolder, $logsFolder

# --- UUID -> nick ---
$jmena = @{
    '10d807ae-f713-4d9d-966d-a6e7b4bddafd' = 'dufe_com'
    '4b91ee4a-88d0-48f0-b111-8f8e6e3647b7' = 'KarlTheBroken'
    '90afe98a-4c6a-4469-959e-d55070e4b6b8' = 'Kathryn_Reed'
    '953decf3-5ac0-4108-965f-3b82cea52143' = 'Alex_Reed'
    'aa14ea23-012a-48b8-b39d-3e280496e83a' = 'Johny_Reed'
    'bd265486-b561-4510-860c-76a0bc9ea3ae' = 'ettelwen'
}

# --- NAČTENÍ VŠECH STATISTIK (kategorie/klíč -> hodnota) ---
$players = [ordered]@{}
foreach ($file in (Get-ChildItem 'stats/*.json' -ErrorAction SilentlyContinue)) {
    $uuid = $file.BaseName
    $nick = if ($jmena.ContainsKey($uuid)) { $jmena[$uuid] } else { $uuid }
    $json = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
    $flat = [ordered]@{}
    if ($json.stats) {
        foreach ($cat in $json.stats.PSObject.Properties) {
            $catName = $cat.Name -replace '^minecraft:', ''
            foreach ($st in $cat.Value.PSObject.Properties) {
                $name = $st.Name -replace '^minecraft:', ''
                $flat["$catName/$name"] = $st.Value
            }
        }
    }
    $players[$nick] = $flat
}

if ($players.Count -eq 0) { throw 'Nenalezeny žádné soubory statistik, index.html se nepřepisuje.' }

# =====================================================================
# --- LOGY ZE SERVERU: stažení z FTP (/logs) ---
# Údaje se berou z proměnných prostředí (GitHub Secrets):
#   FTP_HOST   např. ftp.hostify.cz   (volitelně i s portem: host:21)
#   FTP_USER, FTP_PASS
#   FTP_LOGS_PATH   výchozí /logs
#   FTP_SSL         true = explicitní FTPS (výchozí false)
#   FTP_SKIP_CERT_CHECK   1 = nekontrolovat certifikát (jen u FTPS)
# Když FTP_HOST není nastaven, stahování se přeskočí a použijí se logy
# ve složce logs/ a uložená historie smrtí.
# Chyba FTP nikdy neshodí generování – vypíše se jen varování.
# =====================================================================
$ftpHost     = $env:FTP_HOST
# Kandidáti na složku s logy (použije se první, která jde vypsat). Vlastní cestu lze zadat v FTP_LOGS_PATH.
$ftpLogsCandidates = if ($env:FTP_LOGS_PATH) { @($env:FTP_LOGS_PATH) } else { @('/minecraft/Forever Reeds/logs', '/logs') }
$ftpLogsCandidates = @($ftpLogsCandidates | ForEach-Object { '/' + $_.Trim('/') })
$ftpSsl      = ($env:FTP_SSL -eq 'true' -or $env:FTP_SSL -eq '1')

function New-FtpRequest([string]$path, [string]$method) {
    $req = [System.Net.FtpWebRequest]::Create("ftp://$ftpHost$path")
    $req.Method           = $method
    $req.Credentials      = New-Object System.Net.NetworkCredential($env:FTP_USER, $env:FTP_PASS)
    $req.UsePassive       = $true
    $req.UseBinary        = $true
    $req.KeepAlive        = $false
    $req.EnableSsl        = $ftpSsl
    $req.Timeout          = 30000
    $req.ReadWriteTimeout = 60000
    return $req
}

function Get-FtpListing([string]$dir) {
    $resp = (New-FtpRequest "$dir/" 'NLST').GetResponse()
    try {
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $txt = $sr.ReadToEnd()
    } finally { $resp.Dispose() }
    return @($txt -split "`r?`n" | Where-Object { $_ -ne '' } | ForEach-Object { ($_ -split '/')[-1] })
}

function Get-FtpFile([string]$remote, [string]$local) {
    $tmp = "$local.part"
    $resp = (New-FtpRequest $remote 'RETR').GetResponse()
    try {
        $in  = $resp.GetResponseStream()
        $out = [System.IO.File]::Create($tmp)
        try { $in.CopyTo($out) } finally { $out.Dispose() }
    } finally { $resp.Dispose() }
    Move-Item -Path $tmp -Destination $local -Force
}

function Get-FtpModified([string]$remote) {
    $resp = (New-FtpRequest $remote 'MDTM').GetResponse()
    try { return $resp.LastModified.ToUniversalTime() } finally { $resp.Dispose() }
}

$ftpDownloaded = 0
if ($ftpHost -and $env:FTP_USER) {
    try {
        if ($ftpSsl -and $env:FTP_SKIP_CERT_CHECK -eq '1') {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        }
        $remoteNames = @(); $ftpLogsPath = $null
        foreach ($cand in $ftpLogsCandidates) {
            try {
                $names = Get-FtpListing $cand
                if (@($names | Where-Object { $_ -match '\.log(\.gz)?$' }).Count -gt 0) { $ftpLogsPath = $cand; $remoteNames = $names; break }
            } catch { Write-Host "FTP: složka '$cand' nejde vypsat ($($_.Exception.Message))" }
        }
        if (-not $ftpLogsPath) { throw "nenalezena složka s logy (zkoušeno: $($ftpLogsCandidates -join ', '))" }
        Write-Host "FTP: logy ze složky $ftpLogsPath"
        foreach ($name in $remoteNames) {
            $isArchive = $name -match '^\d{4}-\d{2}-\d{2}-\d+\.log\.gz$'
            $isLatest  = $name -eq 'latest.log'
            if (-not ($isArchive -or $isLatest)) { continue }
            $local = Join-Path $logsFolder $name
            # archivní .log.gz se nemění -> stačí stáhnout jednou; latest.log vždy znovu
            if ($isArchive -and (Test-Path $local) -and (Get-Item $local).Length -gt 0) { continue }
            try {
                Get-FtpFile "$ftpLogsPath/$name" $local
                if ($isLatest) {
                    try { (Get-Item $local).LastWriteTimeUtc = Get-FtpModified "$ftpLogsPath/$name" } catch { }
                }
                $ftpDownloaded++
            } catch {
                Write-Warning "FTP: soubor '$name' se nepodařilo stáhnout: $($_.Exception.Message)"
            }
        }
        Write-Host "FTP logy: staženo souborů: $ftpDownloaded"
    } catch {
        Write-Warning "FTP logy se nepodařilo stáhnout: $($_.Exception.Message) – pokračuji s tím, co je uloženo."
    }
} else {
    Write-Host 'FTP_HOST nenastaveno – logy se berou z lokální složky logs/ (stahuje je krok workflow) a z uložené historie.'
}

# --- SMRTI HRÁČŮ Z LOGŮ SERVERU ---
# Řádek smrti: "[čas] [Server thread/INFO]: [System chat: ]Nick <zpráva o smrti>"
$deathRe = '^\[(\d{2}:\d{2}:\d{2})\] \[[^\]]*/INFO\]: (?:System chat: )?([A-Za-z0-9_]{3,16}) ((?:was (?!kicked|banned)|fell |drowned|died|burned to death|tried to |suffocated|starved|withered|hit the ground|went up in flames|walked into|experienced |blew up|froze|discovered |didn.t want|left the world).*)$'

function Read-LogLines([string]$path) {
    if ($path -like '*.gz') {
        $fs = [System.IO.File]::OpenRead($path)
        try {
            $gz = New-Object System.IO.Compression.GZipStream($fs, [System.IO.Compression.CompressionMode]::Decompress)
            $sr = New-Object System.IO.StreamReader($gz, [System.Text.Encoding]::UTF8)
            while ($null -ne ($line = $sr.ReadLine())) { $line }
        } finally { $fs.Dispose() }
    } else {
        Get-Content -Path $path -Encoding utf8
    }
}

$deathsAll  = New-Object System.Collections.Generic.List[object]
$deathSeen  = @{}

function Add-Death([string]$ts, [string]$t, [string]$n, [string]$m) {
    $key = "$ts|$n|$m"
    if ($deathSeen.ContainsKey($key)) { return }          # ochrana proti duplicitám
    $deathSeen[$key] = $true
    $deathsAll.Add([ordered]@{ ts = $ts; t = $t; n = $n; m = $m })
}

# 1) dříve uložená historie (smrti zůstanou, i kdyby server staré logy smazal)
$deathsHistoryFile = Join-Path $historyFolder 'deaths.json'
if (Test-Path $deathsHistoryFile) {
    try {
        foreach ($h in @(Get-Content -Path $deathsHistoryFile -Raw | ConvertFrom-Json)) {
            Add-Death $h.ts $h.t $h.n $h.m
        }
    } catch { Write-Warning "deaths.json se nepodařilo načíst: $($_.Exception.Message)" }
}

# 2) všechny lokální logy
$logFiles = @(Get-ChildItem $logsFolder -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(\d{4}-\d{2}-\d{2}-\d+\.log\.gz|latest\.log)$' })
# soubory chronologicky (2026-10-03-2 před 2026-10-03-10, latest.log nakonec)
$logFiles = @($logFiles | Sort-Object { if ($_.Name -match '^(\d{4}-\d{2}-\d{2})-(\d+)\.log\.gz$') { "$($Matches[1])-" + $Matches[2].PadLeft(4, '0') } else { '9999' } })

$joinRe = '^\[(\d{2}:\d{2}:\d{2})\] \[[^\]]*/INFO\]: (?:System chat: )?([A-Za-z0-9_]{3,16}) (joined|left) the game$'
$stopRe = '^\[(\d{2}:\d{2}:\d{2})\] \[[^\]]*/INFO\]: (?:System chat: )?Stopping (?:the )?server$'
$events = New-Object System.Collections.Generic.List[object]

foreach ($lf in $logFiles) {
    if ($lf.Name -match '^(\d{4}-\d{2}-\d{2})-\d+\.log\.gz$') {
        $day = [DateTime]::ParseExact($Matches[1], 'yyyy-MM-dd', $inv)
    } else {
        $day = [TimeZoneInfo]::ConvertTimeFromUtc($lf.LastWriteTimeUtc, $tz).Date
    }
    foreach ($line in (Read-LogLines $lf.FullName)) {
        if ($line -match $deathRe) {
            $when = $day.Add([TimeSpan]::Parse($Matches[1], $inv))
            Add-Death $when.ToString('yyyy-MM-dd HH:mm:ss', $inv) $when.ToString('dd.MM.yyyy HH:mm:ss', $inv) $Matches[2] $Matches[3]
        } elseif ($line -match $joinRe) {
            $events.Add(@{ w = $day.Add([TimeSpan]::Parse($Matches[1], $inv)); k = $Matches[3]; n = $Matches[2] })
        } elseif ($line -match $stopRe) {
            $events.Add(@{ w = $day.Add([TimeSpan]::Parse($Matches[1], $inv)); k = 'stop'; n = '' })
        }
    }
}

[object[]]$deaths = @($deathsAll | Sort-Object { $_.ts } -Descending)
$deathsFrom = if ($deaths.Count -gt 0) { $deaths[-1].t.Substring(0, 10) } else { '' }

# 3) uložení historie
[System.IO.File]::WriteAllText(
    (Join-Path (Get-Location) $deathsHistoryFile),
    (ConvertTo-Json -InputObject $deaths -Depth 3 -Compress),
    [System.Text.UTF8Encoding]::new($false))

# --- SEZENÍ HRÁČŮ (joined/left) + AKTIVITA ---
$sessSeen = @{}
$sessAll  = New-Object System.Collections.Generic.List[object]

function Add-SessionRaw([string]$n, [string]$s, [string]$e) {
    $key = "$n|$s|$e"
    if ($sessSeen.ContainsKey($key)) { return }
    $sessSeen[$key] = $true
    $sessAll.Add([ordered]@{ n = $n; s = $s; e = $e })
}
function Add-Session([string]$n, [DateTime]$a, [DateTime]$b) {
    $dur = ($b - $a).TotalMinutes
    if ($dur -le 0 -or $dur -gt 960) { return }            # nesmysl (chybějící řádek v logu)
    Add-SessionRaw $n $a.ToString('yyyy-MM-dd HH:mm:ss', $inv) $b.ToString('yyyy-MM-dd HH:mm:ss', $inv)
}

# 1) uložená historie sezení
$sessHistoryFile = Join-Path $historyFolder 'sessions.json'
if (Test-Path $sessHistoryFile) {
    try {
        foreach ($h in @(Get-Content -Path $sessHistoryFile -Raw | ConvertFrom-Json)) { Add-SessionRaw $h.n $h.s $h.e }
    } catch { Write-Warning "sessions.json se nepodařilo načíst: $($_.Exception.Message)" }
}

# 2) sezení z lokálních logů (nedokončená sezení se zahodí; hráč online se dopočítá příště)
$openS = @{}
foreach ($ev in $events) {
    switch ($ev.k) {
        'joined' { $openS[$ev.n] = $ev.w }                  # předchozí nedokončené (pád serveru) se zahodí
        'left'   { if ($openS.ContainsKey($ev.n)) { Add-Session $ev.n $openS[$ev.n] $ev.w; $openS.Remove($ev.n) } }
        'stop'   { foreach ($pn in @($openS.Keys)) { Add-Session $pn $openS[$pn] $ev.w }; $openS.Clear() }
    }
}
[object[]]$sessions = @($sessAll | Sort-Object { $_.s })

# 3) uložení historie sezení
[System.IO.File]::WriteAllText(
    (Join-Path (Get-Location) $sessHistoryFile),
    (ConvertTo-Json -InputObject $sessions -Depth 3 -Compress),
    [System.Text.UTF8Encoding]::new($false))

# 4) agregace: minuty podle (den v týdnu × hodina) a podle dne, pro každého hráče
$actHours = @{}; $actDays = @{}; $actSess = @{}
foreach ($se in $sessions) {
    $a = [DateTime]::ParseExact($se.s, 'yyyy-MM-dd HH:mm:ss', $inv)
    $b = [DateTime]::ParseExact($se.e, 'yyyy-MM-dd HH:mm:ss', $inv)
    $pn = $se.n
    if (-not $actHours.ContainsKey($pn)) { $actHours[$pn] = New-Object 'double[]' 168; $actDays[$pn] = @{}; $actSess[$pn] = 0 }
    $actSess[$pn]++
    $cur = $a
    while ($cur -lt $b) {
        $hourEnd = $cur.Date.AddHours($cur.Hour + 1)
        $segEnd  = if ($b -lt $hourEnd) { $b } else { $hourEnd }
        $mins    = ($segEnd - $cur).TotalMinutes
        $idx     = ((([int]$cur.DayOfWeek) + 6) % 7) * 24 + $cur.Hour      # pondělí = 0
        $actHours[$pn][$idx] += $mins
        $dk = $cur.ToString('yyyy-MM-dd', $inv)
        if ($actDays[$pn].ContainsKey($dk)) { $actDays[$pn][$dk] += $mins } else { $actDays[$pn][$dk] = $mins }
        $cur = $segEnd
    }
}
$aHours = [ordered]@{}; $aDays = [ordered]@{}; $aSess = [ordered]@{}
foreach ($pn in ($actHours.Keys | Sort-Object)) {
    $aHours[$pn] = [double[]]@($actHours[$pn] | ForEach-Object { [Math]::Round($_, 1) })
    $dd = [ordered]@{}
    foreach ($k in ($actDays[$pn].Keys | Sort-Object)) { $dd[$k] = [Math]::Round($actDays[$pn][$k], 1) }
    $aDays[$pn] = $dd
    $aSess[$pn] = $actSess[$pn]
}
$activity = [ordered]@{ hours = $aHours; days = $aDays; sessions = $aSess }

# --- SNAPSHOT: jednou denně (první běh dne = stav na začátku dne) ---
$snapFile = Join-Path $historyFolder "snap_$todayStr.json"
if (-not (Test-Path $snapFile)) {
    [ordered]@{
        taken   = $now.ToString('dd.MM.yyyy HH:mm', $inv)
        players = $players
    } | ConvertTo-Json -Depth 6 -Compress | Set-Content -Path $snapFile -Encoding utf8
}

# Ponecháme posledních 45 snapshotů
$snaps = @(Get-ChildItem "$historyFolder/snap_*.json" | Sort-Object Name)
if ($snaps.Count -gt 45) {
    $snaps | Select-Object -First ($snaps.Count - 45) | Remove-Item -Force
    $snaps = @(Get-ChildItem "$historyFolder/snap_*.json" | Sort-Object Name)
}

# --- VÝPOČET ZMĚN OPROTI SNAPSHOTU ---
function Get-Baseline([int]$daysBack) {
    $target = $now.Date.AddDays(-$daysBack).ToString('yyyy-MM-dd', $inv)
    $cand = $snaps | Where-Object { [string]::CompareOrdinal($_.BaseName, "snap_$target") -le 0 } | Select-Object -Last 1
    $exact = $true
    if (-not $cand) { $cand = $snaps | Select-Object -First 1; $exact = $false }
    $raw = Get-Content -Path $cand.FullName -Raw | ConvertFrom-Json -AsHashtable
    return @{ since = $raw.taken; exact = $exact; players = $raw.players }
}

function Get-Delta($basePlayers) {
    $res = [ordered]@{}
    foreach ($nick in $players.Keys) {
        $cur = $players[$nick]
        $bp  = if ($basePlayers -and $basePlayers.ContainsKey($nick)) { $basePlayers[$nick] } else { @{} }
        $d = [ordered]@{}
        foreach ($k in $cur.Keys) {
            $b = if ($bp.ContainsKey($k)) { [double]$bp[$k] } else { 0 }
            $diff = [Math]::Max(0, [double]$cur[$k] - $b)
            if ($diff -ne 0) { $d[$k] = $diff }
        }
        $res[$nick] = $d
    }
    return $res
}

$periods = [ordered]@{}
foreach ($def in @(@('day', 0), @('week', 6), @('month', 29))) {
    $b = Get-Baseline $def[1]
    $periods[$def[0]] = [ordered]@{
        since = $b.since
        exact = $b.exact
        delta = (Get-Delta $b.players)
    }
}

$avatars = [ordered]@{}
foreach ($kv in $jmena.GetEnumerator()) { $avatars[$kv.Value] = $kv.Key }

$data = [ordered]@{
    updated    = $updated
    current    = $players
    periods    = $periods
    deaths     = $deaths
    deathsInfo = [ordered]@{ files = $logFiles.Count; from = $deathsFrom }
    activity   = $activity
    avatars    = $avatars
}
$dataJson = ($data | ConvertTo-Json -Depth 10 -Compress).Replace('</', '<\/')

# --- HTML ŠABLONA ---
$template = @'
<!DOCTYPE html>
<html lang="cs">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="dark">
<title>Forever Reeds MC Server</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:wght@600;700;800&family=IBM+Plex+Sans:wght@400;500;600&display=swap" rel="stylesheet">
<style>
  :root {
    --bg: #12151b; --panel: #1a1f28; --panel-2: #212835; --line: #2b3342;
    --text: #e7ecf3; --muted: #8d99ab; --emerald: #3ddc97;
    --gold: #f4c95d; --silver: #ffffff; --bronze: #d99a6c; --gray: #98a3b3;
  }
  * { box-sizing: border-box; }
  html, body { height: 100%; margin: 0; overflow: hidden; }
  body { background: var(--bg); color: var(--text); font-family: 'IBM Plex Sans', system-ui, 'Segoe UI', sans-serif; }

  .app { height: 100%; display: flex; flex-direction: column; gap: clamp(8px, 1.4vh, 14px); padding: clamp(10px, 2vh, 24px) clamp(10px, 2vw, 32px); }

  header { display: flex; align-items: center; justify-content: space-between; gap: 16px; flex-wrap: wrap; }
  .brand h1 { margin: 0; font-family: 'Bricolage Grotesque', system-ui, sans-serif; font-weight: 800; font-size: clamp(20px, 3.4vh, 32px); letter-spacing: -0.02em; line-height: 1.1; }
  .update-time { margin-top: 4px; color: var(--muted); font-size: clamp(11px, 1.5vh, 13px); display: flex; align-items: center; gap: 8px; }
  .dot { width: 7px; height: 7px; border-radius: 50%; background: var(--emerald); animation: pulse 2.4s ease-out infinite; }
  @keyframes pulse { 0% { box-shadow: 0 0 0 0 rgba(61,220,151,.55); } 70% { box-shadow: 0 0 0 7px rgba(61,220,151,0); } 100% { box-shadow: 0 0 0 0 rgba(61,220,151,0); } }
  @media (prefers-reduced-motion: reduce) { .dot { animation: none; } }

  .tabs { display: inline-flex; gap: 2px; padding: 4px; background: var(--panel); border: 1px solid var(--line); border-radius: 12px; }
  .tab-btn { font: inherit; font-weight: 500; font-size: clamp(12px, 1.7vh, 14px); color: var(--muted); background: transparent; border: 0; padding: 7px 14px; border-radius: 8px; cursor: pointer; white-space: nowrap; transition: background .15s, color .15s; }
  .tab-btn:hover { color: var(--text); background: var(--panel-2); }
  .tab-btn:focus-visible, .ctl:focus-visible { outline: 2px solid var(--emerald); outline-offset: 2px; }
  .tab-btn.active { background: var(--emerald); color: #08261a; font-weight: 600; }

  .toolbar { display: flex; align-items: center; gap: 10px 14px; flex-wrap: wrap; }
  .note { color: var(--muted); font-size: clamp(11px, 1.5vh, 13px); }
  .spacer { flex: 1; }
  .controls { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
  .ctl { font: inherit; font-size: clamp(12px, 1.7vh, 14px); color: var(--text); background: var(--panel); border: 1px solid var(--line); border-radius: 10px; padding: 7px 12px; }
  input.ctl { width: clamp(140px, 16vw, 220px); }
  select.ctl { max-width: 180px; }
  .switch { display: inline-flex; align-items: center; gap: 8px; cursor: pointer; font-size: clamp(12px, 1.7vh, 14px); color: var(--text); user-select: none; }
  .switch input { position: absolute; opacity: 0; }
  .slider { width: 36px; height: 20px; border-radius: 999px; background: var(--panel-2); border: 1px solid var(--line); position: relative; transition: background .15s; }
  .slider::after { content: ''; position: absolute; top: 2px; left: 2px; width: 14px; height: 14px; border-radius: 50%; background: var(--muted); transition: transform .15s, background .15s; }
  .switch input:checked + .slider { background: var(--emerald); border-color: var(--emerald); }
  .switch input:checked + .slider::after { transform: translateX(16px); background: #08261a; }
  .switch input:focus-visible + .slider { outline: 2px solid var(--emerald); outline-offset: 2px; }

  main { flex: 1; min-height: 0; }
  .view { height: 100%; }
  .card { height: 100%; background: var(--panel); border: 1px solid var(--line); border-radius: 14px; overflow: auto; }
  .card.map { overflow: hidden; }
  .card iframe { width: 100%; height: 100%; border: 0; display: block; }
  .empty { padding: 40px; text-align: center; color: var(--muted); }

  table { width: 100%; border-collapse: separate; border-spacing: 0; table-layout: fixed; font-size: clamp(11px, 1.8vh, 15px); font-variant-numeric: tabular-nums; }
  table.fit { height: 100%; min-height: 540px; }
  table.tall td { height: 34px; }
  th, td { padding: 0 clamp(8px, 1vw, 16px); text-align: left; vertical-align: middle; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; border-bottom: 1px solid var(--line); }
  tbody tr:last-child td { border-bottom: 0; }
  thead th { position: sticky; top: 0; z-index: 2; background: var(--panel-2); height: 40px; font-family: 'Bricolage Grotesque', system-ui, sans-serif; font-weight: 700; font-size: clamp(12px, 1.9vh, 16px); color: var(--text); }
  tbody tr:hover td { background: rgba(255,255,255,.035); }

  .stat-name { width: clamp(170px, 17vw, 250px); color: var(--muted); font-weight: 500; position: sticky; left: 0; z-index: 1; background: var(--panel); border-right: 1px solid var(--line); }
  thead th.stat-name { z-index: 3; background: var(--panel-2); color: var(--muted); }
  tbody tr:hover td.stat-name { background: #1e2430; }

  .server-total { color: var(--emerald); font-weight: 600; background: rgba(61,220,151,.06); }
  thead th.server-total { background: #1f3a33; color: var(--emerald); }

  td.r1 { color: var(--gold); font-weight: 600; background: rgba(244,201,93,.08); }
  tbody td { color: var(--gray); }
  td.r2 { color: var(--silver); }
  td.r3 { color: var(--bronze); }
  td.z { color: #5d6879; }
  .medal { margin-left: 6px; font-size: .9em; }
  .unit { color: var(--muted); font-weight: 400; font-size: .9em; }
  td.r1 .unit, td.r2 .unit { color: inherit; opacity: .7; }
  tr.grp td { background: var(--panel-2); color: var(--emerald); font-family: 'Bricolage Grotesque', system-ui, sans-serif; font-weight: 700; height: 34px; }
  tr.grp:hover td { background: var(--panel-2); }

  .fun { padding: clamp(10px, 1.6vh, 18px); display: flex; flex-direction: column; gap: 12px; }
  .kpis { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 10px; }
  .kpi { background: var(--panel-2); border: 1px solid var(--line); border-radius: 12px; padding: 10px 14px; }
  .kpi b { display: block; font-family: 'Bricolage Grotesque', system-ui, sans-serif; font-size: clamp(18px, 3vh, 26px); font-weight: 800; color: var(--emerald); }
  .kpi span { color: var(--muted); font-size: 12px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 10px; }
  .fc { background: var(--panel-2); border: 1px solid var(--line); border-radius: 12px; padding: 12px 14px; }
  .fc h3 { margin: 0; font-family: 'Bricolage Grotesque', system-ui, sans-serif; font-size: 15px; font-weight: 700; }
  .fc .sub { color: var(--muted); font-size: 12px; margin: 2px 0 8px; }
  .fr { display: grid; grid-template-columns: 24px 1fr auto; align-items: center; column-gap: 8px; padding: 3px 0; font-size: 13px; font-variant-numeric: tabular-nums; }
  .fr .nm { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .fr .val { font-weight: 600; }
  .fr .val small { color: var(--muted); font-weight: 400; }
  .fr:first-of-type .val { color: var(--gold); }
  .bar { grid-column: 2 / 4; height: 3px; border-radius: 2px; background: var(--line); margin-top: 3px; }
  .bar i { display: block; height: 100%; border-radius: 2px; background: var(--emerald); }
  .none { color: var(--muted); font-size: 13px; padding: 6px 0; }

  /* záložka Overview (dashboard) */
  .ov-head { padding: 2px 2px 4px; }
  .ov-head h2 { margin: 0 0 3px; font-family: 'Bricolage Grotesque', system-ui, sans-serif; font-weight: 800; font-size: clamp(17px, 2.6vh, 22px); }
  .ov-head p { margin: 0; color: var(--muted); font-size: 13px; }
  .ov-section { display: flex; flex-direction: column; margin-top: 2px; }
  .ov-section > h3 { margin: 0 0 8px; font-family: 'Bricolage Grotesque', system-ui, sans-serif; font-size: 13px; font-weight: 700; color: var(--muted); text-transform: uppercase; letter-spacing: .05em; }

  .roster { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 10px; }
  .rp { display: flex; align-items: center; gap: 10px; background: var(--panel-2); border: 1px solid var(--line); border-radius: 12px; padding: 9px 12px; }
  .rp-av { position: relative; width: 38px; height: 38px; border-radius: 10px; flex: none; display: flex; align-items: center; justify-content: center; font-weight: 700; font-size: 13px; color: #08261a; font-family: 'Bricolage Grotesque', system-ui, sans-serif; overflow: hidden; }
  .rp-av img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; image-rendering: pixelated; }
  .rp-name { font-weight: 600; font-size: 14px; display: flex; align-items: center; gap: 5px; overflow: hidden; }
  .rp-name > span:first-child { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .rp-sub { color: var(--muted); font-size: 12px; margin-top: 1px; }

  .ov-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(190px, 1fr)); gap: 10px; }
  .ov-tile { text-align: left; background: var(--panel-2); border: 1px solid var(--line); border-radius: 12px; padding: 14px; cursor: pointer; color: var(--text); font: inherit; transition: border-color .15s, transform .15s; }
  .ov-tile:hover { border-color: var(--emerald); transform: translateY(-1px); }
  .ov-tile:focus-visible { outline: 2px solid var(--emerald); outline-offset: 2px; }
  .ov-tile .ti { font-size: 20px; line-height: 1; }
  .ov-tile h4 { margin: 8px 0 2px; font-family: 'Bricolage Grotesque', system-ui, sans-serif; font-size: 14px; }
  .ov-tile p { margin: 0; color: var(--muted); font-size: 12px; }

  .ov-deaths { background: var(--panel-2); border: 1px solid var(--line); border-radius: 12px; overflow: hidden; }
  .ov-deaths .dr { display: flex; align-items: center; gap: 10px; padding: 9px 12px; border-bottom: 1px solid var(--line); font-size: 13px; }
  .ov-deaths .dr:last-child { border-bottom: 0; }
  .ov-deaths .dr .when { color: var(--muted); font-size: 12px; white-space: nowrap; }
  .ov-deaths .dr .who { font-weight: 600; white-space: nowrap; }
  .ov-deaths .dr .cause { color: var(--gray); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .ov-more { align-self: flex-start; margin-top: 10px; background: transparent; border: 1px solid var(--line); color: var(--muted); font: inherit; font-size: 12px; padding: 7px 14px; border-radius: 999px; cursor: pointer; }
  .ov-more:hover { color: var(--text); border-color: var(--emerald); }

  [hidden] { display: none !important; }

  /* karty statistik (používají se na telefonu) */
  .sg { margin: 16px 2px 6px; font-family: 'Bricolage Grotesque', system-ui, sans-serif; font-size: 15px; font-weight: 700; color: var(--emerald); }
  .sc { background: var(--panel); border: 1px solid var(--line); border-radius: 12px; padding: 10px 10px 8px; margin-bottom: 8px; }
  .sh { display: flex; justify-content: space-between; align-items: baseline; gap: 10px; margin: 0 4px 6px; }
  .sl { font-weight: 600; }
  .st { color: var(--emerald); font-weight: 600; font-variant-numeric: tabular-nums; white-space: nowrap; }
  .pr { display: grid; grid-template-columns: 28px 1fr auto; align-items: center; padding: 7px 8px; border-radius: 8px; font-variant-numeric: tabular-nums; background: linear-gradient(90deg, rgba(61,220,151,.14) var(--w, 0%), transparent var(--w, 0%)); }
  .pr + .pr { margin-top: 2px; }
  .pn { color: var(--muted); font-size: .9em; }
  .pnm { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; padding-right: 8px; }
  .pv { white-space: nowrap; font-weight: 500; color: var(--gray); }
  .pr.r1 .pv { color: var(--gold); font-weight: 600; }
  .pr.r2 .pv { color: var(--silver); }
  .pr.r3 .pv { color: var(--bronze); }
  .pr.z { opacity: .45; }
  details.more > summary { list-style: none; cursor: pointer; color: var(--muted); font-size: 13px; padding: 8px 8px 4px; }
  details.more > summary::-webkit-details-marker { display: none; }
  details.more[open] > summary { color: var(--text); }

  /* záložka Deaths */
  .dtw { background: var(--panel-2); border: 1px solid var(--line); border-radius: 12px; overflow-x: auto; }
  table.dt { table-layout: auto; min-width: 360px; }
  table.dt td.cause { white-space: normal; color: var(--text); }
  table.dt td.when { color: var(--muted); }
  table.dt td.who { color: var(--emerald); font-weight: 600; }
  table.dt tbody td { height: 34px; }

  /* záložka Activity */
  .apanel { background: var(--panel-2); border: 1px solid var(--line); border-radius: 12px; padding: 12px 14px; }
  .apanel h3 { margin: 0; font-family: 'Bricolage Grotesque', system-ui, sans-serif; font-size: 15px; font-weight: 700; }
  .apanel .sub { color: var(--muted); font-size: 12px; margin: 2px 0 10px; }
  .hm { max-width: 980px; }
  .hm-g { display: grid; grid-template-columns: 34px repeat(24, minmax(0, 1fr)); gap: 3px; align-items: center; }
  .hm-g .c { aspect-ratio: 1; min-height: 11px; border-radius: 3px; }
  .hm-g .hl, .hm-g .dl { font-size: 11px; color: var(--muted); text-align: center; }
  .hm-g .dl { text-align: left; }
  .cal-wrap { overflow-x: auto; padding-bottom: 4px; }
  .cal { display: flex; gap: 3px; width: max-content; }
  .cal .wk { display: flex; flex-direction: column; gap: 3px; }
  .cal .wl { height: 14px; font-size: 10px; color: var(--muted); white-space: nowrap; overflow: visible; }
  .cal .wd { height: 13px; font-size: 10px; line-height: 13px; color: var(--muted); padding-right: 4px; }
  .cal .d { width: 13px; height: 13px; border-radius: 3px; }
  .cal .d.nil { background: transparent; }
  .legend { display: flex; align-items: center; gap: 4px; margin-top: 8px; color: var(--muted); font-size: 11px; }
  .legend i { width: 13px; height: 13px; border-radius: 3px; display: inline-block; }

  @media (max-width: 720px) {
    html, body { height: auto; min-height: 100%; overflow: auto; -webkit-text-size-adjust: 100%; }
    .app { height: auto; min-height: 100vh; min-height: 100dvh; padding: 12px 12px calc(76px + env(safe-area-inset-bottom)); gap: 10px; }
    header { gap: 4px; }
    .brand h1 { font-size: 22px; }
    .update-time { font-size: 12px; margin-top: 2px; }

    #main-tabs { position: fixed; left: 0; right: 0; bottom: 0; z-index: 50; display: flex; gap: 0; border-radius: 0; border-width: 1px 0 0 0; padding: 6px 8px calc(6px + env(safe-area-inset-bottom)); background: rgba(26,31,40,.96); backdrop-filter: blur(8px); -webkit-backdrop-filter: blur(8px); }
    #main-tabs .tab-btn { flex: 1; padding: 10px 2px; text-align: center; font-size: 12px; line-height: 1.2; white-space: normal; }

    .toolbar { display: contents; }
    #period-tabs { display: flex; position: sticky; top: 8px; z-index: 30; box-shadow: 0 0 0 8px var(--bg); }
    #period-tabs .tab-btn { flex: 1; padding: 10px 2px; text-align: center; font-size: 13px; }
    .spacer { display: none; }
    .note { font-size: 12px; margin-top: -2px; }
    .controls { width: 100%; }
    input.ctl { flex: 1; width: auto; min-width: 0; font-size: 16px; }
    select.ctl { flex: 1 1 100%; max-width: none; width: 100%; font-size: 16px; }

    main { flex: 1; }
    .view { height: auto; }
    .card { height: auto; overflow: visible; background: none; border: 0; border-radius: 0; }
    .card.map { height: calc(100vh - 160px); height: calc(100dvh - 160px - env(safe-area-inset-bottom)); overflow: hidden; background: var(--panel); border: 1px solid var(--line); border-radius: 14px; }
    .fun { padding: 0; }
    .kpis { grid-template-columns: repeat(2, 1fr); }
    .grid { grid-template-columns: 1fr; }
  }
</style>
</head>
<body>
<div class="app">
  <header>
    <div class="brand">
      <h1>Forever Reeds</h1>
      <div class="update-time"><span class="dot"></span>Updated __UPDATED__</div>
    </div>
    <nav class="tabs" id="main-tabs">
      <button class="tab-btn" data-view="overview">Overview 🏠</button>
      <button class="tab-btn" data-view="stats">Stats 📈</button>
      <button class="tab-btn" data-view="fun">Fun facts ✨</button>
      <button class="tab-btn" data-view="deaths">Deaths 💀</button>
      <button class="tab-btn" data-view="activity">Activity 🔥</button>
      <button class="tab-btn" data-view="map">World map 🗺️</button>
    </nav>
  </header>

  <div class="toolbar" id="toolbar">
    <nav class="tabs" id="period-tabs">
      <button class="tab-btn" data-period="all">Lifetime 🏆</button>
      <button class="tab-btn" data-period="month">Month 📅</button>
      <button class="tab-btn" data-period="week">Week 📊</button>
      <button class="tab-btn" data-period="day">Day ⚡</button>
    </nav>
    <span class="note" id="note"></span>
    <div class="spacer"></div>
    <div class="controls" id="statsControls">
      <input class="ctl" type="search" id="q" placeholder="Search stats…" aria-label="Search stats">
      <label class="switch"><input type="checkbox" id="showAll"><span class="slider"></span><span>Show all stats</span></label>
      <select class="ctl" id="cat" aria-label="Category"></select>
    </div>
    <div class="controls" id="deathControls" hidden>
      <select class="ctl" id="deathPlayer" aria-label="Player"></select>
    </div>
    <div class="controls" id="actControls" hidden>
      <select class="ctl" id="actPlayer" aria-label="Player"></select>
    </div>
  </div>

  <main>
    <section class="view" id="view-data"><div class="card" id="content"></div></section>
    <section class="view" id="view-map" style="display:none"><div class="card map"><iframe id="map-frame" data-src="mapa/index.html" title="World map"></iframe></div></section>
  </main>
</div>

<script>
(function () {
  'use strict';
  var DATA = __DATA__;

  var PERIOD_LABEL = { all: 'Lifetime', month: 'last 30 days', week: 'last 7 days', day: 'today' };
  var STATE_KEYS = { 'custom/time_since_death': 1, 'custom/time_since_rest': 1 };
  var CAT_NAMES = { highlights: '★ Highlights', custom: 'General', mined: 'Mined', crafted: 'Crafted', used: 'Used', broken: 'Broken', picked_up: 'Picked up', dropped: 'Dropped', killed: 'Killed', killed_by: 'Killed by' };
  var CAT_ORDER = ['highlights', 'custom', 'mined', 'crafted', 'used', 'broken', 'picked_up', 'dropped', 'killed', 'killed_by'];
  var NOT_PLACED = /minecart|boat|sword|axe|pickaxe|shovel|hoe|shear|flint|bucket|potion|apple|stew|bread|pie|beef|pork|chicken|mutton|salmon|cod|cookie|carrot|potato|kelp|melon|berries|soup/;
  var MEDAL = { 1: '👑', 2: '🥈', 3: '🥉' };

  var CURATED = [
    { k: 'hours',      label: '⏱️ Time Played', time: true },
    { k: 'deaths',     label: '💀 Deaths', low: true },
    { k: 'sinceDeath', label: '🛡️ Time Since Last Death', unit: 'hrs', dec: 1, noTotal: true },
    { k: 'dmgDealt',   label: '⚔️ Damage Dealt (HP)' },
    { k: 'mobKills',   label: '🧟 Mob Kills' },
    { k: 'dragon',     label: '🐉 Ender Dragon Kills' },
    { k: 'wither',     label: '☠️ Wither Kills' },
    { k: 'mined',      label: '⛏️ Blocks Mined' },
    { k: 'placed',     label: '🧱 Blocks Placed' },
    { k: 'diamonds',   label: '💎 Diamond Ore Mined' },
    { k: 'debris',     label: '🔥 Ancient Debris Mined' },
    { k: 'distKm',     label: '🧭 Distance Traveled', unit: 'km', dec: 1 },
    { k: 'jumps',      label: '🦘 Jump Count' },
    { k: 'crafted',    label: '🔨 Times Crafted' },
    { k: 'traded',     label: '🤝 Trades with Villagers' },
    { k: 'bred',       label: '🐄 Animals Bred' },
    { k: 'quit',       label: '🚪 Games Quit' }
  ];

  function rate(x, d) { return d.hours >= 0.1 ? x / d.hours : null; }
  var FUN = [
    { i: '⛏️', t: 'Strip miner', s: 'blocks mined per hour', dec: 0, u: '/h', f: function (d) { return rate(d.mined, d); } },
    { i: '⚔️', t: 'Mob slayer', s: 'mob kills per hour', dec: 1, u: '/h', f: function (d) { return rate(d.mobKills, d); } },
    { i: '🛡️', t: 'Survivor', s: 'hours played per death', dec: 1, u: 'h', f: function (d) { return d.hours >= 0.1 ? d.hours / Math.max(1, d.deaths) : null; }, note: function (d) { return d.deaths === 0 ? 'no deaths' : ''; } },
    { i: '🧭', t: 'Explorer', s: 'kilometers per hour of play', dec: 2, u: 'km/h', f: function (d) { return rate(d.distKm, d); } },
    { i: '🧱', t: 'Builder', s: 'blocks placed per hour', dec: 0, u: '/h', f: function (d) { return rate(d.placed, d); } },
    { i: '💎', t: 'Diamond luck', s: 'diamond ores per 1 000 blocks mined', dec: 2, u: '', f: function (d) { return d.mined >= 50 ? d.diamonds / d.mined * 1000 : null; } },
    { i: '🦘', t: 'Bunny hopper', s: 'jumps per hour', dec: 0, u: '/h', f: function (d) { return rate(d.jumps, d); } },
    { i: '🔨', t: 'Craftsman', s: 'items crafted per hour', dec: 1, u: '/h', f: function (d) { return rate(d.crafted, d); } },
    { i: '⏳', t: 'Marathon sessions', s: 'average session length (play time ÷ games quit)', dec: 0, u: 'min', f: function (d) { return d.quit > 0 && d.hours > 0 ? d.hours * 60 / d.quit : null; } },
    { i: '🥷', t: 'Sneak factor', s: 'share of play time spent sneaking', dec: 1, u: '%', f: function (d) { return d.hours >= 0.1 ? d.sneakH / d.hours * 100 : null; } },
    { i: '🥊', t: 'Glass cannon', s: 'damage dealt per 1 HP taken', dec: 2, u: '×', f: function (d) { return d.dmgTaken > 0 ? d.dmgDealt / d.dmgTaken : null; } },
    { i: '🎣', t: 'Angler', s: 'fish caught per hour', dec: 1, u: '/h', f: function (d) { return rate(d.fish, d); } }
  ];

  var ui = { view: 'overview', period: 'all', showAll: false, q: '', cat: '', dp: '', ap: '' };
  var mq = window.matchMedia ? window.matchMedia('(max-width: 720px)') : { matches: false };
  function isMobile() { return mq.matches; }
  var cache = {};
  window.__goto = function (v, p) { ui.view = v; if (p) ui.period = p; update(); window.scrollTo(0, 0); };

  function el(id) { return document.getElementById(id); }
  function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
  // Barvy nicků (Minecraft chat barvy)
  var NICK_COLORS = {
    'Alex_Reed':     '#AA00AA',  // purple (dark_purple)
    'Johny_Reed':    '#55FFFF',  // aqua
    'Kathryn_Reed':  '#AA0000',  // dark red
    'ettelwen':      '#00AA00',  // dark green
    'KarlTheBroken': '#FFAA00',  // gold
    'dufe_com':      '#5555FF'   // blue
  };
  function nick(n) {
    var c = NICK_COLORS[n];
    return c ? '<span style="color:' + c + '">' + esc(n) + '</span>' : esc(n);
  }
  var fmts = {};
  function fmt(v, dec) {
    dec = dec || 0;
    if (!fmts[dec]) fmts[dec] = new Intl.NumberFormat('cs-CZ', { minimumFractionDigits: dec, maximumFractionDigits: dec });
    return fmts[dec].format(v);
  }
  function pretty(name) { return name.replace(/_/g, ' ').replace(/\b\w/g, function (c) { return c.toUpperCase(); }); }

  function sumPrefix(p, prefix, skip) {
    var s = 0;
    for (var k in p) {
      if (k.indexOf(prefix) === 0 && !(skip && skip.test(k.slice(prefix.length)))) s += p[k];
    }
    return s;
  }

  function derive(p) {
    function g(k) { return p[k] || 0; }
    var ticks = g('custom/play_time') || g('custom/play_one_minute');
    return {
      hours: ticks / 72000,
      deaths: g('custom/deaths'),
      sinceDeath: g('custom/time_since_death') / 72000,
      dmgDealt: g('custom/damage_dealt') / 10,
      dmgTaken: g('custom/damage_taken') / 10,
      mobKills: g('custom/mob_kills'),
      dragon: g('killed/ender_dragon'),
      wither: g('killed/wither'),
      mined: sumPrefix(p, 'mined/'),
      placed: sumPrefix(p, 'used/', NOT_PLACED),
      diamonds: g('mined/diamond_ore') + g('mined/deepslate_diamond_ore'),
      debris: g('mined/ancient_debris'),
      distKm: (g('custom/walk_one_cm') + g('custom/sprint_one_cm') + g('custom/crouch_one_cm')) / 100000,
      jumps: g('custom/jump'),
      crafted: sumPrefix(p, 'crafted/'),
      traded: g('custom/traded_with_villager'),
      bred: g('custom/animals_bred'),
      quit: g('custom/leave_game'),
      sneakH: g('custom/sneak_time') / 72000,
      fish: g('custom/fish_caught')
    };
  }

  function valuesFor(period) {
    if (cache[period]) return cache[period];
    var out = {};
    Object.keys(DATA.current).forEach(function (n) {
      var cur = DATA.current[n];
      if (period === 'all') { out[n] = cur; return; }
      var d = (DATA.periods[period].delta || {})[n] || {};
      var o = {};
      Object.keys(d).forEach(function (k) { o[k] = d[k]; });
      Object.keys(STATE_KEYS).forEach(function (k) { if (cur[k] != null) o[k] = cur[k]; });
      out[n] = o;
    });
    cache[period] = out;
    return out;
  }

  function keyInfo(key) {
    var i = key.indexOf('/');
    var cat = key.slice(0, i), name = key.slice(i + 1);
    var info = { cat: cat, label: pretty(name), scale: 1, unit: '', dec: 0 };
    if (cat === 'custom') {
      if (/_one_cm$/.test(name)) { info.scale = 100000; info.unit = 'km'; info.dec = 2; }
      else if (/^(play_time|play_one_minute|total_world_time|time_since_death|time_since_rest|sneak_time)$/.test(name)) { info.scale = 72000; info.unit = 'h'; info.dec = 1; }
      else if (/^damage_/.test(name)) { info.scale = 10; info.unit = 'HP'; }
    }
    return info;
  }

  function curatedRows(vals, nicks) {
    var D = {};
    nicks.forEach(function (n) { D[n] = derive(vals[n]); });
    return CURATED.map(function (def) {
      var v = {}, tot = 0;
      nicks.forEach(function (n) { v[n] = D[n][def.k]; tot += v[n]; });
      return { cat: 'highlights', label: def.label, vals: v, total: def.noTotal ? null : tot, dec: def.dec || 0, unit: def.unit || '', time: !!def.time, low: !!def.low, medals: true };
    });
  }

  function rawRows(vals, nicks) {
    var keys = {};
    nicks.forEach(function (n) { for (var k in vals[n]) keys[k] = 1; });
    var rows = [];
    Object.keys(keys).forEach(function (k) {
      var info = keyInfo(k), v = {}, tot = 0;
      nicks.forEach(function (n) { var x = (vals[n][k] || 0) / info.scale; v[n] = x; tot += x; });
      rows.push({ cat: info.cat, label: info.label, vals: v, total: tot, dec: info.dec, unit: info.unit, time: false, low: false, medals: false });
    });
    rows.sort(function (a, b) {
      var ca = CAT_ORDER.indexOf(a.cat), cb = CAT_ORDER.indexOf(b.cat);
      if (ca < 0) ca = 99; if (cb < 0) cb = 99;
      return (ca - cb) || (b.total - a.total) || a.label.localeCompare(b.label);
    });
    return rows;
  }

  function ranks(row, nicks) {
    var vs = nicks.map(function (n) { return row.vals[n]; });
    var uniq = vs.filter(function (v, i) { return vs.indexOf(v) === i; }).sort(function (a, b) { return row.low ? a - b : b - a; });
    var res = {};
    if (uniq.length < 2) return res;
    nicks.forEach(function (n) {
      var v = row.vals[n];
      if (!row.low && v === 0) return;
      var r = uniq.indexOf(v) + 1;
      if (r <= 3 && (row.medals || r === 1)) res[n] = r;
    });
    return res;
  }

  function fmtVal(row, v) {
    if (row.time) return fmt(v, 1) + ' h / ' + fmt(v / 24, 1) + ' d';
    var s = fmt(v, row.dec);
    return row.unit ? s + '<span class="unit"> ' + row.unit + '</span>' : s;
  }

  function sortedNicks(vals) {
    var nicks = Object.keys(vals), h = {};
    nicks.forEach(function (n) { h[n] = derive(vals[n]).hours; });
    return nicks.sort(function (a, b) { return h[b] - h[a]; });
  }

  function viewStatsMobile(rows, nicks) {
    var h = '', lastCat = null;
    rows.forEach(function (row) {
      if (ui.showAll && row.cat !== lastCat) {
        h += '<h2 class="sg">' + esc(CAT_NAMES[row.cat] || row.cat) + '</h2>';
        lastCat = row.cat;
      }
      var rk = ranks(row, nicks);
      var order = nicks.slice().sort(function (a, b) { return row.low ? row.vals[a] - row.vals[b] : row.vals[b] - row.vals[a]; });
      var max = 0;
      nicks.forEach(function (n) { if (row.vals[n] > max) max = row.vals[n]; });
      var line = function (n, i) {
        var v = row.vals[n], r = rk[n];
        var w = (max > 0 && v > 0) ? Math.max(3, v / max * 100) : 0;
        var pos = (r && row.medals) ? MEDAL[r] : String(i + 1);
        return '<div class="pr' + (r ? ' r' + r : '') + (v === 0 ? ' z' : '') + '" style="--w:' + w.toFixed(1) + '%"><span class="pn">' + pos + '</span><span class="pnm">' + nick(n) + '</span><span class="pv">' + fmtVal(row, v) + '</span></div>';
      };
      h += '<div class="sc"><div class="sh"><span class="sl">' + esc(row.label) + '</span><span class="st">' + (row.total == null ? '—' : fmtVal(row, row.total)) + '</span></div>';
      order.slice(0, 3).forEach(function (n, i) { h += line(n, i); });
      if (order.length > 3) {
        h += '<details class="more"><summary>Show ' + (order.length - 3) + ' more</summary>';
        order.slice(3).forEach(function (n, i) { h += line(n, i + 3); });
        h += '</details>';
      }
      h += '</div>';
    });
    return h;
  }

  function viewStats(vals, nicks) {
    var rows = curatedRows(vals, nicks);
    if (ui.showAll) rows = rows.concat(rawRows(vals, nicks));

    var present = {};
    rows.forEach(function (r) { present[r.cat] = 1; });
    var cats = CAT_ORDER.filter(function (c) { return present[c]; });
    var sel = el('cat');
    var opts = '<option value="">All categories</option>';
    cats.forEach(function (c) { opts += '<option value="' + c + '">' + esc(CAT_NAMES[c] || c) + '</option>'; });
    sel.innerHTML = opts;
    if (!present[ui.cat]) ui.cat = '';
    sel.value = ui.cat;

    var q = ui.q.trim().toLowerCase();
    rows = rows.filter(function (r) {
      if (ui.cat && r.cat !== ui.cat) return false;
      if (q && (r.label.toLowerCase().indexOf(q) < 0 && (CAT_NAMES[r.cat] || r.cat).toLowerCase().indexOf(q) < 0)) return false;
      return true;
    });
    if (!rows.length) return '<div class="empty">No stats match your filter.</div>';

    if (isMobile()) return viewStatsMobile(rows, nicks);

    var fit = rows.length <= 20;
    var minW = 200 + nicks.length * 130 + 140;
    var h = '<table class="' + (fit ? 'fit' : 'tall') + '" style="min-width:' + minW + 'px"><thead><tr><th class="stat-name">Statistic</th>';
    nicks.forEach(function (n) { h += '<th class="player-header" title="' + esc(n) + '">' + nick(n) + '</th>'; });
    h += '<th class="server-total">Server total</th></tr></thead><tbody>';

    var lastCat = null;
    rows.forEach(function (row) {
      if (ui.showAll && row.cat !== lastCat) {
        h += '<tr class="grp"><td colspan="' + (nicks.length + 2) + '">' + esc(CAT_NAMES[row.cat] || row.cat) + '</td></tr>';
        lastCat = row.cat;
      }
      var rk = ranks(row, nicks);
      h += '<tr><td class="stat-name" title="' + esc(row.label) + '">' + esc(row.label) + '</td>';
      nicks.forEach(function (n) {
        var v = row.vals[n], r = rk[n];
        var cls = r ? ' class="r' + r + '"' : (v === 0 ? ' class="z"' : '');
        var medal = (r && row.medals) ? '<span class="medal">' + MEDAL[r] + '</span>' : '';
        h += '<td' + cls + '>' + fmtVal(row, v) + medal + '</td>';
      });
      h += '<td class="server-total">' + (row.total == null ? '—' : fmtVal(row, row.total)) + '</td></tr>';
    });
    return h + '</tbody></table>';
  }

  function funCard(icon, title, sub, list, dec, unit) {
    var h = '<div class="fc"><h3>' + icon + ' ' + title + '</h3><div class="sub">' + esc(sub) + '</div>';
    if (!list.length) {
      h += '<div class="none">Not enough data yet</div>';
    } else {
      var max = list[0].v;
      list.slice(0, 3).forEach(function (e, idx) {
        h += '<div class="fr"><span>' + MEDAL[idx + 1] + '</span><span class="nm">' + nick(e.n) + '</span>' +
             '<span class="val">' + fmt(e.v, dec) + (unit ? ' <small>' + unit + '</small>' : '') + (e.note ? ' <small>· ' + e.note + '</small>' : '') + '</span>' +
             '<div class="bar"><i style="width:' + Math.max(3, e.v / max * 100).toFixed(1) + '%"></i></div></div>';
      });
    }
    return h + '</div>';
  }

  function initials(n) { return esc(String(n).slice(0, 2).toUpperCase()); }

  function avatarHtml(n) {
    var uuid = (DATA.avatars || {})[n];
    var c = NICK_COLORS[n] || '#3ddc97';
    var h = '<span class="rp-av" style="background:' + c + '">' + initials(n);
    if (uuid) h += '<img src="https://crafatar.com/avatars/' + uuid + '?size=64&overlay" alt="" loading="lazy" onerror="this.remove()">';
    return h + '</span>';
  }

  function viewOverview() {
    var vals = valuesFor('all'), nicks = sortedNicks(vals);
    var D = {};
    nicks.forEach(function (n) { D[n] = derive(vals[n]); });
    function sum(k) { return nicks.reduce(function (s, n) { return s + D[n][k]; }, 0); }

    var h = '<div class="fun">';
    h += '<div class="ov-head"><h2>Forever Reeds dashboard</h2><p>Lifetime totals across ' + nicks.length + ' tracked player' + (nicks.length === 1 ? '' : 's') + ' · updated __UPDATED__</p></div>';

    var hero = [
      [fmt(sum('hours'), 0) + ' h', '= ' + fmt(sum('hours') / 24, 1) + ' days played'],
      [fmt(sum('deaths')), 'total deaths'],
      [fmt(sum('mined')), 'blocks mined'],
      [fmt(sum('diamonds')), 'diamond ore mined'],
      [fmt(sum('mobKills')), 'mobs slain'],
      [fmt(sum('distKm'), 0) + ' km', 'travelled']
    ];
    h += '<div class="kpis">';
    hero.forEach(function (k) { h += '<div class="kpi"><b>' + k[0] + '</b><span>' + k[1] + '</span></div>'; });
    h += '</div>';

    var wv = valuesFor('week'), wn = Object.keys(wv);
    if (wn.length) {
      var WD = {};
      wn.forEach(function (n) { WD[n] = derive(wv[n]); });
      var wsum = function (k) { return wn.reduce(function (s, n) { return s + WD[n][k]; }, 0); };
      if (wsum('hours') > 0 || wsum('mined') > 0 || wsum('deaths') > 0) {
        h += '<div class="ov-section"><h3>Last 7 days</h3><div class="kpis">' +
          '<div class="kpi"><b>' + fmt(wsum('hours'), 1) + ' h</b><span>played</span></div>' +
          '<div class="kpi"><b>' + fmt(wsum('mined')) + '</b><span>blocks mined</span></div>' +
          '<div class="kpi"><b>' + fmt(wsum('mobKills')) + '</b><span>mobs killed</span></div>' +
          '<div class="kpi"><b>' + fmt(wsum('deaths')) + '</b><span>deaths</span></div>' +
          '</div></div>';
      }
    }

    h += '<div class="ov-section"><h3>Players</h3><div class="roster">';
    nicks.forEach(function (n, i) {
      h += '<div class="rp">' + avatarHtml(n) +
        '<div><div class="rp-name"><span>' + nick(n) + '</span>' + (i < 3 ? MEDAL[i + 1] : '') + '</div>' +
        '<div class="rp-sub">' + fmt(D[n].hours, 1) + ' h played · ' + fmt(D[n].deaths) + ' deaths</div></div></div>';
    });
    h += '</div></div>';

    var deaths = DATA.deaths || [];
    if (deaths.length) {
      h += '<div class="ov-section"><h3>Latest deaths</h3><div class="ov-deaths">';
      deaths.slice(0, 5).forEach(function (d) {
        h += '<div class="dr"><span class="when">' + esc(d.t.slice(0, 16)) + '</span><span class="who">' + nick(d.n) + '</span><span class="cause">' + esc(deathCause(d.m)) + '</span></div>';
      });
      h += '</div><button class="ov-more" onclick="window.__goto(\'deaths\')">See all deaths →</button></div>';
    }

    var tiles = [
      { v: 'stats', i: '📈', t: 'Full stats table', s: 'Every tracked statistic, side by side' },
      { v: 'fun', i: '✨', t: 'Fun facts', s: 'Quirky leaderboards & awards' },
      { v: 'deaths', i: '💀', t: 'Deaths', s: 'Full death log with causes' },
      { v: 'activity', i: '🔥', t: 'Activity', s: 'When people actually play' },
      { v: 'map', i: '🗺️', t: 'World map', s: 'Explore the world live' }
    ];
    h += '<div class="ov-section"><h3>Explore</h3><div class="ov-grid">';
    tiles.forEach(function (x) {
      h += '<button class="ov-tile" onclick="window.__goto(\'' + x.v + '\')"><div class="ti">' + x.i + '</div><h4>' + x.t + '</h4><p>' + x.s + '</p></button>';
    });
    h += '</div></div>';

    return h + '</div>';
  }

  function viewFun(vals, nicks) {
    var D = {};
    nicks.forEach(function (n) { D[n] = derive(vals[n]); });
    function sum(k) { return nicks.reduce(function (s, n) { return s + D[n][k]; }, 0); }

    var kp = [
      [fmt(sum('hours'), 1) + ' h', '= ' + fmt(sum('hours') / 24, 1) + ' days played'], [fmt(sum('mined')), 'blocks mined'], [fmt(sum('mobKills')), 'mobs slain'],
      [fmt(sum('distKm'), 1), 'km travelled'], [fmt(sum('crafted')), 'items crafted'], [fmt(sum('deaths')), 'deaths']
    ];
    var h = '<div class="fun"><div class="kpis">';
    kp.forEach(function (k) { h += '<div class="kpi"><b>' + k[0] + '</b><span>' + k[1] + '</span></div>'; });
    h += '</div><div class="grid">';

    FUN.forEach(function (m) {
      var list = [];
      nicks.forEach(function (n) {
        var v = m.f(D[n]);
        if (v != null && isFinite(v) && v > 0) list.push({ n: n, v: v, note: m.note ? m.note(D[n]) : '' });
      });
      list.sort(function (a, b) { return b.v - a.v; });
      h += funCard(m.i, m.t, m.s, list, m.dec, m.u);
    });

    // Co zabilo hráče nejčastěji (součet přes všechny hráče)
    var kb = {};
    nicks.forEach(function (n) {
      for (var k in vals[n]) { if (k.indexOf('killed_by/') === 0) kb[k] = (kb[k] || 0) + vals[n][k]; }
    });
    var killers = Object.keys(kb).map(function (k) { return { n: pretty(k.slice(10)), v: kb[k] }; })
      .filter(function (e) { return e.v > 0; })
      .sort(function (a, b) { return b.v - a.v; });
    h += funCard('☠️', 'Deadliest mobs', 'what killed players most (server total)', killers, 0, 'deaths');

    return h + '</div></div>';
  }

  function deathCause(m) {
    m = String(m).replace(/^was /, '');
    return m.charAt(0).toUpperCase() + m.slice(1);
  }
  function killerOf(m) {
    var x = / by (.+?)(?: using .*)?$/.exec(m);
    return x ? x[1] : deathCause(m);
  }

  function viewDeaths() {
    var all = DATA.deaths || [];
    var info = DATA.deathsInfo || {};

    var names = {};
    all.forEach(function (d) { names[d.n] = (names[d.n] || 0) + 1; });
    var sel = el('deathPlayer');
    var opts = '<option value="">All players</option>';
    Object.keys(names).sort().forEach(function (n) { opts += '<option value="' + esc(n) + '">' + esc(n) + ' (' + names[n] + ')</option>'; });
    sel.innerHTML = opts;
    if (!names[ui.dp]) ui.dp = '';
    sel.value = ui.dp;

    if (!all.length) return '<div class="empty">No deaths found in the server logs yet.</div>';

    var list = ui.dp ? all.filter(function (d) { return d.n === ui.dp; }) : all;

    var byPlayer = {}, byCause = {};
    list.forEach(function (d) {
      byPlayer[d.n] = (byPlayer[d.n] || 0) + 1;
      var k = killerOf(d.m);
      byCause[k] = (byCause[k] || 0) + 1;
    });
    function ranked(o) {
      return Object.keys(o).map(function (k) { return { n: k, v: o[k] }; }).sort(function (a, b) { return b.v - a.v; });
    }
    var rp = ranked(byPlayer), rc = ranked(byCause);

    var h = '<div class="fun"><div class="kpis">' +
      '<div class="kpi"><b>' + fmt(list.length) + '</b><span>deaths' + (ui.dp ? ' · ' + nick(ui.dp) : ' in total') + '</span></div>' +
      '<div class="kpi"><b>' + esc(list[0].t.slice(0, 16)) + '</b><span>latest death' + (ui.dp ? '' : ' · ' + nick(list[0].n)) + '</span></div>' +
      '<div class="kpi"><b>' + esc(rc[0].n) + '</b><span>most common cause (' + rc[0].v + '×)</span></div>' +
      '</div>';

    h += '<div class="note">From server logs' + (info.from ? ' (since ' + esc(info.from) + ')' : '') + ' · times as written in the log</div>';

    h += '<div class="grid">';
    if (!ui.dp) h += funCard('💀', 'Most deaths', 'per player, from logs', rp, 0, 'deaths');
    h += funCard('☠️', 'Deadliest causes', ui.dp ? 'what killed ' + ui.dp : 'what killed players most', rc, 0, 'deaths');
    h += '</div>';

    h += '<div class="dtw"><table class="dt"><thead><tr><th>Time of death</th><th>Player</th><th>Cause</th></tr></thead><tbody>';
    list.forEach(function (d) {
      h += '<tr><td class="when">' + esc(d.t) + '</td><td class="who">' + nick(d.n) + '</td><td class="cause">' + esc(deathCause(d.m)) + '</td></tr>';
    });
    return h + '</tbody></table></div></div>';
  }

  var DOW = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  var DOW_LONG = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  var MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  function pad2(x) { return (x < 10 ? '0' : '') + x; }
  function ymd(d) { return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()); }
  function parseYmd(s) { var p = s.split('-'); return new Date(+p[0], +p[1] - 1, +p[2]); }
  function heat(v, max) {
    if (!(v > 0) || !(max > 0)) return 'rgba(255,255,255,.045)';
    return 'rgba(61,220,151,' + (0.16 + 0.84 * Math.pow(v / max, 0.6)).toFixed(2) + ')';
  }
  function legend() {
    var h = '<div class="legend">Less';
    [0, 0.15, 0.35, 0.6, 1].forEach(function (t) { h += '<i style="background:' + heat(t, 1) + '"></i>'; });
    return h + 'More</div>';
  }

  function viewActivity() {
    var A = DATA.activity || {};
    var H = A.hours || {}, D = A.days || {}, S = A.sessions || {};
    var names = Object.keys(H).sort(function (a, b) { return a.toLowerCase().localeCompare(b.toLowerCase()); });

    var sel = el('actPlayer');
    var opts = '<option value="">All players</option>';
    names.forEach(function (n) { opts += '<option value="' + esc(n) + '">' + esc(n) + '</option>'; });
    sel.innerHTML = opts;
    if (names.indexOf(ui.ap) < 0) ui.ap = '';
    sel.value = ui.ap;

    if (!names.length) return '<div class="empty">No activity found in the server logs yet.</div>';

    var pick = ui.ap ? [ui.ap] : names;
    var grid = [], i;
    for (i = 0; i < 168; i++) grid.push(0);
    var days = {}, sessions = 0;
    pick.forEach(function (n) {
      var a = H[n] || [];
      for (var j = 0; j < 168; j++) grid[j] += a[j] || 0;
      var dd = D[n] || {};
      for (var k in dd) days[k] = (days[k] || 0) + dd[k];
      sessions += S[n] || 0;
    });

    var total = 0, maxCell = 0, maxIdx = 0;
    for (i = 0; i < 168; i++) { total += grid[i]; if (grid[i] > maxCell) { maxCell = grid[i]; maxIdx = i; } }
    var maxDay = 0, maxDayKey = '';
    for (var dk in days) if (days[dk] > maxDay) { maxDay = days[dk]; maxDayKey = dk; }
    if (!total) return '<div class="empty">No activity for this player yet.</div>';

    var bd = maxDayKey ? parseYmd(maxDayKey) : null;
    var h = '<div class="fun"><div class="kpis">' +
      '<div class="kpi"><b>' + fmt(total / 60, 1) + ' h</b><span>online' + (ui.ap ? ' · ' + nick(ui.ap) : ' (all players together)') + '</span></div>' +
      '<div class="kpi"><b>' + fmt(sessions) + '</b><span>sessions · avg ' + fmt(sessions ? total / sessions : 0) + ' min</span></div>' +
      '<div class="kpi"><b>' + DOW[Math.floor(maxIdx / 24)] + ' ' + (maxIdx % 24) + ':00</b><span>busiest hour of the week</span></div>' +
      '<div class="kpi"><b>' + (bd ? bd.getDate() + '. ' + (bd.getMonth() + 1) + '. ' + bd.getFullYear() : '—') + '</b><span>busiest day · ' + fmt(maxDay / 60, 1) + ' h</span></div>' +
      '</div>';

    h += '<div class="note">From server logs (join / leave times) · times as written in the log</div>';

    // 1) den v týdnu × hodina
    h += '<div class="apanel"><h3>🕒 When they play</h3><div class="sub">hours online by weekday and hour of day, all dates added together</div><div class="hm"><div class="hm-g"><span></span>';
    for (var hr = 0; hr < 24; hr++) h += '<span class="hl">' + (hr % 3 === 0 ? hr : '') + '</span>';
    for (var d = 0; d < 7; d++) {
      h += '<span class="dl">' + DOW[d] + '</span>';
      for (hr = 0; hr < 24; hr++) {
        var v = grid[d * 24 + hr];
        h += '<i class="c" style="background:' + heat(v, maxCell) + '" title="' + DOW_LONG[d] + ' ' + hr + ':00–' + (hr + 1) + ':00 · ' + fmt(v / 60, 1) + ' h"></i>';
      }
    }
    h += '</div>' + legend() + '</div></div>';

    // 2) kalendář po dnech
    var allDays = Object.keys(days).sort();
    var first = parseYmd(allDays[0]);
    Object.keys(D).forEach(function (n) { var ks = Object.keys(D[n]).sort(); if (ks.length && parseYmd(ks[0]) < first) first = parseYmd(ks[0]); });
    var now = new Date();
    var last = parseYmd(allDays[allDays.length - 1]);
    if (now > last) last = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    var cur = new Date(first.getFullYear(), first.getMonth(), first.getDate());
    cur.setDate(cur.getDate() - ((cur.getDay() + 6) % 7));        // pondělí

    var cal = '<div class="wk"><span class="wl"></span>';
    for (d = 0; d < 7; d++) cal += '<span class="wd">' + (d % 2 === 0 ? DOW[d] : '') + '</span>';
    cal += '</div>';
    var wi = 0;
    while (cur <= last) {
      var label = (wi === 0 || cur.getDate() <= 7) ? MON[cur.getMonth()] : '';
      cal += '<div class="wk"><span class="wl">' + label + '</span>';
      for (d = 0; d < 7; d++) {
        if (cur > last) { cal += '<i class="d nil"></i>'; }
        else {
          var key = ymd(cur), val = days[key] || 0;
          cal += '<i class="d" style="background:' + heat(val, maxDay) + '" title="' + DOW[d] + ' ' + cur.getDate() + '. ' + (cur.getMonth() + 1) + '. ' + cur.getFullYear() + ' · ' + fmt(val / 60, 1) + ' h"></i>';
        }
        cur.setDate(cur.getDate() + 1);
      }
      cal += '</div>';
      wi++;
    }
    h += '<div class="apanel"><h3>📅 Day by day</h3><div class="sub">hours online per day</div><div class="cal-wrap"><div class="cal">' + cal + '</div></div>' + legend() + '</div>';

    return h + '</div>';
  }

  function setActive(selector, attr, value) {
    var btns = document.querySelectorAll(selector);
    for (var i = 0; i < btns.length; i++) {
      var on = btns[i].getAttribute(attr) === value;
      btns[i].classList.toggle('active', on);
      btns[i].setAttribute('aria-pressed', on ? 'true' : 'false');
    }
  }

  function update() {
    var isMap = ui.view === 'map', isStats = ui.view === 'stats', isDeaths = ui.view === 'deaths', isAct = ui.view === 'activity', isOverview = ui.view === 'overview';
    setActive('#main-tabs .tab-btn', 'data-view', ui.view);
    setActive('#period-tabs .tab-btn', 'data-period', ui.period);

    el('toolbar').hidden = isMap;
    el('statsControls').hidden = !isStats;
    el('deathControls').hidden = !isDeaths;
    el('actControls').hidden = !isAct;
    el('period-tabs').hidden = isDeaths || isAct || isOverview;
    el('note').hidden = isDeaths || isAct || isOverview;
    el('cat').style.display = ui.showAll ? '' : 'none';
    el('view-data').style.display = isMap ? 'none' : 'block';
    el('view-map').style.display = isMap ? 'block' : 'none';

    if (isMap) {
      var frame = el('map-frame');
      if (!frame.getAttribute('src')) frame.setAttribute('src', frame.getAttribute('data-src'));
    } else if (isOverview) {
      el('content').innerHTML = viewOverview();
      el('content').scrollTop = 0;
    } else {
      var vals = valuesFor(ui.period), nicks = sortedNicks(vals);
      if (ui.period === 'all') {
        el('note').textContent = 'All-time totals';
      } else {
        var P = DATA.periods[ui.period];
        el('note').textContent = 'Change since ' + P.since + (P.exact ? '' : ' · history so far') + (isStats ? '' : ' (' + PERIOD_LABEL[ui.period] + ')');
      }
      if (isStats) el('content').innerHTML = viewStats(vals, nicks);
      else if (isDeaths) el('content').innerHTML = viewDeaths();
      else if (isAct) el('content').innerHTML = viewActivity();
      else el('content').innerHTML = viewFun(vals, nicks);
      el('content').scrollTop = 0;
    }
    try { history.replaceState(null, '', '#' + ui.view + '/' + ui.period); } catch (e) {}
  }

  function bind() {
    var vb = document.querySelectorAll('#main-tabs .tab-btn');
    for (var i = 0; i < vb.length; i++) vb[i].addEventListener('click', function () { ui.view = this.getAttribute('data-view'); update(); window.scrollTo(0, 0); });
    var pb = document.querySelectorAll('#period-tabs .tab-btn');
    for (var j = 0; j < pb.length; j++) pb[j].addEventListener('click', function () { ui.period = this.getAttribute('data-period'); update(); });
    el('q').addEventListener('input', function () { ui.q = this.value; update(); });
    el('showAll').addEventListener('change', function () { ui.showAll = this.checked; update(); });
    el('cat').addEventListener('change', function () { ui.cat = this.value; update(); });
    el('deathPlayer').addEventListener('change', function () { ui.dp = this.value; update(); });
    el('actPlayer').addEventListener('change', function () { ui.ap = this.value; update(); });
    if (mq.addEventListener) mq.addEventListener('change', update);
    else if (mq.addListener) mq.addListener(update);
  }

  var parts = location.hash.replace('#', '').split('/');
  if (['overview', 'stats', 'fun', 'deaths', 'activity', 'map'].indexOf(parts[0]) >= 0) ui.view = parts[0];
  if (['all', 'month', 'week', 'day'].indexOf(parts[1]) >= 0) ui.period = parts[1];
  bind();
  update();
})();
</script>
</body>
</html>
'@

$html = $template.Replace('__UPDATED__', $updated).Replace('__DATA__', $dataJson)
[System.IO.File]::WriteAllText((Join-Path (Get-Location) 'index.html'), $html, [System.Text.UTF8Encoding]::new($false))
Write-Host "index.html vygenerován ($($players.Count) hráčů, snapshotů: $($snaps.Count), smrtí: $($deaths.Count), sezení: $($sessions.Count))"
