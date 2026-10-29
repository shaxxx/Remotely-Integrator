# Produkcija: prelazak remote.integrator.hr na .NET 10

Runbook i rezultati za Task 15 (korak 1: server) i Task 16 (korak 2: novi agent za nove instalacije).
Odobrenje korisnika za prelazak: 2026-10-28, nakon izvještaja `staging-krug2.md`.

## 1. Produkcijski build

| Stavka | Vrijednost |
|---|---|
| Verzija | 2026.10.28.1536 |
| Commit | `70ff9e614c34b46c1a78197b88548dd232c4c1e7` |
| Host | `https://remote.integrator.hr` |
| Runtime | .NET 10.0.14 (self-contained, SDK 10.0.403) |
| Izlaz | `C:\build\remotely-net10-prod` |

SHA-256:

```
6592673cbee43ed1c2f49d6cc546d447fcd31580d1e5507a565a8d619a8314bf  Remotely-Agent-x64.zip
7eecb489befc40bc6ef0d68aaf46f8c2ae66d151935f989cc34eed499150b68a  Remotely-Agent-x86.zip
bef88623a444c4b6556ee9005bc6aae8f4ce8501f8c00c369a03a5671738ec16  server.zip
```

Agent paketi iz ovog builda koriste se tek u Task 16 (Tokmak). Server zadržava postojeće pakete u `Content`
(ETag mora ostati jednak, spec P4).


## 2. Osnovica neposredno prije prebacivanja (15:42)

- Uređaja ukupno 1256, online 529, svi s agentom 2021.10.10.1923.
- ETag paketa: x64 `"1d7c3f840097221"`, x86 `"1d7c3f84e574327"`.
- Remote Control zahtjeva u zadnjih 30 min: 2.

## 3. Backup baze

Korisnik je napravio backup i provjeru (`RESTORE VERIFYONLY`): uspješno.

## 4. Deploy

`C:\sites\remotely-net10`: usporedba `Content` 252/252, bez razlike; preflight prebacivanja prošao.

## 5. Prebacivanje

- 2026-10-28 15:42:54: site `Remotely` prebačen na `C:\sites\remotely-net10`.
- Nedostupnost (503) oko 45 s (15:43:03 do 15:43:46); na stagingu je prebacivanje trajalo 4 s.
- 532 greške u `EventLogs` između 15:42:54 i 15:42:58: stari (.NET 5) server je pri gašenju prekinuo veze agenata na `/AgentHub`. Nakon 15:43:30 nema nijedne greške ni upozorenja.
- Stari site ostaje u `C:\sites\remotely` za povratak.

## 6. Brzi testovi

| Provjera | Rezultat |
|---|---|
| ETag x64 / x86 | jednak osnovici; `Cache-Control: no-cache` |
| Online uređaja | 524 (15:44), 526 (15:45), 528 (15:50); osnovica 529 |
| Novi viewer | poslužuje se (K3, K6, R33) |
| Skill `run` | CLOUD, IVICATEST (stari agent), NAPOLEON: OK |
| `/token/token/<IVICATEST>/<token>` | 200 |
| Operativa: status, spajanje, gumb "Remotely" | OK (korisnik) |
| "Integrator podrška" na starom klijentu | OK (korisnik) |
| Remote Control iz weba | OK; `č`/`ć` s fizičke tipkovnice se gube kao i prije (krug 1, odjeljak 4) |
| Greške u logu nakon prebacivanja | 0 |

## 7. Skill recepti (samo čitanje)

- NAPOLEON (Remotely ID `4B9ECE6E-…`): `sql-instances`, `integrator-databases`, `sql-connections` rade; stroj nema SQL Server.
- NAPOLEON se u CEZAR-u vodi pod dva GUID-a (`DC5395D1-…`, `C861A71E-…`), a nijedan nije Remotely ID, pa ga skill po CEZAR GUID-u ne nalazi. To je postojeće stanje podataka, ne posljedica prelaska.
- CLOUD: `sql-instances` i `integrator-databases` rade (MSSQLSERVER 17.0.1000.7).

## 8. Popravci nakon prelaska i novi agent (2026-10-29)

### Uzroci

| Problem | Uzrok | Popravak |
|---|---|---|
| `č`/`ć` s fizičke tipkovnice stižu kao `c`, `đ` kao `d`, `Đ` se gubi | desktop pretvara znak preko `VkKeyScan` u ANSI inačici; na računalima s kodnom stranicom 1252 best-fit (IVICATEST: ACP 1252) | viewer: znakovi izvan ASCII-ja tipkaju se kao tekst; desktop: `VkKeyScan` u Unicode inačici |
| AltGr znakovi (`@ € { } [ ] \ \|`) ne rade, AltGr+V lijepi | desktop ne poznaje `AltGraph`, a `@` dobiva kao Ctrl+Alt+V | viewer: AltGr znakovi kao tekst, `AltGraph` se ne šalje |
| tipka ili klik iza tipkanog teksta se gubi (i "Type Clipboard") | `SendKeys` ostavlja hook na ulaznoj niti, sljedeća radnja padne na promjeni desktopa | desktop: tekst preko `SendInput` na istoj niti; viewer: escape i apsorber i za "Type Clipboard" |
| `ExecuteCommand` vraća 404 nakon 30 s | agent zove `ScriptResultViaApi(requestID)`, server je deklarira s dva argumenta | server bilježi rezultat pri `POST /api/ScriptResults` |
| kartica uređaja u webu pada kad stroj dođe online | kartica se iscrta prije učitavanja korisnika; `GetDeviceGroups(null)` vraćao `null` | `GetDeviceGroups` vraća prazan niz |
| naredbe gube `č`/`ć`/`đ` (ulaz i izlaz) | agent piše/čita u 1252, PowerShell 5.1 u 437 (kodna stranica konzole pri pokretanju) | PowerShell se pokreće u UTF-8 konzoli, CMD uz `chcp 65001`, agent u UTF-8 |

Nije mijenjano: odbijanje "already connected" (štiti od klonova s istim ID-om; agent ponovi za ~90 s), N1, izlazni kod instalera. CMD i dalje ne čita ne-ASCII ulaz (ograničenje cmd-a).

### Koraci

| Vrijeme | Korak |
|---|---|
| 09:00 | IVICATEST: stari agent i svi pokusni ostaci uklonjeni, novi agent 2026.10.29.0852 (isti ID) |
| 09:26 | produkcijski viewer: `InputEventHandlers.js(.map)` zamijenjeni (`*.pre-k37` kopije) |
| 09:32 | server 2026.10.29.0926 (`c5eb3927`) u `C:\sites\remotely-net10b`, prebacivanje ~40 s; povratak: `C:\sites\remotely-net10` |
| 09:45 | IVICATEST ažuriran na 2026.10.29.0943 (`5760c7e3`) istim putem kao automatsko ažuriranje |
| 09:50 | `Content`: `Remotely-Win10-x64/x86.zip` = 0943; stari paketi u `C:\deploy\content-2021`; instaler nepromijenjen |

Paketi 0943 (`C:\build\remotely-net10-prod4`):

```
357ea8dea5074412d83b56f4b217c9cf4ca67d74cb29292473a2a75fe736c77c  Remotely-Agent-x64.zip
2efe90545976f2aa1cea7431de99115645dfed68469cfa555bddd843c04b55d9  Remotely-Agent-x86.zip
```

Povratak paketa: kopirati `C:\deploy\content-2021\*.zip` natrag u `Content`; agenti se tada "ažuriraju" na 2021.

### Prvo automatsko ažuriranje (NAPOLEON)

Restart NAPOLEON-a u 09:52 (stari agent 2021, servis "Automatic (Delayed Start)"). Instaler pokrenut 09:54:56, sigurnosna
kopija, novi servis 09:55:10, online s 2026.10.29.0943 u 09:55:17. Isti DeviceID, token ponovno postavljen, `etag.txt` = novi
ETag ("Version is current"), naredbe preko skilla rade, `č ć đ Đ ž` u izlazu ispravni. U 09:55 je na 0943 već 16 uređaja.

### Ažuriranje flote (stanje 10:30)

- 10:0x korisnik zaustavio server (app pool i site); pri ponovnom pokretanju pool je ostao zaustavljen (pokretanje sitea ne
  pokreće pool) pa je IIS vraćao 503 do 10:11.
- Stari agent pri svakom ponovnom spajanju provjerava ažuriranje, pa je nakon povratka servera ~650 agenata odjednom ušlo u red.
  Server pušta 10 preuzimanja istodobno (`MaxConcurrentUpdates`), čekanje u redu ~20 min, ~12-14 ažuriranja u minuti.
  10:30: 248 uređaja na 0943, 401 online na 2021, 0 grešaka.
- Restart servisa dok agent čeka u redu prekida preuzimanje; sljedeći pokušaj može pasti na zaključanom `RemotelyUpdate.zip`,
  nakon čega stari agent 24 h ne pokušava (do sljedećeg restarta servisa). Viđeno na IVICA.

### Remotely ID i machine GUID (NAPOLEON)

Tokmak instalira agent s `-deviceuuid` = MachineGuidId iz Integrator Supporta, ali instalaciju preskače ako je agent već
instaliran. NAPOLEON je imao agent s ID-om `4B9ECE6E-…` (ConnectionInfo iz 01/2024), a support vraća `DC5395D1-…`, pa ga
Operativa (`GET api/Devices/{MachineGuidId}`) nije nalazila. Ažuriranje ID nije mijenjalo (instaler zadržava DeviceID).

Usklađivanje (10:27): `POST /api/devices` (ID = GUID, alias = GUID, grupa Operativa), na stroju `ConnectionInfo.DeviceID = GUID`,
token prazan, restart servisa (SYSTEM zadatak s odgodom 5 s). NAPOLEON online pod `DC5395D1-…` za 4 s; stari zapis `4B9ECE6E-…`
offline (briše ga korisnik u web sučelju). GUID se na stroju čita kao u Tokmaku: named pipe `integrator`, pozdrav
`Integrator Support`, upit `machineguidid` (2 bajta duljine, UTF-16LE).
