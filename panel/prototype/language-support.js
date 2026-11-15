"use strict";

// Archived translations remain available for release history and migration notices.
const PGLanguageSupport = (() => {
  const notices = {
    ja: {
      name: "日本語", html: "ja", title: "対応言語についてのお知らせ", close: "閉じる", issue: "GitHubでIssueを作成", email: "メール",
      body: "ほかの言語でこのModを使っている方がどれくらいいるのか分からず、利用状況を知る手がかりとなるご意見も届いていません。そのため、今後は中国語版と英語版のみを更新します。ほかの言語の更新をご希望の方は、私のGitHubでIssueを作成するか、メールでご連絡ください。お使いの方が一人でもいれば、その言語の更新を継続します。ご支援ありがとうございます。",
      fallback: "画面はひとまず英語で表示されます。このお知らせは「Settings → Language」の言語設定のすぐ下で、いつでも日本語で読み直せます。",
    },
    fr: {
      name: "Français", html: "fr", title: "Avis sur les langues prises en charge", close: "Fermer", issue: "Ouvrir une issue sur GitHub", email: "E-mail",
      body: "Je ne sais pas combien de personnes utilisent mon mod dans d’autres langues et je n’ai reçu aucun retour permettant de le savoir. Je ne mettrai donc désormais à jour que les versions chinoise et anglaise. Si vous avez besoin d’une autre langue, ouvrez une issue sur mon GitHub ou envoyez-moi un e-mail. Même si une seule personne l’utilise, je continuerai à mettre cette langue à jour. Merci pour votre soutien !",
      fallback: "L’interface s’affiche provisoirement en anglais. Vous pourrez toujours relire cet avis en français juste sous le choix de la langue, dans Settings → Language.",
    },
    de: {
      name: "Deutsch", html: "de", title: "Hinweis zur Sprachunterstützung", close: "Schließen", issue: "Issue auf GitHub erstellen", email: "E-Mail",
      body: "Ich weiß nicht, wie viele Menschen meine Mod in anderen Sprachen nutzen, und habe dazu bisher keine Rückmeldungen erhalten. Deshalb werde ich künftig nur noch die chinesische und die englische Version aktualisieren. Wenn ihr eine andere Sprache benötigt, erstellt bitte ein Issue auf meinem GitHub oder schreibt mir eine E-Mail. Auch wenn nur eine einzige Person eine Sprache nutzt, werde ich sie weiter aktualisieren. Vielen Dank für eure Unterstützung!",
      fallback: "Die Oberfläche wird vorerst auf Englisch angezeigt. Diesen Hinweis könnt ihr jederzeit auf Deutsch direkt unter der Sprachauswahl in Settings → Language nachlesen.",
    },
    es: {
      name: "Español", html: "es", title: "Aviso sobre los idiomas disponibles", close: "Cerrar", issue: "Abrir un issue en GitHub", email: "Correo electrónico",
      body: "No sé cuántas personas usan mi mod en otros idiomas y no he recibido comentarios que permitan saberlo. Por eso, a partir de ahora solo actualizaré las versiones en chino e inglés. Si necesitáis otro idioma, abrid un issue en mi GitHub o enviadme un correo electrónico. Aunque solo lo use una persona, seguiré actualizando ese idioma. ¡Gracias por vuestro apoyo!",
      fallback: "La interfaz se mostrará por ahora en inglés. Podréis volver a leer este aviso en español justo debajo de la selección de idioma, en Settings → Language.",
    },
  };
  const supported = lang => I18N.ACTIVE_LANGS.some(l => l.id === lang);
  const messages = new Map(Object.entries({
    "脱战回血模块未加载": "The out-of-combat healing module is not loaded.",
    "无效的脱战回血设置": "Invalid out-of-combat healing setting.",
    "脱战回血拦截接口未就绪": "The out-of-combat healing interception interface is not ready.",
    "脱战回血设置保存未确认，旧设置继续生效": "Saving the healing setting could not be confirmed. The previous setting remains in effect.",
    "已关闭禁止脱战回血：后续恢复原版规则，不补回已拦截的血量": "Native out-of-combat healing is restored for future events. Previously blocked healing is not refunded.",
    "禁止脱战回血设置已保存，但拦截或已有回血清理未确认，请查看面板状态": "The setting was saved, but blocking healing or removing active regeneration could not be confirmed. Check the panel status.",
    "禁止脱战回血设置已保存，等待游戏就绪或召唤单位": "The setting was saved; waiting for the game to be ready or units to be summoned.",
    "已开启禁止脱战回血：仅拦截原版脱战回血，技能回血保留": "Native out-of-combat healing is blocked. Healing skills still work.",
    "只有梦华支持剧情联动设置": "Only Meng Hua supports the story-link setting.",
    "关闭技能虚化无敌（下次召唤生效）": "Skill invulnerability off (applies to the next summon).",
    "保留技能虚化无敌（下次召唤生效）": "Native skill invulnerability kept (applies to the next summon).",
    "保留梦华剧情联动（下次召唤生效）": "Keep Meng Hua's story link (applies to the next summon).",
    "跳过梦华剧情联动（下次召唤生效）": "Skip Meng Hua's story link (applies to the next summon).",
  }));
  return {
    version: "zh-en-1",
    email: "lingyi01525@gmail.com",
    notices,
    supported,
    resolve: lang => supported(lang) ? lang : notices[lang] ? "en" : "zh",
    message: text => I18N.lang === "en" ? messages.get(text) || text : text,
  };
})();

I18N.add("zh", {
  "languageSupport.heading": "语言支持说明",
  "keys.action.dismiss_companions": "解散全部随从",
  "keys.desc.dismiss_companions": "按下立即解散所有模组随从，只清理随从，不清理蓝方、红方或未配队单位；默认未绑定",
  "keys.dismiss.update": "更新并重载新版游戏内模组后，可设置解散随从快捷键。",
  "languageSupport.intro": "后续维护中文和英文。其他语言用户可以展开自己的语言说明，通过 GitHub Issue 或邮件申请恢复更新。",
  "languageSupport.menu": "语言说明 · 日本語 / Français / Deutsch / Español",
  "xianzhePhantom.keep": "技能虚化无敌：原版",
  "xianzhePhantom.off": "技能虚化无敌：关闭",
  "xianzhePhantom.tip": "弦者的闪避、进退场和部分技能带短时虚化无敌。默认保留原版；关闭后保留动作、位移与视觉特效，移除这些动作的无敌保护。只影响本次之后直召的弦者，蓝红、随从和未配队均适用。下次召唤生效。",
  "menghuaStage.keep": "剧情联动：保留",
  "menghuaStage.skip": "剧情联动：跳过",
  "menghuaStage.label": "跳过梦华剧情联动阶段",
  "menghuaStage.tip": "跳过梦华剧情联动阶段：默认关闭，保留原版。选择跳过后，该次召唤不会进入剧情虚空联动及其41%阶段保护，联动专用招式也会跳过；其他血量下限和不倒下仍生效。只影响模组直召的梦华，地图剧情不改。清理后重新召唤生效。",
  "offcombatRegen.title": "禁止脱战回血",
  "offcombatRegen.offline": "连接游戏后可设置。默认保留原版脱战回血。",
  "offcombatRegen.unsupported": "请更新并重载支持此功能的游戏内模组。",
  "offcombatRegen.failed": "拦截或已有回血清除未确认，请查看操作记录并导出诊断。",
  "offcombatRegen.waiting": "设置已保存，等待游戏就绪或召唤单位后生效。",
  "offcombatRegen.on": "已禁止模组管理单位的脱战回血；角色技能回血、吸血仍保留。",
  "offcombatRegen.off": "默认原版。开启后保留战后残血，已有和新召唤单位均生效。",
  "offcombatRegen.tip": "只拦截原版脱战逐步回血和立即回满，不锁血、不取消正常脱战，也不改变地图原生单位。已回的血不会扣回；关闭后不补回被拦截的血量。",
  "offcombatRegen.history.on": "开启禁止脱战回血",
  "offcombatRegen.history.off": "关闭禁止脱战回血",
});
I18N.add("en", {
  "languageSupport.heading": "Language support",
  "keys.action.dismiss_companions": "Dismiss all companions",
  "keys.desc.dismiss_companions": "Press to dismiss all mod companions. Blue, red and no-team units stay. Unbound by default.",
  "keys.dismiss.update": "Update and reload the in-game mod to bind companion dismissal.",
  "languageSupport.intro": "Chinese and English will receive future updates. Expand the notice in your language to request continued support through a GitHub issue or email.",
  "languageSupport.menu": "Language notices · 日本語 / Français / Deutsch / Español",
  "xianzhePhantom.keep": "Skill invulnerability: native",
  "xianzhePhantom.off": "Skill invulnerability: off",
  "xianzhePhantom.tip": "Xian Zhe's dodges, entrances, exits and some skills briefly grant invulnerability. Native behavior is the default. Turning this off removes that protection while keeping animations, movement and visual effects. Applies to subsequently summoned standalone Xian Zhe units on blue, red, companion or no team. Summon again to apply.",
  "menghuaStage.keep": "Story link: keep",
  "menghuaStage.skip": "Story link: skip",
  "menghuaStage.label": "Skip Meng Hua's story-linked phase",
  "menghuaStage.tip": "Off by default: keep the native story-linked phase. Turning this on skips the Xu Kong story link, its 41% health protection and its exclusive moves for that summon. Other health floors and Undying still apply. Only affects directly summoned Meng Hua units, not map story actors. Clear and summon again to apply.",
  "offcombatRegen.title": "Prevent out-of-combat healing",
  "offcombatRegen.offline": "Connect to the game to change this. Native out-of-combat healing is kept by default.",
  "offcombatRegen.unsupported": "Update and reload the in-game mod to use this feature.",
  "offcombatRegen.failed": "Blocking healing or removing active regeneration could not be confirmed. Check Activity and export a diagnostic report.",
  "offcombatRegen.waiting": "Setting saved; waiting for the game to be ready or units to be summoned.",
  "offcombatRegen.on": "Out-of-combat healing is blocked for mod-managed units. Healing skills and life steal still work.",
  "offcombatRegen.off": "Native behavior by default. Turn on to keep remaining health after battle; applies to existing and newly summoned units.",
  "offcombatRegen.tip": "Blocks only native gradual regeneration and instant full healing outside combat. Does not lock health, prevent normal combat exit or change native map units. Health already restored is not removed; turning this off does not refund blocked healing.",
  "offcombatRegen.history.on": "Enable prevention of out-of-combat healing",
  "offcombatRegen.history.off": "Disable prevention of out-of-combat healing",
});
