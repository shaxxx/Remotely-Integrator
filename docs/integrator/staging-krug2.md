# Staging, krug 2: .NET 10 build + novi agent preko testnog Tokmaka

## 1. Uvod

Krug 2 testira server remote.integrator.hr (Remotely) izgrađen na .NET 10 (K1 do K4) na stagingu, sa starim klijentima (agent i desktop 2021) i s novim agentom instaliranim testnom verzijom Tokmaka (K5). Cilj je provjeriti paritet s produkcijom, rad K3 viewera na mobitelu i izvedivost povratka prije prelaska na produkciju.

- Datum testa: 2026-10-28.
- Okruženje: staging site `remote-test.integrator.hr` (pool `Remotely-Test`), baza `Remotely_Test`, organizacija `<organizationId>`.
- Testni stroj: IVICATEST (`EDFEA380-9C87-4807-BA7F-6D244E06A2D4`), stari agent i desktop `2021.10.10.1923`, kasnije novi agent.

### Buildovi

| oznaka | verzija | commit | napomena |
|---|---|---|---|
| net10 (prvi deploy) | server 2026.10.28.1113 | `2e55bcd0` | sve API pozive vraćao 401 (R31), povučen |
| net10b | server 2026.10.28.1131 | `1dcd3f62` | ispravak API ključeva; kasnije hot-patch K3 (R33) |
| net10c (završni) | server 2026.10.28.1357 | `e88536b4` | R31 + R33 + R34 |
| agent paket | 2026.10.28.1113 | `2e55bcd0` | agent zipovi ostali na ovoj verziji (SHA u testnom Tokmaku vrijedi) |

### Mapa sitea na CLOUD-u

| mapa | sadržaj |
|---|---|
| `C:\sites\remotely-test` | K1 build (cilj vježbe povratka), K6 hot-patch `CaptureProcessor.js` (`*.pre-k6`) |
| `C:\sites\remotely-test-net10` | prvi deploy (prije ispravka R31), ne koristi se |
| `C:\sites\remotely-test-net10b` | 1131 (`1dcd3f62`) + hot-patch K3 (`*.pre-k33`) |
| `C:\sites\remotely-test-net10c` | završni build 1357 (`e88536b4`), trenutno aktivan na `Remotely-Test` |

## 2. Rezultati po stavkama

### Server i automatske provjere

| stavka | rezultat | napomena |
|---|---|---|
| Deploy + prebacivanje (korak 1) | OK | `Content` 252/252, 0 razlika; prebacivanje 4 s; `/` i `/RemoteControl` 200; stari agent ponovno online ~20 s nakon prebacivanja |
| P4 ETag | OK | x64 `"1d7c3f840097221"`, x86 `"1d7c3f84e574327"` = produkcija (i na net10c) |
| Shema i migracije | OK | 12 migracija, zadnja `20210417155829_Add Alert Details`; SHA-256 sheme `bc7fa1b7...` = osnovica kruga 1 |
| API provjera (`Invoke-RemotelyApiCheck.ps1`) | OK, 8/8 | izlazi jednaki krugu 1 (raw WinPS `ccžšd CCŽŠÐ`, raw CMD `ccžšd`, base64 `cczsd CCZSD`); ExecuteCommand 404 nakon 30,1 s (stari agent, = produkcija); `Basic` zaglavlje 200 |
| Varijante zaglavlja (1.5/2.5) | nije testirano | uživo samo `raw` i `Basic`; ostalo pokrivaju jedinični testovi |
| LoadTester 1000 agenata | OK, 1000/1000 | 11:39:49 do 11:50:49, 0 grešaka; spojeni do 11:43:49; API provjera pod opterećenjem 8/8; nakon testa samo IVICATEST online, lažni agenti otišli offline čisto; pool živ (w3wp 280 MB) |
| Logovi servera tijekom testa | nalaz | 25 min: 33 info, 2 greške, 1 upozorenje, sve iz jednog zahtjeva u 11:35:11 (`GET /api/Devices`, odjeljak 4) |
| Web RC pod opterećenjem | nije testirano | kontroler nije prijavljen u staging web |

### Ručne provjere sa starim agentom (korisnik, ~12:10 do 13:10)

| stavka | rezultat | napomena |
|---|---|---|
| Web RC a: miš, Start izbornik | OK | stari agent 2021, unattended, net10b (potvrdio korisnik 2026-10-28) |
| Web RC b: hrvatsko tipkanje | OK (= produkcija) | `č`/`ć`/`Č`/`Ć` se gube kao na produkciji (postojeće, krug 1 odjeljak 4), `ž š đ` prolaze (potvrdio korisnik 2026-10-28) |
| Web RC c: međuspremnik u oba smjera | OK | potvrdio korisnik 2026-10-28 |
| Web RC d: UAC prompt (regedit) | OK | vidljiv i može se potvrditi (potvrdio korisnik 2026-10-28) |
| Web RC e: Task Manager, miš i tipkovnica | OK | potvrdio korisnik 2026-10-28 |
| Web RC f: Ctrl+Alt+Del i Lock | OK | gumb u vieweru otvara sigurni ekran, Lock radi (potvrdio korisnik 2026-10-28) |
| Web RC g: otključavanje nakon prijave | OK | slika i upravljanje se nastavljaju (potvrdio korisnik 2026-10-28) |
| Prijenos datoteke 50 MB | OK | SHA-256 identičan, `C:\ProgramData\Remotely\Shared` |
| Chat | OK | |
| Operativa (`BaseUrl` na staging) | OK | |
| Session ID ("Integrator podrška", attended, stari desktop 2021 "Remotely podrska 2021 STAGING") | OK, uz N1 | prvi pokušaj u 12:46 pogodio N1 (zastoj); kasniji pokušaji OK: korisnikov instrumentirani pokus "sve radi uredno", attended pokusi kontrolera (skrivena kartica 181+ slika; u prvom planu s pravim klikovima 735 slika / 735 potvrda). Provjera K6 sa skrivenom karticom dulje od 6 min NIJE ponovljena u krugu 2 (rađena u krugu 1 na K1+K6). Potvrdio korisnik 2026-10-28 |
| Putanje s hrvatskim slovima u prijenosu datoteka | nije testirano | |
| K3 a: long-press desni klik | OK | Android 16, Chromium 155 WebView (potvrdio korisnik 2026-10-28) |
| K3 b: long-press povlačenje | OK | |
| K3 c: scroll/pinch s dva prsta | OK | |
| K3 d: tipkovnica kao preklopni gumb | OK | |
| K3 f: lijepljenje | OK | |
| K3 g: hrvatska slova | OK | |
| K3 e, tipkovnica (tipkanje) | FAIL, pa OK | svako drugo slovo se gubilo (R33); nakon ispravka na net10c OK: slova jednim pritiskom, Enter, Backspace (i u praznom polju), lijepljenje pa slovo, sva hrvatska slova |
| K3 h, upozorenje za međuspremnik u Firefoxu | nije testirano | nema Firefoxa na mobitelu |

### Novi agent preko testnog Tokmaka (koraci 5 do 8)

| korak | rezultat | napomena |
|---|---|---|
| 5. Instalacija (Tokmak4 1.0.30.0, `-s false`, `TEMP=C:\Temp\Test čćž`) | OK | stari agent deinstaliran, novi `2026.10.28.1113` online na stagingu od 14:15:50, grupa Operativa; Tokmak je vratio exit 1 (test artefakt, odjeljak 4) |
| 5. Provjera ažuriranja nakon restarta servisa | OK | "Version is current" (304) |
| 5. `/token/token/<id>/<token>` | OK | 200 na stagingu (token nije ispisan) |
| 5. Odbijanje pokvarenog paketa | OK | log: "Remotely paket ... ima neispravan SHA-256; instalacija se ne pokreće."; nema instalacije (exit 1) |
| 5. Isti popis kao za stari agent s novim agentom | nije testirano | provjereno samo: online, izvršavanje naredbi, `ExecuteCommand` 404 nakon 30 s (rezultati stižu preko `ScriptResults`) |
| 5. Hrvatska slova u izlazu skripte novog agenta | nije testirano | |
| 6. Povrat instalera uz pokvaren paket (prvih 10 MB zipa) | OK | 15:13:07 `-install -path` pokvaren zip: "Backing up current installation." pa "End of Central Directory record could not be found" pa "Restoring backup."; servis Running, agent 1113, DeviceID nepromijenjen, online na stagingu 15:13:24 (manje od 5 min) |
| 7. Vježba povratka | OK | `Remotely-Test` na `C:\sites\remotely-test` (K1) 15:18:20 za 4 s, stranice 200, agent se vratio 15:18:40 i izvršava naredbe; natrag na net10c 15:20:30 za 4 s, 200, `Cache-Control: no-cache`. Bez restorea baze |
| 8. IVICATEST natrag na produkciju | OK | vraćeno izvorno stanje: stari agent 2021.10.10.1923 na produkciji (paket 115664673 B, instaler exit 0), DeviceID `EDFEA380...`, token očišćen, servis restartan; online na produkciji 15:25:16, naredba preko skilla radi |

## 3. Nalazi i ispravci tijekom kruga 2

| pravilo | problem | ispravak | commit |
|---|---|---|---|
| R31 | Svi API pozivi 401 na net10 stagingu. `DataService.ValidateApiKey` prihvaćao samo `PasswordVerificationResult.Success`; postojeće tajne su v3 hashevi s 10.000 PBKDF2 iteracija, a zadano u ASP.NET Core 7+ je 100.000, pa `VerifyHashedPassword` vraća `SuccessRehashNeeded` za ispravne ključeve. Pogodilo bi sve postojeće ključeve (Operativa, skill) nakon prebacivanja produkcije; testovi T3 to nisu uhvatili jer je `ValidateApiKey` bio mockan | prihvaća se `Success` ili `SuccessRehashNeeded`, bez rehasha (podaci u bazi ostaju bajt-identični pa je povratak na stari server siguran); jedinični test s v3 hashom od 10.000 iteracija | `1dcd3f62` |
| R33 | K3 tipkovnica: svako drugo slovo se gubilo. Dokaz na IVICATEST: slanje `a` do `j` jedno po jedno daje u Notepadu `acegi`. Desktop `SendText` koristi `SendKeys.SendWait`, koji ostavlja hook na ulaznoj niti; sljedeća ulazna radnja ne uspije na `SwitchToInputDesktop` i odbacuje se. Isti kod u novom desktopu | samo viewer: escape za specijalne znakove SendKeys (`+^%~(){}[]`) i `SendKeyUp("Shift")` odmah nakon svakog otipkanog teksta, da upije jednu odbačenu radnju. Provjera uživo: `abcdefghij` potpuno (bilo `acegi`), `+ = ( ) ~ % { } [` doslovno, Backspace/Enter, `čćžšđ` | `9afaa794` |
| R34 | Regresija: produkcija šalje `Cache-Control: no-cache` na sve statične datoteke (wwwroot uključujući `/src` JS module, `/Content` zipove), net10 build ne šalje ništa, pa preglednici drže viewer module svježima heuristički (10% starosti) i ne revalidiraju (vidjeli smo uživo: hot-patchirani K3 JS se nije učitao). Nije iz IIS konfiguracije (`web.config` identičan); vjerojatno ponašanje .NET 5 hosta | server postavlja `Cache-Control: no-cache` u svim `UseStaticFiles` registracijama (`Startup.ConfigureStaticFiles`); P4 testovi prošireni; na produkciji je no-cache i na 304 | `e88536b4` |

Server.Tests nakon R31 37/37, nakon R34 38/38. Ispravci R33 i R34 su na stagingu u buildu net10c.

## 4. Otvoreni nalazi

- **N1: povremeno zamrzavanje odmah nakon spajanja (otvoreno, neriješeno).** Sa starim desktopom na net10b stagingu viđeno 2 puta od oko 4 korisnikova spajanja (12:12 unattended prvo spajanje, 12:46 attended prvo spajanje). U desktop logu "Viewer stalled" 20 do 24 s nakon "Starting screen cast". Simptomi: viewer i dalje crta slike svakih 5 do 10 s (dakle ih prima i potvrđuje), ali desktop ne dobiva potvrde i klikovi ne djeluju, pa je blokiran smjer viewer prema desktopu (`ViewerHub.SendDtoToClient` prema casteru); smjer desktop prema viewer radi. Unattended se oporavlja ponovnim pokretanjem agenta. Nije reproducirano u 8 kontroliranih pokusa (API-pokrenuti unattended statični/animirani/s naletom unosa, attended sa skrivenom karticom, attended u prvom planu s fokusom, pravim klikovima i međuspremnikom) ni u jednom korisnikovom pokusu s dijagnostičkim isječkom. Isključeno: WebRTC (`UseWebRtc=False` svugdje), međuspremnik (0 do 2 KB), rukovatelji u desktopu (`ClipboardTransfer`/`SetKeyStatesUp` ne blokiraju), `await`ovi u `ViewerHub`, EventLogs i stdout servera čisti. Korisnik: "možda" viđeno i na produkciji (nije provjereno). Ako se ponovi: dok je zamrznuto zalijepiti `C:\Users\isako\Desktop\rc-dijagnostika.js` u konzolu preglednika, čekati 20 s i izvršiti `copy(rcDump())`; popis `pend`/`slow` OUT razlikuje backpressure na strani servera od odbacivanja u desktopu.
- **N2: međuspremnik veći od 100 KB prekida vezu viewera** (`MaximumReceiveMessageSize=100_000`; isto u 2021 `Startup.cs`). Postojeće.
- **Ograničenje SendKeys (postojeće, vrijedi i za gumb "Type Clipboard" na produkciji):** `^` stiže kao `6`, a `]` se gubi (korisnikovi rasporedi tipkovnice US+HR). Ne ispravlja se.
- **`ExecuteCommand` vraća 404 nakon 30 s i s novim agentom 1113** (rezultati stižu preko `GET api/ScriptResults`). Isto kao stari agent i produkcija. Put `AgentHub ScriptResultViaApi` s novim agentom nije dodatno analiziran.
- **Prvo ponovno spajanje nakon restarta servisa odbijeno (~80 s):** 14:25:52 odbijeno ("There was an issue registering with the server ... organization ID might be incorrect"), websocket zatvoren, uspjeh 14:27:08 (online 14:27:10). Vjerojatno server još drži staru vezu (provjera duplikata u `DeviceCameOnline`); usporedba sa starim agentom/produkcijom nije napravljena.
- **Tokmak: provjera SHA se preskače kad je agent već instaliran** (prvi pokušaj: "Remotely Agent uspjesno instaliran", provjera paketa nije dosegnuta).
- **Tokmak: `UpdateServerToken` ide na tvrdo zadani produkcijski URL `/token`** (provjera tokena na stagingu rađena je ručno, 200).
- **Tokmak exit 1 kad se pokrene kao SYSTEM** (test artefakt): `Remotely.Install` pokreće attended desktop klijent i javlja grešku ako se ugasi unutar 3 s; u sesiji 0 se gasi. Pravi Tokmak radi kao prijavljeni korisnik. Agent je ipak instaliran.
- **Instaler vraća exit 0 i kad instalacija ne uspije** (pokvaren zip, korak 6), pa se exit kod ne može koristiti u Tokmaku.
- **Ponovna instalacija bez `-deviceuuid` daje novi ID uređaja** (sigurnosna instalacija u koraku 5 dala `6ba82194-fd7a-4700-bb47-a65955070b0d`) i neusklađen `ServerVerificationToken`: agent ne prolazi `VerifyServer`, ignorira naredbe i ne spaja se ponovno. Riješeno ručno: DeviceID vraćen na `EDFEA380...`, a `ServerVerificationToken` zapisa `EDFEA380` u `Remotely_Test` postavljen na token uređaja `6ba82194` (1 redak), pa restart servisa (korisnik, 15:10). Zbog toga je IVICATEST bio nedostupan oko 14:32 do 14:43 (korisnik pomogao preko Proxmox konzole).
- **`GET /api/Devices` (popis svih uređaja) puca usred serijalizacije** zbog `usedStoragePercent` = ±Infinity (dijeljenje s nulom). Postojeće: produkcija (.NET 5) prekida vezu usred odgovora, net10 staging vraća 200 s odrezanim JSON-om. `/api/Devices/{id}` (Operativa, skill) nije pogođen.
- Blazor NRE u `DeviceCard.razor:234` iz kruga 1: u krugu 2 nije zasebno provjeravan.

## 5. Incident: API ključ u izlazu pomoćne skripte

Prvo pokretanje pomoćne skripte (`start-rc-staging.ps1`, lokalna skripta kontrolera) ispisalo je API ključ u poruci iznimke provjere zaglavlja. Izlaz je ostao u lokalnom zapisu sesije alata; nije ušao ni u jedan commit ni dokument. Skripta je ispravljena (`-SkipHeaderValidation`, ispisuje se samo tip iznimke). Korisnik je obaviješten. Preporuka: zamijeniti (rotirati) API ključ; ključ je produkcijski, a staging baza je kopija produkcijske.

## 6. Odluke za korisnika prije produkcije (go/no-go)

1. **N1:** prihvatiti kao poznat otvoren rizik ili tražiti dodatnu istragu prije produkcije.
2. **Brisanje** 1000 zapisa `TestDevice-*` i zalutalog uređaja `6ba82194` iz `Remotely_Test` (traži izričiti "da").
3. **R25:** na razvojnom računalu instalirati najnoviji .NET 10 SDK prije produkcijskog builda (paketi su samostalni i nose runtime 10.0.9 iz SDK 10.0.301; CLOUD ima hosting bundle 10.0.14).
4. **`%AppData%\Remotely\Config.json`** na razvojnom računalu prepisan je smoke testom iz T9: vratiti ili obrisati.
5. **TFVC check-in Tokmaka** nakon T16: `Integrator.MachineSetup\RemotelyOptions.cs`, `FileLocations.cs`, `Remotely.cs`, `FileHashUtils.cs` (novi), `Integrator.MachineSetup.csproj`.
6. **`/api/Devices` Infinity bug:** popraviti (zaštita dijeljenja, `TotalStorage` 0 daje 0) ili ostaviti (T17).
7. **Zamjena API ključa** (odjeljak 5).

Stanje IVICATEST-a nakon testa: stari agent 2021 na produkciji (izvorno stanje); u `C:\Temp\remotely-test\` ostali testni klijenti i logovi koraka 5 do 8; UAC `ConsentPromptBehaviorAdmin=5` nepromijenjen.
