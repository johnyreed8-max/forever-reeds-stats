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
$hraciData14Days = @()
$snapshotTodayData = @{}

# Global totals All-Time
$totalHours = 0; $totalDeaths = 0; $totalMobKills = 0; $totalMined = 0; $totalPlaced = 0; $totalTraded = 0; $totalDistance = 0; $totalTalked = 0;
$totalDamageDealt = 0; $totalDamageTaken = 0; $totalDiamonds = 0; $totalDebris = 0; $totalJumps = 0;
$totalDragonKills = 0; $totalWitherKills = 0; $totalCrafted = 0; $totalBred = 0;

# Global totals 14 Days
$totalHours14 = 0; $totalDeaths14 = 0; $totalMobKills14 = 0; $totalMined14 = 0; $totalPlaced14 = 0; $totalTraded14 = 0; $totalDistance14 = 0; $totalTalked14 = 0;
$totalDamageDealt14 = 0; $totalDamageTaken14 = 0; $totalDiamonds14 = 0; $totalDebris14 = 0; $totalJumps14 = 0;
$totalDragonKills14 = 0; $totalWitherKills14 = 0; $totalCrafted14 = 0; $totalBred14 = 0;

Get-ChildItem 'stats/*.json' -ErrorAction SilentlyContinue | ForEach-Object {
    $uuid =$_.BaseName;
    $nickname = if ($jmena.Contains($uuid)) {$jmena[$uuid] } else {$uuid };
    $json = Get-Content$_.FullName -Raw | ConvertFrom-Json;
    $custom =$json.stats.'minecraft:custom';
    $mined =$json.stats.'minecraft:mined';
    $killed =$json.stats.'minecraft:killed';
    $crafted =$json.stats.'minecraft:crafted';
    
    # Raw values
    $ticks = 0;
    if ($custom.'minecraft:play_time') {$ticks = $custom.'minecraft:play_time' } elseif ($custom.'minecraft:play_one_minute') { $ticks =$custom.'minecraft:play_one_minute' };
    $hours = [Math]::Round($ticks / 20 / 60 / 60, 1);
    $days = [Math]::Round($hours / 24, 1);
    $timePlayedText = "$hours hrs / $days days";

    $deaths = if ($custom.'minecraft:deaths') { $custom.'minecraft:deaths' } else { 0 };$sinceDeathTicks = if ($custom.'minecraft:time_since_death') {$custom.'minecraft:time_since_death' } else { 0 };
    $sinceDeathHours = [Math]::Round($sinceDeathTicks / 20 / 60 / 60, 1);
    
    $damageDealt = if ($custom.'minecraft:damage_dealt') { [Math]::Round($custom.'minecraft:damage_dealt' / 10, 0) } else { 0 };$damageTaken = if ($custom.'minecraft:damage_taken') { [Math]::Round($custom.'minecraft:damage_taken' / 10, 0) } else { 0 };
    $mobKills = if ($custom.'minecraft:mob_kills') { $custom.'minecraft:mob_kills' } else { 0 };$dragonKills = if ($killed.'minecraft:ender_dragon') {$killed.'minecraft:ender_dragon' } else { 0 };
    $witherKills = if ($killed.'minecraft:wither') { $killed.'minecraft:wither' } else { 0 };$talked = if ($custom.'minecraft:talked_to_villager') {$custom.'minecraft:talked_to_villager' } else { 0 };
    $traded = if ($custom.'minecraft:traded_with_villager') { $custom.'minecraft:traded_with_villager' } else { 0 };$jumps = if ($custom.'minecraft:jump') {$custom.'minecraft:jump' } else { 0 };
    $animalsBred = if ($custom.'minecraft:animals_bred') { $custom.'minecraft:animals_bred' } else { 0 };$totalPlayerCrafted = 0;
    if ($crafted) { foreach ($p in$crafted.psobject.Properties) { $totalPlayerCrafted +=$p.Value } };
    
    $walk = if ($custom.'minecraft:walk_one_cm') { $custom.'minecraft:walk_one_cm' } else { 0 };$sprint = if ($custom.'minecraft:sprint_one_cm') {$custom.'minecraft:sprint_one_cm' } else { 0 };
    $distanceKm = [Math]::Round(($walk + $sprint) / 100 / 1000, 1);$blocksMined = 0;
    if ($mined) { foreach ($p in $mined.psobject.Properties) {$blocksMined += $p.Value } };$blocksPlaced = 0;
    if ($json.stats.'minecraft:used') { 
        foreach ($p in$json.stats.'minecraft:used'.psobject.Properties) { 
            if ($p.Name -notmatch 'minecart|boat|sword|axe|pickaxe|shovel|hoe|shear|flint|bucket|potion|apple|stew|bread|pie|beef|pork|chicken|mutton|salmon|cod|cookie|carrot|potato|kelp|melon|berries|soup') { 
                $blocksPlaced +=$p.Value 
            } 
        } 
    };
    
    $diamondOre = if ($mined.'minecraft:diamond_ore') {$mined.'minecraft:diamond_ore' } else { 0 };
    $deepslateDiamondOre = if ($mined.'minecraft:deepslate_diamond_ore') { $mined.'minecraft:deepslate_diamond_ore' } else { 0 };$totalPlayerDiamonds = $diamondOre +$deepslateDiamondOre;
    $ancientDebris = if ($mined.'minecraft:ancient_debris') {$mined.'minecraft:ancient_debris' } else { 0 };
    
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
        Talked = $talked
    };

    # Cumulative totals
    $totalHours +=$hours; $totalDeaths +=$deaths; $totalMobKills +=$mobKills; $totalMined +=$blocksMined; $totalPlaced +=$blocksPlaced; $totalTraded +=$traded; $totalDistance +=$distanceKm; $totalTalked +=$talked;
    $totalDamageDealt +=$damageDealt; $totalDamageTaken +=$damageTaken; $totalDiamonds +=$totalPlayerDiamonds; $totalDebris +=$ancientDebris; $totalJumps +=$jumps;
    $totalDragonKills += $dragonKills; $total
