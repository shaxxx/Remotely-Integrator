# Invoke-RemotelyApiCheck.ps1
# Izvrsava se na razvojnom racunalu (PowerShell 7). Radi iste pozive kao skill, u oba formata zaglavlja.
# Kriteriji (R17): ExecuteCommand sa starim agentom ne vraca 200 ni na produkciji (404 nakon ~30 s), pa se
# rezultat cita iz GET api/ScriptResults (trazi se po markeru u ScriptInput). Provjerava se da je ScriptInput
# TOCNO poslani tekst (server ne gubi znakove). StandardOutput se samo biljezi (agent moze gubiti c/c/d).
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

# Ne-ASCII znakovi ispisuju se kao [U+XXXX], ASCII ostaje citljiv.
function Format-Hex([string]$s) {
    if ($null -eq $s) { return '(null)' }
    -join ($s.ToCharArray() | ForEach-Object { if ([int]$_ -lt 128) { [string]$_ } else { '[U+{0:X4}]' -f [int]$_ } })
}
function Get-NonAscii([string]$s) {
    $l = @($s.ToCharArray() | Where-Object { [int]$_ -ge 128 } | ForEach-Object { 'U+{0:X4}' -f [int]$_ })
    if ($l.Count) { $l -join ' ' } else { '(nema)' }
}

$headers = @(
    @{ Name = 'raw';   Value = "${keyId}:${secret}" },
    @{ Name = 'basic'; Value = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${keyId}:${secret}")) }
)

$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false          # redirect (npr. na http) je greska, ne slijedi se
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(90) # ExecuteCommand ceka agenta do ~30 s

# Vraca { Status, Text, Reason, Err }. Err je samo ime tipa iznimke (poruka moze sadrzavati zaglavlja).
function Invoke-Api([string]$Method, [string]$Path, [string]$Auth, [string]$Body) {
    $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $BaseUrl + $Path)
    $null = $req.Headers.TryAddWithoutValidation('Authorization', $Auth)
    if ($Body) {
        $req.Content = [System.Net.Http.StringContent]::new($Body, [Text.UTF8Encoding]::new($false), 'text/plain')
        $req.Content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('text/plain; charset=utf-8')
    }
    $resp = $null
    try {
        $resp = $client.SendAsync($req).GetAwaiter().GetResult()
        $bytes = $resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        [pscustomobject]@{ Status = [int]$resp.StatusCode; Text = [Text.Encoding]::UTF8.GetString($bytes); Reason = $resp.ReasonPhrase; Err = $null }
    } catch {
        $inner = $_.Exception; while ($inner.InnerException) { $inner = $inner.InnerException }
        [pscustomobject]@{ Status = 0; Text = $null; Reason = $null; Err = $inner.GetType().Name }
    } finally { if ($resp) { $resp.Dispose() }; $req.Dispose() }
}

function New-Marker([int]$n) { 'rac-{0:x8}-{1}' -f (Get-Random -Minimum 0 -Maximum ([int]::MaxValue)), $n }

# Tri naredbe; svaka ima jedinstven marker u izlazno neutralnom prefiksu (WinPS: $null = '<m>'; CMD: set _m=<m>& ,
# bez razmaka prije &, inace bi se razmak ubacio u vrijednost; 'rem' se ne koristi jer guta ostatak retka).
function New-Commands([int]$baseN) {
    $m1 = New-Marker ($baseN + 1); $m2 = New-Marker ($baseN + 2); $m3 = New-Marker ($baseN + 3)
    $ps = "Write-Output '$lower $upper'"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($ps))
    $wrapped = "& ([scriptblock]::Create([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64'))))"
    @(
        @{ Label = 'WinPS-raw'; Shell = 'WinPS'; Marker = $m1; Sent = "`$null = '$m1'; $ps";      Expected = "$lower $upper" },
        @{ Label = 'CMD-raw';   Shell = 'CMD';   Marker = $m2; Sent = "set _m=$m2& echo $lower"; Expected = $lower },
        @{ Label = 'WinPS-b64'; Shell = 'WinPS'; Marker = $m3; Sent = "`$null = '$m3'; $wrapped"; Expected = "$lower $upper" }
    )
}

$failed = 0; $total = 0; $n = 0
foreach ($h in $headers) {
    Write-Host "=== zaglavlje: $($h.Name) ==="

    # 1. Devices
    $total++
    $path = "/api/Devices/$DeviceId"
    $r = Invoke-Api 'GET' $path $h.Value $null
    if ($r.Err) { Write-Host "$($h.Name) Devices GET $path  GRESKA ($($r.Err))"; $failed++ }
    elseif ($r.Status -ne 200) { Write-Host "$($h.Name) Devices GET $path  HTTP $($r.Status) ($($r.Reason))  NEUSPJELO"; $failed++ }
    else {
        try {
            $j = $r.Text | ConvertFrom-Json
            Write-Host "$($h.Name) Devices GET $path  HTTP 200  IsOnline=$($j.isOnline) AgentVersion=$($j.agentVersion)"
        } catch { Write-Host "$($h.Name) Devices GET $path  HTTP 200  NEUSPJELO (odgovor nije JSON)"; $failed++ }
    }

    # 2. Naredbe
    $cmds = New-Commands $n
    $n += 3
    foreach ($c in $cmds) {
        $total++
        $tag = "$($h.Name) $($c.Label)"
        $path = "/api/Scripting/ExecuteCommand/$($c.Shell)/$DeviceId"
        Write-Host "$tag  POST $path  (marker $($c.Marker)) ..."
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-Api 'POST' $path $h.Value $c.Sent
        $sw.Stop(); $secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        if ($r.Err) { Write-Host "$tag  ExecuteCommand GRESKA ($($r.Err)) nakon $secs s" }
        elseif ($r.Status -eq 404 -and $secs -ge 25) { Write-Host "$tag  ExecuteCommand HTTP 404 nakon $secs s  (isto kao produkcija sa starim agentom)" }
        elseif ($r.Status -eq 200) { Write-Host "$tag  ExecuteCommand HTTP 200 nakon $secs s" }
        else { Write-Host "$tag  ExecuteCommand HTTP $($r.Status) ($($r.Reason)) nakon $secs s" }

        # Trazenje rezultata u ScriptResults (svake 3 s, do 60 s)
        $found = $null; $pollDeadline = [DateTime]::UtcNow.AddSeconds(60); $polls = 0; $pollErr = $null
        while ($true) {
            $polls++
            $p = Invoke-Api 'GET' '/api/ScriptResults' $h.Value $null
            if ($p.Err) { $pollErr = $p.Err }
            elseif ($p.Status -ne 200) { $pollErr = "HTTP $($p.Status)" }
            else {
                $pollErr = $null
                try {
                    $all = @($p.Text | ConvertFrom-Json)
                    $hits = @($all | Where-Object {
                        $_.deviceID -and ([string]$_.deviceID).Equals($DeviceId, [StringComparison]::OrdinalIgnoreCase) -and
                        $_.scriptInput -and ([string]$_.scriptInput).Contains($c.Marker, [StringComparison]::Ordinal) })
                    if ($hits.Count -eq 1) { $found = $hits[0] }
                    elseif ($hits.Count -gt 1) {
                        # nepravilan timestamp = najstariji; nikad ne baca iznimku
                        $found = $hits | Sort-Object {
                            $d = [DateTime]::MinValue
                            if ($_.PSObject.Properties['timestamp'] -and [DateTime]::TryParse([string]$_.timestamp, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$d)) { $d } else { [DateTime]::MinValue }
                        } -Descending | Select-Object -First 1
                    }
                } catch { $pollErr = "odgovor nije JSON ($($_.Exception.GetType().Name))" }
            }
            if ($found -or [DateTime]::UtcNow -ge $pollDeadline) { break }
            Start-Sleep -Seconds 3
        }

        if (-not $found) {
            $extra = if ($pollErr) { " (zadnja greska: $pollErr)" } else { '' }
            Write-Host "$tag  ScriptResults: NIJE PRONADJENO u 60 s ($polls upita)$extra  NEUSPJELO"
            $failed++; continue
        }
        Write-Host "$tag  ScriptResults: PRONADJENO (upit $polls)"
        if (([string]$found.scriptInput) -ceq $c.Sent) { Write-Host "$tag  ScriptInput: JEDNAK poslanom  OK" }
        else {
            Write-Host "$tag  ScriptInput: RAZLIKUJE SE od poslanog  NEUSPJELO"
            Write-Host "      poslano: $(Format-Hex $c.Sent)"
            Write-Host "      ulaz:    $(Format-Hex ([string]$found.scriptInput))"
            $failed++
        }
        $outParts = @($found.standardOutput | Where-Object { $null -ne $_ })
        $got = ($outParts -join "`n").TrimEnd()
        $verdict = if ($got -ceq $c.Expected) { 'TOCNO' } else { 'RAZLIKUJE SE' }
        Write-Host "$tag  StandardOutput: '$($outParts -join '|')'  znakovi: $(Get-NonAscii $got)  ocekivano: $verdict (informativno)"
        $err = (@($found.errorOutput) -join ' ').Trim()
        if ($err) { Write-Host "$tag  ErrorOutput: $err" }
    }
}
$client.Dispose()
Write-Host ''
if ($failed -eq 0) { Write-Host "SAZETAK: svih $total provjera OK"; exit 0 }
Write-Host "SAZETAK: $failed od $total provjera NIJE prosao"; exit 1
