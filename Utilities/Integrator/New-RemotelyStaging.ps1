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

# Dekodira bajtove (BOM-aware). Vraca objekt: Enc, BomLen, Text.
function Read-DecodedFile([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $bomLen = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $bomLen = 3; $enc = New-Object System.Text.UTF8Encoding($true)
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $bomLen = 2; $enc = New-Object System.Text.UnicodeEncoding($false, $true)
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $bomLen = 2; $enc = New-Object System.Text.UnicodeEncoding($true, $true)
    } else {
        $enc = New-Object System.Text.UTF8Encoding($false)
    }
    return New-Object psobject -Property @{ Enc = $enc; BomLen = $bomLen; Text = $enc.GetString($bytes, $bomLen, $bytes.Length - $bomLen) }
}

# Samo cita. Vraca listu problema (samo nazivi datoteka i brojevi, nikad sadrzaj).
# Mode 'source': appsettings.json mora imati 'Database=Remotely;' tocno jednom.
# Mode 'target': appsettings.json mora imati 'Database=Remotely_Test;' tocno jednom.
# U svim ostalim *.json/*.config nema referenci na produkcijsku bazu ni ConnectionStrings__/environmentVariable.
function Get-TokenFindings([string]$dir, [string]$mode) {
    $problems = New-Object System.Collections.Generic.List[string]
    $opt = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    if ($mode -eq 'source') { $prodDb = 'Database\s*=\s*Remotely' } else { $prodDb = 'Database\s*=\s*Remotely(?![A-Za-z0-9_])' }
    if ($mode -eq 'source') { $prodCat = 'Initial\s+Catalog\s*=\s*Remotely' } else { $prodCat = 'Initial\s+Catalog\s*=\s*Remotely(?![A-Za-z0-9_])' }
    $root = (Get-Item -LiteralPath $dir).FullName.TrimEnd('\')
    $files = Get-ChildItem -LiteralPath $dir -Recurse -Force -File |
        Where-Object { $_.Extension -ieq '.json' -or $_.Extension -ieq '.config' }
    $sawSettings = $false
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($root.Length).TrimStart('\')
        $text = (Read-DecodedFile $f.FullName).Text
        $nDb  = [regex]::Matches($text, $prodDb, $opt).Count
        $nCat = [regex]::Matches($text, $prodCat, $opt).Count
        $nEnv = [regex]::Matches($text, 'ConnectionStrings__', $opt).Count
        $nEnvEl = 0
        if ($f.Name -ieq 'web.config') { $nEnvEl = [regex]::Matches($text, '<environmentVariable', $opt).Count }
        if ($f.FullName -ieq (Join-Path $root 'appsettings.json')) {
            $sawSettings = $true
            if ($mode -eq 'source') {
                $nExact = ([regex]::Matches($text, [regex]::Escape('Database=Remotely;'))).Count
                if ($nExact -ne 1 -or $nDb -ne 1) { $problems.Add("$rel : 'Database=Remotely;' tocno=$nExact, sve Database=Remotely*=$nDb (ocekivano 1 i 1)") }
            } else {
                $nTest = ([regex]::Matches($text, [regex]::Escape('Database=Remotely_Test;'))).Count
                if ($nTest -ne 1) { $problems.Add("$rel : 'Database=Remotely_Test;' = $nTest (ocekivano 1)") }
                if ($nDb -ne 0) { $problems.Add("$rel : reference na produkcijsku bazu (Database)=$nDb (ocekivano 0)") }
            }
            if ($nCat -ne 0) { $problems.Add("$rel : Initial Catalog=Remotely*=$nCat (ocekivano 0)") }
            if ($nEnv -ne 0) { $problems.Add("$rel : ConnectionStrings__=$nEnv (ocekivano 0)") }
        } else {
            if ($nDb -ne 0)  { $problems.Add("$rel : Database=Remotely*=$nDb (ocekivano 0)") }
            if ($nCat -ne 0) { $problems.Add("$rel : Initial Catalog=Remotely*=$nCat (ocekivano 0)") }
            if ($nEnv -ne 0) { $problems.Add("$rel : ConnectionStrings__=$nEnv (ocekivano 0)") }
            if ($nEnvEl -ne 0) { $problems.Add("$rel : <environmentVariable>=$nEnvEl (ocekivano 0)") }
        }
    }
    if (-not $sawSettings) { $problems.Add("appsettings.json nije pronadjen") }
    return ,$problems
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
$srcProblems = Get-TokenFindings $ProdToken 'source'
if ($srcProblems.Count -gt 0) {
    Write-Output "Izvorna token mapa ne zadovoljava preduvjete (samo nazivi i brojevi):"
    foreach ($pr in $srcProblems) { Write-Output "  - $pr" }
    Fail "izvorna token konfiguracija nije ocekivana; nista nije stvoreno."
}

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
    $df = Read-DecodedFile $cfgPath
    $enc = $df.Enc
    $text = $df.Text
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
    $tgtProblems = Get-TokenFindings $TokenPath 'target'
    if ($tgtProblems.Count -gt 0) {
        foreach ($pr in $tgtProblems) { Write-Output "  - $pr" }
        throw "kopija token aplikacije jos upucuje na produkcijsku bazu (vidi gore, samo brojevi)."
    }
    Write-Output "Provjera kopije: nema referenci na produkcijsku bazu."

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
