using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Options;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Remotely.Server.Services;
using Remotely.Shared.Models;

namespace Remotely.Server.Tests
{
    [TestClass]
    public class ApiSecretValidationTests
    {
        private const string Secret = "S3cret-Value_123";

        private static string HashLikeOldServer(string secret)
        {
            var hasher = new PasswordHasher<RemotelyUser>(Options.Create(new PasswordHasherOptions
            {
                CompatibilityMode = PasswordHasherCompatibilityMode.IdentityV3,
                IterationCount = 10_000
            }));
            return hasher.HashPassword(null, secret);
        }

        [TestMethod]
        public void IsApiSecretValid_OldNet6Hash_CorrectSecret_ReturnsTrue()
        {
            Assert.IsTrue(DataService.IsApiSecretValid(HashLikeOldServer(Secret), Secret));
        }

        [TestMethod]
        public void IsApiSecretValid_OldNet6Hash_WrongSecret_ReturnsFalse()
        {
            Assert.IsFalse(DataService.IsApiSecretValid(HashLikeOldServer(Secret), "wrong"));
        }

        [TestMethod]
        public void IsApiSecretValid_CurrentDefaultHash_CorrectSecret_ReturnsTrue()
        {
            var hash = new PasswordHasher<RemotelyUser>().HashPassword(null, Secret);
            Assert.IsTrue(DataService.IsApiSecretValid(hash, Secret));
        }

        [TestMethod]
        public void IsApiSecretValid_CurrentDefaultHash_WrongSecret_ReturnsFalse()
        {
            var hash = new PasswordHasher<RemotelyUser>().HashPassword(null, Secret);
            Assert.IsFalse(DataService.IsApiSecretValid(hash, "wrong"));
        }

        [TestMethod]
        public void IsApiSecretValid_NullOrEmptyHash_ReturnsFalse()
        {
            Assert.IsFalse(DataService.IsApiSecretValid(null, Secret));
            Assert.IsFalse(DataService.IsApiSecretValid("", Secret));
        }
    }
}
