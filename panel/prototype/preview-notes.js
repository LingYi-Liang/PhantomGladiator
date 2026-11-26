// Cumulative notes after each stable base. Each paragraph part is available from its first beta build.
window.PG_PREVIEW_NOTES = {
  "0.40.23": {
    "title": {
      "zh": "阵容管理、观战红蓝光与首领战修复",
      "en": "Lineup management, attack flashes and boss fixes"
    },
    "added": [
      [
        {
          "since": 1,
          "zh": "「观战」可分别开启「补显示红光预警」和「补显示蓝光预警」。红蓝对打或随从打地图敌人时，开启后可以看到招式原有的对应闪光，设置自动保存。",
          "en": "Spectate has separate red and blue attack flash switches. Enable them to see the original warning flashes in arena and companion fights. Your choices are saved."
        }
      ],
      [
        {
          "since": 2,
          "zh": "红蓝战场卡片新增「管理阵容」，点「+N」也能打开该队的名单。同名单位按召唤顺序编号，能查看存活状态和生命值。备战或战后可指定移除一只，它带出的配合单位也会一起回收。",
          "en": "Use Manage lineup or the +N button on either team card to see the current roster. Copies of the same unit have individual numbers, with health and status shown for each. Before or after a fight, you can remove one unit and the helpers it summoned."
        }
      ],
      [
        {
          "since": 4,
          "zh": "「观战」新增「旧版处决外观」，默认关闭。打开后部分红蓝处决沿用旧版借模，配合魂的外观替换时偶尔会露出借用模型。悬停可看影响范围。",
          "en": "Spectate now includes Legacy execution appearance, off by default. Some Red vs Blue executions can use the old pose setup, which may show a borrowed model with a Hun outfit replacement. Hover for details."
        }
      ]
    ],
    "combat": [],
    "fixes": [
      [
        {
          "since": 1,
          "zh": "GitHub 接口临时不可用时，助手会用 GitHub 正式发布页确认最新版本。检查失败时会在提示里直接写出本机安装的版本。",
          "en": "When the GitHub API is temporarily unavailable, the assistant checks the official GitHub releases page. If the check still fails, the message shows the version installed on this PC."
        }
      ],
      [
        {
          "since": 3,
          "zh": "修复烈焰上桩后，招式和飞剑仍可能锁着本体的问题。会改找同一组能交战的小狮子。确认最后一只卡在原版 20% 血线时，可接上原版狮头处决。对应 #48。",
          "en": "Attacks and flying swords can switch from Flame on a pole to an available cub in her own wave. When the last cub is confirmed at its native 20% floor, the original lion head execution can proceed. Addresses #48."
        }
      ],
      [
        {
          "since": 3,
          "zh": "七星剑阵整队确认阵亡后，清理胜方仍指向阵亡成员的仇恨和锁定，让胜方能按设置正常脱战回血。",
          "en": "Once the entire Seven-Star Sword Formation is confirmed defeated, the winners clear lingering hostility and locks on the fallen so that normal out-of-combat healing can resume."
        }
      ],
      [
        {
          "since": 4,
          "zh": "怪物互相处决时，默认先确认临时借用模型已隐藏，结束后再核对组件已回收，避免 Boss 显示魂的替换外观。",
          "en": "NPC executions now verify that the temporary pose model is hidden before use and that it is removed afterwards, keeping a replacement Hun outfit from appearing on a boss."
        }
      ],
      [
        {
          "since": 4,
          "zh": "修复召唤单位的强制慢走动作可能把「只能移动」写进玩家输入的问题。清场、胜负结算和观战期间也会检查动作归属，避免切回玩家后技能和互动失灵。",
          "en": "Summoned NPCs can no longer apply the native walk-only input restriction to the local player. The action is still checked during cleanup, at the end of a fight, and while spectating."
        }
      ]
    ],
    "details": []
  },
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
  },
  "0.40.22": {
    "title": {
      "zh": "游戏内摄影与战斗修复",
      "en": "In-game photography and combat fixes"
    },
    "added": [
      [
        {
          "since": 4,
          "zh": "观战页新增「双人自拍」。在开阔处和随从站稳后开启，主角与随从会转向镜头并定格。可换姿势、换随从、拍照，四项操作都能单独绑定键盘或 Xbox 手柄快捷键。姿势取自《影之刃零》原生动作，暂时没有适配动作的随从沿用站姿。构图和实际截图效果待实机验证。",
          "en": "Spectate adds Duo Selfie. Stand with a companion in an open area to face the camera and freeze the scene. Start or exit, change pose, switch companion and take a photo using separate keyboard or Xbox hotkeys. Companions without a matching native pose keep their stance. In-game framing and screenshot output still need verification.",
          "legacy": {
            "zh": "新增主角与随从双人自拍及快捷键。",
            "en": "Duo selfie hotkeys."
          }
        }
      ],
      [
        {
          "since": 5,
          "zh": "双人自拍定格后可在游戏中环绕、推拉和调整镜头高度，换姿势时保留机位。已适配的角色可通过原生转头和眼部方向形变跟随镜头，身体留在原姿势。键鼠和双摇杆均有构图控制，动画画面和手柄效果待实机验证。",
          "en": "After framing a duo selfie, orbit, zoom and adjust camera height in game. Changing poses keeps the camera in place. Supported characters use their native head and eye controls to follow the lens while holding their poses. Keyboard, mouse and both sticks can frame the shot. Animation and controller behavior still need an in-game check.",
          "legacy": {
            "zh": "双人自拍可手动调镜头，匹配的头部和眼部跟随取景。",
            "en": "Adjust the selfie camera and gaze."
          }
        }
      ],
      [
        {
          "since": 6,
          "zh": "新增独立的游戏内摄影面板，支持普通拍照和双人自拍。在游戏里调视场角、倾斜、景深、补光和滤镜，还能分别替主角和随从选择姿势、表情及看镜头。可隐藏血条，截图时自动收起摄影面板。普通拍照与面板显隐各自可绑键盘或 Xbox 手柄。游戏内画面待实机验证。",
          "en": "An independent in-game photography panel supports free photo and duo selfie modes. Adjust field of view, roll, depth of field, a fill light and filters in game. Set each subject's pose, expression and look-at separately on compatible models. Hide health bars and automatically tuck away the menu for capture. Free photo and the menu toggle have bindable keyboard and Xbox shortcuts. In-game rendering still needs verification.",
          "legacy": {
            "zh": "独立游戏内摄影支持双人自拍、镜头、补光、滤镜和人物控制。",
            "en": "In-game photography and duo selfie."
          }
        }
      ],
      [
        {
          "since": 7,
          "zh": "普通拍照的「人物」页可以开启主角看镜头。双人自拍可分别开启主角和随从的看镜头。进入摄影时默认关闭。补上主角后处理网格的查找，并保留角色原有的注视目标。主角实际转头待实机核对。",
          "en": "In free photo, enable the player's Look at camera option under Subjects. Duo selfies have separate switches for the player and companion. They start off. The player lookup can also find an owned post-process mesh and restore a previous gaze target. The player's head turn still needs a live check.",
          "legacy": {
            "zh": "普通拍照和自拍都可选看镜头。",
            "en": "Optional gaze."
          }
        }
      ],
      [
        {
          "since": 8,
          "zh": "摄影新增自动对焦、三组独立补光和场景间接光。可以调饱和度、对比度、色温、泛光、色差、颗粒、暗角与模糊，并保存五组预设。也可调整主体显隐和独立眼神、选相框与署名、开构图参考线或请求 HDR 截图。表情和姿势使用本作已有资源，实际画面待实机核对。",
          "en": "Photography adds autofocus, three private light slots, indirect lighting, color and texture controls, and five preset slots. Adjust subject visibility and eye direction independently, choose a frame and caption, show guides or request HDR capture. Poses and expressions use native game assets. Live rendering still needs verification.",
          "legacy": {
            "zh": "摄影新增三灯、调色、构图和预设。",
            "en": "Photo controls and presets."
          }
        },
        {
          "since": 15,
          "zh": "战场新增「最近一场对局」，列出双方开战时的单位、实读等级、周目、难度、数值来源和可核对的原版计算项，支持复制文稿与导出 JSON。观战新增电影运镜和战场血条三档切换，均可单独绑键。镜头按交锋节奏选肩后、贴地、侧跟、高位拉焦或关键动作稳拍，减少频繁切镜和大幅晃动。后台原生数据表改为每轮读取一张。",
          "en": "The battlefield adds Latest Match with both opening lineups, verified levels, game cycles, difficulties, stat sources and native calculation inputs. Copy a formatted report or export JSON. Spectate adds a cinematic director and three battle HUD modes with separate key bindings. The director uses shoulder, low, side, elevated focus-pull or action shots, with conservative cuts and motion. Native data tables are now read one per heartbeat.",
          "legacy": {
            "zh": "对局报告和电影运镜。",
            "en": "Match report and cinema."
          }
        }
      ]
    ],
    "combat": [
      [
        {
          "since": 8,
          "zh": "大师兄卡片开启「原班配合」后，可以作为七星剑阵随从出战。七位成员组成自己的队伍，遇到大师兄实际锁定的地图敌人后调用原版起手。虚空换琵琶、玉妖铁鬼合击补充了地图随从战的读回，实机等本轮复测。",
          "en": "Enable the eldest disciple's native party to summon his seven-swords formation as companions. His squad uses the native opening tree against a confirmed map enemy. Added field-battle evidence for Void's pipa and Yao's combination with Iron Ghost. Live checks are pending.",
          "legacy": {
            "zh": "随从支持大师兄七星剑阵。",
            "en": "Companion sword formation."
          }
        },
        {
          "since": 9,
          "zh": "修复大师兄延迟起手仍读取红蓝对手的问题。阿瑾也可开启「原班配合」率红衣队战斗，爆脸转化每次召唤最多成功一次。玉面郎君的金面具、铁面具编入原版三人小队。梦华作为随从卡在 41% 血线时，满足原版条件会重试召唤自己的虚空。独立召出的虚空、弦者会把当前敌人交给原版攻击树，荒行子的链刃也会跟随实际对手。上述地图战斗效果待实机验证。",
          "en": "Fixed the eldest disciple's delayed opener still reading the arena target. A-Jin can lead her native red squad as a companion, with one successful opening transformation per summon. Jade-Face uses the original three-member group with Gold and Iron Mask. If Meng Hua stalls at 41% as a companion, she can retry summoning her own Void under the native conditions. Independently summoned Void and the String Player pass their current enemy to their original attack trees. Huangxingzi's chain blade also tracks the confirmed opponent. Field-battle behavior still needs in-game verification.",
          "legacy": {
            "zh": "补齐随从阵式、梦华阶段及技能索敌。",
            "en": "Companion formation and aim."
          }
        },
        {
          "since": 10,
          "zh": "随从挑战地图原版烈焰时会优先索敌同一组小狮子。用原版处决拿到最后一只的狮头后，可上桩和烈焰对射。荒行子随从的链刃确认命中普通地图敌人后，可按原版时机处决，锁血与不可处决的目标仍受保护。大师兄的绝望剑意与红衣女剑客的剑阵版可开启「配合阵容」组成原版小队。骑兵随从的坐骑会接收已确认的敌人。碧海残躯、荡秽和武轩跟随离开召唤点后，会在脱战时核对新落点，再更新各自的技能中心。玉鼎的抓技保护也覆盖已锁血的对应地图首领。地图实战待验证。",
          "en": "Companions fighting Flame in the story encounter prioritize the cubs from that encounter. Finishing the last cub with the native execution and taking its head lets them climb a pole and trade fire with Flame. Huangxingzi can execute eligible map enemies on a confirmed chain-blade hit, respecting health locks and execution immunity. Sword of Despair and the formation swordswoman can summon as their original squad. Cavalry companions pass confirmed targets to their mounts. Bihai, Danghui and Wuxuan can reposition their private ability anchors after following the player and leaving combat. Yu Ding's grabs respect the corresponding map bosses' phase locks. Field combat still needs an in-game check.",
          "legacy": {
            "zh": "随从烈焰挑战、铡刀与剑偶编队。",
            "en": "Pole duel and finishers."
          }
        },
        {
          "since": 11,
          "zh": "红队或蓝队超过三条存活血条时，只缩小该侧并收紧行距。打开游戏内设置菜单会暂时隐藏斗蛐蛐的两侧血条，返回战斗后自动恢复。",
          "en": "When either side has more than three living health bars, that column shrinks and tightens its rows. Arena bars hide while the in-game settings menu is open and return when it closes.",
          "legacy": {
            "zh": "血条自动缩小，游戏设置时隐藏。",
            "en": "Adaptive battle HUD."
          }
        }
      ],
      [
        {
          "since": 1,
          "zh": "从图鉴召唤的虚空改拿琵琶。原版靠登场动作换武器，直接召唤没有这段动作，之前一直拿着扇子。梦华自己召出的虚空保持原样。",
          "en": "Void summoned from the bestiary now holds her pipa. The game switches weapons during her entrance, which a direct summon skips, so she kept the fan. The Void summoned by Meng Hua is unchanged.",
          "legacy": {
            "zh": "从图鉴召唤的虚空改拿琵琶。",
            "en": "Void holds her pipa."
          }
        },
        {
          "since": 2,
          "zh": "补上持握读回。虚空换到琵琶后，如果还没拿到手上，会等安全时机再试；演出期间暂停重试。",
          "en": "The assistant now checks that Void is holding the pipa. If the slot changed but it is still sheathed, it retries after the current paired action.",
          "legacy": {
            "zh": "核对虚空确实持握琵琶。",
            "en": "Verify the pipa grip."
          }
        },
        {
          "since": 3,
          "zh": "虚空普通出招或仍在播动作时会等动作结束，再换武器或补持握。",
          "en": "Void finishes her current ability and animation before the assistant equips the pipa or retries drawing it.",
          "legacy": {
            "zh": "虚空收招后再换琵琶。",
            "en": "Void switches after recovery."
          }
        }
      ]
    ],
    "fixes": [
      [
        {
          "since": 1,
          "zh": "修复魂自己的走位和原版连招打断出招的问题。魂出主武器连段、影之武装和格挡时，原版 AI 每换一步走位都会取消当前动作，还会插进一招绝影双刀。绕圈时间调得越短越明显，表现为原地反复起手、连招中断。现在出招收尾前不受这两种情况影响，收招后没有下一招才让它走开。受击、被处决和死亡照常打断。游戏内效果待实测。",
          "en": "Hun's own footwork and native combo no longer cut his attacks. The game's AI cancelled the current action before every step, including weapon chains, shadow armaments and guards started by the mod, and slipped in a swing of his own twin blades. Short circling times made him restart the first swing on the spot. A step or a native swing now waits until the recovery has nothing to chain. Hits, executions and death still interrupt. Awaiting in-game confirmation.",
          "legacy": {
            "zh": "修复走位和原版连招打断魂的出招。",
            "en": "Fix interrupted attacks."
          }
        },
        {
          "since": 2,
          "zh": "格挡和影武每次重新起手都重新计时。收招会恢复技能原来的可取消状态和冷却，暂时恢复失败会再尝试。出招期间的临时冷却两秒到期，重载后会按原实例补恢复。",
          "en": "Each new guard or shadow armament starts its own timer. Recovery restores the original cancel flag and cooldown, retrying temporarily rejected writes. The temporary cooldown expires in two game seconds. After a mod reload, the assistant checks the original instance before continuing cleanup.",
          "legacy": {
            "zh": "修复格挡计时和重载后残留的魂技能冷却。",
            "en": "Fix guard recovery."
          }
        },
        {
          "since": 3,
          "zh": "续写临时冷却时如果读回中断，收招后仍能恢复原值。重载后找不到的技能最多查三次，避免连续查找卡住支持循环。",
          "en": "Hun restores the original cooldown even when a refresh succeeds but the immediate readback fails. After a mod reload, a missing ability lookup is limited to three attempts.",
          "legacy": {
            "zh": "补上冷却恢复，限制重载后的失败查询。",
            "en": "Cooldown recovery."
          }
        },
        {
          "since": 12,
          "zh": "切换分辨率时，旧血条会保留布局，新血条等尺寸可读再显示。意外脱离视口的血条会自动重建。截图发送前会复核摄影面板已隐藏，退出摄影时恢复血条最近的原生透明度。荒行子的铡刀从实际命中开始计时，助手时停期间保留铡刀和烈焰上桩状态。图鉴读取暂时缺失的地图或章节时会复核，减少重复查找。",
          "en": "Health bars retain their layout through temporary resolution changes and rebuild if detached from the viewport. The photo panel must be hidden before capture, and leaving photo mode restores the last native opacity of each masked bar. The guillotine timer starts on impact, and the assistant's time stop preserves active guillotine and pole challenges. The codex retries missing map and chapter details with fewer duplicate lookups.",
          "legacy": {
            "zh": "修复血条、截图、时停结算和图鉴缓存。",
            "en": "HUD, photo and combat fixes."
          }
        },
        {
          "since": 13,
          "zh": "修复梦华保留剧情联动时卡在 41% 的两条路径。召唤起手已中断并消耗许可时，可补发漏掉的原版召唤事件。虚空在配对前出生失败并腾出原生召唤槽时，也能限次重试。助手会等梦华收招，沿用原版后续联动和解锁。补召会优先用已确认的对手定位。",
          "en": "Fixed two ways Menghua could stay at 41% with her story link enabled. If the opening sequence ends before sending the summon event, the assistant can resend that native event. If Void fails to spawn before pairing and the native slot is free, a limited retry is also possible. The assistant waits for the current action to clear, uses the confirmed opponent for retry placement when available, and keeps the original pairing and unlock.",
          "legacy": {
            "zh": "修复梦华卡在 41% 血线。",
            "en": "Restore Menghua's 41% link."
          }
        },
        {
          "since": 14,
          "zh": "梦华跳过联动时清理残留的原版召唤许可，保留联动时在确认脱战收尾完成后重置补召次数。序章左殇首段演出中断后若仍残留原版 80% 血线，会补原版解锁。小雪的原班召唤、大师兄起手及白衣弟子阵亡通知在明确失败时可有限重试。助手时停、原版处决的临时锁血和华山队友保护期间，暂停可能抢走阶段的自动处决与锁血收尾。",
          "en": "Skipping Menghua's link clears leftover summon permission. A completed combat reset renews the retry budget when her link is kept. Prologue Zuo Shang can complete his native 80% unlock after an interrupted opener. Xiaoxue's native summons, the eldest disciple's opener and white disciple death notifications can retry after confirmed failures. Automatic executions and lethal cleanup now respect the assistant's time stop, native execution protection and the HuaShan squad health floor.",
          "legacy": {
            "zh": "补解锁、队员召唤和处决保护。",
            "en": "Fix phase unlocks and squad summons."
          }
        }
      ],
      [
        {
          "since": 1,
          "zh": "修复换图或传送后的持续卡顿。地图卸载后，已经不存在的蓝图挂钩会被反复摘除，某些单位上过场后每 0.5 秒卡约 27 毫秒，到下次召唤才停。现在只认一次，单位再次上场时重新挂上。",
          "en": "Fixed a lasting stutter after a map change or teleport. Hooks on blueprints that had left with the map were removed again and again, costing about 27 ms every half second until the next summon. They are now handled once and hooked again when the unit returns.",
          "legacy": {
            "zh": "修复换图或传送后的持续卡顿。",
            "en": "Fix post-travel stutter."
          }
        },
        {
          "since": 2,
          "zh": "换图后，暂时摘不掉的旧挂钩会立即停止执行。蓝图再次载入时再回收，避免旧回调跟着新回调一起跑。",
          "en": "Callbacks left over after a map change stop running immediately. The assistant removes their handles when the blueprint is loaded again.",
          "legacy": {
            "zh": "换图后立即停用待回收的旧回调。",
            "en": "Disable stale callbacks on travel."
          }
        }
      ],
      [
        {
          "since": 1,
          "zh": "传送等地图重新载入后才报「已到达」，15 秒防坠观察从这时开始。之前目标在 50 米内时，载入前就报到达。页面补充说明传送会重载整张地图，召唤单位、随从和排队中的召唤都会取消。",
          "en": "Teleport reports arrival only after the map has loaded again, and the 15-second fall watch starts there. Targets within 50 m used to report arrival before loading. The page now says that a teleport reloads the map and clears summoned units, companions and the queue.",
          "legacy": {
            "zh": "传送在地图重新载入后才报到达。",
            "en": "Teleport arrival waits for the map to load."
          }
        },
        {
          "since": 2,
          "zh": "补上同图传送的误报。角色自己走近目标、换控制器或换角色时，助手会继续等待地图重载。防坠只跟随已确认到达的角色，离开落点附近或换人就结束。",
          "en": "Walking near the target or changing controllers or pawns no longer confirms a same-map teleport. The fall watch stays with the pawn whose arrival was confirmed and ends when it moves away or is replaced.",
          "legacy": {
            "zh": "修复同图步行、换人触发的传送误报。",
            "en": "Fix false same-map arrivals."
          }
        },
        {
          "since": 3,
          "zh": "没确认进入目标地图的传送会保留原来的返回点。加载中暂时读不到世界时继续等，防坠只把确认拉回的次数记为成功。",
          "en": "A teleport keeps the last return point until the requested map is confirmed. The assistant waits through temporary world read errors and counts only fall recoveries it could verify.",
          "legacy": {
            "zh": "失败的传送保留返回点，防坠按成功读回计数。",
            "en": "Verify returns and fall recovery."
          }
        }
      ],
      [
        {
          "since": 1,
          "zh": "AI 行为参数里，绕圈时间的说明补充：每绕完一次会重新选左右，低于 1 秒会频繁换向。",
          "en": "The circling time hints now explain that each circle picks a new side, so values below 1 second turn back and forth.",
          "legacy": {
            "zh": "补充绕圈时间的说明。",
            "en": "Clarified the circling time hints."
          }
        }
      ]
    ],
    "details": [
      {
        "since": 1,
        "issue": 40,
        "zh": "虚空改拿琵琶，本轮已处理，待游戏内确认。",
        "en": "Void holds her pipa in this build, awaiting in-game confirmation."
      }
    ]
  }
};
