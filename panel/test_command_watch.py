"""Bounded command watches and real loopback Bridge -> RealRuntime completion tests."""
import http.client
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import unittest

spec = importlib.util.spec_from_file_location('watch_backend', Path(__file__).with_name('backend.py'))
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


class FixtureHandler(backend.Handler):
    def do_POST(self):
        if self.path != '/fixture/complete':
            return super().do_POST()
        if not self._trusted(write=True):
            return
        length = int(self.headers['Content-Length'])
        request = json.loads(self.rfile.read(length))
        with self.server.bridge.lock, self.server.bridge.db:
            self.server.bridge.db.execute("UPDATE commands SET state='succeeded',completed=? WHERE id=?",
                                          (time.time(), request['id']))
        self._reply(200, {'ok': True})


class CommandWatchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.bridge = backend.Bridge(Path(self.tmp.name) / 'Runtime', clock=lambda: 100.0)
        (self.bridge.runtime / 'status.tsv').write_text('schema_version\t1\nheartbeat_unix\t100' +
            '\ngame_session\tfixture\ngame_ready\ttrue\n', encoding='utf-8')
        self.server = backend.PanelServer(self.bridge, Path(__file__).parent / 'static', 0)
        self.server.RequestHandlerClass = FixtureHandler
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.bridge.close()
        self.tmp.cleanup()

    def get(self, path):
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=5)
        connection.request('GET', path)
        reply = connection.getresponse()
        result = reply.status, json.loads(reply.read())
        connection.close()
        return result

    def test_watch_is_bounded_deduplicated_and_preserves_large_ids(self):
        first = self.bridge.enqueue({'action': 'start'})['id']
        for _ in range(100):
            self.bridge.enqueue({'action': 'start'})
        self.assertNotIn(first, [row['id'] for row in self.bridge.status()['queue']])
        code, result = self.get('/api/status?watch=1,1,999999')
        self.assertEqual(code, 200)
        self.assertEqual(len(result['queue']), 100)
        self.assertEqual([row['id'] for row in result['watched_commands']], [first])
        self.assertEqual(self.get('/api/status')[1]['watched_commands'], [])
        for query in ('0', '-1', '1e2', '1%20', '1,,2', '1%29%20OR%201%3D1', '9223372036854775808',
                      ','.join(['1'] * 101), '9' * 2001, '1&watch=2'):
            with self.subTest(query=query[:40]):
                self.assertEqual(self.get('/api/status?watch=' + query)[0], 400)
        for ids in ([True], ['1'], [1.5], [backend.MAX_COMMAND_ID + 1], [1] * 101):
            with self.assertRaises(backend.ValidationError):
                self.bridge.status(ids)
        for command_id in (9007199254740993, backend.MAX_COMMAND_ID):
            with self.bridge.lock, self.bridge.db:
                self.bridge.db.execute("INSERT INTO commands(id,action,payload,state,created,game_session) VALUES(?,?,?,?,?,?)",
                    (command_id, 'start', '{"action":"start"}', 'succeeded', time.time(), 'fixture'))
            code, result = self.get('/api/status?watch=' + str(command_id))
            self.assertEqual(code, 200)
            self.assertEqual(result['watched_commands'][0]['id'], str(command_id))

    def test_real_frontend_receives_a_result_outside_the_history_window(self):
        script = r'''
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const base=process.argv[1],source=fs.readFileSync(process.argv[2],'utf8');
const context={window:{},document:{documentElement:{lang:'zh'}},AbortController,Date,setTimeout,clearTimeout,
  fetch:(path,options)=>fetch(base+path,options)};
const delay=ms=>new Promise(done=>setTimeout(done,ms));
vm.runInNewContext(source,context);
(async()=>{
  const rt=context.window.PGRuntime;
  for(let i=0;i<100&&rt.state.game!=='ready';i++)await delay(20);
  assert.equal(rt.state.game,'ready');
  const pending=rt.command('start');
  for(let i=0;i<100&&!rt.jobs.length;i++)await delay(20);
  assert(rt.jobs.length);const id=rt.jobs[0].id;
  const state=await(await fetch(base+'/api/status')).json();
  const headers={'Content-Type':'application/json','X-CSRF-Token':state.csrf_token};
  for(let i=0;i<100;i++)assert.equal((await fetch(base+'/api/command',{method:'POST',headers,body:'{"action":"start"}'})).status,202);
  const oldWindow=await(await fetch(base+'/api/status')).json();
  assert.equal(oldWindow.queue.length,100);assert(!oldWindow.queue.some(row=>String(row.id)===String(id)));
  await fetch(base+'/fixture/complete',{method:'POST',headers,body:JSON.stringify({id})});
  const result=await Promise.race([pending,delay(6000).then(()=>{throw Error('completed command lost behind history window')})]);
  assert.equal(result.status,'succeeded');assert.equal(rt.jobs.length,100);
  console.log('real Bridge HTTP -> RealRuntime watch completion: PASS');process.exit(0);
})().catch(error=>{console.error(error);process.exit(1)});
'''
        source = os.environ.get('PG_TEST_RUNTIME_SOURCE') or str(Path(__file__).parent / 'prototype/real-runtime.js')
        result = subprocess.run(['node', '-e', script, self.server.origin, source], capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout.decode(errors='replace') + result.stderr.decode(errors='replace'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
