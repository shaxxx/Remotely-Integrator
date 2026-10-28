using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Threading.Tasks;

namespace Remotely.Server.Tests.Contract
{
    /// <summary>
    /// P4: for the same Length and LastWriteTimeUtc, the static file middleware must return the same
    /// ETag as production, otherwise the old agents download the whole zip again.
    /// </summary>
    [TestClass]
    public class StaticFileETagTests
    {
        [TestMethod]
        [DataRow("Remotely-Win10-x64.zip", 115664673L, 637701417140000000L, "\"1d7c3f840097221\"")]
        [DataRow("Remotely-Win10-x86.zip", 105480487L, 637701417160000000L, "\"1d7c3f84e574327\"")]
        public async Task ContentZip_ETag_MatchesProduction(string fileName, long length, long lastWriteUtcTicks, string expectedETag)
        {
            var root = Path.Combine(Path.GetTempPath(), "RemotelyETag_" + Guid.NewGuid().ToString("N"));
            var contentDir = Path.Combine(root, "Content");
            Directory.CreateDirectory(contentDir);
            try
            {
                var filePath = Path.Combine(contentDir, fileName);
                using (var fs = new FileStream(filePath, FileMode.Create, FileAccess.Write))
                {
                    fs.SetLength(length);
                }
                File.SetLastWriteTimeUtc(filePath, new DateTime(lastWriteUtcTicks, DateTimeKind.Utc));

                var builder = WebApplication.CreateBuilder(new WebApplicationOptions { ContentRootPath = root, WebRootPath = root });
                builder.WebHost.UseTestServer();
                await using var app = builder.Build();
                Startup.ConfigureStaticFiles(app, app.Environment);
                await app.StartAsync();
                using var client = app.GetTestClient();

                using (var request = new HttpRequestMessage(HttpMethod.Head, "/Content/" + fileName))
                using (var response = await client.SendAsync(request))
                {
                    Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
                    Assert.AreEqual(expectedETag, response.Headers.ETag?.ToString());
                }

                using (var request = new HttpRequestMessage(HttpMethod.Head, "/Content/" + fileName))
                {
                    request.Headers.TryAddWithoutValidation("If-None-Match", expectedETag);
                    using var response = await client.SendAsync(request);
                    Assert.AreEqual(HttpStatusCode.NotModified, response.StatusCode);
                }
            }
            finally
            {
                try { Directory.Delete(root, true); } catch (Exception ex) when (ex is IOException || ex is UnauthorizedAccessException) { }
            }
        }
    }
}
