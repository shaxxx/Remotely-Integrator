# Invoke-RemotelyApiCheck.ps1
# Izvrsava se na razvojnom racunalu (PowerShell 7). Radi iste pozive kao skill, u oba formata zaglavlja.
# Izvor kljuca (prvi koji vrijedi):
#   1. varijable okoline REMOTELY_API_KEY_ID i REMOTELY_API_KEY, ako su OBJE postavljene (explicitna zamjena)
#   2. config skilla ~/.remotely-skill/config.json: remotely.apiKeyId i remotely.apiKey (JSON, moze imati UTF-8 BOM)
# Config se samo cita, nikad se ne mijenja. Kljuc, kljuc-id i vrijednosti iz configa se nikad ne ispisuju.
#
# Kodiranje: datoteka je ASCII; hrvatska slova grade se iz code pointova ([char]0x010D ...), pa
# rezultat ne ovisi o tome kako PowerShell 5.1/7 ili editor cita datoteku.
param(
    [Parameter(Mandatory)][string]$BaseUrl,
    [Parameter(Mandatory)][string]$DeviceId
)
$ErrorActionPreference = 'Stop'

# Vraca objekt { Ok, Source, KeyId, Secret, Error }. Greske su fiksni tekstovi bez vrijednosti iz configa;
# iz iznimki se ispisuje samo tip. Ne pise nista.
function Get-ApiKey([string]$ConfigPath) {
    function Fail([string]$Message) {
        [pscustomobject]@{ Ok = $false; Source = $null; KeyId = $null; Secret = $null; Error = $Message }
    }

    $envId     = $env:REMOTELY_API_KEY_ID
    $envSecret = $env:REMOTELY_API_KEY
    if (-not [string]::IsNullOrWhiteSpace($envId) -and -not [string]::IsNullOrWhiteSpace($envSecret)) {
        return [pscustomobject]@{ Ok = $true; Source = 'env'; KeyId = $envId; Secret = $envSecret; Error = $null }
    }

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        return Fail 'config ne postoji (~/.remotely-skill/config.json)'
    }
    try {
        $raw = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8
    } catch {
        return Fail "config ne moze se procitati ($($_.Exception.GetType().Name))"
    }
    if ($raw) { $raw = $raw.TrimStart([char]0xFEFF) }   # BOM, ako ga ima
    try {
        $cfg = $raw | ConvertFrom-Json
    } catch {
        return Fail "config nije valjan JSON ($($_.Exception.GetType().Name))"
    }
    $section = $cfg.remotely
    $id      = $section.apiKeyId
    $secret  = $section.apiKey
    if (-not ($id -is [string]) -or -not ($secret -is [string]) -or
        [string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($secret)) {
        return Fail 'u configu nema remotely.apiKeyId/apiKey'
    }
    [pscustomobject]@{ Ok = $true; Source = 'config'; KeyId = $id; Secret = $secret; Error = $null }
}

$key = Get-ApiKey (Join-Path $HOME '.remotely-skill/config.json')
if (-not $key.Ok) {
    Write-Host "GRESKA: $($key.Error)"
    exit 2
}
$keyId  = $key.KeyId
$secret = $key.Secret
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)  # da se hrvatska slova ispisu ispravno
if ($key.Source -eq 'env') {
    Write-Host 'Kljuc: iz varijabli okoline'
} else {
    Write-Host 'Kljuc: iz configa skilla (~/.remotely-skill/config.json)'
}
$BaseUrl = $BaseUrl.TrimEnd('/')

function U([int[]]$cp) { -join ($cp | ForEach-Object { [char]$_ }) }
# c, c', z, s, dj  /  C, C', Z, S, DJ
$lower = U 0x010D, 0x0107, 0x017E, 0x0161, 0x0111
$upper = U 0x010C, 0x0106, 0x017D, 0x0160, 0x0110

$headers = @(
    @{ Name = 'raw';   Value = "${keyId}:${secret}" },
    @{ Name = 'basic'; Value = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${keyId}:${secret}")) }
)
$calls = @(
    @{ Label = 'Devices'; Method = 'GET';  Path = "/api/Devices/$DeviceId"; Body = $null; Expected = $null },
    @{ Label = 'WinPS';   Method = 'POST'; Path = "/api/Scripting/ExecuteCommand/WinPS/$DeviceId"
       Body = "Write-Output '$lower $upper'"; Expected = "$lower $upper" },
    @{ Label = 'CMD';     Method = 'POST'; Path = "/api/Scripting/ExecuteCommand/CMD/$DeviceId"
       Body = "echo $lower"; Expected = $lower }
)

$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false          # redirect (npr. na http) je greska, ne slijedi se
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(75) # server ceka agenta do ~30 s

function Get-CodePoints([string]$s) { ($s.ToCharArray() | ForEach-Object { '{0:X4}' -f [int]$_ }) -join ' ' }

$failed = 0; $total = 0
foreach ($h in $headers) {
    foreach ($c in $calls) {
        $total++
        $prefix = '{0,-5} {1,-7} {2,-4}' -f $h.Name, $c.Label, $c.Method
        $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($c.Method), $BaseUrl + $c.Path)
        $null = $req.Headers.TryAddWithoutValidation('Authorization', $h.Value)
        if ($c.Body) {
            $req.Content = [System.Net.Http.StringContent]::new($c.Body, [Text.UTF8Encoding]::new($false), 'text/plain')
            $req.Content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('text/plain; charset=utf-8')
        }
        $resp = $null
        try {
            $resp = $client.SendAsync($req).GetAwaiter().GetResult()
            $status = [int]$resp.StatusCode
            $bytes = $resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            $text = [Text.Encoding]::UTF8.GetString($bytes)
        } catch {
            # Ispisuje se samo kratak razlog; poruka iznimke moze sadrzavati zaglavlja pa se ne ispisuje.
            $inner = $_.Exception; while ($inner.InnerException) { $inner = $inner.InnerException }
            Write-Host "$prefix $($c.Path)  GRESKA ($($inner.GetType().Name))"
            $failed++; continue
        } finally { if ($resp) { $resp.Dispose() }; $req.Dispose() }

        if ($status -ne 200) {
            $why = if ($status -ge 300 -and $status -lt 400) { 'redirect, ne slijedi se' } else { $resp.ReasonPhrase }
            Write-Host "$prefix $($c.Path)  HTTP $status ($why)  NEUSPJELO"
            $failed++; continue
        }
        try { $json = $text | ConvertFrom-Json } catch {
            Write-Host "$prefix $($c.Path)  HTTP 200  NEUSPJELO (odgovor nije JSON)"; $failed++; continue
        }
        if ($c.Label -eq 'Devices') {
            Write-Host "$prefix $($c.Path)  HTTP 200  IsOnline=$($json.isOnline) AgentVersion=$($json.agentVersion)"
            if ($json.isOnline -ne $true) { Write-Host '      IsOnline nije true'; $failed++ }
        } else {
            $got = (@($json.standardOutput) -join "`n").TrimEnd()
            if ($got -ceq $c.Expected) {
                Write-Host "$prefix $($c.Path)  HTTP 200  OK  '$got'"
            } else {
                $err = (@($json.errorOutput) -join ' ').Trim()
                Write-Host "$prefix $($c.Path)  HTTP 200  MISMATCH  primljeno='$got'"
                Write-Host "      primljeno (hex): $(Get-CodePoints $got)"
                Write-Host "      ocekivano (hex): $(Get-CodePoints $c.Expected)"
                if ($err) { Write-Host "      ErrorOutput: $err" }
                $failed++
            }
        }
    }
}
$client.Dispose()
Write-Host ''
if ($failed -eq 0) { Write-Host "SAZETAK: svih $total poziva OK"; exit 0 }
Write-Host "SAZETAK: $failed od $total poziva NIJE prosao"; exit 1
