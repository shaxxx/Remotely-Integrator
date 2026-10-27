# New-RemotelyStaging.ps1
# Izvrsava se na CLOUD-u (Windows PowerShell 5.1, kao SYSTEM preko Remotely agenta).
# Stvara staging: site Remotely-Test, pool-ove, mape i aplikaciju /token.
# Ne dira site Remotely, njegov pool ni njegove mape. Ne ispisuje connection string.
# Bez parametara (agent ih ne moze proslijediti); sve vrijednosti su staging vrijednosti.
$ErrorActionPreference = 'Stop'

$SiteName   = 'Remotely-Test'
$PoolSite   = 'Remotely-Test'
$PoolToken  = 'Remotely-Test-Token'
$HostName   = 'remote-test.integrator.hr'
$SitePath   = 'C:\sites\remotely-test'
$TokenPath  = 'C:\sites\remotely-test-token'
$ProdPath   = 'C:\sites\remotely'
$ProdToken  = 'C:\sites\remotely\token'

Import-Module WebAdministration

$created = New-Object System.Collections.Generic.List[string]

function Fail([string]$msg) {
    Write-Output "GRESKA: $msg"
    if ($created.Count -gt 0) {
        Write-Output "Vec stvoreno (potrebno rucno ocistiti ako treba):"
        foreach ($c in $created) { Write-Output "  - $c" }
    } else {
        Write-Output "Nista nije stvoreno."
    }
    exit 1
}

function Test-NonEmptyDir([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    return ($null -ne (Get-ChildItem -LiteralPath $p -Force | Select-Object -First 1))
}

function Copy-Dacl([string]$src, [string]$dst) {
    $sddl = (Get-Acl -LiteralPath $src).GetSecurityDescriptorSddlForm('Access')
    $acl = Get-Acl -LiteralPath $dst
    $acl.SetSecurityDescriptorSddlForm($sddl, 'Access')
    Set-Acl -LiteralPath $dst -AclObject $acl
}

function New-StagingPool([string]$name) {
    $null = New-WebAppPool -Name $name
    $created.Add("pool $name")
    Set-ItemProperty "IIS:\AppPools\$name" -Name managedRuntimeVersion -Value ''
    Set-ItemProperty "IIS:\AppPools\$name" -Name managedPipelineMode -Value 'Integrated'
    Set-ItemProperty "IIS:\AppPools\$name" -Name startMode -Value 'OnDemand'
    Set-ItemProperty "IIS:\AppPools\$name" -Name processModel.identityType -Value 'ApplicationPoolIdentity'
}

# ---- Preflight: nista se ne mijenja dok sve provjere ne prodju ----
if (Get-Website -Name $SiteName -ErrorAction SilentlyContinue) {
    Fail "site $SiteName vec postoji; odbijam nastaviti."
}
foreach ($p in $PoolSite, $PoolToken) {
    if (Test-Path "IIS:\AppPools\$p") { Fail "pool $p vec postoji; odbijam nastaviti." }
}
foreach ($d in $SitePath, $TokenPath) {
    if (Test-NonEmptyDir $d) { Fail "mapa $d vec postoji i nije prazna; odbijam nastaviti." }
}
foreach ($s in $ProdPath, $ProdToken) {
    if (-not (Test-Path -LiteralPath $s)) { Fail "izvor $s ne postoji." }
}
$srcSettings = Join-Path $ProdToken 'appsettings.json'
if (-not (Test-Path -LiteralPath $srcSettings)) { Fail "izvor $srcSettings ne postoji." }

try {
    # ---- Mape ----
    foreach ($d in $SitePath, $TokenPath) {
        if (-not (Test-Path -LiteralPath $d)) {
            $null = New-Item -ItemType Directory -Path $d
            $created.Add("mapa $d")
        }
    }

    # ---- Kopija token aplikacije ----
    Copy-Item -Path (Join-Path $ProdToken '*') -Destination $TokenPath -Recurse -Force
    $created.Add("sadrzaj kopiran u $TokenPath")

    # ---- appsettings.json: Database=Remotely; -> Database=Remotely_Test; ----
    $cfgPath = Join-Path $TokenPath 'appsettings.json'
    $bytes = [System.IO.File]::ReadAllBytes($cfgPath)
    $bomLen = 0
    $enc = $null
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $bomLen = 3; $enc = New-Object System.Text.UTF8Encoding($true)
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $bomLen = 2; $enc = New-Object System.Text.UnicodeEncoding($false, $true)
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $bomLen = 2; $enc = New-Object System.Text.UnicodeEncoding($true, $true)
    } else {
        $enc = New-Object System.Text.UTF8Encoding($false)
    }
    $text = $enc.GetString($bytes, $bomLen, $bytes.Length - $bomLen)
    $needle = 'Database=Remotely;'
    $count = ([regex]::Matches($text, [regex]::Escape($needle))).Count
    if ($count -ne 1) { throw "u appsettings.json ocekivano tocno 1 pojavljivanje zamjene, nadjeno $count." }
    $text = $text.Replace($needle, 'Database=Remotely_Test;')
    $body = $enc.GetBytes($text)
    $preamble = $enc.GetPreamble()
    $out = New-Object byte[] ($preamble.Length + $body.Length)
    [Array]::Copy($preamble, 0, $out, 0, $preamble.Length)
    [Array]::Copy($body, 0, $out, $preamble.Length, $body.Length)
    [System.IO.File]::WriteAllBytes($cfgPath, $out)
    Write-Output "appsettings.json u kopiji: baza zamijenjena (vrijednost se ne ispisuje)."

    # ---- ACL (samo DACL) ----
    Copy-Dacl $ProdPath $SitePath
    Copy-Dacl $ProdPath $TokenPath
    Write-Output "DACL kopiran s $ProdPath na obje mape."

    # ---- Poolovi ----
    New-StagingPool $PoolSite
    New-StagingPool $PoolToken

    # ---- Site, https binding, aplikacija ----
    $null = New-Website -Name $SiteName -PhysicalPath $SitePath -ApplicationPool $PoolSite -Port 80 -HostHeader $HostName -Force
    $created.Add("site $SiteName")
    $null = New-WebBinding -Name $SiteName -Protocol https -Port 443 -HostHeader $HostName -SslFlags 1
    $null = New-WebApplication -Site $SiteName -Name 'token' -PhysicalPath $TokenPath -ApplicationPool $PoolToken
    $created.Add("aplikacija /token na $SiteName")
}
catch {
    Fail ("korak nije uspio: " + $_.Exception.Message)
}

# ---- Ispis ----
Write-Output ""
Write-Output "Stvoreno:"
foreach ($c in $created) { Write-Output "  - $c" }
Write-Output ""
$site = Get-Website -Name $SiteName
Write-Output "SITE ID: $($site.Id)"
Get-WebBinding -Name $SiteName | Select-Object protocol, bindingInformation, sslFlags | Format-Table -AutoSize | Out-String -Width 200
Write-Output "Https binding jos nema certifikat; win-acme ga dodaje (docs/integrator/staging.md)."
