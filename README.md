# A simple version of opening cases
***The plugin is a case model spawner that starts a timer before creating an entity simulating a reward. As a reward, you can set VIP groups, a random number of credits and experience.***
[^1]: It is a standalone plugin, on the basis of which I am currently writing a private(maybe public) CORE equal to WSGK.

## Requirements
 - [CSGO Colors](https://hlmod.ru/threads/inc-cs-go-colors.46870/)
 - [Levels Ranks](https://github.com/levelsranks/levels-ranks-core/tree/3.1.7B2) (optional)
 - [Shop](https://github.com/hlmod/Shop-Core)
 - [VIP Core](https://github.com/R1KO/VIP-Core/releases) (optional)
 - [FPS](https://github.com/OkyHp/Fire-Players-Stats) (optional)
 - [ParticleFix](https://github.com/komashchenko/ParticleFix/releases/tag/v1.0.2) (optional)
 - *>=* SM 1.10
 - MYSQL | SQLITE

## Setup
1) Move all files according to the current directories. 
2) Add **"case_opener"** section in configuration file **addons/sourcemod/configs/database.cfg**:
```
"case_opener"
{
  "driver"      "mysql"
  "host"	"255.255.255.255"
  "database"	"dbname"
  "user"	"dbuser"
  "pass"	"password"
}
```
3) To configure **CaseOpener.cfg** for yourself in the source code before compilation or after file generation
4) To configure **Opener.ini** if you need 
5) Depends by the statistics plugin on the server - delete the **lvl_ranks.inc** or **FirePlayersStats.inc** library from the **addons/sourcemod/scripting/include** folder. If dont use these plugins for statistics you should delete both libraries
6) Compile **Case Opener.sp** and move it to the **plugins** folder.
7) Restart a server
## Commands 
- Setts in **Opener.ini**
## ConVars
The plugin has auto-generation of a configuration file as **CaseOpener.cfg** located on the path **cfg/sourcemod/** containing ConVars:
- **sm_opener_time_give_vip** - Time of VIP in seconds. 0 - forever.	**Default: 604700**
- **sm_opener_min_exp** - Minimum number of received experience.	**Default: 400**
- **sm_opener_max_exp** - Maximum number of received experience.	**Default: 1000**
- **sm_opener_time_before_next_open** - Time between case openings in seconds.	**Default: 604800**
- **sm_opener_open_anim_speed** - The animation speed of the case. It is configured together with sm_opener_open_speed.	**Default: 0.1**
- **sm_opener_open_speed** - Case opening speed. It is configured together with sm_opener_open_anim_speed.	**Default: 11.5**
- **sm_opener_open_speed_scroll** - Scroll speed.	**Default: 0.25**
- **sm_opener_min_credits** - Minimum number of credits received.	**Default: 500**
- **sm_opener_max_credits** - Maximum number of credits received.	**Default: 2500**
- **sm_opener_max_position_value** - The maximum distance to case spawn. Depends by sm_opener_max_position.	**Default: 3**
- **sm_opener_case_kill_time** - The time after which the case will disappear in seconds.	**Default: 3**
- **sm_opener_same_plat** - Spawn the case on the same plane with the owner.	**1 - Yes | 0 - No.**
- **sm_opener_kill_case_sound** - Turn on the sound of the case disappearing.	**1 - Yes | 0 - No.**
- **sm_opener_case_opening_sound** - Enable case opening sounds.	**1 - Yes | 0 - No.**
- **sm_opener_case_messages** - Enable chat messages.	**1 - Yes | 0 - No.**
- **sm_opener_case_messages_hint** - Enable messages in the hint.	**1 - Yes | 0 - No.**
- **sm_opener_case_access** - Access only for admins.	**1 - Yes | 0 - No.**
- **sm_opener_max_position** - Limit the spawn distance.	**1 - Yes | 0 - No.**
- **sm_opener_open_output_beam** - Display the maximum spawn radius.	**1 - Yes | 0 - No.**
- **sm_opener_give_vip** - Drop a VIP group.	**1 - Yes | 0 - No.**
- **sm_opener_give_exp** - Drop a experience.	**1 - Yes | 0 - No.**
- **sm_opener_reset_counter** - Allow admins to reset the counter.	**1 - Yes | 0 - No.**
- **sm_opener_log** - Enable logging case drops.	**1 - Yes | 0 - No.**
- **sm_opener_print_all** - Print for all when player items drops.	**1 - Yes | 0 - No.**
- **sm_opener_no_boom** - Disable the explosion when removing the case.	**1 - Yes | 0 - No.**
- **sm_opener_start_counter** - To start counter.	**1 - after touch | 0 - after open.**

**mark**: To drop out the necessary VIP groups - configure the Opener.ini with the specifying of the desired groups and chances

## IMPORTANT 
- If you are has lags by types a command !case - set the plugin on SQLite connection or change MYSQL server

## Thanks
- [ScriptKiddie](https://hlmod.ru/members/scriptkiddie.152745/) (tests & ideas)

## About possible problems, please let me know: 
- Quake#2601 - DISCORD
- [HLMOD](https://hlmod.ru/members/palonez.92448/)
- [STEAM](https://steamcommunity.com/id/comecamecame/)
