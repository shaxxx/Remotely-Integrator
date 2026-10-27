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
| 1.1 | Online status i heartbeat | Stroj je online na stagingu, `LastOnline` se osvježava | | |
| 1.2 | `GET api/Devices/{id}` preko `Invoke-RemotelyApiCheck.ps1` | 200, `IsOnline` i `AgentVersion` zabilježeni, u oba formata zaglavlja | | |
| 1.3 | `ExecuteCommand/WinPS` s `Write-Output 'čćžšđ ČĆŽŠĐ'` | `ExecuteCommand` kao na produkciji (sa starim agentom 404 nakon ~30 s), rezultat se nalazi u `GET api/ScriptResults`; `ScriptInput` točno jednak poslanom tekstu; `StandardOutput` zabilježen i jednak produkcijskom za isti stroj i naredbu (usporedba kad se IVICATEST vrati na produkciju); u oba formata zaglavlja | | |
| 1.4 | `ExecuteCommand/CMD` s `echo čćžšđ` | `ExecuteCommand` kao na produkciji (sa starim agentom 404 nakon ~30 s), rezultat se nalazi u `GET api/ScriptResults`; `ScriptInput` točno jednak poslanom tekstu; `StandardOutput` zabilježen i jednak produkcijskom za isti stroj i naredbu (usporedba kad se IVICATEST vrati na produkciju); u oba formata zaglavlja | | |
| 1.5 | Varijante zaglavlja koje šalju stvarni klijenti: razmaci oko vrijednosti, `basic` malim slovima, tajna s `+`, `/`, `=`, tajna s dvotočkom | Sve se autorizira (200); neispravan base64, prazno zaglavlje i pogrešan ključ daju 401 | | |
| 1.6 | Remote control iz weba | Sesija se otvara, slika i unos rade | | |
| 1.7 | Remote control iz testne Operative (`config.ini` s `BaseUrl` na staging) | Sesija se otvara, slika i unos rade | | |
| 1.8 | "Integrator podrška" sa session ID-om preko `/RemoteControl` | Sesija se otvara na stagingu | | |
| 1.9 | Chat | Poruke teku u oba smjera | | |
| 1.10 | Prijenos datoteka u oba smjera | Datoteke stižu neoštećene (usporedba SHA-256) | | |
| 1.11 | Prijenos datoteke od 50 MB kroz remote control | Ponaša se kao na produkciji (uspjeh ili ista poruka o ograničenju) | | |
| 1.12 | Međuspremnik u oba smjera | Tekst se prenosi, uključujući hrvatska slova | | |
| 1.13 | Ctrl+Alt+Del | Secure attention sequence radi | | |
| 1.14 | UAC prompt | Prompt je vidljiv i može se potvrditi u sesiji | | |
| 1.15 | Zaključani ekran | Sesija ostaje upotrebljiva, prijava iz sesije radi | | |
| 1.16 | Više monitora (ako stroj ima više monitora) | Prebacivanje monitora radi | | |
| 1.17 | Hrvatska slova u izlazu skripte kroz stari agent (`čćžšđ ČĆŽŠĐ`) i u tipkanju kroz remote control | Izlaz skripte: kao u 1.3/1.4 (usporedba s produkcijom; stari agent gubi `č`/`ć`/`đ`, vidi objašnjenje ispod Kruga 1); tipkanje i međuspremnik kroz remote control: znakovi stižu na ekran nepromijenjeni | | |

### K1. Server (primjenjive provjere)

| # | stavka | očekivano | rezultat | napomena |
|---|---|---|---|---|
| 1.S1 | P4: `HEAD` na `Remotely-Win10-x64.zip` i `-x86.zip` | `ETag` jednak osnovici u `baseline-production.md` (`"1d7c3f840097221"`, `"1d7c3f84e574327"`) | | |
| 1.S2 | Stari agent na stagingu ne pokreće ažuriranje | Agent ostaje na svojoj verziji (dobiva 304) | | |
| 1.S3 | `__EFMigrationsHistory` prije i nakon starta | Isti popis i broj migracija kao u `baseline-production.md` | | |
| 1.S4 | SHA-256 snimke sheme baze prije i nakon starta | Jednak osnovici u `baseline-production.md` | | |
| 1.S5 | Logovi servera | Bez grešaka | | |

## Krug 2: .NET 10 build s K1-K4 i Tokmak s K5

### K2. Stari agent (2021)

| # | stavka | očekivano | rezultat | napomena |
|---|---|---|---|---|
| 2.1 | Online status i heartbeat | Stroj je online na stagingu, `LastOnline` se osvježava | | |
| 2.2 | `GET api/Devices/{id}` preko `Invoke-RemotelyApiCheck.ps1` | 200, `IsOnline` i `AgentVersion` zabilježeni, u oba formata zaglavlja | | |
| 2.3 | `ExecuteCommand/WinPS` s `Write-Output 'čćžšđ ČĆŽŠĐ'` | `ExecuteCommand` kao na produkciji (sa starim agentom 404 nakon ~30 s), rezultat se nalazi u `GET api/ScriptResults`; `ScriptInput` točno jednak poslanom tekstu; `StandardOutput` zabilježen i jednak produkcijskom za isti stroj i naredbu (usporedba kad se IVICATEST vrati na produkciju); u oba formata zaglavlja | | |
| 2.4 | `ExecuteCommand/CMD` s `echo čćžšđ` | `ExecuteCommand` kao na produkciji (sa starim agentom 404 nakon ~30 s), rezultat se nalazi u `GET api/ScriptResults`; `ScriptInput` točno jednak poslanom tekstu; `StandardOutput` zabilježen i jednak produkcijskom za isti stroj i naredbu (usporedba kad se IVICATEST vrati na produkciju); u oba formata zaglavlja | | |
| 2.5 | Varijante zaglavlja koje šalju stvarni klijenti: razmaci oko vrijednosti, `basic` malim slovima, tajna s `+`, `/`, `=`, tajna s dvotočkom | Sve se autorizira (200); neispravan base64, prazno zaglavlje i pogrešan ključ daju 401 | | |
| 2.6 | Remote control iz weba | Sesija se otvara, slika i unos rade | | |
| 2.7 | Remote control iz testne Operative (`config.ini` s `BaseUrl` na staging) | Sesija se otvara, slika i unos rade | | |
| 2.8 | "Integrator podrška" sa session ID-om preko `/RemoteControl` | Sesija se otvara na stagingu | | |
| 2.9 | Chat | Poruke teku u oba smjera | | |
| 2.10 | Prijenos datoteka u oba smjera | Datoteke stižu neoštećene (usporedba SHA-256) | | |
| 2.11 | Prijenos datoteke od 50 MB kroz remote control | Ponaša se kao na produkciji (uspjeh ili ista poruka o ograničenju) | | |
| 2.12 | Međuspremnik u oba smjera | Tekst se prenosi, uključujući hrvatska slova | | |
| 2.13 | Ctrl+Alt+Del | Secure attention sequence radi | | |
| 2.14 | UAC prompt | Prompt je vidljiv i može se potvrditi u sesiji | | |
| 2.15 | Zaključani ekran | Sesija ostaje upotrebljiva, prijava iz sesije radi | | |
| 2.16 | Više monitora (ako stroj ima više monitora) | Prebacivanje monitora radi | | |
| 2.17 | Hrvatska slova u izlazu skripte kroz stari agent (`čćžšđ ČĆŽŠĐ`) i u tipkanju kroz remote control | Izlaz skripte: kao u 2.3/2.4 (usporedba s produkcijom; stari agent gubi `č`/`ć`/`đ`, vidi objašnjenje ispod Kruga 1); tipkanje i međuspremnik kroz remote control: znakovi stižu na ekran nepromijenjeni | | |
| 2.18 | Hrvatske putanje u prijenosu datoteka (naziv datoteke sa `čćžšđ`) | Datoteka se prenosi s ispravnim nazivom | | |

### K2. Novi agent, instaliran testnom verzijom Tokmaka s K5

Naredba: `Tokmak4 Remotely -i <GUID stroja iz CEZAR-a> -a "<parametri>"`, s `-serverurl https://remote-test.integrator.hr`.

| # | stavka | očekivano | rezultat | napomena |
|---|---|---|---|---|
| 3.1 | Isti popis kao za stari agent (sve stavke iz tablice 2.) | Sve stavke prolaze | | |
| 3.2 | Hrvatska slova u izlazu skripte kroz novi agent (WinPS i CMD) | Cilj: točan izlaz `čćžšđ ČĆŽŠĐ` i `čćžšđ`. Najmanje onako dobro kao stari agent (kriteriji kao 2.3/2.4: rezultat u `ScriptResults`, `ScriptInput` točan, izlaz zabilježen i uspoređen s produkcijom); odstupanje od točnog izlaza evidentira se kao nalaz | | |
| 3.3 | Nakon instalacije novi agent ostaje na svojoj verziji | Provjera ažuriranja dobiva 304 | | |
| 3.4 | Poziv `/token` na stagingu (ručno) | Radi i koristi `Remotely_Test` | | |
| 3.5 | Tokmak odbija paket s pogrešnim SHA-256 | Ne instalira se | | |
| 3.6 | Putanja paketa s razmakom i hrvatskim slovima u `-path` (npr. `%TEMP%` korisnika `Ivančić`) | Installer dobiva cijelu putanju i instalira | | |

### K2. Ažuriranje i povratak

| # | stavka | očekivano | rezultat | napomena |
|---|---|---|---|---|
| 4.1 | Stari agent prelazi na novi preko installera | Stroj je online na novoj verziji | | |
| 4.2 | Installer s namjerno neispravnim paketom (`-path`) | Stroj ostaje online na prethodnoj verziji | | |

### K2. Server

| # | stavka | očekivano | rezultat | napomena |
|---|---|---|---|---|
| 5.1 | P4: `HEAD` na `Remotely-Win10-x64.zip` i `-x86.zip` | `ETag` jednak osnovici u `baseline-production.md` (`"1d7c3f840097221"`, `"1d7c3f84e574327"`) | | |
| 5.2 | Stari agent na stagingu ne pokreće ažuriranje | Agent ostaje na svojoj verziji (dobiva 304) | | |
| 5.3 | `__EFMigrationsHistory` prije i nakon starta | Isti popis i broj migracija kao u `baseline-production.md` | | |
| 5.4 | SHA-256 snimke sheme baze prije i nakon starta | Jednak osnovici u `baseline-production.md` | | |
| 5.5 | Logovi servera | Bez grešaka | | |
| 5.6 | Masovno ponovno spajanje nakon prebacivanja (~660 agenata unutar 30 s; LoadTester s 1000 agenata) | Server ostaje responzivan, bez grešaka u logu, agenti se spajaju | | |
| 5.7 | Vježba povratka zamjenom fizičke putanje | Povratak traje manje od minute, bez restorea baze | | |

### K2. Mobilni viewer (K3)

| # | stavka | očekivano | rezultat | napomena |
|---|---|---|---|---|
| 6.1 | Long-press za desni klik | Desni klik na ciljanoj točki | | |
| 6.2 | Long-press s povlačenjem | Klik-i-povuci radi | | |
| 6.3 | Scroll s dva prsta | Radi (već u početnoj točki) | | |
| 6.4 | Virtualna tipkovnica kao preklopni gumb; Enter, Backspace i lijepljenje teksta | Unos radi | | |
| 6.5 | Dozvola za čitanje međuspremnika u Firefoxu i Safariju | Obrađuje se bez greške | | |
| 6.6 | Viewer sa starim desktop klijentom (2021) | Radi; šalju se samo poruke koje stari klijent poznaje | | |

