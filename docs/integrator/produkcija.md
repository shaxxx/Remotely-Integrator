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
