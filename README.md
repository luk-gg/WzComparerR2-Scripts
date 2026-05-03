Lua scripts for [WzComparerR2](https://github.com/PirateIzzy/WzComparerR2) to batch dump data and assets from .wz files. They have been specifically tested with MapleStory Classic World's Closed Online Test client, but may work with other clients as well.

## Usage
Download the latest [WzComparerR2](https://github.com/PirateIzzy/WzComparerR2/releases) and [all scripts in this repo](https://github.com/PirateIzzy/WzComparerR2/archive/refs/heads/master.zip).

In WzComparerR2, open your `Base.wz`, then click `Tools > Lua Console` and open `DumpEverything.lua`. Change the config variables at the top to your liking, then click `Debug > Run`.

Valid export file types and other config options can be seen in [DumpEverything.lua](DumpEverything.lua).

> [!IMPORTANT]
> If you are missing the Lua Console, try using WinRar to extract WzComparerR2 instead of the default Windows zip extractor.

## Notes
To avoid making thousands of unnecessary folders, the output will not mirror the exact file structure seen in the WzComparer GUI. Instead, the directories stop at the `.img` level, and periods are used in file names to separate further path segments, i.e. `Character\0000001.img\stand\0\1` becomes `Character\0000001.img\stand.0.1.png`.

When combining static images to make animations, the game uses "Wz_Uol" (a reference to an existing asset) to reuse existing frames. So while a "walk" animation might only export 3 images, it might also reference 2 frames from the "stand" animation. Check `Npc\0000406.img\smile` in WzComparer for an example.

| Archive | Contents |
|---------|----------|
| Character.wz | Body, hair, face, equipment |
| Effect.wz    | Damage numbers, level up effects, buffs, debuffs, skill effects like Assaulter afterimage |
| Etc.wz       | Data and strings |
| Item.wz      | Non-equip items like use, cash, set up, etc, pet |
| Map.wz       | Map tiles and data |
| Mob.wz       | Enemy sprites and stats |
| Morph.wz     | Character transformations into mobs |
| Npc.wz       | NPCs |
| Quest.wz     | Quests |
| Reactor.wz   | Breakables |
| Skill.wz     | Skills |
| Sound.wz     | Sounds |
| String.wz    | Game text |
| TamingMob.wz | Mounts? |
| UI.wz        | In-game UI |