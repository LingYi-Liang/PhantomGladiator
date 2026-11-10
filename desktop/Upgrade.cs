// One-time migration to the GitHub build. C# 5 / .NET Framework 4.8.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace PhantomGladiator
{
    static class Upgrade
    {
        const string Prefix = "PhantomGladiator-GitHub";
        const string Marker = ".pg-github-install";
        const string AppExe = "PhantomGladiator.exe";
        const string AssistantMutex = "PhantomGladiator.App.v1";

        sealed class PackageInfo
        {
            public string appVersion { get; set; }
            public string channel { get; set; }
            public string repo { get; set; }
        }

        static Version ReadVersion(string directory)
        {
            if (!File.Exists(Path.Combine(directory, AppExe))) return null;
            try
            {
                var info = new JavaScriptSerializer().Deserialize<PackageInfo>(
                    File.ReadAllText(Path.Combine(directory, "app", "version.json")));
                Version version;
                if (info != null && info.repo == "LingYi-Liang/PhantomGladiator" &&
                    (info.channel == null || info.channel == "github") &&
                    Version.TryParse(info.appVersion, out version)) return version;
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
            catch (ArgumentException) { }
            catch (InvalidOperationException) { }
            return null;
        }

        public static string Install(string programs, Stream package, Version version, string digest)
        {
            programs = Directory.CreateDirectory(programs).FullName;
            string latest = null;
            var latestVersion = version;
            foreach (var folder in new DirectoryInfo(programs).EnumerateDirectories(Prefix + "*"))
            {
                if ((folder.Attributes & FileAttributes.ReparsePoint) != 0 ||
                    !File.Exists(Path.Combine(folder.FullName, Marker))) continue;
                var installed = ReadVersion(folder.FullName);
                if (installed != null && installed >= latestVersion)
                {
                    latest = folder.FullName;
                    latestVersion = installed;
                }
            }
            if (latest != null) return latest;

            string actual;
            using (var sha = SHA256.Create())
                actual = BitConverter.ToString(sha.ComputeHash(package)).Replace("-", "").ToLowerInvariant();
            if (actual != digest) throw new InvalidDataException("SHA-256");
            package.Position = 0;

            var staging = Directory.CreateDirectory(Path.Combine(programs, ".pg-upgrade-" + Guid.NewGuid().ToString("N")));
            try
            {
                using (var zip = new ZipArchive(package, ZipArchiveMode.Read, true))
                    zip.ExtractToDirectory(staging.FullName);
                var bundle = Path.Combine(staging.FullName, "PhantomGladiator-" + version);
                if (ReadVersion(bundle) != version) throw new InvalidDataException("app/version.json");
                File.WriteAllText(Path.Combine(bundle, Marker), version.ToString());

                var destination = Path.Combine(programs, Prefix);
                if (Directory.Exists(destination) || File.Exists(destination))
                    destination += "-" + Guid.NewGuid().ToString("N");
                Directory.Move(bundle, destination);
                return destination;
            }
            finally
            {
                if (staging.Exists && staging.Parent.FullName == programs && (staging.Attributes & FileAttributes.ReparsePoint) == 0)
                {
                    try { staging.Delete(true); }
                    catch (IOException) { }
                    catch (UnauthorizedAccessException) { }
                }
            }
        }

        static void SaveShortcut(string directory, string desktop)
        {
            if (desktop.Length == 0) throw new DirectoryNotFoundException("Desktop");
            dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell", true));
            var executable = Path.Combine(directory, AppExe);
            for (int index = 1; ; index++)
            {
                var suffix = index == 1 ? "" : " (" + index + ")";
                var path = Path.Combine(desktop, "PhantomGladiator (GitHub)" + suffix + ".lnk");
                if (Directory.Exists(path)) continue;
                dynamic shortcut = shell.CreateShortcut(path);
                if (File.Exists(path))
                {
                    if (string.Equals((string)shortcut.TargetPath, executable, StringComparison.OrdinalIgnoreCase)) return;
                    continue;
                }
                shortcut.TargetPath = executable;
                shortcut.WorkingDirectory = directory;
                shortcut.Save();
                return;
            }
        }

        static bool AssistantOpen()
        {
            Mutex mutex;
            if (!Mutex.TryOpenExisting(AssistantMutex, out mutex)) return false;
            mutex.Dispose();
            return true;
        }

        static readonly Dictionary<string, string[]> Texts = new Dictionary<string, string[]>
        {
            { "zh", new[] { "PhantomGladiator 升级", "正在安装 GitHub 版…", "新版已装好。关闭正在运行的助手后，会自动打开新版。", "升级未完成。", "新版已安装，可从这个目录打开。" } },
            { "en", new[] { "PhantomGladiator upgrade", "Installing the GitHub build…", "The new build is installed. Close the running assistant to open it.", "The upgrade did not finish.", "The new build is installed. You can open it from this folder." } },
            { "ja", new[] { "PhantomGladiator の更新", "GitHub 版をインストールしています…", "新版をインストールしました。実行中のアシスタントを閉じると新版が起動します。", "更新を完了できませんでした。", "新版はこのフォルダーから起動できます。" } },
            { "fr", new[] { "Mise à niveau de PhantomGladiator", "Installation de la version GitHub…", "La nouvelle version est installée. Fermez l’assistant en cours pour l’ouvrir.", "La mise à niveau a échoué.", "La nouvelle version est installée et peut être ouverte depuis ce dossier." } },
            { "de", new[] { "PhantomGladiator aktualisieren", "GitHub-Version wird installiert…", "Die neue Version ist installiert. Schließe den laufenden Assistenten, um sie zu öffnen.", "Das Update wurde nicht abgeschlossen.", "Die neue Version ist installiert und kann aus diesem Ordner gestartet werden." } },
            { "es", new[] { "Actualización de PhantomGladiator", "Instalando la versión de GitHub…", "La nueva versión está instalada. Cierra el asistente en ejecución para abrirla.", "La actualización no se completó.", "La nueva versión está instalada y puede abrirse desde esta carpeta." } }
        };

        [STAThread]
        static void Main()
        {
            bool created;
            using (var mutex = new Mutex(true, "PhantomGladiator.GitHubUpgrade.v1", out created))
            {
                if (!created) return;
                string[] words;
                if (!Texts.TryGetValue(CultureInfo.CurrentUICulture.TwoLetterISOLanguageName, out words))
                    words = Texts["en"];

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                using (var window = new Form { Text = words[0], ClientSize = new Size(460, 108),
                    FormBorderStyle = FormBorderStyle.FixedDialog, StartPosition = FormStartPosition.CenterScreen,
                    MaximizeBox = false, MinimizeBox = false, ControlBox = false })
                {
                    var label = new Label { Text = words[1], Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter };
                    window.Controls.Add(label);
                    window.Shown += async (sender, args) =>
                    {
                        string directory = null;
                        try
                        {
                            directory = await Task.Run(() =>
                            {
                                var assembly = typeof(Upgrade).Assembly;
                                using (var stamp = new StreamReader(assembly.GetManifestResourceStream("upgrade.txt")))
                                using (var package = assembly.GetManifestResourceStream("release.zip"))
                                {
                                    var version = Version.Parse(stamp.ReadLine());
                                    var digest = stamp.ReadLine();
                                    var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                                    if (local.Length == 0) throw new DirectoryNotFoundException("LocalAppData");
                                    return Install(Path.Combine(local, "Programs", "PhantomGladiator"), package, version, digest);
                                }
                            });

                            bool shortcutSaved = true;
                            try { SaveShortcut(directory, Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory)); }
                            catch (Exception) { shortcutSaved = false; }

                            if (AssistantOpen())
                            {
                                label.Text = words[2];
                                window.ControlBox = true;
                                while (AssistantOpen()) await Task.Delay(350);
                            }
                            Process.Start(new ProcessStartInfo(Path.Combine(directory, AppExe))
                                { UseShellExecute = false, WorkingDirectory = directory });
                            if (!shortcutSaved) MessageBox.Show(window, words[4] + "\n" + directory, words[0]);
                        }
                        catch (Exception error)
                        {
                            var message = directory == null ? words[3] : words[4] + "\n" + directory;
                            MessageBox.Show(window, message + "\n\n" + error.Message, words[0], MessageBoxButtons.OK, MessageBoxIcon.Error);
                        }
                        window.Close();
                    };
                    Application.Run(window);
                }
            }
        }
    }
}
