using MessagePack;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Remotely.Shared.Models.RemoteControlDtos;
using System;
using System.Buffers;
using System.Collections.Generic;
using System.IO;
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
    /// (Desktop.Core) serialize and deserialize DTOs; the server only relays byte[].
    /// The golden files hold the bytes of MessagePack 2.1.90, which Desktop.Core and Agent resolve at
    /// v2022.09.16.1006. Tests/Contract.DtoGolden.Tests serializes with the MessagePack version that
    /// Microsoft.AspNetCore.SignalR.Protocols.MessagePack 10.x resolves (2.5.x), i.e. the .NET 10 desktop.
    /// MessagePack 2.5.x writes the same keys and values, but for 17 of the 22 DTOs in a different map key
    /// order (DtoType, declared in BaseDto, first). The DTOs are therefore compared by content: map entries
    /// may be in any order; keys, values (with their MessagePack encoding) and array order must match.
    /// Hub and client payload golden files (HubPayloadGoldenTests) stay byte-exact.
    /// MessagePack 2.1.152 (resolved by Server at v2022.09.16.1006) cannot serialize a [DataContract] type
    /// that overrides a [DataMember] property ("key is duplicated ... member:DtoType"), i.e. every DTO
    /// except BaseDto; that is why the DTOs have their own test project.
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

                AssertContentMatches("dto-" + type.Name, bytes);

                var roundTrip = MessagePackSerializer.Deserialize(type, bytes);
                Assert.AreEqual(JsonSerializer.Serialize(sample, type), JsonSerializer.Serialize(roundTrip, type), "Round trip changed the value.");
            });
        }

        /// <summary>
        /// Compares a golden file with the actual bytes by content, ignoring the order of map entries.
        /// With REMOTELY_UPDATE_GOLDEN=1 the file is written only if it is missing or its content differs.
        /// </summary>
        private static void AssertContentMatches(string name, byte[] actual)
        {
            var path = GoldenFile.GetPath(name);

            if (GoldenFile.IsUpdateMode)
            {
                if (!File.Exists(path) || !ContentEquals(File.ReadAllBytes(path), actual))
                {
                    GoldenFile.AssertMatches(name, actual);
                }
                return;
            }

            var expected = GoldenFile.Read(name);
            if (expected.AsSpan().SequenceEqual(actual))
            {
                return;
            }

            if (ContentEquals(expected, actual))
            {
                Console.WriteLine($"{name}: bytes differ from the golden file only in map key order.");
                return;
            }

            Assert.Fail(
                $"Golden file content mismatch (map key order ignored): {path}. " +
                $"Expected {expected.Length} bytes {MessagePackSerializer.ConvertToJson(expected)}, " +
                $"actual {actual.Length} bytes {MessagePackSerializer.ConvertToJson(actual)}.");
        }

        private static bool ContentEquals(byte[] expected, byte[] actual)
        {
            return Canonicalize(expected).AsSpan().SequenceEqual(Canonicalize(actual));
        }

        /// <summary>
        /// The same MessagePack value with the entries of every map sorted by their (canonical) key bytes.
        /// Every other element (map and array headers, keys, scalar values) keeps its exact encoding.
        /// </summary>
        private static byte[] Canonicalize(byte[] bytes)
        {
            var reader = new MessagePackReader(bytes);
            var result = CanonicalizeValue(ref reader);
            if (!reader.End)
            {
                throw new InvalidDataException("Bytes left after the MessagePack value.");
            }
            return result;
        }

        private static byte[] CanonicalizeValue(ref MessagePackReader reader)
        {
            var start = reader.Position;
            switch (reader.NextMessagePackType)
            {
                case MessagePackType.Map:
                    {
                        var count = reader.ReadMapHeader();
                        var parts = new List<byte[]> { reader.Sequence.Slice(start, reader.Position).ToArray() };
                        var entries = new List<(byte[] Key, byte[] Value)>(count);
                        for (var i = 0; i < count; i++)
                        {
                            var key = CanonicalizeValue(ref reader);
                            var value = CanonicalizeValue(ref reader);
                            entries.Add((key, value));
                        }
                        entries.Sort((a, b) =>
                        {
                            var byKey = a.Key.AsSpan().SequenceCompareTo(b.Key);
                            return byKey != 0 ? byKey : a.Value.AsSpan().SequenceCompareTo(b.Value);
                        });
                        foreach (var (key, value) in entries)
                        {
                            parts.Add(key);
                            parts.Add(value);
                        }
                        return parts.SelectMany(p => p).ToArray();
                    }
                case MessagePackType.Array:
                    {
                        var count = reader.ReadArrayHeader();
                        var parts = new List<byte[]> { reader.Sequence.Slice(start, reader.Position).ToArray() };
                        for (var i = 0; i < count; i++)
                        {
                            parts.Add(CanonicalizeValue(ref reader));
                        }
                        return parts.SelectMany(p => p).ToArray();
                    }
                default:
                    reader.Skip();
                    return reader.Sequence.Slice(start, reader.Position).ToArray();
            }
        }
    }
}
