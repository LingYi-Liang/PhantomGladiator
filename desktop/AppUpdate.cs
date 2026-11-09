// Keep the files replaced by one update in its own backup directory. The running exe and loaded DLLs can be
// renamed on the same volume. Cleanup only retires backups marked complete after a successful swap.
// C# 5 / .NET Framework 4.8; compiled into PhantomGladiator.exe and, for tools/test_app_update.py, a test exe.
using System;
using System.Collections.Generic;
using System.IO;

namespace PhantomGladiator
{
    static class AppSwap
    {
        const string BackupPrefix = ".pg-app-swap-";
        const string CompleteMarker = "PhantomGladiatorAppSwapV1";

        // from: the unpacked new version (the folder holding PhantomGladiator.exe); to: the app's folder.
        public static void Apply(string from, string to)
        {
            to = Path.GetFullPath(to);
            var backup = Path.Combine(to, BackupPrefix + Guid.NewGuid().ToString("N"));
            var previous = Path.Combine(backup, "files");
            Directory.CreateDirectory(previous);
            var saved = new List<string>();
            var added = new List<string>();
            try
            {
                foreach (var source in Directory.GetFileSystemEntries(from))
                {
                    var name = Path.GetFileName(source);
                    var target = Path.Combine(to, name);
                    if (Directory.Exists(target) || File.Exists(target))
                    {
                        Move(target, Path.Combine(previous, name));
                        saved.Add(name);
                    }
                    added.Add(target);
                    if (Directory.Exists(source)) CopyTree(source, target); else File.Copy(source, target);
                }
                var marker = Path.Combine(backup, "marking");
                File.WriteAllText(marker, CompleteMarker);
                File.Move(marker, Path.Combine(backup, "complete"));
            }
            catch (Exception e)
            {
                var errors = new List<Exception> { e };
                foreach (var path in added)
                    try { Remove(path); } catch (Exception failure) { errors.Add(failure); }
                foreach (var name in saved)
                    try { Move(Path.Combine(previous, name), Path.Combine(to, name)); }
                    catch (Exception failure) { errors.Add(failure); }
                if (errors.Count > 1)
                    throw new IOException("助手更新恢复未完成，旧文件已保留在 " + backup, new AggregateException(errors));
                try { Remove(backup); } catch (Exception) { }
                throw new IOException(e.Message, e);
            }
        }

        // A missing completion marker can mean a swap was interrupted or its rollback failed.
        public static void Cleanup(string dir)
        {
            foreach (var path in Directory.GetDirectories(Path.GetFullPath(dir), BackupPrefix + "*"))
            {
                var name = Path.GetFileName(path);
                Guid id;
                if (!name.StartsWith(BackupPrefix, StringComparison.Ordinal) ||
                    !Guid.TryParseExact(name.Substring(BackupPrefix.Length), "N", out id)) continue;
                try
                {
                    if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) continue;
                    var marker = Path.Combine(path, "complete");
                    if (!File.Exists(marker) || File.ReadAllText(marker) != CompleteMarker) continue;
                    // Keep the marker until the old files can all be removed.
                    Remove(Path.Combine(path, "files"));
                    Remove(path);
                }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
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
            if (Directory.Exists(path)) Directory.Delete(path, true);
            else if (File.Exists(path)) File.Delete(path);
        }

        static void Move(string from, string to)
        {
            if (Directory.Exists(from)) Directory.Move(from, to);
            else File.Move(from, to);
        }
    }
}
