// Native window of the packaged app. It shows the app UI (panel/prototype, served by panel/backend.py
// with the bundled Python) in WebView2 and does what a web page cannot: find and prepare the game
// folder, launch the game, export a diagnostic report and install updates.
// C# 5 / .NET Framework 4.8, compiled by tools/package/build.py with the framework's own csc.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Win32;

namespace PhantomGladiator
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            // Started by an update or a restart: wait for the old process, or the single-instance check below
            // would find it still running and close this one.
            int oldPid;
            if (args.Length >= 2 && args[0] == "--wait-for" && int.TryParse(args[1], out oldPid))
            {
                try { using (var old = Process.GetProcessById(oldPid)) old.WaitForExit(30000); }
                catch (ArgumentException) { }
            }
            bool created;
            using (var mutex = new Mutex(true, "PhantomGladiator.App.v1", out created))
            {
                if (!created)
                {
                    Native.FocusWindow("PhantomGladiator.MainForm");
                    return;
                }
                UpdateClient.CleanUp();
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new MainForm());
            }
        }
    }

    sealed class HostError : Exception
    {
        public readonly string Code;
        public readonly string[] Tried;
        public HostError(string code, string message, string[] tried = null) : base(message) { Code = code; Tried = tried; }
    }

    static class Paths
    {
        public static readonly string AppDir = Path.GetDirectoryName(Application.ExecutablePath);
        public static readonly string Bundle = Path.Combine(AppDir, "app");
        // PG_DATA_DIR lets a test run keep its settings and WebView2 profile away from the player's.
        public static readonly string Data = Environment.GetEnvironmentVariable("PG_DATA_DIR") ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PhantomGladiator");
        public static string In(params string[] parts) { return Path.Combine(new[] { Data }.Concat(parts).ToArray()); }
    }

    // What this build installs: app/version.json, written by the build script.
    sealed class BuildInfo
    {
        public string AppVersion = "0.0.0", ModBuild = "", VerifiedGameBuild = "", Repo = "";
        public List<string> Manifests = new List<string>();

        public static BuildInfo Load()
        {
            var info = new BuildInfo();
            var json = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(Path.Combine(Paths.Bundle, "version.json"), Encoding.UTF8));
            info.AppVersion = (string)json["appVersion"];
            info.ModBuild = (string)json["modBuild"];
            info.VerifiedGameBuild = (string)json["verifiedGameBuild"];
            info.Repo = (string)json["repo"];
            foreach (var m in (System.Collections.ArrayList)json["manifests"]) info.Manifests.Add((string)m);
            return info;
        }
    }

    sealed class Settings
    {
        public string GamePath = "";
        static string File_ { get { return Paths.In("settings.json"); } }

        public static Settings Load()
        {
            var s = new Settings();
            try
            {
                var json = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(File_, Encoding.UTF8));
                object v;
                if (json.TryGetValue("gamePath", out v) && v is string) s.GamePath = (string)v;
            }
            catch (Exception) { }
            return s;
        }

        public void Save()
        {
            Directory.CreateDirectory(Paths.Data);
            var tmp = File_ + ".tmp";
            File.WriteAllText(tmp, new JavaScriptSerializer().Serialize(new Dictionary<string, object> { { "gamePath", GamePath } }), new UTF8Encoding(false));
            if (File.Exists(File_)) File.Replace(tmp, File_, null); else File.Move(tmp, File_);
        }
    }

    // ---------- Game folder ----------
    sealed class GameInfo
    {
        public string Root, AppId = "", Build = "";
        public string SteamDir { get { return Path.Combine(Root, "platform", "steam"); } }
        public string Ue4ssDir { get { return Path.Combine(SteamDir, "ue4ss"); } }
        public string ModDir { get { return Path.Combine(Ue4ssDir, "Mods", "PhantomGladiator"); } }
        public string RuntimeDir { get { return Path.Combine(ModDir, "Runtime"); } }
    }

    static class GameLocator
    {
        static bool IsRoot(string dir) { return !string.IsNullOrEmpty(dir) && File.Exists(Path.Combine(dir, "platform", "steam", "PBZ.exe")); }

        // Accepts the game root, platform\steam, or any folder inside it the player may pick.
        public static GameInfo FromPath(string path)
        {
            if (string.IsNullOrWhiteSpace(path)) return null;
            string dir;
            try { dir = Path.GetFullPath(path.Trim().Trim('"')); } catch (Exception) { return null; }
            if (File.Exists(dir)) dir = Path.GetDirectoryName(dir);
            for (var d = dir; d != null; d = Path.GetDirectoryName(d))
                if (IsRoot(d)) return Describe(d);
            return null;
        }

        public static GameInfo Detect()
        {
            foreach (var lib in SteamLibraries())
            {
                var apps = Path.Combine(lib, "steamapps");
                if (!Directory.Exists(apps)) continue;
                foreach (var acf in Directory.GetFiles(apps, "appmanifest_*.acf"))
                {
                    var dir = Field(acf, "installdir");
                    if (dir != null && IsRoot(Path.Combine(apps, "common", dir))) return Describe(Path.Combine(apps, "common", dir));
                }
                if (IsRoot(Path.Combine(apps, "common", "PBZ"))) return Describe(Path.Combine(apps, "common", "PBZ"));
            }
            return null;
        }

        static GameInfo Describe(string root)
        {
            var info = new GameInfo { Root = root };
            var common = Path.GetDirectoryName(root);
            var apps = common == null ? null : Path.GetDirectoryName(common);
            if (apps != null && Directory.Exists(apps))
            {
                foreach (var acf in Directory.GetFiles(apps, "appmanifest_*.acf"))
                {
                    if (!string.Equals(Field(acf, "installdir"), Path.GetFileName(root), StringComparison.OrdinalIgnoreCase)) continue;
                    info.AppId = Field(acf, "appid") ?? "";
                    info.Build = Field(acf, "buildid") ?? "";
                    break;
                }
            }
            return info;
        }

        static string Field(string acf, string key)
        {
            try
            {
                var m = Regex.Match(File.ReadAllText(acf), "\"" + key + "\"\\s+\"([^\"]*)\"", RegexOptions.IgnoreCase);
                return m.Success ? m.Groups[1].Value : null;
            }
            catch (Exception) { return null; }
        }

        static IEnumerable<string> SteamLibraries()
        {
            var roots = new List<string>();
            foreach (var key in new[] { @"HKEY_CURRENT_USER\Software\Valve\Steam", @"HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Valve\Steam", @"HKEY_LOCAL_MACHINE\SOFTWARE\Valve\Steam" })
            {
                foreach (var name in new[] { "SteamPath", "InstallPath" })
                {
                    var v = Registry.GetValue(key, name, null) as string;
                    if (!string.IsNullOrEmpty(v)) roots.Add(v.Replace('/', '\\'));
                }
            }
            var libs = new List<string>(roots);
            foreach (var root in roots)
            {
                var vdf = Path.Combine(root, "steamapps", "libraryfolders.vdf");
                if (!File.Exists(vdf)) continue;
                foreach (Match m in Regex.Matches(File.ReadAllText(vdf), "\"path\"\\s+\"([^\"]+)\""))
                    libs.Add(m.Groups[1].Value.Replace(@"\\", @"\"));
            }
            // Common library spots, for Steam installs the registry doesn't know about.
            foreach (var drive in DriveInfo.GetDrives().Where(d => d.DriveType == DriveType.Fixed && d.IsReady))
                foreach (var sub in new[] { "SteamLibrary", "Steam", @"Program Files (x86)\Steam", @"Program Files\Steam", "steam" })
                    libs.Add(Path.Combine(drive.RootDirectory.FullName, sub));
            return libs.Distinct(StringComparer.OrdinalIgnoreCase);
        }

        // Only a game started from this folder counts; another install (or the Steam launcher stub
        // elsewhere) must not block installing here. An unreadable process is assumed to be ours.
        public static bool Running(GameInfo g)
        {
            foreach (var p in Process.GetProcessesByName("PBZ"))
            {
                try
                {
                    if (g == null || p.MainModule.FileName.StartsWith(g.Root, StringComparison.OrdinalIgnoreCase)) return true;
                }
                catch (Exception) { return true; }
                finally { p.Dispose(); }
            }
            return false;
        }
    }

    // ---------- Install ----------
    static class Installer
    {
        static string Payload(params string[] parts) { return Path.Combine(new[] { Paths.Bundle, "payload" }.Concat(parts).ToArray()); }

        static bool SameFile(string a, string b)
        {
            if (!File.Exists(a) || !File.Exists(b)) return false;
            if (new FileInfo(a).Length != new FileInfo(b).Length) return false;
            using (var sha = SHA256.Create())
            using (var fa = File.OpenRead(a))
            using (var fb = File.OpenRead(b))
            {
                var ha = sha.ComputeHash(fa);
                return ha.SequenceEqual(sha.ComputeHash(fb));
            }
        }

        public static string InstalledModBuild(GameInfo g)
        {
            var main = Path.Combine(g.ModDir, "Scripts", "main.lua");
            if (!File.Exists(main)) return "";
            var m = Regex.Match(File.ReadAllText(main, Encoding.UTF8), "BUILD\\s*=\\s*\"([^\"]+)\"");
            return m.Success ? m.Groups[1].Value : "";
        }

        static bool ModListed(GameInfo g)
        {
            var txt = Path.Combine(g.Ue4ssDir, "Mods", "mods.txt");
            return File.Exists(txt) && File.ReadAllLines(txt).Any(l => Regex.IsMatch(l, @"^\s*PhantomGladiator\s*:\s*1\s*$"));
        }

        public static List<Dictionary<string, object>> Components(GameInfo g, BuildInfo build)
        {
            var list = new List<Dictionary<string, object>>();
            Func<string, bool, string, bool, Dictionary<string, object>> item = (id, ok, detail, warn) =>
                new Dictionary<string, object> { { "id", id }, { "ok", ok }, { "detail", detail }, { "warn", warn } };
            list.Add(item("game", g != null, g == null ? "" : (g.Build.Length > 0 ? "build " + g.Build : "Steam"), g != null && g.Build.Length > 0 && g.Build != build.VerifiedGameBuild));
            if (g == null) return list;
            var dll = Path.Combine(g.Ue4ssDir, "UE4SS.dll");
            var loaderOk = File.Exists(dll) && File.Exists(Path.Combine(g.SteamDir, "dwmapi.dll"));
            var ours = SameFile(dll, Payload("ue4ss", "ue4ss", "UE4SS.dll"));
            list.Add(item("loader", loaderOk, loaderOk ? (ours ? "UE4SS 3.0.1" : "UE4SS") : "", loaderOk && !ours));
            var configOk = SameFile(Path.Combine(g.Ue4ssDir, "MemberVariableLayout.ini"), Payload("gameconfig", "MemberVariableLayout.ini"))
                && Directory.GetFiles(Payload("gameconfig", "UE4SS_Signatures")).All(f => SameFile(Path.Combine(g.Ue4ssDir, "UE4SS_Signatures", Path.GetFileName(f)), f));
            list.Add(item("config", configOk, configOk ? "build " + build.VerifiedGameBuild : "", false));
            var installed = InstalledModBuild(g);
            var modOk = installed == build.ModBuild && ModListed(g);
            list.Add(item("mod", modOk, installed.Length > 0 ? installed : "", false));
            return list;
        }

        public static bool ModInstalled(GameInfo g) { return g != null && File.Exists(Path.Combine(g.ModDir, "Scripts", "main.lua")); }

        static void CopyTree(string from, string to, Func<string, bool> overwrite)
        {
            foreach (var dir in Directory.GetDirectories(from, "*", SearchOption.AllDirectories))
                Directory.CreateDirectory(Path.Combine(to, dir.Substring(from.Length + 1)));
            Directory.CreateDirectory(to);
            foreach (var file in Directory.GetFiles(from, "*", SearchOption.AllDirectories))
            {
                var target = Path.Combine(to, file.Substring(from.Length + 1));
                if (File.Exists(target) && !overwrite(target)) continue;
                File.Copy(file, target, true);
            }
        }

        // Loader only when the game has none (another UE4SS may serve other mods); the game-specific
        // signatures always; the mod replaced as a whole, keeping its Runtime data.
        public static void Install(GameInfo g, Action<string, double> progress)
        {
            if (GameLocator.Running(g)) throw new HostError("gameRunning", "请先关闭游戏再安装：游戏运行时组件文件被占用。");
            progress("loader", 0.05);
            if (!File.Exists(Path.Combine(g.Ue4ssDir, "UE4SS.dll")))
            {
                CopyTree(Payload("ue4ss", "ue4ss"), g.Ue4ssDir, t => false);
                File.Copy(Payload("ue4ss", "dwmapi.dll"), Path.Combine(g.SteamDir, "dwmapi.dll"), true);
            }
            else if (!File.Exists(Path.Combine(g.SteamDir, "dwmapi.dll")))
                File.Copy(Payload("ue4ss", "dwmapi.dll"), Path.Combine(g.SteamDir, "dwmapi.dll"), true);
            if (!Directory.Exists(Path.Combine(g.Ue4ssDir, "Mods", "shared")))
                CopyTree(Payload("ue4ss", "ue4ss", "Mods", "shared"), Path.Combine(g.Ue4ssDir, "Mods", "shared"), t => false);
            progress("config", 0.4);
            CopyTree(Payload("gameconfig"), g.Ue4ssDir, t => true);
            progress("mod", 0.6);
            var scripts = Path.Combine(g.ModDir, "Scripts");
            if (Directory.Exists(scripts)) Directory.Delete(scripts, true);
            CopyTree(Payload("mod", "PhantomGladiator"), g.ModDir, t => true);
            // config.lua ships with the author's absolute Runtime path; point it at this game folder.
            var config = Path.Combine(scripts, "config.lua");
            var lua = File.ReadAllText(config, Encoding.UTF8);
            var runtime = g.RuntimeDir.Replace('\\', '/').Replace("\"", "\\\"");
            var patched = Regex.Replace(lua, "^Config\\.RuntimePath\\s*=\\s*\"[^\"\\r\\n]*\"", m => "Config.RuntimePath = \"" + runtime + "\"", RegexOptions.Multiline);
            if (patched == lua && !lua.Contains("Config.RuntimePath = \"" + runtime + "\"")) throw new HostError("install", "config.lua 里没有找到 Config.RuntimePath，模组可能已更新格式。");
            File.WriteAllText(config, patched, new UTF8Encoding(false));
            progress("mod", 0.8);
            var modsTxt = Path.Combine(g.Ue4ssDir, "Mods", "mods.txt");
            var lines = File.Exists(modsTxt) ? File.ReadAllLines(modsTxt).ToList() : new List<string>();
            var at = lines.FindIndex(l => Regex.IsMatch(l, @"^\s*PhantomGladiator\s*:"));
            if (at >= 0) lines[at] = "PhantomGladiator : 1"; else lines.Add("PhantomGladiator : 1");
            File.WriteAllLines(modsTxt, lines, new UTF8Encoding(false));
            // The slim catalog lets the app list and spawn units before the first in-game scan.
            Directory.CreateDirectory(g.RuntimeDir);
            foreach (var seed in Directory.GetFiles(Payload("seed")))
            {
                var target = Path.Combine(g.RuntimeDir, Path.GetFileName(seed));
                if (!File.Exists(target)) File.Copy(seed, target);
            }
            progress("mod", 1);
        }
    }

    // ---------- Backend (panel/backend.py on the bundled Python) ----------
    sealed class Backend : IDisposable
    {
        Process process;
        IntPtr job = IntPtr.Zero;
        public int Port;
        public string Runtime;
        public string LastError = "";

        public Backend()
        {
            Port = FreePort(52088);
            try
            {
                job = Native.CreateKillOnCloseJob();
            }
            catch (Exception) { job = IntPtr.Zero; }
        }

        static int FreePort(int preferred)
        {
            foreach (var p in new[] { preferred, 0 })
            {
                try
                {
                    var l = new TcpListener(IPAddress.Loopback, p);
                    l.Start();
                    var port = ((IPEndPoint)l.LocalEndpoint).Port;
                    l.Stop();
                    return port;
                }
                catch (SocketException) { }
            }
            throw new HostError("port", "没有可用的本地端口。");
        }

        public bool Start(string runtimeDir)
        {
            Stop();
            Runtime = runtimeDir;
            LastError = "";
            Directory.CreateDirectory(Paths.In("logs"));
            var log = Paths.In("logs", "backend.log");
            var psi = new ProcessStartInfo
            {
                FileName = Path.Combine(Paths.Bundle, "python", "python.exe"),
                Arguments = "-I -X utf8 \"" + Path.Combine(Paths.Bundle, "backend", "backend.py") + "\" --runtime-dir \"" + runtimeDir + "\" --port " + Port + " --static-dir \"" + Path.Combine(Paths.Bundle, "ui") + "\"",
                WorkingDirectory = Path.Combine(Paths.Bundle, "backend"),
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardError = true,
                RedirectStandardOutput = true,
                StandardErrorEncoding = Encoding.UTF8,
                StandardOutputEncoding = Encoding.UTF8,
            };
            psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";
            var sb = new StringBuilder();
            process = Process.Start(psi);
            if (job != IntPtr.Zero) Native.AssignProcessToJobObject(job, process.Handle);
            var p = process;
            DataReceivedEventHandler collect = (s, e) => { if (e.Data != null) lock (sb) sb.AppendLine(e.Data); };
            p.ErrorDataReceived += collect;
            p.OutputDataReceived += collect;
            p.BeginErrorReadLine();
            p.BeginOutputReadLine();
            var until = DateTime.UtcNow.AddSeconds(20);
            while (DateTime.UtcNow < until)
            {
                if (p.HasExited) break;
                if (Ping()) return true;
                Thread.Sleep(150);
            }
            p.WaitForExit(500);
            lock (sb) LastError = sb.ToString().Trim();
            try { File.AppendAllText(log, DateTime.Now.ToString("s") + " backend failed to start\r\n" + LastError + "\r\n", Encoding.UTF8); } catch (Exception) { }
            Stop();
            return false;
        }

        bool Ping()
        {
            try
            {
                var req = (HttpWebRequest)WebRequest.Create("http://127.0.0.1:" + Port + "/api/catalog");
                req.Method = "HEAD";
                req.Timeout = 1000;
                req.Proxy = null;
                using (req.GetResponse()) return true;
            }
            catch (WebException e) { return e.Response != null; }
        }

        public void Stop()
        {
            if (process == null) return;
            try { if (!process.HasExited) { process.Kill(); process.WaitForExit(3000); } } catch (Exception) { }
            process.Dispose();
            process = null;
        }

        public void Dispose() { Stop(); }
    }

    // ---------- Updates ----------
    sealed class UpdateClient
    {
        readonly BuildInfo build;
        Dictionary<string, object> manifest;
        string downloaded;
        volatile bool cancel;

        public UpdateClient(BuildInfo b) { build = b; }

        static string Get(string url, int timeout)
        {
            var req = (HttpWebRequest)WebRequest.Create(url);
            req.Timeout = timeout;
            req.ReadWriteTimeout = timeout;
            req.UserAgent = "PhantomGladiator";
            using (var res = (HttpWebResponse)req.GetResponse())
            using (var r = new StreamReader(res.GetResponseStream(), Encoding.UTF8))
                return r.ReadToEnd();
        }

        static int[] Ver(string v)
        {
            return Regex.Matches(v ?? "", @"\d+").Cast<Match>().Select(m => int.Parse(m.Value)).Concat(new[] { 0, 0, 0 }).Take(3).ToArray();
        }

        static bool Newer(string a, string b)
        {
            var x = Ver(a); var y = Ver(b);
            for (var i = 0; i < 3; i++) if (x[i] != y[i]) return x[i] > y[i];
            return false;
        }

        // latest.json lives in the repository and is fetched through every source at once (the CDNs that work
        // in mainland China are listed first). A CDN can keep serving an old copy for hours after a release
        // (jsDelivr did after v0.37.0), so the newest version any source reports wins; on a tie the source
        // listed first is kept.
        public Dictionary<string, object> Check(string lang)
        {
            var sources = build.Manifests.Select(entry => entry.Split(new[] { '|' }, 2)).ToList();
            var fetching = sources.Select(parts => Task.Run(() => Fetch(parts[1]))).ToArray();
            manifest = null;
            foreach (var task in fetching)
            {
                var found = task.Result;
                if (found != null && (manifest == null || Newer((string)found["version"], (string)manifest["version"]))) manifest = found;
            }
            if (manifest == null) throw new HostError("offline", "", sources.Select(parts => parts[0]).ToArray());
            var version = (string)manifest["version"];
            if (!Newer(version, build.AppVersion)) return new Dictionary<string, object> { { "latest", true }, { "version", build.AppVersion } };
            var lines = new List<object>();
            foreach (Dictionary<string, object> d in (System.Collections.ArrayList)manifest["downloads"])
                lines.Add(new Dictionary<string, object> { { "id", d["id"] }, { "ms", Latency((string)d["url"]) } });
            object notes = new string[0];
            var all = manifest.ContainsKey("notes") ? manifest["notes"] as Dictionary<string, object> : null;
            if (all != null) notes = all.ContainsKey(lang) ? all[lang] : (all.ContainsKey("en") ? all["en"] : notes);
            return new Dictionary<string, object> { { "latest", false }, { "version", version }, { "date", manifest["date"] }, { "size", manifest["size"] }, { "notes", notes }, { "lines", lines } };
        }

        // A manifest an update can be installed from (version, size, SHA-256 and download lines), or null.
        static Dictionary<string, object> Fetch(string url)
        {
            try
            {
                var found = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(Get(url, 6000));
                if (found == null || !(found.ContainsKey("version") && found["version"] is string) || !(found.ContainsKey("sha256") && found["sha256"] is string)
                    || !found.ContainsKey("size") || !(found.ContainsKey("downloads") && found["downloads"] is System.Collections.ArrayList)) return null;
                return found;
            }
            catch (Exception) { return null; }
        }

        static object Latency(string url)
        {
            try
            {
                var sw = Stopwatch.StartNew();
                var req = (HttpWebRequest)WebRequest.Create(url);
                req.Method = "HEAD";
                req.Timeout = 4000;
                req.UserAgent = "PhantomGladiator";
                using (req.GetResponse()) { }
                return (int)sw.ElapsedMilliseconds;
            }
            catch (Exception) { return null; }
        }

        public void Download(string line, Action<long, long, double> progress)
        {
            if (manifest == null) throw new HostError("offline", "");
            cancel = false;
            var size = Convert.ToInt64(manifest["size"]);
            var urls = ((System.Collections.ArrayList)manifest["downloads"]).Cast<Dictionary<string, object>>().ToList();
            var pick = urls.FirstOrDefault(d => (string)d["id"] == line) ?? urls.First();
            Directory.CreateDirectory(Paths.In("updates"));
            var target = Paths.In("updates", "PhantomGladiator-" + manifest["version"] + ".zip");
            var part = target + ".part";
            var req = (HttpWebRequest)WebRequest.Create((string)pick["url"]);
            req.UserAgent = "PhantomGladiator";
            req.Timeout = 15000;
            req.ReadWriteTimeout = 30000;
            using (var res = req.GetResponse())
            using (var input = res.GetResponseStream())
            using (var output = File.Create(part))
            {
                var buffer = new byte[81920];
                long done = 0, lastDone = 0;
                var clock = Stopwatch.StartNew();
                var lastTick = 0L;
                int n;
                while ((n = input.Read(buffer, 0, buffer.Length)) > 0)
                {
                    if (cancel) throw new HostError("cancelled", "");
                    output.Write(buffer, 0, n);
                    done += n;
                    if (clock.ElapsedMilliseconds - lastTick >= 200)
                    {
                        var speed = (done - lastDone) * 1000.0 / Math.Max(1, clock.ElapsedMilliseconds - lastTick);
                        progress(done, size, speed);
                        lastTick = clock.ElapsedMilliseconds;
                        lastDone = done;
                    }
                }
                progress(done, size, 0);
            }
            if (File.Exists(target)) File.Delete(target);
            File.Move(part, target);
            downloaded = target;
        }

        public void Cancel() { cancel = true; }

        public void Verify()
        {
            if (downloaded == null) throw new HostError("verify", "");
            string hash;
            using (var sha = SHA256.Create())
            using (var f = File.OpenRead(downloaded))
                hash = BitConverter.ToString(sha.ComputeHash(f)).Replace("-", "").ToLowerInvariant();
            if (hash != ((string)manifest["sha256"]).ToLowerInvariant())
            {
                File.Delete(downloaded);
                downloaded = null;
                throw new HostError("badHash", "下载的文件校验不通过，已删除。请换一条线路重试。");
            }
        }

        // Unpacks next to the app's data and swaps the app's files in place (AppSwap, desktop/AppUpdate.cs), then
        // starts the new exe, which waits for this process to exit. The caller has stopped the backend first: its
        // Python keeps files in app\ open.
        public void Install()
        {
            if (downloaded == null) throw new HostError("verify", "");
            var staging = Paths.In("updates", "staging");
            if (Directory.Exists(staging)) Directory.Delete(staging, true);
            ZipFile.ExtractToDirectory(downloaded, staging);
            var root = Directory.GetFiles(staging, "PhantomGladiator.exe", SearchOption.AllDirectories).Select(Path.GetDirectoryName).FirstOrDefault();
            if (root == null || !Directory.Exists(Path.Combine(root, "app"))) throw new HostError("verify", "更新包内容不完整。");
            try { AppSwap.Apply(root, Paths.AppDir); }
            catch (IOException e) { throw new HostError("install", "更新没有完成，原来的文件已恢复：" + e.Message + "\n\n可以到 GitHub 下载完整包手动替换。"); }
            try
            {
                Process.Start(new ProcessStartInfo(Path.Combine(Paths.AppDir, "PhantomGladiator.exe"), "--wait-for " + Process.GetCurrentProcess().Id)
                    { UseShellExecute = false, WorkingDirectory = Paths.AppDir });
            }
            catch (Exception e) { throw new HostError("install", "新版本已装好，但没能自动打开，请关掉助手后再打开一次：" + e.Message); }
        }

        // At start: what the last update set aside, and the updater.exe copy (with the DLLs it needed) that versions
        // before 0.37.6 ran from AppData. Anything still in use is left for the next start.
        public static void CleanUp()
        {
            try { AppSwap.Cleanup(Paths.AppDir); } catch (Exception) { }
            try
            {
                var updates = Paths.In("updates");
                if (!Directory.Exists(updates)) return;
                foreach (var file in Directory.GetFiles(updates, "*.exe").Concat(Directory.GetFiles(updates, "*.dll")))
                    try { File.Delete(file); } catch (Exception) { }
                var staging = Path.Combine(updates, "staging");
                if (Directory.Exists(staging)) try { Directory.Delete(staging, true); } catch (Exception) { }
            }
            catch (Exception) { }
        }
    }

    // ---------- Window ----------
    sealed class MainForm : Form
    {
        readonly WebView2 web = new WebView2();
        readonly Backend backend = new Backend();
        readonly Settings settings = Settings.Load();
        readonly BuildInfo build = BuildInfo.Load();
        readonly UpdateClient updates;
        readonly System.Windows.Forms.Timer gameTimer = new System.Windows.Forms.Timer { Interval = 3000 };
        readonly JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength = 16 * 1024 * 1024 };
        GameInfo game;
        bool gameRunning;
        string lang = "zh";

        public MainForm()
        {
            updates = new UpdateClient(build);
            Text = "斗蛐蛐 · 影之刃零";
            Name = "PhantomGladiator.MainForm";
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch (Exception) { }
            var area = Screen.PrimaryScreen.WorkingArea;
            Size = new Size(Math.Min(1440, (int)(area.Width * 0.9)), Math.Min(900, (int)(area.Height * 0.9)));
            MinimumSize = new Size(960, 640);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(243, 241, 236);
            web.Dock = DockStyle.Fill;
            web.DefaultBackgroundColor = BackColor;
            Controls.Add(web);
            game = GameLocator.FromPath(settings.GamePath);
            if (game == null)
            {
                game = GameLocator.Detect();
                if (game != null) { settings.GamePath = game.Root; settings.Save(); }
            }
            gameTimer.Tick += (s, e) =>
            {
                var running = GameLocator.Running(game);
                if (running == gameRunning) return;
                gameRunning = running;
                Post(new Dictionary<string, object> { { "event", "gameRunning" }, { "running", running } });
            };
        }

        protected override async void OnLoad(EventArgs e)
        {
            base.OnLoad(e);
            try
            {
                var env = await CoreWebView2Environment.CreateAsync(null, Paths.In("WebView2"));
                await web.EnsureCoreWebView2Async(env);
            }
            catch (WebView2RuntimeNotFoundException)
            {
                if (MessageBox.Show("需要先安装微软的 WebView2 运行库（Windows 10/11 一般自带）。\n点“确定”打开微软官方下载页。", "斗蛐蛐", MessageBoxButtons.OKCancel, MessageBoxIcon.Information) == DialogResult.OK)
                    OpenExternal("https://go.microsoft.com/fwlink/p/?LinkId=2124703");
                Close();
                return;
            }
            var core = web.CoreWebView2;
            core.Settings.AreDevToolsEnabled = Environment.GetEnvironmentVariable("PG_DEVTOOLS") == "1";
            core.Settings.AreDefaultContextMenusEnabled = core.Settings.AreDevToolsEnabled;
            core.Settings.IsStatusBarEnabled = false;
            core.Settings.IsZoomControlEnabled = false;
            core.DocumentTitleChanged += (s, a) => { if (!string.IsNullOrEmpty(core.DocumentTitle)) Text = core.DocumentTitle; };
            core.NewWindowRequested += (s, a) => { a.Handled = true; OpenExternal(a.Uri); };
            core.NavigationStarting += (s, a) =>
            {
                var uri = a.Uri ?? "";
                if (uri.StartsWith("http://127.0.0.1:" + backend.Port + "/") || uri.StartsWith("data:") || uri.StartsWith("about:")) return;
                a.Cancel = true;
                OpenExternal(uri);
            };
            core.WebMessageReceived += OnMessage;
            gameRunning = GameLocator.Running(game);
            gameTimer.Start();
            await StartBackend();
        }

        string RuntimeDir()
        {
            if (Installer.ModInstalled(game)) return game.RuntimeDir;
            // Before the mod is in the game folder the page still needs a backend to load from.
            var fallback = Paths.In("Runtime");
            Directory.CreateDirectory(fallback);
            return fallback;
        }

        async Task StartBackend()
        {
            var runtime = RuntimeDir();
            var ok = await Task.Run(() => backend.Start(runtime));
            if (ok) { web.CoreWebView2.Navigate("http://127.0.0.1:" + backend.Port + "/"); return; }
            var busy = backend.LastError.Contains("已有面板后端");
            ShowError(busy ? "另一个斗蛐蛐助手或开发面板正在使用这份游戏数据。请先关闭它，再点“重试”。" : "助手后台没能启动。可以点“重试”；如果一直这样，请把下面的信息发给作者。",
                busy ? "" : backend.LastError);
        }

        // The backend is down, so this page cannot come from it.
        void ShowError(string message, string detail)
        {
            var html = "<!doctype html><meta charset=utf-8><body style=\"margin:0;font:14px/1.6 'Microsoft YaHei UI',sans-serif;background:#f3f1ec;color:#2a2620;display:grid;place-items:center;height:100vh\">"
                + "<div style=\"max-width:560px;padding:32px;background:#fff;border-radius:16px;box-shadow:0 8px 30px rgba(0,0,0,.08)\"><h2 style=\"margin:0 0 8px\">斗蛐蛐助手</h2><p>" + WebUtility.HtmlEncode(message) + "</p>"
                + (detail.Length > 0 ? "<pre style=\"white-space:pre-wrap;font-size:12px;background:#f6f4f0;padding:12px;border-radius:8px;max-height:200px;overflow:auto\">" + WebUtility.HtmlEncode(detail) + "</pre>" : "")
                + "<button onclick=\"chrome.webview.postMessage({id:0,method:'retry'})\" style=\"font:inherit;padding:8px 18px;border:0;border-radius:10px;background:#b5372a;color:#fff;cursor:pointer\">重试</button></div>";
            web.CoreWebView2.NavigateToString(html);
        }

        // Install and download report progress from worker threads. WebView2 may only be touched on the UI
        // thread ("CoreWebView2 can only be accessed from the UI thread"), even to check it, so a message from
        // any other thread is handed to the UI thread first.
        void Post(Dictionary<string, object> message)
        {
            if (InvokeRequired)
            {
                // Throws (ObjectDisposedException is one) once the window is closing; the message is dropped then.
                try { BeginInvoke((Action)(() => Post(message))); } catch (InvalidOperationException) { }
                return;
            }
            if (IsDisposed || web.IsDisposed || web.CoreWebView2 == null) return;
            web.CoreWebView2.PostWebMessageAsJson(json.Serialize(message));
        }

        void Progress(string task, Dictionary<string, object> data)
        {
            data["event"] = "progress";
            data["task"] = task;
            Post(data);
        }

        async void OnMessage(object sender, CoreWebView2WebMessageReceivedEventArgs e)
        {
            Dictionary<string, object> m;
            try { m = json.Deserialize<Dictionary<string, object>>(e.WebMessageAsJson); } catch (Exception) { return; }
            var id = m.ContainsKey("id") ? m["id"] : 0;
            var method = m.ContainsKey("method") ? m["method"] as string : "";
            var p = m.ContainsKey("params") ? m["params"] as Dictionary<string, object> : null;
            if (p == null) p = new Dictionary<string, object>();
            try
            {
                var result = await Dispatch(method, p);
                Post(new Dictionary<string, object> { { "reply", id }, { "ok", true }, { "result", result } });
            }
            catch (Exception ex)
            {
                var he = ex as HostError;
                Post(new Dictionary<string, object> { { "reply", id }, { "ok", false }, { "error", new Dictionary<string, object> {
                    { "code", he != null ? he.Code : "host" }, { "message", ex.Message }, { "tried", he != null && he.Tried != null ? he.Tried : new string[0] } } } });
            }
        }

        Dictionary<string, object> GameDict(GameInfo g)
        {
            return new Dictionary<string, object> { { "path", g.Root }, { "store", "Steam" }, { "build", g.Build }, { "appId", g.AppId } };
        }

        async Task<object> Dispatch(string method, Dictionary<string, object> p)
        {
            switch (method)
            {
                case "retry":
                    await StartBackend();
                    return null;
                case "info":
                    return new Dictionary<string, object> { { "appVersion", build.AppVersion }, { "modBuild", build.ModBuild }, { "gamePath", game != null ? game.Root : "" }, { "gameRunning", gameRunning } };
                case "detectGame":
                {
                    var found = await Task.Run(() => GameLocator.Detect());
                    if (found == null) throw new HostError("notFound", "");
                    return GameDict(found);
                }
                case "pickFolder":
                    using (var dialog = new FolderBrowserDialog { Description = "选择《影之刃零》的安装文件夹（里面有 platform\\steam\\PBZ.exe）", ShowNewFolderButton = false })
                        return dialog.ShowDialog(this) == DialogResult.OK ? dialog.SelectedPath : null;
                case "setGamePath":
                {
                    var g = GameLocator.FromPath(p.ContainsKey("path") ? p["path"] as string : "");
                    if (g == null) throw new HostError("notGame", "");
                    var restart = game == null || !string.Equals(g.Root, game.Root, StringComparison.OrdinalIgnoreCase);
                    game = g;
                    settings.GamePath = g.Root;
                    settings.Save();
                    if (restart && backend.Runtime != RuntimeDir()) await StartBackend();
                    return GameDict(g);
                }
                case "components":
                    return await Task.Run(() => Installer.Components(game, build));
                case "install":
                {
                    if (game == null) throw new HostError("notGame", "");
                    var g = game;
                    await Task.Run(() => Installer.Install(g, (step, ratio) => Progress("install", new Dictionary<string, object> { { "step", step }, { "ratio", ratio } })));
                    if (backend.Runtime != RuntimeDir()) await StartBackend();
                    return null;
                }
                case "launchGame":
                    if (game == null) throw new HostError("notGame", "");
                    if (game.AppId.Length > 0) OpenExternal("steam://rungameid/" + game.AppId);
                    else Process.Start(new ProcessStartInfo(Path.Combine(game.SteamDir, "PBZ.exe")) { WorkingDirectory = game.SteamDir });
                    return null;
                case "openFolder":
                    Process.Start("explorer.exe", "\"" + (Installer.ModInstalled(game) ? game.RuntimeDir : Paths.Data) + "\"");
                    return null;
                case "exportReport":
                    return await Task.Run(() => ExportReport());
                case "checkUpdate":
                    if (p.ContainsKey("lang")) lang = p["lang"] as string ?? lang;
                    return await Task.Run(() => updates.Check(lang));
                case "downloadUpdate":
                {
                    var line = p.ContainsKey("line") ? p["line"] as string : "";
                    await Task.Run(() => updates.Download(line, (done, total, speed) =>
                        Progress("download", new Dictionary<string, object> { { "done", done }, { "total", total }, { "speed", speed } })));
                    return null;
                }
                case "cancelDownload":
                    updates.Cancel();
                    return null;
                case "verifyUpdate":
                    await Task.Run(() => updates.Verify());
                    return null;
                case "installUpdate":
                    if (gameRunning) throw new HostError("gameRunning", "请先关闭游戏再更新。");
                    // The backend's Python keeps files in app\ open while it runs; it comes back if the update fails.
                    var runtime = backend.Runtime;
                    backend.Stop();
                    Exception failed = null;
                    try { await Task.Run(() => updates.Install()); }
                    catch (Exception e) { failed = e; }
                    if (failed != null)
                    {
                        if (!string.IsNullOrEmpty(runtime)) await Task.Run(() => backend.Start(runtime));
                        throw failed;
                    }
                    BeginInvoke((Action)Close);
                    return null;
                case "restart":
                    Process.Start(new ProcessStartInfo(Application.ExecutablePath, "--wait-for " + Process.GetCurrentProcess().Id) { UseShellExecute = false });
                    BeginInvoke((Action)Close);
                    return null;
                default:
                    throw new HostError("unknown", method);
            }
        }

        // Logs the author needs to look into a problem, zipped onto the desktop.
        string ExportReport()
        {
            var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            var target = Path.Combine(desktop, "斗蛐蛐诊断-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".zip");
            using (var zip = ZipFile.Open(target, ZipArchiveMode.Create))
            {
                Action<string, string> add = (file, name) =>
                {
                    if (!File.Exists(file)) return;
                    using (var src = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                    using (var dst = zip.CreateEntry(name).Open())
                        src.CopyTo(dst);
                };
                add(Paths.In("logs", "backend.log"), "backend.log");
                zip.CreateEntry("app.txt");
                using (var w = new StreamWriter(zip.GetEntry("app.txt").Open(), new UTF8Encoding(false)))
                    w.Write("app " + build.AppVersion + "\r\nmod " + build.ModBuild + "\r\ngame " + (game != null ? game.Root + " build " + game.Build : "not found") + "\r\nwindows " + Environment.OSVersion + "\r\n");
                if (game != null)
                {
                    add(Path.Combine(game.Ue4ssDir, "UE4SS.log"), "UE4SS.log");
                    foreach (var name in new[] { "status.tsv", "ack.tsv", "command-journal.tsv", "function-keybinds-state.tsv" })
                        add(Path.Combine(game.RuntimeDir, name), "Runtime/" + name);
                    if (Directory.Exists(game.RuntimeDir))
                        foreach (var run in Directory.GetFiles(game.RuntimeDir, "run-*.log").OrderByDescending(f => f).Take(2))
                            add(run, "Runtime/" + Path.GetFileName(run));
                }
            }
            return target;
        }

        static void OpenExternal(string uri)
        {
            if (uri == null) return;
            if (!(uri.StartsWith("https://") || uri.StartsWith("http://") || uri.StartsWith("steam://"))) return;
            try { Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true }); } catch (Exception) { }
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            gameTimer.Stop();
            backend.Dispose();
            base.OnFormClosing(e);
        }
    }

    static class Native
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref ExtendedLimits info, int length);
        [DllImport("kernel32.dll")] public static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string cls, string title);
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hwnd);
        [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hwnd, int cmd);

        [StructLayout(LayoutKind.Sequential)]
        struct BasicLimits { public long PerProcessUserTimeLimit, PerJobUserTimeLimit; public uint LimitFlags; public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize; public uint ActiveProcessLimit; public UIntPtr Affinity; public uint PriorityClass, SchedulingClass; }
        [StructLayout(LayoutKind.Sequential)]
        struct IoCounters { public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount, ReadTransferCount, WriteTransferCount, OtherTransferCount; }
        [StructLayout(LayoutKind.Sequential)]
        struct ExtendedLimits { public BasicLimits Basic; public IoCounters Io; public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed; }

        // The backend dies with this window even if the window crashes.
        public static IntPtr CreateKillOnCloseJob()
        {
            var job = CreateJobObject(IntPtr.Zero, null);
            var info = new ExtendedLimits();
            info.Basic.LimitFlags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            if (!SetInformationJobObject(job, 9, ref info, Marshal.SizeOf(typeof(ExtendedLimits)))) throw new Win32Exception();
            return job;
        }

        public static void FocusWindow(string name)
        {
            foreach (var p in Process.GetProcessesByName(Process.GetCurrentProcess().ProcessName))
            {
                if (p.Id == Process.GetCurrentProcess().Id || p.MainWindowHandle == IntPtr.Zero) continue;
                ShowWindow(p.MainWindowHandle, 9);
                SetForegroundWindow(p.MainWindowHandle);
            }
        }
    }

    sealed class Win32Exception : Exception { }
}
