# Produkcijska osnovica Remotely (remote.integrator.hr)

Datum: 2026-10-27. Snimljeno samo citanjem (bez zapisivanja) na CLOUD-u.

Skripte: `Utilities/Integrator/Get-RemotelyBaseline.ps1`, `Utilities/Integrator/Get-RemotelyFleetStatus.ps1`.
Naredba: `remotely.exe run 7665BD18-DDE6-4F36-8743-7C4B49CDC6D5 --timeout 240 --file <skripta>` (zadani parametri).

Napomena: ETag-ovi su `"<hex>"`; ostali su izlaz skripte doslovno.

## Remotely produkcijska osnovica

- Izvrseno (UTC): 2026-10-27T06:35:03.1066762Z
- SitePath: C:\sites\remotely
- BaseUrl: https://remote.integrator.hr
- Database: Remotely

### Content datoteke

### Remotely-Win10-x64.zip

- Length: 115664673
- LastWriteTimeUtc.Ticks: 637701417140000000
- LastWriteTimeUtc (o): 2021-10-18T08:15:14.0000000Z
- SHA-256: 930c473bd31d5def704f2104a9471af4c585727abdb1915699bdc5751437bc8d
- ETag: `"1d7c3f840097221"`

### Remotely-Win10-x86.zip

- Length: 105480487
- LastWriteTimeUtc.Ticks: 637701417160000000
- LastWriteTimeUtc (o): 2021-10-18T08:15:16.0000000Z
- SHA-256: 177c47b6adc6e530b9a11fd524985a342f73c6d952e4e1bc160352a013c49d03
- ETag: `"1d7c3f84e574327"`

### Remotely_Installer.exe

- Length: 276992
- LastWriteTimeUtc.Ticks: 637701417200000000
- LastWriteTimeUtc (o): 2021-10-18T08:15:20.0000000Z
- SHA-256: 8cf5076689e690101fed26595af8fbdba26bcf944278cff198fe3427410d14eb

### __EFMigrationsHistory

Broj migracija: 12

- 20201002214839_InitialCreate
- 20201204210331_Many-to-many
- 20210103153621_WebRtcSetting
- 20210205114415_IsSponsor property
- 20210205221252_Sponsorship Info
- 20210206174936_Sponsor Level
- 20210206232822_Branding Info
- 20210207000343_Rename Branding Props
- 20210210030806_Change BrandingInfo Id
- 20210217033404_Remove 3rd Party Services
- 20210408133030_Add ScriptSchedules
- 20210417155829_Add Alert Details

### Snimka sheme

Format retka: `tablica.stupac:tip:nullable` (tip = DATA_TYPE, uz (CHARACTER_MAXIMUM_LENGTH) kad postoji; nullable = IS_NULLABLE).
Izvor: INFORMATION_SCHEMA.COLUMNS za BASE TABLE u shemi dbo; retci sortirani ordinalno; spojeni znakom LF (bez zavrsnog LF); SHA-256 nad UTF-8 bajtovima, mala hex slova.

- Broj redaka: 179
- SHA-256: bc7fa1b734b2718f0052794da8d77af924f1371df1c91d17a9b85f9b1cf7cfc2

### Flota (Devices po AgentVersion i IsOnline)

| AgentVersion | IsOnline | Broj |
|---|---|---|
| (null) | False | 1 |
| 2021.10.10.1923 | False | 772 |
| 2021.10.10.1923 | True | 482 |

- Ukupno uredjaja: 1255
- Ukupno online: 482

## Get-RemotelyFleetStatus.ps1

```
Database: Remotely
| AgentVersion | IsOnline | Broj |
|---|---|---|
| (null) | False | 1 |
| 2021.10.10.1923 | False | 772 |
| 2021.10.10.1923 | True | 482 |

Ukupno uredjaja: 1255
Ukupno online: 482
```
