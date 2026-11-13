// Entry point for tools/test_update_check.py, compiled together with desktop/PhantomGladiator.cs: the real
// UpdateClient.Check against a local fake server. Every source is asked at once and the newest usable
// manifest wins. C# 5, like the app.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

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

        // Each source is a folder holding latest.json and versions.json.
        static UpdateClient Client(string server, string app, params string[] names)
        {
            var build = new BuildInfo { AppVersion = app };
            foreach (var name in names) build.Manifests.Add(name + "|" + server + "/" + name + "/latest.json");
            return new UpdateClient(build);
        }

        static bool HasPartsLine(Dictionary<string, object> info)
        {
            return ((System.Collections.IEnumerable)info["lines"]).Cast<Dictionary<string, object>>().Any(l => (string)l["id"] == "parts");
        }

        static UpdateClient OneSource(string server, string name)
        {
            var build = new BuildInfo { AppVersion = "0.37.0" };
            build.Manifests.Add(name + "|" + server + "/" + name + ".json");
            return new UpdateClient(build);
        }

        static byte[] Fetch2(string url)
        {
            using (var web = new System.Net.WebClient()) return web.DownloadData(url);
        }

        static string Fetch(string url)
        {
            using (var web = new System.Net.WebClient()) return web.DownloadString(url);
        }

        static void ExpectRefused(Action action, string code, string what)
        {
            try
            {
                action();
                Expect(false, what);
            }
            catch (HostError error)
            {
                Expect(error.Code == code, what + " (" + error.Code + ")");
            }
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

            ExpectRefused(() => Check(server, "0.37.1", "old", "new"), "updateUnconfirmed",
                "matching cached versions without an independent confirmation do not claim latest");

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

            // Going back: the version comes from whichever source lists it, and is what a download then fetches.
            r = Client(server, "0.38.0", "stale", "full").SelectVersion("0.37.0", "zh");
            Expect((bool)r["rollback"] && !(bool)r["latest"] && (string)r["version"] == "0.37.0", "an older version a stale source does not list comes from the next source");
            Expect(((System.Collections.IEnumerable)r["lines"]).Cast<object>().Count() == 1, "it has its download lines");

            r = Client(server, "0.38.0", "stale", "full").SelectVersion("0.37.1", "zh");
            Expect((string)r["date"] == "stale", "on a tie the source listed first is kept");

            r = Client(server, "0.38.0", "broken", "full").SelectVersion("0.37.1", "zh");
            Expect((string)r["date"] == "full", "an entry without download lines is skipped");

            r = Client(server, "0.38.0", "nojson", "notlisted", "full").SelectVersion("0.37.0", "zh");
            Expect((string)r["version"] == "0.37.0", "a broken list and a list without the version are skipped");

            ExpectRefused(() => Client(server, "0.37.1", "full").SelectVersion("0.38.0", "zh"), "notOlder", "a newer version is not gone back to");
            ExpectRefused(() => Client(server, "0.37.1", "full").SelectVersion("0.37.1", "zh"), "notOlder", "nor the version already installed");

            var client = Client(server, "0.37.1", "full");
            ExpectRefused(() => client.SelectVersion("0.38.0", "zh"), "notOlder", "refused once");
            ExpectRefused(() => client.Download("github", (done, size, speed) => { }), "offline", "and a refused version cannot be downloaded");

            try
            {
                Client(server, "0.38.0", "stale", "nojson", "missing").SelectVersion("0.36.0", "zh");
                Expect(false, "a version nobody lists reports offline");
            }
            catch (HostError error)
            {
                Expect(error.Code == "offline" && string.Join(",", error.Tried) == "stale,nojson,missing", "a version nobody lists reports offline with every source tried");
            }

            // Split downloads: a mix of sources that do not have the part, serve wrong bytes, drip, or work.
            var mixed = OneSource(server, "split-mixed");
            r = mixed.Check("zh");
            Expect(HasPartsLine(r), "a manifest with parts offers the split line");
            var clock2 = Stopwatch.StartNew();
            long seenDone = 0, seenTotal = 0;
            mixed.Download("parts", (done, size, speed) => { seenDone = done; seenTotal = size; });
            mixed.Verify();
            Expect(clock2.ElapsedMilliseconds < 30000, "bad sources do not hold it up: joined and SHA-256 verified in " + clock2.ElapsedMilliseconds + " ms");
            Expect(seenDone == seenTotal && seenTotal > 0, "progress ends at the whole size");
            var updates = Paths.In("updates");
            Expect(File.Exists(Path.Combine(updates, "PhantomGladiator-0.37.2.zip")) && !Directory.Exists(Path.Combine(updates, "parts-0.37.2")), "the zip is there and the parts are cleaned up");

            var dead = OneSource(server, "split-dead");
            dead.Check("zh");
            ExpectRefused(() => dead.Download("parts", (done, size, speed) => { }), "download", "no source working fails instead of hanging");
            ExpectRefused(() => dead.Verify(), "verify", "and leaves nothing to verify");

            // A retry fetches only what is missing: two parts are already on disk, one of them damaged.
            var resume = OneSource(server, "split-resume");
            resume.Check("zh");
            var folder = Path.Combine(updates, "parts-0.37.3");
            Directory.CreateDirectory(folder);
            File.WriteAllBytes(Path.Combine(folder, "part.000"), Fetch2(server + "/src/good/part.000"));
            File.WriteAllBytes(Path.Combine(folder, "part.001"), new byte[] { 1, 2, 3 });
            resume.Download("parts", (done, size, speed) => { });
            resume.Verify();
            var hits = Fetch(server + "/hits");
            Expect(hits.Contains("resume/part.001") && !hits.Contains("resume/part.000"), "a finished part is kept, a damaged one is fetched again");

            var stop = OneSource(server, "split-slow");
            stop.Check("zh");
            var running = Task.Run(() => stop.Download("parts", (done, size, speed) => { }));
            System.Threading.Thread.Sleep(1200);
            stop.Cancel();
            var clock3 = Stopwatch.StartNew();
            ExpectRefused(() => { try { running.Wait(); } catch (AggregateException e) { throw e.InnerException; } }, "cancelled", "cancelling stops it");
            Expect(clock3.ElapsedMilliseconds < 6000, "soon after (" + clock3.ElapsedMilliseconds + " ms)");

            // Parts that do not add up, or a name with a path in it, are ignored: the whole-file lines still work.
            foreach (var name in new[] { "split-wrongsize", "split-badname" })
            {
                var odd = OneSource(server, name);
                r = odd.Check("zh");
                Expect(!HasPartsLine(r), name + ": no split line");
                odd.Download("parts", (done, size, speed) => { });
                odd.Verify();
                Expect(true, name + ": the whole-file line is used");
            }

            Console.WriteLine(failures == 0 ? "update_check: PASS" : "update_check: " + failures + " FAILED");
            return failures;
        }
    }
}
