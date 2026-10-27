# Deploy-RemotelyServer.ps1
# Izvrsava se na CLOUD-u (Windows PowerShell 5.1, kao SYSTEM preko Remotely agenta).
# Raspakira server.zip u NOVU mapu (TargetPath) i prenosi konfiguraciju i Content iz SourceSitePath.
# Ne pise u SourceSitePath i ne dira IIS (prebacivanje radi Switch-RemotelySite.ps1).
# Ne ispisuje connection string. Ne brise nista automatski.
#
# -CompareOnly: samo ponovi usporedbu Content (korak 8) izvora i cilja; nista ne mijenja.
param(
    [Parameter(Mandatory = $true)][string]$BuildZip,
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [string]$SourceSitePath = 'C:\sites\remotely',
    [Parameter(Mandatory = $true)][string]$Database,
    [switch]$CompareOnly
)
$ErrorActionPreference = 'Stop'

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

function Write-DecodedFile([string]$path, $enc, [string]$text) {
    $body = $enc.GetBytes($text)
    $preamble = $enc.GetPreamble()
    $out = New-Object byte[] ($preamble.Length + $body.Length)
    [Array]::Copy($preamble, 0, $out, 0, $preamble.Length)
    [Array]::Copy($body, 0, $out, $preamble.Length, $body.Length)
    [System.IO.File]::WriteAllBytes($path, $out)
}

# Pronalazi vrijednost "SQLServer" JSON stringa; zahtijeva tocno jedan pogodak.
function Get-SqlServerMatch([string]$text) {
    $ms = [regex]::Matches($text, '"SQLServer"\s*:\s*"((?:[^"\\]|\\.)*)"')
    if ($ms.Count -ne 1) { throw "u appsettings.json ocekivan tocno 1 kljuc SQLServer, nadjeno $($ms.Count)." }
    return $ms[0]
}

# Vraca novu vrijednost connection stringa (samo unutar SQLServer vrijednosti).
function Get-NewSqlValue([string]$val, [string]$db) {
    $opt = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    $kw = '(^|;)(\s*)(Database|Initial\s+Catalog)(\s*=\s*)([^;]*)'
    $n = [regex]::Matches($val, $kw, $opt).Count
    if ($n -ne 1) { throw "u SQLServer vrijednosti ocekivana tocno 1 oznaka baze (Database/Initial Catalog), nadjeno $n." }
    $ev = [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value + $m.Groups[2].Value + $m.Groups[3].Value + $m.Groups[4].Value + $db }
    $new = [regex]::Replace($val, $kw, $ev, $opt)
    if (-not [regex]::IsMatch($new, '(^|;)\s*TrustServerCertificate\s*=', $opt)) {
        if ($new.TrimEnd().EndsWith(';')) { $new = $new.TrimEnd() + 'TrustServerCertificate=True' }
        else { $new = $new + ';TrustServerCertificate=True' }
    }
    return $new
}

function Get-RelativeFiles([string]$root) {
    $map = @{}
    $rootFull = (Get-Item -LiteralPath $root).FullName.TrimEnd('\')
    foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -Force -File)) {
        $rel = $f.FullName.Substring($rootFull.Length).TrimStart('\').ToLowerInvariant()
        $map[$rel] = $f
    }
    return $map
}

# Tocna usporedba u oba smjera: isti skup putanja, Length i LastWriteTimeUtc. Broj razlika postavlja u $script:diffCount (izlaz funkcije je samo ispis).
function Compare-Content([string]$srcDir, [string]$dstDir) {
    $a = Get-RelativeFiles $srcDir
    $b = Get-RelativeFiles $dstDir
    $diffs = 0
    foreach ($k in ($a.Keys | Sort-Object)) {
        if (-not $b.ContainsKey($k)) { Write-Output "RAZLIKA: nedostaje u cilju: $k"; $diffs++; continue }
        $fa = $a[$k]; $fb = $b[$k]
        if ($fa.Length -ne $fb.Length) { Write-Output "RAZLIKA: Length $k izvor=$($fa.Length) cilj=$($fb.Length)"; $diffs++ }
        if ($fa.LastWriteTimeUtc.Ticks -ne $fb.LastWriteTimeUtc.Ticks) {
            Write-Output ("RAZLIKA: LastWriteTimeUtc {0} izvor={1} cilj={2}" -f $k, $fa.LastWriteTimeUtc.ToString('o'), $fb.LastWriteTimeUtc.ToString('o'))
            $diffs++
        }
    }
    foreach ($k in ($b.Keys | Sort-Object)) {
        if (-not $a.ContainsKey($k)) { Write-Output "RAZLIKA: visak u cilju: $k"; $diffs++ }
    }
    Write-Output "Usporedeno datoteka: izvor=$($a.Count) cilj=$($b.Count); razlika=$diffs"
    $script:diffCount = $diffs
}

try {
    # ---- Preflight (nista se ne mijenja dok sve provjere ne prodju) ----
    if ($Database -notmatch '^[A-Za-z0-9_]+$') { Fail "Database smije sadrzavati samo slova, znamenke i _." }
    if (-not (Test-Path -LiteralPath $SourceSitePath -PathType Container)) { Fail "izvor $SourceSitePath ne postoji." }
    $srcFull = (Get-Item -LiteralPath $SourceSitePath).FullName.TrimEnd('\')
    $srcContent = Join-Path $srcFull 'wwwroot\Content'
    if (-not (Test-Path -LiteralPath $srcContent -PathType Container)) { Fail "izvor $srcContent ne postoji." }

    if ($CompareOnly) {
        $tgtFull0 = [System.IO.Path]::GetFullPath($TargetPath).TrimEnd('\')
        Compare-Content $srcContent (Join-Path $tgtFull0 'wwwroot\Content'); $d = $script:diffCount
        if ($d -ne 0) { Fail "usporedba Content nije prosla ($d razlika)." }
        Write-Output "Usporedba Content: OK."
        exit 0
    }

    if (-not (Test-Path -LiteralPath $BuildZip -PathType Leaf)) { Fail "BuildZip $BuildZip ne postoji." }
    $srcSettings = Join-Path $srcFull 'appsettings.json'
    $srcWebConfig = Join-Path $srcFull 'web.config'
    if (-not (Test-Path -LiteralPath $srcSettings)) { Fail "izvor $srcSettings ne postoji." }
    if (-not (Test-Path -LiteralPath $srcWebConfig)) { Fail "izvor $srcWebConfig ne postoji." }

    $tgtFull = [System.IO.Path]::GetFullPath($TargetPath).TrimEnd('\')
    if ($tgtFull -ieq $srcFull) { Fail "TargetPath je isti kao SourceSitePath." }
    if ($tgtFull.StartsWith($srcFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) { Fail "TargetPath je unutar SourceSitePath." }
    $targetExisted = Test-Path -LiteralPath $tgtFull
    if ($targetExisted) {
        $others = @(Get-ChildItem -LiteralPath $tgtFull -Force | Where-Object { $_.Name -ine '.well-known' -or -not $_.PSIsContainer })
        if ($others.Count -gt 0) { Fail "mapa $tgtFull vec postoji i sadrzi nesto osim .well-known; odbijam nastaviti." }
    }
    $tmpExtract = $tgtFull + '.extract-tmp'
    if (Test-Path -LiteralPath $tmpExtract) { Fail "privremena mapa $tmpExtract vec postoji; odbijam nastaviti." }

    # appsettings izvor: provjera prije bilo kakve izmjene
    $srcDf = Read-DecodedFile $srcSettings
    $null = Get-NewSqlValue (Get-SqlServerMatch $srcDf.Text).Groups[1].Value $Database

    # stdoutLogEnabled iz izvornog web.config
    $wcMs = [regex]::Matches((Read-DecodedFile $srcWebConfig).Text, 'stdoutLogEnabled\s*=\s*"([^"]*)"')
    if ($wcMs.Count -ne 1) { Fail "u izvornom web.config ocekivan tocno 1 stdoutLogEnabled, nadjeno $($wcMs.Count)." }
    $stdoutEnabled = $wcMs[0].Groups[1].Value
    if ($stdoutEnabled -cne 'true' -and $stdoutEnabled -cne 'false') { Fail "izvorni stdoutLogEnabled nije true/false." }

    # ---- 1. Raspakiravanje ----
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory((Get-Item -LiteralPath $BuildZip).FullName, $tmpExtract)
    $created.Add("privremena mapa $tmpExtract (brise se na kraju ako sve uspije)")
    if (-not (Test-Path -LiteralPath (Join-Path $tmpExtract 'Remotely_Server.exe'))) { throw "u zip-u nema Remotely_Server.exe u korijenu." }
    if (-not (Test-Path -LiteralPath (Join-Path $tmpExtract 'web.config'))) { throw "u zip-u nema web.config u korijenu." }
    if (Test-Path -LiteralPath (Join-Path $tmpExtract '.well-known')) { throw "zip sadrzi .well-known; to nije ocekivano." }

    if (-not $targetExisted) {
        $null = New-Item -ItemType Directory -Path $tgtFull
        $created.Add("mapa $tgtFull")
    } else {
        $created.Add("sadrzaj u postojecoj mapi $tgtFull")
    }
    foreach ($item in (Get-ChildItem -LiteralPath $tmpExtract -Force)) {
        Move-Item -LiteralPath $item.FullName -Destination $tgtFull
    }
    Remove-Item -LiteralPath $tmpExtract -Force
    $null = $created.RemoveAt(0)
    Write-Output "Raspakirano u $tgtFull."

    # ---- 3. Content (R4) ----
    $tgtContent = Join-Path $tgtFull 'wwwroot\Content'
    if (Test-Path -LiteralPath $tgtContent) {
        Remove-Item -LiteralPath $tgtContent -Recurse -Force
        Write-Output "Obrisan Content iz builda."
    }
    $rcOut = & robocopy.exe $srcContent $tgtContent /E /COPY:DAT /DCOPY:T /NP /NFL /NDL /NJH /R:2 /W:2
    $rc = $LASTEXITCODE
    $rcOut | Where-Object { $_ -match '\S' } | Select-Object -Last 8 | ForEach-Object { Write-Output "  robocopy: $_" }
    if ($rc -ge 8) { throw "robocopy Content nije uspio (izlazni kod $rc)." }
    Write-Output "Content kopiran (robocopy izlazni kod $rc)."

    # ---- 4. .well-known (R3) ----
    $tgtWk = Join-Path $tgtFull '.well-known'
    $srcWk = Join-Path $srcFull '.well-known'
    if (Test-Path -LiteralPath $tgtWk) {
        Write-Output ".well-known u cilju vec postoji; ostaje kakav jest."
    } elseif (Test-Path -LiteralPath $srcWk -PathType Container) {
        Copy-Item -LiteralPath $srcWk -Destination $tgtWk -Recurse
        Write-Output ".well-known kopiran s izvora."
    } else {
        $null = New-Item -ItemType Directory -Path $tgtWk
        Write-Output ".well-known stvoren prazan."
    }

    # ---- 5. appsettings.json ----
    $cfgPath = Join-Path $tgtFull 'appsettings.json'
    Copy-Item -LiteralPath $srcSettings -Destination $cfgPath -Force
    $df = Read-DecodedFile $cfgPath
    $m = Get-SqlServerMatch $df.Text
    $g = $m.Groups[1]
    $newVal = Get-NewSqlValue $g.Value $Database
    $newText = $df.Text.Substring(0, $g.Index) + $newVal + $df.Text.Substring($g.Index + $g.Length)
    Write-DecodedFile $cfgPath $df.Enc $newText
    try {
        $json = (Read-DecodedFile $cfgPath).Text | ConvertFrom-Json
        $srcJson = $df.Text | ConvertFrom-Json
    } catch {
        throw "appsettings.json se nakon izmjene ne moze parsirati."
    }
    $sqlNow = [string]$json.ConnectionStrings.SQLServer
    $okDb = [regex]::Matches($sqlNow, '(^|;)\s*(Database|Initial\s+Catalog)\s*=\s*' + [regex]::Escape($Database) + '\s*(;|$)', 'IgnoreCase').Count
    $okTsc = [regex]::Matches($sqlNow, '(^|;)\s*TrustServerCertificate\s*=', 'IgnoreCase').Count
    if ($okDb -ne 1 -or $okTsc -ne 1) { throw "provjera appsettings.json: baza=$okDb TrustServerCertificate=$okTsc (ocekivano 1 i 1)." }
    $pgSame = ([string]$json.ConnectionStrings.PostgreSQL -ceq [string]$srcJson.ConnectionStrings.PostgreSQL)
    Write-Output "appsettings.json: JSON je valjan, SQLServer baza=$okDb TrustServerCertificate=$okTsc, PostgreSQL nepromijenjen=$pgSame (vrijednosti se ne ispisuju)."

    # ---- 6. web.config ----
    $wcPath = Join-Path $tgtFull 'web.config'
    $wdf = Read-DecodedFile $wcPath
    $wms = [regex]::Matches($wdf.Text, 'stdoutLogEnabled\s*=\s*"[^"]*"')
    if ($wms.Count -ne 1) { throw "u web.config ocekivan tocno 1 stdoutLogEnabled, nadjeno $($wms.Count)." }
    $wnew = $wdf.Text.Substring(0, $wms[0].Index) + ('stdoutLogEnabled="' + $stdoutEnabled + '"') + $wdf.Text.Substring($wms[0].Index + $wms[0].Length)
    Write-DecodedFile $wcPath $wdf.Enc $wnew
    $xml = New-Object System.Xml.XmlDocument
    $xml.Load($wcPath)
    $bad = New-Object System.Collections.Generic.List[string]
    $loc = $xml.SelectSingleNode('/configuration/location')
    if ($null -eq $loc -or $loc.GetAttribute('path') -ne '.' -or $loc.GetAttribute('inheritInChildApplications') -ne 'false') { $bad.Add('location path="." inheritInChildApplications="false"') }
    $h = $xml.SelectNodes('//system.webServer/handlers/add') | Where-Object { $_.GetAttribute('modules') -eq 'AspNetCoreModuleV2' }
    if (@($h).Count -lt 1) { $bad.Add('handler modules="AspNetCoreModuleV2"') }
    $asp = $xml.SelectSingleNode('//system.webServer/aspNetCore')
    if ($null -eq $asp) { $bad.Add('element aspNetCore') } else {
        if ($asp.GetAttribute('processPath') -ne '.\Remotely_Server.exe') { $bad.Add('processPath=".\Remotely_Server.exe"') }
        if ($asp.GetAttribute('hostingModel') -ne 'inprocess') { $bad.Add('hostingModel="inprocess"') }
        if ($asp.GetAttribute('stdoutLogFile') -ne '.\logs\stdout') { $bad.Add('stdoutLogFile=".\logs\stdout"') }
        if ($asp.GetAttribute('stdoutLogEnabled') -ne $stdoutEnabled) { $bad.Add('stdoutLogEnabled kao na izvoru') }
    }
    if ($bad.Count -gt 0) {
        foreach ($b in $bad) { Write-Output "  web.config nema: $b" }
        throw "web.config ne zadovoljava ocekivanja (nista nije popravljeno)."
    }
    Write-Output "web.config: provjera OK; stdoutLogEnabled=$stdoutEnabled (kao na izvoru)."

    # ---- 7. logs i ACL ----
    $tgtLogs = Join-Path $tgtFull 'logs'
    if (-not (Test-Path -LiteralPath $tgtLogs)) { $null = New-Item -ItemType Directory -Path $tgtLogs }
    $srcLogs = Join-Path $srcFull 'logs'
    if (-not (Test-Path -LiteralPath $srcLogs -PathType Container)) { $srcLogs = $srcFull }
    Copy-Dacl $srcFull $tgtFull
    Copy-Dacl $srcLogs $tgtLogs
    Write-Output "DACL kopiran: korijen i logs."

    # ---- 8. Usporedba Content ----
    Compare-Content $srcContent $tgtContent; $d = $script:diffCount
    if ($d -ne 0) { throw "usporedba Content nije prosla ($d razlika)." }
    Write-Output "Usporedba Content: OK."
    Write-Output "Deploy gotov: $tgtFull"
}
catch {
    Fail ("korak nije uspio: " + $_.Exception.Message)
}
