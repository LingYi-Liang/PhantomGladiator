// Entry point for tools/test_update_install.py, compiled together with desktop/PhantomGladiator.cs and
// desktop/AppUpdate.cs: the real UpdateClient checks a local fake server, downloads and verifies the new package
// and installs it over the folder this exe runs from. The package's exe is this same test exe: started with
// --wait-for, it waits for the old process, cleans up the way the app does at start, and writes a report to
// PG_TEST_REPORT. C# 5, like the app.
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;

namespace PhantomGladiator
{
    static class UpdateInstallTest
    {
        static string State(string status)
        {
            var dir = Paths.AppDir;
            var entries = Directory.GetFileSystemEntries(dir, "*", SearchOption.AllDirectories)
                .Select(p => p.Substring(dir.Length + 1).Replace('\\', '/')).OrderBy(p => p, StringComparer.Ordinal);
            var updates = Directory.Exists(Paths.In("updates"))
                ? Directory.GetFileSystemEntries(Paths.In("updates")).Select(Path.GetFileName).OrderBy(p => p, StringComparer.Ordinal)
                : Enumerable.Empty<string>();
            return status + "\n" + string.Join("\n", entries) + "\nupdates=" + string.Join(",", updates)
                + "\nversion=" + BuildInfo.Load().AppVersion;
        }

        static int Main(string[] args)
        {
            var report = Environment.GetEnvironmentVariable("PG_TEST_REPORT");
            int pid;
            if (args.Length >= 2 && args[0] == "--wait-for" && int.TryParse(args[1], out pid))
            {
                try { using (var old = Process.GetProcessById(pid)) old.WaitForExit(30000); }
                catch (ArgumentException) { }
                UpdateClient.CleanUp();
                File.WriteAllText(report, State("ok"));
                return 0;
            }
            try
            {
                var client = new UpdateClient(BuildInfo.Load());
                var found = client.Check("zh");
                if ((bool)found["latest"]) throw new Exception("no newer version found");
                client.Download("github", (done, size, speed) => { });
                client.Verify();
                client.Install();
                return 0;
            }
            catch (Exception e)
            {
                File.WriteAllText(report, "failed: " + e.GetType().Name + ": " + e.Message + "\n" + State(""));
                return 1;
            }
        }
    }
}
