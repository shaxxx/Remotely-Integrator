# Get-RemotelyFleetStatus.ps1
# Izvrsava se na CLOUD-u (Windows PowerShell 5.1). Strogo samo cita; ne ispisuje tajne.
param(
    [string]$SitePath = 'C:\sites\remotely',
    [string]$Database = 'Remotely'
)
$ErrorActionPreference = 'Stop'

$cfg = Get-Content -LiteralPath (Join-Path $SitePath 'appsettings.json') -Raw | ConvertFrom-Json
$csb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($cfg.ConnectionStrings.SQLServer)
$csb['Initial Catalog'] = $Database
$cn = New-Object System.Data.SqlClient.SqlConnection($csb.ConnectionString)
try {
    $cn.Open()
    $cmd = $cn.CreateCommand()
    $cmd.CommandText = 'SELECT AgentVersion, IsOnline, COUNT(*) AS Cnt FROM dbo.Devices GROUP BY AgentVersion, IsOnline ORDER BY AgentVersion, IsOnline'
    $dt = New-Object System.Data.DataTable
    $null = (New-Object System.Data.SqlClient.SqlDataAdapter($cmd)).Fill($dt)
} finally { $cn.Dispose() }

"Database: $Database"
"| AgentVersion | IsOnline | Broj |"
"|---|---|---|"
$total = 0; $online = 0
foreach ($row in $dt.Rows) {
    $v = if ($row.AgentVersion -is [System.DBNull]) { '(null)' } else { [string]$row.AgentVersion }
    "| $v | $($row.IsOnline) | $($row.Cnt) |"
    $total += [int]$row.Cnt
    if ([bool]$row.IsOnline) { $online += [int]$row.Cnt }
}
""
"Ukupno uredjaja: $total"
"Ukupno online: $online"
