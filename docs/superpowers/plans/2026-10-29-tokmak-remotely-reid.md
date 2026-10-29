# Tokmak: usklađivanje Remotely ID-a, plan implementacije

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kad Tokmak (Halo, interaktivni Tokmak, `Remotely -i`) naiđe na instaliran Remotely agent čiji se
`DeviceID` razlikuje od MachineGuidId-a, ponovno pokreće instaler s ispravnim ID-om, pa Operativa vidi stroj.

**Architecture:** Odluka je u čistoj statičkoj metodi `Remotely.CheckDeviceId` (Integrator.MachineSetup).
`Remotely.Install` dobiva treću granu: servis postoji, a ID je kriv, pa se ponovno pokreće isti `RegularInstall`
kao kod nove instalacije. Očekivani ID nosi novo svojstvo `RemotelyOptions.DeviceId`, koje pune dva postojeća
pozivatelja. Server, agent, instaler i Operativa se ne mijenjaju.

**Tech Stack:** C# (.NET Framework 4.6.2, stari `.csproj`), Newtonsoft.Json, log4net, MSBuild (skill
`vs-build`), Windows PowerShell 5.1 za provjeru logike, TFVC (`tfp`), remotely skill za TOKMAKTEST i CLOUD.

**Spec:** `docs/superpowers/specs/2026-10-29-tokmak-remotely-reid-design.md`

## Global Constraints

- Tokmak je pod TFVC-om (`C:\zeba\Tokmak\Tokmak`):
  - datoteke se otvaraju s `& "$env:USERPROFILE\bin\tfp.cmd" vc checkout <putanja>` iz PowerShella;
  - `checkin` se nikad ne radi, check-in radi korisnik;
  - ne dodaju se nove datoteke ni izmjene `.csproj`.
- Dirate se točno četiri datoteke (spec 9):
  - `Integrator.MachineSetup\RemotelyOptions.cs`;
  - `Integrator.MachineSetup\Remotely.cs`;
  - `Tokmak\Program.cs`;
  - `Tokmak\Commands\RemotelyCommand.cs`.
- Svaka datoteka zadržava svoje kodiranje (BOM) i CRLF. `tfp vc diff <datoteka> /format:unified` mora pokazati
  samo namjeravane retke, a ne cijelu datoteku.
- Log poruke su doslovno iz speca (4.3), na hrvatskom:
  - "Remotely ID {stari} ne odgovara MachineGuidId {novi}, ponovno instaliram";
  - "Remotely ID usklađen";
  - "Usklađivanje Remotely ID-a nije uspjelo".
- Terminologija je "nit", nikad "dretva".
- Nema izmjena na serveru, agentu, instaleru (`Remotely_Install-[523e].exe`) ni Operativi (spec 3.5).
- Na CLOUD-u i TOKMAKTEST-u naredbe idu kroz remotely skill (`$HOME/.claude/skills/remotely/bin/remotely.exe`).
  Produkcijski zapisi uređaja ne brišu se, to radi korisnik.
- Tajne se nikad ne ispisuju (lozinka certifikata u `Tokmak4.csproj` PostBuildEvent, connection stringovi, API
  ključevi).

## Review Focus

1. **Lažni "Mismatch" na svakom Halu.** Ako se putanja ili datoteka krivo pročita, svaki Halo bi ponovno instalirao
   agenta. Pokriva ga scenarij 3 u Tasku 3: drugi Halo ne smije pokrenuti instaler.
2. **BOM na početku JSON-a.** `ConnectionInfo.json` može početi s U+FEFF i mora se ipak parsirati. Pokriva ga
   slučaj `bom` u Tasku 1.
3. **Drugačija velika i mala slova u ključu** (`deviceId` umjesto `DeviceID`). Ključ se traži bez obzira na velika
   i mala slova. Pokriva ga slučaj `key-case` u Tasku 1.
4. **JSON koji nije objekt** (`[]`, `"x"`). Rezultat je `Unreadable`, a ne iznimka. Pokriva ga slučaj
   `not-object` u Tasku 1.
5. **Neuspjela ponovna instalacija.** Stroj ostaje sa starim agentom, a Tokmak upozorava i ne baca iznimku.
   Pokriva ga ponovna provjera nakon `RegularInstall` u Tasku 2.

---

### Task 1: Metoda provjere ID-a

**Files:**
- Modify: `C:\zeba\Tokmak\Tokmak\Integrator.MachineSetup\Remotely.cs` (klasa `Integrator.MachineSetup.Remotely`)
- Test: `C:\Users\isako\AppData\Local\Temp\claude\c--Users-isako-source-repos-Remotely-integrator\a90e5fcc-2305-480f-8d5c-7e1dd60a8b30\scratchpad\Test-DeviceIdCheck.ps1`
  (izvan TFVC-a)

**Interfaces:**
- Produces:
  - `public enum DeviceIdCheck { NotChecked, Match, Mismatch, Unreadable }`, ugniježđen u
    `Integrator.MachineSetup.Remotely`;
  - `public static DeviceIdCheck CheckDeviceId(string connectionInfoJson, string expectedDeviceId, out string currentDeviceId)`.
    Vrijednost `currentDeviceId` je pročitani `DeviceID`, ili `null` ako ga nema.

- [ ] **Step 1: Napisati testnu skriptu**

Windows PowerShell 5.1. Skripta:
- učita `C:\zeba\Tokmak\Tokmak\Integrator.MachineSetup\bin\Release\Integrator.MachineSetup.dll` (`Add-Type -Path`;
  `Newtonsoft.Json.dll` je u istoj mapi);
- za svaki slučaj pozove `[Integrator.MachineSetup.Remotely]::CheckDeviceId($json, $expected, [ref]$current)`;
- usporedi rezultat i `$current`;
- na kraju ispiše `PASS n/n` ili `FAIL <naziv>: <dobiveno>` i izađe s kodom 1 ako je ijedan pao.

Ovdje je `E` = `DC5395D1-E510-48FD-88C4-82661D146E1B`, a `O` = `4B9ECE6E-7DB8-4DE3-BC81-C7CA69045034`.

| Naziv | `connectionInfoJson` | `expectedDeviceId` | Rezultat | `currentDeviceId` |
|---|---|---|---|---|
| match | `{"DeviceID":"E","Host":"https://remote.integrator.hr"}` | `E` | Match | `E` |
| lower | `{"DeviceID":"<E malim slovima>"}` | `E` | Match | E malim slovima |
| braces | `{"DeviceID":"E"}` | `{E}` | Match | `E` |
| other | `{"DeviceID":"O"}` | `E` | Mismatch | `O` |
| empty-id | `{"DeviceID":""}` | `E` | Mismatch | `""` |
| not-guid | `{"DeviceID":"nije-guid"}` | `E` | Mismatch | `nije-guid` |
| no-key | `{"Host":"x"}` | `E` | Mismatch | `null` |
| missing-file | `$null` | `E` | Mismatch | `null` |
| corrupt | `{"DeviceID":` | `E` | Unreadable | `null` |
| not-object | `[]` | `E` | Unreadable | `null` |
| bom | `[char]0xFEFF + '{"DeviceID":"E"}'` | `E` | Match | `E` |
| key-case | `{"deviceId":"E"}` | `E` | Match | `E` |
| expected-empty | `{"DeviceID":"O"}` | `""` | NotChecked | `null` |
| expected-null | `{"DeviceID":"O"}` | `$null` | NotChecked | `null` |
| expected-bad | `{"DeviceID":"O"}` | `abc` | NotChecked | `null` |

- [ ] **Step 2: Pokrenuti skriptu i vidjeti da pada**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <putanja skripte>`
Expected: greška da metoda ili tip `CheckDeviceId` ne postoji.

- [ ] **Step 3: Implementirati `DeviceIdCheck` i `CheckDeviceId` u `Remotely.cs`**

Datoteka se prvo otvara s `tfp vc checkout`. Redoslijed pravila:
1. Ako očekivani ID nije GUID (`Guid.TryParse`), rezultat je `NotChecked`.
2. Ako je sadržaj `null`, rezultat je `Mismatch`.
3. Ukloniti vodeći U+FEFF i parsirati s `JToken.Parse`. Ako parsiranje baci `JsonException` ili rezultat nije
   `JObject`, rezultat je `Unreadable`.
4. `DeviceID` se traži s `JObject.GetValue("DeviceID", StringComparison.OrdinalIgnoreCase)`.
5. Ako vrijednost nema ili nije GUID, rezultat je `Mismatch`. Inače se GUID-ovi uspoređuju s `Guid ==`.

- [ ] **Step 4: Izgraditi `Integrator.MachineSetup` (Release) i pokrenuti skriptu**

Run: skill `vs-build`, MSBuild
`C:\zeba\Tokmak\Tokmak\Integrator.MachineSetup\Integrator.MachineSetup.csproj /restore /p:Configuration=Release`,
zatim skripta iz Stepa 2.
Expected: build bez grešaka, `PASS 15/15`.

- [ ] **Step 5: Provjeriti TFVC**

Run: `& "$env:USERPROFILE\bin\tfp.cmd" vc diff Integrator.MachineSetup\Remotely.cs /format:unified`
(iz `C:\zeba\Tokmak\Tokmak`).
Expected: diff sadrži samo enum i metodu. Bez commita: Tokmak je TFVC, a check-in radi korisnik.

### Task 2: Grana u `Install`, `DeviceId` i testni build

**Files:**
- Modify: `C:\zeba\Tokmak\Tokmak\Integrator.MachineSetup\RemotelyOptions.cs`
- Modify: `C:\zeba\Tokmak\Tokmak\Integrator.MachineSetup\Remotely.cs` (`Install`, oko redaka 25-68)
- Modify: `C:\zeba\Tokmak\Tokmak\Tokmak\Program.cs` (oko retka 921)
- Modify: `C:\zeba\Tokmak\Tokmak\Tokmak\Commands\RemotelyCommand.cs` (oko retka 51)
- Output: `C:\build\tokmak-reid-test\`

**Interfaces:**
- Consumes: `Remotely.CheckDeviceId` i `Remotely.DeviceIdCheck` iz Taska 1.
- Produces:
  - `public string DeviceId { get; set; }` u `RemotelyOptions`, bez vrijednosti u konstruktoru;
  - testni Tokmak u `C:\build\tokmak-reid-test` (`Tokmak4.exe`, `halo.exe`, `.config`).

- [ ] **Step 1: `RemotelyOptions.DeviceId`**

Svojstvo ide uz postojeća, bez vrijednosti u konstruktoru.

- [ ] **Step 2: Pozivatelji pune `DeviceId`**

- `Program.cs`: `startupConfig.RemotelyOptions.DeviceId = id;` u istom bloku u kojem se dopisuju
  `-devicealias/-deviceuuid`, prije `remotely.Install(...)`.
- `RemotelyCommand.Run`: `_options.DeviceId = _machineGuid;` uz postojeće dopisivanje argumenata, prije
  `remotely.Install(_options)`.

- [ ] **Step 3: `private DeviceIdCheck ReadDeviceIdCheck(string expectedDeviceId, out string currentDeviceId)` u `Remotely.cs`**

Redoslijed pravila:
1. Ako očekivani ID nije GUID, rezultat je `NotChecked`, bez čitanja datoteke.
2. Ako `global::MachineSetup.Remotely.GetServiceImagePath()` vrati `null`, rezultat je `Unreadable`.
3. Putanja je `Path.Combine(Path.GetDirectoryName(imagePath), "ConnectionInfo.json")`. Ako datoteka ne postoji,
   poziva se `CheckDeviceId(null, …)`.
4. Inače se poziva `File.ReadAllText`. `IOException` ili `UnauthorizedAccessException` daje `Unreadable`.
5. Pročitani sadržaj ide u `CheckDeviceId`.

- [ ] **Step 4: Treća grana u `Install`**

Kad servis postoji, poziva se `ReadDeviceIdCheck(options.DeviceId, …)`:
- **`Mismatch`:**
  - `_log.InfoFormat("Remotely ID {0} ne odgovara MachineGuidId {1}, ponovno instaliram", <stari ili "(nema)">, options.DeviceId)`;
  - `RegularInstall(options)`;
  - ponovno `ReadDeviceIdCheck`: `Match` daje `_log.Info("Remotely ID usklađen")`, a sve drugo
    `_log.Warn("Usklađivanje Remotely ID-a nije uspjelo")`.
- **`Unreadable`:** `_log.Warn("ConnectionInfo.json nije čitljiv, Remotely ID se ne provjerava")`, bez
  instalacije.
- **`Match` i `NotChecked`:** postojeći `_log.Debug("Remotely Agent je već instaliran.")`.

Ostatak metode (Automatic, start, prečac, klijent) ostaje nepromijenjen.

- [ ] **Step 5: Izgraditi Tokmak4 (Release) i složiti testni build**

Run: skill `vs-build`, MSBuild `C:\zeba\Tokmak\Tokmak\Tokmak4\Tokmak4.csproj /restore /p:Configuration=Release`.
Post-build potpisuje `Tokmak4.exe`, `halo.exe` i `fina.exe`. Zatim:
- `Tokmak4\bin\Release\*` se kopira u `C:\build\tokmak-reid-test\`;
- dodaje se `TEST-BUILD.txt`: "TESTNI BUILD — usklađivanje Remotely ID-a (spec 2026-10-29); ne distribuirati".

Expected: build bez grešaka. `Tokmak4.exe` i `halo.exe` postoje u `C:\build\tokmak-reid-test`.

- [ ] **Step 6: Provjeriti TFVC i logiku**

Run (iz `C:\zeba\Tokmak\Tokmak`):
- `& "$env:USERPROFILE\bin\tfp.cmd" vc status . /recursive`;
- `tfp vc diff` za svaku od četiri datoteke;
- skripta iz Taska 1.

Expected: točno četiri izmjene (`RemotelyOptions.cs`, `Remotely.cs`, `Program.cs`, `RemotelyCommand.cs`),
svaki diff samo s namjeravanim retcima i `PASS 15/15`.

### Task 3: Scenariji na TOKMAKTEST-u i predaja

**Files:**
- Modify: `docs/integrator/produkcija.md` (Remotely-integrator, git)
- Ulaz: `C:\build\tokmak-reid-test\`

**Interfaces:**
- Consumes: testni build iz Taska 2.
- Pomoćne skripte u scratchpadu: `read-machineguid.ps1`, `api-operativa-check.ps1`, `prod-device-ver.ps1`. Svaka
  nova skripta za čitanje baze na CLOUD-u čita connection string iz
  `C:\sites\remotely-net10b\appsettings.json` i ne ispisuje ga.

- [ ] **Step 1: Scenarij 1 (objavljeni Tokmak, svježi stroj)**

Korisnik je pokrenuo Halo na svježem TOKMAKTEST-u. Provjerava se:
- na CLOUD-u, samo čitanjem: zapis s `DeviceName = 'TOKMAKTEST'` ima `AgentVersion = 2026.10.29.0943`, grupu
  Operativa i alias jednak ID-u;
- MachineGuidId preko skilla (`read-machineguid.ps1`) jednak je `DeviceID`;
- `api-operativa-check.ps1` za taj GUID vraća 200.

Expected: sve ispunjeno. Time je zatvorena i T16 iz plana `2026-10-26-remotely-net10.md`.

- [ ] **Step 2: Priprema neusklađenog ID-a**

Preko skilla na TOKMAKTEST-u, kao SYSTEM zadatak (agent se restarta, pa naredba ne smije ovisiti o njemu):
- `ConnectionInfo.json` se kopira u `ConnectionInfo.json.reid-backup`;
- u `ConnectionInfo.json` se upisuje `DeviceID` = novi slučajni GUID i `ServerVerificationToken` = `null`;
- servis se restarta s odgodom, a zadatak se poslije briše.

Expected: uređaj je online pod slučajnim ID-om, a zapis s MachineGuidId-om offline.

- [ ] **Step 3: Scenarij 2 (testni Tokmak, Halo)**

Testni build ide na TOKMAKTEST (skill šalje datoteku ili korisnik kopira). Korisnik pokreće
`Tokmak4.exe Halo -k` iz testnog builda.

Expected:
- ispis sadrži "ne odgovara … ponovno instaliram" i "Remotely ID usklađen";
- uređaj je online pod MachineGuidId-om, s 0943 i grupom Operativa;
- zapis sa slučajnim ID-om je offline;
- Operativa API vraća 200.

- [ ] **Step 4: Scenarij 3 (ponovni Halo)**

Korisnik ponovno pokreće `Tokmak4.exe Halo -k`.

Expected: nema poruke "ponovno instaliram", a `Remotely_Installer.log` u `C:\Windows\Temp` (ili `SystemTemp`)
nije promijenjen.

- [ ] **Step 5 (neobavezno): Scenarij 4 (`Remotely -i`)**

Ponoviti Step 2. Zatim korisnik pokreće `Tokmak4.exe Remotely -i <MachineGuidId> -s false`. Očekivano je isto kao
u Stepu 3.

- [ ] **Step 6: Bilješka i predaja**

- U `docs/integrator/produkcija.md` dodaje se kratak odjeljak:
  - što Tokmak sada radi kod neusklađenog ID-a;
  - rezultati scenarija;
  - ID-ovi zaostalih offline zapisa (slučajni GUID-ovi), koje korisnik briše u web sučelju.
- Commit (lokalno, bez pusha): `git add docs/integrator/produkcija.md`, poruka "Produkcija: Tokmak usklađuje
  Remotely ID (scenariji na TOKMAKTEST-u)".
- Korisniku se predaje popis četiri datoteke za check-in i objavu Tokmaka. Povratak je prethodna inačica
  Tokmaka.
