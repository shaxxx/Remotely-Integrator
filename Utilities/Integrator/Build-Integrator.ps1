# Build-Integrator.ps1
# Gradi Remotely server i pakete agenta (s desktop klijentom unutar) za Integrator.
# Izvodi se na razvojnom racunalu (PowerShell 7). Ne hardkodira TFM; izvedena je iz Utilities/Publish.ps1.
#
# Izlaz u <OutDir>:
#   server\                      dotnet publish Server (win-x64, self-contained), bez wwwroot\Content
#   server.zip                   zip mape server\
#   Remotely-Agent-x64.zip       agent u korijenu, Desktop.Win u Desktop\
#   Remotely-Agent-x86.zip
#   SHA256SUMS.txt, build-info.txt
param(
    [Parameter(Mandatory = $true)][string]$Hostname,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [string]$CurrentVersion = ''
)
$ErrorActionPreference = 'Stop'

$Root = (Get-Item -LiteralPath $PSScriptRoot).Parent.Parent.FullName

# --- Validacija ulaza
[Uri]$HostUri = $null
if (-not [Uri]::TryCreate($Hostname, [UriKind]::Absolute, [ref]$HostUri) -or $HostUri.Scheme -ne 'https') {
    throw "Hostname mora biti apsolutni https:// URL: '$Hostname'"
}
$Hostname = $Hostname.TrimEnd('/')

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Get-Item -LiteralPath $OutDir).FullName

function Assert-Exit([string]$what) {
    if ($LASTEXITCODE -ne 0) { throw "$what nije uspjelo (exit $LASTEXITCODE)" }
}

Push-Location -Path $Root
try {
    # --- Verzija (kao Publish.ps1)
    if (-not $CurrentVersion) {
        $versionString = git show -s --format=%ci
        Assert-Exit 'git show'
        $d = [DateTimeOffset]::Parse($versionString)
        $CurrentVersion = '{0}.{1}.{2}.{3}{4}' -f $d.Year, $d.Month.ToString().PadLeft(2, '0'), $d.Day.ToString().PadLeft(2, '0'), $d.Hour.ToString().PadLeft(2, '0'), $d.Minute.ToString().PadLeft(2, '0')
    }
    $commit = (git rev-parse HEAD)
    Assert-Exit 'git rev-parse'

    # --- Zastita: DesktopAppConfig.cs mora biti cist
    $cfgRel = 'Shared/Models/DesktopAppConfig.cs'
    $cfgPath = Join-Path $Root $cfgRel
    $dirty = git status --porcelain -- $cfgRel
    Assert-Exit 'git status'
    if ($dirty) { throw "$cfgRel ima nekommitane izmjene; odbijam pokretanje." }

    # --- Ciscenje izlaza
    $serverDir = Join-Path $OutDir 'server'
    $stageRoot = Join-Path $OutDir '_stage'
    foreach ($p in @($serverDir, $stageRoot)) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
    }
    foreach ($f in 'server.zip', 'Remotely-Agent-x64.zip', 'Remotely-Agent-x86.zip', 'SHA256SUMS.txt', 'build-info.txt') {
        $fp = Join-Path $OutDir $f
        if (Test-Path -LiteralPath $fp) { Remove-Item -LiteralPath $fp -Force }
    }

    $verProps = @("/p:Version=$CurrentVersion", "/p:FileVersion=$CurrentVersion")

    # --- Injekcija hostname-a (bajt-vjerno: BOM i CRLF ostaju); vraca se u finally
    $origBytes = [IO.File]::ReadAllBytes($cfgPath)
    $enc = New-Object System.Text.UTF8Encoding($false)
    $text = $enc.GetString($origBytes)   # BOM, ako postoji, ostaje kao U+FEFF i vraca se isto
    $re = [regex]'(?m)^[^\r\n]*private string _host[^\r\n]*'
    $m = $re.Matches($text)
    if ($m.Count -ne 1) { throw "Ocekivan tocno jedan redak 'private string _host', nadjeno $($m.Count)" }
    $newLine = '        private string _host = "' + $Hostname + '";'
    $newText = $re.Replace($text, [System.Text.RegularExpressions.MatchEvaluator] { param($x) $newLine }, 1)

    try {
        [IO.File]::WriteAllBytes($cfgPath, $enc.GetBytes($newText))

        # --- Server
        dotnet publish (Join-Path $Root 'Server') -c Release -r win-x64 --self-contained -p:LibraryRestore=false @verProps --output $serverDir
        Assert-Exit 'dotnet publish Server'

        # Content se nikad ne isporucuje iz repozitorija; produkcijski Content se kopira s produkcije.
        $content = Join-Path $serverDir 'wwwroot\Content'
        if (Test-Path -LiteralPath $content) { Remove-Item -LiteralPath $content -Recurse -Force }

        # --- Agent + Desktop za svaku arhitekturu
        foreach ($arch in 'x64', 'x86') {
            $stage = Join-Path $stageRoot "agent-$arch"
            dotnet publish (Join-Path $Root 'Agent') -c Release -r "win-$arch" --self-contained -p:LibraryRestore=false @verProps --output $stage
            Assert-Exit "dotnet publish Agent $arch"

            # Ekvivalent Desktop.Win/Properties/PublishProfiles/packaged-win-<arch>.pubxml, ali s win-<arch> RID-om
            dotnet publish (Join-Path $Root 'Desktop.Win') -c Release -r "win-$arch" --self-contained true `
                -p:Platform=$arch -p:PublishSingleFile=false -p:PublishReadyToRun=false -p:PublishTrimmed=false `
                -p:LibraryRestore=false @verProps --output (Join-Path $stage 'Desktop')
            Assert-Exit "dotnet publish Desktop.Win $arch"
        }
    }
    finally {
        [IO.File]::WriteAllBytes($cfgPath, $origBytes)
    }

    # --- Zipovi (CreateFromDirectory: forward slash unosi, bez dodatne vršne mape)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    function New-Zip([string]$dir, [string]$zip) {
        [System.IO.Compression.ZipFile]::CreateFromDirectory($dir, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
    }
    New-Zip (Join-Path $stageRoot 'agent-x64') (Join-Path $OutDir 'Remotely-Agent-x64.zip')
    New-Zip (Join-Path $stageRoot 'agent-x86') (Join-Path $OutDir 'Remotely-Agent-x86.zip')
    New-Zip $serverDir (Join-Path $OutDir 'server.zip')

    # --- SHA256SUMS.txt (LF, bez BOM-a)
    $lines = foreach ($n in 'Remotely-Agent-x64.zip', 'Remotely-Agent-x86.zip', 'server.zip') {
        $h = (Get-FileHash -LiteralPath (Join-Path $OutDir $n) -Algorithm SHA256).Hash.ToLowerInvariant()
        "$h  $n"
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $OutDir 'SHA256SUMS.txt'), (($lines -join "`n") + "`n"), $utf8)

    # --- build-info.txt
    $info = "version: $CurrentVersion`ncommit: $commit`nhostname: $Hostname`n"
    [IO.File]::WriteAllText((Join-Path $OutDir 'build-info.txt'), $info, $utf8)

    Remove-Item -LiteralPath $stageRoot -Recurse -Force
    Write-Host "Gotovo: $OutDir (verzija $CurrentVersion)"
}
finally {
    Pop-Location
}
