# Remotely na .NET 10 uz punu kompatibilnost s postojećim klijentima

- **Datum:** 2026-10-26
- **Status:** dizajn odobren u razgovoru, spec čeka pregled
- **Repozitorij:** `shaxxx/Remotely`, grana `integrator` (od upstream taga `v2022.09.16.1006`, commit `eae16cb3`)

## 1. Cilj

Remotely server na `remote.integrator.hr` vrti verziju 2021.10.10.1923 na .NET 5, koji je bez sigurnosnih
zakrpa od svibnja 2022., a server je izložen internetu. Cilj je prebaciti server na podržani runtime
(.NET 10, podrška do studenog 2028.) **bez ikakvog prekida rada postojećih klijenata**.

Prioriteti:

1. **Sigurnost:** server, dio izložen internetu, radi na podržanom runtimeu.
2. **Bonus:** bolji rad web viewera na mobitelu.

## 2. Zahtjevi

### 2.1 Pravilo koje se ne krši

Postojeći klijenti moraju raditi prije, tijekom i nakon svakog koraka ovog projekta. To uključuje remote control
(Machines u Operativi), "Integrator podrška" (session ID), skill i Tokmak. Neuspjeh bilo kojeg koraka ne smije
ostaviti klijenta offline.

### 2.2 Bez izmjena kod korisnika Remotelyja

Ne mijenjaju se: postojeći agenti na ~1250 strojeva, Tokmak (uključujući `Remotely_Install-[523e].exe`),
Start2023, Operativa, remotely skill, TokenExtractor (`/token`) i procedura `dbo.TokenUpdate`.

### 2.3 Kriteriji uspjeha

- Server radi na .NET 10, na istom IIS siteu, s istom bazom i **istom shemom**.
- Nakon prebacivanja broj online uređaja unutar 15 minuta dolazi na osnovicu izmjerenu neposredno prije
  prebacivanja (u radno vrijeme ~660).
- Machines (status, spajanje), gumb "Remotely" (session ID), "Integrator podrška", skill (`find`, `run`,
  recepti) i Tokmak instalacija rade kao prije.
- Web viewer na mobitelu podržava long-press (desni klik, povlačenje), scroll s dva prsta te virtualnu
  tipkovnicu s lijepljenjem teksta.
- Nove instalacije preko Tokmaka dobivaju .NET 10 agent. Postojeći agenti se ne ažuriraju sami.

## 3. Trenutno stanje (snimljeno 2026-10-26)

### 3.1 Server

| Stavka | Vrijednost |
|---|---|
| Stroj | CLOUD, Windows Server 2022 Standard, 16 GB RAM |
| IIS | site `Remotely`, mapa `C:\sites\remotely`, pool `Remotely` (No Managed Code), host `remote.integrator.hr` (http i https) |
| Hosting | in-process, ANCM V2 iz .NET 10.0.14 Hosting Bundlea, self-contained .NET 5.0.10 |
| Verzija | 2021.10.10.1923 = commit `eee74139`; fork je čisti upstream, bez vlastitih izmjena |
| Baza | SQL Server 2025, baza `Remotely`, `DBProvider=SQLServer`, zadnja migracija `20210417155829_Add Alert Details` |
| Certifikat | Let's Encrypt preko win-acme (IIS renewal za site `Remotely`) |
| Pod-aplikacija | `/token`: `C:\sites\remotely\token`, pool `.NET Core`, TokenExtractor (netcoreapp3.1), poziva `dbo.TokenUpdate` |
| Ostalo na IIS-u | ~20 drugih siteova; ne diraju se |

### 3.2 Flota

1255 uređaja: 911 viđenih u zadnjih 30 dana, 661 online u trenutku snimanja. Svi su na Windowsima i svi imaju
agent 2021.10.10.1923. Od toga je 12 x86 te 22 na Windows 7 (8 aktivnih).

### 3.3 Korisnici Remotely sučelja

| Korisnik | Što koristi |
|---|---|
| Stari agent (2021) | SignalR `/AgentHub`; rezultati skripti `POST /API/ScriptResults` (ExpiringToken); ažuriranje: `HEAD /Content/Remotely-Win10-{x64,x86}.zip` s `If-None-Match` iz `etag.txt`, zatim `/Content/Remotely_Installer.exe`, `/api/AgentUpdate/DownloadPackage/win-{arch}/{id}` i `/api/AgentUpdate/ClearDownload/{id}` |
| Stari desktop klijent | SignalR `/CasterHub`; zadana adresa servera ugrađena u build (`-Hostname`), uz `%AppData%\Remotely\Config.json` |
| Web viewer | stranica `/RemoteControl`, SignalR `/ViewerHub` |
| Tokmak (`Remotely_Install-[523e].exe`, .NET Framework 4.8) | `/api/relay/523e`, `/api/branding/{org}`, `GET` i `HEAD /Content/Remotely-Win10-{arch}.zip`, `POST /api/devices` (grupa `Operativa`, alias = CEZAR GUID), zatim `/token/token/{id}/{token}` |
| Start2023 | `/token/token/{id}/{token}` pri svakom pokretanju |
| Operativa, Machines | `GET api/Devices/{id}`, `POST api/RemoteControl` (`DeviceID`, `Email`, `Password`), pa otvara vraćeni URL; zaglavlje `Authorization: KeyId:Secret` |
| Operativa, gumb "Remotely" | otvara `https://remote.integrator.hr/RemoteControl` (unos session ID-a) |
| Remotely skill | `GET api/Devices/{id}`, `POST api/Scripting/ExecuteCommand/{shell}/{deviceId}`; `Authorization: KeyId:Secret`; ljuske WinPS i CMD |

## 4. Odluke

### 4.1 Zašto ne upstream 2024 (v2024.08.07)

Od `v2022.12.31` (commit `3ef4cdf8`, 2022-12-23) upstream je promijenio:

- hubove: `/hubs/service`, `/hubs/desktop`, `/hubs/viewer`;
- nazive metoda i modele te remote-control biblioteku;
- pakete za ažuriranje: `Remotely-Win-*.zip`, a `Install-Remotely.ps1` umjesto installera;
- shemu baze: 8 novih migracija, uključujući brisanje stupaca koje stari server čita.

Stari agenti i stari desktop klijenti s takvim serverom ne rade. Za pravilo 2.1 trebao bi drugi server u
paralelnom radu ili ugradnja starog protokola u novi server.

Mogućnosti koje nas zanimaju to ne opravdavaju:

- **remote file explorer** ne postoji ni u jednoj verziji;
- **prijenos slike** je isti (JPEG promijenjenog područja preko SignalR-a), a WebRTC je u 2024 uklonjen;
- **mobilna poboljšanja** su u web vieweru i mogu se prenijeti (K3).

Upstream je osim toga neaktivan od prosinca 2024.

### 4.2 Početna točka: `v2022.09.16.1006` (.NET 6)

To je zadnje upstream izdanje prije prijeloma; između njega i `3ef4cdf8` nema drugih commitova.

U odnosu na 2021.10.10 (69 commitova) nepromijenjeni su:

- hubovi i njihove metode te `Shared/Models`;
- shema baze (nema novih migracija);
- `ExpiringTokenFilter`;
- API za uređaje, skripte, remote control, relay i branding;
- stranica `/RemoteControl`;
- mehanizam ažuriranja agenata i `Agent.Installer.Win`.

Promjene u vieweru koriste samo postojeće poruke. **Jedina nekompatibilnost:** API ključ se prihvaća samo kao
`Basic base64(KeyId:Secret)`. To ispravlja K1.

Ta verzija donosi:

- .NET 6 umjesto .NET 5;
- ispravak remote controla kad prebacivanje na ulazni desktop ne uspije (#486);
- scroll s dva prsta (#487, #501);
- SkiaSharp umjesto System.Drawing (#485);
- HttpClient za ažuriranja (#500);
- DbContext factory (#418) i API za grupe uređaja (#416).

**Početna točka se potvrđuje testom** (7.2, krug 1) prije porta. Ako test padne, a ne da se popraviti malom
izmjenom, polazi se od `master` (2021.10.10), a ostatak dizajna ostaje isti.

### 4.3 Agenti se ne ažuriraju masovno

Postojeći agenti ostaju kakvi jesu, jer su kompatibilni s novim serverom. To vrijedi i za Windows 7 strojeve.
Nove instalacije dobivaju .NET 10 agent. Masovno ažuriranje flote izvan je ovog projekta (poglavlje 9).

## 5. Rješenje: kod i build

### 5.1 Izmjene na grani `integrator`

Svaka izmjena ide u zasebnom commitu.

- **K1, API ključ u oba formata.** `ApiAuthorizationFilter` prihvaća:
  - `Authorization: KeyId:Secret`, bez prefiksa (skill, Operativa);
  - `Authorization: Basic base64(KeyId:Secret)`.

  Sve ostalo se odbija kao i do sada. K1 je jedina izmjena koja ide prije testa početne točke.

- **K2, port na .NET 10.**
  - **Okviri:** `Server`, `Shared`, `Agent` i `Desktop.Core` na `net10.0`, `Desktop.Win` na `net10.0-windows`,
    a testni projekti analogno.
  - **Paketi:**
    - ASP.NET Core, EF Core (SqlServer, Sqlite, Npgsql) te SignalR klijent i MessagePack protokol na 10.x;
    - PowerShell SDK (`Microsoft.PowerShell.SDK`, `System.Management.Automation`, `Microsoft.WSMan.*`) na
      verziju koja cilja .NET 10;
    - MailKit, Swashbuckle i `Microsoft.TypeScript.MSBuild` na aktualne verzije.
  - SharpDX, NAudio i SkiaSharp zadržavamo dok god rade na .NET 10.
  - `Microsoft.MixedReality.WebRTC` (WebRTC je kod nas isključen, `UseWebRtc=false`) uklanja se samo ako
    blokira build ili rad, i to bez promjene protokola.

- **K3, mobilna poboljšanja web viewera.** Iz kasnijeg upstreama ciljano prenosimo TypeScript promjene:
  - long-press za desni klik te long-press s povlačenjem za klik-i-povuci (v2023.07.20);
  - virtualnu tipkovnicu kao preklopni gumb, skriveni `input` umjesto `textarea`, Enter i Backspace preko
    `keydown` te lijepljenje teksta s virtualne tipkovnice (v2024.06.27);
  - obradu dozvole za čitanje međuspremnika u Firefoxu i Safariju (v2024.06.27).

  Scroll s dva prsta je već u početnoj točki. **Uvjet:** preneseno smije slati samo poruke koje postoje u
  desktop klijentu iz 2021., jer viewer mora raditi i sa starim desktop klijentima.

- **K4, build.** Osnova je `Utilities/Publish.ps1` iz početne točke, prilagođen ovako:
  - `-Hostname https://remote.integrator.hr`, kao i danas: adresa se ugrađuje kao zadana adresa desktop
    klijenta i u ClickOnce;
  - RID `win-x64` i `win-x86` umjesto ukinutih `win10-x64` i `win10-x86`, uz `--self-contained` (već postoji);
  - izbacuju se Linux i macOS agenti, `Desktop.XPlat` i `Server.Installer`;
  - zadržavaju se desktop klijent i ClickOnce u `Content\Win-x64` i `Content\Win-x86`;
  - **u `Content` ide postojeća produkcijska binarka `Remotely_Installer.exe`,** a ne nanovo izgrađena; njen
    SHA-256 bilježi se pri deployu;
  - server se objavljuje za `win-x64` kao self-contained;
  - exe datoteke ostaju nepotpisane, kao i danas.

- **K5, prekidač automatskog ažuriranja agenata.** Postavka `ApplicationOptions:AgentAutoUpdate`, zadano
  `false`.
  - Dok je `false`, server na `HEAD /Content/Remotely-Win10-x64.zip` i `HEAD /Content/Remotely-Win10-x86.zip`
    koji nose `If-None-Match` odgovara `304 Not Modified`.
  - `HEAD` bez tog zaglavlja (installer, Tokmak) i svi `GET` zahtjevi poslužuju se normalno.
  - Na taj način provjeru ažuriranja šalju i stari (2021) i novi (2022.09 / .NET 10) agenti, pa se nijedan
    ne ažurira sam. Installer i Tokmak i dalje dobivaju aktualni paket.

### 5.2 Pravila koja se provjeravaju testovima

- **P1, protokol se ne mijenja.** Ostaju isti:
  - hubovi `/AgentHub`, `/CasterHub` i `/ViewerHub`, s istim metodama i potpisima;
  - DTO poruke (MessagePack);
  - API rute i modeli zahtjeva i odgovora.
- **P2, shema baze se ne mijenja.** Nema novih migracija, a EF Core 10 ne smije prijaviti promjene modela.
  (Od EF Core 9 `Database.Migrate()` u `Startup` baca iznimku kad model odstupa od snimke migracija.)
- **P3, isti nazivi i putanje:**
  - na serveru: `Remotely-Win10-x64.zip`, `Remotely-Win10-x86.zip`, `Remotely_Installer.exe`,
    `Content\Win-x64` i `Content\Win-x86`;
  - na klijentu: `C:\Program Files\Remotely`, servis `Remotely_Service`, `Remotely_Agent.exe` i
    `Desktop\Remotely_Desktop.exe`.

### 5.3 Što ostaje nepromijenjeno

- `Agent.Installer.Win` i produkcijska binarka installera.
- Postavke u `appsettings.json`. Dodaju se samo `TrustServerCertificate=True` u connection string (novi
  SqlClient po zadanom traži enkripciju) i `AgentAutoUpdate=false`.
- `/token`, TokenExtractor i `dbo.TokenUpdate`.

## 6. Rješenje: uvođenje

Načelo: jedan rizik u jednom trenutku. Server i agentski paketi mijenjaju se u odvojenim koracima.

### 6.1 Korak 1: nadogradnja servera

Preduvjet su prošli testovi iz 7.1 i 7.2. Korak se radi izvan radnog vremena, uz korisnika s RDP pristupom
CLOUD-u.

1. **Backup:** puni `COPY_ONLY` backup baze `Remotely`. Stara mapa `C:\sites\remotely` se ne mijenja.
2. **Priprema nove mape** `C:\sites\remotely-net10`:
   - novi build;
   - `appsettings.json` iz stare mape, uz dodatke iz 5.3;
   - `web.config` za in-process hosting s `inheritInChildApplications="false"`;
   - `wwwroot\Content` **prekopiran iz stare mape s očuvanim vremenom izmjene** (stari paketi);
   - prava za `IIS AppPool\Remotely`: čitanje na cijeloj mapi i izmjena na mapi `logs`.
3. **Prebacivanje:** zaustavlja se samo pool `Remotely`, siteu `Remotely` mijenja se fizička putanja na
   `C:\sites\remotely-net10`, a pool se ponovo pokreće.
   - `/token` ima vlastitu fizičku putanju i vlastiti pool, pa se ne dira.
   - win-acme kod obnove sam piše provjeru u novu putanju.
4. **Start:** `Migrate()` ne pokreće nijednu migraciju (P2), a stari agenti se sami ponovo spajaju unutar
   1–30 sekundi.
5. **Brzi testovi:**
   - prijava u web sučelje;
   - broj online uređaja prema osnovici izmjerenoj prije prebacivanja;
   - skill `find` i `run` na nekoliko strojeva;
   - Operativa: status, spajanje i gumb "Remotely" sa session ID-om;
   - "Integrator podrška";
   - `/token`;
   - `HEAD` na `Remotely-Win10-x64.zip` s `If-None-Match` vraća 304, a bez njega 200.

**Povratak:** fizička putanja sitea vraća se na `C:\sites\remotely` i radi se recycle poola. To traje manje od
minute, a restore baze nije potreban, jer se shema nije mijenjala. Stara mapa se čuva do kraja projekta.

### 6.2 Korak 2: novi agent za nove instalacije

Radi se nakon najmanje nekoliko dana stabilnog rada koraka 1.

1. Postojeći paketi iz `Content` kopiraju se u `Content\rollback\`.
2. U `Content` se stavljaju novi paketi: `Remotely-Win10-x64.zip`, `Remotely-Win10-x86.zip` te desktop i
   ClickOnce u `Content\Win-x64` i `Content\Win-x86`. `Remotely_Installer.exe` ostaje isti.
3. `AgentAutoUpdate` ostaje `false`, pa postojeći agenti ostaju kakvi jesu.
4. Provjera: svježa Tokmak instalacija na IVICATEST-u, nakon koje se novi agent pojavljuje online.

**Povratak:** paketi iz `Content\rollback\` vraćaju se u `Content`.

### 6.3 Pojedinačno ažuriranje postojećeg stroja (po potrebi, nakon koraka 2)

Kad stroj treba ispravak iz novog desktop klijenta, skill na njemu pokreće
`Remotely_Installer.exe -install -quiet -serverurl https://remote.integrator.hr -organizationid <OrganizationID>`
kao zaseban, odvezani proces. `<OrganizationID>` se čita iz `ConnectionInfo.json` tog stroja. Installer preuzima aktualni paket, radi backup i, ako instalacija ne uspije, vraća
stari agent. Stari agent i dalje radi s novim serverom.

### 6.4 Praćenje

Upit nad bazom koji broji uređaje po `AgentVersion` i online statusu pokreće se prije i nakon svakog koraka te
svakodnevno tjedan dana nakon koraka 1.

## 7. Testiranje

### 7.1 Automatski testovi u repozitoriju

- Postojeći testovi (`Server.Tests`, `Shared.Tests`, `Desktop.Win.Tests`) na .NET 10 prolaze.
- **K1:** prihvaća `KeyId:Secret` i `Basic base64(KeyId:Secret)`, a odbija prazno zaglavlje, pogrešan ključ i
  neispravan base64.
- **K5:**
  - `HEAD` s `If-None-Match` vraća 304 dok je `AgentAutoUpdate=false`;
  - `HEAD` bez zaglavlja vraća 200 i ETag;
  - kad je `AgentAutoUpdate=true`, ponašanje je normalno.
- **P2:** `dotnet ef migrations has-pending-model-changes` za `SqlServerDbContext` ne prijavljuje promjene,
  a isto provjerava test u repozitoriju.
- **P1:**
  - snimka javnih metoda i potpisa `AgentHub`, `CasterHub` i `ViewerHub` uspoređuje se sa snimkom iz
    `v2022.09.16.1006`;
  - zlatne datoteke DTO poruka, serijalizirane buildom `v2022.09.16.1006`, .NET 10 build mora deserijalizirati
    i serijalizirati identično.

### 7.2 Staging (`remote-test.integrator.hr`)

**Postavke:**

- na CLOUD-u zaseban IIS site `Remotely-Test`, mapa `C:\sites\remotely-test` i pool `Remotely-Test`;
- baza `Remotely_Test`, obnovljena iz `COPY_ONLY` backupa produkcijske baze;
- kopija `/token` koja koristi `Remotely_Test`;
- certifikat preko win-acme;
- DNS zapis postoji od 2026-10-26.

**Klijent:** IVICATEST. Skill mu prepiše `Host` u `ConnectionInfo.json` na staging i restarta servis. Dok je
usmjeren na staging, za produkciju je offline, a korisnik ima RDP. Dodatni Windows Server VM nije obavezan,
ali je dobrodošao.

**Skill na stagingu:** skill je vezan uz produkcijski config, koji se ne mijenja. Njegove pozive (iste rute i
isto zaglavlje) na stagingu radi testna skripta, a sam skill se provjerava na produkciji nakon koraka 1.

**Krug 1, provjera početne točke:**

- Izvorni `v2022.09.16.1006` s K1 objavljuje se self-contained za .NET 6.
- Stari agent i stari desktop prolaze isti popis kao u krugu 2 (osim stavki koje traže novi agent).
- Ako krug 1 ne prođe, odlučuje se o povratku na `master` (4.2).

**Krug 2, .NET 10 build s K1–K5:**

- **Stari agent (2021):**
  - online status i heartbeat;
  - pozivi kao skill: `Devices/{id}` i `ExecuteCommand` s WinPS i CMD;
  - remote control iz weba i iz testne Operative (`config.ini` s `BaseUrl` na staging);
  - "Integrator podrška" sa session ID-om preko `/RemoteControl`;
  - chat, prijenos datoteka u oba smjera i međuspremnik;
  - Ctrl+Alt+Del, UAC prompt, zaključani ekran i više monitora;
  - viewer na mobitelu, sve stavke iz K3.
- **Novi agent, instaliran Tokmakom.** Naredba je `Tokmak4 Remotely -i <GUID stroja iz CEZAR-a> -a "<parametri>"`,
  gdje su `<parametri>` produkcijski parametri iz `RemotelyOptions.SetupCommandLineParameters`, ali sa
  `-serverurl https://remote-test.integrator.hr`. Provjerava se:
  - isti popis kao za stari agent;
  - poziv `/token` na stagingu, ručno.
- **Ažuriranje i povratak:**
  - stari agent prelazi na novi preko installera;
  - zatim se installer pokreće s namjerno neispravnim paketom (`-path`), nakon čega stroj mora ostati online
    na prethodnoj verziji.
- **K5:** provjera agenta dobiva 304, a installer i Tokmak dobivaju paket.
- **Server:**
  - `__EFMigrationsHistory` i popis stupaca u bazi isti su prije i nakon starta;
  - logovi su bez grešaka;
  - vježba povratka zamjenom fizičke putanje.

### 7.3 Produkcija

- Brzi testovi iz 6.1, korak 5.
- Prvi puni test skill recepata, uključujući SQL recepte, jer na IVICATEST-u nema SQL Servera.
- Tjedan dana praćenja: broj online uređaja prema osnovici, logovi servera i povratne informacije ljudi koji
  rade s Machinesom.

## 8. Rizici

| Rizik | Mjera |
|---|---|
| Razlike u radu između .NET 5/6 i .NET 10 (serijalizacija, SignalR) | P1 testovi sa zlatnim datotekama; krug 2 na stagingu sa starim agentom |
| EF Core 10 vidi promjenu modela pa `Migrate()` baca iznimku ili traži migraciju | P2 test; ako se pojavi razlika, rješava se konfiguracijom modela, nikad migracijom |
| SqlClient odbija vezu bez enkripcije | `TrustServerCertificate=True` u connection stringu |
| Agent bez `etag.txt` šalje provjeru bez `If-None-Match`, pa ga K5 ne zaustavlja | Ažurira se; installer pri neuspjehu vraća stari agent, koji ostaje kompatibilan |
| K3 slučajno uvede poruku koju stari desktop ne razumije | Uvjet u K3; test sa starim desktopom u krugu 2 |
| PowerShell SDK na .NET 10 mijenja ponašanje ljuske PSCore u novom agentu | Skill koristi WinPS i CMD (vanjski procesi); PSCore se testira u krugu 2 |
| `Microsoft.MixedReality.WebRTC` ne radi na .NET 10 | Uklanja se (WebRTC je isključen), bez promjene protokola |
| Antivirus kod klijenata označi nove nepotpisane binarke | Isto stanje kao danas; nove instalacije se prate nakon koraka 2 |
| Nove instalacije na Windows 7 i 8.1 dobivaju .NET 10 agent koji tamo ne radi | Prihvaćeno (Windows 7 je izvan opsega); postojeći Win7 agenti nastavljaju raditi |
| In-process hosting .NET 10 aplikacije u IIS-u | Isti IIS i ANCM na stagingu; vježba povratka |

## 9. Izvan opsega

- Masovno ažuriranje postojećih agenata. Ako se jednom poželi, ide u valovima pa uključenjem `AgentAutoUpdate`.
- Prelazak na upstream 2024 i njegove mogućnosti.
- Remote file explorer. Moguć je kao zaseban projekt iznad izvršavanja PowerShella i postojećeg relaya,
  neovisno o verziji Remotelyja.
- Modernizacija Tokmaka: `Install-Remotely.ps1`, prečac s `--host`, ispravak čitanja registryja u
  `Integrator.MachineSetup\Remotely.cs` i obrada greške `UpdateServerToken`.
- Potpisivanje binarki.
- Podrška za Windows 7 i 8.1 kod novih instalacija.
- Uklanjanje i zamjena API ključa zapisanog u komentaru u `Operativa2023\frmMachinesNew.vb` (zasebna radnja).

## 10. Preduvjeti

- DNS zapis `remote-test.integrator.hr` (postoji od 2026-10-26) i certifikat preko win-acme.
- Prostor za backup i obnovu baze na CLOUD-u. Baza ima ~1300 uređaja i nekoliko tisuća redaka, a na disku C:
  je 171 GB slobodno.
- .NET 10 SDK (10.0.301 instaliran na razvojnom računalu) i Visual Studio MSBuild za ClickOnce i WPF.
- IVICATEST dostupan kroz Remotely te korisnikov RDP pristup za slučaj da zapne.
- Testna kopija Operative s `config.ini` usmjerenim na staging.
- Dogovoren termin izvan radnog vremena za korak 1.
