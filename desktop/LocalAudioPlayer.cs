// Isolated WAV playback. A missing parent heartbeat closes the player.
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Windows.Media;
using System.Windows.Threading;
using System.Web.Script.Serialization;

static class LocalAudioPlayer
{
    static readonly object gate = new object();
    static readonly Stopwatch clock = Stopwatch.StartNew();
    static long lastInput;
    static string pending = "";
    static bool ended;
    [STAThread]
    static int Main(string[] args)
    {
        if (args.Length != 1 || !Path.IsPathRooted(args[0]) || !args[0].EndsWith(".wav", StringComparison.OrdinalIgnoreCase)) return 2;
        Console.OutputEncoding = new UTF8Encoding(false);
        var json = new JavaScriptSerializer();
        var player = new MediaPlayer();
        string state = "opening";
        bool playing = false;
        long reported = -1000;
        Action<string> report = value => {
            state = value;
            Console.WriteLine(json.Serialize(new { state = value, position = player.Position.TotalSeconds }));
            Console.Out.Flush();
        };
        Action close = () => { ended = true; player.Close(); Dispatcher.CurrentDispatcher.BeginInvokeShutdown(DispatcherPriority.Normal); };
        player.Volume = 0;
        player.MediaOpened += (s,e) => report("ready");
        player.MediaFailed += (s,e) => { report("failed"); close(); };
        player.MediaEnded += (s,e) => { if (playing) { player.Position=TimeSpan.Zero;player.Play(); } };
        var reader = new Thread(() => {
            try {
                while (!ended) {
                    var line = new StringBuilder();
                    int ch;
                    while ((ch=Console.In.Read())>=0 && ch!='\n') { if (line.Length>=64) return; if(ch!='\r')line.Append((char)ch); }
                    if(ch<0)return;
                    lock(gate) { lastInput=clock.ElapsedMilliseconds;if(line.ToString()!="PING")pending=line.ToString(); }
                }
            } catch { }
        });
        reader.IsBackground=true;reader.Start();
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
        timer.Tick += (s,e) => {
            try {
                string command;long last;
                lock(gate) { command=pending;pending="";last=lastInput; }
                if(clock.ElapsedMilliseconds-last>2500 || command=="STOP") { close();return; }
                if(command.StartsWith("PLAY ",StringComparison.Ordinal)) {
                    int volume;
                    if(!int.TryParse(command.Substring(5),out volume)||volume<0||volume>100||state=="opening") { report("failed");close();return; }
                    player.Volume=volume/100.0;playing=true;player.Play();report("playing");
                }
                if(clock.ElapsedMilliseconds-reported>=500) { reported=clock.ElapsedMilliseconds;report(state); }
            } catch { close(); }
        };
        try { player.Open(new Uri(args[0],UriKind.Absolute));timer.Start();Dispatcher.Run(); }
        catch { try {report("failed");player.Close();}catch{}return 2; }
        return state=="failed" ? 2 : 0;
    }
}
