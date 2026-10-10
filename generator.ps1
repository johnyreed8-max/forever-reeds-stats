# Pojistka: Pokud složka stats neexistuje, skript ji sám vytvoří
if (-not (Test-Path "stats")) { New-Item -ItemType Directory -Path "stats" }

# Zajištění správného českého času (UTC + 2 hodiny posun pro střední Evropu)
$aktualniCas = (Get-Date).ToUniversalTime().AddHours(2).ToString("dd.MM.yyyy HH:mm:ss");

# Nastavení formátování pro oddělování tisíců mezerou podle české kultury
$czCulture = [System.Globalization.CultureInfo]::GetCultureInfo("cs-CZ")

$html = @("<!DOCTYPE html><html lang='cs'><head><meta charset='UTF-8'><title>Minecraft Statistiky</title><style>body { font-family: sans-serif; background: #1e1e1e; color: #fff; padding: 40px; } h1 { color: #5cff5c; margin-bottom: 5px; } .update-time { color: #aaa; font-size: 0.9em; margin-bottom: 25px; border-bottom: 2px solid #444; padding-bottom: 15px; } table { width: 100%; border-collapse: collapse; margin-top: 20px; table-layout: fixed; } th, td { border: 1px solid #444; padding: 12px; text-align: left; vertical-align: middle; } th { background: #2e2e2e; color: #5cff5c; } tr:nth-child(even) { background: #252525; } tr:hover { background: #333; } .stat-name { font-weight: bold; background: #2a2a2a; width: 240px; } .server-total { font-weight: bold; color: #5cff5c; background: #222; } .player-head { width: 24px; height: 24px; vertical-align: middle; margin-right: 10px; border-radius: 3px; image-rendering: pixelated; } .player-header { font-weight: bold; text-align: left; }</style></head><body><h1>Statistiky hráčů — Forever Reeds</h1><div class='update-time'>Poslední aktualizace: $aktualniCas</div><table>");

# Přesné spárování UUID podle vašeho serveru
$jmena = @{
    '10d807ae-f713-4d9d-966d-a6e7b4bddafd' = 'dufe_com';
    '4b91ee4a-88d0-48f0-b111-8f8e6e3647b7' = 'KarlTheBroken';
    '90afe98a-4c6a-4469-959e-d55070e4b6b8' = 'Kathryn_Reed';
    '953decf3-5ac0-4108-965f-3b82cea52143' = 'Alex_Reed';
    'aa14ea23-012a-48b8-b39d-3e280496e83a' = 'Johny_Reed';
    'bd265486-b561-4510-860c-76a0bc9ea3ae' = 'ettelwen'
};

$hraciData = @()

# Globální součty serveru
$totalHours = 0; $totalDeaths = 0; $totalMobKills = 0; $totalMined = 0; $totalPlaced = 0; $totalTraded = 0; $totalDistance = 0; $totalTalked = 0;
$totalDamageDealt = 0; $totalDamageTaken = 0; $totalDiamonds = 0; $totalDebris = 0; $totalJumps = 0;
$totalDragonKills = 0; $totalCrafted = 0; $totalBred = 0;

Get-ChildItem 'stats/*.json' | ForEach-Object {
    $uuid = $_.BaseName;
    $nickname = if ($jmena.Contains($uuid)) { $jmena[$uuid] } else { $uuid };
    $json = Get-Content $_.FullName -Raw | ConvertFrom-Json;
    $custom = $json.stats.'minecraft:custom';
    $mined = $json.stats.'minecraft:mined';
    $killed = $json.stats.'minecraft:killed';
    $crafted = $json.stats.'minecraft:crafted';
    
    # Základní časy a úmrtí
    $ticks = 0; if ($custom.'minecraft:play_time') { $ticks = $custom.'minecraft:play_time' } elseif ($custom.'minecraft:play_one_minute') { $ticks = $custom.'minecraft:play_one_minute' };
    $hours = [Math]::Round($ticks / 20 / 60 / 60, 1);
    $deaths = if ($custom.'minecraft:deaths') { $custom.'minecraft:deaths' } else { 0 };
    $sinceDeathTicks = if ($custom.'minecraft:time_since_death') { $custom.'minecraft:time_since_death' } else { 0 };
    $sinceDeathHours = [Math]::Round($sinceDeathTicks / 20 / 60 / 60, 1);
    
    # Damage a boj
    $damageDealt = if ($custom.'minecraft:damage_dealt') { [Math]::Round($custom.'minecraft:damage_dealt' / 10, 0) } else { 0 };
    $damageTaken = if ($custom.'minecraft:damage_taken') { [Math]::Round($custom.'minecraft:damage_taken' / 10, 0) } else { 0 };
    $mobKills = if ($custom.'minecraft:mob_kills') { $custom.'minecraft:mob_kills' } else { 0 };
    $dragonKills = if ($killed.'minecraft:ender_dragon') { $killed.'minecraft:ender_dragon' } else { 0 };
    
    # Blokování, pohyb, crafting, zvířata a chat
    $talked = if ($custom.'minecraft:talked_to_villager') { $custom.'minecraft:talked_to_villager' } else { 0 };
    $traded = if ($custom.'minecraft:traded_with_villager') { $custom.'minecraft:traded_with_villager' } else { 0 };
    $jumps = if ($custom.'minecraft:jump') { $custom.'minecraft:jump' } else { 0 };
    $animalsBred = if ($custom.'minecraft:animals_bred') { $custom.'minecraft:animals_bred' } else { 0 };
    
    $totalPlayerCrafted = 0; if ($crafted) { foreach ($p in $crafted.psobject.Properties) { $totalPlayerCrafted += $p.Value } };
    
    $walk = if ($custom.'minecraft:walk_one_cm') { $custom.'minecraft:walk_one_cm' } else { 0 };
    $sprint = if ($custom.'minecraft:sprint_one_cm') { $custom.'minecraft:sprint_one_cm' } else { 0 };
    $distanceKm = [Math]::Round(($walk + $sprint) / 100 / 1000, 1);
    
    # Těžba a stavění
    $blocksMined = 0; if ($mined) { foreach ($p in $mined.psobject.Properties) { $blocksMined += $p.Value } };
    $blocksPlaced = 0; if ($json.stats.'minecraft:used') { foreach ($p in $json.stats.'minecraft:used'.psobject.Properties) { if ($p.Name -notmatch 'minecart|boat|sword|axe|pickaxe|shovel|hoe|shear|flint|bucket|potion|apple|stew|bread|pie|beef|pork|chicken|mutton|salmon|cod|cookie|carrot|potato|kelp|melon|berries|soup') { $blocksPlaced += $p.Value } } };
    
    # Specifické rudy
    $diamondOre = if ($mined.'minecraft:diamond_ore') { $mined.'minecraft:diamond_ore' } else { 0 };
    $deepslateDiamondOre = if ($mined.'minecraft:deepslate_diamond_ore') { $mined.'minecraft:deepslate_diamond_ore' } else { 0 };
    $totalPlayerDiamonds = $diamondOre + $deepslateDiamondOre;
    $ancientDebris = if ($mined.'minecraft:ancient_debris') { $mined.'minecraft:ancient_debris' } else { 0 };
    
    # Sčítání globálních hodnot serveru
    $totalHours += $hours; $totalDeaths += $deaths; $totalMobKills += $mobKills; $totalMined += $blocksMined; $totalPlaced += $blocksPlaced; $totalTraded += $traded; $totalDistance += $distanceKm; $totalTalked += $talked;
    $totalDamageDealt += $damageDealt; $totalDamageTaken += $damageTaken; $totalDiamonds += $totalPlayerDiamonds; $totalDebris += $ancientDebris; $totalJumps += $jumps;
    $totalDragonKills += $dragonKills; $totalCrafted += $totalPlayerCrafted; $totalBred += $animalsBred;

    $hraciData += [PSCustomObject]@{
        UUID            = $uuid
        Nickname        = $nickname
        Hours           = $hours
        Deaths          = $deaths
        SinceDeathHours = $sinceDeathHours
        DamageDealt     = $damageDealt
        DamageTaken     = $damageTaken
        MobKills        = $mobKills
        DragonKills     = $dragonKills
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

# Seřazení hráčů podle herního času pro pořadí sloupců
$serazeniHraci = $hraciData | Sort-Object Hours -Descending

# --- GENEROVÁNÍ HTML ŽÁHLAVÍ S NOVÝM STABILNÍM API PRO HLAVY ---
$htmlRow = "<tr><th class='stat-name'>Statistika</th>"
$serazeniHraci | ForEach-Object {
    # Crafatar API je 100% stabilní a vyžaduje UUID hráče
    $headUrl = "https://crafatar.com" + $_.UUID + "?size=24&overlay";
    $htmlRow += "<th class='player-header'><img class='player-head' src='$headUrl' alt=''>$($_.Nickname)</th>"
}
$htmlRow += "<th class='server-total'>CELKEM SERVER</th></tr>"
$html += $htmlRow

# Pomocná funkce s vyhodnocením 1., 2. a 3. místa (Zlato, Stříbro, Bronz)
function Add-StatRow ($label, $property, $formatSuffix = "", $serverValue = "", $lowerWins = $false) {
    # Seřazení hodnot pro určení medailí
    $values = if ($lowerWins) {
        $serazeniHraci | Select-Object -ExpandProperty $property | Sort-Object -Ascending
    } else {
        $serazeniHraci | Select-Object -ExpandProperty $property | Sort-Object -Descending
    }

    $top1 = $values[0]
    $top2 = $values[1]
    $top3 = $values[2]

    $row = "<tr><td class='stat-name'>$label</td>"
    foreach ($hrac in $serazeniHraci) {
        $val = $hrac.$property
        $formattedVal = if ($val -is [ValueType]) { $val.ToString("N0", $czCulture) } else { $val.ToString() }
        
        # Logika přidělování medailí
        $medal = ""
        # Výjimka: Pokud je hodnota 0, medaile se nedávají (např. 0 zabitých draků nebo 0 úmrtí u trestné statistiky)
        if ($val -ne 0 -or (-not $lowerWins -and $property -ne "Deaths")) {
            if ($val -eq $top1) { $medal = " 👑" }
            elseif ($val -eq $top2 -and $top2 -ne $top1) { $medal = " 🥈" }
            elseif ($val -eq $top3 -and $top3 -ne $top2 -and $top3 -ne $top1) { $medal = " 🥉" }
        }
        
        $row += "<td>$formattedVal $formatSuffix$medal</td>"
    }
    
    $formattedServerVal = if ($serverValue -is [ValueType]) { $serverValue.ToString("N0", $czCulture) } else { $serverValue }
    $finalServerVal = if ($serverValue -ne "") { $formattedServerVal } else { "—" }
    
    $row += "<td class='server-total'>$finalServerVal $formatSuffix</td></tr>"
    return $row
}

# Přidávání jednotlivých řádků statistik přesně podle vašeho seznamu
$html += Add-StatRow "Odehraný čas" "Hours" "hod." $totalHours
$html += Add-StatRow "Úmrtí" "Deaths" "" $totalDeaths -lowerWins $true # Méně je lépe
$html += Add-StatRow "Čas od poslední smrti" "SinceDeathHours" "hod." ""
$html += Add-StatRow "Rozdané zranění (HP)" "DamageDealt" "" $totalDamageDealt
$html += Add-StatRow "Obdržené zranění (HP)" "DamageTaken" "" $totalDamageTaken
$html += Add-StatRow "Zabitá monstra" "MobKills" "" $totalMobKills
$html += Add-StatRow "Zabití ender draka" "DragonKills" "ks" $totalDragonKills
$html += Add-StatRow "Vytěženo bloků" "BlocksMined" "" $totalMined
$html += Add-StatRow "Položeno bloků" "BlocksPlaced" "" $totalPlaced
$html += Add-StatRow "Vytěženo diamantové rudy" "Diamonds" "ks" $totalDiamonds
