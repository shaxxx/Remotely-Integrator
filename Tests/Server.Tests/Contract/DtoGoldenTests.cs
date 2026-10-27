using MessagePack;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Remotely.Shared.Models.RemoteControlDtos;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Text.Json;

namespace Remotely.Server.Tests.Contract
{
    /// <summary>
    /// MessagePack bytes of the remote control DTOs (MessagePackSerializer default options, as used by
    /// the desktop clients), one golden file dto-&lt;Type&gt; per DTO.
    /// </summary>
    [TestClass]
    public class DtoGoldenTests
    {
        /// <summary>
        /// MessagePack 2.1.152 reaches Server (and so this project) through Microsoft.VisualStudio.Debugger.Contracts.
        /// It cannot build a formatter for a [DataContract] type that overrides a [DataMember] property
        /// ("key is duplicated ... member:DtoType"), which is every DTO except BaseDto. The server never
        /// serializes DTOs (it relays byte[]); the desktop clients do, with MessagePack 2.1.90 at v2022.09.16.1006.
        /// The dto-*.bin files were therefore generated from this same test code compiled against MessagePack
        /// 2.1.90 (2.5.192 writes identical bytes); see docs/integrator/baseline-tests.md.
        /// Under 2.1.152 the test only checks that the golden files exist and ends inconclusive.
        /// </summary>
        public const string BrokenMessagePackVersion = "2.1.152";

        /// <summary>
        /// Every non-abstract class in Remotely.Shared.Models.RemoteControlDtos assignable to BaseDto,
        /// BaseDto included (it is concrete). Sorted by name (ordinal).
        /// </summary>
        public static IReadOnlyList<Type> DtoTypes()
        {
            return typeof(BaseDto).Assembly.GetTypes()
                .Where(t => t.Namespace == typeof(BaseDto).Namespace &&
                    t.IsClass &&
                    !t.IsAbstract &&
                    typeof(BaseDto).IsAssignableFrom(t))
                .OrderBy(t => t.Name, StringComparer.Ordinal)
                .ToArray();
        }

        public static string MessagePackVersion()
        {
            var version = typeof(MessagePackSerializer).Assembly
                .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
                .InformationalVersion ?? string.Empty;

            var metadata = version.IndexOf('+');
            return metadata >= 0 ? version.Substring(0, metadata) : version;
        }

        [TestMethod]
        public void Dtos_MatchBaseline()
        {
            var types = DtoTypes();
            Assert.AreNotEqual(0, types.Count, "No DTO types found.");

            GoldenFile.AssertNoOrphans("dto-", types.Select(t => "dto-" + t.Name));

            if (MessagePackVersion() == BrokenMessagePackVersion)
            {
                if (!GoldenFile.IsUpdateMode)
                {
                    GoldenFile.AssertAll(types, t => "dto-" + t.Name, t => GoldenFile.Read("dto-" + t.Name));
                }

                Assert.Inconclusive(
                    $"MessagePack {BrokenMessagePackVersion} cannot serialize DTOs that override BaseDto.DtoType; " +
                    $"{types.Count} dto golden file(s) exist in {GoldenFile.GetDirectory()} but were not compared.");
            }

            GoldenFile.AssertAll(types, t => "dto-" + t.Name, type =>
            {
                var sample = SampleFactory.Create(type);
                var bytes = MessagePackSerializer.Serialize(type, sample);

                GoldenFile.AssertMatches("dto-" + type.Name, bytes);

                var roundTrip = MessagePackSerializer.Deserialize(type, bytes);
                Assert.AreEqual(JsonSerializer.Serialize(sample, type), JsonSerializer.Serialize(roundTrip, type), "Round trip changed the value.");
            });
        }
    }
}
