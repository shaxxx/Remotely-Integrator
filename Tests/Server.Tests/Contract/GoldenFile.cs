using Microsoft.VisualStudio.TestTools.UnitTesting;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;

namespace Remotely.Server.Tests.Contract
{
    /// <summary>
    /// Golden files for the protocol contract: Contract/Golden/&lt;name&gt;.bin next to the test sources.
    /// With REMOTELY_UPDATE_GOLDEN=1 the files are (re)written and the assertion passes.
    /// Without it the bytes are compared exactly and a missing file fails the test.
    /// </summary>
    public static class GoldenFile
    {
        public const string UpdateVariable = "REMOTELY_UPDATE_GOLDEN";

        public const string Extension = ".bin";

        public static bool IsUpdateMode => Environment.GetEnvironmentVariable(UpdateVariable) == "1";

        /// <summary>
        /// The Golden directory next to the calling source file. The path comes from [CallerFilePath],
        /// so the tests must run from a source checkout (no PathMap/deterministic source paths).
        /// </summary>
        public static string GetDirectory([CallerFilePath] string callerPath = "")
        {
            return Path.Combine(Path.GetDirectoryName(callerPath), "Golden");
        }

        public static string GetPath(string name, [CallerFilePath] string callerPath = "")
        {
            return Path.Combine(GetDirectory(callerPath), name + Extension);
        }

        public static void AssertMatches(string name, byte[] actual, [CallerFilePath] string callerPath = "")
        {
            if (actual is null)
            {
                throw new ArgumentNullException(nameof(actual));
            }

            var path = GetPath(name, callerPath);

            if (IsUpdateMode)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(path));
                if (!File.Exists(path) || !File.ReadAllBytes(path).AsSpan().SequenceEqual(actual))
                {
                    File.WriteAllBytes(path, actual);
                }
                return;
            }

            var expected = Read(name, callerPath);
            if (expected.AsSpan().SequenceEqual(actual))
            {
                return;
            }

            var length = Math.Min(expected.Length, actual.Length);
            var offset = 0;
            while (offset < length && expected[offset] == actual[offset])
            {
                offset++;
            }

            Assert.Fail(
                $"Golden file mismatch: {path}. " +
                $"Expected {expected.Length} bytes, actual {actual.Length} bytes, first difference at offset {offset}.");
        }

        /// <summary>
        /// Reads a golden file; fails with a message naming the file if it does not exist.
        /// </summary>
        public static byte[] Read(string name, [CallerFilePath] string callerPath = "")
        {
            var path = GetPath(name, callerPath);
            if (!File.Exists(path))
            {
                Assert.Fail($"Golden file not found: {path}. Run the tests with {UpdateVariable}=1 to create it.");
            }
            return File.ReadAllBytes(path);
        }

        /// <summary>
        /// Fails if the Golden directory holds files with the given prefix that no test produces
        /// (for example a golden file left behind by a removed hub method or DTO).
        /// </summary>
        public static void AssertNoOrphans(string prefix, IEnumerable<string> expectedNames, [CallerFilePath] string callerPath = "")
        {
            var directory = GetDirectory(callerPath);
            if (!Directory.Exists(directory))
            {
                return;
            }

            var expected = new HashSet<string>(expectedNames, StringComparer.Ordinal);
            var orphans = Directory.GetFiles(directory, prefix + "*" + Extension)
                .Select(f => Path.GetFileNameWithoutExtension(f))
                .Where(n => !expected.Contains(n))
                .OrderBy(n => n, StringComparer.Ordinal)
                .ToArray();

            if (orphans.Length > 0)
            {
                Assert.Fail($"Golden files without a producing test in {directory}: {string.Join(", ", orphans.Select(n => n + Extension))}");
            }
        }

        /// <summary>
        /// Runs an assertion per item and reports all failures together, so one run shows every broken golden file.
        /// </summary>
        public static void AssertAll<T>(IEnumerable<T> items, Func<T, string> describe, Action<T> assert)
        {
            var failures = new List<string>();
            foreach (var item in items)
            {
                try
                {
                    assert(item);
                }
                catch (Exception ex) when (ex is not AssertInconclusiveException)
                {
                    var message = $"{describe(item)}: {ex.GetType().Name}: {ex.Message}";
                    for (var inner = ex.InnerException; inner is not null; inner = inner.InnerException)
                    {
                        message += $" ---> {inner.GetType().Name}: {inner.Message}";
                    }
                    failures.Add(message);
                }
            }

            if (failures.Count > 0)
            {
                Assert.Fail($"{failures.Count} failure(s):{Environment.NewLine}{string.Join(Environment.NewLine, failures)}");
            }
        }
    }
}
