// C# 5 / .NET Framework 4. No HTTP, Python, NuGet or game API calls.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

namespace PhantomGladiator.Desktop
{
    public sealed class UnitRecord
    {
        public string Id { get; set; }
        public string Name { get; set; }
        public string Category { get; set; }
        public string ClassPath { get; set; }
        public bool? Loaded { get; set; }
        public bool? Spawnable { get; set; }
        public string Reason { get; set; }
        public string NativeParent { get; set; }
    }

    public sealed class JobRecord
    {
        public string Id { get; set; }
        public string Action { get; set; }
        public string UnitId { get; set; }
        public string Team { get; set; }
        public int Count { get; set; }
        public Dictionary<string, string> Bindings { get; set; }
        public string Status { get; set; }
        public string Message { get; set; }
        public int? SpawnedCount { get; set; }
        public string CreatedAt { get; set; }
        public string SentAt { get; set; }
        public string CompletedAt { get; set; }
    }

    public sealed class RuntimeSnapshot
    {
        public string RuntimePath { get; set; }
        public bool GameOnline { get; set; }
        public string GameState { get; set; }
        public string Message { get; set; }
        public string TransportError { get; set; }
        public Dictionary<string, string> GameStatus { get; set; }
        public Dictionary<string, string> KeyBindings { get; set; }
        public Dictionary<string, string> RequestedKeyBindings { get; set; }
        public List<UnitRecord> Units { get; set; }
        public List<JobRecord> Jobs { get; set; }
        public bool CatalogAvailable { get; set; }
        public bool CatalogPartial { get; set; }
        public int CatalogTotal { get; set; }
        public int ExcludedNonUnits { get; set; }
        public string CatalogError { get; set; }
        public string CatalogState { get; set; }
        public string CatalogMessage { get; set; }
        public int? CatalogPathsDone { get; set; }
        public int? CatalogPathsTotal { get; set; }
        public int? BlueCount { get; set; }
        public int? RedCount { get; set; }
        public int? NeutralCount { get; set; }
        public string CurrentUnit { get; set; }
        public string CurrentTeam { get; set; }
        public int? CurrentCount { get; set; }
        public bool? SpectatorEnabled { get; set; }
    }

    public sealed class QueueDocument
    {
        public int SchemaVersion { get; set; }
        public List<JobRecord> Jobs { get; set; }
        public Dictionary<string, string> RequestedKeyBindings { get; set; }
    }

    public sealed class RuntimeClient : IDisposable
    {
        private const string NpcParent = "/Script/ProjectPBZ.PBZCharacter_NPC";
        private const string CatalogHeader = "id\tname\tcategory\tclass_path\tloaded\tspawnable\treason";
        private const int MaxCatalogBytes = 32 * 1024 * 1024;
        private const int MaxQueueBytes = 8 * 1024 * 1024;
        private static readonly UTF8Encoding Utf8 = new UTF8Encoding(false, true);
        private static readonly DateTime Epoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        private static readonly string[] BindingActions = { "spawn", "start", "stop", "refresh_catalog" };
        private static readonly string[] Keys = { "F1", "F2", "F3", "F4", "F5", "F9", "F11",
            "NUM_ZERO", "NUM_ONE", "NUM_TWO", "NUM_THREE", "NUM_FOUR", "NUM_FIVE", "NUM_SIX", "NUM_SEVEN", "NUM_EIGHT", "NUM_NINE" };
        private static readonly HashSet<string> KeySet = new HashSet<string>(Keys, StringComparer.Ordinal);
        private static readonly HashSet<string> Actions = new HashSet<string>(new[] {
            "spawn", "select_unit", "start", "stop", "refresh_catalog", "configure_keys", "toggle_spectator" }, StringComparer.Ordinal);
        private static readonly HashSet<string> NonUnits = new HashSet<string>(new[] {
            "/Script/SGameCombatSystem.SGameGameplayAbility", "/Script/PBZCombatAsset.WeaponActorBase",
            "/Script/PBZCombatAsset.WeaponActorBase_NoSkeletalMesh", "/Script/PBZCombatAsset.PBZ_ProjectileBullet",
            "/Script/SGameCombatSystem.BulletEventBase", "/Script/Engine.Actor", "/Script/Engine.ActorComponent" }, StringComparer.Ordinal);
        private readonly object gate = new object();
        private readonly string root;
        private readonly JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength = MaxQueueBytes };
        private FileStream lease;
        private QueueDocument store;
        private bool disposed;
        private string transportError;

        public static string[] AllowedKeys { get { return (string[])Keys.Clone(); } }
        public string RuntimePath { get { return root; } }

        public RuntimeClient(string runtimePath)
        {
            if (String.IsNullOrWhiteSpace(runtimePath)) throw new ArgumentException("必须指定 Mod 的 Runtime 目录。", "runtimePath");
            root = Path.GetFullPath(runtimePath).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            Directory.CreateDirectory(root);
            try
            {
                lease = new FileStream(FilePath("panel.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.ReadWrite);
                if (lease.Length == 0) { lease.WriteByte(0); lease.Flush(true); }
                try { lease.Lock(0, 1); }
                catch (IOException error) { throw new IOException("此 Runtime 已被网页后端或另一个修改器占用。请先关闭原服务；修改器不会强制结束进程。", error); }
                string saved = ReadText("desktop-queue.json", MaxQueueBytes, false);
                store = saved == null ? NewStore() : json.Deserialize<QueueDocument>(saved);
                ValidateStore(store);
            }
            catch
            {
                if (lease != null) lease.Dispose();
                lease = null;
                throw;
            }
        }

        private static QueueDocument NewStore()
        {
            return new QueueDocument { SchemaVersion = 1, Jobs = new List<JobRecord>(), RequestedKeyBindings = new Dictionary<string, string>() };
        }

        private static void ValidateStore(QueueDocument document)
        {
            if (document == null || document.SchemaVersion != 1 || document.Jobs == null)
                throw new InvalidDataException("desktop-queue.json 无法识别；未重建队列，避免重复执行。");
            if (document.RequestedKeyBindings == null) document.RequestedKeyBindings = new Dictionary<string, string>();
            var ids = new HashSet<string>(StringComparer.Ordinal);
            int pending = 0;
            foreach (JobRecord job in document.Jobs)
            {
                if (job == null || job.Id == null || !Regex.IsMatch(job.Id, @"^desktop-[0-9a-f]{32}$") || !ids.Add(job.Id) || !Actions.Contains(job.Action))
                    throw new InvalidDataException("桌面队列损坏；不自动重放或覆盖。");
                if (job.Status == "pending") pending++;
                else if (job.Status != "queued" && job.Status != "succeeded" && job.Status != "failed" && job.Status != "uncertain")
                    throw new InvalidDataException("桌面队列含未知状态。");
                Wire(job);
            }
            if (pending > 1) throw new InvalidDataException("桌面队列存在多条未确认投递；暂停以避免重复执行。");
        }

        private void EnsureOpen() { if (disposed) throw new ObjectDisposedException("RuntimeClient"); }
        private string FilePath(string name)
        {
            if (name.IndexOfAny(new[] { '/', '\\' }) >= 0 || name == "." || name == "..") throw new InvalidDataException("非法 Runtime 文件名。");
            string path = Path.Combine(root, name);
            if (File.Exists(path) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("Runtime 文件为重解析点，拒绝访问: " + name);
            return path;
        }

        private string ReadText(string name, int limit, bool completeLines)
        {
            string path = FilePath(name);
            if (!File.Exists(path)) return null;
            byte[] bytes;
            try
            {
                using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (var memory = new MemoryStream())
                {
                    byte[] buffer = new byte[8192]; int count;
                    while ((count = stream.Read(buffer, 0, Math.Min(buffer.Length, limit + 1 - (int)memory.Length))) > 0)
                    {
                        memory.Write(buffer, 0, count);
                        if (memory.Length > limit) throw new InvalidDataException(name + " 超过读取上限。");
                    }
                    bytes = memory.ToArray();
                }
            }
            catch (FileNotFoundException) { return null; }
            int length = bytes.Length;
            if (completeLines && length > 0 && bytes[length - 1] != 10)
            {
                int newline = Array.LastIndexOf(bytes, (byte)10);
                length = newline + 1; // Drop the unfinished line before strict UTF-8 decoding.
            }
            string text = Utf8.GetString(bytes, 0, length);
            return text.Length > 0 && text[0] == '\uFEFF' ? text.Substring(1) : text;
        }

        private void AtomicWrite(string name, string text)
        {
            string target = FilePath(name), temporary = FilePath(name + ".desktop-" + Guid.NewGuid().ToString("N") + ".tmp");
            try
            {
                byte[] bytes = Utf8.GetBytes(text);
                using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                { output.Write(bytes, 0, bytes.Length); output.Flush(true); }
                if (File.Exists(target)) File.Replace(temporary, target, null);
                else File.Move(temporary, target);
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }

        private void Save()
        {
            string text = json.Serialize(store);
            if (Utf8.GetByteCount(text) > MaxQueueBytes) throw new InvalidDataException("桌面队列达到容量上限；未继续投递。");
            AtomicWrite("desktop-queue.json", text);
        }

        private static string Value(Dictionary<string, string> values, string key)
        { string found; return values.TryGetValue(key, out found) ? found : null; }
        private static int? Integer(string text)
        { int number; return Int32.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out number) ? (int?)number : null; }
        private static bool? Boolean(string text)
        { if (text == "1" || text == "true") return true; if (text == "0" || text == "false") return false; return null; }
        private static double UnixNow() { return (DateTime.UtcNow - Epoch).TotalSeconds; }
        private static string Timestamp() { return DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture); }
        private static bool Finite(double number) { return !Double.IsNaN(number) && !Double.IsInfinity(number); }

        private Dictionary<string, string> ReadStatus(out bool online, out string error)
        {
            online = false; error = null;
            var values = new Dictionary<string, string>(StringComparer.Ordinal);
            try
            {
                string text = ReadText("status.tsv", 65536, false);
                if (text == null) { error = "等待游戏写入状态。"; return values; }
                foreach (string raw in text.Split('\n'))
                {
                    string line = raw.TrimEnd('\r'); if (line.Length == 0) continue;
                    string[] parts = line.Split('\t');
                    if (parts.Length != 2) throw new InvalidDataException("status.tsv 格式错误。");
                    values[parts[0]] = parts[1];
                }
                double heartbeat;
                if (Value(values, "schema_version") != "1" || !Double.TryParse(Value(values, "heartbeat_unix"), NumberStyles.Float, CultureInfo.InvariantCulture, out heartbeat) || !Finite(heartbeat))
                    throw new InvalidDataException("游戏状态缺少有效版本或心跳。");
                double age = UnixNow() - heartbeat;
                online = age >= 0 && age <= 15;
                if (!online) error = "游戏心跳已过期，未确认在线。";
            }
            catch (Exception exception)
            {
                if (!(exception is IOException) && !(exception is UnauthorizedAccessException) && !(exception is DecoderFallbackException)) throw;
                error = exception.Message;
            }
            return values;
        }

        public static string ParseNativeParent(string reason)
        {
            string found = null; int count = 0;
            foreach (string part in (reason ?? "").Split(';'))
                if (part.StartsWith("native_parent=", StringComparison.Ordinal)) { found = part.Substring(14).Trim(); count++; }
            if (count != 1) return null;
            if (Regex.IsMatch(found, @"^/Script/[A-Za-z0-9_]+\.[A-Za-z0-9_]+$")) return found;
            Match wrapped = Regex.Match(found, @"^(?:/Script/[A-Za-z0-9_]+\.[A-Za-z0-9_]+|Class|BlueprintGeneratedClass)?(['""\"])(/Script/[A-Za-z0-9_]+\.[A-Za-z0-9_]+)\1$");
            return wrapped.Success ? wrapped.Groups[2].Value : null;
        }

        private void ReadCatalog(RuntimeSnapshot snapshot)
        {
            snapshot.Units = new List<UnitRecord>();
            try
            {
                string final = FilePath("catalog.tsv"), partial = FilePath("catalog.tsv.partial");
                bool usePartial = false;
                if (File.Exists(partial) && (snapshot.CatalogState == "scanning" || !File.Exists(final)))
                {
                    double started; double modified = (File.GetLastWriteTimeUtc(partial) - Epoch).TotalSeconds;
                    if (Double.TryParse(Value(snapshot.GameStatus, "catalog_started_at"), NumberStyles.Float, CultureInfo.InvariantCulture, out started) && Finite(started) && started > 0)
                        usePartial = modified >= started;
                    else if (File.Exists(final)) usePartial = File.GetLastWriteTimeUtc(partial) > File.GetLastWriteTimeUtc(final);
                }
                string text = ReadText(usePartial ? "catalog.tsv.partial" : "catalog.tsv", MaxCatalogBytes, usePartial);
                if (text == null && usePartial) { text = ReadText("catalog.tsv", MaxCatalogBytes, false); usePartial = false; }
                if (text == null) return;
                string[] rows = text.Split('\n');
                if (rows.Length == 0 || rows[0].TrimEnd('\r') != CatalogHeader) throw new InvalidDataException("catalog.tsv 表头不匹配。");
                var seen = new HashSet<string>(StringComparer.Ordinal);
                int invalid = 0;
                for (int index = 1; index < rows.Length; index++)
                {
                    string line = rows[index].TrimEnd('\r'); if (line.Length == 0) continue;
                    string[] fields = line.Split('\t');
                    if (fields.Length != 7 || fields[0].Length == 0 || fields[1].Length == 0 || fields[3].Length == 0 || !seen.Add(fields[0])
                        || (fields[4] != "0" && fields[4] != "1" && fields[4] != "unknown") || (fields[5] != "0" && fields[5] != "1" && fields[5] != "unknown"))
                    { invalid++; continue; }
                    string native = ParseNativeParent(fields[6]);
                    if (native != null && NonUnits.Contains(native)) { snapshot.ExcludedNonUnits++; continue; }
                    var unit = new UnitRecord { Id = fields[0], Name = fields[1], Category = fields[2], ClassPath = fields[3],
                        Loaded = Boolean(fields[4]), Spawnable = Boolean(fields[5]), Reason = fields[6], NativeParent = native };
                    if (native != NpcParent) { unit.Spawnable = false; unit.Reason = "npc_identity_unknown;NPC身份未验证；" + unit.Reason; }
                    if (unit.ClassPath.EndsWith("_Base_C", StringComparison.Ordinal)) { unit.Spawnable = false; unit.Reason = "基类不可召唤；" + unit.Reason; }
                    snapshot.Units.Add(unit);
                }
                snapshot.CatalogAvailable = true; snapshot.CatalogPartial = usePartial; snapshot.CatalogTotal = snapshot.Units.Count;
                if (invalid > 0) snapshot.CatalogError = invalid.ToString(CultureInfo.InvariantCulture) + " 条目录记录无效，已跳过。";
            }
            catch (Exception error)
            {
                if (!(error is IOException) && !(error is UnauthorizedAccessException) && !(error is DecoderFallbackException)) throw;
                snapshot.CatalogError = error.Message;
            }
        }

        public RuntimeSnapshot ReadSnapshot()
        {
            lock (gate)
            {
                EnsureOpen(); bool online; string statusError;
                var status = ReadStatus(out online, out statusError);
                var snapshot = new RuntimeSnapshot { RuntimePath = root, GameOnline = online, GameStatus = status,
                    GameState = Value(status, "state") ?? "unavailable", Message = statusError ?? Value(status, "message"), TransportError = transportError,
                    KeyBindings = new Dictionary<string, string>(), RequestedKeyBindings = new Dictionary<string, string>(store.RequestedKeyBindings),
                    CatalogState = Value(status, "catalog_state"), CatalogMessage = Value(status, "catalog_message"),
                    CatalogPathsDone = Integer(Value(status, "catalog_paths_done")), CatalogPathsTotal = Integer(Value(status, "catalog_paths_total")),
                    BlueCount = Integer(Value(status, "blue_count")), RedCount = Integer(Value(status, "red_count")), NeutralCount = Integer(Value(status, "neutral_count")),
                    CurrentUnit = Value(status, "current_unit"), CurrentTeam = Value(status, "current_team"), CurrentCount = Integer(Value(status, "current_count")),
                    SpectatorEnabled = Boolean(Value(status, "spectator_enabled") ?? Value(status, "spectator") ?? Value(status, "neutral_enabled")),
                    Jobs = new List<JobRecord>() };
                foreach (string action in BindingActions) snapshot.KeyBindings[action] = Value(status, "key_" + action);
                for (int index = Math.Max(0, store.Jobs.Count - 100); index < store.Jobs.Count; index++) snapshot.Jobs.Add(Clone(store.Jobs[index]));
                ReadCatalog(snapshot);
                return snapshot;
            }
        }

        private JobRecord Clone(JobRecord job) { return json.Deserialize<JobRecord>(json.Serialize(job)); }
        private static void CheckField(string value, string name, int byteLimit, bool allowEmpty)
        {
            if (value == null || (!allowEmpty && value.Length == 0) || Utf8.GetByteCount(value) > byteLimit) throw new ArgumentException(name + " 超过长度限制或为空。");
            foreach (char letter in value) if (letter < 32 || letter == 127) throw new ArgumentException(name + " 不允许控制字符。");
        }
        private static void CheckBindings(Dictionary<string, string> bindings)
        {
            if (bindings == null || bindings.Count != 4) throw new ArgumentException("需要四个快捷键。");
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (string action in BindingActions)
            {
                string key;
                if (!bindings.TryGetValue(action, out key) || key == null || !KeySet.Contains(key) || !seen.Add(key))
                    throw new ArgumentException("快捷键必须互不重复；F6/F7相机、F8无仇恨、F10/F12保留。");
            }
        }

        public JobRecord Enqueue(string action, string unitId = "", string team = "blue", int count = 1, Dictionary<string, string> bindings = null)
        {
            lock (gate)
            {
                EnsureOpen();
                if (action == null || !Actions.Contains(action)) throw new ArgumentException("不支持的动作。");
                if (action == "spawn" || action == "select_unit")
                {
                    CheckField(unitId, "unit_id", 512, false);
                    if (team != "blue" && team != "red" && team != "neutral") throw new ArgumentException("队伍无效。");
                    if (count < 1 || count > 8) throw new ArgumentException("数量必须为1到8。");
                    UnitRecord unit = ReadSnapshot().Units.Find(delegate(UnitRecord item) { return item.Id == unitId; });
                    if (unit == null || unit.Spawnable == false) throw new ArgumentException("所选单位不在可尝试召唤的真实目录中。");
                }
                else { unitId = ""; team = "blue"; count = 1; }
                if (action == "configure_keys") CheckBindings(bindings);
                else if (bindings != null && bindings.Count > 0) throw new ArgumentException("此动作不接受快捷键字段。");
                var job = new JobRecord { Id = "desktop-" + Guid.NewGuid().ToString("N"), Action = action, UnitId = unitId, Team = team,
                    Count = count, Bindings = bindings == null ? new Dictionary<string, string>() : new Dictionary<string, string>(bindings),
                    Status = "queued", Message = "等待发送与游戏回执", CreatedAt = Timestamp() };
                Wire(job);
                QueueDocument previous = json.Deserialize<QueueDocument>(json.Serialize(store));
                store.Jobs.Add(job);
                if (action == "configure_keys") store.RequestedKeyBindings = new Dictionary<string, string>(bindings);
                try { Save(); } catch { store = previous; throw; }
                return Clone(job);
            }
        }

        private static string Wire(JobRecord job)
        {
            CheckField(job.Id, "id", 80, false); CheckField(job.UnitId ?? "", "unit_id", 512, true);
            if (!Actions.Contains(job.Action) || (job.Team != "blue" && job.Team != "red" && job.Team != "neutral") || job.Count < 1 || job.Count > 8)
                throw new InvalidDataException("持久指令字段无效。");
            var fields = new List<string> { job.Id, job.Action, job.UnitId ?? "", job.Team, job.Count.ToString(CultureInfo.InvariantCulture) };
            foreach (string action in BindingActions)
            {
                string key = job.Bindings == null ? null : Value(job.Bindings, action);
                CheckField(key ?? "", "key", 32, true); fields.Add(key ?? "");
            }
            if (job.Action == "configure_keys") CheckBindings(job.Bindings);
            fields.Add("1"); string wire = String.Join("\t", fields.ToArray()) + "\n";
            if (Utf8.GetByteCount(wire) > 2048) throw new InvalidDataException("指令超过2048字节。");
            return wire;
        }

        private static bool Terminal(string status) { return status == "succeeded" || status == "failed" || status == "uncertain"; }
        private void PruneHistory()
        {
            for (int index = 0; store.Jobs.Count > 1000 && index < store.Jobs.Count;)
            { if (Terminal(store.Jobs[index].Status)) store.Jobs.RemoveAt(index); else index++; }
        }

        public void Tick()
        {
            lock (gate)
            {
                EnsureOpen(); transportError = null;
                try
                {
                    JobRecord current = store.Jobs.Find(delegate(JobRecord job) { return job.Status == "pending"; });
                    string inbox = ReadText("inbox.tsv", 8192, false);
                    if (current != null)
                    {
                        string ack = ReadText("ack.tsv", 8192, false);
                        if (!String.IsNullOrEmpty(ack))
                        {
                            if (!ack.EndsWith("\n", StringComparison.Ordinal)) throw new InvalidDataException("ACK尚未完整写入，继续等待。");
                            string[] parts = ack.TrimEnd('\n', '\r').Split('\t');
                            if (parts.Length != 4 || parts[2].IndexOfAny(new[] { '\n', '\r' }) >= 0) throw new InvalidDataException("ack.tsv 格式错误。");
                            if (parts[0] == current.Id)
                            {
                                if (parts[1] != "ok" && parts[1] != "error" && parts[1] != "uncertain") throw new InvalidDataException("ACK状态无效。");
                                int? spawned = parts[3] == "unknown" || parts[3] == "" ? null : Integer(parts[3]);
                                if ((spawned.HasValue && (spawned.Value < 0 || spawned.Value > 8)) || (!spawned.HasValue && parts[3] != "unknown" && parts[3] != ""))
                                    throw new InvalidDataException("ACK生成数量无效。");
                                if (parts[1] == "ok" && current.Action == "spawn" && !spawned.HasValue) throw new InvalidDataException("成功召唤必须有实际读回数量。");
                                if (inbox != null && inbox.Split('\t')[0] != current.Id) throw new InvalidDataException("inbox属于另一指令，保留文件并暂停。");
                                string newState = parts[1] == "ok" ? "succeeded" : parts[1] == "error" ? "failed" : "uncertain";
                                if (parts[2].IndexOf("uncertain", StringComparison.OrdinalIgnoreCase) >= 0) newState = "uncertain";
                                string oldStatus = current.Status, oldMessage = current.Message;
                                current.Status = newState; current.Message = parts[2]; current.SpawnedCount = spawned; current.CompletedAt = Timestamp();
                                try { Save(); } catch { current.Status = oldStatus; current.Message = oldMessage; current.CompletedAt = null; current.SpawnedCount = null; throw; }
                                if (inbox != null) File.Delete(FilePath("inbox.tsv"));
                                inbox = null; current = null;
                            }
                        }
                        if (current != null)
                        {
                            if (inbox == null) transportError = "未确认指令的inbox已不在；等待同ID回执，不自动重放。";
                            return;
                        }
                    }
                    if (inbox != null)
                    {
                        // Recover a crash after durable ACK storage but before inbox deletion.
                        string oldId = inbox.Split('\t')[0];
                        JobRecord done = store.Jobs.Find(delegate(JobRecord job) { return job.Id == oldId && Terminal(job.Status); });
                        if (done != null && inbox == Wire(done)) { File.Delete(FilePath("inbox.tsv")); inbox = null; }
                        else { transportError = "存在未归属的inbox（可能来自旧网页后端）；未覆盖，暂停投递。"; return; }
                    }
                    JobRecord next = store.Jobs.Find(delegate(JobRecord job) { return job.Status == "queued"; });
                    if (next != null)
                    {
                        next.Status = "pending"; next.SentAt = Timestamp(); next.Message = "已投递，等待游戏同ID回执";
                        try { Save(); } catch { next.Status = "queued"; next.SentAt = null; throw; }
                        // Commit first. A crash before publication stays visibly pending,
                        // rather than replaying a possibly executed command after restart.
                        AtomicWrite("inbox.tsv", Wire(next));
                    }
                    PruneHistory();
                }
                catch (Exception error)
                {
                    if (!(error is IOException) && !(error is UnauthorizedAccessException) && !(error is DecoderFallbackException) && !(error is ArgumentException)) throw;
                    transportError = error.Message;
                }
            }
        }

        public RuntimeSnapshot Poll() { lock (gate) { Tick(); return ReadSnapshot(); } }
        public void Dispose()
        {
            lock (gate)
            {
                if (disposed) return;
                disposed = true;
                if (lease != null) { try { lease.Unlock(0, 1); } catch (IOException) { } lease.Dispose(); lease = null; }
            }
        }
    }
}
