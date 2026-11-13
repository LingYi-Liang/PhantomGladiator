using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;

namespace PhantomGladiator
{
    static class UpdateFreshnessTest
    {
        static int failures;
        static string server;
        static void Expect(bool ok, string message)
        {
            Console.WriteLine((ok ? "PASS " : "FAIL ") + message);
            if (!ok) failures++;
        }
        static UpdateClient Client(string path, string version, string build, string api)
        {
            var info = new BuildInfo { AppVersion=version, ModBuild=build };
            info.Manifests.Add("cdn|" + server + "/" + path + "/latest.json");
            var ctor = typeof(UpdateClient).GetConstructors().FirstOrDefault(c => c.GetParameters().Length == 3);
            return ctor == null ? new UpdateClient(info) : (UpdateClient)ctor.Invoke(new object[] { info, false, server + "/api/" + api });
        }
        static void Refuses(UpdateClient client, string message)
        {
            try { client.Check("zh"); Expect(false, message); }
            catch (HostError e) { Expect(e.Code == "updateUnconfirmed", message + ": " + e.Code); }
        }
        static bool Available(Dictionary<string, object> value, string version)
        { return !(bool)value["latest"] && (string)value["version"] == version; }

        static int Main(string[] args)
        {
            Console.OutputEncoding=new System.Text.UTF8Encoding(false);
            server=args[0];
            Refuses(Client("stale","0.40.11","v0.40.11","unavailable"),
                "a cached matching release alone cannot claim the installed app is newest");
            Expect(Available(Client("nonce","0.40.11","v0.40.11","unavailable").Check("zh"),"0.40.13"),
                "cache-bypassing requests reach the new manifest");
            Expect(Available(Client("list","0.40.11","v0.40.11","unavailable").Check("zh"),"0.40.13"),
                "the release list can recover a newer release hidden by a stale latest file");
            Expect(Available(Client("api-only","0.40.11","v0.40.11","latest").Check("zh"),"0.40.13"),
                "the stable GitHub release recovers an update when both repository files are stale");
            var latest=Client("current","0.40.13","v0.40.13","latest").Check("zh");
            Expect((bool)latest["latest"],"a current public release is confirmed by independent release information");
            var beta=Client("current","0.40.13","v0.40.13-beta-1","latest");
            var promotion=beta.Check("zh");
            Expect(Available(promotion,"0.40.13") && promotion.ContainsKey("switchToStable") && (bool)promotion["switchToStable"],
                "a beta can switch to the public release even with the same numeric version");
            var check=typeof(UpdateClient).GetMethods().FirstOrDefault(m => m.Name=="Check" && m.GetParameters().Length==2);
            if (check != null)
                Expect((bool)((Dictionary<string,object>)check.Invoke(beta,new object[]{"zh",false}))["latest"],
                    "automatic checks do not repeatedly offer same-version stable promotion");
            var ahead=Client("current","0.40.14","v0.40.14-beta-1","latest").Check("zh");
            Expect(Available(ahead,"0.40.13") && ahead.ContainsKey("switchToStable"),
                "a manual check can explicitly switch an ahead-of-release beta back to stable");
            Refuses(Client("current","0.40.13","v0.40.13","preview"),"a prerelease cannot confirm the public latest version");
            Refuses(Client("current","0.40.13","v0.40.13","draft"),"a draft cannot confirm the public latest version");
            Refuses(Client("stale","0.40.11","v0.40.11","incomplete"),"a newer tag without installable package metadata cannot claim latest");
            Refuses(Client("stale","0.40.11","v0.40.11-beta-3","incomplete"),"a known newer stable release prevents promoting a beta to an older cached package");
            var requests=new System.Net.WebClient().DownloadString(server+"/requests");
            Expect(requests.Contains("pg_check") && requests.Contains("no-cache"),"fresh checks set a nonce and request cache bypass");
            Console.WriteLine("update freshness failures="+failures);
            return failures;
        }
    }
}
