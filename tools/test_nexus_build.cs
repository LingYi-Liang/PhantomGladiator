// Entry point for tools/test_nexus_build.py, compiled with desktop/PhantomGladiator.cs once with /define:NEXUS and
// once without. The Nexus Mods build's UpdateClient refuses every call; the GitHub build's asks the fake server, which
// shows the test notices a connection. C# 5, like the app.
using System;

namespace PhantomGladiator
{
    static class NexusBuildTest
    {
        static int failures;

        static void Expect(bool ok, string what)
        {
            Console.WriteLine((ok ? "PASS " : "FAIL ") + what);
            if (!ok) failures++;
        }

        // The HostError code a call ends with, "none" if it returns.
        static string Outcome(Action call)
        {
            try { call(); return "none"; }
            catch (HostError e) { return e.Code; }
            catch (Exception e) { return e.GetType().Name; }
        }

        static int Main(string[] args)
        {
            var build = new BuildInfo { AppVersion = "0.40.10" };
            build.Manifests.Add("cdn|" + args[0] + "/latest.json");
            build.Manifests.Add("github|" + args[0] + "/raw/latest.json");
            var updates = new UpdateClient(build);
#if NEXUS
            Expect(BuildInfo.Channel == "nexus", "the build says it is the nexus channel");
            Expect(Outcome(() => updates.Check("zh")) == "updatesOff", "Check refuses");
            Expect(Outcome(() => updates.SelectVersion("0.40.9", "zh")) == "updatesOff", "SelectVersion (rollback) refuses");
            Expect(Outcome(() => updates.Download("auto", (done, total, speed) => { })) == "updatesOff", "Download refuses");
            Expect(Outcome(() => updates.Verify()) == "updatesOff", "Verify refuses");
            Expect(Outcome(() => updates.Install()) == "updatesOff", "Install refuses");
            Expect(Outcome(() => updates.Cancel()) == "none", "Cancel does nothing");
            Expect(Outcome(() => UpdateClient.CleanUp()) == "none", "start-up cleanup still runs");
#else
            Expect(BuildInfo.Channel == "github", "the build says it is the github channel");
            Expect(Outcome(() => updates.Check("zh")) == "none", "Check asks the update sources");
#endif
            Console.WriteLine(failures == 0 ? "ALL PASS" : failures + " FAILED");
            return failures == 0 ? 0 : 1;
        }
    }
}
