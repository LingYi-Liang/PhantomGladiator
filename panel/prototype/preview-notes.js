// Cumulative notes after each stable base. Each paragraph part is available from its first beta build.
window.PG_PREVIEW_NOTES = {
  "0.40.18": {
    "title": {
      "zh": "龙柱五战与擂台对战更新",
      "en": "Dragon Pillar trials and arena combat"
    },
    "added": [
      [
        {
          "since": 3,
          "zh": "补齐龙柱第 2、3、4 战的魔渊。现在五战都能单独召唤，各自使用原版数值和招式。",
          "en": "Added Mó Yuan’s second, third and fourth Dragon Pillar trials. All five encounters can now be summoned separately with their original stats and moves."
        },
        {
          "since": 2,
          "zh": "第一战的金面具黑衣人可以在卡面关闭虚化，下次召唤生效。",
          "en": "The Gold-Masked One’s card lets you turn off his trial protection for the next summon."
        }
      ],
      [
        {
          "since": 2,
          "zh": "最终战魔渊在红蓝擂台开战也会响起原版战斗曲。进入二阶段时切歌，战后恢复场景音乐。",
          "en": "The final-trial Mó Yuan can now play his native boss theme in the arena. The music changes in phase two and the map soundtrack returns when the fight ends."
        }
      ]
    ],
    "combat": [
      [
        {
          "since": 3,
          "zh": "烈焰召出小狮子后，对手会先清她这一波。谁处决最后一只、戴上狮头，谁就上桩挑战她。同场多组烈焰各自配对。",
          "en": "Flame’s opponents now go after her cubs first. The fighter who executes the last cub and gets the lion head earns the pole duel against that Flame, even with multiple groups in the arena."
        },
        {
          "since": 2,
          "zh": "首跳受阻时，NPC 会换方向重试。",
          "en": "NPCs can retry a blocked first jump from another direction."
        }
      ],
      [
        {
          "since": 3,
          "zh": "毕峰的残血终结抓现在允许 NPC 反制。被抓者优先，无法行动时，附近正在交战的队友也有机会接手。玉鼎的斩杀投则需要 NPC 对这一下打出精准闪避，才能接上收尾。",
          "en": "NPCs can counter Bi Feng’s low-health grab. The grabbed fighter has first chance, and an engaged teammate nearby can respond if it cannot act. Against Yuding’s execution grab, the NPC must perfect-dodge that attack to perform the counter."
        }
      ],
      [
        {
          "since": 1,
          "zh": "魂自动处决 NPC 时会看对手剩余血量，默认常态 10%、破防 20%。两项都能自定义，填 0 可关闭对应状态的自动处决。",
          "en": "Hun’s automatic executions now check the target’s remaining HP. The defaults are 10% normally and 20% during guard break. Both are adjustable. Set either to 0 to disable executions in that state."
        }
      ],
      [
        {
          "since": 4,
          "zh": "AI「全部拉满」同时强化进攻和闪避，四组共 65 项参数仍可单独调整。用过旧预设的玩家，重新点一次「全部拉满 → 保存并应用」即可。",
          "en": "Max everything now boosts attacks and dodges together. All 65 settings can still be adjusted individually or by group. To replace an old preset, choose Max everything, then Save and apply."
        }
      ]
    ],
    "fixes": [
      [
        {
          "since": 2,
          "zh": "修复魔渊二阶段砸火柱被打断后，火柱特效跟着他移动的问题。",
          "en": "Fixed the pillar effect following summoned Mó Yuan when his phase-two slam is interrupted."
        }
      ],
      [
        {
          "since": 3,
          "zh": "修复角色下坠时把半空误记为安全落点的问题。",
          "en": "Fixed a mid-air position being saved as a safe landing point during a fall."
        },
        {
          "since": 2,
          "zh": "双方一起坠落时会尝试返回已确认的地面，跟踪镜头向下移动时也会检查地形。",
          "en": "If both fighters fall, recovery can use a previously confirmed floor. The tracking camera now checks the terrain as it follows a target downward."
        }
      ],
      [
        {
          "since": 5,
          "zh": "修正桌面快捷方式和助手内版本号显示过旧的问题。",
          "en": "Fixed the desktop shortcut and assistant showing an outdated version."
        },
        {
          "since": 6,
          "zh": "更新窗口可直接查看当前安装版本的完整公告。",
          "en": "The updater now shows the full notes for the build you have installed."
        }
      ]
    ],
    "details": [
      {
        "since": 3,
        "issue": 22,
        "zh": "毕峰在自身血量 15% 或以下时会优先选终结抓。反制沿用原版 6 米范围和行动条件，支持红蓝擂台及开启随从处决后的地图交战。玩家被抓时仍由玩家操作。不同 NPC 的反制动画还待实战观察。",
        "en": "Bi Feng prioritizes the grab at 15% HP or less. The counter uses the original 6-metre reach and action checks, in arena fights and map encounters with companion boss executions enabled. The player keeps control when grabbed. Animations on different NPC rigs still need a live check."
      },
      {
        "since": 2,
        "issue": 21,
        "zh": "烈焰首跳遇到角色或本场木桩时最多重试两次。完整的桩上对射还待实机确认。",
        "en": "The first jump can be retried twice if a fighter or a pole in the same arena blocks it. The full pole duel still needs an in-game check."
      },
      {
        "since": 3,
        "issue": 19,
        "zh": "五战参考等级依次为 10、10、19、25、26。中英文卡片按战次排列，支持用悲泣溪谷、血色森林、戏梦山庄、庞镇、梅谷湖遗迹搜索。地点由你选，遇到哪一战由试炼进度决定。新卡也能单独指定本地配乐。",
        "en": "Reference levels are 10, 10, 19, 25 and 26. Cards are numbered in both languages. Search by Weeping Creek Valley, Crimson Forest, Mirage Estate, Pang Town or Meigu Lake Ruins. Trial progress determines which encounter appears at a site. The new cards also support local music assignments."
      },
      {
        "since": 2,
        "issue": 19,
        "zh": "金面具的虚化默认使用原版规则。卡面切到「虚化：解除」后作用于下一次直接召唤，实际伤害表现待实战观察。",
        "en": "The Gold-Masked One defaults to native protection. Switching it off applies to the next direct summon. Damage in the encounter still needs a live check."
      },
      {
        "since": 2,
        "issue": 18,
        "zh": "骑兵持续朝错误目标挥空还在排查。诊断已记录骑手与坐骑各自的目标、朝向、距离和高差。",
        "en": "Persistent mounted attacks at the wrong target are still under investigation. Diagnostics now include both targets, facing, range and elevation."
      },
      {
        "since": 2,
        "issue": 17,
        "zh": "只清理招式结束后仍持续挂在魔渊本体上的火柱，实际消退表现待实战观察。",
        "en": "Cleanup targets the lingering effect attached to Mó Yuan after the move ends. Its visual disappearance still needs in-game confirmation."
      },
      {
        "since": 4,
        "issue": 16,
        "zh": "「规则 → 调整 AI 参数」里可以预览和微调。近中距离走位、近战来袭和弹道来袭分别判断闪避。规则页已补说明，并增加了龙柱投出时魔渊的动作和破防记录，实战闪避频率待确认。",
        "en": "Open Rules → Adjust AI parameters to preview and edit the preset. Footwork, melee reactions and projectile reactions have separate dodge choices. Diagnostics capture Mó Yuan’s action and guard-break state at projectile launch. Actual dodge frequency still needs a live check."
      },
      {
        "since": 2,
        "issue": 15,
        "zh": "雷当低于 10% 血量且满足阶段条件时，会按原版 AI 优先选转阶段招式。工单已按原版机制关闭。",
        "en": "Below 10% HP, Lei Dang’s native AI prioritizes the phase-transition attack when its conditions are met. The issue was closed as native behavior."
      },
      {
        "since": 3,
        "issue": 14,
        "zh": "已接入玉鼎专用的精准闪避反制。不同 NPC 骨架的表现，以及反馈中的另一处 E 键提示，仍待现场确认。",
        "en": "The dedicated perfect-dodge counter is connected. Its animation on different NPC rigs and the separate E prompt mentioned in the report still need confirmation."
      },
      {
        "since": 3,
        "issue": 13,
        "zh": "召唤出生点和救援都会核实地面。召唤者脚下悬空时，替身等到有支撑再归位。突然下坠会记录前后高度，追命两个变体带人穿地的最初触发动作仍在追查。",
        "en": "Spawn placement and rescue verify ground support. A stand waits before returning to an airborne summoner. Sudden drops are logged. The move that first pulls fighters underground in the two Hunt encounters is still being investigated."
      },
      {
        "since": 2,
        "issue": 12,
        "zh": "魔渊交战配乐使用默认原版音乐模式，剧情音乐优先。切歌的实际听感待实战确认。",
        "en": "Mó Yuan’s arena theme uses native music mode. Story music takes priority. The audible transition still needs a live check."
      },
      {
        "since": 2,
        "issue": 8,
        "zh": "玉璧沿用原版替身时序，永久保留替身的变体暂缓。",
        "en": "Yubi retains her native summon timing. A permanent-double variant is deferred."
      },
      {
        "since": 1,
        "zh": "魂的设置在「角色属性 → 处决」。0.01 代表目标剩余 1%，保存方案后重新召唤生效。距离和原有处决条件仍需满足。",
        "en": "Hun’s two thresholds are in the execution attributes. Enter 0.01 for 1% remaining HP. Save and summon Hun again. The usual range and execution conditions still apply."
      }
    ]
  },
  "0.40.19": {
    "title": {
      "zh": "战斗流畅性、魂的外观与快捷键修复",
      "en": "Combat performance, Hun outfits and hotkey fixes"
    },
    "added": [],
    "combat": [],
    "fixes": [
      [
        {
          "since": 1,
          "zh": "修复了序章左殇或梦华在擂台挨玉鼎的斩杀投后，明明还活着却一直倒地或陷在慢动作里的问题。对手受阶段锁血保护时，玉鼎会使用普通投。",
          "en": "Fixed prologue Zuo Shang and Meng Hua staying down or moving in slow motion after surviving Yuding’s lethal grab in the arena. Yuding uses her regular grab while their phase HP floor is active.",
          "legacy": {
            "zh": "玉鼎投技后，受锁血保护的对手可以起身。",
            "en": "Protected opponents recover from Yuding’s grab."
          }
        }
      ],
      [
        {
          "since": 1,
          "zh": "修复了关闭梦华的剧情联动后，重新召唤她并开战，双方有时仍站在原地不动的问题。",
          "en": "Fixed both sides sometimes standing idle at the start of a fight after Meng Hua was summoned with story assists disabled.",
          "legacy": {
            "zh": "梦华跳过剧情联动后可正常开战。",
            "en": "Meng Hua engages with story assists off."
          }
        }
      ],
      [
        {
          "since": 1,
          "zh": "修复了断魂山银发左殇在红蓝对战中放金色剑雨时，剑雨有时会落向旁观玩家的问题。剑雨现在会跟随左殇的对手。",
          "en": "Fixed golden sword rain from silver-haired Zuo Shang of Mount Soulrend sometimes landing on the spectating player during Blue vs Red battles. The rain now follows his opponent.",
          "legacy": {
            "zh": "银发左殇的金色剑雨追踪对手。",
            "en": "Silver-haired Zuo Shang’s sword rain follows his foe."
          }
        }
      ],
      [
        {
          "since": 1,
          "zh": "修复了最终战魔渊进入二阶段时战斗音乐可能中断的问题。使用原版音乐或让助手自动选曲时，都能接续二阶段曲目。",
          "en": "Fixed battle music cutting out when final-battle Mo Yuan enters phase two. His second-phase theme now continues in both Native and Auto modes.",
          "legacy": {
            "zh": "魔渊进入二阶段可以接续配乐。",
            "en": "Mo Yuan’s phase-two music continues."
          }
        }
      ],
      [
        {
          "since": 3,
          "zh": "修复魂在换装延迟加载时头身错位的问题。整套外观对齐后才切换，骨架不合时保留原外观。",
          "en": "Fixed split heads and bodies on late-loading Hun outfits. A new outfit is shown only once its pose matches.",
          "legacy": {
            "zh": "魂的延迟换装等头身对齐后再显示。",
            "en": "Late Hun outfits wait for the head and body to align."
          }
        }
      ],
      [
        {
          "since": 3,
          "zh": "修复随从卡在战斗状态后站着不动的问题。卡住时重试追敌，目标消失后重新索敌或跟随玩家。",
          "en": "Fixed stalled companions. They retry pursuit, seek a new enemy or follow the player when a target is gone.",
          "legacy": {
            "zh": "卡住的随从重试追敌或跟随。",
            "en": "Stalled companions resume pursuit or follow."
          }
        }
      ],
      [
        {
          "since": 4,
          "zh": "进入地图或手动刷新目录时，助手会分批读取图鉴、刷怪配置和单位等级。单项读取失败会重试，面板指令仍能响应。状态没有变化时也减少了重复写盘。",
          "en": "The assistant loads the codex, spawns and unit levels in separate steps when entering a map or refreshing the catalog. Commands still work if a read fails, and unchanged status uses fewer disk writes.",
          "legacy": {
            "zh": "分批读取目录，读取失败继续响应指令。",
            "en": "Staged catalog reads keep commands responsive."
          }
        }
      ],
      [
        {
          "since": 4,
          "zh": "自定义 AI 参数分批核对。已经通过游戏回调生效的数值不再反复查询，被游戏改回的数值会单独恢复。",
          "en": "Custom AI settings are checked in batches. Values confirmed through the game callback skip redundant reads, and a changed value is repaired individually.",
          "legacy": {
            "zh": "减少 AI 参数重复查询，恢复被改回的数值。",
            "en": "AI checks are batched and changed values restored."
          }
        }
      ],
      [
        {
          "since": 4,
          "zh": "普通随从活动时，助手优先检查直属召唤物，减少整图扫描。多条召唤记录给出冲突的阵营时，等归属明确后再接管。",
          "en": "Companions check directly owned summons between map sweeps. Conflicting records must agree on the summon’s side before the assistant adopts it.",
          "legacy": {
            "zh": "减少随从整图扫描，核实召唤物阵营。",
            "en": "Fewer map sweeps and verified summon allegiance."
          }
        }
      ],
      [
        {
          "since": 4,
          "zh": "多只魂同时检查换装时共用一次玩家外观读取。其他外观 Mod 替换分身身体后，助手会撤下旧部件，避免旧头部重新出现或卸载时改回旧模型。",
          "en": "Simultaneous Hun outfit checks share one player lookup. If another mod replaces a clone’s body, the assistant removes its old parts and preserves the replacement on unload.",
          "legacy": {
            "zh": "多只魂共用换装读取，撤下残留旧部件。",
            "en": "Hun shares outfit checks and clears obsolete parts."
          }
        }
      ],
      [
        {
          "since": 4,
          "zh": "修复已被占用的旧快捷键阻止保存其他快捷键的问题。有冲突的绑定会在对应功能下提示，其他空闲按键可以正常保存。",
          "en": "A conflicting saved hotkey now shows an error on its own action. You can still save free keys for other actions.",
          "legacy": {
            "zh": "旧快捷键的冲突只影响对应功能。",
            "en": "A blocked hotkey no longer stops other key edits."
          }
        }
      ],
      [
        {
          "since": 5,
          "zh": "自定义难度现在能正确识别未达到门槛的单位。进图后分次查找难度规则，已经核实的单位减少重复查询。",
          "en": "Custom difficulty now recognizes units below a difficulty threshold. Rule lookups run on separate updates, and verified units need fewer repeat checks.",
          "legacy": {
            "zh": "修正难度误报，分批检查。",
            "en": "Fixed false difficulty alerts."
          }
        }
      ],
      [
        {
          "since": 5,
          "zh": "战斗音乐、血条或诊断读取偶尔出错时，战斗和增援仍会继续。出错的功能稍后自动重试。卸载时也会逐项停止快捷键和战斗回调。",
          "en": "Fights and reinforcements continue if music, health bars or diagnostics encounter a read error. The affected feature retries later. Hotkeys and battle callbacks are stopped individually on unload.",
          "legacy": {
            "zh": "音乐或血条出错时战斗继续。",
            "en": "Fights survive HUD or music errors."
          }
        }
      ],
      [
        {
          "since": 5,
          "zh": "多只魂同场时会错开武器判断，每只魂仍按原有间隔出招。魂偶尔读不到目标或战斗计时未能启动时会重试，重生后会忽略上一条命留下的回调。",
          "en": "Groups of Hun stagger their weapon checks while keeping each fighter’s usual interval. Failed timer starts and transient decision errors retry. Callbacks from a previous life can no longer issue inputs after revival.",
          "legacy": {
            "zh": "多魂错开武器判断，决策可重试。",
            "en": "Hun staggers weapon checks and retries."
          }
        }
      ],
      [
        {
          "since": 5,
          "zh": "魂的喝药动作在启动过程中被打断时，会保留这次药量。药已耗尽时减少重复读取。死亡标记仍在时，短暂回血也不会反复开启黑魔伤的重生等待。",
          "en": "An interruption before the drinking animation finishes starting now preserves the charge. An empty flask skips redundant checks. Brief HP gains while Hun is still marked dead no longer reopen the rebirth window.",
          "legacy": {
            "zh": "修复扣药时机和重生等待。",
            "en": "Fixed flask and rebirth timing."
          }
        }
      ],
      [
        {
          "since": 5,
          "zh": "修复魂的影之武装接第二段时，已被打断或已换目标仍接着出招的问题。延迟启动的后续招式也会核对原来的对手。",
          "en": "Hun now drops a Shadow Weapon follow-up if the chain was interrupted or its opponent changed. Delayed follow-ups also check the original target before continuing.",
          "legacy": {
            "zh": "影武接段会核实原对手。",
            "en": "Shadow combos recheck their target."
          }
        }
      ],
      [
        {
          "since": 5,
          "zh": "反复进出自由观战后，旧镜头回调不会再移动新镜头。连续传送时，已结束的观察不会干扰下一次传送，防坠保护到期后会立即停止拉回。",
          "en": "Re-entering free spectate no longer lets an old camera callback move the new view. An expired teleport watch can no longer act on a later trip or pull you back after fall protection ends.",
          "legacy": {
            "zh": "清理观战和传送旧回调。",
            "en": "Fixed stale camera and teleport updates."
          }
        }
      ]
    ],
    "details": [
      {
        "since": 1,
        "issue": 26,
        "zh": "魔渊卡片的「锁血后：打死」在最终锁血线生效。血量还在锁血线以上时，对手仍有机会触发普通处决。",
        "en": "The kill option on Mo Yuan’s card takes effect at his final HP floor. Opponents can still perform a regular execution above that floor."
      }
    ]
  },
  "0.40.20": {
    "title": {
      "zh": "魂的独立外观与擂台对战修复",
      "en": "Independent Hun outfits and arena fixes"
    },
    "added": [
      [
        {
          "since": 1,
          "zh": "魂的方案新增「外观来源」。默认跟随本体，选「分身独立」可固定默认服装、保留召唤魂原模型或使用绝影分身模型。保存后，按钮和快捷键召唤的新魂都会使用这项设置。",
          "en": "Choose an appearance source in Hun’s profile. Follow player is the default. Independent clone can wear the default outfit, keep the summoned NPC model, or use the Shadow Double mesh. Summon buttons and hotkeys use the saved choice for new clones.",
          "legacy": {"zh": "魂的方案可选跟随本体或分身独立。", "en": "Hun can follow the player’s outfit or use an independent look."}
        }
      ],
      [
        {
          "since": 2,
          "zh": "新增「召唤时定格」。穿好一套衣服召一只魂，再换装召下一只，每只都会保留自己出生时已显示的装束和染色。排队召唤同样按每只实际出生时取外观。",
          "en": "Choose Capture on summon in Hun’s appearance settings. Wear one outfit, summon Hun, then change before summoning the next. Each clone keeps the outfit and dye visible when it spawns, including queued summons."
        }
      ],
      [
        {
          "since": 3,
          "zh": "诊断包现在会记录梦华随从的攻击弹打中了谁、冷荼持续隐身时的本体状态，以及玉鼎斩杀时对手有没有打出精闪。",
          "en": "Diagnostics now record who was hit by companion Menghua’s projectiles, Lengtu’s mesh state during prolonged invisibility, and NPC perfect dodges during Yuding’s execution grab.",
          "legacy": {"zh": "补充三种战斗诊断。", "en": "Added boss diagnostics."}
        }
      ]
    ],
    "combat": [
      [
        {
          "since": 4,
          "zh": "七星剑阵：大师兄和悲痛欲绝的阿瑾在卡片选择「配合阵容：带队」后，召到红蓝擂台会各带六名队员。大师兄使用原版七人起手阵，阿瑾在首次迎敌时使用梅谷湖的「爆脸转化」。同场多组各认自己的队员。",
          "en": "Enable Entourage on the card for the Chief Disciple of the Seven-Stars Formation or Grief-Stricken Jin to bring six disciples into the arena. The Chief Disciple opens with the seven-person formation. Jin performs her ambush transformation on first engaging an opponent. Each party has its own members.",
          "legacy": {"zh": "大师兄和阿瑾带队上擂台，使用原版开场和阵位。", "en": "Sword formations use their own openings and positions."}
        }
      ],
      [
        {
          "since": 4,
          "zh": "剑阵 AI 可以按原版条件让同组弟子献血，为受伤的主将恢复生命。大师兄也能选中符合复活条件的白衣弟子，接原版起身和回血动作。",
          "en": "The sword formations use the game’s conditions for members to sacrifice HP and heal their leader. The Chief Disciple can also select a fallen white-robed disciple for the original revival and recovery sequence.",
          "legacy": {"zh": "接入献血和白衣弟子复起。", "en": "Restored blood donation and white-robed disciple revival."}
        }
      ]
    ],
    "fixes": [
      [
        {
          "since": 1,
          "zh": "修复跟随本体时，本体的染色在分身出生后才加载，分身一直停在默认色的问题。分批复查可读取的材质参数，并保留其他 Mod 已接管的分身材质槽。",
          "en": "Hun now picks up supported dye and material changes that finish loading after a summon. Checks are spread across clones and leave material slots taken over by other mods alone."
        }
      ],
      [
        {
          "since": 3,
          "zh": "整队接力开战后，即使首批有单位还没锁定对手，后续候补也会保留，本方这一批打完后照常补位。",
          "en": "Once a relay fight starts, reserves stay queued even if some opening fighters take longer to acquire a target. Replacements enter when their wave is defeated.",
          "legacy": {"zh": "接力开战保留候补。", "en": "Relay reserves retained."}
        }
      ],
      [
        {
          "since": 3,
          "zh": "烈焰的桩挤在一起时，拿到狮头的 NPC 现在可以在起跳途中连续避开多根木桩，并在落脚前恢复桩体碰撞。",
          "en": "In Flame’s pole arena, the fighter wearing the lion head can clear several overlapping posts in one jump. The landing post supports the fighter again before touchdown.",
          "legacy": {"zh": "修复密集木桩挡住首跳。", "en": "Fixed crowded pole jumps."}
        }
      ],
      [
        {
          "since": 3,
          "zh": "修复随从弹体换目标失败却仍报告成功的问题。梦华的攻击弹会核对自己锁定的敌人，仍指向玩家或空目标时放弃这次锁定。",
          "en": "Companion projectiles now verify their target after a failed redirect. If a Menghua projectile still points at the player or has no target, the selector retries the enemy and rejects an unconfirmed lock.",
          "legacy": {"zh": "随从弹体会核对目标。", "en": "Companion projectile targets are verified."}
        }
      ],
      [
        {
          "since": 3,
          "zh": "对手确认阵亡后，参战 NPC 会在当前动作结束后清掉仍指向它的锁定。这也适用于最后一个敌人倒下的情况。",
          "en": "Arena fighters release a lingering lock on a defeated opponent once their current action finishes, including when the last enemy falls.",
          "legacy": {"zh": "清理仍指向阵亡敌人的锁定。", "en": "Fighters release dead opponents."}
        }
      ],
      [
        {
          "since": 3,
          "zh": "大师兄和阿瑾整组阵亡后，会清理长期留在场上的本组遗体。主将先倒时，活着的小弟继续战斗；组内发生复活会重新计时。",
          "en": "Lingering bodies are cleaned up after the eldest disciple’s or Ajin’s entire formation falls. Surviving members keep fighting if the leader dies first. A revival restarts the cleanup timer.",
          "legacy": {"zh": "整组阵亡后清理剑阵遗体。", "en": "Defeated sword formations are cleaned up."}
        }
      ],
      [
        {
          "since": 5,
          "zh": "多人擂台减少重复查询。阿瑾和大师兄多组同场时会共用一次场上名单核对。修复剑阵召唤中断后可能留下隐藏物件的问题，清场遇到游戏暂时拒绝时会稍后重试。",
          "en": "Crowded arena fights need fewer checks, and Ajin’s and the Chief Disciple’s formations share one battlefield roster scan. Interrupted summons now clean up hidden formation actors. If the game temporarily refuses cleanup, the assistant retries after a short delay.",
          "legacy": {"zh": "群战减少重复查询，修复剑阵残留。", "en": "Fewer crowd checks. Fixed formation cleanup."}
        }
      ],
      [
        {
          "since": 5,
          "zh": "开启免仇恨观战时，助手会减少全图搜索，继续逐批检查敌人是否锁定玩家。切换地图会立即刷新，刚用助手召出的敌人也会立即处理。",
          "en": "With no-aggro enabled, the assistant searches the map less often while continuing to check enemies for a lock on the player. It refreshes on map changes and handles enemies summoned by the assistant immediately.",
          "legacy": {"zh": "减少观战扫图。", "en": "Fewer spectator scans."}
        }
      ]
    ],
    "details": [
      {
        "since": 3,
        "issue": 31,
        "zh": "诊断包会记录梦华随从弹体造成伤害时的目标和血量，以及冷荼在后期阶段持续隐身时的本体状态。紫球、落扇和冷荼的现场表现仍待复核。",
        "en": "Diagnostics record targets and HP during companion Menghua projectile damage calls, and Lengtu’s mesh state if she stays hidden in her later phases. The reported orbs, falling fans and invisibility still need in-game confirmation."
      },
      {
        "since": 3,
        "issue": 35,
        "zh": "新增玉鼎斩杀的诊断记录，能查看这次攻击是否读到 NPC 精准闪避，以及游戏是否接受反制请求。",
        "en": "Diagnostics for Yuding’s execution grab now show whether a matching NPC perfect dodge was observed and whether the game accepted the counter request."
      }
    ]
  },
  "0.40.21": {
    "title": {
      "zh": "Xbox 手柄快捷键",
      "en": "Xbox controller hotkeys"
    },
    "added": [
      [
        {
          "since": 1,
          "zh": "设置快捷键时可以直接按 Xbox 手柄按钮，或从列表选择。支持单键、LB 或 RB 加另一键，以及两个肩键一起加另一键。魂、单位卡、怪物池、天气和传送地点都沿用各自的绑定和冲突提示。",
          "en": "Bind Xbox buttons by pressing them or choosing from the list. Use one button or hold LB, RB, or both with another button. Hun, unit cards, pools, weather and teleport destinations use their existing binding and conflict controls.",
          "legacy": {
            "zh": "Xbox 手柄支持独立快捷键和 LB、RB 组合。",
            "en": "Xbox shortcuts support individual buttons and LB/RB combinations."
          }
        }
      ],
      [
        {
          "since": 3,
          "zh": "右栏保留随从摘要、召回和遣散。通行、不倒下、处决及完整属性表移入「随从设置」。原属性入口可直接打开对应页，切页或刷新状态时保留输入。",
          "en": "Open Companion settings from the right sidebar for passage, Undying, executions and the full stat form. Recall and dismiss are still in the sidebar. Stat shortcuts open the relevant section and drafts survive status refreshes.",
          "legacy": {
            "zh": "随从设置移入宽面板。",
            "en": "Companion settings now have a dedicated panel."
          }
        }
      ]
    ],
    "combat": [
      [
        {
          "since": 3,
          "zh": "沐小葵可以作为一名双阶段随从召唤。少主和铁玉女王仍能单独召唤。双阶段可选脱战还原、变身后持续、手动切换或固定任一形态。变身血线由助手设置，铁玉女王仍受原有剧情进度保护。",
          "en": "Summon Mu Xiaokui as one dual-form companion or use either original card. Choose automatic transformation with or without returning after combat, manual switching, or a fixed form. Set the HP threshold yourself. The second form still requires the existing story-progress check.",
          "legacy": {
            "zh": "新增双阶段沐小葵和五种形态策略。",
            "en": "Dual-form Mu Xiaokui with five form policies."
          }
        }
      ],
      [
        {
          "since": 3,
          "zh": "在随从设置里可以选择主动迎敌、受攻击时反击或和平跟随，调整跟随距离、自动脱困、新仇恨与脱战回血。支持设置默认值、沐小葵角色配置或单个场上随从。~~沐小葵可在安全的非战斗时刻尝试原生合影动作。~~ 本版未加入合影功能。",
          "en": "Set combat behavior, following distance, automatic rescue, eligibility for new aggro and out-of-combat healing for future summons, Mu Xiaokui, or one live companion. ~~Both forms can try their own photo pose outside combat.~~ Photo mode is not included in this release.",
          "legacy": {
            "zh": "新增跟随、交战、脱战回血和单体指令。",
            "en": "Companion behavior, healing and individual commands."
          }
        }
      ]
    ],
    "fixes": [
      [
        {
          "since": 2,
          "zh": "玉鼎抓住处于阶段锁血的序章左殇或梦华后，按实际受招者判断是否致死。技能的锁定对象变化时，已抓住的角色仍有阶段保护。序章左殇的 4% 血线补救也会等原生抓取结束再解除。",
          "en": "Yu Ding’s grabs check the fighter actually caught when prologue Zuo Shang or Menghua is protected by a phase HP floor, even if the lock-on target changes. The prologue’s 4% recovery waits for the native grab to end before releasing the floor.",
          "legacy": {
            "zh": "玉鼎按实际受招者判断阶段保护。",
            "en": "Yu Ding checks the phase protection of the fighter she caught."
          }
        }
      ],
      [
        {
          "since": 2,
          "zh": "梦华在红蓝擂台卡在 41% 血线时，如果已经满足原版召唤条件，助手会等手头的动作结束，再请求她召出自己的虚空。后续配对与阶段解锁沿用原版流程。",
          "en": "If Menghua stalls at her 41% HP floor in the arena after meeting the game’s summon requirements, the assistant waits for her current action to finish and requests her own Xu Kong. The game handles the pairing and phase unlock.",
          "legacy": {
            "zh": "梦华 41% 血线可重试原版召唤。",
            "en": "Menghua can retry her native summon at 41% HP."
          }
        }
      ],
      [
        {
          "since": 3,
          "zh": "切换形态时先核对阵营、生命和杀气比例，再回收旧形态和它的配合单位。受处决、传送或目标变化影响时会暂缓。新形态切换及多人长时间跟随仍待游戏内验证。",
          "en": "Form changes check allegiance and HP and Sha-Chi ratios before retiring the old body and its helpers. Executions, travel or a target change can defer a switch. Form changes and extended group play await in-game verification.",
          "legacy": {
            "zh": "形态切换及长时间跟随待实机验证。",
            "en": "Form changes and long sessions await in-game tests."
          }
        }
      ],
      [
        {
          "since": 4,
          "zh": "多名沐小葵同时达到变身条件时会轮流切换，轮到之前重新检查血量和战斗状态。多名女王同时倒下时分批回收替身，集中遣散时合并归属检查。",
          "en": "Mu Xiaokui companions take turns changing form and recheck HP and combat before each change. When several queens fall at once, cleanup is spread out. Dismissing a group checks helper ownership together.",
          "legacy": {
            "zh": "多人换形、回收替身分批处理。",
            "en": "Spaced out form changes and helper cleanup."
          }
        }
      ],
      [
        {
          "since": 4,
          "zh": "修复随从待命后目标暂时读不到，或从和平切回主动时可能原地不动的问题。多人交战时减少重复索敌、仇恨和回血查询；替身的诊断记录达到上限后停止额外动作采样。",
          "en": "Companions can resume following when their target is temporarily unreadable and release a mod-owned pause after leaving peaceful mode. Crowds need fewer targeting and healing queries. Stand diagnostics stop sampling poses once their detail limit is reached.",
          "legacy": {
            "zh": "修复待命卡住，减少索敌和回血查询。",
            "en": "Fixed stuck orders and reduced targeting and healing queries."
          }
        }
      ],
      [
        {
          "since": 4,
          "zh": "随从血条、通行碰撞或状态读取失败时会延迟重试。切换玩家碰撞通道会先恢复原通道；单只随从读回异常时，其余随从可继续更新。",
          "en": "Missing health bars, denied collision changes and unreadable companion state retry with a delay. Changing the player collision channel restores the original one. One unreadable companion no longer interrupts updates for the others.",
          "legacy": {
            "zh": "血条及碰撞故障会延迟重试。",
            "en": "Backoff for failed health bars and collision changes."
          }
        }
      ],
      [
        {
          "since": 4,
          "zh": "修复属性读取失败时设置页反复刷新的问题。现在可以手动重新读取；在名单读取期间召唤或遣散，窗口会补上最新名单并保留输入。",
          "en": "A failed stat read now offers a retry instead of repeatedly refreshing the form. If companions are summoned or dismissed during a pending read, the window fetches the latest roster and keeps your edits.",
          "legacy": {
            "zh": "修复设置页反复刷新和名单漏更新。",
            "en": "Fixed repeated settings refreshes and stale rosters."
          }
        }
      ]
    ],
    "details": []
  }
};
