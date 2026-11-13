// Entry point for tools/test_update_install.py, compiled together with desktop/PhantomGladiator.cs and
// desktop/AppUpdate.cs: the real UpdateClient checks a local fake server (or, with PG_TEST_ROLLBACK, picks that older
// version), downloads and verifies the package and installs it over the folder this exe runs from. The package's exe is this same test exe: started with
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
                + "\nversion=" + BuildInfo.Load().AppVersion + "\nbuild=" + BuildInfo.Load().ModBuild + "\ndirectory=" + dir;
        }

        static int Main(string[] args)
        {
            if (args.Length == 1 && args[0] == "--install-components")
            {
                try
                {
                    var game = new GameInfo { Root = Path.Combine(Paths.AppDir, "test-game") };
                    Installer.Install(game, (step, ratio) => { });
                    return 0;
                }
                catch (Exception e)
                {
                    Console.Error.WriteLine(e.Message);
                    return 1;
                }
            }
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
                var client = new UpdateClient(BuildInfo.Load(),false,Environment.GetEnvironmentVariable("PG_TEST_RELEASE_API"));
                var back = Environment.GetEnvironmentVariable("PG_TEST_ROLLBACK");
                var found = string.IsNullOrEmpty(back) ? client.Check("zh") : client.SelectVersion(back, "zh");
                if ((bool)found["latest"]) throw new Exception("no newer version found");
                var line = Environment.GetEnvironmentVariable("PG_TEST_LINE");
                client.Download(string.IsNullOrEmpty(line) ? "github" : line, (done, size, speed) => { });
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
