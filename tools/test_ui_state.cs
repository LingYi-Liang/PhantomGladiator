using System;
using System.Collections.Generic;
using System.IO;
using System.Web.Script.Serialization;

namespace PhantomGladiator
{
    static class UiStateTests
    {
        static void Check(bool ok, string what)
        {
            if (!ok) throw new Exception(what);
            Console.WriteLine("PASS " + what);
        }

        static string Refused(Action action)
        {
            try { action(); }
            catch (HostError error) { return error.Code; }
            return "";
        }

        static int Main()
        {
            try { Run(); return 0; }
            catch (Exception error)
            {
                Console.WriteLine("FAIL " + error.Message);
                return 1;
            }
        }

        static void Run()
        {
            var file = Path.Combine(Paths.Data, "ui-state.json");
            Check(!File.Exists(file) && UiState.LoadScript() == "window.__pgUiState=null;", "nothing saved yet hands the page null");

            var state = new Dictionary<string, object> {
                { "onboarded", "true" }, { "lang", "\"zh\"" }, { "note", "</script><script>alert(1)" + (char)0x2028 + "'" },
                { "", "dropped" }, { "number", 5 }, { new string('k', 65), "dropped" } };
            UiState.Save(state);
            var script = UiState.LoadScript();
            Check(script.StartsWith("window.__pgUiState={") && script.EndsWith("};"), "saved state comes back as one assignment");
            Check(script.IndexOf('<') < 0 && script.IndexOf((char)0x2028) < 0 && script.IndexOf('\'') < 0, "values cannot close the script or the statement");
            var back = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(script.Substring("window.__pgUiState=".Length).TrimEnd(';'));
            Check(back.Count == 3 && (string)back["onboarded"] == "true" && (string)back["lang"] == "\"zh\"" && (string)back["note"] == (string)state["note"],
                "string values survive unchanged and other entries are dropped");

            UiState.Save(new Dictionary<string, object> { { "theme", "\"dark\"" } });
            back = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(file));
            Check(back.Count == 1 && (string)back["theme"] == "\"dark\"" && !File.Exists(file + ".tmp"), "a later save replaces the whole file");

            Check(Refused(() => UiState.Save(null)) == "uiState", "a malformed save is refused");
            Check(Refused(() => UiState.Save(new Dictionary<string, object> { { "big", new string('x', 1024 * 1024 + 1) } })) == "uiState", "an oversized save is refused");
            back = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(file));
            Check(back.Count == 1 && (string)back["theme"] == "\"dark\"", "refused saves leave the file as it was");

            File.WriteAllText(file, "{ not json");
            Check(UiState.LoadScript() == "window.__pgUiState=null;", "a damaged file hands the page null");
            File.WriteAllText(file, "[1,2]");
            Check(UiState.LoadScript() == "window.__pgUiState=null;", "a file of the wrong shape hands the page null");
        }
    }
}
