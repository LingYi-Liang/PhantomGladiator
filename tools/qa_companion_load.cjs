// Run on the prototype with the same Playwright/Edge setup as qa_companion_ui.cjs.
const assert = require("node:assert/strict");
const path = require("node:path");
const {pathToFileURL} = require("node:url");
const {chromium} = require(process.env.PG_PLAYWRIGHT || "playwright");
(async () => {
  const browser = await chromium.launch({channel: "msedge", headless: true});
  try {
    const page = await browser.newPage({locale: "en-US"});
    page.setDefaultTimeout(4000);
    await page.addInitScript(() => {
      for (const [key, value] of Object.entries({onboarded:true, autoUpdate:false, langMode:"manual", lang:"en"}))
        localStorage.setItem("pg-proto."+key, JSON.stringify(value));
    });
    await page.goto(pathToFileURL(process.argv[2] || path.resolve(__dirname,"../panel/prototype/index.html")).href);
    await page.evaluate(() => {
      const rt=window.PGRuntime, original=rt.companionManager.bind(rt);
      window.testCalls={rosters:0, stats:0};
      rt.companionManager=async () => {
        const number=++window.testCalls.rosters, data=await original();
        if (number===1) await new Promise(resolve=>{window.releaseRoster=resolve;});
        if (number>=2) data.units=[{id:"C7-preview",path:"BP_Monster_MuXiaoKui",phase:"1",profile:data.profiles.mu,revision:1,state:"following",dual:true}];
        return data;
      };
      rt.companionStats=async () => {
        window.testCalls.stats++;
        // Bound the deliberately failing old UI: even a broken version eventually settles.
        if(window.testCalls.stats<=12) throw new Error("offline stats");
        return {values:{Health_Max:111}};
      };
      rt.state.companionStats.mode="custom";
    });
    await page.locator('[data-action="cm-open"]').click();
    await page.waitForFunction(()=>typeof window.releaseRoster==="function");
    await page.evaluate(()=>{const rt=window.PGRuntime;rt.state.companionManagerRevision++;rt.setGame("ready");window.releaseRoster();});
    await page.waitForFunction(()=>!document.querySelector('[data-cm="behavior"]').disabled);
    // Drive a complete render turn without generating another manager revision.
    await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
    const found=await page.locator('#cm-scope option[value="C7-preview"]').count();
    await page.locator('[data-tab="recovery"]').click();
    await page.waitForFunction(()=>window.testCalls.stats>0);
    await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
    const counts=await page.evaluate(()=>window.testCalls);
    console.log(JSON.stringify({lateRosterPresent:found, rosterReads:counts.rosters, failedStatsRequests:counts.stats}));
    assert.equal(found,1,"a revision arriving during the first read must be delivered");
    assert.equal(counts.stats,1,"one failing stats request must not recursively repaint and retry");
    await page.evaluate(()=>{window.PGRuntime.companionStats=async()=>{window.testCalls.stats++;return {values:{Health_Max:111}};};});
    await page.locator('[data-action="stats-retry"]').click();
    await page.waitForFunction(()=>document.querySelector('input[data-field="Health_Max"]')?.value==="111");
    assert.equal(await page.evaluate(()=>window.testCalls.stats),2);
    await page.keyboard.press("Escape");
    await page.evaluate(()=>{
      const rt=window.PGRuntime, read=rt.companionManager;let fail=true;
      rt.companionManager=async()=>{if(fail){fail=false;throw new Error("unavailable");}return read();};
    });
    await page.locator('[data-action="cm-open"]').click();
    await page.locator('[data-action="cm-read"]').click();
    await page.waitForFunction(()=>!document.querySelector('[data-cm="behavior"]').disabled);
  } finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exitCode=1;});