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

# --- NAČTENÍ STATISTIK ZA POSLEDNÍCH 14 DNÍ ---
$todayStr = (Get-Date).ToString("yyyy-MM-dd")
$todaySnapshotFile = "$historyFolder/stats_$todayStr.json"
$fourteenDaysAgoStr = (Get-Date).AddDays(-14).ToString("yyyy-MM-dd")

$oldSnapshotFile = Get-ChildItem "$historyFolder/stats_*.json" -ErrorAction SilentlyContinue | 
    Where-Object { $_.BaseName -le "stats_$fourteenDaysAgoStr" } | 
    Sort-Object Name -Descending | Select-Object -First 1

$oldStatsData = @{}
if ($oldSnapshotFile) {
    $rawOld = Get-Content$oldSnapshotFile.FullName -Raw | ConvertFrom-Json
    foreach ($prop in $rawOld.psobject.Properties) {$oldStatsData[$prop.Name] =$prop.Value
    }
}

# --- NAČTENÍ AKTUÁLNÍCH STATISTIK ---
$hraciDataAllTime = @()
$hraciData14Days = @();$snapshotTodayData = @{}

# Global totals All-Time
$totalHours = 0; $totalDeaths = 0; $totalMobKills = 0; $totalMined = 0; $totalPlaced = 0; $totalTraded = 0; $totalDistance = 0; $totalTalked = 0;
$totalDamageDealt = 0; $totalDamageTaken = 0; $totalDiamonds = 0; $totalDebris = 0; $totalJumps = 0;
$totalDragonKills = 0; $totalWitherKills = 0; $totalCrafted = 0; $totalBred = 0;

# Global totals 14 Days
$totalHours14 = 0; $totalDeaths14 = 0; $totalMobKills14 = 0; $totalMined14 = 0; $totalPlaced14 = 0; $totalTraded14 = 0; $totalDistance14 = 0; $totalTalked14 = 0;
$totalDamageDealt14 = 0; $totalDamageTaken14 = 0; $totalDiamonds14 = 0; $totalDebris14 = 0; $totalJumps14 = 0;
$totalDragonKills14 = 0; $totalWitherKills14 = 0; $totalCrafted14 = 0; $totalBred14 = 0;

$statsFiles = Get-ChildItem 'stats/*.json' -ErrorAction SilentlyContinue

foreach ($file in$statsFiles) {
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
    if ($crafted) { 
        foreach ($p in$crafted.psobject.Properties) { 
            $totalPlayerCrafted +=$p.Value 
        } 
    }
    
    $walk = if ($custom.'minecraft:walk_one_cm') { $custom.'minecraft:walk_one_cm' } else { 0 }$sprint = if ($custom.'minecraft:sprint_one_cm') {$custom.'minecraft:sprint_one_cm' } else { 0 }
    $distanceKm = [Math]::Round(($walk + $sprint) / 100 / 1000, 1)$blocksMined = 0
    if ($mined) { 
        foreach ($p in$mined.psobject.Properties) { 
            $blocksMined +=$p.Value 
        } 
    }
    
    $blocksPlaced = 0
    if ($json.stats.'minecraft:used') { 
        foreach ($p in$json.stats.'minecraft:used'.psobject.Properties) { 
            if ($p.Name -notmatch 'minecart|boat|sword|axe|pickaxe|shovel|hoe|shear|flint|bucket|potion|apple|stew|bread|pie|beef|pork|chicken|mutton|salmon|cod|cookie|carrot|potato|kelp|melon|berries|soup') { 
                $blocksPlaced +=$p.Value 
            } 
        } 
    }
    
    $diamondOre = if ($mined.'minecraft:diamond_ore') { $mined.'minecraft:diamond_ore' } else { 0 }$deepslateDiamondOre = if ($mined.'minecraft:deepslate_diamond_ore') {$mined.'minecraft:deepslate_diamond_ore' } else { 0 }
    $totalPlayerDiamonds =$diamondOre + $deepslateDiamondOre$ancientDebris = if ($mined.'minecraft:ancient_debris') {$mined.'minecraft:ancient_debris' } else { 0 }
    
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

    # 14-day Delta Calculation
    $old = if ($oldStatsData.ContainsKey($nickname)) { $oldStatsData[$nickname] } else { $null }$h14 = if ($old) { [Math]::Max(0, [Math]::Round($hours - $old.Hours, 1)) } else {$hours }
    $d14 = [Math]::Round($h14 / 24, 1)
    $t14 = "$h14 hrs / $d14 days"

    $dt14 = if ($old) { [Math]::Max(0,$deaths - $old.Deaths) } else {$deaths }
    $dd14 = if ($old) { [Math]::Max(0, $damageDealt -$old.DamageDealt) } else { $damageDealt }$mk14 = if ($old) { [Math]::Max(0,$mobKills - $old.MobKills) } else {$mobKills }
    $dk14 = if ($old) { [Math]::Max(0, $dragonKills -$old.DragonKills) } else { $dragonKills }$wk14 = if ($old) { [Math]::Max(0,$witherKills - $old.WitherKills) } else {$witherKills }
    $bm14 = if ($old) { [Math]::Max(0, $blocksMined -$old.BlocksMined) } else { $blocksMined }$bp14 = if ($old) { [Math]::Max(0,$blocksPlaced - $old.BlocksPlaced) } else {$blocksPlaced }
    $dia14 = if ($old) { [Math]::Max(0, $totalPlayerDiamonds -$old.Diamonds) } else { $totalPlayerDiamonds }$deb14 = if ($old) { [Math]::Max(0,$ancientDebris - $old.Debris) } else {$ancientDebris }
    $dist14 = if ($old) { [Math]::Max(0, [Math]::Round($distanceKm -$old.Distance, 1)) } else { $distanceKm }$j14 = if ($old) { [Math]::Max(0,$jumps - $old.Jumps) } else {$jumps }
    $cr14 = if ($old) { [Math]::Max(0, $totalPlayerCrafted -$old.Crafted) } else { $totalPlayerCrafted }$tr14 = if ($old) { [Math]::Max(0,$traded - $old.Traded) } else {$traded }
    $br14 = if ($old) { [Math]::Max(0, $animalsBred -$old.Bred) } else { $animalsBred }$tk14 = if ($old) { [Math]::Max(0,$talked - $old.Talked) } else {$talked }

    $totalHours14 +=$h14; $totalDeaths14 +=$dt14; $totalMobKills14 +=$mk14; $totalMined14 +=$bm14; $totalPlaced14 +=$bp14; $totalTraded14 +=$tr14; $totalDistance14 +=$dist14; $totalTalked14 +=$tk14
    $totalDamageDealt14 +=$dd14; $totalDiamonds14 +=$dia14; $totalDebris14 +=$deb14; $totalJumps14 +=$j14; $totalDragonKills14 +=$dk14; $totalWitherKills14 +=$wk14; $totalCrafted14 +=$cr14; $totalBred14 +=$br14

    $hraciData14Days += [PSCustomObject]@{
        Nickname = $nickname
        Hours = $h14
        TimePlayedText = $t14
        Deaths = $dt14
        SinceDeathHours = $sinceDeathHours
        DamageDealt = $dd14
        MobKills = $mk14
        DragonKills = $dk14
        WitherKills = $wk14
        BlocksMined = $bm14
        BlocksPlaced = $bp14
        Diamonds = $dia14
        Debris = $deb14
        Distance = $dist14
        Jumps = $j14
        Crafted = $cr14
        Traded = $tr14
        Bred = $br14
        Talked = $tk14
    }
}

# Save today's snapshot
$snapshotTodayData \vert{} ConvertTo-Json -Depth 5 \vert{} Set-Content -Path$todaySnapshotFile -Encoding utf8

# Sorting
$serazeniAllTime =$hraciDataAllTime | Sort-Object Hours -Descending
$serazeni14Days =$hraciData14Days | Sort-Object Hours -Descending

# HTML Table Builder
function Build-TableContent ($listHraci,$tHours, $tDeaths,$tDamage, $tMobKills,$tDragon, $tWither,$tMined, $tPlaced,$tDia, $tDebris,$tDist, $tJumps,$tCrafted, $tTraded,$tBred, $tTalked) {$out = "<table>"
    $out += "<tr><th class='stat-name'>Statistic</th>"
    $listHraci \vert{} ForEach-Object {$out += "<th class='player-header'>$($_.Nickname)</th>" }
    $out += "<th class='server-total'>SERVER TOTAL</th></tr>"

    $AddRow = {
        param($label, $property,$formatSuffix = "", $serverValue = "", $lowerWins = $false,$sortProperty = "")
        $evalProperty = if ($sortProperty -ne "") { $sortProperty } else {$property }

        $values = if ($lowerWins) {
            $listHraci \vert{} Select-Object -ExpandProperty$evalProperty | Sort-Object
        } else {
            $listHraci \vert{} Select-Object -ExpandProperty$evalProperty | Sort-Object -Descending
        }

        $top1 =$values[0]; $top2 =$values[1]; $top3 =$values[2]

        $row = "<tr><td class='stat-name'>$label</td>"
        foreach ($hrac in$listHraci) {
            $val =$hrac.$property$evalVal = $hrac.$evalProperty
            $formattedVal = if ($val -is [ValueType]) { $val.ToString("N0", $usCulture) } else { $val.ToString() }$medal = ""
            if ($evalVal -ne 0 -or (-not $lowerWins -and$evalProperty -ne "Deaths")) {
                if ($evalVal -eq $top1) {$medal = " 👑" }
                elseif ($evalVal -eq $top2 -and$top2 -ne $top1) {$medal = " 🥈" }
                elseif ($evalVal -eq $top3 -and$top3 -ne $top2 -and$top3 -ne $top1) {$medal = " 🥉" }
            }
            $row += "<td>$formattedVal$formatSuffix$medal</td>"
        }
        $formattedServerVal = if ($serverValue -is [ValueType]) { $serverValue.ToString("N0", $usCulture) } else { $serverValue }$finalServerVal = if ($serverValue -ne "") { $formattedServerVal } else { "—" }
        $row += "<td class='server-total'>$finalServerVal$formatSuffix</td></tr>"
        return $row
    }

    $out += &$AddRow "Time Played" "TimePlayedText" "" $tHours$false "Hours"
    $out += &$AddRow "Deaths" "Deaths" "" $tDeaths$true
    $out += &$AddRow "Time Since Last Death" "SinceDeathHours" "hrs" "" $false "SinceDeathHours"
    $out += &$AddRow "Damage Dealt (HP)" "DamageDealt" "" $tDamage
    $out += &$AddRow "Mob Kills" "MobKills" "" $tMobKills
    $out += &$AddRow "Ender Dragon Kills" "DragonKills" "" $tDragon
    $out += &$AddRow "Wither Kills" "WitherKills" "" $tWither
    $out += &$AddRow "Blocks Mined" "BlocksMined" "" $tMined
    $out += &$AddRow "Blocks Placed" "BlocksPlaced" "" $tPlaced
    $out += &$AddRow "Diamond Ore Mined" "Diamonds" "" $tDia
    $out += &$
