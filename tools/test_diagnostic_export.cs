using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Threading.Tasks;

namespace PhantomGladiator
{
    static class DiagnosticExportTests
    {
        static void Write(string folder, DateTime time, string content, out string path)
        {
            using (var zip = MainForm.CreateReportArchive(folder, time, out path))
            using (var writer = new StreamWriter(zip.CreateEntry("test.txt").Open())) writer.Write(content);
        }
        static string Read(string path)
        {
            using (var zip = ZipFile.OpenRead(path))
            using (var reader = new StreamReader(zip.GetEntry("test.txt").Open())) return reader.ReadToEnd();
        }
        static int Main(string[] args)
        {
            try { Run(args); return 0; }
            catch (Exception error)
            {
                Console.WriteLine("FAIL " + error.GetType().FullName + " HRESULT=" + error.HResult);
                return 1;
            }
        }
        static void Run(string[] args)
        {
            var folder = args[0];
            var time = new DateTime(2026, 1, 2, 3, 4, 5);
            string first, second;
            Write(folder, time, "first", out first);
            Write(folder, time, "second", out second);
            if (first == second || Read(first) != "first" || Read(second) != "second")
                throw new Exception("repeated exports must preserve each completed report");
            Console.WriteLine("PASS two exports in the same second create separate valid archives");
            var paths = new string[8];
            Parallel.For(0, paths.Length, i => Write(folder, time, "parallel-" + i, out paths[i]));
            if (paths.Distinct(StringComparer.OrdinalIgnoreCase).Count() != paths.Length)
                throw new Exception("simultaneous report names collided");
            for (var i = 0; i < paths.Length; i++)
                if (Read(paths[i]) != "parallel-" + i) throw new Exception("parallel report data lost");
            if (Read(first) != "first") throw new Exception("an existing report was overwritten");
            Console.WriteLine("PASS simultaneous exports keep distinct paths and preserve existing reports");
            var missing = Path.Combine(folder, "missing");
            try
            {
                string ignored;
                using (MainForm.CreateReportArchive(missing, time, out ignored)) { }
                throw new Exception("missing directory unexpectedly accepted");
            }
            catch (DirectoryNotFoundException) { }
            Console.WriteLine("PASS missing-directory failures are propagated without creating files");
        }
    }
}
