# Staging, krug 1: početna točka v2022.09.16.1006 + K1

## 1. Uvod

Krug 1 testira početnu točku seobe servera remote.integrator.hr (Remotely) s .NET 5 na .NET 10: upstream `v2022.09.16.1006` s našom izmjenom K1 (.NET 6), uz stare klijente (agent i desktop 2021). Cilj je provjeriti da je ponašanje prema starim klijentima barem jednako produkcijskom (spec 2.1) prije nastavka na krug 2.

- Datum testa: 2026-10-27 i 2026-10-28.
- Okruženje: staging site `remote-test.integrator.hr` (pool `Remotely-Test`, `C:\sites\remotely-test`), baza `Remotely_Test`.
- Testni stroj: IVICATEST (`EDFEA380-9C87-4807-BA7F-6D244E06A2D4`), agent `2021.10.10.1923`, stari desktop 2021 (`2021.10.10.1923`); za pokuse s novim desktopom korišten je desktop v2022 (staging build) i dijagnostičke inačice.
- Odluka korisnika: 2026-10-28 početna točka (`v2022.09.16` + K1) je potvrđena kao osnovica za dalji rad.
- Osnovica produkcije je u `baseline-production.md`; detaljne stavke su u `checklist-staging.md`.

### Rezultati po stavkama

| # | stavka | rezultat | napomena |
|---|---|---|---|
| 1.1 | Online status i heartbeat | OK | IVICATEST online na stagingu |
| 1.2 | `GET api/Devices/{id}` | OK | 200 u oba formata zaglavlja |
| 1.3 | `ExecuteCommand/WinPS` | OK (= produkcija) | 404 nakon 30 s kao na produkciji, odjeljak 2 |
| 1.4 | `ExecuteCommand/CMD` | OK (= produkcija) | isto, odjeljak 2 |
| 1.5 | Varijante zaglavlja | nije testirano | uživo samo `raw` i `Basic`; ostalo pokrivaju jedinični testovi (T3) |
| 1.6 | Remote control iz weba | OK | |
| 1.7 | Remote control iz testne Operative | OK | s `BaseUrl` koji završava na `/api/` |
| 1.8 | "Integrator podrška" preko session ID-a | nalaz | odjeljak 3 |
| 1.9 | Chat | OK | |
| 1.10 | Prijenos datoteka | OK | |
| 1.11 | Datoteka od 50 MB | OK | |
| 1.12 | Međuspremnik | OK | |
| 1.13 | Ctrl+Alt+Del | OK | |
| 1.14 | UAC prompt | OK | nakon uključivanja prompta na IVICATEST |
| 1.15 | Zaključani ekran | OK | kroz Ctrl+Alt+Del, Lock |
| 1.16 | Više monitora | N/A | jedan monitor |
| 1.17 | Hrvatska slova | OK (= produkcija) | gubitak `č`/`ć` isti na produkciji, odjeljak 4 |
| 1.S1 | ETag paketa | OK | jednak osnovici |
| 1.S2 | Agent ne pokreće ažuriranje | OK | "Version is current" |
| 1.S3 | Migracije | OK | 12, jednake osnovici |
| 1.S4 | SHA-256 sheme | OK | 179 redaka, `bc7fa1b7...` |
| 1.S5 | Logovi servera | nalaz | Blazor NRE, odjeljak 4 |

## 2. Paritet API-ja s produkcijom (1.3 do 1.5)

Kriteriji su usporedni s produkcijom jer su dvije činjenice u starom kodu, neovisne o našim izmjenama:

- Stari agent (2021) nakon izvršenja naredbe šalje rezultat na `/API/ScriptResults`, ali hub metodu `ScriptResultViaApi` zove s jednim argumentom (`requestID`), a server je definira s dva (`commandID, requestID`). Poziv ne uspije, server nikad ne sazna rezultat i `POST api/Scripting/ExecuteCommand` nakon čekanja od 30 s vraća 404. Isto je na produkciji (provjereno, 62 s za dva poziva). Rezultat se zato čita iz `GET api/ScriptResults`, kao što to radi skill.
- Stari agent prosljeđuje stdin/stdout preko CP1252 i gubi `č`/`ć`/`đ`; to ne ovisi o serveru.

Rezultati (skripta `Invoke-RemotelyApiCheck.ps1`, IVICATEST, na stagingu 8 od 8 provjera prošlo):

- ExecuteCommand: na stagingu 404 nakon 30,1 s, na produkciji 404 nakon 30 s. Rezultat je pronađen u `ScriptResults` već pri prvom upitu.
- `ScriptInput` je točno jednak poslanom tekstu (kodne točke `U+010D U+0107 U+017E U+0161 U+0111` / `U+010C U+0106 U+017D U+0160 U+0110`), server ne gubi znakove.
- Izlazi su isti na stagingu i produkciji za isti stroj: `raw WinPS` daje `ccžšd CCŽŠÐ`, `raw CMD` daje `ccžšd`, `base64 WinPS` (kako šalje skill) daje `cczsd CCZSD`. Trajni shell starog agenta može ispred izlaza dodati zaostali redak iz prethodne naredbe (viđen GUID).
- GUID stroja: usporedba u `ServiceConnections` razlikuje velika i mala slova (velika rade, mala odmah daju 404), isto kao u 2021.
- Zaglavlje `Basic`: na produkciji daje 500 (server 2021 ga ne zna parsirati), na stagingu (K1) 200.
- Izlazi su spremljeni u `krug1-apicheck.out` (staging) i `krug1-apicheck-prod-ivicatest.out` (produkcija) u radnoj mapi `.superpowers/sdd`.
- Stavka 1.5: uživo su provjerena samo zaglavlja `raw` i `Basic`. Razmaci oko vrijednosti, `basic` malim slovima, posebni znakovi u tajni i 401 slučajevi nisu pokrenuti uživo, pokrivaju ih jedinični testovi (T3).

## 3. Prekid sesije kod povezivanja preko session ID-a (1.8)

Ovo je glavni nalaz kruga 1. Povezivanje preko session ID-a ("Integrator podrška") sa starim desktopom 2021 na stagingu radi. Sa novim desktopom (v2022), a kasnije i u dužim sesijama sa starim, pojavilo se "Viewer stalled" nakon 15 s, nakon čega slika i unos prestaju. Uzroci su dva, nezavisna.

### a) Novi desktop (v2022): ista Sequence 0 za početnu sliku i prvu sliku petlje

- U refaktoru v2022 `ScreenCaster.BeginScreenCastingImpl` šalje početnu sliku sa `Sequence=0` (zadana vrijednost; 2021 je koristio `sequence++`), a zatim pokreće `CastScreen(..., 0)`, pa i prva slika petlje ima `Sequence=0`.
- Viewer (`CaptureProcessor.processQueue`) `Sequence==0` tumači kao ponovno pokretanje: `NextSequence=0` i `BitmapQueue.splice(0)` briše red. Ako je slika 1 već u redu kad se iscrta duplikat 0, slika 1 se izbaci i nikad ne bude potvrđena, a pri statičnom ekranu nema novih slika. Nakon 15 s desktop javlja `IsStalled`, petlja slanja završava i viewer se uklanja.
- Dokaz: DIAG log, 9 sesija, 4 zastoja, 5 uspješnih (primjer: 2 poslane slike, 1 potvrda). Pojavljuje se isprekidano.
- Ispravak: commit `6b76aeff` (pravilo R18), početna slika uzima `sequence++` i petlja nastavlja od te vrijednosti (semantika 2021). Stari klijenti nisu pogođeni.

### b) Neovisno o verziji: Chrome throttling skrivene kartice

- Chrome u kartici skrivenoj dulje od oko 5 minuta pušta lančane tajmere jednom u minuti (intensive wake-up throttling). Viewer je napredovao kroz `setTimeout(processQueue, 1)`, pa su potvrde slika kasnile do 60 s i desktop je nakon 15 s prekidao sesiju (slika i unos). Primanje preko WebSocketa se ne throttlea, slike su dolazile dalje.
- Dokaz na PRODUKCIJI sa starim klijentom 2021 (bez ikakvog koda v2022): razmak kontrolnog zapisa (heartbeat) skočio je s 2 s na 60 s u 08:07:18 UTC, slika 143 primljena u 08:07:17,9 UTC potvrđena je tek +60 s, slike 144 i 145 potvrđene +50 s i +99 s, a "Viewer stalled" u desktop logu je u 09:07:36 po lokalnom vremenu.
- Dakle problem postoji i na produkciji i nije posljedica seobe. Pojavljuje se kad je kartica viewera skrivena dulje vrijeme (npr. rad u Proxmox konzoli u drugoj kartici).
- Ispravak K6 (commiti `df1f5ea7` i `6be9a5b8`): obrada slika bez tajmera, nastavak bez `setTimeout`.
- Provjera na stagingu sa starim klijentom 2021, viewer build `df1f5ea7`: Chromeov intensive throttling uključio se u 08:29:17 UTC (razmak heartbeata 13 s, zatim oko 60 s) dok je kartica bila skrivena. Kroz cijelu sesiju 4007 slika i 4007 potvrda, najveće kašnjenje potvrde 10 ms; sesija živa kroz oko 13 minuta throttlinga, uključujući oko 4 minute gotovo statičnog ekrana (SignalR ostao Connected). Na produkciji sa starim viewerom isti uvjeti dali su kašnjenje potvrda 60 do 99 s i "Viewer stalled" unutar 15 s.
- Završni commit `6be9a5b8` (potvrda zastarjele slike i odbacivanje, oslobađanje bitmapa), ista provjera sa starim klijentom 2021: throttling se uključio u 08:49:17 UTC (razmak heartbeata 34 s, zatim 60 s); tijekom throttlinga 2678 slika, najveće kašnjenje potvrde 5 ms; ukupno 3162 slike i 3162 potvrde, bez grešaka u konzoli i bez promjene vidljivosti kartice. Desktop log: sesija 09:47:46–09:58:35, "Viewer Stalled: False" (završila odspajanjem).
- Na stagingu su datoteke viewera (`CaptureProcessor.js` i `.js.map`) zamijenjene izravno, uz kopije `*.pre-k6`; ostatak staging builda je K1. Sljedeći puni build iz grane `integrator` sadrži K6.

### c) Opažanja koja nisu uzrok

- "Failed to switch to input desktop (170)" u logu desktopa pojavljuje se u naletima i kod sesija koje se ne zaustave; nije uzrok zastoja.
- UIPI: Task Manager pokrenut s administratorskim pravima (integrity level High) blokira unos iz klijenta bez tih prava (Medium). Dok je Task Manager u fokusu, unos ne dolazi; to je ponašanje Windowsa i vrijedi i za 2021.

## 4. Postojeći nalazi (nisu uzrokovani seobom)

- Gumb Copy za session ID u desktopu ne radi (ni u starom klijentu 2021).
- Blazor NRE u `DeviceCard.razor:234`: `DataService.GetDeviceGroups(Username)` vrati `null`, pa `foreach` padne i Blazor krug se sruši kad stroj postane online dok je njegova kartica otvorena (viđeno 12:10:08). Do osvježavanja stranice izgleda da stroj nije online. `DeviceCard.razor` je isti od 2021 do 2022, upstream greška, neblokirajuća.
- Gubitak `č`/`ć`/`Č`/`Ć` pri tipkanju kroz stari desktop (stižu kao `c`/`C`; `ž š đ` prolaze). Isto na produkciji (potvrdio korisnik). Kod za tipke u vieweru je isti u 2021 i 2022.
- `ExecuteCommand` sa starim agentom vraća 404 nakon 30 s (odjeljak 2), isto na produkciji.

## 5. Napomene za Operativu i krug 2

- `BaseUrl` u `config.ini` Operative mora završavati s `/api/` (npr. `https://remote-test.integrator.hr/api/`). Bez toga Operativa zove `Devices/{id}` relativno na korijen, dobije HTML, ne uspije deserijalizirati i prikaže stroj kao offline.
- Gumb "Remotely" u Operativi je tvrdo vezan na produkciju (`mdi.vb:1834`, `https://remote.integrator.hr/RemoteControl`) i ne može se usmjeriti na staging; pokriva ga test 1.8 na stagingu.
- Stari attended desktop 2021 ima ugrađen produkcijski host, a `Config.json` se čita samo ako je ugrađeni host prazan, pa ga se ne može usmjeriti na staging. Za staging je napravljen build desktopa 2021 s ugrađenim staging hostom.
- Agent se na stagingu ne ažurira ("Version is current", `etag.txt` nepromijenjen).

## 6. Otvoreno za krug 2

- Stavka 2.8 s novim desktopom (R18 + K6): ponoviti povezivanje preko session ID-a, uključujući dulje sesije sa skrivenom karticom i statičan ekran.
- Stavka 1.5: ostale varijante zaglavlja uživo (ako se ne smatraju pokrivenima jediničnim testovima).
- Ostale stavke iz `checklist-staging.md` (krug 2).
