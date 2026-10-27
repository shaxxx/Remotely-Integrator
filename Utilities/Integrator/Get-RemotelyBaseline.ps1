# Get-RemotelyBaseline.ps1
# Izvrsava se na CLOUD-u (Windows PowerShell 5.1). Strogo samo cita; ne ispisuje tajne.
# Ispis je markdown koji se moze izravno spremiti.
param(
    [string]$SitePath = 'C:\sites\remotely',
    [string]$BaseUrl  = 'https://remote.integrator.hr',
    [string]$Database = 'Remotely'
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-ConnString {
    $cfg = Get-Content -LiteralPath (Join-Path $SitePath 'appsettings.json') -Raw | ConvertFrom-Json
    $csb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($cfg.ConnectionStrings.SQLServer)
    $csb['Initial Catalog'] = $Database
    return $csb.ConnectionString
}
function Invoke-Query([string]$sql) {
    $cn = New-Object System.Data.SqlClient.SqlConnection((Get-ConnString))
    try {
        $cn.Open()
        $cmd = $cn.CreateCommand()
        $cmd.CommandText = $sql
        $cmd.CommandTimeout = 120
        $dt = New-Object System.Data.DataTable
        $null = (New-Object System.Data.SqlClient.SqlDataAdapter($cmd)).Fill($dt)
        return ,$dt
    } finally { $cn.Dispose() }
}
function Get-Sha256Hex([byte[]]$bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}

"# Remotely produkcijska osnovica"
""
"- Izvrseno (UTC): $((Get-Date).ToUniversalTime().ToString('o'))"
"- SitePath: $SitePath"
"- BaseUrl: $BaseUrl"
"- Database: $Database"
""
"## Content datoteke"
""
$contentDir = Join-Path $SitePath 'wwwroot\Content'
foreach ($name in 'Remotely-Win10-x64.zip', 'Remotely-Win10-x86.zip', 'Remotely_Installer.exe') {
    $p = Join-Path $contentDir $name
    "### $name"
    ""
    if (-not (Test-Path -LiteralPath $p)) { "- NEMA DATOTEKE: $p"; ""; continue }
    $fi = Get-Item -LiteralPath $p
    $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()
    "- Length: $($fi.Length)"
    "- LastWriteTimeUtc.Ticks: $($fi.LastWriteTimeUtc.Ticks)"
    "- LastWriteTimeUtc (o): $($fi.LastWriteTimeUtc.ToString('o'))"
    "- SHA-256: $h"
    if ($name -like '*.zip') {
        $etag = ''
        try {
            $r = Invoke-WebRequest -Uri "$BaseUrl/Content/$name" -Method Head -UseBasicParsing
            $etag = [string]$r.Headers['ETag']
        } catch { $etag = 'GRESKA: ' + $_.Exception.Message }
        "- ETag: ``$etag``"
    }
    ""
}

"## __EFMigrationsHistory"
""
$mig = Invoke-Query 'SELECT MigrationId FROM dbo.__EFMigrationsHistory ORDER BY MigrationId'
"Broj migracija: $($mig.Rows.Count)"
""
foreach ($row in $mig.Rows) { "- $($row.MigrationId)" }
""

"## Snimka sheme"
""
"Format retka: ``tablica.stupac:tip:nullable`` (tip = DATA_TYPE, uz (CHARACTER_MAXIMUM_LENGTH) kad postoji; nullable = IS_NULLABLE)."
"Izvor: INFORMATION_SCHEMA.COLUMNS za BASE TABLE u shemi dbo; retci sortirani ordinalno; spojeni znakom LF (bez zavrsnog LF); SHA-256 nad UTF-8 bajtovima, mala hex slova."
""
$sch = Invoke-Query @"
SELECT c.TABLE_NAME, c.COLUMN_NAME, c.DATA_TYPE, c.CHARACTER_MAXIMUM_LENGTH, c.IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS c
JOIN INFORMATION_SCHEMA.TABLES t ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME
WHERE t.TABLE_TYPE = 'BASE TABLE' AND c.TABLE_SCHEMA = 'dbo'
"@
$lines = New-Object 'System.Collections.Generic.List[string]'
foreach ($row in $sch.Rows) {
    $type = [string]$row.DATA_TYPE
    if ($row.CHARACTER_MAXIMUM_LENGTH -isnot [System.DBNull]) { $type = "$type($($row.CHARACTER_MAXIMUM_LENGTH))" }
    $lines.Add("$($row.TABLE_NAME).$($row.COLUMN_NAME):$($type):$($row.IS_NULLABLE)")
}
$arr = $lines.ToArray()
[Array]::Sort($arr, [StringComparer]::Ordinal)
$joined = $arr -join "`n"
$utf8 = New-Object System.Text.UTF8Encoding($false)
"- Broj redaka: $($arr.Length)"
"- SHA-256: $(Get-Sha256Hex $utf8.GetBytes($joined))"
""

"## Flota (Devices po AgentVersion i IsOnline)"
""
$fleet = Invoke-Query 'SELECT AgentVersion, IsOnline, COUNT(*) AS Cnt FROM dbo.Devices GROUP BY AgentVersion, IsOnline ORDER BY AgentVersion, IsOnline'
$total = 0; $online = 0
"| AgentVersion | IsOnline | Broj |"
"|---|---|---|"
foreach ($row in $fleet.Rows) {
    $v = if ($row.AgentVersion -is [System.DBNull]) { '(null)' } else { [string]$row.AgentVersion }
    "| $v | $($row.IsOnline) | $($row.Cnt) |"
    $total += [int]$row.Cnt
    if ([bool]$row.IsOnline) { $online += [int]$row.Cnt }
}
""
"- Ukupno uredjaja: $total"
"- Ukupno online: $online"
