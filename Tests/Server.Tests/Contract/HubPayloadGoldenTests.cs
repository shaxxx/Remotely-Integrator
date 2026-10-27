using Microsoft.AspNetCore.SignalR;
using Microsoft.AspNetCore.SignalR.Protocol;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System;
using System.Buffers;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace Remotely.Server.Tests.Contract
{
    /// <summary>
    /// SignalR MessagePack payloads of every hub method (client to server) and every server to client
    /// invocation, as written by MessagePackHubProtocol with its default options (the server calls
    /// AddMessagePackProtocol() without options).
    /// </summary>
    [TestClass]
    public class HubPayloadGoldenTests
    {
        private const string InvocationId = "1";

        public sealed class PayloadCase
        {
            public PayloadCase(string goldenName, string target, Type[] parameterTypes)
            {
                GoldenName = goldenName;
                Target = target;
                ParameterTypes = parameterTypes;
            }

            public string GoldenName { get; }
            public string Target { get; }
            public Type[] ParameterTypes { get; }

            /// <summary>Argument i is SampleFactory.Create(type, seed: i + 1).</summary>
            public object[] CreateArguments()
            {
                return ParameterTypes.Select((type, i) => SampleFactory.Create(type, i + 1)).ToArray();
            }
        }

        /// <summary>hub-&lt;Hub&gt;-&lt;Method&gt;, target "&lt;Hub&gt;.&lt;Method&gt;".</summary>
        public static IReadOnlyList<PayloadCase> HubMethodCases()
        {
            return HubSignatureTests.GetHubMethods()
                .Select(x => new PayloadCase(
                    $"hub-{x.Hub.Name}-{x.Method.Name}",
                    $"{x.Hub.Name}.{x.Method.Name}",
                    x.Method.GetParameters().Select(p => p.ParameterType).ToArray()))
                .ToArray();
        }

        /// <summary>client-&lt;Name&gt;-&lt;i&gt; (i = index within the same Name in ClientInvocationCatalog.All), target "&lt;Name&gt;".</summary>
        public static IReadOnlyList<PayloadCase> ClientInvocationCases()
        {
            return ClientInvocationCatalog.All
                .GroupBy(e => e.Name, StringComparer.Ordinal)
                .SelectMany(group => group.Select((e, i) => new PayloadCase($"client-{e.Name}-{i}", e.Name, e.ArgTypes)))
                .ToArray();
        }

        public static byte[] Serialize(PayloadCase payloadCase)
        {
            var protocol = new MessagePackHubProtocol();
            var writer = new ArrayBufferWriter<byte>();
            protocol.WriteMessage(new InvocationMessage(InvocationId, payloadCase.Target, payloadCase.CreateArguments()), writer);
            return writer.WrittenSpan.ToArray();
        }

        [TestMethod]
        public void HubMethodPayloads_MatchBaseline()
        {
            var cases = HubMethodCases();
            Assert.AreEqual(cases.Count, cases.Select(c => c.GoldenName).Distinct(StringComparer.Ordinal).Count(), "Overloaded hub methods would share a golden file.");

            GoldenFile.AssertAll(cases, c => c.GoldenName, c => GoldenFile.AssertMatches(c.GoldenName, Serialize(c)));
        }

        [TestMethod]
        public void ClientInvocationPayloads_MatchBaseline()
        {
            GoldenFile.AssertAll(ClientInvocationCases(), c => c.GoldenName, c => GoldenFile.AssertMatches(c.GoldenName, Serialize(c)));
        }

        [TestMethod]
        public void GoldenPayloads_ParseToSamples()
        {
            var cases = HubMethodCases().Concat(ClientInvocationCases()).ToArray();

            GoldenFile.AssertAll(cases, c => GoldenFile.GetPath(c.GoldenName), c =>
            {
                // In update mode the files are being (re)written by the other tests, in no guaranteed order.
                var bytes = GoldenFile.IsUpdateMode ? Serialize(c) : GoldenFile.Read(c.GoldenName);

                var protocol = new MessagePackHubProtocol();
                var input = new ReadOnlySequence<byte>(bytes);
                Assert.IsTrue(protocol.TryParseMessage(ref input, new FixedBinder(c.Target, c.ParameterTypes), out var message), "TryParseMessage returned false.");
                Assert.IsTrue(input.IsEmpty, $"{input.Length} unread byte(s) after the message.");

                if (message is InvocationBindingFailureMessage failure)
                {
                    throw failure.BindingFailure.SourceException;
                }

                var invocation = message as InvocationMessage;
                Assert.IsNotNull(invocation, $"Expected InvocationMessage, got {message?.GetType().Name}.");
                Assert.AreEqual(InvocationId, invocation.InvocationId);
                Assert.AreEqual(c.Target, invocation.Target);
                Assert.AreEqual(c.ParameterTypes.Length, invocation.Arguments.Length);

                var samples = c.CreateArguments();
                for (var i = 0; i < samples.Length; i++)
                {
                    var expected = JsonSerializer.Serialize(samples[i], c.ParameterTypes[i]);
                    var actual = JsonSerializer.Serialize(invocation.Arguments[i], c.ParameterTypes[i]);
                    Assert.AreEqual(expected, actual, $"Argument {i} ({HubSignatureTests.FormatType(c.ParameterTypes[i])}).");
                }
            });

            GoldenFile.AssertNoOrphans("hub-", cases.Select(c => c.GoldenName).Append("hub-signatures"));
            GoldenFile.AssertNoOrphans("client-", cases.Select(c => c.GoldenName));
        }

        private sealed class FixedBinder : IInvocationBinder
        {
            private readonly string _target;
            private readonly Type[] _parameterTypes;

            public FixedBinder(string target, Type[] parameterTypes)
            {
                _target = target;
                _parameterTypes = parameterTypes;
            }

            public IReadOnlyList<Type> GetParameterTypes(string methodName)
            {
                if (!string.Equals(methodName, _target, StringComparison.Ordinal))
                {
                    throw new InvalidOperationException($"Unexpected target '{methodName}', expected '{_target}'.");
                }
                return _parameterTypes;
            }

            public Type GetReturnType(string invocationId)
            {
                throw new NotSupportedException("Golden payloads contain only invocation messages.");
            }

            public Type GetStreamItemType(string streamId)
            {
                throw new NotSupportedException("Golden payloads contain only invocation messages.");
            }
        }
    }
}
