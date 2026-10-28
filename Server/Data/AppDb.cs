using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Metadata.Conventions;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;
using Microsoft.Extensions.Logging;
using Remotely.Shared.Models;
using Remotely.Shared.Utilities;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace Remotely.Server.Data
{
    public class AppDb : IdentityDbContext
    {
        private static readonly ValueComparer<string[]> _stringArrayComparer = new(
                    (a, b) => a.SequenceEqual(b),
                    c => c.Aggregate(0, (a, b) => HashCode.Combine(a, b.GetHashCode())),
                    c => c.ToArray());

        public DbSet<Alert> Alerts { get; set; }

        public DbSet<ApiToken> ApiTokens { get; set; }

        public DbSet<DeviceGroup> DeviceGroups { get; set; }
        public DbSet<Device> Devices { get; set; }
        public DbSet<EventLog> EventLogs { get; set; }
        public DbSet<InviteLink> InviteLinks { get; set; }
        public DbSet<Organization> Organizations { get; set; }
        public DbSet<ScriptRun> ScriptRuns { get; set; }
        public DbSet<SavedScript> SavedScripts { get; set; }
        public DbSet<ScriptSchedule> ScriptSchedules { get; set; }
        public DbSet<ScriptResult> ScriptResults { get; set; }
        public DbSet<SharedFile> SharedFiles { get; set; }
        public new DbSet<RemotelyUser> Users { get; set; }


        protected override void OnConfiguring(DbContextOptionsBuilder options)
        {
            options.ConfigureWarnings(x => x.Ignore(RelationalEventId.MultipleCollectionIncludeWarning));
            options.LogTo((message) => System.Diagnostics.Debug.Write(message));
        }

        protected override void ConfigureConventions(ModelConfigurationBuilder configurationBuilder)
        {
            base.ConfigureConventions(configurationBuilder);

            // No new migrations (P2): EF Core 8+ gives the TPH discriminator column a max length
            // (nvarchar(13) for RemotelyUsers.Discriminator); the migrations created it without one.
            configurationBuilder.Conventions.Remove(typeof(DiscriminatorLengthConvention));
        }

        protected override void OnModelCreating(ModelBuilder builder)
        {

            base.OnModelCreating(builder);

            // No new migrations (P2): the migrations created these key columns with max length 128. REQUIRED, do not
            // remove as redundant: Startup's Stores.MaxLengthForKeys = 128 never reaches this model, because the provider
            // contexts (SqlServerDbContext etc.) are constructed with IConfiguration only and never receive the app's
            // DbContextOptions/ApplicationServiceProvider, so Identity sees no IdentityOptions and defaults the keys to 450.
            // Without this pin the model differs from the migrations and Database.Migrate() in Startup throws (EF Core 9+).
            builder.Entity<IdentityUserLogin<string>>(b =>
            {
                b.Property(x => x.LoginProvider).HasMaxLength(128);
                b.Property(x => x.ProviderKey).HasMaxLength(128);
            });
            builder.Entity<IdentityUserToken<string>>(b =>
            {
                b.Property(x => x.LoginProvider).HasMaxLength(128);
                b.Property(x => x.Name).HasMaxLength(128);
            });

            builder.Entity<IdentityUser>().ToTable("RemotelyUsers");

            builder.Entity<Organization>()
                .HasMany(x => x.Devices)
                .WithOne(x => x.Organization);
            builder.Entity<Organization>()
                .HasMany(x => x.RemotelyUsers)
                .WithOne(x => x.Organization);
            builder.Entity<Organization>()
                .HasMany(x => x.EventLogs)
                .WithOne(x => x.Organization);
            builder.Entity<Organization>()
                .HasMany(x => x.DeviceGroups)
                .WithOne(x => x.Organization);
            builder.Entity<Organization>()
              .HasMany(x => x.InviteLinks)
              .WithOne(x => x.Organization);
            builder.Entity<Organization>()
              .HasMany(x => x.SharedFiles)
              .WithOne(x => x.Organization);
            builder.Entity<Organization>()
              .HasMany(x => x.ApiTokens)
              .WithOne(x => x.Organization);
            builder.Entity<Organization>()
                .HasMany(x => x.Alerts)
                .WithOne(x => x.Organization);
            builder.Entity<Organization>()
                .HasMany(x => x.ScriptRuns)
                .WithOne(x => x.Organization);
            builder.Entity<Organization>()
                .HasMany(x => x.ScriptSchedules)
                .WithOne(x => x.Organization);
            builder.Entity<Organization>()
                .HasMany(x => x.ScriptResults)
                .WithOne(x => x.Organization);
            builder.Entity<Organization>()
                .HasMany(x => x.SavedScripts)
                .WithOne(x => x.Organization);

            builder.Entity<RemotelyUser>()
               .HasOne(x => x.Organization)
               .WithMany(x => x.RemotelyUsers);

            builder.Entity<RemotelyUser>()
                .HasMany(x => x.DeviceGroups)
                .WithMany(x => x.Users);
            builder.Entity<RemotelyUser>()
                .HasMany(x => x.Alerts)
                .WithOne(x => x.User);
            builder.Entity<RemotelyUser>()
                .Property(x => x.UserOptions)
                .HasConversion(
                    x => JsonSerializer.Serialize(x, (JsonSerializerOptions)null),
                    x => JsonSerializer.Deserialize<RemotelyUserOptions>(x, (JsonSerializerOptions)null));
            builder.Entity<RemotelyUser>()
                .HasMany(x => x.SavedScripts)
                .WithOne(x => x.Creator);
            builder.Entity<RemotelyUser>()
                .HasMany(x => x.ScriptSchedules)
                .WithOne(x => x.Creator);

            builder.Entity<RemotelyUser>()
                .HasIndex(x => x.UserName);

            builder.Entity<Device>()
                .Property(x => x.Drives)
                .HasConversion(
                    x => JsonSerializer.Serialize(x, (JsonSerializerOptions)null),
                    x => JsonSerializer.Deserialize<List<Drive>>(x, (JsonSerializerOptions)null));
            builder.Entity<Device>()
               .Property(x => x.Drives)
               .Metadata.SetValueComparer(new ValueComparer<List<Drive>>(true));
            builder.Entity<Device>()
                .HasIndex(x => x.DeviceName);
            builder.Entity<Device>()
                .HasMany(x => x.Alerts)
                .WithOne(x => x.Device);
            builder.Entity<Device>()
                .HasMany(x => x.ScriptRuns)
                .WithMany(x => x.Devices);
            builder.Entity<Device>()
                .HasMany(x => x.ScriptRunsCompleted)
                .WithMany(x => x.DevicesCompleted);
            builder.Entity<Device>()
                .HasMany(x => x.ScriptSchedules)
                .WithMany(x => x.Devices);

            builder.Entity<DeviceGroup>()
                .HasMany(x => x.Devices);
            builder.Entity<DeviceGroup>()
                .HasMany(x => x.ScriptSchedules)
                .WithMany(x => x.DeviceGroups);

            builder.Entity<ScriptRun>()
                .HasMany(x => x.Devices)
                .WithMany(x => x.ScriptRuns);
            builder.Entity<ScriptRun>()
                .HasMany(x => x.DevicesCompleted)
                .WithMany(x => x.ScriptRunsCompleted);

            builder.Entity<ScriptResult>()
              .Property(x => x.ErrorOutput)
              .HasConversion(
                  x => JsonSerializer.Serialize(x, (JsonSerializerOptions)null),
                  x => JsonSerializer.Deserialize<string[]>(x, (JsonSerializerOptions)null))
              .Metadata
              .SetValueComparer(_stringArrayComparer);

            builder.Entity<ScriptResult>()
              .Property(x => x.StandardOutput)
              .HasConversion(
                  x => JsonSerializer.Serialize(x, (JsonSerializerOptions)null),
                  x => JsonSerializer.Deserialize<string[]>(x, (JsonSerializerOptions)null))
              .Metadata
              .SetValueComparer(_stringArrayComparer);

            builder.Entity<Alert>()
                .HasOne(x => x.User)
                .WithMany(x => x.Alerts);


            if (Database.ProviderName == "Microsoft.EntityFrameworkCore.Sqlite")
            {
                // SQLite does not have proper support for DateTimeOffset via Entity Framework Core, see the limitations
                // here: https://docs.microsoft.com/en-us/ef/core/providers/sqlite/limitations#query-limitations
                // To work around this, when the SQLite database provider is used, all model properties of type DateTimeOffset
                // use the DateTimeOffsetToBinaryConverter
                // Based on: https://github.com/aspnet/EntityFrameworkCore/issues/10784#issuecomment-415769754
                // This only supports millisecond precision, but should be sufficient for most use cases.
                foreach (var entityType in builder.Model.GetEntityTypes())
                {
                    // Without a primary key: e.g. IdentityPasskeyData (ASP.NET Core Identity 10), left over from the
                    // ignored passkey entity and removed when the model is finalized. Configuring it here would
                    // keep it in the model without a key and model validation would fail.
                    if (entityType.IsKeyless || entityType.FindPrimaryKey() is null)
                    {
                        continue;
                    }
                    var properties = entityType.ClrType.GetProperties().Where(p => p.PropertyType == typeof(DateTimeOffset)
                                                                                || p.PropertyType == typeof(DateTimeOffset?));
                    foreach (var property in properties)
                    {
                        builder
                             .Entity(entityType.Name)
                             .Property(property.Name)
                             .HasConversion(new DateTimeOffsetToStringConverter());
                    }
                }
            }

        }
    }
}
