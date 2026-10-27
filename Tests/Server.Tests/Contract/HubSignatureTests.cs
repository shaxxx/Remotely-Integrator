using Microsoft.VisualStudio.TestTools.UnitTesting;
using Remotely.Server.Hubs;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Text;

namespace Remotely.Server.Tests.Contract
{
    [TestClass]
    public class HubSignatureTests
    {
        public static IReadOnlyList<Type> HubTypes { get; } = new[] { typeof(AgentHub), typeof(CasterHub), typeof(ViewerHub) };

        private static readonly HashSet<string> _excludedMethods = new(StringComparer.Ordinal)
        {
            "OnConnectedAsync",
            "OnDisconnectedAsync",
            "Dispose"
        };

        /// <summary>
        /// Public instance methods declared on each hub type itself (not inherited), without
        /// OnConnectedAsync, OnDisconnectedAsync and Dispose. Property accessors are not hub methods.
        /// Sorted by hub name, then method name (ordinal), independent of reflection order.
        /// </summary>
        public static IReadOnlyList<(Type Hub, MethodInfo Method)> GetHubMethods()
        {
            return HubTypes
                .SelectMany(hub => hub
                    .GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
                    .Where(m => !m.IsSpecialName && !_excludedMethods.Contains(m.Name))
                    .Select(m => (Hub: hub, Method: m)))
                .OrderBy(x => x.Hub.Name, StringComparer.Ordinal)
                .ThenBy(x => x.Method.Name, StringComparer.Ordinal)
                .ToArray();
        }

        /// <summary>
        /// Type.FullName with readable generics: System.Threading.Tasks.Task&lt;System.Boolean&gt;, System.String[].
        /// </summary>
        public static string FormatType(Type type)
        {
            if (type.IsArray)
            {
                return FormatType(type.GetElementType()) + "[" + new string(',', type.GetArrayRank() - 1) + "]";
            }

            if (type.IsByRef)
            {
                return FormatType(type.GetElementType()) + "&";
            }

            if (type.IsGenericType)
            {
                var definition = type.GetGenericTypeDefinition().FullName;
                var tick = definition.IndexOf('`');
                if (tick >= 0)
                {
                    definition = definition.Substring(0, tick);
                }
                return definition + "<" + string.Join(",", type.GetGenericArguments().Select(FormatType)) + ">";
            }

            return type.FullName ?? type.Name;
        }

        public static string FormatSignature(Type hub, MethodInfo method)
        {
            var parameters = string.Join(",", method.GetParameters().Select(p => FormatType(p.ParameterType)));
            return $"{hub.Name}.{method.Name}({parameters})->{FormatType(method.ReturnType)}";
        }

        [TestMethod]
        public void HubSignatures_MatchBaseline()
        {
            var lines = GetHubMethods()
                .Select(x => FormatSignature(x.Hub, x.Method))
                .OrderBy(line => line, StringComparer.Ordinal);

            // "\n" (not Environment.NewLine) so the bytes do not depend on the OS.
            var text = string.Join("\n", lines) + "\n";

            GoldenFile.AssertMatches("hub-signatures", Encoding.UTF8.GetBytes(text));
        }
    }
}
