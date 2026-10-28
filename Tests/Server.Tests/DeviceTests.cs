using Microsoft.VisualStudio.TestTools.UnitTesting;
using Remotely.Shared.Models;
using System.Text.Json;

namespace Remotely.Server.Tests
{
    [TestClass]
    public class DeviceTests
    {
        [TestMethod]
        [DataRow(0d, 0d)]
        [DataRow(10d, 0d)]
        [DataRow(10d, -5d)]
        public void UsedStoragePercent_TotalNotPositive_ReturnsZero(double used, double total)
        {
            var device = new Device { UsedStorage = used, TotalStorage = total };

            Assert.AreEqual(0d, device.UsedStoragePercent);
            Assert.AreEqual(0d, device.UsedMemoryPercent);
        }

        [TestMethod]
        public void Serialize_ZeroTotals_DoesNotThrow()
        {
            var device = new Device { UsedStorage = 10, TotalStorage = 0, UsedMemory = 5, TotalMemory = 0 };

            var json = JsonSerializer.Serialize(device);

            Assert.IsFalse(string.IsNullOrEmpty(json));
        }

        [TestMethod]
        public void UsedStoragePercent_NormalValues_ReturnsRatio()
        {
            var device = new Device { UsedStorage = 50, TotalStorage = 200, UsedMemory = 1, TotalMemory = 4 };

            Assert.AreEqual(0.25, device.UsedStoragePercent, 1e-9);
            Assert.AreEqual(0.25, device.UsedMemoryPercent, 1e-9);
        }
    }
}
