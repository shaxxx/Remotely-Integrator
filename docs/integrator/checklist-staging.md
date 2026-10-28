# Checklista staginga (remote-test.integrator.hr)

Osnovica vrijednosti (ETag, migracije, SHA-256 sheme) je u `docs/integrator/baseline-production.md`. Stupci `rezultat` i `napomena` popunjavaju se tijekom testa. Rezultati kruga 1 prepisuju se u `staging-krug1.md`.

Provjere API-ja rade se skriptom `Utilities/Integrator/Invoke-RemotelyApiCheck.ps1` (ključ se čita iz configa skilla `~/.remotely-skill/config.json`, polja `remotely.apiKeyId` i `remotely.apiKey`; varijable okoline `REMOTELY_API_KEY_ID` i `REMOTELY_API_KEY` imaju prednost).

## Krug 1: početna točka (`v2022.09.16.1006` + K1, .NET 6)

Stari agent (2021, IVICATEST) i stari desktop prolaze isti popis kao u krugu 2, bez stavki koje traže novi agent ili K3. Ako krug 1 ne prođe, odlučuje se o povratku na `master` (spec 4.2).

### Zašto su kriteriji usporedni s produkcijom

Dvije su činjenice iz starog koda (nisu uvedene našim izmjenama). Prvo, stari agent (2021) nakon izvršenja naredbe šalje rezultat na `/API/ScriptResults` (sprema se u bazu), ali zatim poziva hub metodu `ScriptResultViaApi(requestID)` s jednim argumentom, dok metoda na serveru prima dva (`commandID, requestID`). Server zato nikad ne sazna rezultat i `POST api/Scripting/ExecuteCommand` nakon čekanja od 30 s vraća 404 (`Server/API/ScriptingController.cs`); isto je i na produkciji. Rezultat se zato čita iz `GET api/ScriptResults`. Drugo, stari agent u vlastitom prosljeđivanju stdin/stdouta gubi `č`/`ć`/`đ` (izlaz `ccžšd CCŽŠÐ`), neovisno o serveru; server je pritom bez gubitka (`ScriptInput` je točno poslani tekst). Zato se provjerava paritet s produkcijom (isto ponašanje, isti izlaz za isti stroj i naredbu), a ne točan hrvatski izlaz.

### K1. Stari agent (2021) i stari desktop

| # | stavka | očekivano | rezultat | napomena |
|---|---|---|---|---|
| 1.1 | Online status i heartbeat | Stroj je online na stagingu, `LastOnline` se osvježava | OK | IVICATEST online na stagingu (agent 2021.10.10.1923), heartbeat radi. |
| 1.2 | `GET api/Devices/{id}` preko `Invoke-RemotelyApiCheck.ps1` | 200, `IsOnline` i `AgentVersion` zabilježeni, u oba formata zaglavlja | OK | 200 u oba formata zaglavlja, `IsOnline=True`, `AgentVersion=2021.10.10.1923`; produkcijsko `Basic` zaglavlje daje 500, staging 200 (odjeljak 2 u `staging-krug1.md`). |
| 1.3 | `ExecuteCommand/WinPS` s `Write-Output 'čćžšđ ČĆŽŠĐ'` | `ExecuteCommand` kao na produkciji (sa starim agentom 404 nakon ~30 s), rezultat se nalazi u `GET api/ScriptResults`; `ScriptInput` točno jednak poslanom tekstu; `StandardOutput` zabilježen i jednak produkcijskom za isti stroj i naredbu (usporedba kad se IVICATEST vrati na produkciju); u oba formata zaglavlja | OK (= produkcija) | 404 nakon 30,1 s kao na produkciji, rezultat u `ScriptResults`, `ScriptInput` točan, izlazi isti na stagingu i produkciji (odjeljak 2). |
| 1.4 | `ExecuteCommand/CMD` s `echo čćžšđ` | `ExecuteCommand` kao na produkciji (sa starim agentom 404 nakon ~30 s), rezultat se nalazi u `GET api/ScriptResults`; `ScriptInput` točno jednak poslanom tekstu; `StandardOutput` zabilježen i jednak produkcijskom za isti stroj i naredbu (usporedba kad se IVICATEST vrati na produkciju); u oba formata zaglavlja | OK (= produkcija) | 404 nakon 30 s kao na produkciji, rezultat u `ScriptResults`, `ScriptInput` točan, izlaz `ccžšd` isti na oba servera (odjeljak 2). |
| 1.5 | Varijante zaglavlja koje šalju stvarni klijenti: razmaci oko vrijednosti, `basic` malim slovima, tajna s `+`, `/`, `=`, tajna s dvotočkom | Sve se autorizira (200); neispravan base64, prazno zaglavlje i pogrešan ključ daju 401 | nije testirano | Ispitani su samo `raw` i `Basic` (200 na stagingu, `Basic` na produkciji 500); ostale varijante zaglavlja i 401 slučajevi nisu pokrenuti uživo, pokrivaju ih jedinični testovi (T3). |
| 1.6 | Remote control iz weba | Sesija se otvara, slika i unos rade | OK | Sesija iz weba otvara se, slika i unos rade (stari desktop kao servis). |
| 1.7 | Remote control iz testne Operative (`config.ini` s `BaseUrl` na staging) | Sesija se otvara, slika i unos rade | OK | Radi s `BaseUrl=https://remote-test.integrator.hr/api/` (završni `/api/` je obavezan, odjeljak 5). |
| 1.8 | "Integrator podrška" sa session ID-om preko `/RemoteControl` | Sesija se otvara na stagingu | nalaz | Glavni nalaz kruga: prekid sesije kod novog desktopa (R18) i Chromeovo throttling kartice (K6); stari desktop radi, vidi odjeljak 3. |
| 1.9 | Chat | Poruke teku u oba smjera | OK | Poruke teku u oba smjera, hrvatska slova ispravna. |
| 1.10 | Prijenos datoteka u oba smjera | Datoteke stižu neoštećene (usporedba SHA-256) | OK | Prijenos datoteka u oba smjera radi, uključujući datoteku od 50 MB. |
| 1.11 | Prijenos datoteke od 50 MB kroz remote control | Ponaša se kao na produkciji (uspjeh ili ista poruka o ograničenju) | OK | Datoteka od 50 MB (SHA-256 f72e406a...) prenesena kroz remote control. |
| 1.12 | Međuspremnik u oba smjera | Tekst se prenosi, uključujući hrvatska slova | OK | Međuspremnik radi u oba smjera. |
| 1.13 | Ctrl+Alt+Del | Secure attention sequence radi | OK | Ctrl+Alt+Del radi. |
| 1.14 | UAC prompt | Prompt je vidljiv i može se potvrditi u sesiji | OK | Nakon uključivanja UAC prompta na IVICATEST (prije je bio tihi, EnableLUA s ConsentPromptBehaviorAdmin=0) prompt je vidljiv i potvrđuje se. |
| 1.15 | Zaključani ekran | Sesija ostaje upotrebljiva, prijava iz sesije radi | OK | Zaključavanje kroz Ctrl+Alt+Del, Lock radi; Win+L zaključava korisnikov vlastiti PC (isto i u staroj verziji). |
| 1.16 | Više monitora (ako stroj ima više monitora) | Prebacivanje monitora radi | N/A | IVICATEST ima jedan monitor. |
| 1.17 | Hrvatska slova u izlazu skripte kroz stari agent (`čćžšđ ČĆŽŠĐ`) i u tipkanju kroz remote control | Izlaz skripte: kao u 1.3/1.4 (usporedba s produkcijom; stari agent gubi `č`/`ć`/`đ`, vidi objašnjenje ispod Kruga 1); tipkanje i međuspremnik kroz remote control: znakovi stižu na ekran nepromijenjeni | OK (= produkcija) | Slova `č`, `ć`, `Č`, `Ć` pri tipkanju stižu kao `c`/`C`, isto na produkciji (stari desktop); izlaz skripte isti kao na produkciji (odjeljci 2 i 4). |

### K1. Server (primjenjive provjere)

| # | stavka | očekivano | rezultat | napomena |
|---|---|---|---|---|
| 1.S1 | P4: `HEAD` na `Remotely-Win10-x64.zip` i `-x86.zip` | `ETag` jednak osnovici u `baseline-production.md` (`"1d7c3f840097221"`, `"1d7c3f84e574327"`) | OK | ETag x64 i x86 jednaki osnovici. |
| 1.S2 | Stari agent na stagingu ne pokreće ažuriranje | Agent ostaje na svojoj verziji (dobiva 304) | OK | Log agenta: "Service Updater: Version is current."; `etag.txt` nepromijenjen, agent ostaje 2021.10.10.1923. |
| 1.S3 | `__EFMigrationsHistory` prije i nakon starta | Isti popis i broj migracija kao u `baseline-production.md` | OK | 12 migracija, popis jednak osnovici. |
| 1.S4 | SHA-256 snimke sheme baze prije i nakon starta | Jednak osnovici u `baseline-production.md` | OK | 179 redaka, SHA-256 `bc7fa1b7...` jednak osnovici. |
| 1.S5 | Logovi servera | Bez grešaka | nalaz | Bez grešaka kod sesija, osim pada Blazor kruga u `DeviceCard.razor:234` (postojeća greška, odjeljak 4). |

## Krug 2: .NET 10 build s K1-K4 i Tokmak s K5

### K2. Stari agent (2021)

| # | stavka | očekivano | rezultat | napomena |
|---|---|---|---|---|
| 2.1 | Online status i heartbeat | Stroj je online na stagingu, `LastOnline` se osvježava | OK | IVICATEST online na net10 stagingu (~20 s nakon prebacivanja). |
| 2.2 | `GET api/Devices/{id}` preko `Invoke-RemotelyApiCheck.ps1` | 200, `IsOnline` i `AgentVersion` zabilježeni, u oba formata zaglavlja | OK | API provjera 8/8, oba formata zaglavlja. |
| 2.3 | `ExecuteCommand/WinPS` s `Write-Output 'čćžšđ ČĆŽŠĐ'` | `ExecuteCommand` kao na produkciji (sa starim agentom 404 nakon ~30 s), rezultat se nalazi u `GET api/ScriptResults`; `ScriptInput` točno jednak poslanom tekstu; `StandardOutput` zabilježen i jednak produkcijskom za isti stroj i naredbu (usporedba kad se IVICATEST vrati na produkciju); u oba formata zaglavlja | OK (= produkcija) | 404 nakon 30,1 s, rezultat u `ScriptResults`, izlazi jednaki krugu 1 (`staging-krug2.md`). |
| 2.4 | `ExecuteCommand/CMD` s `echo čćžšđ` | `ExecuteCommand` kao na produkciji (sa starim agentom 404 nakon ~30 s), rezultat se nalazi u `GET api/ScriptResults`; `ScriptInput` točno jednak poslanom tekstu; `StandardOutput` zabilježen i jednak produkcijskom za isti stroj i naredbu (usporedba kad se IVICATEST vrati na produkciju); u oba formata zaglavlja | OK (= produkcija) | Isto kao 2.3. |
| 2.5 | Varijante zaglavlja koje šalju stvarni klijenti: razmaci oko vrijednosti, `basic` malim slovima, tajna s `+`, `/`, `=`, tajna s dvotočkom | Sve se autorizira (200); neispravan base64, prazno zaglavlje i pogrešan ključ daju 401 | nije testirano | Uživo samo `raw` i `Basic`; ostalo pokrivaju jedinični testovi. |
| 2.6 | Remote control iz weba | Sesija se otvara, slika i unos rade | OK | Web RC a do g OK. |
| 2.7 | Remote control iz testne Operative (`config.ini` s `BaseUrl` na staging) | Sesija se otvara, slika i unos rade | OK | Operativa s `BaseUrl` na staging. |
| 2.8 | "Integrator podrška" sa session ID-om preko `/RemoteControl` | Sesija se otvara na stagingu | nije testirano | Nema zapisa rezultata za krug 2; vidi N1 u `staging-krug2.md`. |
| 2.9 | Chat | Poruke teku u oba smjera | OK |  |
| 2.10 | Prijenos datoteka u oba smjera | Datoteke stižu neoštećene (usporedba SHA-256) | OK | Datoteka 50 MB, SHA-256 identičan; ostali smjerovi nisu zasebno zabilježeni. |
| 2.11 | Prijenos datoteke od 50 MB kroz remote control | Ponaša se kao na produkciji (uspjeh ili ista poruka o ograničenju) | OK | 50 MB, SHA-256 identičan. |
| 2.12 | Međuspremnik u oba smjera | Tekst se prenosi, uključujući hrvatska slova | nije testirano | Nije zasebno zabilježeno. |
| 2.13 | Ctrl+Alt+Del | Secure attention sequence radi | nije testirano | Nije zasebno zabilježeno. |
| 2.14 | UAC prompt | Prompt je vidljiv i može se potvrditi u sesiji | nije testirano | Nije zasebno zabilježeno. |
| 2.15 | Zaključani ekran | Sesija ostaje upotrebljiva, prijava iz sesije radi | nije testirano | Nije zasebno zabilježeno. |
| 2.16 | Više monitora (ako stroj ima više monitora) | Prebacivanje monitora radi | N/A | IVICATEST ima jedan monitor (krug 1). |
| 2.17 | Hrvatska slova u izlazu skripte kroz stari agent (`čćžšđ ČĆŽŠĐ`) i u tipkanju kroz remote control | Izlaz skripte: kao u 2.3/2.4 (usporedba s produkcijom; stari agent gubi `č`/`ć`/`đ`, vidi objašnjenje ispod Kruga 1); tipkanje i međuspremnik kroz remote control: znakovi stižu na ekran nepromijenjeni | OK (= produkcija) | Gubitak `č`/`ć` pri tipkanju kroz stari desktop isti kao na produkciji; izlaz skripte kao u 2.3/2.4. |
| 2.18 | Hrvatske putanje u prijenosu datoteka (naziv datoteke sa `čćžšđ`) | Datoteka se prenosi s ispravnim nazivom | nije testirano |  |

### K2. Novi agent, instaliran testnom verzijom Tokmaka s K5

Naredba: `Tokmak4 Remotely -i <GUID stroja iz CEZAR-a> -a "<parametri>"`, s `-serverurl https://remote-test.integrator.hr`.

| # | stavka | očekivano | rezultat | napomena |
|---|---|---|---|---|
| 3.1 | Isti popis kao za stari agent (sve stavke iz tablice 2.) | Sve stavke prolaze | nije testirano | Provjereno samo: online, izvršavanje naredbi, `ExecuteCommand` 404 nakon 30 s (rezultati preko `ScriptResults`). |
| 3.2 | Hrvatska slova u izlazu skripte kroz novi agent (WinPS i CMD) | Cilj: točan izlaz `čćžšđ ČĆŽŠĐ` i `čćžšđ`. Najmanje onako dobro kao stari agent (kriteriji kao 2.3/2.4: rezultat u `ScriptResults`, `ScriptInput` točan, izlaz zabilježen i uspoređen s produkcijom); odstupanje od točnog izlaza evidentira se kao nalaz | nije testirano |  |
| 3.3 | Nakon instalacije novi agent ostaje na svojoj verziji | Provjera ažuriranja dobiva 304 | OK | Nakon restarta servisa "Version is current". |
| 3.4 | Poziv `/token` na stagingu (ručno) | Radi i koristi `Remotely_Test` | OK | 200 na stagingu (token nije ispisan). |
| 3.5 | Tokmak odbija paket s pogrešnim SHA-256 | Ne instalira se | OK | Log: "ima neispravan SHA-256; instalacija se ne pokreće." Provjera se preskače ako je agent već instaliran. |
| 3.6 | Putanja paketa s razmakom i hrvatskim slovima u `-path` (npr. `%TEMP%` korisnika `Ivančić`) | Installer dobiva cijelu putanju i instalira | OK | `TEMP=C:\Temp\Test čćž`, instalacija uspjela (agent 2026.10.28.1113). |

### K2. Ažuriranje i povratak

| # | stavka | očekivano | rezultat | napomena |
|---|---|---|---|---|
| 4.1 | Stari agent prelazi na novi preko installera | Stroj je online na novoj verziji | nije testirano | Instalacija novog agenta provedena je nakon deinstalacije starog, ne nadogradnjom preko installera. |
| 4.2 | Installer s namjerno neispravnim paketom (`-path`) | Stroj ostaje online na prethodnoj verziji | OK | Pokvaren zip: "Restoring backup.", online na prethodnoj verziji za manje od 5 min; installer vraća exit 0. |

### K2. Server

| # | stavka | očekivano | rezultat | napomena |
|---|---|---|---|---|
| 5.1 | P4: `HEAD` na `Remotely-Win10-x64.zip` i `-x86.zip` | `ETag` jednak osnovici u `baseline-production.md` (`"1d7c3f840097221"`, `"1d7c3f84e574327"`) | OK | ETag x64 i x86 jednaki osnovici. |
| 5.2 | Stari agent na stagingu ne pokreće ažuriranje | Agent ostaje na svojoj verziji (dobiva 304) | OK | Stari agent na stagingu ne pokreće ažuriranje (osnovica kruga 1); u krugu 2 posebna provjera nije zabilježena. |
| 5.3 | `__EFMigrationsHistory` prije i nakon starta | Isti popis i broj migracija kao u `baseline-production.md` | OK | 12 migracija, zadnja `20210417155829_Add Alert Details`. |
| 5.4 | SHA-256 snimke sheme baze prije i nakon starta | Jednak osnovici u `baseline-production.md` | OK | SHA-256 `bc7fa1b7...` = osnovica. |
| 5.5 | Logovi servera | Bez grešaka | nalaz | Jedan zahtjev u 11:35:11 (`GET /api/Devices`, Infinity): 2 greške, 1 upozorenje; postojeće. |
| 5.6 | Masovno ponovno spajanje nakon prebacivanja (~660 agenata unutar 30 s; LoadTester s 1000 agenata) | Server ostaje responzivan, bez grešaka u logu, agenti se spajaju | OK | LoadTester 1000/1000, 0 grešaka, API provjera pod opterećenjem 8/8; ~660 agenata u 30 s nije zasebno mjereno. |
| 5.7 | Vježba povratka zamjenom fizičke putanje | Povratak traje manje od minute, bez restorea baze | OK | Povratak 4 s, natrag 4 s, agent ~20 s, bez restorea baze. |

### K2. Mobilni viewer (K3)

| # | stavka | očekivano | rezultat | napomena |
|---|---|---|---|---|
| 6.1 | Long-press za desni klik | Desni klik na ciljanoj točki | OK | Mobitel a do d, f OK (Android 16, Chromium). |
| 6.2 | Long-press s povlačenjem | Klik-i-povuci radi | OK | Vidi 6.1. |
| 6.3 | Scroll s dva prsta | Radi (već u početnoj točki) | OK | Vidi 6.1. |
| 6.4 | Virtualna tipkovnica kao preklopni gumb; Enter, Backspace i lijepljenje teksta | Unos radi | OK | Prvo FAIL (svako drugo slovo, R33), nakon ispravka na net10c OK. |
| 6.5 | Dozvola za čitanje međuspremnika u Firefoxu i Safariju | Obrađuje se bez greške | nije testirano | Nema Firefoxa na mobitelu. |
| 6.6 | Viewer sa starim desktop klijentom (2021) | Radi; šalju se samo poruke koje stari klijent poznaje | nije testirano | Nije zasebno zabilježeno. |

