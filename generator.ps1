$aktualniCas = Get-Date -Format "dd.MM.yyyy HH:mm:ss";

$html = @("<!DOCTYPE html><html lang='cs'><head><meta charset='UTF-8'><title>Minecraft Statistiky</title><style>body { font-family: sans-serif; background: #1e1e1e; color: #fff; padding: 40px; } h1 { color: #5cff5c; margin-bottom: 5px; } .update-time { color: #aaa; font-size: 0.9em; margin-bottom: 25px; border-bottom: 2px solid #444; padding-bottom: 15px; } table { width: 100%; border-collapse: collapse; margin-top: 20px; } th, td { border: 1px solid #444; padding: 12px; text-align: left; vertical-align: middle; } th { background: #2e2e2e; color: #5cff5c; } tr:nth-child(even) { background: #252525; } tr:hover { background: #333; } .player-cell { display: flex; align-items: center; gap: 10px; } .player-head { width: 32px; height: 32px; image-rendering: pixelated; }</style></head><body><h1>Statistiky hráčů — Forever Reeds</h1><div class='update-time'>Poslední aktualizace: $aktualniCas</div><table><tr><th>Hráč (Nick)</th><th>Odehraný čas</th><th>Úmrtí</th><th>Čas od posl. smrti</th><th>Zabitá monstra</th><th>Vytěženo bloků</th><th>Položeno bloků</th><th>Obchody s villagery</th><th>Nachozeno km</th><th>Zprávy v chatu</th></tr>");

# Přesné a správné spárování UUID podle vašeho serveru
$jmena = @{
    '10d807ae-f713-4d9d-966d-a6e7b4bddafd' = 'dufe_com';
    '4b91ee4a-88d0-48f0-b111-8f8e6e3647b7' = 'KarlTheBroken';
    '90afe98a-4c6a-4469-959e-d55070e4b6b8' = 'Kathryn_Reed';
    '953decf3-5ac0-4108-965f-3b82cea52143' = 'Alex_Reed';
    'aa14ea23-012a-48b8-b39d-3e280496e83a' = 'Johny_Reed';
    'bd265486-b561-4510-860c-76a0bc9ea3ae' = 'ettelwen'
};

$hraciData = @()

Get-ChildItem 'stats/*.json' | ForEach-Object {
    $uuid = $_.BaseName;
    $nickname = if ($jmena.Contains($uuid)) { $jmena[$uuid] } else { $uuid };
    $json = Get-Content $_.FullName -Raw | ConvertFrom-Json;
    $custom = $json.stats.'minecraft:custom';
    $mined = $json.stats.'minecraft:mined';
    
    $ticks = 0; if ($custom.'minecraft:play_time') { $ticks = $custom.'minecraft:play_time' } elseif ($custom.'minecraft:play_one_minute') { $ticks = $custom.'minecraft:play_one_minute' };
    $hours = [Math]::Round($ticks / 20 / 60 / 60, 1);
    $deaths = if ($custom.'minecraft:deaths') { $custom.'minecraft:deaths' } else { 0 };
    $sinceDeathTicks = if ($custom.'minecraft:time_since_death') { $custom.'minecraft:time_since_death' } else { 0 };
    $sinceDeath = if ($sinceDeathTicks -gt 72000) { ([Math]::Round($sinceDeathTicks / 20 / 60 / 60, 1)).ToString() + ' hod.' } else { ([Math]::Round($sinceDeathTicks / 20 / 60, 0)).ToString() + ' min.' };
    $mobKills = if ($custom.'minecraft:mob_kills') { $custom.'minecraft:mob_kills' } else { 0 };
    $talked = if ($custom.'minecraft:talked_to_villager') { $custom.'minecraft:talked_to_villager' } else { 0 };
    $traded = if ($custom.'minecraft:traded_with_villager') { $custom.'minecraft:traded_with_villager' } else { 0 };
    $walk = if ($custom.'minecraft:walk_one_cm') { $custom.'minecraft:walk_one_cm' } else { 0 };
    $sprint = if ($custom.'minecraft:sprint_one_cm') { $custom.'minecraft:sprint_one_cm' } else { 0 };
    $distanceKm = [Math]::Round(($walk + $sprint) / 100 / 1000, 1);
    
    $blocksMined = 0; if ($mined) { foreach ($p in $mined.psobject.Properties) { $blocksMined += $p.Value } };
    $blocksPlaced = 0; if ($json.stats.'minecraft:used') { foreach ($p in $json.stats.'minecraft:used'.psobject.Properties) { if ($p.Name -notmatch 'minecart|boat|sword|axe|pickaxe|shovel|hoe|shear|flint|bucket|potion|apple|stew|bread|pie|beef|pork|chicken|mutton|salmon|cod|cookie|carrot|potato|kelp|melon|berries|soup') { $blocksPlaced += $p.Value } } };
    
    $hrac = [PSCustomObject]@{
        Nickname = $nickname
        Hours = $hours
        Deaths = $deaths
        SinceDeath = $sinceDeath
        MobKills = $mobKills
        BlocksMined = $blocksMined
        BlocksPlaced = $blocksPlaced
        Traded = $traded
        Distance = $distanceKm
        Talked = $talked
    }
    $hraciData += $hrac
}

# Seřazení a vygenerování řádků s 3D avatary hlav
$hraciData | Sort-Object Hours -Descending | ForEach-Object {
    $avatarUrl = "https://mc-heads.net" + $_.Nickname + "/32";
    $html += '<tr><td><div class="player-cell"><img class="player-head" src="' + $avatarUrl + '" alt="skin"><strong>' + $_.Nickname + '</strong></div></td><td>' + $_.Hours + ' hod.</td><td>' + $_.Deaths + '</td><td>' + $_.SinceDeath + '</td><td>' + $_.MobKills + '</td><td>' + $_.BlocksMined + '</td><td>' + $_.BlocksPlaced + '</td><td>' + $_.Traded + '</td><td>' + $_.Distance + ' km</td><td>' + $_.Talked + '</td></tr>';
}

$html += '</table></body></html>';
$html | Out-File -FilePath 'index.html' -Encoding utf8
