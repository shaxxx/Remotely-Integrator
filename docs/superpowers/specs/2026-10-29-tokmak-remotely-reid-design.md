# Tokmak: usklađivanje Remotely ID-a s MachineGuidId-om

- **Datum:** 2026-10-29
- **Status:** dizajn odobren u razgovoru, spec čeka pregled
- **Repozitorij koda:** Tokmak (TFVC, `C:\zeba\Tokmak\Tokmak`); check-in radi korisnik
- **Odnos prema specifikaciji prelaska na .NET 10:** zamjenjuje dio o Tokmaku iz
  [2026-10-26-remotely-net10-design.md](2026-10-26-remotely-net10-design.md) (2.2, 6.2). Od "dvostrukog" agenta se
  odustalo (odluka korisnika 2026-10-29). Server od 09:50 isti dan nudi agent 2026.10.29.0943 i postojećim i novim
  strojevima, a Tokmakove izmjene za pakete u `tokmak/exe` i `-path` su poništene.

## 1. Cilj

Operativa (Machines) nudi "Connect Remotely" samo ako `GET api/Devices/{MachineGuidId}` pronađe uređaj. Za to
Remotely ID uređaja (`DeviceID` u `ConnectionInfo.json`) mora biti jednak MachineGuidId-u koji vraća Integrator
podrška. Kad Tokmak naiđe na instaliran agent s drugim ID-om, treba ga uskladiti.

## 2. Kontekst

- **Slučaj NAPOLEON:** Windowsi su reinstalirani, a agent je ostao s ID-om iz ranije instalacije (4B9ECE6E…).
  Podrška vraća DC5395D1…, pa ga Operativa nije vidjela. Tokmak instalaciju preskače čim servis postoji
  (`Integrator.MachineSetup.Remotely.Install`), pa se razlika nikad nije ispravila. NAPOLEON je ručno usklađen
  2026-10-29 (`docs/integrator/produkcija.md`, odjeljak 8).
- **Instaler to već zna:** `Remotely_Install-[523e].exe` (isti kao `Content/Remotely_Installer.exe`, 1.0.0.0, SHA
  8CF50766…), pokrenut preko postojeće instalacije s `-deviceuuid`, napravi sljedeće
  (`Agent.Installer.Win/Services/InstallerService.cs`):
  - upiše novi `DeviceID` i obriše token;
  - preuzme agent sa servera (`/Content/Remotely-Win10-{x64|x86}.zip`);
  - anonimnim `POST /api/devices` stvori zapis s grupom i aliasom (ako zapis već postoji, server vrati 400, a
    instaler to zanemari);
  - ako ne uspije, vrati backup.
- **Tko zove `Remotely.Install`:**
  - `Program.RunStartConfiguration`: Halo (pokreće ga Start kad klijent traži podršku), interaktivni Tokmak i Tokmak
    s datotekom postavki. MachineGuidId čita iz podrške preko pipea `integrator`.
  - `RemotelyCommand`: `Tokmak Remotely -i <GUID>`.

  Oba mjesta GUID danas samo dopisuju u niz argumenata (`-devicealias "GUID" -deviceuuid "GUID"`).

## 3. Kriteriji uspjeha

1. Halo na stroju s instaliranim agentom i krivim ID-om ostavi agent pod MachineGuidId-om, u grupi Operativa i
   online. Operativa ga vidi.
2. Halo na stroju s ispravnim ID-om ne instalira ništa (ponašanje kao danas).
3. Svježa instalacija radi kao danas.
4. Neuspjeh usklađivanja nikad ne ostavlja stroj bez agenta. Ostaje stari agent sa starim ID-om, a sljedeći Halo
   pokušava ponovo.
5. Nema izmjena na serveru, agentu, instaleru ni Operativi.

## 4. Dizajn

### 4.1 `RemotelyOptions.DeviceId`

Novo svojstvo `string DeviceId` je očekivani Remotely ID, tj. MachineGuidId. Po defaultu je prazno. Ne šalje se
instaleru i nigdje se ne sprema. Služi samo provjeri u `Remotely.Install`. Obrazac je isti kao `RustDeskOptions.Id`,
koji se puni iz istog MachineGuidId-a na istom mjestu.

`RemotelyOptions` je dio `StartConfiguration`, koji se može učitati iz JSON datoteke postavki. Vrijednost iz datoteke
nema učinka, jer je pozivatelj uvijek prepiše prije `Install`.

### 4.2 Tko ga puni

| Pozivatelj | Izvor | Trenutak |
|---|---|---|
| `Program.RunStartConfiguration` (`Tokmak\Program.cs`, oko retka 921) | `id` iz `support.ReadMachineGuidId(30)` | Unutar `if (support.Start())` i `if (!string.IsNullOrEmpty(id))`, u istom retku u kojem se dopisuju `-devicealias/-deviceuuid`, prije `remotely.Install` |
| `RemotelyCommand.Run` (`Tokmak\Commands\RemotelyCommand.cs`) | Opcija `-i` (obavezna, prošla regex, velikim slovima) | Uz postojeće dopisivanje argumenata, prije `remotely.Install` |

Dopisivanje `-devicealias/-deviceuuid` ostaje kakvo je.

### 4.3 `Remotely.Install`

Grane:

1. Servis ne postoji: `RegularInstall(options)`, kao danas.
2. Servis postoji, a provjera ID-a (4.4) vrati `Mismatch`:
   - log: "Remotely ID {stari} ne odgovara MachineGuidId {novi}, ponovno instaliram";
   - `RegularInstall(options)`, isti poziv kao kod nove instalacije;
   - nakon toga ponovna provjera: `Match` daje log "Remotely ID usklađen", a sve drugo upozorenje
     "Usklađivanje Remotely ID-a nije uspjelo".
3. Inače: "Remotely Agent je već instaliran", kao danas.

Ostatak metode je nepromijenjen: servis na Automatic, pokretanje servisa, prečac i desktop klijent.

### 4.4 Provjera ID-a

Odluka je u čistoj statičkoj metodi klase `Integrator.MachineSetup.Remotely`, s ugniježđenim enumom (nema novih
datoteka ni izmjene `.csproj`). Ulaz je sadržaj `ConnectionInfo.json` (`null` ako datoteka ne postoji) i očekivani
ID. Izlaz je `NotChecked`, `Match`, `Mismatch` ili `Unreadable`.

| Ulaz | Rezultat |
|---|---|
| Očekivani ID prazan ili nije GUID (`Guid.TryParse`) | `NotChecked` |
| Sadržaj `null` (datoteka ne postoji) | `Mismatch` |
| JSON se ne može parsirati | `Unreadable` |
| `DeviceID` nema, prazan je ili nije GUID | `Mismatch` |
| `DeviceID` i očekivani ID su isti GUID (velika i mala slova i vitičaste zagrade ne smetaju) | `Match` |
| Različiti GUID-ovi | `Mismatch` |

Datoteku čita `Install`:
- putanja je mapa iz `global::MachineSetup.Remotely.GetServiceImagePath()` + `ConnectionInfo.json`, isto kao
  postojeći `UpdateServerToken`;
- JSON parsira Newtonsoft.Json, koji projekt već koristi;
- greška pri čitanju (`IOException`, `UnauthorizedAccessException`) daje `Unreadable`;
- ako `GetServiceImagePath()` vrati `null`, rezultat je `Unreadable`.

Ponovna instalacija ide samo na `Mismatch`. `Unreadable` daje samo upozorenje u logu, jer bi instaler na oštećenoj
datoteci ionako pao i vratio backup.

## 5. Greške i rubni slučajevi

| Situacija | Ponašanje |
|---|---|
| Preuzimanje instalera iz `tokmak/exe` ne uspije | `RegularInstall` izlazi kao danas, a postojeći agent ostaje netaknut |
| Instaler ne uspije (mreža, server, greška) | Instaler vraća backup (stari agent, stari ID). Tokmak upozorava, a sljedeći Halo pokušava ponovo |
| Tehničar je spojen preko Remotelyja dok Halo radi | Veza pukne dok instaler radi (oko minutu). Uređaj se vraća pod novim ID-om |
| Zapis s MachineGuidId-om već postoji na serveru | `POST` vrati 400, a instaler to zanemari. Agent se spaja na postojeći zapis i zadržava njegovu grupu |
| Drugi online stroj već ima isti MachineGuidId | Izvan opsega. Server odbija drugu vezu ("already connected") |
| Ponovni Halo nakon uspjeha | `Match`, bez instalacije |
| Stari zapis na serveru | Ostaje offline. Bilješke i alias sa starog zapisa ne prenose se. Novi zapis dobiva alias = GUID i grupu Operativa, kao svaka Tokmakova instalacija |

## 6. Izvan opsega

- Provjera `Host`-a (stroj usmjeren na drugi server).
- Brisanje starog zapisa na serveru.
- Poziv TokenExtractora (`UpdateServerToken`), koji ostaje kakav jest.
- Strojevi koji ne pokreću Halo: zaseban korak (pregled flote samo čitanjem, MachineGuidId prema Remotely ID-u, pa
  recept u remotely skillu).
- Klonovi koji dijele i MachineGuidId.

## 7. Testiranje

### 7.1 Logika provjere

Tokmak nema testni projekt, a novi se ne dodaje. Skripta u scratchpadu učita izgrađeni `Integrator.MachineSetup.dll`
i pozove metodu iz 4.4 sa slučajevima iz tablice:
- isti GUID, razlika samo u velikim i malim slovima te u vitičastim zagradama;
- drugi GUID;
- prazan `DeviceID`, `DeviceID` koji nije GUID, bez polja `DeviceID`;
- `null` sadržaj, oštećen JSON;
- prazan i neispravan očekivani ID.

Skripta ne ide u TFVC.

### 7.2 Scenariji na TOKMAKTEST-u (Proxmox VM)

Tokmak pokreće korisnik u konzoli VM-a, kao klijent. Stanje se provjerava preko API-ja i remotely skilla.

1. **Svježa instalacija, objavljeni Tokmak (Halo):**
   - očekivano: agent 2026.10.29.0943, `DeviceID` = MachineGuidId, grupa Operativa, Operativa ga vidi;
   - ovim se zatvara T16 i prvi put provjerava instaler bez `-path` na novom serveru.
2. **Neusklađen ID, testni Tokmak:**
   - priprema: preko skilla se u `ConnectionInfo.json` upiše slučajni GUID (token prazan) i restarta servis, pa se
     uređaj pojavi pod slučajnim ID-om;
   - korisnik pokrene Halo;
   - očekivano: log "ne odgovara … ponovno instaliram" i "usklađen", uređaj online pod MachineGuidId-om, a zapis sa
     slučajnim ID-om offline.
3. **Ponovni Halo, testni Tokmak:** očekivano "već instaliran", bez instalacije.
4. **Neobavezno:** scenarij 2 kroz `Tokmak Remotely -i <MachineGuidId> -s false`.

Testni Tokmak gradi se lokalno (skill `vs-build`) u `C:\build\tokmak-reid-test`. Korisnik ga prenosi na TOKMAKTEST.

## 8. Puštanje i povratak

- Nakon uspješnih scenarija korisnik radi check-in i objavljuje Tokmak kao inače.
- Povratak je prethodna inačica Tokmaka.
- U `docs/integrator/produkcija.md` dodaje se kratka bilješka.

## 9. Datoteke (Tokmak, TFVC)

- `Integrator.MachineSetup\RemotelyOptions.cs`: svojstvo `DeviceId`.
- `Integrator.MachineSetup\Remotely.cs`: grana u `Install`, metoda provjere i enum.
- `Tokmak\Program.cs`: puni `DeviceId`.
- `Tokmak\Commands\RemotelyCommand.cs`: puni `DeviceId`.
