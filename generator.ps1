# Safety check: If stats folder does not exist, create it
if (-not (Test-Path "stats")) { New-Item -ItemType Directory -Path "stats" }

# Ensure correct time formatting
$currentDateTime = (Get-Date).ToUniversalTime().AddHours(2).ToString("dd.MM.yyyy HH:mm:ss");

# Set number formatting to use spaces as thousands separators (English text, formatted numbers)
$usCulture = [System.Globalization.CultureInfo]::GetCultureInfo("cs-CZ")

$html = @("<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'><title>Minecraft Player Statistics</title><style>body { font-family: sans-serif; background: #1e1e1e; color: #fff; padding: 40px; } h1 { color: #5cff5c; margin-bottom: 5px; } .update-time { color: #aaa; font-size: 0.9em; margin-bottom: 25px; border-bottom: 2px solid #444; padding-bottom: 15px; } table { width: 100%; border-collapse: collapse; margin-top: 20px; table-layout: fixed; } th, td { border: 1px solid #444; padding: 12px; text-align: left; vertical-align: middle; } th { background: #2e2e2e; color: #5cff5c; } tr:nth-child(even) { background: #252525; } tr:hover { background: #333; } .stat-name { font-weight: bold; background: #2a2a2a; width: 240px; } .server-total { font-weight: bold; color: #5cff5c; background: #222; } .player-head { width: 24px; height: 24px; vertical-align: middle; margin-right: 10px; border-radius: 3px; image-rendering: pixelated; } .player-header { font-weight: bold; text-align: left; }</style></head><body><h1>Player Statistics — Forever Reeds</h1><div class='update-time'>Last updated: $currentDateTime</div><table>");

# Exact UUID mapping for your server
$jmena = @{
    '10d807ae-f713-4d9d-966d-a6e7b4bddafd' = 'dufe_com';
    '4b91ee4a-88d0-48f0-b111-8f8e6e3647b7' = 'KarlTheBroken';
    '90afe98a-4c6a-4469-959e-d55070e4b6b8' = 'Kathryn_Reed';
    '953decf3-5ac0-4108-965f-3b82cea52143' = 'Alex_Reed';
    'aa14ea23-012a-48b8-b39d-3e280496e83a' = 'Johny_Reed';
    'bd265486-b561-4510-860c-76a0bc9ea3ae' = 'ettelwen'
};

$hraciData = @()

# Global server totals
$totalHours = 0; $totalDeaths = 0; $totalMobKills = 0; $totalMined = 0; $totalPlaced = 0; $totalTraded = 0; $totalDistance = 0; $totalTalked = 0;
$totalDamageDealt = 0; $totalDamageTaken = 0; $totalDiamonds = 0; $totalDebris = 0; $totalJumps = 0;
$totalDragonKills = 0; $totalWitherKills = 0; $totalCrafted = 0; $totalBred = 0;

Get-ChildItem 'stats/*.json' | ForEach-Object {
    $uuid = $_.BaseName;
    # Clean dashes out of UUID for Crafatar API compatibility
    $cleanUUID = $uuid.Replace("-", "");
    
    $nickname = if ($jmena.Contains($uuid)) { $jmena[$uuid] } else { $uuid };
    $json = Get-Content $_.FullName -Raw | ConvertFrom-Json;
    $custom = $json.stats.'minecraft:custom';
    $mined = $json.stats.'minecraft:mined';
    $killed = $json.stats.'minecraft:killed';
    $crafted = $json.stats.'minecraft:crafted';
    
    # Core play time & deaths
    $ticks = 0; if ($custom.'minecraft:play_time') { $ticks = $custom.'minecraft:play_time' } elseif ($custom.'minecraft:play_one_minute') { $ticks = $custom.'minecraft:play_one_minute' };
    $hours = [Math]::Round($ticks / 20 / 60 / 60, 1);
    $deaths = if ($custom.'minecraft:deaths') { $custom.'minecraft:deaths' } else { 0 };
    $sinceDeathTicks = if ($custom.'minecraft:time_since_death') { $custom.'minecraft:time_since_death' } else { 0 };
    $sinceDeathHours = [Math]::Round($sinceDeathTicks / 20 / 60 / 60, 1);
    
    # Combat
    $damageDealt = if ($custom.'minecraft:damage_dealt') { [Math]::Round($custom.'minecraft:damage_dealt' / 10, 0) } else { 0 };
    $damageTaken = if ($custom.'minecraft:damage_taken') { [Math]::Round($custom.'minecraft:damage_taken' / 10, 0) } else { 0 };
    $mobKills = if ($custom.'minecraft:mob_kills') { $custom.'minecraft:mob_kills' } else { 0 };
    $dragonKills = if ($killed.'minecraft:ender_dragon') { $killed.'minecraft:ender_dragon' } else { 0 };
    $witherKills = if ($killed.'minecraft:wither') { $killed.'minecraft:wither' } else { 0 };
    
    # Interaction, crafting & movement
    $talked = if ($custom.'minecraft:talked_to_villager') { $custom.'minecraft:talked_to_villager' } else { 0 };
    $traded = if ($custom.'minecraft:traded_with_villager') { $custom.'minecraft:traded_with_villager' } else { 0 };
    $jumps = if ($custom.'minecraft:jump') { $custom.'minecraft:jump' } else { 0 };
    $animalsBred = if ($custom.'minecraft:animals_bred') { $custom.'minecraft:animals_bred' } else { 0 };
    
    $totalPlayerCrafted = 0; if ($crafted) { foreach ($p in $crafted.psobject.Properties) { $totalPlayerCrafted += $p.Value } };
    
    $walk = if ($custom.'minecraft:walk_one_cm') { $custom.'minecraft:walk_one_cm' } else { 0 };
    $sprint = if ($custom.'minecraft:sprint_one_cm') { $custom.'minecraft:sprint_one_cm' } else { 0 };
    $distanceKm = [Math]::Round(($walk + $sprint) / 100 / 1000, 1);
    
    # Mining & building
    $blocksMined = 0; if ($mined) { foreach ($p in $mined.psobject.Properties) { $blocksMined += $p.Value } };
    $blocksPlaced = 0; if ($json.stats.'minecraft:used') { foreach ($p in $json.stats.'minecraft:used'.psobject.Properties) { if ($p.Name -notmatch 'minecart|boat|sword|axe|pickaxe|shovel|hoe|shear|flint|bucket|potion|apple|stew|bread|pie|beef|pork|chicken|mutton|salmon|cod|cookie|carrot|potato|kelp|melon|berries|soup') { $blocksPlaced += $p.Value } } };
    
    # Specific ores
    $diamondOre = if ($mined.'minecraft:diamond_ore') { $mined.'minecraft:diamond_ore' } else { 0 };
    $deepslateDiamondOre = if ($mined.'minecraft:deepslate_diamond_ore') { $mined.'minecraft:deepslate_diamond_ore' } else { 0 };
    $totalPlayerDiamonds = $diamondOre + $deepslateDiamondOre;
    $ancientDebris = if ($mined.'minecraft:ancient_debris') { $mined.'minecraft:ancient_debris' } else { 0 };
    
    # Calculate server totals
    $totalHours += $hours; $totalDeaths += $deaths; $totalMobKills += $mobKills; $totalMined += $blocksMined; $totalPlaced += $blocksPlaced; $totalTraded += $traded; $totalDistance += $distanceKm; $totalTalked += $talked;
    $totalDamageDealt += $damageDealt; $totalDamageTaken += $damageTaken; $totalDiamonds += $totalPlayerDiamonds; $totalDebris += $ancientDebris; $totalJumps += $jumps;
    $totalDragonKills += $dragonKills; $totalWitherKills += $witherKills; $totalCrafted += $totalPlayerCrafted; $totalBred += $animalsBred;

    $hraciData += [PSCustomObject]@{
        CleanUUID       = $cleanUUID
        Nickname        = $nickname
        Hours           = $hours
        Deaths          = $deaths
        SinceDeathHours = $sinceDeathHours
        DamageDealt     = $damageDealt
        DamageTaken     = $damageTaken
        MobKills        = $mobKills
        DragonKills     = $dragonKills
        WitherKills     = $witherKills
        BlocksMined     = $blocksMined
        BlocksPlaced    = $blocksPlaced
        Diamonds        = $totalPlayerDiamonds
        Debris          = $ancientDebris
        Distance        = $distanceKm
        Jumps           = $jumps
        Crafted         = $totalPlayerCrafted
        Traded          = $traded
        Bred            = $animalsBred
        Talked          = $talked
    }
}

# Sort players by total playtime for column hierarchy
$serazeniHraci = $hraciData | Sort-Object Hours -Descending

# --- GENERATE HTML HEADERS WITH FIXED CRAFATAR URL PATH ---
$htmlRow = "<tr><th class='stat-name'>Statistic</th>"
$serazeniHraci | ForEach-Object {
    # FIXED: Added missing slash before avatars
    $headUrl = "https://crafatar.com" + $_.CleanUUID + "?size=24&overlay";
    # Backup URL if Crafatar fails (Minotar fallback)
    $fallbackUrl = "https://minotar.net" + $_.Nickname + "/24.png";
    $htmlRow += "<th class='player-header'><img class='player-head' src='$headUrl' onerror=""this.onerror=null; this.src='$fallbackUrl';"" alt=''>$($_.Nickname)</th>"
}
$htmlRow += "<th class='server-total'>SERVER TOTAL</th></tr>"
$html += $htmlRow

# Dynamic row building helper
function Add-StatRow ($label, $property, $formatSuffix = "", $serverValue = "", $lowerWins = $false) {
    $values = if ($lowerWins) {
        $serazeniHraci | Select-Object -ExpandProperty $property | Sort-Object
    } else {
        $serazeniHraci | Select-Object -ExpandProperty $property | Sort-Object -Descending
    }

    $top1 = $values[0]
    $top2 = $values[1]
    $top3 = $values[2]

    $row = "<tr><td class='stat-name'>$label</td>"
    foreach ($hrac in $serazeniHraci) {
        $val = $hrac.$property
        $formattedVal = if ($val -is [ValueType]) { $val.ToString("N0", $usCulture) } else { $val.ToString() }
        
        $medal = ""
        if ($val -ne 0 -or (-not $lowerWins -and $property -ne "Deaths")) {
            if ($val -eq $top1) { $medal = " 👑" }
            elseif ($val -eq $top2 -and $top2 -ne $top1) { $medal = " 🥈" }
            elseif ($val -eq $top3 -and $top3 -ne $top2 -and $top3 -ne $top1) { $medal = " 🥉" }
        }
        
        $row += "<td>$formattedVal $formatSuffix$medal</td>"
    }
    
    $formattedServerVal = if ($serverValue -is [ValueType]) { $serverValue.ToString("N0", $usCulture) } else { $serverValue }
    $finalServerVal = if ($serverValue -ne "") { $formattedServerVal } else { "—" }
    
    $row += "<td class='server-total'>$finalServerVal $formatSuffix</td></tr>"
    return $row
}

# Append statistics rows
$html += Add-StatRow "Time Played" "Hours" "hrs" $totalHours
$html += Add-StatRow "Deaths" "Deaths" "" $totalDeaths -lowerWins $true
$html += Add-StatRow "Time Since Last Death" "SinceDeathHours" "hrs" ""
$html += Add-StatRow "Damage Dealt (HP)" "DamageDealt" "" $totalDamageDealt
$html += Add-StatRow "Damage Taken (HP)" "DamageTaken" "" $totalDamageTaken
$html += Add-StatRow "Mob Kills" "MobKills" "" $totalMobKills
$html += Add-StatRow "Ender Dragon Kills" "DragonKills" "pcs" $totalDragonKills
$html += Add-StatRow "Wither Kills" "WitherKills" "pcs" $totalWitherKills
$html += Add-StatRow "Blocks Mined" "BlocksMined" "" $totalMined
$html += Add-StatRow "Blocks Placed" "BlocksPlaced" "" $totalPlaced
$html += Add-StatRow "Diamond Ore Mined" "Diamonds" "pcs" $totalDiamonds
$html += Add-StatRow "Ancient Debris Mined" "Debris" "pcs" $totalDebris
$html += Add-StatRow "Distance Traveled" "Distance" "km" $totalDistance
$html += Add-StatRow "Jump Count" "Jumps" "" $totalJumps
$html += Add-StatRow "Times Crafted" "Crafted" "pcs" $totalCrafted
$html += Add-StatRow "Trades with Villagers" "Traded" "" $totalTraded
$html += Add-StatRow "Animals Bred" "Bred" "pcs" $totalBred
$html += Add-StatRow "Chat Messages" "Talked" "" $totalTalked
$html += ""
$html | Out-File -FilePath 'index.html' -Encoding utf8
