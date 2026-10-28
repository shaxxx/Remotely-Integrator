#nullable enable

using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Remotely.Server.Data;
using System.Collections.Generic;

namespace Remotely.Server.Tests.Contract
{
    /// <summary>
    /// P2: no new EF migrations. The SQL Server model built by the current EF Core version must match
    /// the last migration snapshot (SqlServerDbContextModelSnapshot). No database connection is opened.
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
    }
}
