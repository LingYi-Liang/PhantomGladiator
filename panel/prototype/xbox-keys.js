"use strict";
window.PGXbox = (() => {
  // Standard Gamepad API order. The saved numbers are Windows VK_GAMEPAD codes.
  const codes = [195,196,197,198,200,199,201,202,208,207,209,210,203,204,205,206];
  const names = ["A","B","X","Y","LB","RB","LT","RT","View","Menu","LS","RS","D-pad ↑","D-pad ↓","D-pad ←","D-pad →"];
  const shoulder = i => i === 4 || i === 5;
  function label(code, mask = 0) {
    const i = codes.indexOf(code);
    return i < 0 ? "" : "Xbox " + [(mask & 1) && "LB", (mask & 2) && "RB", names[i]].filter(Boolean).join("+");
  }
  function sample(pad, previous) {
    const down = codes.map((code, i) => {
      const button = pad.buttons[i];
      return !!button && (i === 6 || i === 7 ? button.value > (previous?.down[i] ? .4 : .55) : button.pressed);
    });
    const used = previous?.used || [false, false], armed = previous?.armed || [false, false];
    const state = {down, used, armed, binding: null};
    if (!previous) return state;
    const mask = Number(down[4]) + 2 * Number(down[5]);
    for (let i = 4; i <= 5; i++) {
      if (down[i] && !previous.down[i]) { armed[i-4] = true; used[i-4] = false; }
      if (mask === 3) used[i-4] = true;
    }
    for (let i = 0; i < codes.length; i++) {
      if (shoulder(i) || !down[i] || previous.down[i]) continue;
      if (down[4]) used[0] = true;
      if (down[5]) used[1] = true;
      state.binding ||= {code: codes[i], mods: mask};
    }
    for (let i = 4; i <= 5; i++) {
      if (!down[i] && previous.down[i] && armed[i-4] && !used[i-4]) state.binding ||= {code: codes[i], mods: 0};
      if (!down[i]) armed[i-4] = used[i-4] = false;
    }
    return state;
  }
  let stopCurrent;
  function capture(active, receive, cancel) {
    stopCurrent?.();
    const picker = document.createElement("select");
    picker.className = "xbox-picker";
    const title = I18N.lang === "zh" ? "选择 Xbox 按键或组合键…" : "Choose an Xbox button or chord…";
    picker.setAttribute("aria-label", title); picker.add(new Option(title, ""));
    for (let mask = 0; mask <= 3; mask++) {
      for (const [i, code] of codes.entries()) {
        if (mask && shoulder(i)) continue;
        picker.add(new Option(label(code,mask), code + ":" + mask));
      }
    }
    let frame, stopped = false;
    const samples = new Map();
    function stop() {
      stopped = true; cancelAnimationFrame(frame); picker.remove(); window.removeEventListener("blur", blur);
      if (stopCurrent === stop) stopCurrent = null;
    }
    function blur() { if (active()) cancel(); stop(); }
    function offer(binding) { if (active()) receive(binding); if (!active()) stop(); }
    picker.addEventListener("click", e => e.stopPropagation());
    picker.addEventListener("change", () => {
      if (!picker.value) return;
      const [code, mods] = picker.value.split(":").map(Number); picker.value = ""; offer({code,mods});
    });
    function tick() {
      if (stopped) return;
      if (!active() || document.hidden) { blur(); return; }
      let pads = [];
      try { pads = navigator.getGamepads?.() || []; } catch { /* The manual picker stays available. */ }
      const live = new Set();
      for (const pad of pads) {
        if (!pad || !pad.connected || pad.mapping !== "standard") continue;
        const key = pad.index + ":" + pad.id; live.add(key);
        const state = sample(pad,samples.get(key)); samples.set(key,state);
        if (state.binding) { offer(state.binding); if (stopped) return; }
      }
      for (const key of samples.keys()) if (!live.has(key)) samples.delete(key);
      frame = requestAnimationFrame(tick);
    }
    document.body.append(picker); window.addEventListener("blur", blur);
    stopCurrent = stop; tick();
  }
  return {label,capture};
})();
