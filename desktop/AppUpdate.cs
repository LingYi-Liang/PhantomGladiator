// Replacing the app's files with a new version while the app runs. A running exe and the DLLs it has loaded
// can be renamed but not overwritten, so each top-level file or folder the new version brings is renamed to
// <name>.old and the new one copied in; if anything fails, what was copied is removed and the .old ones are
// renamed back, so the old version still starts. The new exe deletes the .old leftovers once this process has
// exited (Cleanup). Nothing else is written or run: versions before 0.37.6 copied the exe to AppData as
// updater.exe and ran that copy, which Windows Defender took for a trojan.
// C# 5 / .NET Framework 4.8; compiled into PhantomGladiator.exe and, for tools/test_app_update.py, a test exe.
using System;
using System.Collections.Generic;
using System.IO;

namespace PhantomGladiator
{
    static class AppSwap
    {
        public const string Aside = ".old";

        // from: the unpacked new version (the folder holding PhantomGladiator.exe); to: the app's folder.
        public static void Apply(string from, string to)
        {
            Cleanup(to);
            var moved = new List<string>();
            var added = new List<string>();
            try
            {
                foreach (var source in Directory.GetFileSystemEntries(from))
                {
                    var target = Path.Combine(to, Path.GetFileName(source));
                    if (Directory.Exists(target)) { Directory.Move(target, target + Aside); moved.Add(target); }
                    else if (File.Exists(target)) { File.Move(target, target + Aside); moved.Add(target); }
                    added.Add(target);
                    if (Directory.Exists(source)) CopyTree(source, target); else File.Copy(source, target);
                }
            }
            catch (Exception e)
            {
                foreach (var path in added) Remove(path);
                foreach (var path in moved) Restore(path);
                throw new IOException(e.Message, e);
            }
        }

        // Deletes what an earlier swap set aside; anything still in use stays for the next start.
        public static void Cleanup(string dir)
        {
            foreach (var path in Directory.GetFileSystemEntries(dir))
                if (path.EndsWith(Aside, StringComparison.OrdinalIgnoreCase)) Remove(path);
        }

        static void CopyTree(string from, string to)
        {
            Directory.CreateDirectory(to);
            foreach (var dir in Directory.GetDirectories(from, "*", SearchOption.AllDirectories))
                Directory.CreateDirectory(Path.Combine(to, dir.Substring(from.Length + 1)));
            foreach (var file in Directory.GetFiles(from, "*", SearchOption.AllDirectories))
                File.Copy(file, Path.Combine(to, file.Substring(from.Length + 1)));
        }

        static void Remove(string path)
        {
            try
            {
                if (Directory.Exists(path)) Directory.Delete(path, true);
                else if (File.Exists(path)) File.Delete(path);
            }
            catch (Exception) { }
        }

        static void Restore(string path)
        {
            try
            {
                if (Directory.Exists(path + Aside)) Directory.Move(path + Aside, path);
                else if (File.Exists(path + Aside)) File.Move(path + Aside, path);
            }
            catch (Exception) { }
        }
    }
}
