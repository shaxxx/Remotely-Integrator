using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Abstractions;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.AspNetCore.Routing;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Moq;
using Remotely.Server.Auth;
using Remotely.Server.Services;
using Remotely.Shared.Models;
using System;
using System.Collections.Generic;
using System.Net;
using System.Text;

namespace Remotely.Server.Tests
{
    [TestClass]
    public class ApiAuthorizationFilterTests
    {
        private Mock<IDataService> _dataService;

        [TestInitialize]
        public void Init()
        {
            _dataService = new Mock<IDataService>();
            _dataService
                .Setup(x => x.ValidateApiKey(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>()))
                .Returns(true);
            _dataService
                .Setup(x => x.GetApiKey(It.IsAny<string>()))
                .Returns(new ApiToken { OrganizationID = "org1" });
        }

        private AuthorizationFilterContext Run(string header)
        {
            var httpContext = new DefaultHttpContext();
            httpContext.Connection.RemoteIpAddress = IPAddress.Parse("10.0.0.5");
            if (header != null)
            {
                httpContext.Request.Headers["Authorization"] = header;
            }
            var context = new AuthorizationFilterContext(
                new ActionContext(httpContext, new RouteData(), new ActionDescriptor()),
                new List<IFilterMetadata>());
            new ApiAuthorizationFilter(_dataService.Object).OnAuthorization(context);
            return context;
        }

        private static string Basic(string value) =>
            "Basic " + Convert.ToBase64String(Encoding.UTF8.GetBytes(value));

        private void AssertAuthorized(AuthorizationFilterContext context)
        {
            Assert.IsNull(context.Result);
            Assert.AreEqual("org1", context.HttpContext.Request.Headers["OrganizationID"].ToString());
        }

        [TestMethod]
        public void RawKeyIdSecret_Valid_Authorizes()
        {
            AssertAuthorized(Run("key1:secret1"));
            _dataService.Verify(x => x.ValidateApiKey("key1", "secret1", It.IsAny<string>(), It.IsAny<string>()), Times.Once);
        }

        [TestMethod]
        public void BasicBase64_Valid_Authorizes()
        {
            AssertAuthorized(Run(Basic("key1:secret1")));
            _dataService.Verify(x => x.ValidateApiKey("key1", "secret1", It.IsAny<string>(), It.IsAny<string>()), Times.Once);
        }

        [TestMethod]
        public void BasicScheme_IsCaseInsensitive()
        {
            AssertAuthorized(Run("basic " + Basic("key1:secret1").Substring(6)));
            _dataService.Verify(x => x.ValidateApiKey("key1", "secret1", It.IsAny<string>(), It.IsAny<string>()), Times.Once);
        }

        [TestMethod]
        public void Secret_WithBase64Characters_Passed()
        {
            AssertAuthorized(Run("key1:ab+/cd=="));
            _dataService.Verify(x => x.ValidateApiKey("key1", "ab+/cd==", It.IsAny<string>(), It.IsAny<string>()), Times.Once);
        }

        [TestMethod]
        public void SplitsOnFirstColonOnly()
        {
            AssertAuthorized(Run("key1:a:b"));
            _dataService.Verify(x => x.ValidateApiKey("key1", "a:b", It.IsAny<string>(), It.IsAny<string>()), Times.Once);
        }

        [TestMethod]
        public void Whitespace_IsTrimmed()
        {
            AssertAuthorized(Run("  key1 : secret1 "));
            _dataService.Verify(x => x.ValidateApiKey("key1", "secret1", It.IsAny<string>(), It.IsAny<string>()), Times.Once);
        }

        [TestMethod]
        public void MissingHeader_Unauthorized()
        {
            Assert.IsInstanceOfType(Run(null).Result, typeof(UnauthorizedResult));
        }

        [TestMethod]
        public void WrongSecret_Unauthorized()
        {
            _dataService
                .Setup(x => x.ValidateApiKey(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>()))
                .Returns(false);
            Assert.IsInstanceOfType(Run("key1:wrong").Result, typeof(UnauthorizedResult));
        }

        [TestMethod]
        public void InvalidBase64_Unauthorized()
        {
            Assert.IsInstanceOfType(Run("Basic %%%").Result, typeof(UnauthorizedResult));
            _dataService.Verify(x => x.ValidateApiKey(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>()), Times.Never);
        }

        [TestMethod]
        public void NoColon_Unauthorized()
        {
            Assert.IsInstanceOfType(Run("key1secret1").Result, typeof(UnauthorizedResult));
            _dataService.Verify(x => x.ValidateApiKey(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>()), Times.Never);
        }
    }
}
