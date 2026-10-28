#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Remotely.Server.Data;
using System.Collections.Generic;

namespace Remotely.Server.Tests.Contract
{
    /// <summary>
    /// P2: no new EF migrations. The model of each provider context built by the current EF Core version
    /// must match that provider's last migration snapshot. No database connection is opened.
    /// </summary>
    [TestClass]
    public class SchemaTests
    {
        [TestMethod]
        public void SqlServerModel_HasNoPendingChanges()
        {
            var config = new ConfigurationBuilder()
                .AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["ConnectionStrings:SQLServer"] = "Server=.;Database=x;TrustServerCertificate=True"
                })
                .Build();

            using var ctx = new SqlServerDbContext(config);
            Assert.IsFalse(ctx.Database.HasPendingModelChanges());
        }

        [TestMethod]
        public void SqliteModel_HasNoPendingChanges()
        {
            var config = new ConfigurationBuilder()
                .AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["ConnectionStrings:SQLite"] = "DataSource=x.db"
                })
                .Build();

            using var ctx = new SqliteDbContext(config);
            Assert.IsFalse(ctx.Database.HasPendingModelChanges());
        }

        [TestMethod]
        public void PostgreSqlModel_HasNoPendingChanges()
        {
            var config = new ConfigurationBuilder()
                .AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["ConnectionStrings:PostgreSQL"] = "Host=localhost;Database=x;Username=x"
                })
                .Build();

            using var ctx = new PostgreSqlDbContext(config);
            Assert.IsFalse(ctx.Database.HasPendingModelChanges());
        }
    }
}
