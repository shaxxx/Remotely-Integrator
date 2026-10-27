using MessagePack;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Remotely.Shared.Models.RemoteControlDtos;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace Remotely.Server.Tests.Contract
{
    /// <summary>
    /// MessagePack bytes of the remote control DTOs (MessagePackSerializer default options, as used by
    /// the desktop clients), one golden file dto-&lt;Type&gt; per DTO.
    /// </summary>
    /// <remarks>
    /// Compiled and run by Tests/Contract.DtoGolden.Tests, not by Server.Tests. The desktop clients
    /// (Desktop.Core) serialize and deserialize DTOs; the server only relays byte[]. At v2022.09.16.1006
    /// Desktop.Core and Agent resolve MessagePack 2.1.90, which is the reference for dto-*.bin.
    /// Server (and so Server.Tests) resolves MessagePack 2.1.152 through Microsoft.VisualStudio.Debugger.Contracts;
    /// 2.1.152 cannot serialize a [DataContract] type that overrides a [DataMember] property
    /// ("key is duplicated ... member:DtoType"), i.e. every DTO except BaseDto.
    /// MessagePack 2.5.192 writes the same keys and values, but for 17 of the 22 DTOs in a different map
    /// key order (DtoType, declared in BaseDto, first), so its bytes differ from these golden files.
    /// </remarks>
    [TestClass]
    public class DtoGoldenTests
    {
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

        [TestMethod]
        public void Dtos_MatchBaseline()
        {
            var types = DtoTypes();
            Assert.AreNotEqual(0, types.Count, "No DTO types found.");

            GoldenFile.AssertNoOrphans("dto-", types.Select(t => "dto-" + t.Name));

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
