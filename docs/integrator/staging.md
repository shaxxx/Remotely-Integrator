# Staging: remote-test.integrator.hr

## Svrha

Prije diranja produkcije (`remote.integrator.hr`) na istom IIS-u na CLOUD-u podiže se staging
`remote-test.integrator.hr` s vlastitom kopijom baze. Na njemu se provjerava .NET 10 inačica servera.

Skripta `Utilities/Integrator/New-RemotelyStaging.ps1` stvara:

- IIS site `Remotely-Test` (`http *:80:remote-test.integrator.hr`, `https *:443:remote-test.integrator.hr`, SNI)
  s fizičkom putanjom `C:\sites\remotely-test` i poolom `Remotely-Test`;
- aplikaciju `/token` na `C:\sites\remotely-test-token` s poolom `Remotely-Test-Token`
  (zasebni poolovi jer dvije in-process aplikacije ne mogu dijeliti pool);
- poolove: No Managed Code, `ApplicationPoolIdentity`, `OnDemand`, Integrated;
- kopiju `C:\sites\remotely\token` u `C:\sites\remotely-test-token`, u kojoj je u `appsettings.json`
  `Database=Remotely;` zamijenjeno s `Database=Remotely_Test;` (vrijednost se ne ispisuje);
- DACL s `C:\sites\remotely` kopiran na obje nove mape (samo DACL, ne vlasnik).

Skripta ne dira site `Remotely`, njegov pool ni njegove mape. Odbija se pokrenuti (bez ikakve promjene)
ako site `Remotely-Test`, bilo koji od dva poola ili neprazna ciljna mapa već postoje. Ako korak pukne
usred posla, ispiše što je već stvoreno; automatskog rollbacka IIS objekata nema.

## 1. Pokretanje skripte (mijenja stanje)

Naredba ispod mijenja stanje na CLOUD-u i izvršava se tek uz izričit "da" korisnika:

```bash
"$R" run 7665BD18-DDE6-4F36-8743-7C4B49CDC6D5 --timeout 240 --file Utilities/Integrator/New-RemotelyStaging.ps1
```

Ispis sadrži `SITE ID: <ID>` i `Get-WebBinding` (protokol, bindingInformation, sslFlags); treba biti
dva bindinga. `<ID>` treba za win-acme.

## 2. Kopija baze (korisnik, SSMS, admin prijava)

SYSTEM na CLOUD-u nema sysadmin/dbcreator, pa ovo izvršava korisnik u SSMS-u s admin prijavom:

```sql
BACKUP DATABASE [Remotely] TO DISK = N'C:\sql-backup\Remotely_staging_copy.bak' WITH COPY_ONLY, INIT, CHECKSUM;
RESTORE FILELISTONLY FROM DISK = N'C:\sql-backup\Remotely_staging_copy.bak';
-- logička imena iz FILELISTONLY upisati umjesto <data> i <log>
RESTORE DATABASE [Remotely_Test] FROM DISK = N'C:\sql-backup\Remotely_staging_copy.bak'
  WITH MOVE N'<data>' TO N'C:\Program Files\Integrator\Baze\Remotely_Test.mdf',
       MOVE N'<log>'  TO N'C:\Program Files\Integrator\Baze\Remotely_Test_log.ldf', RECOVERY;
```

### Provjera

```sql
-- mora biti 1255 (osnovica u docs/integrator/baseline-production.md) ili trenutni broj u trenutku kopiranja
SELECT COUNT(*) FROM [Remotely_Test].dbo.Devices;

-- prijava remotely se mora moći spojiti na Remotely_Test
EXECUTE AS LOGIN = 'remotely';
SELECT DB_NAME(), COUNT(*) FROM [Remotely_Test].dbo.Devices;
REVERT;
```

Vraćeni DB korisnik `remotely` mapira se na istu serversku prijavu po SID-u jer je riječ o istoj
SQL Server instanci. Ako ne (orphaned user, druga provjera pada), popravak unutar `Remotely_Test`:

```sql
USE [Remotely_Test];
ALTER USER [remotely] WITH LOGIN = [remotely];
```

## 3. Certifikat (win-acme, korisnik)

Korisnik u svojoj RDP sesiji, iz povišenog (elevated) prompta. Verzija na CLOUD-u je 2.2.9.
Prvo potvrditi prekidače na toj verziji:

```
C:\win-acme\wacs.exe --help
```

Zatim, s `<ID>` iz ispisa skripte:

```
C:\win-acme\wacs.exe --source iis --siteid <ID> --installation iis
```

### Provjera

```powershell
Get-ChildItem Cert:\LocalMachine\WebHosting, Cert:\LocalMachine\My |
  Where-Object { $_.Subject -eq 'CN=remote-test.integrator.hr' } |
  Select-Object Subject, Thumbprint, NotAfter
```

`Get-WebBinding -Name Remotely-Test` mora za `https` pokazati `certificateHash` (neprazan).

## 4. Čišćenje (samo na izričit zahtjev)

Samo na izričit zahtjev, na kraju projekta. Ništa od ovoga se ne izvršava samo od sebe.

```powershell
Remove-Website -Name Remotely-Test            # uklanja i aplikaciju /token
Remove-WebAppPool -Name Remotely-Test
Remove-WebAppPool -Name Remotely-Test-Token
Remove-Item C:\sites\remotely-test -Recurse
Remove-Item C:\sites\remotely-test-token -Recurse
```

```sql
DROP DATABASE [Remotely_Test];
```

Opcionalno obrisati `C:\sql-backup\Remotely_staging_copy.bak` i certifikat `remote-test.integrator.hr`
(win-acme: `wacs.exe --cancel` / ručno iz trezora certifikata).
