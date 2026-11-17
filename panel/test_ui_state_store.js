// The page preferences must not depend on which local port the native window got.
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const app = readFileSync(path.join(__dirname, "prototype", "app.js"), "utf8");
const first = app.indexOf('  const STORE_PREFIX = "pg-proto.";');
const last = app.indexOf("  const REPO =", first);
assert(first >= 0 && last > first);
const section = app.slice(first, last);

function storage(initial = {}) {
  const data = new Map(Object.entries(initial));
  return new Proxy({
    getItem: key => data.has(key) ? data.get(key) : null,
    setItem: (key, value) => { data.set(key, String(value)); },
    removeItem: key => { data.delete(key); },
  }, { ownKeys: () => [...data.keys()], getOwnPropertyDescriptor: (_, key) => data.has(key) ? { enumerable: true, configurable: true, value: data.get(key) } : undefined });
}

// One launch of the page: its origin's localStorage, this run's sessionStorage, and what the window handed over.
function launch({ local = {}, session = storage(), saved, host = true } = {}) {
  const sent = [];
  const window = { __pgUiState: saved };
  if (host) window.chrome = { webview: { postMessage: message => sent.push(JSON.parse(JSON.stringify(message))) } };
  const localStorage = storage(local);
  const context = { window, localStorage, sessionStorage: session, queueMicrotask, JSON, Object };
  vm.createContext(context);
  vm.runInContext(section + "\nthis.store = store;", context);
  return { store: context.store, sent, localStorage, session };
}
const settle = () => new Promise(resolve => setImmediate(resolve));

(async () => {
  // A new port means an empty localStorage; the saved copy must bring everything back.
  let run = launch({ saved: { onboarded: "true", lang: '"en"' } });
  assert.equal(run.store.get("onboarded", false), true);
  assert.equal(run.store.get("lang", "auto"), "en");
  await settle();
  assert.deepEqual(run.sent, [], "restoring sends nothing back");

  // The saved copy is the newest state from the last run, so it replaces what this origin still holds.
  run = launch({ local: { "pg-proto.theme": '"dark"', "pg-proto.lang": '"zh"', "other.key": "kept" }, saved: { lang: '"en"', bad: 7 } });
  assert.equal(run.store.get("lang", "auto"), "en");
  assert.equal(run.store.get("theme", "light"), "light");
  assert.equal(run.store.get("bad", "none"), "none");
  assert.equal(run.localStorage.getItem("other.key"), "kept");

  // Writes in one tick go to the window as one whole-state message.
  run.store.set("onboarded", true);
  run.store.set("theme", "dark");
  await settle();
  assert.deepEqual(run.sent, [{ id: "ui-state", method: "saveUiState", params: { state: { lang: '"en"', onboarded: "true", theme: '"dark"' } } }]);
  run.store.clear();
  await settle();
  assert.deepEqual(run.sent[1].params.state, {});

  // A reload inside the same run keeps the newer values of its own origin, not the copy from launch.
  const session = storage();
  run = launch({ session, saved: { lang: '"en"' } });
  run.store.set("lang", "zh");
  const reloaded = launch({ session, local: { "pg-proto.lang": '"zh"' }, saved: { lang: '"en"' } });
  assert.equal(reloaded.store.get("lang", "auto"), "zh");

  // First launch of a build with this copy: nothing saved yet, so the page sends what the origin has.
  run = launch({ local: { "pg-proto.onboarded": "true" }, saved: null });
  await settle();
  assert.deepEqual(run.sent, [{ id: "ui-state", method: "saveUiState", params: { state: { onboarded: "true" } } }]);

  // In a plain browser there is no window to talk to and nothing changes.
  run = launch({ host: false, local: { "pg-proto.lang": '"zh"' }, saved: { lang: '"en"' } });
  run.store.set("theme", "dark");
  await settle();
  assert.equal(run.store.get("lang", "auto"), "zh");
  assert.deepEqual(run.sent, []);
  console.log("ui state store ok");
})().catch(error => { console.error(error); process.exit(1); });
