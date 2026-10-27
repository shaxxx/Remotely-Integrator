# Switch-RemotelySite.ps1
# Izvrsava se na CLOUD-u (Windows PowerShell 5.1, kao SYSTEM preko Remotely agenta).
# Prebacuje fizicku putanju zadanog sitea: zaustavi pool, postavi physicalPath, pokrene pool.
# Rollback = isti poziv sa starom putanjom. Dira samo zadani site (ne i njegove aplikacije).
# -PreflightOnly: samo provjere i ispis (bez Stop/Set/Start); PhysicalPath smije biti i trenutna putanja.
param(
    [string]$SiteName,
    [string]$PhysicalPath,
    [switch]$PreflightOnly
)
$ErrorActionPreference = 'Stop'

$script:PollMs = 500

function Fail([string]$msg) {
    Write-Output "GRESKA: $msg"
    exit 1
}

function Normalize-Path([string]$p) {
    return [System.IO.Path]::GetFullPath([System.Environment]::ExpandEnvironmentVariables($p)).TrimEnd('\')
}

function Get-ShutdownLimitSec([string]$pool) {
    try {
        $v = (Get-ItemProperty "IIS:\AppPools\$pool" -Name processModel.shutdownTimeLimit).TotalSeconds
        if ($v -gt 0) { return [int][Math]::Ceiling($v) }
    } catch { }
    return 90
}

function Wait-PoolState([string]$pool, [string]$state, [int]$timeoutSec) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ((Get-WebAppPoolState -Name $pool).Value -eq $state) { return $true }
        Start-Sleep -Milliseconds $script:PollMs
    }
    return ((Get-WebAppPoolState -Name $pool).Value -eq $state)
}

# Ceka da pool izadje iz Starting/Stopping (stabilno stanje Started ili Stopped). Vraca stanje.
function Wait-PoolStable([string]$pool, [int]$timeoutSec) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ($true) {
        $s = [string](Get-WebAppPoolState -Name $pool).Value
        if ($s -eq 'Started' -or $s -eq 'Stopped') { return $s }
        if ((Get-Date) -ge $deadline) { return $s }
        Start-Sleep -Milliseconds $script:PollMs
    }
}

# Petlja do roka: Stopped -> Start (ponavlja ako baci), Stopping/Starting -> ceka, Started -> gotovo.
function Ensure-PoolStarted([string]$pool, [int]$timeoutSec) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ($true) {
        $s = [string](Get-WebAppPoolState -Name $pool).Value
        if ($s -eq 'Started') { return $true }
        if ((Get-Date) -ge $deadline) { return $false }
        if ($s -eq 'Stopped') {
            try { Start-WebAppPool -Name $pool }
            catch { Write-Host "UPOZORENJE: Start-WebAppPool nije uspio, ponavljam: $($_.Exception.Message)" }
        }
        Start-Sleep -Milliseconds $script:PollMs
    }
}

function Write-ManualRecovery([string]$pool) {
    Write-Output "RUCNI OPORAVAK: pool $pool NIJE Started. Na CLOUD-u pokrenuti: Import-Module WebAdministration; Start-WebAppPool -Name '$pool'"
    Write-Output "  (ili: C:\Windows\System32\inetsrv\appcmd.exe start apppool /apppool.name:`"$pool`")"
}

function Invoke-Switch {
    if (-not $SiteName) { Fail "SiteName je obavezan." }
    if (-not $PhysicalPath) { Fail "PhysicalPath je obavezan." }
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

    $shared = New-Object System.Collections.Generic.List[string]
    foreach ($s in @(Get-Website)) {
        if ($s.Name -ne $SiteName -and [string]$s.applicationPool -ieq $pool) { $shared.Add("site $($s.Name)") }
    }
    foreach ($a in @(Get-WebApplication)) {
        if ([string]$a.applicationPool -ieq $pool) { $shared.Add("aplikacija $($a.path) ($($a.PSPath))") }
    }

    $oldPath = [string]$site.physicalPath
    $limit = Get-ShutdownLimitSec $pool
    $startState = [string](Get-WebAppPoolState -Name $pool).Value
    Write-Output "Site: $SiteName  pool: $pool  stanje poola: $startState"
    Write-Output "processModel.shutdownTimeLimit: $limit s"
    Write-Output "Trenutna putanja: $oldPath"
    Write-Output "Ciljna putanja:   $newPath"
    if ($shared.Count -gt 0) {
        foreach ($x in $shared) { Write-Output "  pool $pool koristi i: $x" }
    } else {
        Write-Output "Pool $pool ne koristi nijedan drugi site ni aplikacija."
    }
    if ($shared.Count -gt 0) {
        Fail "pool $pool koristi jos netko osim korijena sitea $SiteName; zaustavljanje bi ga zahvatilo. Nista nije promijenjeno."
    }
    if ($PreflightOnly) {
        Write-Output "PreflightOnly: sve provjere prosle; nista nije promijenjeno."
        exit 0
    }

    $recoverSec = $limit + 60

    # ---- Ista putanja: nista ne mijenjaj, ali pazi da pool radi ----
    if ((Normalize-Path $oldPath) -ieq $newPath) {
        Write-Output "Putanja je vec $newPath; putanja se ne mijenja."
        if (-not (Ensure-PoolStarted $pool $recoverSec)) {
            Write-ManualRecovery $pool
            Fail "pool $pool nije Started."
        }
        Write-Output "Pool $pool : Started. OK."
        exit 0
    }

    # ---- Prebacivanje ----
    $failed = $null
    $began = $false
    try {
        $began = $true
        $st = Wait-PoolStable $pool ($limit + 15)
        if ($st -ne 'Started' -and $st -ne 'Stopped') { throw "pool $pool je ostao u stanju $st; nista nije promijenjeno." }
        if ($st -eq 'Started') { Stop-WebAppPool -Name $pool }
        if (-not (Wait-PoolState $pool 'Stopped' ($limit + 15))) { throw "pool $pool se nije zaustavio u $($limit + 15) s." }

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
            $ok = $false
            try { $ok = Ensure-PoolStarted $pool $recoverSec } catch { Write-Host "UPOZORENJE: $($_.Exception.Message)" }
            if (-not $ok) { $script:recoveryFailed = $true }
        }
    }

    $state = (Get-WebAppPoolState -Name $pool).Value
    Write-Output "Stara putanja: $oldPath"
    Write-Output "Nova putanja:  $([string](Get-Website -Name $SiteName).physicalPath)"
    Write-Output "Pool $pool : $state"
    if ($script:recoveryFailed) { Write-ManualRecovery $pool }
    if ($failed) { Fail "prebacivanje nije uspjelo: $failed" }
    if ($state -ne 'Started') { Write-ManualRecovery $pool; Fail "pool $pool nije Started." }
    Write-Output "OK."
}

# Dot-sourcing (testovi) samo ucita funkcije.
if ($MyInvocation.InvocationName -ne '.') { Invoke-Switch }
