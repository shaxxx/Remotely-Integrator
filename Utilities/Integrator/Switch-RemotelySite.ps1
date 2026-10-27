# Switch-RemotelySite.ps1
# Izvrsava se na CLOUD-u (Windows PowerShell 5.1, kao SYSTEM preko Remotely agenta).
# Prebacuje fizicku putanju zadanog sitea: zaustavi pool, postavi physicalPath, pokrene pool.
# Rollback = isti poziv sa starom putanjom. Dira samo zadani site (ne i njegove aplikacije).
param(
    [Parameter(Mandatory = $true)][string]$SiteName,
    [Parameter(Mandatory = $true)][string]$PhysicalPath
)
$ErrorActionPreference = 'Stop'

function Fail([string]$msg) {
    Write-Output "GRESKA: $msg"
    exit 1
}

function Normalize-Path([string]$p) {
    return [System.IO.Path]::GetFullPath([System.Environment]::ExpandEnvironmentVariables($p)).TrimEnd('\')
}

function Wait-PoolState([string]$pool, [string]$state, [int]$timeoutSec) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ((Get-WebAppPoolState -Name $pool).Value -eq $state) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return ((Get-WebAppPoolState -Name $pool).Value -eq $state)
}

Import-Module WebAdministration

# ---- Preflight ----
$site = @(Get-Website -Name $SiteName -ErrorAction SilentlyContinue)
if ($site.Count -ne 1) { Fail "site $SiteName ne postoji (ili nije jedinstven)." }
$site = $site[0]

if (-not (Test-Path -LiteralPath $PhysicalPath -PathType Container)) { Fail "mapa $PhysicalPath ne postoji." }
$newPath = Normalize-Path $PhysicalPath
foreach ($f in 'web.config', 'Remotely_Server.exe') {
    if (-not (Test-Path -LiteralPath (Join-Path $newPath $f) -PathType Leaf)) { Fail "u $newPath nema $f." }
}

$pool = [string]$site.applicationPool
if (-not (Test-Path "IIS:\AppPools\$pool")) { Fail "pool $pool ne postoji." }

# Pool smije koristiti samo korijenska aplikacija ovog sitea.
$shared = New-Object System.Collections.Generic.List[string]
foreach ($s in @(Get-Website)) {
    if ($s.Name -ne $SiteName -and [string]$s.applicationPool -ieq $pool) { $shared.Add("site $($s.Name)") }
}
foreach ($a in @(Get-WebApplication)) {
    if ([string]$a.applicationPool -ieq $pool) { $shared.Add("aplikacija $($a.path) ($($a.PSPath))") }
}
if ($shared.Count -gt 0) {
    foreach ($x in $shared) { Write-Output "  pool $pool koristi i: $x" }
    Fail "pool $pool koristi jos netko osim korijena sitea $SiteName; zaustavljanje bi ga zahvatilo. Nista nije promijenjeno."
}

$oldPath = [string]$site.physicalPath
Write-Output "Site: $SiteName  pool: $pool"
Write-Output "Stara putanja: $oldPath"
if ((Normalize-Path $oldPath) -ieq $newPath) {
    Write-Output "Putanja je vec $newPath; nista se ne mijenja."
    exit 0
}

# ---- Prebacivanje ----
$began = $false
$failed = $null
try {
    $began = $true
    if ((Get-WebAppPoolState -Name $pool).Value -ne 'Stopped') {
        Stop-WebAppPool -Name $pool
    }
    if (-not (Wait-PoolState $pool 'Stopped' 60)) { throw "pool $pool se nije zaustavio u 60 s." }

    Set-ItemProperty "IIS:\Sites\$SiteName" -Name physicalPath -Value $newPath
    $check = [string](Get-Website -Name $SiteName).physicalPath
    if ((Normalize-Path $check) -ine $newPath) { throw "physicalPath nakon postavljanja nije $newPath." }

    Start-WebAppPool -Name $pool
    if (-not (Wait-PoolState $pool 'Started' 60)) { throw "pool $pool se nije pokrenuo u 60 s." }
}
catch {
    $failed = $_.Exception.Message
}
finally {
    if ($began) {
        try {
            if ((Get-WebAppPoolState -Name $pool).Value -ne 'Started') {
                Start-WebAppPool -Name $pool
                $null = Wait-PoolState $pool 'Started' 60
            }
        } catch {
            Write-Output "UPOZORENJE: pool $pool nije moguce pokrenuti: $($_.Exception.Message)"
        }
    }
}

$state = (Get-WebAppPoolState -Name $pool).Value
Write-Output "Stara putanja: $oldPath"
Write-Output "Nova putanja:  $([string](Get-Website -Name $SiteName).physicalPath)"
Write-Output "Pool $pool : $state"
if ($failed) { Fail "prebacivanje nije uspjelo: $failed" }
if ($state -ne 'Started') { Fail "pool $pool nije Started." }
Write-Output "OK."
