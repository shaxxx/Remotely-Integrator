using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Remotely.Server.Services;
using System;
using System.Text;

namespace Remotely.Server.Auth
{
    public class ApiAuthorizationFilter : ActionFilterAttribute, IAuthorizationFilter
    {
        public ApiAuthorizationFilter(IDataService dataService)
        {
            DataService = dataService;
        }

        private IDataService DataService { get; }

        public void OnAuthorization(AuthorizationFilterContext context)
        {

            if (context.HttpContext.User.Identity.IsAuthenticated)
            {
                var orgID = DataService.GetUserByNameWithOrg(context.HttpContext.User.Identity.Name)?.OrganizationID;
                context.HttpContext.Request.Headers["OrganizationID"] = orgID;
                return;
            }

            if (context.HttpContext.Request.Headers.TryGetValue("Authorization", out var result) &&
                TryParseApiKey(result.ToString(), out var keyId, out var apiSecret) &&
                DataService.ValidateApiKey(
                    keyId,
                    apiSecret,
                    context.HttpContext.Request.Path,
                    context.HttpContext.Connection.RemoteIpAddress?.ToString()))
            {
                var orgID = DataService.GetApiKey(keyId)?.OrganizationID;
                context.HttpContext.Request.Headers["OrganizationID"] = orgID;
                return;
            }

            context.Result = new UnauthorizedResult();
        }

        /// <summary>
        /// Parses an API key from an Authorization header value. Accepts both
        /// "Basic base64(keyId:secret)" and the raw "keyId:secret" form.
        /// </summary>
        public static bool TryParseApiKey(string headerValue, out string keyId, out string secret)
        {
            keyId = null;
            secret = null;

            var value = headerValue?.Trim();
            if (string.IsNullOrEmpty(value))
            {
                return false;
            }

            var decoded = value;

            var schemeEnd = value.IndexOfAny(new[] { ' ', '	' });
            if (schemeEnd > 0 &&
                value.Substring(0, schemeEnd).Equals("Basic", StringComparison.OrdinalIgnoreCase))
            {
                var encoded = value.Substring(schemeEnd).Trim();
                if (encoded.Length > 0)
                {
                    var buffer = new byte[encoded.Length];
                    if (!Convert.TryFromBase64String(encoded, buffer, out var written))
                    {
                        return false;
                    }
                    try
                    {
                        decoded = new UTF8Encoding(false, true).GetString(buffer, 0, written);
                    }
                    catch (ArgumentException)
                    {
                        return false;
                    }
                }
            }

            var colon = decoded.IndexOf(':');
            if (colon < 0)
            {
                return false;
            }

            var id = decoded.Substring(0, colon).Trim();
            var sec = decoded.Substring(colon + 1).Trim();
            if (id.Length == 0 || sec.Length == 0)
            {
                return false;
            }

            keyId = id;
            secret = sec;
            return true;
        }
    }
}
