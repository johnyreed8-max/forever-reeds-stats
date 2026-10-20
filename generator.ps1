# Safety check: If stats & history folders do not exist, create them
if (-not (Test-Path "stats")) { New-Item -ItemType Directory -Path "stats" | Out-Null }
$historyFolder = "stats_history"
if (-not (Test-Path $historyFolder)) { New-Item -ItemType Directory -Path$historyFolder | Out-Null }

# Ensure correct time formatting
$currentDateTime = (Get-Date).ToUniversalTime().AddHours(2).ToString("dd.MM.yyyy HH:mm:ss")
$usCulture = [System.Globalization.CultureInfo]::GetCultureInfo("cs-CZ")

# Exact UUID mapping for your server
$jmena = @{
    '10d807ae-f713-4d9d-966d-a6e7b4bddafd' = 'dufe_com';
    '4b91ee4a-88d0-48f0-b111-8f8e6e3647b7' = 'KarlTheBroken';
    '90afe98a-4c6a-4469-959e-d55070e4b6b8' = 'Kathryn_Reed';
    '953decf3-5ac0-4108-965f-3b82cea52143' = 'Alex_Reed';
    'aa14ea23-012a-48b8-b39d-3e280496e83a' = 'Johny_Reed';
    'bd265486-b561-4510-860c-76a0bc9ea3ae' = 'ettelwen'
}

# --- NAČTENÍ AKTUÁLNÍCH STATISTIK ---
$hraciDataAllTime = @(); $snapshotTodayData = @{}

# Global totals All-Time
$totalHours = 0; $totalDeaths = 0; $totalMobKills = 0; $totalMined = 0; $totalPlaced = 0; $totalTraded = 0; $totalDistance = 0; $totalTalked = 0;
$totalDamageDealt = 0; $totalDamageTaken = 0; $totalDiamonds = 0; $totalDebris = 0; $totalJumps = 0;
$totalDragonKills = 0; $totalWitherKills = 0; $totalCrafted = 0; $totalBred = 0;

$statsFiles = Get-ChildItem 'stats/*.json' -ErrorAction SilentlyContinue

$statsFiles | ForEach-Object {
    $file =$_
    $uuid =$file.BaseName
    $nickname = if ($jmena.Contains($uuid)) {$jmena[$uuid] } else {$uuid }
    $json = Get-Content$file.FullName -Raw | ConvertFrom-Json
    $custom =$json.stats.'minecraft:custom'
    $mined =$json.stats.'minecraft:mined'
    $killed =$json.stats.'minecraft:killed'
    $crafted =$json.stats.'minecraft:crafted'
    
    # Raw values
    $ticks = 0
    if ($custom.'minecraft:play_time') { 
        $ticks =$custom.'minecraft:play_time' 
    } elseif ($custom.'minecraft:play_one_minute') { 
        $ticks =$custom.'minecraft:play_one_minute' 
    }
    
    $hours = [Math]::Round($ticks / 20 / 60 / 60, 1)
    $days = [Math]::Round($hours / 24, 1)
    $timePlayedText = "$hours hrs / $days days"

    $deaths = if ($custom.'minecraft:deaths') { $custom.'minecraft:deaths' } else { 0 }$sinceDeathTicks = if ($custom.'minecraft:time_since_death') {$custom.'minecraft:time_since_death' } else { 0 }
    $sinceDeathHours = [Math]::Round($sinceDeathTicks / 20 / 60 / 60, 1)
    
    $damageDealt = if ($custom.'minecraft:damage_dealt') { [Math]::Round($custom.'minecraft:damage_dealt' / 10, 0) } else { 0 }$damageTaken = if ($custom.'minecraft:damage_taken') { [Math]::Round($custom.'minecraft:damage_taken' / 10, 0) } else { 0 }
    $mobKills = if ($custom.'minecraft:mob_kills') { $custom.'minecraft:mob_kills' } else { 0 }$dragonKills = if ($killed.'minecraft:ender_dragon') {$killed.'minecraft:ender_dragon' } else { 0 }
    $witherKills = if ($killed.'minecraft:wither') { $killed.'minecraft:wither' } else { 0 }$talked = if ($custom.'minecraft:talked_to_villager') {$custom.'minecraft:talked_to_villager' } else { 0 }
    $traded = if ($custom.'minecraft:traded_with_villager') { $custom.'minecraft:traded_with_villager' } else { 0 }$jumps = if ($custom.'minecraft:jump') {$custom.'minecraft:jump' } else { 0 }
    $animalsBred = if ($custom.'minecraft:animals_bred') { $custom.'minecraft:animals_bred' } else { 0 }$totalPlayerCrafted = 0
    if ($crafted) {$crafted.psobject.Properties | ForEach-Object { 
            $totalPlayerCrafted +=$_.Value 
        } 
    }
    
    $walk = if ($custom.'minecraft:walk_one_cm') { $custom.'minecraft:walk_one_cm' } else { 0 }
    $sprint = if ($custom.'minecraft:sprint_one_cm') { $custom.'minecraft:sprint_one_cm' } else { 0 }
    $distanceKm = [Math]::Round(($walk + $sprint) / 100 / 1000, 1)
    
    $blocksMined = 0
    if ($mined) { 
        $mined.psobject.Properties | ForEach-Object { 
            $blocksMined += $_.Value 
        } 
    }
    
    $blocksPlaced = 0
    if ($json.stats.'minecraft:used') { 
        $json.stats.'minecraft:used'.psobject.Properties | ForEach-Object { 
            if ($_.Name -notmatch 'minecart|boat|sword|axe|pickaxe|shovel|hoe|shear|flint|bucket|potion|apple|stew|bread|pie|beef|pork|chicken|mutton|salmon|cod|cookie|carrot|potato|kelp|melon|berries|soup') { 
                $blocksPlaced += $_.Value 
            } 
        } 
    }
    
    $diamondOre = if ($mined.'minecraft:diamond_ore') { $mined.'minecraft:diamond_ore' } else { 0 }
    $deepslateDiamondOre = if ($mined.'minecraft:deepslate_diamond_ore') { $mined.'minecraft:deepslate_diamond_ore' } else { 0 }
    $totalPlayerDiamonds = $diamondOre + $deepslateDiamondOre
    $ancientDebris = if ($mined.'minecraft:ancient_debris') { $mined.'minecraft:ancient_debris' } else { 0 }
    
    # Save current raw values for future snapshot
    $snapshotTodayData[$nickname] = @{
        Hours = $hours
        Deaths = $deaths
        DamageDealt = $damageDealt
        DamageTaken = $damageTaken
        MobKills = $mobKills
        DragonKills = $dragonKills
        WitherKills = $witherKills
        BlocksMined = $blocksMined
        BlocksPlaced = $blocksPlaced
        Diamonds = $totalPlayerDiamonds
        Debris = $ancientDebris
        Distance = $distanceKm
        Jumps = $jumps
        Crafted = $totalPlayerCrafted
        Traded = $traded
        Bred = $animalsBred
        Talked = $talked
    }

    # Cumulative totals
    $totalHours +=$hours; $totalDeaths +=$deaths; $totalMobKills +=$mobKills; $totalMined +=$blocksMined; $totalPlaced +=$blocksPlaced; $totalTraded +=$traded; $totalDistance +=$distanceKm; $totalTalked +=$talked
    $totalDamageDealt +=$damageDealt; $totalDamageTaken +=$damageTaken; $totalDiamonds +=$totalPlayerDiamonds; $totalDebris +=$ancientDebris; $totalJumps +=$jumps
    $totalDragonKills +=$dragonKills; $totalWitherKills +=$witherKills; $totalCrafted +=$totalPlayerCrafted; $totalBred +=$animalsBred

    $hraciDataAllTime += [PSCustomObject]@{
        Nickname = $nickname
        Hours = $hours
        TimePlayedText = $timePlayedText
        Deaths = $deaths
        SinceDeathHours = $sinceDeathHours
        DamageDealt = $damageDealt
        DamageTaken = $damageTaken
        MobKills = $mobKills
        DragonKills = $dragonKills
        WitherKills = $witherKills
        BlocksMined = $blocksMined
        BlocksPlaced = $blocksPlaced
        Diamonds = $totalPlayerDiamonds
        Debris = $ancientDebris
        Distance = $distanceKm
        Jumps = $jumps
        Crafted = $totalPlayerCrafted
        Traded = $traded
        Bred = $animalsBred
        Talked = $talked
    }
}

# Uložíme dnešní snapshot
$todayStr = (Get-Date).ToString("yyyy-MM-dd")
$todaySnapshotFile = "$historyFolder/stats_$todayStr.json"
$snapshotTodayData | ConvertTo-Json -Depth 5 | Set-Content -Path $todaySnapshotFile -Encoding utf8
# Sorting
$serazeniAllTime =$hraciDataAllTime | Sort-Object Hours -Descending

# --- HTML Table Builder ---
function Build-TableContent ($listHraci,$tHours, $tDeaths,$tDamage, $tMobKills,$tDragon, $tWither,$tMined, $tPlaced,$tDia, $tDebris,$tDist, $tJumps,$tCrafted, $tTraded,$tBred, $tTalked) {$out = "<table>"
    $out += "<tr><th class='stat-name'>Statistic</th>"
    $listHraci | ForEach-Object {$out += "<th class='player-header'>$($_.Nickname)</th>" }
    $out += "<th class='server-total'>SERVER TOTAL</th></tr>"

    $AddRow = {
        param($label, $property,$formatSuffix = "", $serverValue = "", $lowerWins = $false,$sortProperty = "")
        $evalProperty = if ($sortProperty -ne "") { $sortProperty } else {$property }

        $values = if ($lowerWins) {
            $listHraci | Select-Object -ExpandProperty$evalProperty | Sort-Object
        } else {
            $listHraci | Select-Object -ExpandProperty$evalProperty | Sort-Object -Descending
        }

        $top1 =$values[0]; $top2 =$values[1]; $top3 =$values[2]

        $row = "<tr><td class='stat-name'>$label</td>"
        $listHraci | ForEach-Object {
            $hrac = $_
            $val = $hrac.$property
            $evalVal = $hrac.$evalProperty
            $formattedVal = if ($val -is [ValueType]) { $val.ToString("N0", $usCulture) } else { $val.ToString() }
            
            $medal = ""
            if ($evalVal -ne 0 -or (-not $lowerWins -and $evalProperty -ne "Deaths")) {
                if ($evalVal -eq $top1) { $medal = " 👑" }
                elseif ($evalVal -eq $top2 -and $top2 -ne $top1) { $medal = " 🥈" }
                elseif ($evalVal -eq $top3 -and $top3 -ne $top2 -and $top3 -ne $top1) { $medal = " 🥉" }
            }
            $row += "<td>$formattedVal$formatSuffix$medal</td>"
        }
        $formattedServerVal = if ($serverValue -is [ValueType]) { $serverValue.ToString("N0", $usCulture) } else { $serverValue }
        $finalServerVal = if ($serverValue -ne "") { $formattedServerVal } else { "—" }
        $row += "<td class='server-total'>$finalServerVal$formatSuffix</td></tr>"
        return $row
    }

    $out += & $AddRow "Time Played" "TimePlayedText" "" $tHours $false "Hours"
    $out += & $AddRow "Deaths" "Deaths" "" $tDeaths $true
    $out += & $AddRow "Time Since Last Death" "SinceDeathHours" "hrs" "" $false "SinceDeathHours"
    $out += & $AddRow "Damage Dealt (HP)" "DamageDealt" "" $tDamage
    $out += & $AddRow "Mob Kills" "MobKills" "" $tMobKills
    $out += & $AddRow "Ender Dragon Kills" "DragonKills" "" $tDragon
    $out += & $AddRow "Wither Kills" "WitherKills" "" $tWither
    $out += & $AddRow "Blocks Mined" "BlocksMined" "" $tMined
    $out += & $AddRow "Blocks Placed" "BlocksPlaced" "" $tPlaced
    $out += & $AddRow "Diamond Ore Mined" "Diamonds" "" $tDia
    $out += & $AddRow "Ancient Debris Mined" "Debris" "" $tDebris
    $out += & $AddRow "Distance Traveled" "Distance" "km" $tDist
    $out += & $AddRow "Jump Count" "Jumps" "" $tJumps
    $out += & $AddRow "Times Crafted" "Crafted" "" $tCrafted
    $out += & $AddRow "Trades with Villagers" "Traded" "" $tTraded
    $out += & $AddRow "Animals Bred" "Bred" "" $tBred
    $out += & $AddRow "Chat Messages" "Talked" "" $tTalked
    $out += "</table>"

    return $out
}

# --- UNIVERZÁLNÍ FUNKCE PRO VÝPOČET DELTY ZA URČITÝ POČET DNÍ ---
function Get-DeltaStatsForDays($days) {
    $targetDateStr = (Get-Date).AddDays(-$days).ToString("yyyy-MM-dd")

    # Najdeme starší snapshot
    $oldSnapshotFile = Get-ChildItem "$historyFolder/stats_*.json" -ErrorAction SilentlyContinue | 
        Where-Object { $_.BaseName -le "stats_$targetDateStr" } | 
        Sort-Object Name -Descending | Select-Object -First 1

    if (-not $oldSnapshotFile) {
        $oldSnapshotFile = Get-ChildItem "$historyFolder/stats_*.json" -ErrorAction SilentlyContinue | 
            Sort-Object Name | Select-Object -First 1
    }

    $oldStatsData = @{}
    if ($oldSnapshotFile) {
        $rawOld = Get-Content $oldSnapshotFile.FullName -Raw | ConvertFrom-Json
        $rawOld.psobject.Properties | ForEach-Object { $oldStatsData[$_.Name] = $_.Value }
    }

    $listDelta = @()
    $totH=0; $totD=0; $totDMG=0; $totMK=0; $totDK=0; $totWK=0; $totBM=0; $totBP=0; $totDIA=0; $totDEB=0; $totDIST=0; $totJ=0; $totCR=0; $totTR=0; $totBR=0; $totTK=0;

    foreach ($hrac in $hraciDataAllTime) {
        $nickname = $hrac.Nickname
        $old = if ($oldStatsData.ContainsKey($nickname)) { $oldStatsData[$nickname] } else { $null }

        $h = if ($old) { [Math]::Max(0, [Math]::Round($hrac.Hours - $old.Hours, 1)) } else { $hrac.Hours }
        $d = [Math]::Round($h / 24, 1)
        $t = "$h hrs / $d days"

        $dt = if ($old) { [Math]::Max(0, $hrac.Deaths - $old.Deaths) } else { $hrac.Deaths }
        $dd = if ($old) { [Math]::Max(0, $hrac.DamageDealt - $old.DamageDealt) } else { $hrac.DamageDealt }
        $mk = if ($old) { [Math]::Max(0, $hrac.MobKills - $old.MobKills) } else { $hrac.MobKills }
        $dk = if ($old) { [Math]::Max(0, $hrac.DragonKills - $old.DragonKills) } else { $hrac.DragonKills }
        $wk = if ($old) { [Math]::Max(0, $hrac.WitherKills - $old.WitherKills) } else { $hrac.WitherKills }
        $bm = if ($old) { [Math]::Max(0, $hrac.BlocksMined - $old.BlocksMined) } else { $hrac.BlocksMined }
        $bp = if ($old) { [Math]::Max(0, $hrac.BlocksPlaced - $old.BlocksPlaced) } else { $hrac.BlocksPlaced }
        $dia = if ($old) { [Math]::Max(0, $hrac.Diamonds - $old.Diamonds) } else { $hrac.Diamonds }
        $deb = if ($old) { [Math]::Max(0, $hrac.Debris - $old.Debris) } else { $hrac.Debris }
        $dist = if ($old) { [Math]::Max(0, [Math]::Round($hrac.Distance - $old.Distance, 1)) } else { $hrac.Distance }
        $j = if ($old) { [Math]::Max(0, $hrac.Jumps - $old.Jumps) } else { $hrac.Jumps }
        $cr = if ($old) { [Math]::Max(0, $hrac.Crafted - $old.Crafted) } else { $hrac.Crafted }
        $tr = if ($old) { [Math]::Max(0, $hrac.Traded - $old.Traded) } else { $hrac.Traded }
        $br = if ($old) { [Math]::Max(0, $hrac.Bred - $old.Bred) } else { $hrac.Bred }
        $tk = if ($old) { [Math]::Max(0, $hrac.Talked - $old.Talked) } else { $hrac.Talked }

        $totH += $h; $totD += $dt; $totDMG += $dd; $totMK += $mk; $totDK += $dk; $totWK += $wk; $totBM += $bm; $totBP += $bp;
        $totDIA += $dia; $totDEB += $deb; $totDIST += $dist; $totJ += $j; $totCR += $cr; $totTR += $tr; $totBR += $br; $totTK += $tk;

        $listDelta += [PSCustomObject]@{
            Nickname = $nickname
            Hours = $h
            TimePlayedText = $t
            Deaths = $dt
            SinceDeathHours = $hrac.SinceDeathHours
            DamageDealt = $dd
            MobKills = $mk
            DragonKills = $dk
            WitherKills = $wk
            BlocksMined = $bm
            BlocksPlaced = $bp
            Diamonds = $dia
            Debris = $deb
            Distance = $dist
            Jumps = $j
            Crafted = $cr
            Traded = $tr
            Bred = $br
            Talked = $tk
        }
    }

    $sortedDelta = $listDelta | Sort-Object Hours -Descending
    $tableHtml = Build-TableContent $sortedDelta $totH $totD $totDMG $totMK $totDK $totWK $totBM $totBP $totDIA $totDEB $totDIST $totJ $totCR $totTR $totBR $totTK
    return $tableHtml
}

# --- GENERACE TABULEK PRO VŠECHNA OBDOBÍ ---
$tableAllTimeHtml = Build-TableContent $serazeniAllTime $totalHours $totalDeaths $totalDamageDealt $totalMobKills $totalDragonKills $totalWitherKills $totalMined $totalPlaced $totalDiamonds $totalDebris $totalDistance $totalJumps $totalCrafted $totalTraded $totalBred $totalTalked
$tableMonthHtml   = Get-DeltaStatsForDays 30
$tableWeekHtml    = Get-DeltaStatsForDays 7
$tableDayHtml     = Get-DeltaStatsForDays 1

# --- FINAL HTML ASSEMBLY ---
$finalHtml = @"
<!DOCTYPE html>
<html lang='cs'>
<head>
    <meta charset='UTF-8'>
    <title>Forever Reeds MC Server</title>
    <style>
        body { font-family: sans-serif; background: #1e1e1e; color: #fff; padding: 40px; }
        h1 { color: #5cff5c; margin-bottom: 5px; }
        .update-time { color: #aaa; font-size: 0.9em; margin-bottom: 25px; border-bottom: 2px solid #444; padding-bottom: 15px; }
        
        .tab-buttons { display: flex; gap: 12px; margin-bottom: 20px; flex-wrap: wrap; }
        .tab-btn { background: #2e2e2e; color: #aaa; border: 2px solid #444; padding: 10px 24px; cursor: pointer; border-radius: 6px; font-weight: bold; font-size: 1em; transition: 0.2s; }
        .tab-btn:hover { background: #383838; color: #fff; }
        .tab-btn.active { background: #4CAF50; color: white; border-color: #4CAF50; }
        
        .tab-content { display: none; }
        .tab-content.active { display: block; }

        table { width: 100%; border-collapse: collapse; margin-top: 10px; table-layout: fixed; }
        th, td { border: 1px solid #444; padding: 12px; text-align: left; vertical-align: middle; }
        th { background: #2e2e2e; color: #5cff5c; }
        tr:nth-child(even) { background: #252525; }
        tr:hover { background: #333; }
        .stat-name { font-weight: bold; background: #2a2a2a; width: 240px; }
        .server-total { font-weight: bold; color: #5cff5c; background: #222; }
        .player-header { font-weight: bold; text-align: left; }
    </style>
    <script>
    function showTab(tabId, btn) {
        document.querySelectorAll('.tab-content').forEach(function(content) {
            content.classList.remove('active');
            content.style.display = 'none';
        });

        document.querySelectorAll('.tab-btn').forEach(function(button) {
            button.classList.remove('active');
        });

        var target = document.getElementById(tabId);
        if (target) {
            target.classList.add('active');
            target.style.display = 'block';
        }
        if (btn) {
            btn.classList.add('active');
        }
    }
    </script>
</head>
<body>
    <h1>Forever Reeds MC Server</h1>
    <div class='update-time'>Last updated: $currentDateTime</div>

    <!-- Skupina tlačítek -->
    <div class="tab-buttons">
        <button class="tab-btn active" onclick="showTab('stats-all', this)">Celá doba 🏆</button>
        <button class="tab-btn" onclick="showTab('stats-month', this)">Měsíc 📅</button>
        <button class="tab-btn" onclick="showTab('stats-week', this)">Týden 📊</button>
        <button class="tab-btn" onclick="showTab('stats-day', this)">Den ⚡</button>
        <button class="tab-btn" onclick="showTab('world-map', this)">Mapa světa 🗺️</button>
    </div>

    <!-- Obsah pro Celou dobu -->
    <div id="stats-all" class="tab-content active">
        $tableAllTimeHtml
    </div>

    <!-- Obsah pro Měsíc -->
    <div id="stats-month" class="tab-content">
        $tableMonthHtml
    </div>

    <!-- Obsah pro Týden -->
    <div id="stats-week" class="tab-content">
        $tableWeekHtml
    </div>

    <!-- Obsah pro Den -->
    <div id="stats-day" class="tab-content">
        $tableDayHtml
    </div>

    <!-- Obsah pro Mapu světa -->
    <div id="world-map" class="tab-content" style="width: 100%; height: 80vh;">
        <iframe src="mapa/index.html" style="width: 100%; height: 100%; border: none; border-radius: 8px;"></iframe>
    </div>
</body>
</html>
"@

$finalHtml | Out-File -FilePath 'index.html' -Encoding utf8
