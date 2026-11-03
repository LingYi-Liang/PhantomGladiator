// Test exe for tools/test_app_update.py: what PhantomGladiator.exe does when it installs an update, with AppSwap
// from desktop/AppUpdate.cs, run for real in a temporary folder.
//   --swap <from> <report>      load Fake.dll from its own folder (a loaded DLL, as WebView2Loader.dll is in the
//                               app), swap its own folder with <from> while running, start the new exe with
//                               --wait-for and exit; if the swap fails, write the failure and the folder to <report>
//   --wait-for <pid> <report>   wait for the old process, clean up what it set aside, write the folder to <report>
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;

namespace PhantomGladiator
{
    static class AppUpdateTest
    {
        [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr LoadLibrary(string path);

        static string Dir { get { return AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\'); } }

        static string State()
        {
            var entries = Directory.GetFileSystemEntries(Dir, "*", SearchOption.AllDirectories)
                .Select(p => p.Substring(Dir.Length + 1).Replace('\\', '/')).OrderBy(p => p, StringComparer.Ordinal);
            return string.Join("\n", entries) + "\nversion=" + File.ReadAllText(Path.Combine(Dir, "app", "version.txt"));
        }

        static int Main(string[] args)
        {
            if (args.Length == 3 && args[0] == "--swap")
            {
                if (LoadLibrary(Path.Combine(Dir, "Fake.dll")) == IntPtr.Zero)
                {
                    File.WriteAllText(args[2], "failed: Fake.dll did not load");
                    return 1;
                }
                try { AppSwap.Apply(args[1], Dir); }
                catch (IOException e)
                {
                    File.WriteAllText(args[2], "failed: " + e.Message + "\n" + State());
                    return 2;
                }
                Process.Start(new ProcessStartInfo(Path.Combine(Dir, "PhantomGladiator.exe"),
                    "--wait-for " + Process.GetCurrentProcess().Id + " \"" + args[2] + "\"") { UseShellExecute = false });
                return 0;
            }
            if (args.Length == 3 && args[0] == "--wait-for")
            {
                try { using (var old = Process.GetProcessById(int.Parse(args[1]))) old.WaitForExit(30000); }
                catch (ArgumentException) { }
                AppSwap.Cleanup(Dir);
                File.WriteAllText(args[2], "ok\n" + State());
                return 0;
            }
            return 3;
        }
    }
}
