using Microsoft.Extensions.Caching.Memory;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Moq;
using Remotely.Server.API;
using Remotely.Server.Hubs;
using Remotely.Server.Services;
using Remotely.Shared.Enums;
using Remotely.Shared.Models;
using System;
using System.Threading.Tasks;

namespace Remotely.Tests
{
    [TestClass]
    public class ScriptResultsControllerTests
    {
        [TestMethod]
        public async Task Post_ApiResult_IsRecordedForExecuteCommand()
        {
            var requestId = Guid.NewGuid().ToString();

            await CreateController().Post(new ScriptResult
            {
                ID = "result-1",
                InputType = ScriptInputType.Api,
                SenderConnectionID = requestId
            });

            Assert.IsTrue(AgentHub.ApiScriptResults.TryGetValue(requestId, out var resultId));
            Assert.AreEqual("result-1", resultId);
        }

        [TestMethod]
        public async Task Post_TerminalResult_IsNotRecorded()
        {
            var connectionId = Guid.NewGuid().ToString();

            await CreateController().Post(new ScriptResult
            {
                ID = "result-2",
                InputType = ScriptInputType.Terminal,
                SenderConnectionID = connectionId
            });

            Assert.IsFalse(AgentHub.ApiScriptResults.TryGetValue(connectionId, out _));
        }

        private static ScriptResultsController CreateController()
        {
            return new ScriptResultsController(new Mock<IDataService>().Object, new Mock<IEmailSenderEx>().Object);
        }
    }
}
