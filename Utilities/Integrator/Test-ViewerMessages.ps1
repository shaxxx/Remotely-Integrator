# Provjera da viewer (TypeScript) šalje samo poruke koje razumiju i stari (2021.) i novi desktop klijent.
#  1. Svaki poziv MessageSender.<Ime>( u Server/wwwroot/src/RemoteControl/*.ts mora biti u dopuštenom skupu.
#  2. MessageSender.ts mora biti identičan oznaci v2022.09.16.1006.
#
# Dopušteni skup = skup iz početne točke plus SendFile, GetWindowsSessions i ChangeWindowsSession
# (ruling R5): sva tri već zove TS iz početne točke, pa bez njih provjera ne bi prošla ni na
# nepromijenjenom kodu.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$srcDir = Join-Path $repo 'Server/wwwroot/src/RemoteControl'
$tag = 'v2022.09.16.1006'

$allowed = @(
    'SendFrameReceived', 'SendSelectScreen', 'SendMouseMove', 'SendMouseDown', 'SendMouseUp', 'SendTap',
    'SendMouseWheel', 'SendKeyDown', 'SendKeyUp', 'SendKeyPress', 'SendSetKeyStatesUp', 'SendCtrlAltDel',
    'SendOpenFileTransferWindow', 'SendToggleAudio', 'SendToggleBlockInput', 'SendToggleWebRtcVideo',
    'SendClipboardTransfer',
    # R5: već u početnoj točki
    'SendFile', 'GetWindowsSessions', 'ChangeWindowsSession'
)

$failed = $false
$scanned = 0
foreach ($f in Get-ChildItem -Path $srcDir -Filter *.ts -Recurse) {
    $scanned++
    $text = Get-Content -LiteralPath $f.FullName -Raw
    foreach ($m in [regex]::Matches($text, 'MessageSender\.(\w+)\s*\(')) {
        $name = $m.Groups[1].Value
        if ($allowed -notcontains $name) {
            Write-Host "FAIL: $($f.Name) zove nedopuštenu MessageSender.$name("
            $failed = $true
        }
    }
}

if ($scanned -eq 0) {
    Write-Host "FAIL: nijedna .ts datoteka nije skenirana u $srcDir"
    $failed = $true
}

Push-Location $repo
try {
    & git diff --exit-code --quiet $tag -- Server/wwwroot/src/RemoteControl/MessageSender.ts
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAIL: MessageSender.ts se razlikuje od $tag"
        $failed = $true
    }
}
finally { Pop-Location }

if ($failed) { exit 1 }
Write-Host 'PASS'
