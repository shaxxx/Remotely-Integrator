# Remotely na .NET 10: plan implementacije

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remotely server na `remote.integrator.hr` prebaciti s .NET 5 na .NET 10 tako da postojeći agenti,
Tokmak, Start2023, Operativa i skill rade bez ikakve promjene, a nove instalacije preko Tokmaka dobiju .NET 10
agent.

**Architecture:** Polazi se od upstream taga `v2022.09.16.1006`, koji ima isti protokol, iste API rute i istu
shemu baze kao produkcijski 2021.10.10. Na njega idu male izmjene: K1 (API ključ), K2 (port na .NET 10), K3
(mobilni viewer) i K4 (build). Server se na produkciji mijenja zamjenom fizičke putanje IIS sitea, s povratkom
u manje od minute. Agenti se ne ažuriraju; nove instalacije dobivaju novi paket preko Tokmaka (K5).

**Tech Stack:** ASP.NET Core 10 (Blazor Server, SignalR + MessagePack), EF Core 10 (SQL Server 2025), WPF
desktop klijent, PowerShell SDK, TypeScript viewer, MSTest + Moq, IIS in-process (ANCM V2), PowerShell skripte
za CLOUD, Tokmak (.NET Framework, TFVC).

**Spec:** `docs/superpowers/specs/2026-10-26-remotely-net10-design.md`

## Global Constraints

- Nijedan korak ne smije ostaviti postojećeg klijenta offline (spec 2.1).
- Ne mijenjaju se: postojeći agenti, `Remotely_Install-[523e].exe`, Start2023, Operativa, remotely skill,
  TokenExtractor (`/token`) i `dbo.TokenUpdate` (spec 2.2).
- **P1:** hubovi `/AgentHub`, `/CasterHub` i `/ViewerHub`, njihove metode i potpisi, DTO poruke te API rute i
  modeli ostaju isti.
- **P2:** nema novih EF migracija, a `HasPendingModelChanges()` za `SqlServerDbContext` vraća `false`.
- **P3:** nazivi i putanje ostaju isti: `Remotely-Win10-x64.zip`, `Remotely-Win10-x86.zip`,
  `Remotely_Installer.exe`, `C:\Program Files\Remotely`, `Remotely_Service`, `Remotely_Agent.exe`,
  `Desktop\Remotely_Desktop.exe`.
- **P4:** za iste datoteke u `Content` server vraća isti `ETag` kao produkcija.
- Server `wwwroot\Content` se nikad ne gradi; uvijek se kopira s produkcije, s očuvanim vremenom izmjene.
- Adrese: produkcija `https://remote.integrator.hr`, staging `https://remote-test.integrator.hr`.
- Git: radi se na grani `integrator` u `C:\Users\isako\source\repos\Remotely-integrator`. Commiti su lokalni;
  push samo na izričit zahtjev korisnika.
- Tokmak je pod TFVC-om: datoteke se otvaraju s `tf checkout`, nove dodaju s `tf add`, a **`tf checkin` se nikad
  ne radi** (radi ga korisnik).
- Naredbe na CLOUD-u i IVICATEST-u idu kroz remotely skill. **Svaka naredba koja mijenja stanje traži izričit "da"
  korisnika**, uz prikaz točne naredbe i cilja. Naredbe samo za čitanje ne traže potvrdu.
- Tajne se nikad ne ispisuju: connection stringovi, lozinke, API ključevi. `~/.remotely-skill/config.json` se ne
  mijenja i ne ispisuje.
- Skill `posalji` traži da ciljna mapa na stroju već postoji. Mapa `C:\deploy\<ime>` na CLOUD-u zato se stvara
  prije slanja, uz "da" korisnika.
- Backup i restore baze radi **korisnik** s admin SQL prijavom, jer SYSTEM na CLOUD-u nema prava `sysadmin` ni
  `dbcreator`. T-SQL se zapisuje u runbook (markdown), a ne u `.sql` datoteke.
- ID-evi na CLOUD-u: site `Remotely` = 19; zadana mapa za backup `C:\sql-backup`; mapa za podatke
  `C:\Program Files\Integrator\Baze\`; Tokmakova web `exe` mapa `C:\sites\integrator.hr\wwwroot\tokmak\exe`.
- Uređaji: CLOUD `7665BD18-DDE6-4F36-8743-7C4B49CDC6D5`, IVICATEST `EDFEA380-9C87-4807-BA7F-6D244E06A2D4`.

## Review Focus

Uvjeti koje spec podrazumijeva, a koje nijedan test ne bi uhvatio sam od sebe. Svaki je pokriven testom u
navedenom zadatku:

1. **Zaglavlje API ključa u varijantama koje šalju stvarni klijenti** (razmaci, `basic` malim slovima, tajna s
   `+`, `/` i `=`, tajna s dvotočkom): mora se autorizirati kao i danas. Zadatak 3, a uživo zadaci 7 i 14.
2. **Hrvatska slova u izlazu skripti** (`čćžšđ ČĆŽŠĐ`) kroz stari i novi agent: skill ih mora vidjeti
   nepromijenjena. Zadaci 7 i 14.
3. **Masovno ponovno spajanje nakon prebacivanja** (~660 agenata unutar 30 sekundi): server mora ostati
   odaziv i upravljiv. Zadatak 14 (LoadTester s 1000 agenata).
4. **Putanja paketa s razmakom i hrvatskim slovima** u Tokmakovom `-path` (npr. `%TEMP%` korisnika
   `Ivančić`): installer mora dobiti cijelu putanju. Zadatak 14.
5. **Veliki prijenos datoteke kroz remote control** (50 MB): ponašanje mora biti isto kao na produkciji
   (uspjeh ili ista greška ograničenja). Zadatak 14.

---

## Faza A: osnovica i ugovor protokola (početna točka, prije ikakve izmjene)

### Task 1: Produkcijska osnovica (samo čitanje)

**Files:**
- Create: `Utilities/Integrator/Get-RemotelyBaseline.ps1`
- Create: `Utilities/Integrator/Get-RemotelyFleetStatus.ps1`
- Create: `docs/integrator/baseline-production.md`

**Interfaces:**
- Produces: vrijednosti u `docs/integrator/baseline-production.md` koje koriste zadaci 7, 10, 14 i 15:
  `ETag`, `Length` i `LastWriteTimeUtc` (ticks i ISO) za `Remotely-Win10-x64.zip` i `-x86.zip`; SHA-256 za
  te dvije datoteke i za `Remotely_Installer.exe`; popis `__EFMigrationsHistory`; SHA-256 i broj redaka
  snimke shema (`tablica.stupac:tip:nullable`, sortirano); broj uređaja po `AgentVersion` i `IsOnline`.
- Produces: `Get-RemotelyFleetStatus.ps1 [-Database <ime>]`, koji ispisuje broj uređaja po `AgentVersion` i
  `IsOnline` te ukupno online.

- [ ] **Step 1: Napiši `Get-RemotelyBaseline.ps1`**

Skripta se izvršava **na CLOUD-u**. Parametri su `-SitePath` (zadano `C:\sites\remotely`), `-BaseUrl` (zadano
`https://remote.integrator.hr`) i `-Database` (zadano `Remotely`).
- Connection string čita iz `<SitePath>\appsettings.json` (`ConnectionStrings:SQLServer`), zamjenjuje
  `Database=` zadanim imenom i ne ispisuje ga.
- `ETag` dobiva s `Invoke-WebRequest -Method Head -UseBasicParsing`.
- Ispis je markdown koji se može izravno spremiti.
- Samo čita.

- [ ] **Step 2: Napiši `Get-RemotelyFleetStatus.ps1`**

Isti način spajanja kao u Step 1. Upit:
`SELECT AgentVersion, IsOnline, COUNT(*) FROM Devices GROUP BY AgentVersion, IsOnline`, plus ukupni broj
online uređaja.

- [ ] **Step 3: Pokreni obje skripte na CLOUD-u**

Run: `"$R" run 7665BD18-DDE6-4F36-8743-7C4B49CDC6D5 --timeout 240 --file Utilities/Integrator/Get-RemotelyBaseline.ps1`,
pa isto za `Get-RemotelyFleetStatus.ps1`.
Expected: dva retka s `ETag` (oblik `"<hex>"`), 12 migracija, zadnja `20210417155829_Add Alert Details`, i
1255 ± novi uređaji.

- [ ] **Step 4: Spremi izlaz u `docs/integrator/baseline-production.md` i commitaj**

```bash
git add Utilities/Integrator/Get-RemotelyBaseline.ps1 Utilities/Integrator/Get-RemotelyFleetStatus.ps1 docs/integrator/baseline-production.md
git commit -m "Produkcijska osnovica: ETag, sažeci, shema, flota"
```

### Task 2: Ugovor protokola (P1) sa zlatnim datotekama na početnoj točki

Ovaj zadatak se radi **na `v2022.09.16.1006` bez ikakvih drugih izmjena**. Zlatne datoteke predstavljaju
protokol koji stari agenti i desktop klijenti razumiju.

**Files:**
- Create: `Tests/Server.Tests/Contract/SampleFactory.cs`
- Create: `Tests/Server.Tests/Contract/GoldenFile.cs`
- Create: `Tests/Server.Tests/Contract/ClientInvocationCatalog.cs`
- Create: `Tests/Server.Tests/Contract/HubSignatureTests.cs`
- Create: `Tests/Server.Tests/Contract/HubPayloadGoldenTests.cs`
- Create: `Tests/Server.Tests/Contract/DtoGoldenTests.cs`
- Create: `Tests/Server.Tests/Contract/Golden/*` (generira se)
- Create: `docs/integrator/baseline-tests.md`

**Interfaces:**
- Produces: `public static class SampleFactory { public static object Create(Type type, int seed = 1); }`.
  Determinističko punjenje:
  - `string` → `"<ImeSvojstva>-<seed>"`;
  - brojevi → `seed`;
  - `bool` → `true`;
  - `enum` → prva definirana vrijednost različita od `default`;
  - `DateTime` i `DateTimeOffset` → `2022-09-16T10:06:00Z`;
  - `Guid` → `new Guid(seed, 0, 0, new byte[8])`;
  - `byte[]` → `{1, 2, 3, (byte)seed}`;
  - nizovi i liste → 2 elementa; rječnici → 1 element;
  - klase → javna svojstva sa setterom, rekurzivno do dubine 2; dublje `null`.
- Produces: `public static class GoldenFile { public static void AssertMatches(string name, byte[] actual, [CallerFilePath] string callerPath = ""); }`.
  - Datoteka je `Contract/Golden/<name>.bin`, uz izvorni kod testa.
  - Uz varijablu okoline `REMOTELY_UPDATE_GOLDEN=1` zapisuje datoteku i prolazi.
  - Bez nje uspoređuje bajt po bajt; ako datoteke nema, pada s porukom koja imenuje datoteku.
- Produces: `ClientInvocationCatalog.All` — popis `(string Name, Type[] ArgTypes)` svih poziva koje server
  šalje klijentima: `SendAsync("…", …)` i `Clients.*.SendAsync` u `Server/**`, u stanju početne točke.

- [ ] **Step 1: Izgradi početnu točku i pokreni postojeće testove**

Run:
- `dotnet test Tests/Server.Tests`
- `dotnet test Tests/Shared.Tests`

Expected: rezultat (prošlo, palo, preskočeno) zapisan u `docs/integrator/baseline-tests.md`. Padovi na
početnoj točki se samo bilježe, ne popravljaju.

- [ ] **Step 2: Napiši `HubSignatureTests.HubSignatures_MatchBaseline`**

Za `AgentHub`, `CasterHub` i `ViewerHub` uzima javne metode instance deklarirane na samom tipu, bez
`OnConnectedAsync`, `OnDisconnectedAsync` i `Dispose`.
- Format retka: `Hub.Metoda(TipParametra1,TipParametra2)->PovratniTip`, s `Type.FullName` i čitljivim
  generičkim tipovima.
- Redci su sortirani ordinalno.
- Usporedba: `GoldenFile.AssertMatches("hub-signatures", Encoding.UTF8.GetBytes(text))`.

- [ ] **Step 3: Napiši `HubPayloadGoldenTests`**

- `HubMethodPayloads_MatchBaseline`: za svaku metodu iz Step 2 argumenti dolaze iz `SampleFactory`,
  `new MessagePackHubProtocol().WriteMessage(new InvocationMessage("1", "<Hub>.<Metoda>", args), writer)`,
  pa `GoldenFile.AssertMatches("hub-<Hub>-<Metoda>", bytes)`.
- `ClientInvocationPayloads_MatchBaseline`: isto za `ClientInvocationCatalog.All`, s imenom
  `client-<Name>-<i>`.
- `GoldenPayloads_ParseToSamples`: svaka zlatna datoteka parsira se s `TryParseMessage`, uz binder koji vraća
  tipove parametara. Argumenti serijalizirani u System.Text.Json moraju biti jednaki JSON-u uzorka.

- [ ] **Step 4: Napiši `DtoGoldenTests.Dtos_MatchBaseline`**

Za svaki konkretni tip u imenskom prostoru `Remotely.Shared.Models.RemoteControlDtos` izveden iz `BaseDto`:
- `bytes = MessagePackSerializer.Serialize(type, SampleFactory.Create(type))`;
- `GoldenFile.AssertMatches("dto-<Tip>", bytes)`;
- `MessagePackSerializer.Deserialize(type, bytes)` serijaliziran u JSON jednak je JSON-u uzorka.

- [ ] **Step 5: Generiraj zlatne datoteke**

Run: `$env:REMOTELY_UPDATE_GOLDEN=1; dotnet test Tests/Server.Tests --filter FullyQualifiedName~Contract`
Expected: PASS, a u `Contract/Golden/` nastaju `hub-signatures.bin`, `hub-*`, `client-*` i `dto-*` (22 DTO tipa).

- [ ] **Step 6: Provjeri usporedbu bez generiranja**

Run: `Remove-Item Env:REMOTELY_UPDATE_GOLDEN; dotnet test Tests/Server.Tests --filter FullyQualifiedName~Contract`
Expected: PASS. Zatim namjerno promijeni jedan bajt u `dto-MouseMoveDto.bin` i ponovi: FAIL koji imenuje
datoteku. Vrati datoteku.

- [ ] **Step 7: Commit**

```bash
git add Tests/Server.Tests/Contract docs/integrator/baseline-tests.md
git commit -m "P1: ugovor protokola sa zlatnim datotekama iz v2022.09.16"
```

## Faza B: K1, build i provjera početne točke (krug 1)

### Task 3: K1, API ključ u oba formata

**Files:**
- Modify: `Server/Auth/ApiAuthorizationFilter.cs`
- Create: `Tests/Server.Tests/ApiAuthorizationFilterTests.cs`

**Interfaces:**
- Produces: `public static bool TryParseApiKey(string headerValue, out string keyId, out string secret)` u
  `ApiAuthorizationFilter`.
  - Prihvaća `Basic <base64(keyId:secret)>`; shema se uspoređuje bez obzira na veličinu slova.
  - Prihvaća i `keyId:secret` bez sheme.
  - Dijeli se na **prvoj** dvotočki, a `keyId` i `secret` se trimaju.
  - Neispravan base64, prazan dio ili nedostatak dvotočke vraća `false`, bez iznimke.

- [ ] **Step 1: Napiši testove**

Koriste `Mock<IDataService>`, s `ValidateApiKey(keyId, secret, path, ip)` i `GetApiKey(keyId)` koji vraća
`new ApiToken { OrganizationID = "org1" }`. Kontekst se gradi iz `DefaultHttpContext` (postavi
`Connection.RemoteIpAddress`).

```csharp
[TestMethod] public void RawKeyIdSecret_Valid_Authorizes()      // "key1:secret1" -> Result == null, Headers["OrganizationID"] == "org1"
[TestMethod] public void BasicBase64_Valid_Authorizes()         // "Basic " + Base64("key1:secret1") -> isto
[TestMethod] public void BasicScheme_IsCaseInsensitive()        // "basic " + Base64(...) -> autorizirano
[TestMethod] public void Secret_WithBase64Characters_Passed()   // "key1:ab+/cd==" -> ValidateApiKey("key1","ab+/cd==",…) pozvan
[TestMethod] public void SplitsOnFirstColonOnly()               // "key1:a:b" -> ValidateApiKey("key1","a:b",…)
[TestMethod] public void Whitespace_IsTrimmed()                 // "  key1 : secret1 " -> ValidateApiKey("key1","secret1",…)
[TestMethod] public void MissingHeader_Unauthorized()           // Result is UnauthorizedResult
[TestMethod] public void WrongSecret_Unauthorized()             // ValidateApiKey -> false -> UnauthorizedResult
[TestMethod] public void InvalidBase64_Unauthorized()           // "Basic %%%" -> UnauthorizedResult, bez iznimke
[TestMethod] public void NoColon_Unauthorized()                 // "key1secret1" -> UnauthorizedResult
```

- [ ] **Step 2: Pokreni testove i provjeri da padaju**

Run: `dotnet test Tests/Server.Tests --filter FullyQualifiedName~ApiAuthorizationFilterTests`
Expected: FAIL. `TryParseApiKey` ne postoji, a raw format se odbija.

- [ ] **Step 3: Implementiraj `TryParseApiKey` i koristi je u `OnAuthorization`**

Grana za prijavljenog korisnika ostaje nepromijenjena.

- [ ] **Step 4: Pokreni testove**

Run: `dotnet test Tests/Server.Tests`
Expected: svi testovi iz ovog zadatka PASS, `Contract` PASS, a ostali kao u `baseline-tests.md`.

- [ ] **Step 5: Commit**

```bash
git add Server/Auth/ApiAuthorizationFilter.cs Tests/Server.Tests/ApiAuthorizationFilterTests.cs
git commit -m "K1: API ključ prihvaća KeyId:Secret i Basic base64"
```

### Task 4: K4, build skripta

**Files:**
- Create: `Utilities/Integrator/Build-Integrator.ps1`

**Interfaces:**
- Produces: `Build-Integrator.ps1 -Hostname <https URL> -OutDir <mapa> [-CurrentVersion <a.b.c.d>]`. Izlaz:
  - `<OutDir>\server\`: `dotnet publish Server -c Release -r win-x64 --self-contained`;
  - `<OutDir>\Remotely-Agent-x64.zip` i `<OutDir>\Remotely-Agent-x86.zip`: u korijenu je publish agenta
    (`-r win-<arch> --self-contained`), a u `Desktop\` publish `Desktop.Win` (`-r win-<arch> --self-contained`).
    Isti raspored kao `Remotely-Win10-*.zip`;
  - `<OutDir>\server.zip`: zip mape `server\`;
  - `<OutDir>\SHA256SUMS.txt`: redak `<sha256 malim slovima>  <ime>` za oba paketa agenta i za `server.zip`;
  - `<OutDir>\build-info.txt`: verzija, `git rev-parse HEAD` i `Hostname`.
- Verzija je iz datuma zadnjeg commita (`yyyy.MM.dd.HHmm`, kao u `Publish.ps1`) i prosljeđuje se kao
  `/p:Version` i `/p:FileVersion`.
- Skripta prije builda zamijeni redak `private string _host = "...";` u `Shared/Models/DesktopAppConfig.cs`
  s `-Hostname`, a u `finally` vrati izvorni sadržaj. Ako ta datoteka ima nekommitane izmjene, odbija se
  pokrenuti.

- [ ] **Step 1: Napiši skriptu**

- [ ] **Step 2: Pokreni je za staging**

Run: `pwsh -File Utilities/Integrator/Build-Integrator.ps1 -Hostname https://remote-test.integrator.hr -OutDir C:\build\remotely-k1`
Expected:
- obje zip datoteke sadrže `Remotely_Agent.exe` u korijenu i `Desktop/Remotely_Desktop.exe`;
- `(Get-Item C:\build\remotely-k1\server\Remotely_Server.exe).VersionInfo.FileVersion` jednak je verziji iz
  `build-info.txt`;
- `git status --porcelain` je prazan.

- [ ] **Step 3: Commit**

```bash
git add Utilities/Integrator/Build-Integrator.ps1
git commit -m "K4: build skripta za server i pakete agenta"
```

### Task 5: Staging infrastruktura na CLOUD-u

**Files:**
- Create: `Utilities/Integrator/New-RemotelyStaging.ps1`
- Create: `docs/integrator/staging.md`

**Interfaces:**
- Produces: IIS site `Remotely-Test` (`http *:80:remote-test.integrator.hr`,
  `https *:443:remote-test.integrator.hr`, SNI) s fizičkom putanjom `C:\sites\remotely-test`, pool
  `Remotely-Test`, aplikaciju `/token` na `C:\sites\remotely-test-token` s poolom `Remotely-Test-Token` i
  bazu `Remotely_Test`.
- Produces: ispis ID-a novog sitea, koji koristi win-acme.

- [ ] **Step 1: Napiši `New-RemotelyStaging.ps1`** (izvršava se na CLOUD-u)

Ako site `Remotely-Test` već postoji, skripta se odbija pokrenuti. Inače:
1. Stvara `C:\sites\remotely-test` i `C:\sites\remotely-test-token`.
2. U `C:\sites\remotely-test-token` kopira `C:\sites\remotely\token`, a u njegovom `appsettings.json`
   zamjenjuje `Database=Remotely;` s `Database=Remotely_Test;`, bez ispisa vrijednosti.
3. Na obje mape kopira ACL s `C:\sites\remotely`.
4. Stvara poolove `Remotely-Test` i `Remotely-Test-Token`: No Managed Code, `ApplicationPoolIdentity`,
   `OnDemand`. Poolovi su zasebni jer dvije in-process aplikacije ne mogu dijeliti pool.
5. Stvara site i aplikaciju `/token`.

- [ ] **Step 2: Napiši `docs/integrator/staging.md`**

Runbook sadrži T-SQL za korisnika (SSMS, admin prijava):

```sql
BACKUP DATABASE [Remotely] TO DISK = N'C:\sql-backup\Remotely_staging_copy.bak' WITH COPY_ONLY, INIT, CHECKSUM;
RESTORE FILELISTONLY FROM DISK = N'C:\sql-backup\Remotely_staging_copy.bak';
-- logička imena iz FILELISTONLY upisati umjesto <data> i <log>
RESTORE DATABASE [Remotely_Test] FROM DISK = N'C:\sql-backup\Remotely_staging_copy.bak'
  WITH MOVE N'<data>' TO N'C:\Program Files\Integrator\Baze\Remotely_Test.mdf',
       MOVE N'<log>'  TO N'C:\Program Files\Integrator\Baze\Remotely_Test_log.ldf', RECOVERY;
```

Uz to: naredba za win-acme. Prvo se `C:\win-acme\wacs.exe --help` provjeri za 2.2.9, zatim
`wacs.exe --source iis --siteid <ID> --installation iis`.

- [ ] **Step 3: Pokreni `New-RemotelyStaging.ps1` na CLOUD-u**

Uz izričit "da" korisnika, nakon prikaza naredbe.
Expected: ispis ID-a sitea; `Get-WebBinding -Name Remotely-Test` pokazuje dva bindinga.

- [ ] **Step 4: Korisnik izvršava T-SQL i win-acme**

Expected:
- `SELECT COUNT(*) FROM [Remotely_Test].dbo.Devices` jednak je broju iz osnovice;
- prijava `remotely` se može spojiti na `Remotely_Test`;
- binding `https` ima certifikat s `CN=remote-test.integrator.hr`.

- [ ] **Step 5: Commit**

```bash
git add Utilities/Integrator/New-RemotelyStaging.ps1 docs/integrator/staging.md
git commit -m "Staging: IIS site, /token i runbook za kopiju baze"
```

### Task 6: Skripte za deploy i prebacivanje

**Files:**
- Create: `Utilities/Integrator/Deploy-RemotelyServer.ps1`
- Create: `Utilities/Integrator/Switch-RemotelySite.ps1`

**Interfaces:**
- Produces: `Deploy-RemotelyServer.ps1 -BuildZip <server.zip> -TargetPath <mapa> -SourceSitePath C:\sites\remotely -Database <ime>` (izvršava se na CLOUD-u):
  1. Odbija se pokrenuti ako `TargetPath` postoji i nije prazan.
  2. Raspakira `server.zip` u `TargetPath`.
  3. `robocopy <SourceSitePath>\wwwroot\Content <TargetPath>\wwwroot\Content /E /COPY:DAT /DCOPY:T`, nakon
     čega `Content` buildа više ne postoji, nego samo produkcijski.
  4. Kopira `.well-known` iz izvora, ili ga stvori prazan. Mora postojati prije starta, jer ga `Startup` inače
     ne poslužuje.
  5. `appsettings.json` uzima iz izvora, mijenja `Database=` u `-Database` i dodaje `TrustServerCertificate=True`
     ako nedostaje. Sve ostale vrijednosti ostaju, a ništa se ne ispisuje.
  6. Provjerava `web.config`: `AspNetCoreModuleV2`, `processPath=".\Remotely_Server.exe"`,
     `hostingModel="inprocess"`, `inheritInChildApplications="false"`, `stdoutLogFile=".\logs\stdout"`.
  7. Stvara `logs\` i kopira ACL s izvora.
  8. Ispisuje usporedbu `Length` i `LastWriteTimeUtc` za sve datoteke u `Content` prema izvoru. Svaka
     razlika znači pad skripte.
- Produces: `Switch-RemotelySite.ps1 -SiteName <ime> -PhysicalPath <mapa>` zaustavi pool tog sitea, postavi
  `physicalPath`, pokrene pool i ispiše staru i novu putanju. Dira samo zadani site.

- [ ] **Step 1: Napiši obje skripte**

- [ ] **Step 2: Suhi test na razvojnom računalu**

`Deploy-RemotelyServer.ps1` se pokrene s lažnom izvornom mapom: `Content` s dvije datoteke s postavljenim
`LastWriteTimeUtc`, `appsettings.json` s lažnim connection stringom.
Expected: usporedba prolazi; `appsettings.json` ima `Database=<zadano>` i `TrustServerCertificate=True`;
ponovno pokretanje na istu mapu se odbija.

- [ ] **Step 3: Commit**

```bash
git add Utilities/Integrator/Deploy-RemotelyServer.ps1 Utilities/Integrator/Switch-RemotelySite.ps1
git commit -m "Skripte za deploy servera i prebacivanje fizičke putanje"
```

### Task 7: Krug 1, početna točka na stagingu (odluka o nastavku)

**Files:**
- Create: `docs/integrator/checklist-staging.md`
- Create: `docs/integrator/staging-krug1.md`
- Create: `Utilities/Integrator/Invoke-RemotelyApiCheck.ps1`

**Interfaces:**
- Consumes: build iz Task 4 (`C:\build\remotely-k1`), skripte iz Task 6, osnovica iz Task 1.
- Produces: `Invoke-RemotelyApiCheck.ps1 -BaseUrl <url> -DeviceId <guid>` (izvršava se na razvojnom računalu).
  - API ključ čita iz varijabli okoline `REMOTELY_API_KEY_ID` i `REMOTELY_API_KEY`, koje postavlja korisnik.
    Ključ se nikad ne ispisuje.
  - Radi iste pozive kao skill: `GET api/Devices/{id}` te
    `POST api/Scripting/ExecuteCommand/WinPS/{id}` s tijelom `Write-Output 'čćžšđ ČĆŽŠĐ'` i
    `POST api/Scripting/ExecuteCommand/CMD/{id}` s `echo čćžšđ`.
  - Svaki poziv šalje dvaput: sa zaglavljem `KeyId:Secret` i s `Basic base64(KeyId:Secret)`.
  - Ispisuje status i usporedbu `StandardOutput` s očekivanim tekstom.
- Produces: odluku korisnika "početna točka potvrđena" ili "povratak na `master`".

- [ ] **Step 1: Napiši `checklist-staging.md`**

Stavke krugova 1 i 2 iz spec 7.2, svaka s kolonama "očekivano", "rezultat" i "napomena". Dodatne stavke iz
Review Focusa:
- naredba `Write-Output 'čćžšđ ČĆŽŠĐ'` kroz WinPS i CMD (`echo`) vraća točno te znakove;
- prijenos datoteke od 50 MB kroz remote control ponaša se isto kao na produkciji.

- [ ] **Step 2: Prenesi `server.zip` na CLOUD i deployaj**

Prijenos ide s `posalji` u `C:\deploy\remotely-k1\server.zip`, uz izričit "da" korisnika. Zatim:
`Deploy-RemotelyServer.ps1 -BuildZip C:\deploy\remotely-k1\server.zip -TargetPath C:\sites\remotely-test -SourceSitePath C:\sites\remotely -Database Remotely_Test`
Expected: usporedba `Content` bez razlika.

- [ ] **Step 3: Pokreni pool `Remotely-Test` i provjeri P4**

Run na CLOUD-u: `Get-RemotelyBaseline.ps1 -SitePath C:\sites\remotely-test -BaseUrl https://remote-test.integrator.hr -Database Remotely_Test`
Expected:
- `ETag` za oba zipa jednak je osnovici;
- migracije su iste;
- SHA-256 sheme je isti.

- [ ] **Step 4: Preusmjeri IVICATEST na staging**

Uz izričit "da" korisnika. Naredba u `C:\Program Files\Remotely\ConnectionInfo.json` mijenja samo `Host` u
`https://remote-test.integrator.hr` (ostala polja ostaju, uključujući token) i restarta `Remotely_Service`.
Expected: IVICATEST je online na stagingu (`Get-RemotelyFleetStatus.ps1 -Database Remotely_Test`).

- [ ] **Step 5: Pozivi kao skill**

Run: `pwsh -File Utilities/Integrator/Invoke-RemotelyApiCheck.ps1 -BaseUrl https://remote-test.integrator.hr -DeviceId EDFEA380-9C87-4807-BA7F-6D244E06A2D4`
Expected: svi pozivi 200 u oba formata zaglavlja; `IsOnline=true`; izlaz WinPS i CMD točno `čćžšđ ČĆŽŠĐ`,
odnosno `čćžšđ`.

- [ ] **Step 6: Prođi ostale stavke kruga 1 iz checkliste**

Stari agent i stari desktop: status, remote control iz weba i iz testne Operative,
"Integrator podrška", chat, prijenos datoteka, međuspremnik, Ctrl+Alt+Del, UAC, zaključani ekran, hrvatska
slova i 50 MB. Rezultati idu u `staging-krug1.md`.

- [ ] **Step 7: Odluka korisnika**

Expected: korisnik izričito potvrđuje početnu točku. Ako ne potvrdi, rad staje i otvara se pitanje povratka na
`master` (spec 4.2).

- [ ] **Step 8: Commit**

```bash
git add docs/integrator/checklist-staging.md docs/integrator/staging-krug1.md Utilities/Integrator/Invoke-RemotelyApiCheck.ps1
git commit -m "Krug 1: početna točka v2022.09.16 na stagingu"
```

## Faza C: K2, port na .NET 10

### Task 8: Shared, Server i testovi na .NET 10, uz P2

**Files:**
- Modify: `Shared/Shared.csproj`, `Server/Server.csproj`, `Tests/Server.Tests/Server.Tests.csproj`,
  `Tests/Shared.Tests/Shared.Tests.csproj`
- Modify: `Server/**` samo gdje to traži prevođenje ili rad, bez promjene površine iz P1
- Modify: `Server/appsettings.json` (primjer connection stringa dobiva `TrustServerCertificate=True`)
- Create: `Tests/Server.Tests/Contract/SchemaTests.cs`

**Interfaces:**
- Consumes: zlatne datoteke iz Task 2 i testovi iz Task 3, koji se ne smiju mijenjati.

- [ ] **Step 1: Napiši `SchemaTests.SqlServerModel_HasNoPendingChanges`**

Konfiguracija je `new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?> { ["ConnectionStrings:SQLServer"] = "Server=.;Database=x;TrustServerCertificate=True" }).Build()`,
a test radi `using var ctx = new SqlServerDbContext(config); Assert.IsFalse(ctx.Database.HasPendingModelChanges());`.

- [ ] **Step 2: Provjeri da se test ne prevodi na .NET 6**

Run: `dotnet build Tests/Server.Tests`
Expected: FAIL, jer `HasPendingModelChanges` ne postoji u EF Core 6.

- [ ] **Step 3: Prebaci na `net10.0` i ažuriraj pakete**

- Paketi Microsoft.AspNetCore.\*, Microsoft.EntityFrameworkCore.\*, Npgsql.EntityFrameworkCore.PostgreSQL,
  Microsoft.Extensions.\* i System.Text.Json idu na zadnju stabilnu 10.x.
- MailKit i Swashbuckle.AspNetCore idu na zadnju stabilnu; Microsoft.TypeScript.MSBuild na zadnju 5.x.
- Testni paketi (MSTest, Moq, Microsoft.NET.Test.Sdk) idu na zadnju stabilnu.

- [ ] **Step 4: Popravi greške prevođenja**

Javne metode hubova, DTO tipovi, API rute i modeli se ne mijenjaju (P1).

- [ ] **Step 5: Provjeri P2 alatom**

Run: `dotnet tool update --global dotnet-ef --version 10.*; dotnet ef migrations has-pending-model-changes --project Server --context SqlServerDbContext`
Expected: `No changes have been made to the model since the last migration.`
Ako alat prijavi razliku, rješava se konfiguracijom modela u `AppDb`, a **nikad migracijom**.

- [ ] **Step 6: Pokreni testove**

Run: `dotnet test Tests/Server.Tests; dotnet test Tests/Shared.Tests`
Expected: PASS za `Contract` (bez `REMOTELY_UPDATE_GOLDEN`), K1 i `SchemaTests`. Ostali testovi moraju
proći barem kao u `baseline-tests.md`. Ako zlatna datoteka ne odgovara, rad staje: razlika se analizira i
javlja korisniku, a zlatne datoteke se ne regeneriraju.

- [ ] **Step 7: Provjeri ranjivosti paketa**

Run: `dotnet list Server package --vulnerable --include-transitive; dotnet list Shared package --vulnerable --include-transitive`
Expected: `has no vulnerable packages`.

- [ ] **Step 8: Commit**

```bash
git add Shared Server Tests/Server.Tests Tests/Shared.Tests
git commit -m "K2: Shared i Server na .NET 10, P2 test sheme"
```

### Task 9: Agent i desktop klijent na .NET 10

**Files:**
- Modify: `Agent/Agent.csproj`, `Desktop.Core/Desktop.Core.csproj`, `Desktop.Win/Desktop.Win.csproj`,
  `Tests/Desktop.Win.Tests/Desktop.Win.Tests.csproj`
- Modify: `Agent/**`, `Desktop.Core/**` i `Desktop.Win/**` samo gdje to traži prevođenje ili rad

**Interfaces:**
- Consumes: `Build-Integrator.ps1` iz Task 4.

- [ ] **Step 1: Prebaci TFM i pakete**

- TFM: `net10.0` za `Agent` i `Desktop.Core`, `net10.0-windows` za `Desktop.Win` i `Desktop.Win.Tests`.
- Paketi:
  - `Microsoft.PowerShell.SDK`, `System.Management.Automation` i `Microsoft.WSMan.*` idu na zadnju stabilnu
    verziju koja cilja `net10.0` (provjeriti na nuget.org);
  - SignalR klijent, MessagePack protokol i Microsoft.Extensions.\* na 10.x;
  - SkiaSharp na zadnju stabilnu 2.88.x (3.x samo ako 2.88 ne radi);
  - SharpDX i NAudio ostaju.

- [ ] **Step 2: Odluka o `Microsoft.MixedReality.WebRTC`**

Ako build ili start desktop klijenta pada zbog te biblioteke, uklanja se paket i kod koji ga koristi. DTO tipovi
(`ToggleWebRtcVideoDto` i ostali) i hub metode ostaju, zbog P1. Odluka se upisuje u commit poruku.

- [ ] **Step 3: Izgradi pakete za staging**

Run: `pwsh -File Utilities/Integrator/Build-Integrator.ps1 -Hostname https://remote-test.integrator.hr -OutDir C:\build\remotely-net10-staging`
Expected: build prolazi; oba zipa sadrže `Remotely_Agent.exe` i `Desktop/Remotely_Desktop.exe`;
`runtimeconfig.json` agenta ima `"tfm": "net10.0"`.

- [ ] **Step 4: Pokreni sve testove i provjeri ranjivosti**

Run: `dotnet test Tests/Server.Tests; dotnet test Tests/Shared.Tests; dotnet list Agent package --vulnerable --include-transitive; dotnet list Desktop.Win package --vulnerable --include-transitive`
Expected: testovi PASS kao u Task 8; `has no vulnerable packages`.

- [ ] **Step 5: Commit**

```bash
git add Agent Desktop.Core Desktop.Win Tests/Desktop.Win.Tests
git commit -m "K2: agent i desktop klijent na .NET 10"
```

### Task 10: P4, test ETaga statičkih datoteka

**Files:**
- Modify: `Server/Startup.cs`: `ConfigureStaticFiles` iz `private static` postaje `internal static`
- Modify: `Server/Server.csproj`: `<InternalsVisibleTo Include="Remotely.Server.Tests" />`
- Modify: `Tests/Server.Tests/Server.Tests.csproj`: dodaje se `Microsoft.AspNetCore.TestHost` 10.x
- Create: `Tests/Server.Tests/Contract/StaticFileETagTests.cs`

**Interfaces:**
- Consumes: `Length`, `LastWriteTimeUtc` (ticks) i `ETag` za oba zipa iz `docs/integrator/baseline-production.md`.

- [ ] **Step 1: Napiši test**

```csharp
[DataTestMethod]
[DataRow("Remotely-Win10-x64.zip", <Length x64>, <ticks x64>, "<ETag x64>")]
[DataRow("Remotely-Win10-x86.zip", <Length x86>, <ticks x86>, "<ETag x86>")]
public async Task ContentZip_ETag_MatchesProduction(string fileName, long length, long lastWriteUtcTicks, string expectedETag)
// privremeni WebRoot\Content s datotekom zadane duljine (FileStream.SetLength) i LastWriteTimeUtc;
// TestServer čiji pipeline poziva Startup.ConfigureStaticFiles(app, env), uz WebRootPath i ContentRootPath na privremenu mapu;
// HEAD /Content/<fileName> -> response.Headers.ETag.ToString() == expectedETag;
// HEAD s If-None-Match: expectedETag -> 304.
```

Vrijednosti u `DataRow` prepisuju se doslovno iz osnovice.

- [ ] **Step 2: Pokreni test**

Run: `dotnet test Tests/Server.Tests --filter FullyQualifiedName~StaticFileETagTests`
Expected: PASS. Ako padne, rad staje: P4 je uvjet za korak 1, a odstupanje se javlja korisniku.

- [ ] **Step 3: Commit**

```bash
git add Server/Startup.cs Server/Server.csproj Tests/Server.Tests
git commit -m "P4: ETag za Content jednak produkcijskom"
```

## Faza D: K3, mobilni viewer

Izvor za obje sljedeće zadaće je repozitorij `https://github.com/immense/RemoteControl` (arhiviran). Lokalni
klon je u scratchpadu prethodne sesije; po potrebi ga treba ponovo klonirati. Datoteke su pod
`Immense.RemoteControl.Server/wwwroot/src/`. Logika se prenosi u `Server/wwwroot/src/RemoteControl/`, gdje
je struktura drukčija, pa se prenosi ponašanje, a ne datoteke.

### Task 11: Dodir u vieweru

**Files:**
- Modify: `Server/wwwroot/src/RemoteControl/InputEventHandlers.ts` (i generirani `.js` i `.js.map`, koji se
  commitaju kao i dosad)
- Create: `Utilities/Integrator/Test-ViewerMessages.ps1`

**Interfaces:**
- Produces: `Test-ViewerMessages.ps1` pada ako:
  - neki `ts` u `Server/wwwroot/src/RemoteControl/` zove `MessageSender.<Ime>(` izvan skupa iz početne točke
    (`SendFrameReceived`, `SendSelectScreen`, `SendMouseMove`, `SendMouseDown`, `SendMouseUp`, `SendTap`,
    `SendMouseWheel`, `SendKeyDown`, `SendKeyUp`, `SendKeyPress`, `SendSetKeyStatesUp`, `SendCtrlAltDel`,
    `SendOpenFileTransferWindow`, `SendToggleAudio`, `SendToggleBlockInput`, `SendToggleWebRtcVideo`,
    `SendClipboardTransfer`);
  - `git diff --exit-code v2022.09.16.1006 -- Server/wwwroot/src/RemoteControl/MessageSender.ts` nije prazan.

- [ ] **Step 1: Napiši `Test-ViewerMessages.ps1` i pokreni ga na trenutnom stanju**

Run: `pwsh -File Utilities/Integrator/Test-ViewerMessages.ps1`
Expected: PASS na kodu prije izmjene.

- [ ] **Step 2: Prenesi ponašanje iz commitova `887b5a9`, `1664c8b`, `199970d` i dijela za dodir iz `9358ffb`**

- Long-press na mjestu: miš se pomakne na točku dodira (`SendMouseMove`), zatim desni klik (`SendMouseDown`
  i `SendMouseUp` s tipkom 2).
- Long-press pa pomicanje: klik-i-povuci (`SendMouseDown` s tipkom 0, niz `SendMouseMove`, `SendMouseUp`).
- Prag za long-press i zona mirovanja preuzimaju se iz upstream koda.
- U načinu samo za gledanje ne šalje se nikakav unos.
- Scroll s dva prsta i pinch-zoom iz početne točke ostaju.

- [ ] **Step 3: Izgradi i provjeri ograničenje poruka**

Run: `dotnet build Server; pwsh -File Utilities/Integrator/Test-ViewerMessages.ps1`
Expected: `tsc` bez grešaka, skripta PASS.

- [ ] **Step 4: Commit**

```bash
git add Server/wwwroot/src/RemoteControl Utilities/Integrator/Test-ViewerMessages.ps1
git commit -m "K3: long-press i povlačenje na mobitelu (iz immense/RemoteControl)"
```

### Task 12: Virtualna tipkovnica i međuspremnik

**Files:**
- Modify: `Server/wwwroot/src/RemoteControl/InputEventHandlers.ts`, `UI.ts`, `ClipboardWatcher.ts` (i
  generirani `.js` i `.js.map`)
- Modify: stranica viewera `Server/Pages/RemoteControl.cshtml` i njen CSS (gumb tipkovnice)

- [ ] **Step 1: Prenesi ponašanje iz `f4cb1c5`, `5106350` i `7671cb1` (tipkovnica) te `513d396` i `76c3d3e` (međuspremnik)**

- Gumb tipkovnice je preklopni: tipkovnica ostaje otvorena dok se gumb ponovo ne pritisne i ne zatvara se
  sama gubitkom fokusa.
- Skriveno polje je `<input>`, ne `<textarea>`. Enter i Backspace hvataju se preko `keydown`.
- Zalijepljeni ili upisani tekst ide kao `SendClipboardTransfer(text, true)`, umjesto upstream
  `SendTextTransfer(text, true)` (ista poruka pod starim imenom).
- Kad `navigator.clipboard.readText` nije dostupan ili traži korisničku radnju (Firefox, Safari), viewer
  **jednom** prikaže upozorenje, zapiše oznaku u `localStorage` i ne pokušava sinkronizaciju u pozadini.

- [ ] **Step 2: Izgradi i provjeri ograničenje poruka**

Run: `dotnet build Server; pwsh -File Utilities/Integrator/Test-ViewerMessages.ps1`
Expected: `tsc` bez grešaka, skripta PASS.

- [ ] **Step 3: Commit**

```bash
git add Server/wwwroot Server/Pages/RemoteControl.cshtml
git commit -m "K3: virtualna tipkovnica i međuspremnik na mobitelu"
```

## Faza E: K5, Tokmak

### Task 13: Tokmak uzima paket iz `exe` mape i predaje ga installeru

Radi se u `C:\zeba\Tokmak\Tokmak` (TFVC), uz skill `tfs-workflow` (checkout, add; **bez checkina**).

**Files:**
- Modify: `Integrator.MachineSetup/RemotelyOptions.cs`
- Modify: `Integrator.MachineSetup/FileLocations.cs`
- Modify: `Integrator.MachineSetup/Remotely.cs` (`RegularInstall`)
- Create: `Integrator.MachineSetup/FileHashUtils.cs` (uz `<Compile Include>` u csproj i `tf add`)

**Interfaces:**
- Produces: u `RemotelyOptions`:
  - `RemotelyAgentPackageX64 = "Remotely-Agent-x64.zip"`, `RemotelyAgentPackageX86 = "Remotely-Agent-x86.zip"`;
  - `RemotelyAgentPackageSha256X64` i `RemotelyAgentPackageSha256X86` (string, mala slova), s vrijednostima iz
    `SHA256SUMS.txt` buildа za koji je ta verzija Tokmaka namijenjena.
- Produces: `public static string FileLocations.RemotelyAgentPackageLocation(RemotelyOptions options)` =
  `ExeLocation(options.RemotelyAgentPackageX86, options.RemotelyAgentPackageX64, options.WebUrl)`.
- Produces: `public static string FileHashUtils.Sha256Hex(string path)`, koji vraća heksadecimalni zapis
  malim slovima.

- [ ] **Step 1: `tf checkout` za tri postojeće datoteke**

- [ ] **Step 2: Implementiraj izmjene u `RemotelyOptions`, `FileLocations` i `FileHashUtils`**

- [ ] **Step 3: Izmijeni `RegularInstall`**

Nakon što su installer i certifikati osigurani:
1. Paket se dohvaća kroz `RemotelyAgentPackageLocation`. Ako ga treba preuzeti, ide istim putem kao installer
   (`ExeNeedsDownload`, `DownloadExe`, `DownloadWithProgress`, preimenovanje s `Uri.UnescapeDataString`).
2. Računa se `Sha256Hex` i uspoređuje s očekivanim za arhitekturu (`OsUtils.Is64BitOperatingSystem()`).
3. Ako se ne poklapa: `_log.Error("Remotely paket {0} ima neispravan SHA-256; instalacija se ne pokreće.")` i
   povratak bez instalacije.
4. Ako se poklapa: `parameters = options.SetupCommandLineParameters + $" -path \"{packagePath}\""`.

- [ ] **Step 4: Izgradi Tokmak4 za test na stagingu**

Testni build dobiva SHA-256 vrijednosti iz `C:\build\remotely-net10-staging\SHA256SUMS.txt`, pa ga zbog toga
treba označiti kao testni. Gradi se uz skill `vs-build`.
Expected: build prolazi. Provjera u radu je u Task 14.

- [ ] **Step 5: Bez checkina**

Korisniku se javlja popis izmijenjenih i dodanih datoteka. Check-in u TFVC radi korisnik, tek nakon Task 16.

## Faza F: krug 2 na stagingu

### Task 14: Krug 2, .NET 10 build s K1–K4 i Tokmak s K5

**Files:**
- Create: `docs/integrator/staging-krug2.md`

**Interfaces:**
- Consumes: `C:\build\remotely-net10-staging` (Task 9), skripte iz Task 6, testni Tokmak4 iz Task 13 i
  osnovica iz Task 1.

- [ ] **Step 1: Deploy u novu mapu i prebacivanje**

1. Prijenos `server.zip` na CLOUD, uz izričit "da" korisnika.
2. `Deploy-RemotelyServer.ps1 -BuildZip C:\deploy\remotely-net10-staging\server.zip -TargetPath C:\sites\remotely-test-net10 -SourceSitePath C:\sites\remotely -Database Remotely_Test`.
3. `Switch-RemotelySite.ps1 -SiteName Remotely-Test -PhysicalPath C:\sites\remotely-test-net10`.

Expected: usporedba `Content` bez razlika; IVICATEST (stari agent) ponovo online na stagingu unutar 1 minute.

- [ ] **Step 2: P4 i shema**

Run: `Get-RemotelyBaseline.ps1 -SitePath C:\sites\remotely-test-net10 -BaseUrl https://remote-test.integrator.hr -Database Remotely_Test`
Expected: `ETag` i SHA-256 sheme jednaki osnovici; migracije iste.

- [ ] **Step 3: Stavke za stari agent iz checkliste**

`Invoke-RemotelyApiCheck.ps1` na staging, kao u krugu 1, i isti popis kao u krugu 1, plus:
- K3 na mobitelu: long-press desni klik, povlačenje, scroll s dva prsta, tipkovnica (toggle, Enter,
  Backspace, lijepljenje) i upozorenje za međuspremnik u Firefoxu;
- hrvatska slova;
- 50 MB.

- [ ] **Step 4: Masovno spajanje**

Run (s razvojnog računala): `Tests/LoadTester` s `-serverurl https://remote-test.integrator.hr -organizationid <OrganizationID iz baze>` i 1000 agenata, 10 minuta.
Expected: IVICATEST cijelo vrijeme odgovara na remote control i naredbe kao skill; nakon testa nema grešaka
u logu servera. Lažni uređaji se iz `Remotely_Test` brišu tek uz "da" korisnika.

- [ ] **Step 5: Novi agent preko testnog Tokmaka**

1. Na IVICATEST-u se stari agent deinstalira:
   `"C:\Program Files\Remotely\Remotely_Installer.exe" -uninstall -quiet` (uz "da" korisnika; po potrebi
   preko RDP-a).
2. Testni Tokmak4 pokreće se s `Remotely -i EDFEA380-9C87-4807-BA7F-6D244E06A2D4 -a "<produkcijski SetupCommandLineParameters s -serverurl https://remote-test.integrator.hr>"`,
   uz `TEMP` postavljen na `C:\Temp\Test čćž`.

Expected:
- novi agent je online na stagingu s novom `AgentVersion`;
- nakon 6 sati, ili ručnog restarta servisa, i dalje je na istoj verziji (provjera ažuriranja dobiva 304);
- prolazi popis iz Step 3;
- poziv `/token/token/<id>/<token>` na stagingu vraća 200;
- s namjerno promijenjenim zipom Tokmak odbija instalaciju i to zapiše u log.

- [ ] **Step 6: Installer vraća prethodni agent kad paket ne valja**

Na IVICATEST-u: `Remotely_Installer.exe -install -quiet -path <neispravan zip> -serverurl https://remote-test.integrator.hr -organizationid <OrganizationID>`, kao odvezani proces, uz "da" korisnika.
Expected: unutar 5 minuta IVICATEST je online na stagingu na prethodnoj verziji.

- [ ] **Step 7: Vježba povratka**

`Switch-RemotelySite.ps1 -SiteName Remotely-Test -PhysicalPath C:\sites\remotely-test`, pa natrag na
`C:\sites\remotely-test-net10`.
Expected: oba puta je IVICATEST online unutar 1 minute.

- [ ] **Step 8: IVICATEST natrag na produkciju**

Uz "da" korisnika: `Host` u `ConnectionInfo.json` vraća se na `https://remote.integrator.hr` i servis se
restarta. Novi agent je kompatibilan s produkcijskim serverom.
Expected: IVICATEST online na produkciji (`find IVICATEST`).

- [ ] **Step 9: Zapiši rezultate i commitaj**

```bash
git add docs/integrator/staging-krug2.md
git commit -m "Krug 2: .NET 10 build na stagingu"
```

Korisnik izričito odobrava prelazak na produkciju.

## Faza G: produkcija

### Task 15: Korak 1, nadogradnja produkcijskog servera

**Files:**
- Create: `docs/integrator/produkcija.md` (runbook i rezultati)

**Interfaces:**
- Consumes: skripte iz Task 1 i Task 6, odobrenje iz Task 14.

- [ ] **Step 1: Produkcijski build**

Run: `pwsh -File Utilities/Integrator/Build-Integrator.ps1 -Hostname https://remote.integrator.hr -OutDir C:\build\remotely-net10-prod`
Expected: verzija i SHA-256 zapisani u `produkcija.md`.

- [ ] **Step 2: Neposredno prije prebacivanja**

Pokreću se `Get-RemotelyBaseline.ps1` i `Get-RemotelyFleetStatus.ps1`. Broj online uređaja zapisuje se kao
osnovica prebacivanja.

- [ ] **Step 3: Korisnik radi backup**

```sql
BACKUP DATABASE [Remotely] TO DISK = N'C:\sql-backup\Remotely_pre_net10.bak' WITH COPY_ONLY, INIT, CHECKSUM;
RESTORE VERIFYONLY FROM DISK = N'C:\sql-backup\Remotely_pre_net10.bak';
```

Expected: `The backup set on file 1 is valid.`

- [ ] **Step 4: Deploy**

1. Prijenos `server.zip`, uz "da" korisnika.
2. `Deploy-RemotelyServer.ps1 -BuildZip C:\deploy\remotely-net10-prod\server.zip -TargetPath C:\sites\remotely-net10 -SourceSitePath C:\sites\remotely -Database Remotely`.

Expected: usporedba `Content` bez razlika.

- [ ] **Step 5: Prebacivanje**

Uz "da" korisnika: `Switch-RemotelySite.ps1 -SiteName Remotely -PhysicalPath C:\sites\remotely-net10`.

- [ ] **Step 6: Brzi testovi (spec 6.1, korak 5)**

Expected:
- `ETag` jednak osnovici. Ako nije, **odmah povratak**:
  `Switch-RemotelySite.ps1 -SiteName Remotely -PhysicalPath C:\sites\remotely`.
- Broj online uređaja unutar 15 minuta jednak osnovici iz Step 2.
- `find` i `run` skilla rade na CLOUD-u, IVICATEST-u i jednom klijentskom stroju (samo čitanje).
- Operativa: status, spajanje i gumb "Remotely" sa session ID-om.
- "Integrator podrška" na jednom starom klijentu.
- `/token/token/<IVICATEST id>/<token>` vraća 200.
- U `logs` nema grešaka.

- [ ] **Step 7: Prvi puni test skill recepata**

Uključuje SQL recepte, samo one za čitanje, na jednom klijentu koji korisnik odabere.
Expected: isti rezultati kao prije prebacivanja.

- [ ] **Step 8: Zapiši rezultate i commitaj**

```bash
git add docs/integrator/produkcija.md
git commit -m "Korak 1: produkcijski server na .NET 10"
```

### Task 16: Korak 2, novi agent za nove instalacije

Radi se najmanje nekoliko dana nakon Task 15, bez problema u praćenju.

**Interfaces:**
- Consumes: `C:\build\remotely-net10-prod` (`Remotely-Agent-x64.zip`, `-x86.zip`, `SHA256SUMS.txt`) i
  izmjene iz Task 13.

- [ ] **Step 1: Paketi u Tokmakove `exe` mape**

Uz "da" korisnika paketi idu u `C:\sites\integrator.hr\wwwroot\tokmak\exe` na CLOUD-u (`posalji`), a
korisnik ih kopira na `\\192.168.5.32\Visual\Tokmak\exe`.
Expected: `HEAD http://integrator.hr/tokmak/exe/Remotely-Agent-x64.zip` vraća 200 s ispravnom duljinom.

- [ ] **Step 2: Produkcijske SHA-256 vrijednosti u `RemotelyOptions`**

Upisuju se vrijednosti iz produkcijskog `SHA256SUMS.txt`, pa se gradi Tokmak4 (skill `vs-build`).

- [ ] **Step 3: Korisnik radi check-in i objavljuje Tokmak**

- [ ] **Step 4: Provjera**

1. Na IVICATEST-u se agent deinstalira (uz "da" korisnika).
2. Novi Tokmak instalira agent na produkciju.

Expected:
- IVICATEST je online s novom `AgentVersion`;
- `Get-RemotelyFleetStatus.ps1`: osim IVICATEST-a, nijedan postojeći uređaj nije promijenio `AgentVersion`.

**Povratak:** prethodna verzija Tokmaka.

### Task 17: Praćenje i zatvaranje

- [ ] **Step 1: Sedam dana praćenja**

Svaki dan: `Get-RemotelyFleetStatus.ps1`, pregled logova servera i povratne informacije ljudi koji rade s
Machinesom. Sve se zapisuje u `docs/integrator/produkcija.md`.
Expected: broj online uređaja u rasponu osnovice; nema novih vrsta grešaka.

- [ ] **Step 2: Odluke korisnika na kraju**

- Brisanje `C:\sites\remotely` (stari server), staging sitea, poolova, `C:\sites\remotely-test*` i baze
  `Remotely_Test`.
- Push grane `integrator` na GitHub.

Svaka od tih radnji ide samo na izričit zahtjev korisnika.

- [ ] **Step 3: Commit**

```bash
git add docs/integrator/produkcija.md
git commit -m "Praćenje nakon prelaska na .NET 10"
```
