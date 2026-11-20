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
  }
};
