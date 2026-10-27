# Postojeći testovi na početnoj točki

Datum: 2026-10-27. Stanje: grana `integrator` @ `b780ab27` (= tag `v2022.09.16.1006` + dokumentacija +
skripte osnovice; bez izmjena koda). Alat: .NET SDK 10.0.301 (nema `global.json`), projekti ciljaju
`net6.0`, testovi se izvršavaju na runtimeu 6.0.36.

## Rezultat

| Naredba | Prošlo | Palo | Preskočeno | Ukupno |
|---|---|---|---|---|
| `dotnet test Tests/Server.Tests -p:LibraryRestore=false` | 13 | 0 | 0 | 13 |
| `dotnet test Tests/Shared.Tests` | 1 | 0 | 0 | 1 |

Na početnoj točki nema palih testova.

Testovi u `Tests/Server.Tests` (prije P1): `AgentHubTests` (`DeviceCameOnline_BannedByName`,
`DeviceCameOnline_BannedById`, `DeviceCameOnline_NotBanned`), `DataServiceTests` (`AddAlert`,
`AddOrUpdateDevice`, `CreateDevice`, `DeviceGroupPermissions`,
`GetPendingScriptRuns_GivenMultipleRunsQueued_ReturnsOnlyLatest`, `UpdateOrganizationName`,
`UpdateServerAdmins`, `VerifyInitialData`), `ScriptScheduleDispatcherTests`
(`DispatchPendingScriptRuns_GivenNoSchedulesDue_DoesNothing`,
`DispatchPendingScriptRuns_GivenSchedulesDue_CreatesScriptRuns`).
Test u `Tests/Shared.Tests`: `CopyToAsyncTest`.

## Build bez `-p:LibraryRestore=false` ne prolazi

`dotnet test Tests/Server.Tests` bez parametra pada već u buildu projekta `Server` (0 izvršenih testova):

```
libman.json : error LIB002: The "@microsoft/signalr-protocol-msgpack@6.0.6" library could not be resolved by the "unpkg" provider [Server\Server.csproj]
```

Uzrok je izvan repozitorija: unpkg.com za popis datoteka paketa sada preusmjerava (301) na
`app.unpkg.com`, pa `Microsoft.Web.LibraryManager.Build` 2.1.175 ne može razriješiti paket.
Sve datoteke iz `Server/libman.json` već su u gitu (`Server/wwwroot/lib/...`), pa
`-p:LibraryRestore=false` samo preskače preuzimanje i ne mijenja izlaz. `Tests/Shared.Tests` ne ovisi o
`Server` i prolazi i bez parametra.

## Upozorenja (postojeća, ne popravljaju se)

- `NETSDK1138`: `net6.0` više nije podržan.
- `NU1902`: MailKit 3.3.0 (`Server`).
- `NU1903`: System.Text.Json 6.0.5 (`Shared`).

Napomena: `dotnet build --no-incremental` na SDK-u 10.0.301 jednom padne u `Server`
(`StaticWebAssets`: „No file exists for the asset ... wwwroot\src\RemoteControl\App.js") jer čišćenje
obriše JS koji generira TypeScript; sljedeći obični build prolazi i datoteke su iste kao u gitu.

## Ugovor protokola (P1)

Testovi u `Tests/Server.Tests/Contract`, zlatne datoteke u `Tests/Server.Tests/Contract/Golden`
(`.gitattributes`: `binary`, bez pretvorbe krajeva redaka).

- Provjera: `dotnet test Tests/Server.Tests -p:LibraryRestore=false --filter FullyQualifiedName~Contract`
- Generiranje: isto uz `REMOTELY_UPDATE_GOLDEN=1`.

Rezultat na početnoj točki: 4 prošla, 1 preskočen (`Dtos_MatchBaseline`, vidi dolje), 0 palih.
S njima `Tests/Server.Tests` ima 18 testova: 17 prošlo, 1 preskočen.

### Zlatne datoteke DTO-a (`dto-*.bin`) su iz MessagePacka 2.1.90

`Server` (pa time i `Server.Tests`) preko `Microsoft.VisualStudio.Debugger.Contracts` 17.2.0 dobiva
MessagePack **2.1.152**. Ta verzija ne može napraviti formatter za `[DataContract]` klasu koja
nadjačava `[DataMember]` svojstvo:

```
MessagePackDynamicObjectResolverException: key is duplicated, all members key must be unique. type: Remotely.Shared.Models.RemoteControlDtos.MouseMoveDto member:DtoType
```

To vrijedi za 21 od 22 DTO-a (svi osim `BaseDto`). Server DTO-e nikad ne serijalizira (prosljeđuje
`byte[]`); serijaliziraju ih desktop klijenti (`Desktop.Core`), koji na početnoj točki koriste
MessagePack **2.1.90**. Zato su `dto-*.bin` generirani istim testnim kodom
(`SampleFactory.cs`, `GoldenFile.cs`, `DtoGoldenTests.cs`) preveden uz MessagePack 2.1.90, ovim
pomoćnim projektom izvan repozitorija:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net6.0</TargetFramework>
    <IsPackable>false</IsPackable>
    <Repo>C:\Users\isako\source\repos\Remotely-integrator</Repo>
    <MpVersion Condition="'$(MpVersion)' == ''">2.1.90</MpVersion>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="MessagePack" Version="$(MpVersion)" />
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.2.0" />
    <PackageReference Include="MSTest.TestAdapter" Version="2.2.10" />
    <PackageReference Include="MSTest.TestFramework" Version="2.2.10" />
    <ProjectReference Include="$(Repo)\Shared\Shared.csproj" />
    <Compile Include="$(Repo)\Tests\Server.Tests\Contract\SampleFactory.cs" />
    <Compile Include="$(Repo)\Tests\Server.Tests\Contract\GoldenFile.cs" />
    <Compile Include="$(Repo)\Tests\Server.Tests\Contract\DtoGoldenTests.cs" />
  </ItemGroup>
</Project>
```

Naredbe: `REMOTELY_UPDATE_GOLDEN=1 dotnet test -p:MpVersion=2.1.90` (generiranje), zatim
`dotnet test -p:MpVersion=2.1.90` (provjera: 1 prošao). Datoteke se pišu u `Contract/Golden` repozitorija
jer putanja dolazi iz `[CallerFilePath]` povezanih izvornih datoteka.

U `Server.Tests` s MessagePackom 2.1.152 `Dtos_MatchBaseline` provjeri da postoje sve 22 datoteke
`dto-*.bin` (i da nema viška), a zatim završi kao *inconclusive* (preskočen). S bilo kojom drugom
verzijom MessagePacka test uspoređuje bajtove.

### Pregled za .NET 10: MessagePack 2.5.192

Isti testovi uz MessagePack 2.5.192 (još uvijek `net6.0` i SignalR 6.0.6):

- `hub-signatures`, svi `hub-*`, svi `client-*` i `GoldenPayloads_ParseToSamples`: prolaze, bajtovi isti.
- `dto-*`: 17 od 22 se razlikuje. Duljina je ista, razlika je redoslijed ključeva u mapi: 2.5.192 piše
  `DtoType` (svojstvo deklarirano u `BaseDto`) prvo, a 2.1.90 redom deklaracije u izvedenoj klasi, npr.
  `{"Width":1,"Height":2,"DtoType":2}` (2.1.90) prema `{"DtoType":2,"Width":1,"Height":2}` (2.5.192).
  Isti su `BaseDto`, `CaptureFrameDto`, `MouseMoveDto`, `MouseWheelDto` i `TapDto`, kojima je `DtoType`
  već prvi.
