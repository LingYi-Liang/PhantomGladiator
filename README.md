<div align="center">

# 斗蛐蛐 · 影之刃零怪物对战助手

**Phantom Gladiator — NPC battles for *Phantom Blade Zero***

让《影之刃零》里的怪物和 BOSS 互相开打：选怪、分阵营、一键开战，打到破防就用原版处决收尾；再用自由视角从任意角度观战，随时时停截图。

[下载最新版](https://github.com/LingYi-Liang/PhantomGladiator/releases/latest) · [使用说明](#三步开始) · [常见问题](#常见问题) · [English](#english)

作者：**泠依_01** · B站 UID **10010098** · [B站主页](https://space.bilibili.com/10010098)

</div>

![对战页：左边选怪，右边召唤、数值设定和战场](docs/images/arena.png)

---

## 这是什么

《影之刃零》里的敌人默认只会打玩家。这个项目由两部分组成：

- **游戏内模组**（UE4SS Lua）：在你面前召唤游戏里原有的怪物，把它们分成蓝方、红方，改写它们的仇恨和阵营关系，让它们按游戏原生的招式、受击和死亡逻辑真打起来。
- **桌面助手**（本仓库发布的 `PhantomGladiator.exe`）：给模组配了一个小白也能用的界面。第一次打开会自动找到游戏、一键装好所需组件，之后点点鼠标就能选怪、召唤、开战、观战。

模组只在游戏运行时改内存里的对象，**不修改游戏文件、资源或存档**。关掉游戏，召唤的单位和改动都会消失。

## 下载

到 **[Releases](https://github.com/LingYi-Liang/PhantomGladiator/releases/latest)** 下载 `PhantomGladiator-<版本>-win64.zip`（约 20 MB），旁边的 `.sha256` 文件可用来校验下载是否完整。

- 国内网络打不开 GitHub 时，可以借助常见的 GitHub 下载加速站下载同一个文件，下载后对照 `.sha256` 校验即可。
- 装好以后，助手里的「检查更新」会自动挑选国内可用的线路，下载后自动校验 SHA-256，不需要再手动找下载地址。

## 三步开始

1. **解压**：把整个压缩包解压到任意文件夹（不要在压缩包里直接双击）。
2. **打开助手**：双击 `PhantomGladiator.exe`。新手引导会：
   - 自动在 Steam 库里找到《影之刃零》（找不到可以手动选择文件夹）；
   - 检查并一键安装需要的组件：模组加载器 UE4SS、游戏适配文件、斗蛐蛐模组。
3. **开打**：启动游戏、读取存档进入地图，等助手右上角变成绿色「已连接 · 可以召唤」。在左边选一个怪，召唤到蓝方；再选一个召唤到红方；点「开战」。

> 第一次运行时 Windows 可能弹出「Windows 已保护你的电脑」：点「更多信息」→「仍要运行」。助手没有购买代码签名证书，这是未签名程序的正常提示。

![新手引导](docs/images/welcome.png)

## 功能一览

### 选怪与召唤
- **图鉴选怪**：内置游戏原生图鉴里的 177 个角色（其中 75 个 BOSS 及其形态），按章节和地图分组，支持搜索、按小怪/BOSS 筛选。
- **怪物头像**：卡片、当前选择、数值基准和快捷键列表显示游戏图鉴里的怪物头像。头像由模组从你自己电脑上的游戏里导出，安装包里没有：装好模组后第一次进地图，后台约 1 分钟存完 177 张，助手里自动出现，不用重启。只需要一次，以后打开助手直接显示，不开游戏也行；游戏更新加了新怪，下次进地图会自动补上。还没存好或读不出来的，卡片照旧显示名字首字。
- **分阵营召唤**：蓝方、红方，每次 1–100 只（常用 1、5、10、50 一键选），场上总数不设上限。一次召唤几十只时游戏会卡一两秒。
- **快捷操作**：鼠标移到卡片上直接「+蓝方 / +红方」；键盘选中卡片后按 `B` / `R` / `N` 分别召唤到蓝方、红方、暂不配队，`Ctrl+Enter` 召唤当前选择。
- **单位召唤键**：给常用的怪绑一个键，在游戏里按下就召唤它。每个键记住自己的阵营和数量：在对战页选中这个怪，切换上面的阵营或数量，它的键就跟着改，不同的怪可以各站一边。
- **骑兵和随行单位**：荆野、马匪、无面枪骑兵、鬼差骑兵等骑兵召唤出来骑着自己的马；驯犬客会带上两只狗，和游戏里的摆法一样。

### 对战
- **一键开战**：蓝红双方各至少 1 只即可开战，交战中继续召唤的单位会自动加入战斗。
- **战场计数**：实时显示双方存活数、倒下待清理数，以及暂时读不到状态的单位。
- **胜负与再来一局**：一方全灭后显示胜者和用时；「再来一局」会按上一局的阵容重新召唤并开战。
- **用时**：交战时在「交战中」旁边计时，用的是游戏内时间，暂停不计。在「观战」里打开「画面顶部显示计时」，游戏画面正上方也会显示。
- **不倒下**：蓝方、红方方框底部和随从卡片里各有一个开关。开着时这一方照常挨打、掉杀气、被破防，但血量锁住，不会倒下。适合测"一群杂兵打 BOSS 要多久"：杂兵开不倒下，看 BOSS 多久倒下。
- **不死不休**：交战中，蓝红两队不会打一阵就脱战回出生点；一旦脱战，下一帧就被拉回去打原来的目标。
- **怪对怪处决**：交战中一方被打破防、血量低到处决线，或 BOSS 被打到锁血线时，离它最近的敌人会用游戏原版的处决把它解决。覆盖游戏里 60 份怪物配置的专属处决，以及骑乘处决和原生反制；附近还有下一个目标时才会接连携处决。执行方借用的是玩家的处决动作，体型不同会有穿模。
- **停止并清理**：移除所有由助手召唤的单位并恢复战斗中改动过的关系，游戏原有的怪物不受影响。

### 暂不配队：自己练 BOSS
选「暂不配队」召唤的单位不加入蓝红任何一方，像游戏里的普通敌人一样会来打你，适合反复练同一个 BOSS。它们有独立的存活计数和「仅清理暂不配队」按钮，不影响正在进行的蓝红对战；全部倒下后点「再刷一次」就能立刻再来一只。

![暂不配队](docs/images/solo.png)

### 数值设定
对战页右侧的「数值设定」有三种模式，只影响之后召唤的单位：
- **按游戏**：用游戏本来的数值，随召唤等级和难度变化。
- **统一成第一只**：第一只召唤的单位成为「基准」，之后召唤的单位把生命和杀气上限、攻击、削杀气、攻防倍率统一成基准的数值（共 107 项战斗属性，满生命满杀气入场），游戏算伤害用的 1 级基准值也一起统一。招式、体型、速度和 AI 不变，适合看「同样的数值下谁更会打」。
- **自定义**：自己填数值。卡片上直接有血量上限、杀气上限、攻击、削杀气四项；「全部属性」里是游戏的全部 223 项属性，按类别分组、可以搜索，包括当前血量和下限、护盾、杀气回复、各类伤害与抗性倍率、杀器抗性、异常状态积累、绝技与觉醒、处决血量阈值、移动速度、等级等。空着的项保留单位自己的数值；填了的项会覆盖召唤等级和难度带来的变化，改了血量或杀气上限的单位满血满杀气入场。每项写入后都会读回，游戏不接受的项（例如超过上限的当前值）恢复原值并在卡片上列出，其余照常生效。随从不受影响。

**为什么要连 1 级基准值一起改**：游戏算伤害不看你看到的血量上限和攻击，而是看每只怪的「1 级基准值」：

**每一下扣掉对方血量上限的比例 = 攻击方的 1 级攻击 × 招式倍率 ÷ 受击方的 1 级血量**

所以只改血量上限，只会让血条和数字变大，挨几下倒下不变；只改攻击，伤害也不变。自定义改血量上限、杀气上限、攻击、削杀气时，助手会把对应的 1 级值按同样比例一起改（在「全部属性」里自己填了 1 级值的，以你填的为准）。v0.37.0 的自定义和更早版本的「数值统一」都漏了这一步：数值显示对了，实际挨打和出手的伤害没变；v0.37.1 起修正。

![数值统一](docs/images/stat-match.png)

### 召唤难度
不用改游戏难度，也能召唤不同难度的怪。在对战页右侧的「召唤难度」里选择：跟随游戏、入阵者、破局者、逆天者或六十六天。之后召唤的单位就按这一档生成：
- 血量、攻击、杀气等数值；
- AI 的难度判断，例如技能池里逆天者才开放的招式。

你自己、地图上原有的怪，以及存档里的游戏难度都不会变。六十六天和逆天者的怪物数值完全一样；区别主要在玩家这边：死亡次数上限，以及完美格挡的判定窗口更短（逆天者 8 帧，六十六天 6 帧）。另外有 28 只怪在六十六天换一套 AI，打法可能不一样。少数以整个世界为对象的难度查询，以及游戏底层直接读取难度的部分（例如 BOSS 召唤小怪的血量门槛），仍按游戏本身的难度。

难度只决定数值要乘的系数，数值本身有多高还看等级，见下面的「召唤等级」。

### 召唤等级
等级越高，血量、杀气和攻击越高。在对战页「召唤难度」下面的「召唤等级」里选等级从哪来：
- **老家等级（默认）**：用这只怪在游戏里本来的等级，在哪召唤都一样。模组带着从游戏文件里读出来的全游戏刷怪点等级（2055 个刷怪点、242 种怪），BOSS 就是剧情那一战的等级（例如三张脸是 15 级，88,830 血）。默认取它图鉴所属地图上刷得最多的那处；选中单位后，可以在「老家等级」里换成它出现过的别的地方。
- **当前地点等级**：和你身边地图上原有的怪一样。取 200 米内地图怪的最高等级，没有就取已加载的地图怪里最高的；一只都没加载时，按你所在位置的游戏刷怪点。只往上调，不会调低。
- **自定义等级**：所有召唤都用你填的等级（1～60）。

游戏还会在刷怪点的等级上加两样，老家等级和当前地点等级照加：难度「辅助」下 −1 级，每多一个周目 +25 级。每个 BOSS 的原生等级和各地方的等级见[怪物数值说明](docs/STATS_GUIDE.md#boss-战的等级)。

v0.36 之前，召唤出来的单位一律是 0 级，拿的是游戏里最低一档的数值，所以召出来的 BOSS 几刀就死。

### 怪物数值怎么算
完整的说明（等级是什么、哪些数值随等级变、怪打怪和你打怪的伤害怎么算、为什么大家测出来不一样）见 [怪物数值说明](docs/STATS_GUIDE.md)。下面是简要版。

下面的算法是用模组直接读游戏内部数据得到的，在魔渊、阿花和地图小怪身上逐项核对过，16 项数值算出来和游戏里完全一致：

**最终数值 = 基础值 ×（1＋等级曲线）× 全局难度系数 × 怪物类型系数**

1. **基础值**：写在每个角色自己的配置里。例：魔渊 血 12000、杀气 3000、攻击 120、削杀气 120；阿花 9000 / 2000 / 100 / 100；白鹤门弟子（刀）800 / 800 / 100 / 100。游戏属性表里魔渊的血写的是 10000，但实际生效的是配置里的 12000。
2. **等级倍数**：所有怪共用同一组曲线，0 级和 1 级都是 1 倍。

   | 等级 | 血量 | 杀气上限 | 攻击 | 削杀气 |
   |---|---|---|---|---|
   | 1 | 1 | 1 | 1 | 1 |
   | 5 | 3.032 | 1.95 | 1.111 | 1.073 |
   | 10 | 6.07 | 3.415 | 1.296 | 1.221 |
   | 15 | 9.87 | 4.634 | 1.652 | 1.512 |
   | 18 | 11.628 | 7.9345 | 2.109 | 1.61 |
   | 19 | 12.209 | 8.9695 | 2.212 | 1.663 |
   | 20 | 12.8 | 9.7515 | 2.309 | 1.73 |
   | 25 | 18.51 | 12.7875 | 2.917 | 1.876 |
   | 30 | 19.55 | 13.29 | 3.02 | 1.897 |
   | 40 | 23.07 | 14.72 | 3.14 | 1.996 |

   血量和杀气涨得最快，攻击到 40 级也才 3 倍多。
3. **全局难度系数**：召唤的单位按「召唤难度」，选「跟随游戏」时按游戏难度。入阵者 杀气 ×0.5、攻击 ×0.7、削杀气 ×0.33；破局者 只有削杀气 ×0.66；逆天者、六十六天没有。
4. **怪物类型系数**：杂兵和普通怪 杀气 ×0.4，在入阵者、破局者下血量再 ×0.8；精英 杀气 ×0.6；BOSS 杀气 ×0.8。

等级还改「异常积累上限」，难度和类型还管几项抗性、处决血线和破防后的失衡时间；打起来每一招还要乘招式类型权重。全部因素的清单见[怪物数值说明](docs/STATS_GUIDE.md#7-影响怪物数值的全部因素)。

例：19 级（梅谷湖一带）、六十六天的魔渊，血量 = 12000 × 12.209 = 146508。BOSS 的血量没有难度系数，选哪一档都是这个数。

### 随从：让 BOSS 跟着你打
召唤时阵营选「随从」，召出来的怪就成了你的随从，数量不限，召唤难度照样生效：
- **跟着你走**：用的是游戏自带的助战 NPC 跟随行为。离你 10 米内走路，超过 10 米加速追上；超过 100 米，或者你在地图上快速移动后，会直接传送到你身边。离你 8 米以上、6 秒都没能靠近（比如卡在台阶、楼梯、平台下面）时，也会传送过来。正在和 BOSS 打的时候不会自动传送。
- **召回到身边**：随从卡片上的按钮，或者绑一个快捷键，所有随从立刻回到你身边，BOSS 战里也能用。
- **帮你打**：和你同一阵营，互相不伤害。会主动去打附近的敌人，投技对地图上原有的怪也能用。随从自己召唤出来的单位也站在你这边。随从对你始终友好：开着自由观战或无仇恨时召唤也一样；Mod 每秒核对一次随从（以及骑兵随从的坐骑）对你的关系，被改动会立刻改回。
- **随时解散**：「停止并清理」不会带走随从，右侧随从区有单独的「解散随从」按钮。单位召唤键也可以直接召随从。

目前的限制：随从加速追你时速度是对的，但很多怪仍然是走路的动作；换地图或读档后随从会消失，需要重新召唤；个别单位在复杂地形上可能找不到路，卡住时会自动传送回来，也可以手动召回。

### 观战
- **自由观战**：无仇恨 + 隐身 + 无敌（锁血），声音跟随镜头。用 WASD 移动、空格或 E 上升、Ctrl 或 Q 下降、Shift 加速、鼠标转向，退出后恢复进入前的状态。镜头每帧更新，起步、停下和转向都有缓动；「自由视角设置」里可以调移动速度、转向速度和平滑程度（平滑调到 0 就是直接跟手）。可以在助手里点「进入」，也可以绑定快捷键。
- **时停**：游戏完全暂停，镜头照常移动，方便截图。用的是游戏自带拍照模式同一套暂停。打开「观战」里的「时停」开关或按快捷键；不在自由观战时会先进入，退出自由观战会自动恢复。
- **处决镜头**：打开后，怪物处决对手时画面切到这段处决原版的镜头，和你亲手处决时看到的一样，播完回到原来的视角。
- **无仇恨**：只让怪物不主动打你，不隐身也不锁血，适合在普通视角下观战。

「观战」卡片里的自由观战、时停、无仇恨三行下面都有「设置快捷键」，点一下直接按键就行。

### 趣味功能
左栏「趣味功能」页有三个开关，可以随意组合。它们只作用在你自己的角色上，召唤出来的单位不受影响：
- **无限杀气**：杀气槽一直保持满格，杀招随便放。关掉后恢复正常。
- **自动精准防御**：敌人的攻击快打到你时，自动替你按格挡，你在出招时也会按。轻攻击基本都能完美格挡，较重的攻击多数是普通格挡。
- **自动闪避红光**：红光等不能格挡的攻击，自动替你闪避；方向还是由你推的方向决定。

自动防御和闪避还在实验阶段：游戏留的反应时间很短，个别招式可能接不住。自由观战时这两项会暂停。

### 快捷键
10 个功能键（召唤、开战、停止并清理、切换召唤阵营、进入 / 退出自由观战、退出自由观战、开关无仇恨、扫描目录、召回随从、时停）**默认全部不绑定**，需要时在「快捷键」页自己设置，可组合 Ctrl / Alt / Shift。同一个键只能分给一个功能或单位，冲突和系统保留键会直接提示。

![快捷键](docs/images/hotkeys.png)

### 其他
- **六种语言**：简体中文、English、日本語、Français、Deutsch、Español，按电脑时区自动选择，也可以手动切换。单位、章节和地图名称跟随游戏语言：带着模组进一次地图后，助手显示你游戏里的名称（游戏是英文就显示英文名）；在此之前显示中文。游戏里 BOSS 血条上的单位名和队伍名也跟随游戏语言。
- **浅色 / 深色主题**。
- **操作记录**：每条操作都等游戏回执后才显示成功；没有回执就不算成功，也不会自动重发。指令卡住时助手会说明原因，「操作记录」里可以一键「清理排队的指令」。
- **诊断报告**：设置 → 高级里一键把日志打包到桌面，方便反馈问题。
- **更新记录**：「检查更新」窗口里可以展开查看每个版本更新了什么，不联网也能看。
- **回退版本**：更新记录里，v0.37.6 起的旧版本后面有「回退到此版本」按钮。新版本有问题时可以换回去，设置和按键都保留，之后也能再升级。

![深色主题](docs/images/arena-dark.png)

## 系统要求与兼容性

| 项目 | 要求 |
| --- | --- |
| 系统 | Windows 10 / 11，64 位 |
| 运行库 | Microsoft Edge WebView2（Windows 10/11 一般自带；缺少时助手会给出微软官方下载链接）、.NET Framework 4.8（系统自带） |
| 游戏 | Steam 版《影之刃零》，已测试 build **26367565**；其他版本未经测试 |
| 模组加载器 | UE4SS 3.0.1（随包附带；游戏里已经装了 UE4SS 时不会覆盖） |

## 已验证的范围

为了不误导，这里如实写明哪些经过了实机验证：

- 已实测：普通持刀暴徒互斗；新娘阿花与暗魔天堡之主魔渊对战；数值统一（两轮 109 项数值读回全部一致；但当时没统一 1 级基准值，实际伤害并不相同，v0.37.1 起修正）；BOSS 常驻血条和生命数字；自由观战的隐身、锁血、声音跟随与退出恢复；暂不配队单位的召唤与存活计数；全部 8 个功能键的保存与生效回执；单位召唤键按各自的阵营召唤。
- 召唤难度已实测：游戏本身保持入阵者，阿花和魔渊按逆天者、六十六天召唤，数值读回与游戏配置表一致（攻击约 1.43 倍、杀气攻击约 3 倍、杀气上限 2 倍；这两个 BOSS 的血量在各难度相同）。AI 的两类难度检查（行为树分支、技能池条件）都按所选难度回答，地图上的其他怪和整个世界仍是游戏难度。
- 随从已实测（魔渊、阿花）：跟随、远距离和快速移动后的传送、和地图怪战斗、投技抓地图怪、与玩家互不伤害、召唤后立刻进入战斗；同时召两只、开着召唤难度时不卡顿。
- 召唤等级已实测（梅谷湖一带，附近地图怪 18～19 级）：召唤的阿花从 0 级提到 18 级，血量从 9000 变成 104652。上面的数值算法在魔渊、阿花、白鹤门弟子身上逐项核对，16 项全部一致。v0.37.6 实测三张脸：老家等级在正道大营和悲泣溪谷召唤都是 15 级、88,830 血；当前地点等级在悲泣溪谷、附近没有地图怪时按 178 米外的刷怪点取 4 级，23,225 血；自定义 60 级 271,080 血。
- 趣味功能已实测：无限杀气一直锁满；自动格挡的每次按键游戏都收到了，轻攻击 9 次全是完美格挡；红光会自动按闪避。没有预告、或者预告来得太晚的攻击接不住。
- v0.37 已实测：自定义数值的 223 项属性逐项写入、隔 0.5 秒读回并恢复，全部成功；伤害按 1 级基准值计算：v0.37.0 里血量上限填 9999999 的单位每一下仍掉上限的 13.6%（和原数值时的比例相同），攻击填 99999 伤害也不变；v0.37.1 连 1 级值一起改后，血量上限 9999999 的双镐疯妇被 10 只同级怪围攻 50 秒只掉约 0.5%，攻击 99999 一下打倒一只；50 只小怪打魔渊，蓝方开不倒下后一只未倒；交战计时与日志里的游戏时间一致，画面顶部计时读回已显示；一次召唤 50 只约卡 1.4 秒；不死不休开启后小怪脱战会在下一帧被拉回，魔渊持续掉血，但仍有少数小怪会短暂走开；自由观战空格、Ctrl 升降。
- v0.37.3 已实测：图鉴头像 177 张全部导出，失败 0，用时约 57 秒；助手里 177 个单位全部显示头像，读不出来的图会退回名字首字。随从召唤物站到玩家一方（会召唤的怪当随从时，它召出的单位改成玩家阵营、不再仇恨玩家）只做了离线测试，还没实机验证。
- v0.37.4 的随从修复没有实机验证：原因（开着自由观战或无仇恨时召唤的随从，关闭后对玩家变回敌对）是从代码里找到的，作者这边复现不了反馈里的情况。随从每秒的自检会在日志里记下被改成了什么；如果还遇到随从打到自己，请附上诊断报告。
- v0.38 已实测：
  - 怪对怪处决在测试版里逐轮实机验收（0.37.31 通过）。发布前最后一场，毕远掌门残躯处决魔渊：处决播完，目标倒下，执行方的 AI 和身体都恢复了。
  - 时停：游戏暂停读回成功；镜头离开时停点 2～4 米时画面都跟着走；暂停期间双方血量不变；用快捷键来回切换约 9 次都成功。
  - 自由观战已在游戏里改为每帧更新。
- v0.38 只做了离线测试、还没实机验证：骑兵召唤带马、驯犬客带狗、随从卡住自动传送和召回、清理排队的指令，以及处决里新加的骑乘处决和原生反制。遇到问题请附上诊断报告。
- 可以尝试、但不保证：图鉴里的其他单位都能召唤，但不一定都能正常对打。个别单位有天生机制（例如机灵鬼天生无敌/穿透），不会因为召唤而改变。
- 已知情况：清理时如果还有单位活着，游戏端第一遍会留下一条恢复记录。助手会在同一次点击里自动补做第二遍；在游戏里直接按「停止并清理」快捷键时，目前需要按两次。

## 常见问题

<details>
<summary><b>右上角一直是「游戏未启动」或「未进入地图」</b></summary>

需要先启动游戏并读取存档进入地图。如果游戏已经在运行，但组件是刚装好的，请重启一次游戏让模组加载。设置 → 游戏里可以看到各组件是否「已就绪」。
</details>

<details>
<summary><b>助手找不到游戏</b></summary>

在新手引导或设置 → 游戏里点「选择文件夹」，选《影之刃零》的安装目录（里面有 <code>platform\steam\PBZ.exe</code>）。
</details>

<details>
<summary><b>提示「另一个斗蛐蛐助手或开发面板正在使用这份游戏数据」</b></summary>

同一时间只能有一个助手连接游戏。请关掉其他已打开的斗蛐蛐助手（或开发用的网页面板），再点「重试」。
</details>

<details>
<summary><b>同一只怪，在不同地方召唤，血量不一样？</b></summary>

用默认的「老家等级」时，同一只怪在哪召唤都一样；选了「当前地点等级」，就按你附近地图怪的等级生成，地方不同等级就不同。等级越高数值越高，算法见[召唤等级](#召唤等级)和[怪物数值怎么算](#怪物数值怎么算)。想让两边数值完全一样，可以在「数值设定」里选「统一成第一只」；想指定具体数值，选「自定义」。
</details>

<details>
<summary><b>血少、等级低的 BOSS 打赢了血多的后期大 BOSS，是不是改了伤害？</b></summary>

没有改，游戏本来就这样算。怪打怪时，每一下扣的是对方血量上限的固定比例：攻击方的 1 级攻击 × 招式倍率 ÷ 受击方的 1 级血量。等级只让血条上的数字变大，不让怪更耐打，所以就算两只 BOSS 都按玩家剧情里打到的那个等级召唤，前期 BOSS 一样可能赢后期 BOSS。

实测例子：7 级的毕远掌门残躯（41,800 血）打 26 级的魔渊（223,200 血）。毕远普通一下就扣魔渊 1.08% 的血；魔渊杀气防御低，容易被打破防，破防后 4 秒掉了 36%；最后剩 13.9% 时被毕远处决。整场毕远自己还剩 28% 血。

想比得公平，在「数值设定」里选「统一成第一只」：血量、杀气、攻击、削杀气、各种攻防倍率和抗性（107 项）连同 1 级基准值都统一成第一只的。统一之后比的只剩招式、出手快慢和 AI，也就是「同样的数值下谁更会打」。原理见[怪物数值说明](docs/STATS_GUIDE.md)。
</details>

<details>
<summary><b>召唤失败 / 召唤的怪不动</b></summary>

部分单位在当前地图无法生成，或天生不参与战斗。可以先试「暴徒」这类已实测的单位；失败原因会显示在通知和「操作记录」里。
</details>

<details>
<summary><b>会影响存档或游戏文件吗？</b></summary>

模组只在游戏运行时改内存中的对象，不写游戏资源和存档。安装时只会在游戏目录的 <code>platform\steam</code> 下放入 UE4SS（<code>dwmapi.dll</code> 和 <code>ue4ss</code> 文件夹）以及本模组。使用任何第三方模组都有一定风险，请自行判断。
</details>

<details>
<summary><b>怎么卸载？</b></summary>

- 助手：直接删除解压出来的文件夹；助手的设置和缓存在 <code>%LOCALAPPDATA%\PhantomGladiator</code>，也可以一起删。
- 游戏里的组件：删除游戏目录 <code>platform\steam\ue4ss\Mods\PhantomGladiator</code> 即可停用本模组；如果不再需要 UE4SS，再删除 <code>platform\steam\dwmapi.dll</code> 和 <code>platform\steam\ue4ss</code>。
</details>

<details>
<summary><b>遇到问题怎么反馈？</b></summary>

到 <a href="https://github.com/LingYi-Liang/PhantomGladiator/issues">Issues</a> 描述你做了什么、看到了什么，并附上设置 → 高级 →「导出诊断报告」生成在桌面上的压缩包。
</details>

<details>
<summary><b>随从的攻击打到了我</b></summary>

v0.37.4 修复了一个原因：开着自由观战或无仇恨时召唤的随从，关闭后会对你变回敌对，范围攻击就会打到你。更新后，随从（以及骑兵随从的坐骑）每秒自检一次，对你不是友好就立刻改回。已经召出来的随从，更新后重新召唤一次最稳妥。如果还会被打到，请在设置 → 高级里生成诊断报告发给我们，并说明是哪只怪、哪一招。
</details>

<details>
<summary><b>卡片上只有一个字，没有怪物头像</b></summary>

头像要从你自己的游戏里导出，安装包里没有。先在设置 → 游戏里确认模组已更新到 v0.37.3 或更新的版本，然后进游戏任意地图待 1 分钟左右，头像会陆续出现在助手里，不用重启。导出只需要一次。头像存在游戏目录的 <code>platform\steam\ue4ss\Mods\PhantomGladiator\Runtime\codex-icons</code>，删掉这个文件夹再进一次地图会重新导出。
</details>

## 工作原理

```
助手窗口（WebView2）
   │  同源 HTTP，仅本机 127.0.0.1
本地后台（panel/backend.py，随包附带精简 Python）
   │  文件桥：Runtime/inbox.tsv → ack.tsv，status.tsv 每 250 ms 刷新
游戏内模组（Mods/PhantomGladiator，UE4SS Lua）
   │  调用游戏原生的召唤、阵营、仇恨与 AI 接口
《影之刃零》
```

- 每条操作都要等游戏写回执（ack）才算完成，没有回执就标为「结果未确认」，不会自动重发，避免重复召唤。
- 召唤的每个单位都登记在模组里，清理只移除自己登记的单位，并把战斗中改过的关系逐条恢复、逐条读回确认。
- 助手不调用任何游戏接口，也不联网收集数据；联网只用于你主动或自动检查更新。

## 给开发者

```
Mods/PhantomGladiator/Scripts/   游戏内模组（Lua，入口 main.lua，配置 config.lua）
GameConfig/                      本作的 UE4SS 签名与内存布局适配
panel/backend.py                 本地后台：校验指令、文件桥、读取游戏状态（仅标准库）
panel/prototype/                 助手界面；mock-runtime.js 是可离线点击的原型，real-runtime.js 连接真实后台
desktop/PhantomGladiator.cs      原生窗口：WebView2、启动后台、安装组件、启动游戏、更新
tools/package/build.py           打包脚本：生成 dist/PhantomGladiator-<版本>-win64.zip
panel/static/                    开发用的旧网页面板
docs/STATS_GUIDE.md              怪物数值说明
```

**打包**：准备好 `build.py` 开头列出的三个第三方文件（Python 嵌入版、WebView2 SDK、UE4SS 3.0.1，脚本会核对 SHA-256），然后运行：

```powershell
python tools/package/build.py --deps <下载目录> --seed <游戏的 Runtime 目录>
```

`--seed` 提供随包附带的精简单位目录（由模组从游戏注册表导出）。编译原生窗口使用 Windows 自带的 .NET Framework 编译器，不需要安装 Visual Studio。

**界面原型**：用任意静态服务器打开 `panel/prototype/index.html`，左下角「原型演示」可以模拟连接状态、召唤失败、清理未完成等各种情况，不需要游戏。

## 声明

- 本项目是玩家自制的非官方工具，与《影之刃零》开发商 S-GAME（灵游坊）及发行方无关。
- 仓库和发布包不包含任何游戏资源文件。界面里的单位名称来自游戏内图鉴；单位头像由模组在你自己的电脑上从你的游戏里导出，只存在本机。版权归原权利人所有。
- 使用模组的风险由使用者自行承担。

## 许可

本项目以 [MIT 许可](LICENSE) 发布。发布包附带的第三方组件：

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)：MIT 许可
- [Python 3.11 嵌入版](https://www.python.org/)：PSF 许可
- [Microsoft Edge WebView2 SDK](https://www.nuget.org/packages/Microsoft.Web.WebView2)：见发布包内 `licenses` 文件夹

---

## English

**Phantom Gladiator** makes the monsters and bosses of *Phantom Blade Zero* fight each other. It is a UE4SS Lua mod plus a desktop app: pick units from the game's own codex, summon them to the Blue or Red team, start the fight, and watch from a free camera that keeps your character hidden and invulnerable.

**Get started**

1. Download `PhantomGladiator-<version>-win64.zip` from [Releases](https://github.com/LingYi-Liang/PhantomGladiator/releases/latest) and unzip it.
2. Run `PhantomGladiator.exe`. The first-run guide finds the game in your Steam library and installs UE4SS and the mod in one click.
3. Start the game, load a save, wait for the green "Connected" badge, then summon and fight.

**Features**: 177 codex characters (75 bosses), shown with their codex portraits once the mod has saved them from your own copy of the game (the first time you enter a map, in about a minute; no game images ship with the app) · Blue / Red / No team (fight a boss yourself) · 1–100 per summon (1, 5, 10 or 50 in one click), no total cap · unit stats: the game's own, equal to the first unit (107 combat attributes), or custom — set any of the game's 223 attributes (max and current HP, shield, Sha-Chi, damage and resistance multipliers, status buildup, execution thresholds, movement speed, level…) for units you summon next, each one read back. Damage is worked out from level-1 base values (a hit takes attacker's level-1 attack × move multiplier ÷ target's level-1 HP of the target's max HP), so custom HP, Sha-Chi, attack and Sha-Chi damage move those by the same ratio and equal stats copies them · summon difficulty: new units play at Wayfarer, Pathbreaker, Hellwalker or Sixty-Six Days (stats and the AI's difficulty checks) while the game, map enemies and your save keep their own difficulty · summon level: by default each unit spawns at its own level in the game (a boss at the level of its story fight), or pick another place it appears, the level of where you are, or a custom level from 1 to 60 (final stat = base × (1 + level curve) × difficulty modifier × unit-type modifier; for example 9,000 HP at level 1 becomes 109,881 at level 19) · fun features for your own character: infinite Sha-Chi, auto perfect deflect and auto-dodge for attacks that can't be deflected (experimental) · undying switch per side (takes hits, never goes down) and fights that time themselves, also shown at the top of the game screen on request · blue and red no longer drift out of a fight and walk home · monster-vs-monster executions: a broken or nearly dead fighter, or a boss on its health lock, is finished by the nearest enemy with the game's own execution (unique executions from 60 monster configurations, rider executions and native counters; the executor borrows the player's moves, so bodies may clip) · riders spawn on their own horses and the dog handler brings his dogs · a free camera that updates every frame (Space/E up, Ctrl/Q down; adjustable move speed, turn speed and smoothing), time stop that pauses the game while the camera keeps moving, an execution camera that plays each execution's own camera work, and no-aggro spectating · all 10 function keys rebindable (none bound by default; the Spectate card sets its own) · stuck commands can be cleared from Activity · per-unit summon keys that remember their own team and amount · companions: summon any unit to follow you and fight on your side (no limit, teleports back from 100 m, after fast travel or when stuck on steps and ledges, a Bring to me button and key, grabs work on map enemies, their own summons and a rider's mount join your side, and they stay friendly even when summoned with the free camera or no aggro on, dismiss any time) · rematch with the last lineup · six UI languages chosen from your time zone; unit, chapter and map names follow your game's language once you have entered a map with the mod (Chinese until then), as do the in-game boss bars · light and dark themes · update checks with mirrors, SHA-256 verification and a release history of every version.

**Why can an early boss beat a late one?** In monster-vs-monster fights each hit takes a share of the target's max HP: attacker's level-1 attack × move multiplier ÷ target's level-1 HP. Level only makes the numbers bigger, so a level-7 boss with 41,800 HP can beat a level-26 one with 223,200 HP. For a fight that is fair on numbers, set *Unit stats* to *Equal stats*: every unit takes the first one's numbers, copying 107 combat attributes and the level-1 base values, leaving moves, speed and AI to decide.

**Requirements**: Windows 10/11 64-bit, WebView2 runtime (built in), Steam version of *Phantom Blade Zero* build 26367565 (other builds untested).

The mod only changes objects in memory while the game runs; it never edits game files or saves. Unit portraits are saved by the mod from your own copy of the game and stay on your PC. This is an unofficial fan project, not affiliated with S-GAME. Released under the [MIT License](LICENSE).
