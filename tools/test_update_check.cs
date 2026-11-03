// Entry point for tools/test_update_check.py, compiled together with desktop/PhantomGladiator.cs: the real
// UpdateClient.Check against a local fake server. Every source is asked at once and the newest usable
// manifest wins. C# 5, like the app.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;

namespace PhantomGladiator
{
    static class UpdateCheckTest
    {
        static int failures;

        static void Expect(bool ok, string what)
        {
            Console.WriteLine((ok ? "PASS " : "FAIL ") + what);
            if (!ok) failures++;
        }

        static Dictionary<string, object> Check(string server, string app, params string[] names)
        {
            var build = new BuildInfo { AppVersion = app };
            foreach (var name in names) build.Manifests.Add(name + "|" + server + "/" + name + ".json");
            return new UpdateClient(build).Check("zh");
        }

        static int Main(string[] args)
        {
            var server = args[0];

            // A stale copy first and the current one last (jsDelivr after v0.37.0): the current one wins.
            var r = Check(server, "0.37.0", "old", "new");
            Expect(!(bool)r["latest"] && (string)r["version"] == "0.37.1", "a stale first source does not hide a newer release");

            // Two sources that never answer cost one timeout, not two.
            var clock = Stopwatch.StartNew();
            r = Check(server, "0.37.0", "slow", "slow2", "new");
            Expect((string)r["version"] == "0.37.1" && clock.ElapsedMilliseconds < 9000,
                "sources are asked at once (" + clock.ElapsedMilliseconds + " ms with two timeouts)");

            r = Check(server, "0.37.1", "old", "new");
            Expect((bool)r["latest"], "already on the newest version");

            r = Check(server, "0.37.0", "new", "new2");
            Expect((string)r["date"] == "first", "on a tie the source listed first is kept");

            // Broken JSON and a manifest without download lines are skipped, even when it names a higher version.
            r = Check(server, "0.37.0", "bad", "partial", "new");
            Expect((string)r["version"] == "0.37.1", "unusable manifests are skipped");

            try
            {
                Check(server, "0.37.0", "bad", "missing");
                Expect(false, "nothing usable reports offline");
            }
            catch (HostError error)
            {
                Expect(error.Code == "offline" && error.Tried != null && string.Join(",", error.Tried) == "bad,missing",
                    "nothing usable reports offline with every source tried");
            }

            Console.WriteLine(failures == 0 ? "update_check: PASS" : "update_check: " + failures + " FAILED");
            return failures;
        }
    }
}
