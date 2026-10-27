using Remotely.Shared.Enums;
using Remotely.Shared.Models;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;

namespace Remotely.Server.Tests.Contract
{
    /// <summary>
    /// Every invocation the server sends to clients (agents, desktop casters, browser viewers) with
    /// SendAsync("Name", ...) in Server/**, as of tag v2022.09.16.1006.
    /// </summary>
    /// <remarks>
    /// ArgTypes are the static types of the argument expressions at the call site. The serializer writes
    /// each argument with its runtime type; that equals the static type for every entry, except that a
    /// non-null Nullable&lt;T&gt; is boxed to T (same bytes as T, and null is written as nil).
    /// One entry per distinct argument shape. <see cref="All"/> is sorted by Name, then by the argument
    /// type list (ordinal); golden file client-&lt;Name&gt;-&lt;i&gt; uses the index i within the same Name.
    /// </remarks>
    public static class ClientInvocationCatalog
    {
        public static IReadOnlyList<(string Name, Type[] ArgTypes)> All { get; } = CallSites()
            .OrderBy(e => e.Name, StringComparer.Ordinal)
            .ThenBy(e => string.Join(",", e.ArgTypes.Select(HubSignatureTests.FormatType)), StringComparer.Ordinal)
            .ToArray();

        private static IEnumerable<(string Name, Type[] ArgTypes)> CallSites()
        {
            // Server/Hubs/AgentHub.cs:66 (Clients.Caller), Server/Hubs/CircuitConnection.cs:284 (agent)
            yield return ("Chat", new[] { typeof(string), typeof(string), typeof(string), typeof(bool), typeof(string) });

            // Server/Hubs/ViewerHub.cs:92 (agent)
            yield return ("ChangeWindowsSession", new[] { typeof(string), typeof(string), typeof(int) });

            // Server/Hubs/AgentHub.cs:259, Server/Hubs/CasterHub.cs:136, Server/API/LoginController.cs:80, Server/Areas/Identity/Pages/Account/Logout.cshtml:18 (viewer)
            yield return ("ConnectionFailed", Type.EmptyTypes);

            // Server/Hubs/CasterHub.cs:141 (viewer)
            yield return ("ConnectionRequestDenied", Type.EmptyTypes);

            // Server/Hubs/CasterHub.cs:151 (agent)
            yield return ("CtrlAltDel", Type.EmptyTypes);

            // Server/Hubs/CircuitConnection.cs:109 (agent)
            yield return ("DeleteLogs", Type.EmptyTypes);

            // Server/API/LoginController.cs:79, Server/Areas/Identity/Pages/Account/Logout.cshtml:17 (caster)
            yield return ("Disconnect", new[] { typeof(string) });

            // Server/Hubs/CircuitConnection.cs:127 (agent)
            yield return ("ExecuteCommand", new[] { typeof(ScriptingShell), typeof(string), typeof(string), typeof(string), typeof(string) });

            // Server/API/AgentUpdateController.cs:147 (agent): shell sent as the string "cmd", and only 4 arguments.
            yield return ("ExecuteCommand", new[] { typeof(string), typeof(string), typeof(string), typeof(string) });

            // Server/API/ScriptingController.cs:83 (agent)
            yield return ("ExecuteCommandFromApi", new[] { typeof(ScriptingShell), typeof(string), typeof(string), typeof(string), typeof(string) });

            // Server/Hubs/CircuitConnection.cs:158 (agent)
            yield return ("GetLogs", new[] { typeof(string) });

            // Server/Hubs/CircuitConnection.cs:146 (agent): forward is bool?.
            yield return ("GetPowerShellCompletions", new[] { typeof(string), typeof(int), typeof(CompletionIntent), typeof(bool?), typeof(string) });

            // Server/Hubs/ViewerHub.cs:223 (caster)
            yield return ("GetScreenCast", new[] { typeof(string), typeof(string), typeof(bool), typeof(bool), typeof(bool), typeof(string) });

            // Server/Hubs/CasterHub.cs:163 (viewer)
            yield return ("ReceiveIceCandidate", new[] { typeof(string), typeof(int), typeof(string) });

            // Server/Hubs/ViewerHub.cs:127 (caster)
            yield return ("ReceiveIceCandidate", new[] { typeof(string), typeof(int), typeof(string), typeof(string) });

            // Server/Hubs/ViewerHub.cs:132 (caster)
            yield return ("ReceiveRtcAnswer", new[] { typeof(string), typeof(string) });

            // Server/Hubs/CasterHub.cs:173 (viewer)
            yield return ("ReceiveRtcOffer", new[] { typeof(string), typeof(IceServerModel[]) });

            // Server/Hubs/CasterHub.cs:118 (viewer)
            yield return ("Reconnecting", Type.EmptyTypes);

            // Server/Hubs/CircuitConnection.cs:193, Server/Pages/ServerConfig.razor.cs:406 (agent)
            yield return ("ReinstallAgent", Type.EmptyTypes);

            // Server/Hubs/CasterHub.cs:94 (viewer)
            yield return ("RelaunchedScreenCasterReady", new[] { typeof(string) });

            // Server/Hubs/CircuitConnection.cs:223, Server/API/RemoteControlController.cs:104 (agent)
            yield return ("RemoteControl", new[] { typeof(string), typeof(string) });

            // Server/Hubs/ViewerHub.cs:240 (caster)
            yield return ("RequestScreenCast", new[] { typeof(string), typeof(string), typeof(bool), typeof(bool) });

            // Server/Hubs/ViewerHub.cs:239 (viewer, Clients.Caller)
            yield return ("RequestingScreenCast", Type.EmptyTypes);

            // Server/Hubs/CasterHub.cs:119 (agent): the viewer list is RCSessionInfo.ViewerList, a ConcurrentList<string> (NuGet ConcurrentList).
            yield return ("RestartScreenCaster", new[] { typeof(ConcurrentList<string>), typeof(string), typeof(string) });

            // Server/Hubs/CircuitConnection.cs:259 (agent): savedScriptId is Guid.
            yield return ("RunScript", new[] { typeof(Guid), typeof(int), typeof(string), typeof(ScriptInputType), typeof(string) });

            // Server/Hubs/AgentHub.cs:77 (agent, Clients.Caller): ScriptRun.SavedScriptId is Guid?.
            yield return ("RunScript", new[] { typeof(Guid?), typeof(int), typeof(string), typeof(ScriptInputType), typeof(string) });

            // Server/Hubs/CasterHub.cs:112 (viewer)
            yield return ("ScreenCasterDisconnected", Type.EmptyTypes);

            // Server/Hubs/CasterHub.cs:156 (viewer)
            yield return ("SendDtoToBrowser", new[] { typeof(byte[]) });

            // Server/Hubs/ViewerHub.cs:107 (caster)
            yield return ("SendDtoToClient", new[] { typeof(byte[]), typeof(string) });

            // Server/Hubs/ViewerHub.cs:146, Server/Hubs/ViewerHub.cs:155 (viewer, Clients.Caller)
            yield return ("SessionIDNotFound", Type.EmptyTypes);

            // Server/Hubs/CasterHub.cs:146, Server/Hubs/ViewerHub.cs:180 (viewer)
            yield return ("ShowMessage", new[] { typeof(string) });

            // Server/Hubs/CircuitConnection.cs:312 (agent)
            yield return ("TransferFileFromBrowserToAgent", new[] { typeof(string), typeof(string[]), typeof(string), typeof(string) });

            // Server/Hubs/CircuitConnection.cs:331 (agent)
            yield return ("TriggerHeartbeat", Type.EmptyTypes);

            // Server/Hubs/ViewerHub.cs:233 (viewer, Clients.Caller)
            yield return ("Unauthorized", Type.EmptyTypes);

            // Server/Hubs/AgentHub.cs:299 (Clients.Caller), Server/Hubs/CircuitConnection.cs:340, Server/API/AgentUpdateController.cs:153 (agent)
            yield return ("UninstallAgent", Type.EmptyTypes);

            // Server/Hubs/CircuitConnection.cs:379 (agent)
            yield return ("UploadFiles", new[] { typeof(string), typeof(List<string>), typeof(string) });

            // Server/Hubs/ViewerHub.cs:119 (caster)
            yield return ("ViewerDisconnected", new[] { typeof(string) });

            // Server/Hubs/CasterHub.cs:55 (viewer)
            yield return ("ViewerRemoved", Type.EmptyTypes);
        }
    }
}
