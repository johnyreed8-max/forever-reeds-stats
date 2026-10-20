# Safety check: If stats & history folders do not exist, create them
if (-not (Test-Path "stats")) { New-Item -ItemType Directory -Path "stats" | Out-Null };
$historyFolder = "stats_history";
if (-not (Test-Path $historyFolder)) { New-Item -ItemType Directory -Path $historyFolder | Out-Null };

# Ensure correct time formatting
$currentDateTime = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, 'Europe/Prague').ToString("dd.MM.yyyy HH:mm:ss");
$usCulture = [System.Globalization.CultureInfo]::GetCultureInfo("cs-CZ");

# Exact UUID mapping for your server
$jmena = @{
    '10d807ae-f713-4d9d-966d-a6e7b4bddafd' = 'dufe_com';
    '4b91ee4a-88d0-48f0-b111-8f8e6e3647b7' = 'KarlTheBroken';
    '90afe98a-4c6a-4469-959e-d55070e4b6b8' = 'Kathryn_Reed';
    '953decf3-5ac0-4108-965f-3b82cea52143' = 'Alex_Reed';
    'aa14ea23-012a-48b8-b39d-3e280496e83a' = 'Johny_Reed';
    'bd265486-b561-4510-860c-76a0bc9ea3ae' = 'ettelwen'
};

# --- NAČTENÍ AKTUÁLNÍCH STATISTIK ---
$hraciDataAllTime = @();
$snapshotTodayData = @{};

# Global totals All-Time
$totalHours = 0; $totalDeaths = 0; $totalMobKills = 0; $totalMined = 0; $totalPlaced = 0; $totalTraded = 0; $totalDistance = 0; $totalQuit = 0;
$totalDamageDealt = 0; $totalDamageTaken = 0; $totalDiamonds = 0; $totalDebris = 0; $totalJumps = 0;
$totalDragonKills = 0; $totalWitherKills = 0; $totalCrafted = 0; $totalBred = 0;

$statsFiles = Get-ChildItem 'stats/*.json' -ErrorAction SilentlyContinue;

$statsFiles | ForEach-Object {
    $file = $_;
    $uuid = $file.BaseName;
    $nickname = if ($jmena.Contains($uuid)) { $jmena[$uuid] } else { $uuid };
    $json = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json;
    $custom = $json.stats.'minecraft:custom';
    $mined = $json.stats.'minecraft:mined';
    $killed = $json.stats.'minecraft:killed';
    $crafted = $json.stats.'minecraft:crafted';
    
    # Raw values
    $ticks = 0;
    if ($custom.'minecraft:play_time') { $ticks = $custom.'minecraft:play_time' } elseif ($custom.'minecraft:play_one_minute') { $ticks = $custom.'minecraft:play_one_minute' };
    
    $hours = [Math]::Round($ticks / 20 / 60 / 60, 1);
    $days = [Math]::Round($hours / 24, 1);
    $timePlayedText = "$hours hrs / $days days";

    $deaths = if ($custom.'minecraft:deaths') { $custom.'minecraft:deaths' } else { 0 };
    $sinceDeathTicks = if ($custom.'minecraft:time_since_death') { $custom.'minecraft:time_since_death' } else { 0 };
    $sinceDeathHours = [Math]::Round($sinceDeathTicks / 20 / 60 / 60, 1);
    
    $damageDealt = if ($custom.'minecraft:damage_dealt') { [Math]::Round($custom.'minecraft:damage_dealt' / 10, 0) } else { 0 };
    $damageTaken = if ($custom.'minecraft:damage_taken') { [Math]::Round($custom.'minecraft:damage_taken' / 10, 0) } else { 0 };
    $mobKills = if ($custom.'minecraft:mob_kills') { $custom.'minecraft:mob_kills' } else { 0 };
    $dragonKills = if ($killed.'minecraft:ender_dragon') { $killed.'minecraft:ender_dragon' } else { 0 };
    $witherKills = if ($killed.'minecraft:wither') { $killed.'minecraft:wither' } else { 0 };
    $quit = if ($custom.'minecraft:leave_game') { $custom.'minecraft:leave_game' } else { 0 };
    $traded = if ($custom.'minecraft:traded_with_villager') { $custom.'minecraft:traded_with_villager' } else { 0 };
    $jumps = if ($custom.'minecraft:jump') { $custom.'minecraft:jump' } else { 0 };
    $animalsBred = if ($custom.'minecraft:animals_bred') { $custom.'minecraft:animals_bred' } else { 0 };
    
    $totalPlayerCrafted = 0;
    if ($crafted) { $crafted.psobject.Properties | ForEach-Object { $totalPlayerCrafted += $_.Value } };
    
    $walk = if ($custom.'minecraft:walk_one_cm') { $custom.'minecraft:walk_one_cm' } else { 0 };
    $sprint = if ($custom.'minecraft:sprint_one_cm') { $custom.'minecraft:sprint_one_cm' } else { 0 };
    $crouch = if ($custom.'minecraft:crouch_one_cm') { $custom.'minecraft:crouch_one_cm' } else { 0 };
    $distanceKm = [Math]::Round(($walk + $sprint + $crouch) / 100 / 1000, 1);
    
    $blocksMined = 0;
    if ($mined) { $mined.psobject.Properties | ForEach-Object { $blocksMined += $_.Value } };
    
    $blocksPlaced = 0;
    if ($json.stats.'minecraft:used') { 
        $json.stats.'minecraft:used'.psobject.Properties | ForEach-Object { 
            if ($_.Name -notmatch 'minecart|boat|sword|axe|pickaxe|shovel|hoe|shear|flint|bucket|potion|apple|stew|bread|pie|beef|pork|chicken|mutton|salmon|cod|cookie|carrot|potato|kelp|melon|berries|soup') { 
                $blocksPlaced += $_.Value;
            } 
        } 
    };
    
    $diamondOre = if ($mined.'minecraft:diamond_ore') { $mined.'minecraft:diamond_ore' } else { 0 };
    $deepslateDiamondOre = if ($mined.'minecraft:deepslate_diamond_ore') { $mined.'minecraft:deepslate_diamond_ore' } else { 0 };
    $totalPlayerDiamonds = $diamondOre + $deepslateDiamondOre;
    $ancientDebris = if ($mined.'minecraft:ancient_debris') { $mined.'minecraft:ancient_debris' } else { 0 };
    
    # Save current raw values for future snapshot
    $snapshotTodayData[$nickname] = @{
        Hours = $hours;
        Deaths = $deaths;
        DamageDealt = $damageDealt;
        DamageTaken = $damageTaken;
        MobKills = $mobKills;
        DragonKills = $dragonKills;
        WitherKills = $witherKills;
        BlocksMined = $blocksMined;
        BlocksPlaced = $blocksPlaced;
        Diamonds = $totalPlayerDiamonds;
        Debris = $ancientDebris;
        Distance = $distanceKm;
        Jumps = $jumps;
        Crafted = $totalPlayerCrafted;
        Traded = $traded;
        Bred = $animalsBred;
        Quit = $quit
    };

    # Cumulative totals
    $totalHours += $hours; $totalDeaths += $deaths; $totalMobKills += $mobKills; $totalMined += $blocksMined; $totalPlaced += $blocksPlaced; $totalTraded += $traded; $totalDistance += $distanceKm; $totalQuit += $quit;
    $totalDamageDealt += $damageDealt; $totalDamageTaken += $damageTaken; $totalDiamonds += $totalPlayerDiamonds; $totalDebris += $ancientDebris; $totalJumps += $jumps;
    $totalDragonKills += $dragonKills; $totalWitherKills += $witherKills; $totalCrafted += $totalPlayerCrafted; $totalBred += $animalsBred;

    $hraciDataAllTime += [PSCustomObject]@{
        Nickname = $nickname;
        Hours = $hours;
        TimePlayedText = $timePlayedText;
        Deaths = $deaths;
        SinceDeathHours = $sinceDeathHours;
        DamageDealt = $damageDealt;
        DamageTaken = $damageTaken;
        MobKills = $mobKills;
        DragonKills = $dragonKills;
        WitherKills = $witherKills;
        BlocksMined = $blocksMined;
        BlocksPlaced = $blocksPlaced;
        Diamonds = $totalPlayerDiamonds;
        Debris = $ancientDebris;
        Distance = $distanceKm;
        Jumps = $jumps;
        Crafted = $totalPlayerCrafted;
        Traded = $traded;
        Bred = $animalsBred;
        Quit = $quit
    };
};

# Uložíme dnešní snapshot
$todayStr = (Get-Date).ToString("yyyy-MM-dd");
$todaySnapshotFile = "$historyFolder/stats_$todayStr.json";
$snapshotTodayData | ConvertTo-Json -Depth 5 | Set-Content -Path $todaySnapshotFile -Encoding utf8;

# Sorting
$serazeniAllTime = $hraciDataAllTime | Sort-Object Hours -Descending;

# --- HTML Table Builder ---
function Build-TableContent ($listHraci, $tHours, $tDeaths, $tDamage, $tMobKills, $tDragon, $tWither, $tMined, $tPlaced, $tDia, $tDebris, $tDist, $tJumps, $tCrafted, $tTraded, $tBred, $tQuit) {
    $out = "<table>";
    $out += "<tr><th class='stat-name'>Statistic</th>";
    $listHraci | ForEach-Object { $out += "<th class='player-header'>$($_.Nickname)</th>" };
    $out += "<th class='server-total'>Server total</th></tr>";

    $AddRow = {
        param($label, $property, $formatSuffix = "", $serverValue = "", $lowerWins = $false, $sortProperty = "")
        $evalProperty = if ($sortProperty -ne "") { $sortProperty } else { $property };

        $values = if ($lowerWins) {
            $listHraci | Select-Object -ExpandProperty $evalProperty | Sort-Object
        } else {
            $listHraci | Select-Object -ExpandProperty $evalProperty | Sort-Object -Descending
        };

        $top1 = $values[0]; $top2 = $values[1]; $top3 = $values[2];

        $row = "<tr><td class='stat-name'>$label</td>";
        $listHraci | ForEach-Object {
            $hrac = $_;
            $val = $hrac.$property;
            $evalVal = $hrac.$evalProperty;
            $formattedVal = if ($val -is [ValueType]) { $val.ToString("N0", $usCulture) } else { $val.ToString() };
            
            $medal = "";
            $cls = "";
            if ($evalVal -ne 0 -or (-not $lowerWins -and $evalProperty -ne "Deaths")) {
                if ($evalVal -eq $top1) { $medal = "<span class='medal'>👑</span>"; $cls = " class='r1'" } 
                elseif ($evalVal -eq $top2 -and $top2 -ne $top1) { $medal = "<span class='medal'>🥈</span>"; $cls = " class='r2'" } 
                elseif ($evalVal -eq $top3 -and $top3 -ne $top2 -and $top3 -ne $top1) { $medal = "<span class='medal'>🥉</span>"; $cls = " class='r3'" }
            };
            $unit = if ($formatSuffix -ne "") { "<span class='unit'> $formatSuffix</span>" } else { "" };
            $row += "<td$cls>$formattedVal$unit$medal</td>";
        };
        $formattedServerVal = if ($serverValue -is [ValueType]) { $serverValue.ToString("N0", $usCulture) } else { $serverValue };
        $finalServerVal = if ($serverValue -ne "") { $formattedServerVal } else { "—" };
        $serverUnit = if ($formatSuffix -ne "" -and $serverValue -ne "") { "<span class='unit'> $formatSuffix</span>" } else { "" };
        $row += "<td class='server-total'>$finalServerVal$serverUnit</td></tr>";
        return $row
    };

    $out += & $AddRow "⏱️ Time Played" "TimePlayedText" "" $tHours $false "Hours";
    $out += & $AddRow "💀 Deaths" "Deaths" "" $tDeaths $true;
    $out += & $AddRow "🛡️ Time Since Last Death" "SinceDeathHours" "hrs" "" $false "SinceDeathHours";
    $out += & $AddRow "⚔️ Damage Dealt (HP)" "DamageDealt" "" $tDamage;
    $out += & $AddRow "🧟 Mob Kills" "MobKills" "" $tMobKills;
    $out += & $AddRow "🐉 Ender Dragon Kills" "DragonKills" "" $tDragon;
    $out += & $AddRow "💀 Wither Kills" "WitherKills" "" $tWither;
    $out += & $AddRow "⛏️ Blocks Mined" "BlocksMined" "" $tMined;
    $out += & $AddRow "🧱 Blocks Placed" "BlocksPlaced" "" $tPlaced;
    $out += & $AddRow "💎 Diamond Ore Mined" "Diamonds" "" $tDia;
    $out += & $AddRow "🔥 Ancient Debris Mined" "Debris" "" $tDebris;
    $out += & $AddRow "🧭 Distance Traveled" "Distance" "km" $tDist;
    $out += & $AddRow "🦘 Jump Count" "Jumps" "" $tJumps;
    $out += & $AddRow "🔨 Times Crafted" "Crafted" "" $tCrafted;
    $out += & $AddRow "🤝 Trades with Villagers" "Traded" "" $tTraded;
    $out += & $AddRow "🐄 Animals Bred" "Bred" "" $tBred;
    $out += & $AddRow "🚪 Games Quit" "Quit" "" $tQuit;
    $out += "</table>";

    return $out
}

# --- UNIVERZÁLNÍ FUNKCE PRO VÝPOČET DELTY ZA URČITÝ POČET DNÍ ---
function Get-DeltaStatsForDays($days) {
    $targetDateStr = (Get-Date).AddDays(-$days).ToString("yyyy-MM-dd");

    # Najdeme starší snapshot
    $oldSnapshotFile = Get-ChildItem "$historyFolder/stats_*.json" -ErrorAction SilentlyContinue | 
        Where-Object { $_.BaseName -le "stats_$targetDateStr" } | 
        Sort-Object Name -Descending | Select-Object -First 1;

    if (-not $oldSnapshotFile) {
        $oldSnapshotFile = Get-ChildItem "$historyFolder/stats_*.json" -ErrorAction SilentlyContinue | 
            Sort-Object Name | Select-Object -First 1;
    };

    $oldStatsData = @{};
    if ($oldSnapshotFile) {
        $rawOld = Get-Content -Path $oldSnapshotFile.FullName -Raw | ConvertFrom-Json;
        $rawOld.psobject.Properties | ForEach-Object { $oldStatsData[$_.Name] = $_.Value };
    };

    $listDelta = @();
    $totH = 0; $totD = 0; $totDMG = 0; $totMK = 0; $totDK = 0; $totWK = 0; $totBM = 0; $totBP = 0; $totDIA = 0; $totDEB = 0; $totDIST = 0; $totJ = 0; $totCR = 0; $totTR = 0; $totBR = 0; $totTK = 0;

    foreach ($hrac in $hraciDataAllTime) {
        $nickname = $hrac.Nickname;
        $old = if ($oldStatsData.ContainsKey($nickname)) { $oldStatsData[$nickname] } else { $null };

        $h = if ($old) { [Math]::Max(0, [Math]::Round($hrac.Hours - $old.Hours, 1)) } else { $hrac.Hours };
        $d = [Math]::Round($h / 24, 1);
        $t = "$h hrs / $d days";

        $dt = if ($old) { [Math]::Max(0, $hrac.Deaths - $old.Deaths) } else { $hrac.Deaths };
        $dd = if ($old) { [Math]::Max(0, $hrac.DamageDealt - $old.DamageDealt) } else { $hrac.DamageDealt };
        $mk = if ($old) { [Math]::Max(0, $hrac.MobKills - $old.MobKills) } else { $hrac.MobKills };
        $dk = if ($old) { [Math]::Max(0, $hrac.DragonKills - $old.DragonKills) } else { $hrac.DragonKills };
        $wk = if ($old) { [Math]::Max(0, $hrac.WitherKills - $old.WitherKills) } else { $hrac.WitherKills };
        $bm = if ($old) { [Math]::Max(0, $hrac.BlocksMined - $old.BlocksMined) } else { $hrac.BlocksMined };
        $bp = if ($old) { [Math]::Max(0, $hrac.BlocksPlaced - $old.BlocksPlaced) } else { $hrac.BlocksPlaced };
        $dia = if ($old) { [Math]::Max(0, $hrac.Diamonds - $old.Diamonds) } else { $hrac.Diamonds };
        $deb = if ($old) { [Math]::Max(0, $hrac.Debris - $old.Debris) } else { $hrac.Debris };
        $dist = if ($old) { [Math]::Max(0, [Math]::Round($hrac.Distance - $old.Distance, 1)) } else { $hrac.Distance };
        $j = if ($old) { [Math]::Max(0, $hrac.Jumps - $old.Jumps) } else { $hrac.Jumps };
        $cr = if ($old) { [Math]::Max(0, $hrac.Crafted - $old.Crafted) } else { $hrac.Crafted };
        $tr = if ($old) { [Math]::Max(0, $hrac.Traded - $old.Traded) } else { $hrac.Traded };
        $br = if ($old) { [Math]::Max(0, $hrac.Bred - $old.Bred) } else { $hrac.Bred };
        $tk = if ($old -and $null -ne $old.Quit) { [Math]::Max(0, $hrac.Quit - $old.Quit) } elseif ($old) { 0 } else { $hrac.Quit };

        $totH += $h; $totD += $dt; $totDMG += $dd; $totMK += $mk; $totDK += $dk; $totWK += $wk; $totBM += $bm; $totBP += $bp;
        $totDIA += $dia; $totDEB += $deb; $totDIST += $dist; $totJ += $j; $totCR += $cr; $totTR += $tr; $totBR += $br; $totTK += $tk;

        $listDelta += [PSCustomObject]@{
            Nickname = $nickname;
            Hours = $h;
            TimePlayedText = $t;
            Deaths = $dt;
            SinceDeathHours = $hrac.SinceDeathHours;
            DamageDealt = $dd;
            MobKills = $mk;
            DragonKills = $dk;
            WitherKills = $wk;
            BlocksMined = $bm;
            BlocksPlaced = $bp;
            Diamonds = $dia;
            Debris = $deb;
            Distance = $dist;
            Jumps = $j;
            Crafted = $cr;
            Traded = $tr;
            Bred = $br;
            Quit = $tk
        };
    };

    $sortedDelta = $listDelta | Sort-Object Hours -Descending;
    $tableHtml = Build-TableContent $sortedDelta $totH $totD $totDMG $totMK $totDK $totWK $totBM $totBP $totDIA $totDEB $totDIST $totJ $totCR $totTR $totBR $totTK;
    return $tableHtml
}

# --- GENERACE TABULEK PRO VŠECHNA OBDOBÍ ---
$tableAllTimeHtml = Build-TableContent $serazeniAllTime $totalHours $totalDeaths $totalDamageDealt $totalMobKills $totalDragonKills $totalWitherKills $totalMined $totalPlaced $totalDiamonds $totalDebris $totalDistance $totalJumps $totalCrafted $totalTraded $totalBred $totalQuit;
$tableMonthHtml   = Get-DeltaStatsForDays 30;
$tableWeekHtml    = Get-DeltaStatsForDays 7;
$tableDayHtml     = Get-DeltaStatsForDays 1;

# --- FINAL HTML ASSEMBLY ---
$finalHtml = @"
<!DOCTYPE html>
<html lang='cs'>
<head>
    <meta charset='UTF-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1'>
    <meta name='color-scheme' content='dark'>
    <title>Forever Reeds MC Server</title>
    <link rel='preconnect' href='https://fonts.googleapis.com'>
    <link rel='preconnect' href='https://fonts.gstatic.com' crossorigin>
    <link href='https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:wght@600;700;800&family=IBM+Plex+Sans:wght@400;500;600&display=swap' rel='stylesheet'>
    <style>
        :root {
            --bg: #12151b;
            --panel: #1a1f28;
            --panel-2: #212835;
            --line: #2b3342;
            --text: ##bdbdbd;
            --muted: #8d99ab;
            --emerald: #3ddc97;
            --gold: #f4c95d;
            --silver: ##fafcfc;
            --bronze: #d99a6c;
        }
        * { box-sizing: border-box; }
        html, body { height: 100%; margin: 0; overflow: hidden; }
        body {
            background: var(--bg);
            color: var(--text);
            font-family: 'IBM Plex Sans', system-ui, 'Segoe UI', sans-serif;
        }

        .app {
            height: 100%;
            display: flex;
            flex-direction: column;
            gap: clamp(8px, 1.6vh, 16px);
            padding: clamp(10px, 2vh, 24px) clamp(10px, 2vw, 32px);
        }

        header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 16px;
            flex-wrap: wrap;
        }
        .brand h1 {
            margin: 0;
            font-family: 'Bricolage Grotesque', system-ui, sans-serif;
            font-weight: 800;
            font-size: clamp(20px, 3.4vh, 32px);
            letter-spacing: -0.02em;
            line-height: 1.1;
        }
        .update-time {
            margin-top: 4px;
            color: var(--muted);
            font-size: clamp(11px, 1.5vh, 13px);
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .dot {
            width: 7px; height: 7px; border-radius: 50%;
            background: var(--emerald);
            box-shadow: 0 0 0 0 rgba(61, 220, 151, .6);
            animation: pulse 2.4s ease-out infinite;
        }
        @keyframes pulse {
            0% { box-shadow: 0 0 0 0 rgba(61, 220, 151, .55); }
            70% { box-shadow: 0 0 0 7px rgba(61, 220, 151, 0); }
            100% { box-shadow: 0 0 0 0 rgba(61, 220, 151, 0); }
        }
        @media (prefers-reduced-motion: reduce) { .dot { animation: none; } }

        .tabs {
            display: inline-flex;
            gap: 2px;
            padding: 4px;
            background: var(--panel);
            border: 1px solid var(--line);
            border-radius: 12px;
        }
        .tab-btn {
            font: inherit;
            font-weight: 500;
            font-size: clamp(12px, 1.7vh, 14px);
            color: var(--muted);
            background: transparent;
            border: 0;
            padding: 8px 16px;
            border-radius: 8px;
            cursor: pointer;
            white-space: nowrap;
            transition: background .15s, color .15s;
        }
        .tab-btn:hover { color: var(--text); background: var(--panel-2); }
        .tab-btn:focus-visible { outline: 2px solid var(--emerald); outline-offset: 2px; }
        .tab-btn.active { background: var(--emerald); color: #08261a; font-weight: 600; }

        main { flex: 1; min-height: 0; }
        .tab-content { display: none; height: 100%; }
        .tab-content.active { display: block; }

        .card {
            height: 100%;
            background: var(--panel);
            border: 1px solid var(--line);
            border-radius: 14px;
            overflow: auto;
        }
        .card.map { overflow: hidden; }
        .card iframe { width: 100%; height: 100%; border: 0; display: block; }

        table {
            width: 100%;
            height: 100%;
            min-width: 780px;
            min-height: 540px;
            border-collapse: separate;
            border-spacing: 0;
            table-layout: fixed;
            font-size: clamp(11px, 1.8vh, 15px);
            font-variant-numeric: tabular-nums;
        }
        th, td {
            padding: 0 clamp(8px, 1vw, 16px);
            text-align: left;
            vertical-align: middle;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            border-bottom: 1px solid var(--line);
        }
        tr:last-child td { border-bottom: 0; }
        tr:first-child th {
            position: sticky; top: 0; z-index: 2;
            background: var(--panel-2);
            font-family: 'Bricolage Grotesque', system-ui, sans-serif;
            font-weight: 700;
            font-size: clamp(12px, 1.9vh, 16px);
            color: var(--text);
        }
        tr:not(:first-child):hover td { background: rgba(255, 255, 255, .035); }

        .stat-name, th.stat-name {
            width: clamp(170px, 17vw, 250px);
            color: var(--muted);
            font-weight: 500;
            position: sticky; left: 0; z-index: 1;
            background: var(--panel);
            border-right: 1px solid var(--line);
        }
        tr:first-child th.stat-name { z-index: 3; background: var(--panel-2); color: var(--muted); }
        tr:not(:first-child):hover td.stat-name { background: #1e2430; }

        .server-total { color: var(--emerald); font-weight: 600; background: rgba(61, 220, 151, .06); }
        th.server-total { background: rgba(61, 220, 151, .12) !important; color: var(--emerald) !important; }

        td.r1 { color: var(--gold); font-weight: 600; background: rgba(244, 201, 93, .08); }
        td.r2 { color: var(--silver); }
        td.r3 { color: var(--bronze); }
        .medal { margin-left: 6px; font-size: .9em; }
        .unit { color: var(--muted); font-weight: 400; font-size: .9em; }
        td.r1 .unit { color: inherit; opacity: .7; }
    </style>
    <script>
    function showTab(tabId) {
        var tabs = document.querySelectorAll('.tab-content');
        for (var i = 0; i < tabs.length; i++) { tabs[i].classList.remove('active'); }
        var btns = document.querySelectorAll('.tab-btn');
        for (var j = 0; j < btns.length; j++) {
            btns[j].classList.toggle('active', btns[j].getAttribute('data-tab') === tabId);
        }
        var target = document.getElementById(tabId);
        if (target) { target.classList.add('active'); }

        // Mapu načteme až při prvním otevření, aby se správně spočítala velikost
        if (tabId === 'world-map') {
            var frame = document.getElementById('map-frame');
            if (frame && !frame.getAttribute('src')) { frame.setAttribute('src', frame.getAttribute('data-src')); }
        }
        try { history.replaceState(null, '', '#' + tabId); } catch (e) {}
    }

    document.addEventListener('DOMContentLoaded', function() {
        var btns = document.querySelectorAll('.tab-btn');
        for (var i = 0; i < btns.length; i++) {
            btns[i].addEventListener('click', function() { showTab(this.getAttribute('data-tab')); });
        }
        var wanted = location.hash.replace('#', '');
        if (wanted && document.getElementById(wanted)) { showTab(wanted); }
    });
    </script>
</head>
<body>
    <div class='app'>
        <header>
            <div class='brand'>
                <h1>Forever Reeds</h1>
                <div class='update-time'><span class='dot'></span>Updated $currentDateTime</div>
            </div>
            <nav class='tabs'>
                <button class='tab-btn active' data-tab='stats-all'>Lifetime 🏆</button>
                <button class='tab-btn' data-tab='stats-month'>Month 📅</button>
                <button class='tab-btn' data-tab='stats-week'>Week 📊</button>
                <button class='tab-btn' data-tab='stats-day'>Day ⚡</button>
                <button class='tab-btn' data-tab='world-map'>World map 🗺️</button>
            </nav>
        </header>

        <main>
            <section id='stats-all' class='tab-content active'>
                <div class='card'>$tableAllTimeHtml</div>
            </section>
            <section id='stats-month' class='tab-content'>
                <div class='card'>$tableMonthHtml</div>
            </section>
            <section id='stats-week' class='tab-content'>
                <div class='card'>$tableWeekHtml</div>
            </section>
            <section id='stats-day' class='tab-content'>
                <div class='card'>$tableDayHtml</div>
            </section>
            <section id='world-map' class='tab-content'>
                <div class='card map'>
                    <iframe id='map-frame' data-src='mapa/index.html' title='World map'></iframe>
                </div>
            </section>
        </main>
    </div>
</body>
</html>
"@;

$finalHtml | Out-File -FilePath 'index.html' -Encoding utf8;
