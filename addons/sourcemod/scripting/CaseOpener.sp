#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <csgo_colors>
#include <shop>
#tryinclude <vip_core>
#tryinclude <lvl_ranks>
#tryinclude <FirePlayersStats>

#if !defined _shop_included
	#error "Cant find in directory \"scripting/include/\" SHOP CORE library named as \"shop.inc\""
#endif

#if defined _vip_core_included
	bool bGiveVIP;
	ConVar g_hGiveVIP;
	ArrayList hArrayList;
#else
#endif

#if defined _levelsranks_included_ || defined _fire_players_stats_included
#if defined _levelsranks_included_
#endif
#if defined _fire_players_stats_included
#endif
#if defined _fire_players_stats_included && defined _levelsranks_included_
	#error "CANT USE TWO STATS PLUGINS TOGETHER. REMOVE FirePlayerStats.inc or lvl_ranks.inc"
#endif
	int iMinExp;
	int iMaxExp;
	bool bGiveExp;
	ConVar g_hGiveExp;
	ConVar g_hMinExp;
	ConVar g_hMaxExp;
#else
#endif

ArrayList aRating[2];

Database gDatabase;
KeyValues kv;
Handle hTimers[MAXPLAYERS+1][6];

float 
	fOpenSpeed,
	fOpenSpeedScroll,
	fOpenSpeedAnim;

int 
	iTimeBeforeNextOpen,
	iMinCredits,
	iMaxCredits,
	iMaxPositionValue,
	iCaseKillTimer,
	iExplode,
	iReward[MAXPLAYERS+1] = {-1,...},
	iEntCaseData[MAXPLAYERS+1][5],
	g_HaloSprite,
	g_BeamSprite;

bool 
	bEnableBoom,
	bWarn[MAXPLAYERS+1],
	bCaseRequestPending[MAXPLAYERS+1],
	bRewardClaimed[MAXPLAYERS+1],
	bOutputBeam,
	bSamePlat,
	bKillCaseSound,
	bCaseOpeningSound,
	bCaseMessages,
	bCaseMessagesHint,
	bCaseAccess,
	bMaxPosition,
	bResetCounter,
	bPrintAll,
	bDropLog,
	bStartCounter;

ConVar 
	g_hEnableBoom,
	g_hOutputBeam,
	g_hOpenSpeedAnim,
	g_hOpenSpeedScroll,
	g_hTimeBeforeNextOpen,
	g_hOpenSpeed,
	g_hMinCredits,
	g_hMaxCredits,
	g_hPrintAll,
	g_hDropLog,
	g_hMaxPositionValue,
	g_hCaseKillTimer,
	g_hSamePlat,
	g_hKillCaseSound,
	g_hCaseOpeningSound,
	g_hCaseMessages,
	g_hCaseMessagesHint,
	g_hCaseAccess,
	g_hMaxPosition,
	g_hResetCounter,
	g_hStartCounter;

char sQuery[256], auth[22];

#include "CaseOpener/files.sp"

static char sLog[PLATFORM_MAX_PATH];

static const char sColor[][] = {"FF0000", "00FF00"};

enum { x, y, z };

enum { open, vip, exp, crd };

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) 
{
	if(GetEngineVersion() != Engine_CSGO) 
	{
		SetFailState("[CASEOPENER] Error loading plugin: Only for CS:GO");
		return APLRes_Failure;
	}
	else if(error[0]) 
	{
		SetFailState("[CASEOPENER] Error loading plugin: %s", error);
		return APLRes_Failure;
	}
	
	return APLRes_Success;
}

public Plugin myinfo = 
{
	name = "Case Opener",
	author = "Quake1011",
	description = "Spawning case with reward",
	version = "1.5.0",
	url = "https://github.com/Quake1011/"
}

public void OnPluginStart() 
{
	if(!SQL_CheckConfig("case_opener")) 
		SetFailState("[CASEOPENER] Section \"case_opener\" is not found in databases.cfg");

	Database.Connect(SQLConnectGlobalDB, "case_opener");

	HookEvent("round_start", EventRoundStart, EventHookMode_Post);
	
	for(int i = 1;i <= MaxClients; i++) 
		NullClient(i);

	LoadTranslations("CaseOpener.phrases.txt");
	
#if defined _vip_core_included
	HookConVarChange((g_hGiveVIP = CreateConVar("sm_opener_give_vip","1","Give the VIP Group [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bGiveVIP = g_hGiveVIP.BoolValue;
#endif
#if defined _levelsranks_included_ || defined _fire_players_stats_included
	HookConVarChange((g_hGiveExp = CreateConVar("sm_opener_give_exp","1","Give the experience [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bGiveExp = g_hGiveExp.BoolValue;

	HookConVarChange((g_hMinExp = CreateConVar("sm_opener_min_exp","400","Minimum number of received experience.",0, true, 0.0)), OnConvarChanged);
	iMinExp = g_hMinExp.IntValue;

	HookConVarChange((g_hMaxExp = CreateConVar("sm_opener_max_exp","1000","Maximum number of received experience.",0, true, 0.0)), OnConvarChanged);
	iMaxExp = g_hMaxExp.IntValue;
#endif
	HookConVarChange((g_hResetCounter = CreateConVar("sm_opener_reset_counter","1","Allow admins to reset the counter [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bResetCounter = g_hResetCounter.BoolValue;

	HookConVarChange((g_hDropLog = CreateConVar("sm_opener_log","1","Enable logging case drops [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bDropLog = g_hDropLog.BoolValue;

	HookConVarChange((g_hPrintAll = CreateConVar("sm_opener_print_all","1","Print for all when player items drops [1 - For all | 0 - For self]. When enabled sm_opener_case_messages",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bPrintAll = g_hPrintAll.BoolValue;

	HookConVarChange((g_hTimeBeforeNextOpen = CreateConVar("sm_opener_time_before_next_open", "604800", "Time between case openings in seconds.",0, true, 0.0)), OnConvarChanged);
	iTimeBeforeNextOpen = g_hTimeBeforeNextOpen.IntValue;

	HookConVarChange((g_hOpenSpeedAnim = CreateConVar("sm_opener_open_anim_speed","0.1","The animation speed of the case. It is configured together with sm_opener_open_speed.",0, true, 0.01)), OnConvarChanged);
	fOpenSpeedAnim = g_hOpenSpeedAnim.FloatValue;

	HookConVarChange((g_hOpenSpeed = CreateConVar("sm_opener_open_speed","11.5","Case opening speed. It is configured together with sm_opener_open_anim_speed.",0, true, 0.1)), OnConvarChanged);
	fOpenSpeed = g_hOpenSpeed.FloatValue;

	HookConVarChange((g_hOpenSpeedScroll = CreateConVar("sm_opener_open_speed_scroll","0.25","Speed of scrolls.",0, true, 0.05)), OnConvarChanged);
	fOpenSpeedScroll = g_hOpenSpeedScroll.FloatValue;

	HookConVarChange((g_hOutputBeam = CreateConVar("sm_opener_open_output_beam","1","Display the maximum spawn radius of the case [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bOutputBeam = g_hOutputBeam.BoolValue;

	HookConVarChange((g_hMinCredits = CreateConVar("sm_opener_min_credits","500","Minimum number of credits received.",0, true, 0.0)), OnConvarChanged);
	iMinCredits = g_hMinCredits.IntValue;

	HookConVarChange((g_hMaxCredits = CreateConVar("sm_opener_max_credits","2500","Maximum number of credits received.",0, true, 0.0)), OnConvarChanged);
	iMaxCredits = g_hMaxCredits.IntValue;

	HookConVarChange((g_hMaxPositionValue = CreateConVar("sm_opener_max_position_value","3","The maximum distance to case spawn. Depends by sm_opener_max_position",0, true, 0.0)), OnConvarChanged);
	iMaxPositionValue = g_hMaxPositionValue.IntValue;

	HookConVarChange((g_hCaseKillTimer = CreateConVar("sm_opener_case_kill_time","3","The time after which the case will disappear in seconds.",0, true, 1.0)), OnConvarChanged);
	iCaseKillTimer = g_hCaseKillTimer.IntValue;

	HookConVarChange((g_hSamePlat = CreateConVar("sm_opener_same_plat","1","Spawn the case on the same plane with the owner [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bSamePlat = g_hSamePlat.BoolValue;

	HookConVarChange((g_hKillCaseSound = CreateConVar("sm_opener_kill_case_sound","1","Turn on the sound of the case disappearing [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bKillCaseSound = g_hKillCaseSound.BoolValue;

	HookConVarChange((g_hCaseOpeningSound = CreateConVar("sm_opener_case_opening_sound","1","Enable case opening sounds [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bCaseOpeningSound = g_hCaseOpeningSound.BoolValue;

	HookConVarChange((g_hCaseMessages = CreateConVar("sm_opener_case_messages","1","Enable chat messages [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bCaseMessages = g_hCaseMessages.BoolValue;

	HookConVarChange((g_hCaseMessagesHint = CreateConVar("sm_opener_case_messages_hint","1","Enable messages in the hint [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bCaseMessagesHint = g_hCaseMessagesHint.BoolValue;

	HookConVarChange((g_hCaseAccess = CreateConVar("sm_opener_case_access","0","Access only for admins [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bCaseAccess = g_hCaseAccess.BoolValue;

	HookConVarChange((g_hMaxPosition = CreateConVar("sm_opener_max_position","1","Restrict distance for spawn case [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bMaxPosition = g_hMaxPosition.BoolValue;

	HookConVarChange((g_hEnableBoom = CreateConVar("sm_opener_no_boom","1","Disable the explosion when removing the case [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bEnableBoom = !g_hEnableBoom.BoolValue;

	HookConVarChange((g_hStartCounter = CreateConVar("sm_opener_start_counter","1","To start counter [1 - after touch, 0 - after open]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bStartCounter = g_hStartCounter.BoolValue;
	
	AutoExecConfig(true, "CaseOpener");
	
	char sPath[PLATFORM_MAX_PATH];	
#if defined _vip_core_included
	hArrayList = CreateArray(64);
#endif
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/Opener.ini");
	kv = CreateKeyValues("Settings");
	
	bool bConfigLoaded = kv.ImportFromFile(sPath);
	if(bConfigLoaded) 
	{
		char buffer[64];
		kv.Rewind();
		if(kv.GotoFirstSubKey())
		{
			do{
				kv.GetSectionName(buffer, sizeof(buffer));
				LogMessage("VIP founded in Opener.ini: %s | chance: %.3f", buffer, kv.GetFloat("chance"));
		#if defined _vip_core_included
				hArrayList.PushString(buffer);
		#endif
			} while(kv.GotoNextKey());
		}
	}
	else
		LogError("[CASEOPENER] Cannot load config: %s", sPath);

	RegCommandsFromKv("cmds_case", Command_Case, "Spawn case in view direction point", "sm_case");
	RegCommandsFromKv("cmds_reset_me", CommandResetCounter, "Fast reset self counter", "sm_rc");
	RegCommandsFromKv("cmds_reset_all", CommandResetFor, "List of players for reset anybody counter", "sm_ra");
	RegCommandsFromKv("cmds_rating", CommandRatingMenu, "Menu of case rating", "sm_cstats");
	
	BuildPath(Path_SM, sLog, sizeof(sLog), "logs/CaseOpener.log");
	if(bDropLog)
	{
		File hFile = OpenFile(sLog, "a+");
		CloseHandle(hFile);
	}
	
	aRating[0] = aRating[1] = CreateArray(256);
}

public void OnConvarChanged(ConVar convar, const char[] oldValue, const char[] newValue) 
{
	if(convar == g_hOpenSpeedScroll) fOpenSpeedScroll = convar.FloatValue;
	else if(convar == g_hTimeBeforeNextOpen) iTimeBeforeNextOpen = convar.IntValue;
#if defined _vip_core_included
	else if(convar == g_hGiveVIP) bGiveVIP = convar.BoolValue;
#endif
#if defined _levelsranks_included_ || defined _fire_players_stats_included
	else if(convar == g_hMinExp) iMinExp = convar.IntValue;
	else if(convar == g_hGiveExp) bGiveExp = convar.BoolValue;
	else if(convar == g_hMaxExp) iMaxExp = convar.IntValue;
#endif
	else if(convar == g_hOutputBeam) bOutputBeam = convar.BoolValue;
	else if(convar == g_hOpenSpeed) fOpenSpeed = convar.FloatValue;
	else if(convar == g_hOpenSpeedAnim) fOpenSpeedAnim = convar.FloatValue;
	else if(convar == g_hMinCredits) iMinCredits = convar.IntValue;
	else if(convar == g_hMaxCredits) iMaxCredits = convar.IntValue;
	else if(convar == g_hMaxPositionValue) iMaxPositionValue = convar.IntValue;
	else if(convar == g_hCaseKillTimer) iCaseKillTimer = convar.IntValue;
	else if(convar == g_hSamePlat) bSamePlat = convar.BoolValue;
	else if(convar == g_hKillCaseSound) bKillCaseSound = convar.BoolValue;
	else if(convar == g_hCaseOpeningSound) bCaseOpeningSound = convar.BoolValue;
	else if(convar == g_hCaseMessages) bCaseMessages = convar.BoolValue;
	else if(convar == g_hCaseMessagesHint) bCaseMessagesHint = convar.BoolValue;
	else if(convar == g_hCaseAccess) bCaseAccess = convar.BoolValue;
	else if(convar == g_hMaxPosition) bMaxPosition = convar.BoolValue;
	else if(convar == g_hResetCounter) bResetCounter = convar.BoolValue;
	else if(convar == g_hDropLog) bDropLog = convar.BoolValue;
	else if(convar == g_hPrintAll) bPrintAll = convar.BoolValue;
	else if(convar == g_hEnableBoom) bEnableBoom = !convar.BoolValue;
	else if(convar == g_hStartCounter) bStartCounter = convar.BoolValue;
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//																							CMDS CALLBACKS																					//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

public Action Command_Case(int client, int args) 
{
	if(!IsValidHumanClient(client))
		return Plugin_Handled;

	if(IsPlayerAlive(client)) 
	{
		if(gDatabase == null || bCaseRequestPending[client])
			return Plugin_Handled;

		if(!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)))
			return Plugin_Handled;

		bCaseRequestPending[client] = true;
		SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "SELECT `last_open`, `available` FROM `opener_base` WHERE `steam`='%s'", auth);
		gDatabase.Query(SQLCreatingCaseQuery, sQuery, GetClientUserId(client), DBPrio_High);
	}
	else 
	{
		if(bCaseMessages) 
			CGOPrintToChat(client, "%t%t", "prefix", "be_alive");
			
		EmitSoundToClient(client, "buttons/blip1.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR);
	}
	return Plugin_Handled;
}

public Action CommandResetCounter(int client, int args) 
{
	if(!IsValidHumanClient(client))
		return Plugin_Handled;

	if(bResetCounter) 
	{
		if(GetUserAdmin(client) != INVALID_ADMIN_ID)
		{
			if(gDatabase != null && GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)))
			{
				SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "SELECT `steam` FROM `opener_base` WHERE `steam`='%s'", auth);
				gDatabase.Query(SQLResetedCounterCB, sQuery, GetClientUserId(client), DBPrio_High);
			}
		}
	}
	else 
	{
		if(bCaseMessages) 
			CGOPrintToChat(client, "%t%t", "prefix", "not_works");
			
		EmitSoundToClient(client, "buttons/blip1.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR);
	}
	return Plugin_Handled;
}

public Action CommandResetFor(int client, int args)
{
	if(!IsValidHumanClient(client))
		return Plugin_Handled;

	if(bResetCounter)
	{
		if(GetUserAdmin(client) != INVALID_ADMIN_ID)
		{
			char temp[2][256], buff[256];
			Menu hMenu = CreateMenu(SelectPlayer);
			Format(buff, sizeof(buff), "%t", "Select player");
			hMenu.SetTitle(buff);
			for(int i = 1;i <= MaxClients; i++)
			{
				if(IsClientInGame(i) && !IsFakeClient(i) && !IsClientSourceTV(i))
				{
					Format(temp[0], 256, "%i", GetClientUserId(i));
					Format(temp[1], 256, "%N(%i)", i, GetClientUserId(i));
					hMenu.AddItem(temp[0], temp[1]);
				}
			}
			hMenu.ExitButton = true;
			hMenu.Display(client, 0);			
		}
	}
	else 
	{
		if(bCaseMessages) 
			CGOPrintToChat(client, "%t%t", "prefix", "not_works");
		EmitSoundToClient(client, "buttons/blip1.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR);
	}
	return Plugin_Handled;
}

public Action CommandRatingMenu(int client, int args)
{
	if(IsValidHumanClient(client))
		OpenRatingMainCmdMenu(client);
	return Plugin_Handled;
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//																							HANDLERS																						//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

public int RatingMenu(Menu menu, MenuAction action, int client, int item)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char info[256], position[8];
			menu.GetItem(item, position, sizeof(position), _, info, sizeof(info));
			switch(position[0])
			{
				case '0': 	
				{
					OpenTopSub(open, client);
					GetRatingNow(open, client);
				}
				case '1':	
				{
					OpenTopSub(vip, client);
					GetRatingNow(vip, client);
				}
				case '2':	
				{
					OpenTopSub(crd, client);
					GetRatingNow(crd, client);
				}
				case '3':	
				{
					OpenTopSub(exp, client);
					GetRatingNow(exp, client);
				}
			}
		}
		case MenuAction_End: 
			delete menu;
	}
	return 0;
}

public int MenuHandlers(Menu menu, MenuAction action, int client, int item)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			if(item == 3) 
				OpenRatingMainCmdMenu(client);
			else if(item == 4) 
				return 0;
		}
		case MenuAction_End:
			delete menu;
	}
	return 0;
}

public int SelectPlayer(Menu menu, MenuAction action, int client, int item)
{
	switch(action)
	{
		case MenuAction_End: delete menu;
		case MenuAction_Select: 
		{
			char tmp[32];
			menu.GetItem(item, tmp, sizeof(tmp));
			int idx = GetClientOfUserId(StringToInt(tmp));
			if(!IsValidHumanClient(idx) || gDatabase == null)
				return 0;

			GetClientAuthId(idx, AuthId_Steam2, auth, sizeof(auth));

			SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "SELECT `steam` FROM `opener_base` WHERE `steam`='%s'", auth);
			gDatabase.Query(SQLResetCounterCB, sQuery, GetClientUserId(idx), DBPrio_High);
			
			char temp[2][256], buff[256];
			Menu hMenu = CreateMenu(SelectPlayer);
			Format(buff, sizeof(buff), "%t", "Select player");
			hMenu.SetTitle(buff);
			for(int i = 1;i <= MaxClients; i++)
			{
				if(IsClientInGame(i) && !IsFakeClient(i) && !IsClientSourceTV(i))
				{
					Format(temp[0], 256, "%i", GetClientUserId(i));
					Format(temp[1], 256, "%N(%i)", i, GetClientUserId(i));
					hMenu.AddItem(temp[0], temp[1]);
				}
			}
			hMenu.ExitButton = true;
			hMenu.Display(client, 0);
		}
	}
	return 0;
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//																							EVENTS																							//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

public void OnClientDisconnect(int client) 
{
	NullClient(client);
}

public void OnClientPostAdminCheck(int client) 
{
	if(IsValidHumanClient(client)) 
	{
		NullClient(client);
		AddDataToDB(client);
	}
}

public void OnMapStart() 
{
	for(int i = 0; i < sizeof(sDownloadPaths); i++) 
		AddFileToDownloadsTable(sDownloadPaths[i]);	
	
	PreCacheFiles();
}

public void OnMapEnd()
{
	for(int j = 1; j <= MaxClients; j++)
		NullClient(j);

	if(kv != null)
		kv.Rewind();
}

public void EventRoundStart(Event hEvent, const char[] sEvent, bool bdb) 
{
	for(int i = 1; i <= MaxClients; i++) 
		if(IsValidHumanClient(i)) 
			NullClient(i);
}

public Action Hook_ModelStartTouch(int iEntity, int activator) 
{
	if(activator > 0 && activator <= MaxClients && IsClientInGame(activator) && IsPlayerAlive(activator))
	{
		if(iEntCaseData[activator][1] == iEntity && iEntity > MaxClients && IsValidEntity(iEntity) && !bRewardClaimed[activator])
		{
			bRewardClaimed[activator] = true;
			char sTime[32];
			FormatTime(sTime, sizeof(sTime), "%X", GetTime());
			switch(iReward[activator]) 
			{
				case 0: 
				{
					Shop_GiveClientCredits(activator, iEntCaseData[activator][4], CREDITS_BY_NATIVE);
					UpdateRating(crd, activator, iEntCaseData[activator][4]);
					if(bCaseMessages)
					{
						if(bPrintAll) 
							CGOPrintToChatAll("%t%t", "prefix", "received_credits_all", activator, iEntCaseData[activator][4]);
						else 
							CGOPrintToChat(activator, "%t%t", "prefix", "received_credits", iEntCaseData[activator][4]);
					}
					LogMessage("[CASEOPENER] The player %N received %i credits", activator, iEntCaseData[activator][4]);
					if(bDropLog) 
						LogToFileEx(sLog, "[ %s ] The player %N got %i credits ", sTime, activator, iEntCaseData[activator][4]);
				}
#if defined _levelsranks_included_ || defined _fire_players_stats_included
				case 1: 
				{
					if(bGiveExp) 
					{	
	#if defined _levelsranks_included_ || !defined _fire_players_stats_included
						LR_ChangeClientValue(activator, iEntCaseData[activator][4]);
	#elseif !defined _levelsranks_included_ || defined _fire_players_stats_included
						FPS_SetPoints(activator, float(iEntCaseData[activator][4]), false);
	#endif
						UpdateRating(exp, activator, iEntCaseData[activator][4]);
						
						if(bCaseMessages) 
						{
							if(bPrintAll) 
								CGOPrintToChatAll("%t%t", "prefix", "received_exp_all", activator, iEntCaseData[activator][4]);
							else 
								CGOPrintToChat(activator, "%t%t", "prefix", "received_exp", iEntCaseData[activator][4]);
						}
						LogMessage("[CASEOPENER] The player %N received %i experience", activator, iEntCaseData[activator][4]);
						if(bDropLog) 
							LogToFileEx(sLog, "[ %s ] The player %N got %i experience ", sTime, activator, iEntCaseData[activator][4]);
					}
					else 
					{
						Shop_GiveClientCredits(activator, iEntCaseData[activator][4], CREDITS_BY_NATIVE);
						UpdateRating(crd, activator, iEntCaseData[activator][4]);
						if(bCaseMessages) 
						{
							if(bPrintAll) 
								CGOPrintToChatAll("%t%t", "prefix", "received_credits_all", activator, iEntCaseData[activator][4]);
							else 
								CGOPrintToChat(activator, "%t%t", "prefix", "received_credits", iEntCaseData[activator][4]);
						}
						LogMessage("[CASEOPENER] The player %N received %i credits", activator, iEntCaseData[activator][4]);
						if(bDropLog) 
							LogToFileEx(sLog, "[ %s ] The player %N got %i credits ", sTime, activator, iEntCaseData[activator][4]);
					}
				}
#endif
#if defined _vip_core_included
				case 2: 
				{
					if(bGiveVIP) 
					{
						if(!VIP_IsClientVIP(activator)) 
						{
							char buffer[32];
							hArrayList.GetString(iEntCaseData[activator][4], buffer,sizeof(buffer));
							kv.Rewind();
							kv.JumpToKey(buffer);
							VIP_GiveClientVIP(0, activator, kv.GetNum("time"), buffer, true);
							UpdateRating(vip, activator, 0);
							if(bCaseMessages) 
							{
								if(bPrintAll) 
								{
									if(!kv.GetNum("time")) 
										CGOPrintToChatAll("%t%t", "prefix", "got_vip_all_forever", activator, buffer);
									else 
										CGOPrintToChatAll("%t%t", "prefix", "got_vip_all", activator, buffer, kv.GetNum("time"));
								}
							}
							LogMessage("[CASEOPENER] The player %N received a privilege: %s", activator, buffer);
							if(bDropLog) 
								LogToFileEx(sLog, "[ %s ] The player %N got %s for %i seconds ", sTime, activator, buffer, kv.GetNum("time"));
						}
						else 
						{
							if(bCaseMessages) 
							{
								if(bPrintAll) 
									CGOPrintToChatAll("%t%t", "prefix", "nothing", activator);
								else 
									CGOPrintToChat(activator, "%t%t", "prefix", "already_has_vip");
							}
							LogMessage("[CASEOPENER] The player %N already has vip", activator);
						}					
					}
					else 
					{
						Shop_GiveClientCredits(activator, iEntCaseData[activator][4], CREDITS_BY_NATIVE);
						UpdateRating(crd, activator, iEntCaseData[activator][4]);
						if(bCaseMessages)
						{
							if(bPrintAll) 
								CGOPrintToChatAll("%t%t", "prefix", "received_credits_all", activator, iEntCaseData[activator][4]);
							else 
								CGOPrintToChat(activator, "%t%t", "prefix", "received_credits", iEntCaseData[activator][4]);
						}
						LogMessage("[CASEOPENER] The player %N received %i credits", activator, iEntCaseData[activator][4]);
						if(bDropLog) 
							LogToFileEx(sLog, "[ %s ] The player %N got %i credits ", sTime, activator, iEntCaseData[activator][4]);
					}
				}
#endif
			}
			EmitSoundToClient(activator, "ui/panorama/music_equip_01.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR);
			if(bStartCounter)
			{
				if(gDatabase != null && GetClientAuthId(activator, AuthId_Steam2, auth, sizeof(auth)))
				{
					SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "UPDATE `opener_base` SET `available`='0', `last_open`='%i' WHERE `steam`='%s'", GetTime(), auth);
					SQL_FastQuery(gDatabase, sQuery);
				}
			}

			if(IsValidEdict(iEntCaseData[activator][1])) 
			{
				iEntCaseData[activator][2] = GetEntPropEnt(iEntCaseData[activator][1], Prop_Send, "m_hEffectEntity");
				if(iEntCaseData[activator][2] && IsValidEdict(iEntCaseData[activator][2])) 
					AcceptEntityInput(iEntCaseData[activator][2], "Kill");
				AcceptEntityInput(iEntCaseData[activator][1], "Kill");
			}
			if(hTimers[activator][3] != null)
				KillTimer(hTimers[activator][3]);
			hTimers[activator][3] = CreateTimer(float(iCaseKillTimer), OnTouchDelete, GetClientUserId(activator));
		}
		else if(bCaseMessages && iEntCaseData[activator][1] != -1) 
		{
			if(!bWarn[activator]) 
			{
				CGOPrintToChat(activator, "%t%t", "prefix", "not_your_case");
				bWarn[activator] = true;
			}
		}
	}
	return Plugin_Continue;
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//																							SQL CALLBACKS																					//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

public void Get10Rating(Database db, DBResultSet results, const char[] error, any data)
{
	int client = GetClientOfUserId(data);
	if(results && !error[0] && results.HasResults)
	{
		if(results.RowCount) 
		{
			aRating[0].Clear();
			aRating[1].Clear();
			char name[256];
			for(int i = 0; i < results.RowCount; i++)
			{
				results.FetchRow();
				results.FetchString(0, name, sizeof(name));
				aRating[0].PushString(name);
				aRating[1].Push(results.FetchInt(1));
			}
		}
		else if(IsValidHumanClient(client))
			PrintToChat(client, "Rating is empty now");
	}
	else 
		PrintError(error, 663);
}

public void UpdateSQLRateing(Database db, DBResultSet results, const char[] error, any data)
{
	if(error[0] || !db) 
		PrintError(error, 729);
}

public void SQLResetCounterCB(Database db, DBResultSet result, const char[] error, int client)
{
	client = GetClientOfUserId(client);
	if(!IsValidHumanClient(client))
		return;

	if(IsValidHumanClient(client) && result && !error[0])
	{
		if(result.HasResults && result.RowCount) 
		{
			if(!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)))
				return;
			
			SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "UPDATE `opener_base` SET `available`='1', `last_open`='0' WHERE `steam`='%s'", auth);
			SQL_FastQuery(gDatabase, sQuery);
			
			if(bCaseMessages) 
				CGOPrintToChat(client, "%t%t", "prefix", "counter_reseted");
		}
	}
	else 
		PrintError(error, 693);
}

public void SQLConnectGlobalDB(Database db, const char[] error, any data) 
{
	if(!db || error[0]) 
		SetFailState("[CASEOPENER] Problem with connection to Database");

	LogMessage("Connection is READY!");
	gDatabase = db;
	CreateTableDB();
}

public void SQLTQueryCallBack(Handle owner, Handle hndl, const char[] error, any data) 
{
	if(!error[0] && hndl) 
		LogMessage("[CASEOPENER] The table has been created");
	else 
	{
		SetFailState("[CASEOPENER] Cant create a table \"opener_base\": %s", error);
		LogError(error);
	}
}

public void SQLAddClientData(Database db, DBResultSet result, const char[] error, int client)
{
	client = GetClientOfUserId(client);
	if(!IsValidHumanClient(client))
		return;

	if(IsValidHumanClient(client) && result && !error[0])
	{
		if(result.HasResults) 
		{
			if(!result.RowCount) 
			{
				char name[MAX_NAME_LENGTH];
				if(!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)))
					return;
				GetClientName(client, name, sizeof(name));

				SQL_FormatQuery(db, sQuery, sizeof(sQuery), "INSERT INTO `opener_base` (`steam`, `last_open`, `available`, `name`, `cases_opened`, `vips_total`, `exp_total`, `credits_total`) VALUES ('%s', 0, 1, '%s', 0, 0, 0, 0)", auth, name);
				SQL_FastQuery(db, sQuery);
				
				LogMessage("[CASEOPENER] The player has been added to the database");
			}
			else 
				LogMessage("[CASEOPENER] The player %N is already in the database", client);
		}
	}
	else 
		PrintError(error, 799);
}

public void SQLResetedCounterCB(Database db, DBResultSet result, const char[] error, int client)
{
	client = GetClientOfUserId(client);
	if(!IsValidHumanClient(client))
		return;

	if(IsValidHumanClient(client) && result && !error[0])
	{
		if(result.HasResults && result.RowCount) 
		{
			if(!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)))
				return;
			
			SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "UPDATE `opener_base` SET `available`='1', `last_open`='0' WHERE `steam`='%s'", auth);
			SQL_FastQuery(gDatabase, sQuery);
			
			if(bCaseMessages) 
				CGOPrintToChat(client, "%t%t", "prefix", "counter_reseted");
		}
	}
	else 
		PrintError(error, 755);
}

public void SQLCreatingCaseQuery(Database db, DBResultSet result, const char[] error, int client)
{
	client = GetClientOfUserId(client);
	if(client <= 0 || client > MaxClients)
		return;

	bCaseRequestPending[client] = false;
	if(!IsValidHumanClient(client) || !result || error[0] || !result.HasResults || !result.RowCount || !result.FetchRow())
	{
		if(error[0])
			PrintError(error, 776);
		return;
	}

	int lastOpen = result.FetchInt(0);
	int available = result.FetchInt(1);
	int remaining = (lastOpen + iTimeBeforeNextOpen) - GetTime();
	if(!available && remaining > 0)
	{
		if(bCaseMessages)
			CGOPrintToChat(client, "%t%t", "prefix", "wait_next_case", remaining / 3600 / 24, remaining / 3600 % 24, remaining / 60 % 60, remaining % 60);
		EmitSoundToClient(client, "buttons/blip1.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR);
		return;
	}

	if(!available)
	{
		if(!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)))
			return;
		SQL_FormatQuery(db, sQuery, sizeof(sQuery), "UPDATE `opener_base` SET `available`='1' WHERE `steam`='%s'", auth);
		SQL_FastQuery(db, sQuery);
	}

	if(iEntCaseData[client][0] != -1 || iEntCaseData[client][1] != -1 || iEntCaseData[client][2] != -1 || iEntCaseData[client][3] != -1 || iEntCaseData[client][4] != -1)
	{
		if(bCaseMessages)
			CGOPrintToChat(client, "%t%t", "prefix", "existing_case");
		EmitSoundToClient(client, "buttons/blip1.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR);
		return;
	}

	if(bCaseAccess && GetUserAdmin(client) == INVALID_ADMIN_ID)
	{
		if(bCaseMessages)
			CGOPrintToChat(client, "%t%t", "prefix", "not_admin");
		EmitSoundToClient(client, "buttons/blip1.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR);
		return;
	}

	float fOrig[3], fAng[3], fEndOfTrace[3];
	GetClientEyePosition(client, fOrig);
	GetClientEyeAngles(client, fAng);
	Handle hTrace = TR_TraceRayFilterEx(fOrig, fAng, CONTENTS_SOLID, RayType_Infinite, TRFilter, client);
	if(hTrace == INVALID_HANDLE || !TR_DidHit(hTrace))
	{
		delete hTrace;
		return;
	}

	float fClientOrigin[3];
	TR_GetEndPosition(fEndOfTrace, hTrace);
	GetClientAbsOrigin(client, fClientOrigin);
	delete hTrace;

	if(bSamePlat && FloatAbs(fEndOfTrace[z] - fClientOrigin[z]) >= 5.0)
	{
		if(bCaseMessages)
			CGOPrintToChat(client, "%t%t", "prefix", "same_level_case");
		return;
	}

	if(bMaxPosition && GetVectorDistance(fClientOrigin, fEndOfTrace) > float(iMaxPositionValue * 100))
	{
		if(bCaseMessages)
			CGOPrintToChat(client, "%t%t", "prefix", "too_longer", iMaxPositionValue);
		if(bOutputBeam)
		{
			float fDist = float(iMaxPositionValue * 100);
			TE_SetupBeamRingPoint(fClientOrigin, 0.0, fDist * 2, g_BeamSprite, g_HaloSprite, 0, 660, 1.0, 2.0, 0.0, {255, 255, 0, 255}, 1000, 0);
			TE_SendToClient(client);
		}
		EmitSoundToClient(client, "buttons/blip1.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR);
		return;
	}

	bRewardClaimed[client] = false;
	DataPack dp = CreateDataPack();
	float fPosit[3];
	fPosit = SpawnCase(client, fEndOfTrace, fAng);
	dp.WriteCell(GetClientUserId(client));
	dp.WriteFloat(fPosit[0]);
	dp.WriteFloat(fPosit[1]);
	dp.WriteFloat(fPosit[2]);
	hTimers[client][4] = CreateTimer(1.4, FallAfterTimer, dp);
}

public void SQLTCheckStatusForTime(Database db, DBResultSet result, const char[] error, int client)
{
	client = GetClientOfUserId(client);
	if(IsValidHumanClient(client) && result && !error[0])
	{
		if(result.HasResults && result.RowCount && result.FetchRow())
		{
			int time = (result.FetchInt(1) + iTimeBeforeNextOpen) - GetTime();
			if(time >= 0) 
				CGOPrintToChat(client, "%t%t", "prefix", "wait_next_case", time/3600/24, time/3600%24, time/60%60, time%60);
			EmitSoundToClient(client, "buttons/blip1.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR);
			LogMessage("[CASEOPENER] The player %N trying to use !case command but already has active block after opening", client);
		}		
	}
	else 
		PrintError(error, 860);
}

public void SQLCheckTimeStatusCaseClient(Database db, DBResultSet result, const char[] error, int client)
{
	client = GetClientOfUserId(client);
	if(IsValidHumanClient(client) && result && !error[0])
	{
		if(result.HasResults && result.RowCount && result.FetchRow())
		{
			if((result.FetchInt(1) + iTimeBeforeNextOpen) <= GetTime()) 
			{
				result.FetchString(0, auth, sizeof(auth));
				
				SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "UPDATE `opener_base` SET `available`='1' WHERE `steam`='%s'", auth);
				SQL_FastQuery(gDatabase, sQuery);
			}
		}
	}
	else 
		PrintError(error, 892);
}

public void SQLOnRewardSpawn(Database db, DBResultSet result, const char[] error, int client)
{
	client = GetClientOfUserId(client);
	if(IsValidHumanClient(client) && result && !error[0])
	{
		if(result.HasResults && result.RowCount) 
		{
			char steam[32], query[256];
			if(GetClientAuthId(client, AuthId_Steam2, steam, sizeof(steam)))
			{
				SQL_FormatQuery(db, query, sizeof(query), "UPDATE `opener_base` SET `available`='0', `last_open`='%i' WHERE `steam`='%s'", GetTime(), steam);
				SQL_FastQuery(db, query);
			}
		}
	}
	else 
		PrintError(error, 906);
}

public void SQLSetUnavailableCase(Database db, DBResultSet result, const char[] error, int client)
{
	client = GetClientOfUserId(client);
	if(IsValidHumanClient(client) && result && !error[0]) 
	{
		if(result.HasResults && result.RowCount) 
		{
			char steam[32], query[256];
			if(GetClientAuthId(client, AuthId_Steam2, steam, sizeof(steam)))
			{
				SQL_FormatQuery(db, query, sizeof(query), "UPDATE `opener_base` SET `available`='0', `last_open`='%i' WHERE `steam`='%s'", GetTime(), steam);
				SQL_FastQuery(db, query);
			}
		}
	}
	else 
		PrintError(error, 920);
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//																							TIMERS																							//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

public Action FallAfterTimer(Handle hTimer, DataPack dp) 
{
	float fPos[3];
	dp.Reset();
	int client = GetClientOfUserId(dp.ReadCell());
	fPos[0] = dp.ReadFloat();
	fPos[1] = dp.ReadFloat();
	fPos[2] = dp.ReadFloat();
	delete dp;
	if(client > 0 && client <= MaxClients)
		hTimers[client][4] = null;

	if(!IsValidHumanClient(client) || !IsValidEntity(iEntCaseData[client][0]))
	{
		if(client > 0 && client <= MaxClients)
			NullClient(client);
		return Plugin_Stop;
	}
	SpawningReward(fPos, client);
	return Plugin_Stop;
}

public Action SubSub(Handle hTimer, DataPack dp)
{
	dp.Reset();
	int a = dp.ReadCell();
	int b = GetClientOfUserId(dp.ReadCell());
	delete dp;
	if(IsValidHumanClient(b))
		OpenSubSub(a, b);
	return Plugin_Continue;
}

public Action Scrolling(Handle hNewTimer, int client) 
{
	client = GetClientOfUserId(client);
	if(!IsValidHumanClient(client) || !IsValidEntity(iEntCaseData[client][0]) || !IsValidEntity(iEntCaseData[client][3]))
	{
		if(client > 0 && client <= MaxClients)
			hTimers[client][2] = null;
		return Plugin_Stop;
	}

	int clr[4];
	float fPos[3];
	clr[0] = clr[1] = clr[2] = GetRandomInt(0,255);
	clr[3] = 255;

	GetEntPropVector(iEntCaseData[client][0], Prop_Data, "m_vecAbsOrigin", fPos);

	if(bCaseOpeningSound) 
		EmitSoundToAll("ui/csgo_ui_crate_item_scroll.wav", iEntCaseData[client][0], SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, fPos);

	SetVariantColor(clr);
	AcceptEntityInput(iEntCaseData[client][3], "color");

	if(bCaseMessagesHint) 
		PrintToHintScrolling(client);

	return Plugin_Continue;
}

public Action SoundOpen(Handle hNewTimer, int client) 
{
	client = GetClientOfUserId(client);
	if(!IsValidHumanClient(client) || !IsValidEntity(iEntCaseData[client][0]))
	{
		if(client > 0 && client <= MaxClients)
			hTimers[client][1] = null;
		return Plugin_Stop;
	}

	if(hTimers[client][2] != INVALID_HANDLE) 
	{
		KillTimer(hTimers[client][2]);
		hTimers[client][2] = null;
	}
	
	if(hTimers[client][1] != INVALID_HANDLE) 
		hTimers[client][1] = null;

	float fPos[3];
	GetEntPropVector(iEntCaseData[client][0], Prop_Data, "m_vecAbsOrigin", fPos);
	if(bCaseOpeningSound) 
		EmitSoundToAll("ui/csgo_ui_crate_display.wav", iEntCaseData[client][0], SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, fPos);
		
	switch(iReward[client]) 
	{
		case 0:
		{
			if(iEntCaseData[client][4] == -1)
				iEntCaseData[client][4] = GetSafeRandomInt(iMinCredits, iMaxCredits);
				
			if(bCaseMessagesHint) 
				PrintHintText(client, "%t", "credits_scroll", sColor[1], iEntCaseData[client][4]);
		}
#if (defined _levelsranks_included_ || defined _fire_players_stats_included)
		case 1:
		{
			if(iEntCaseData[client][4] == -1)
				iEntCaseData[client][4] = GetSafeRandomInt(iMinExp, iMaxExp);
				
			if(bGiveExp) if(bCaseMessagesHint) 
				PrintHintText(client, "%t", "exp_scroll", sColor[1], iEntCaseData[client][4]);
			else if(bCaseMessagesHint) 
				PrintHintText(client, "%t", "credits_scroll", sColor[1], iEntCaseData[client][4]);
		}
#endif
#if defined _vip_core_included
		case 2:
		{
			char buffer[64];
			if(SelectVipGroup(iEntCaseData[client][4]))
			{
				hArrayList.GetString(iEntCaseData[client][4], buffer, sizeof(buffer));
				if(bCaseMessagesHint)
					PrintHintText(client, "%t", "vip_scroll", sColor[1], buffer);
				}
			else 
			{
				iReward[client] = 0;
				iEntCaseData[client][4] = GetSafeRandomInt(iMinCredits, iMaxCredits);
				if(bCaseMessagesHint) 
					PrintHintText(client, "%t", "credits_scroll", sColor[1], iEntCaseData[client][4]);
			}
		}
#endif
	}
	return Plugin_Continue;
}

public Action SpawnReward(Handle hNewTimer, int client) 
{
	client = GetClientOfUserId(client);
	if(client <= 0 || client > MaxClients)
		return Plugin_Stop;
	hTimers[client][0] = null;
	if(!IsValidHumanClient(client) || !IsValidEntity(iEntCaseData[client][1]))
		return Plugin_Stop;

	DispatchKeyValue(iEntCaseData[client][1], "modelscale", "1.0");
	DispatchKeyValue(iEntCaseData[client][1], "rendermode", "0");
	DispatchSpawn(iEntCaseData[client][1]);
	if(!bStartCounter)
	{
		if(gDatabase != null && GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)))
		{
			SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "UPDATE `opener_base` SET `available`='0', `last_open`='%i' WHERE `steam`='%s'", GetTime(), auth);
			SQL_FastQuery(gDatabase, sQuery);
		}
	}
	SDKHook(iEntCaseData[client][1], SDKHook_StartTouch, Hook_ModelStartTouch);
	
	return Plugin_Stop;
}

public Action OnTouchDelete(Handle hNewTimer, int activator) 
{
	activator = GetClientOfUserId(activator);
	if(activator <= 0 || activator > MaxClients)
		return Plugin_Stop;
	hTimers[activator][3] = null;

	float fPos[3];
	bool bCaseValid = IsValidEntity(iEntCaseData[activator][0]);
	if(bCaseValid)
		GetEntPropVector(iEntCaseData[activator][0], Prop_Data, "m_vecAbsOrigin", fPos);
	if(bCaseValid && bKillCaseSound) 
		EmitSoundToAll("weapons/hegrenade/explode3.wav", iEntCaseData[activator][0], SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, fPos);

	if(bCaseValid && bEnableBoom)
	{
		TE_SetupExplosion(fPos, iExplode, 10.0, 1, 0, 275, 160);
		TE_SendToAll();
	}

	KillCaseEntities(activator);
	ResetClientState(activator);
	return Plugin_Stop;
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//																							HELPERS																							//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

void RegCommandsFromKv(const char[] key, ConCmd Callback, const char[] desc, const char[] defcmd)
{
	if(key[0] != '\0')
	{
		char keybuffer[2048], cmds[32][64];
		kv.Rewind();
		kv.GetString(key, keybuffer, sizeof(keybuffer));
		if(keybuffer[0] == '\0')
		{
			RegConsoleCmd(defcmd, Callback, desc);
			return;
		}

		int count = ExplodeString(keybuffer, ";", cmds, sizeof(cmds), sizeof(cmds[]));
		for(int i = 0; i < count; i++) 
		{
			TrimString(cmds[i]);
			if(cmds[i][0] == '\0')
				continue;
			if(cmds[i][0] == '!') 
				ReplaceString(cmds[i], sizeof(cmds[]), "!", "sm_", true);
			RegConsoleCmd(cmds[i], Callback, desc);
		}		
	}
	else 
		RegConsoleCmd(defcmd, Callback, desc);
}

void PrintToHintScrolling(int client) 
{
	int reward = SelectRewardType();
	switch(reward)
	{
		case 0: 
			PrintHintText(client, "%t", "credits_scroll", sColor[0], GetSafeRandomInt(iMinCredits, iMaxCredits));
#if defined _levelsranks_included_ || defined _fire_players_stats_included
		case 1: 
		{
			PrintHintText(client, "%t", "exp_scroll", sColor[0], GetSafeRandomInt(iMinExp, iMaxExp));
		}
#endif
#if defined _vip_core_included
		case 2: 
		{
			int group;
			if(SelectVipGroup(group))
			{
				char buffer[32];
				hArrayList.GetString(group, buffer, sizeof(buffer));
				PrintHintText(client, "%t", "vip_scroll", sColor[0], buffer);			
			}
			else 
				PrintHintText(client, "%t", "credits_scroll", sColor[0], GetSafeRandomInt(iMinCredits, iMaxCredits));
		}
#endif
	}
}

void PrintError(const char[] error, int line)
{
	LogMessage("Query ERROR on line [%i]: %s", line, error);
}

void NullClient(int client) 
{
	if(client <= 0 || client > MaxClients)
		return;

	for(int i = 0; i < 6; i++)
	{
		if(hTimers[client][i] != null)
			KillTimer(hTimers[client][i]);
		hTimers[client][i] = null;
	}

	KillCaseEntities(client);
	ResetClientState(client);
}

void ResetClientState(int client)
{
	if(client <= 0 || client > MaxClients)
		return;

	for(int i = 0;i <= 4; i++) 
		iEntCaseData[client][i] = -1;

	iReward[client] = -1;
	bWarn[client] = false;
	bCaseRequestPending[client] = false;
	bRewardClaimed[client] = false;
}

void KillCaseEntities(int client)
{
	if(client <= 0 || client > MaxClients)
		return;

	for(int i = 1; i <= 4; i++)
	{
		if(IsValidEntity(iEntCaseData[client][i]))
			AcceptEntityInput(iEntCaseData[client][i], "Kill");
	}
	if(IsValidEntity(iEntCaseData[client][0]))
		AcceptEntityInput(iEntCaseData[client][0], "Kill");
}

bool IsValidHumanClient(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client);
}

int GetSafeRandomInt(int min, int max)
{
	if(min < 0)
		min = 0;
	if(max < 0)
		max = 0;
	if(min > max)
	{
		int value = min;
		min = max;
		max = value;
	}
	return GetRandomInt(min, max);
}

int SelectRewardType()
{
	kv.Rewind();
	float credits = kv.GetFloat("_credits");
	if(credits < 0.0)
		credits = 0.0;
	float total = credits;

#if defined _levelsranks_included_ || defined _fire_players_stats_included
	float expChance = bGiveExp ? kv.GetFloat("_exps") : 0.0;
	if(expChance < 0.0)
		expChance = 0.0;
	total += expChance;
#endif
#if defined _vip_core_included
	float vipChance = (bGiveVIP && hArrayList != null && hArrayList.Length > 0) ? kv.GetFloat("_vips") : 0.0;
	if(vipChance < 0.0)
		vipChance = 0.0;
	total += vipChance;
#endif

	if(total <= 0.0)
		return 0;

	float roll = GetRandomFloat(0.0, total);
	if(roll < credits)
		return 0;
	roll -= credits;

#if defined _levelsranks_included_ || defined _fire_players_stats_included
	if(roll < expChance)
		return 1;
	roll -= expChance;
#endif
#if defined _vip_core_included
	if(roll < vipChance)
		return 2;
#endif
	return 0;
}

#if defined _vip_core_included
bool SelectVipGroup(int &group)
{
	group = -1;
	if(hArrayList == null || hArrayList.Length <= 0)
		return false;

	float total = 0.0;
	char buffer[64];
	for(int i = 0; i < hArrayList.Length; i++)
	{
		hArrayList.GetString(i, buffer, sizeof(buffer));
		kv.Rewind();
		if(kv.JumpToKey(buffer))
		{
			float chance = kv.GetFloat("chance");
			if(chance > 0.0)
				total += chance;
		}
	}
	if(total <= 0.0)
		return false;

	float roll = GetRandomFloat(0.0, total);
	for(int i = 0; i < hArrayList.Length; i++)
	{
		hArrayList.GetString(i, buffer, sizeof(buffer));
		kv.Rewind();
		if(!kv.JumpToKey(buffer))
			continue;
		float chance = kv.GetFloat("chance");
		if(chance <= 0.0)
			continue;
		if(roll < chance)
		{
			group = i;
			return true;
		}
		roll -= chance;
	}
	return false;
}
#endif

void SpawningReward(float fPos[3], int client) 
{
	if(!IsValidHumanClient(client) || !IsValidEntity(iEntCaseData[client][0]))
	{
		if(client > 0 && client <= MaxClients)
			NullClient(client);
		return;
	}

	SetVariantString("open");
	AcceptEntityInput(iEntCaseData[client][0], "SetAnimation", -1, -1, -1);
	DispatchKeyValueFloat(iEntCaseData[client][0], "playbackrate", fOpenSpeedAnim); 
	
	iReward[client] = SelectRewardType();
	int R; // Не знаю под чем я это писал :/
#if defined _vip_core_included
	if(iReward[client] == 2 && (hArrayList == null || hArrayList.Length <= 0))
		iReward[client] = 0;
#endif
	R = iReward[client];
	if(R < 0)
		iReward[client] = 0;

	if(IsValidHumanClient(client)) 
	{
		char clr[20], sTargetName[32], sBufer[70];
		iEntCaseData[client][1] = CreateEntityByName("prop_dynamic");
		if(!IsValidEntity(iEntCaseData[client][1]))
		{
			KillCaseEntities(client);
			ResetClientState(client);
			return;
		}
		Format(sTargetName, sizeof(sTargetName), "Reward_%i", iEntCaseData[client][1]);
		DispatchKeyValue(iEntCaseData[client][1], "targetname", sTargetName);
		DispatchKeyValueVector(iEntCaseData[client][1], "origin", fPos);
		DispatchKeyValue(iEntCaseData[client][1], "modelscale", "0.1");
		DispatchKeyValue(iEntCaseData[client][1], "rendermode", "10");
		switch(iReward[client]) 
		{
			case 0: 
				DispatchKeyValue(iEntCaseData[client][1], "model", sRewardMDL[iReward[client]]);
#if (defined _levelsranks_included_ || defined _fire_players_stats_included)
			case 1: 
			{
				if(bGiveExp) 
					DispatchKeyValue(iEntCaseData[client][1], "model", sRewardMDL[iReward[client]]);				
				else 
					DispatchKeyValue(iEntCaseData[client][1], "model", sRewardMDL[0]);	
			}
#endif
#if defined _vip_core_included
			case 2: 
			{
				if(bGiveVIP) 
					DispatchKeyValue(iEntCaseData[client][1], "model", sRewardMDL[iReward[client]]);				
				else 
					DispatchKeyValue(iEntCaseData[client][1], "model", sRewardMDL[0]);
			}
#endif
		}
		SetVariantString(sTargetName);

		DispatchSpawn(iEntCaseData[client][1]);
		SetEntProp(iEntCaseData[client][1], Prop_Send, "m_usSolidFlags", 8);
		SetEntProp(iEntCaseData[client][1], Prop_Send, "m_CollisionGroup", 1);
		Format(sBufer, sizeof(sBufer), "OnUser1 !self:kill::999.0:-1");
		SetVariantString(sBufer);
		AcceptEntityInput(iEntCaseData[client][1], "AddOutput");
		AcceptEntityInput(iEntCaseData[client][1], "FireUser1");

		iEntCaseData[client][2] = CreateEntityByName("func_rotating", -1);
		if(!IsValidEntity(iEntCaseData[client][2]))
		{
			KillCaseEntities(client);
			ResetClientState(client);
			return;
		}

		DispatchKeyValueVector(iEntCaseData[client][2], "origin", fPos);
		DispatchKeyValue(iEntCaseData[client][2], "targetname", sTargetName);
		DispatchKeyValue(iEntCaseData[client][2], "maxspeed", "50");
		DispatchKeyValue(iEntCaseData[client][2], "friction", "0");
		DispatchKeyValue(iEntCaseData[client][2], "dmg", "0");
		DispatchKeyValue(iEntCaseData[client][2], "solid", "6");
		DispatchKeyValue(iEntCaseData[client][2], "spawnflags", "64");
		DispatchSpawn(iEntCaseData[client][2]);

		SetVariantString("!activator");

		AcceptEntityInput(iEntCaseData[client][1], "SetParent", iEntCaseData[client][2], iEntCaseData[client][2]);
		AcceptEntityInput(iEntCaseData[client][2], "Start", -1, -1);
		SetEntProp(iEntCaseData[client][2], Prop_Send, "m_CollisionGroup", 1);
		Format(sBufer, sizeof(sBufer), "OnUser1 !self:kill::999.0:-1");
		SetVariantString(sBufer);
		AcceptEntityInput(iEntCaseData[client][2], "AddOutput");
		AcceptEntityInput(iEntCaseData[client][2], "FireUser1");
		SetEntPropEnt(iEntCaseData[client][1], Prop_Send, "m_hEffectEntity", iEntCaseData[client][2]);

		Format(clr, sizeof(clr), "%i %i %i", GetRandomInt(0,255),GetRandomInt(0,255),GetRandomInt(0,255));

		iEntCaseData[client][3] = CreateEntityByName("env_sprite");
		if(!IsValidEntity(iEntCaseData[client][3]))
		{
			KillCaseEntities(client);
			ResetClientState(client);
			return;
		}

		DispatchKeyValue(iEntCaseData[client][3], "rendermode", "5");
		DispatchKeyValue(iEntCaseData[client][3], "rendercolor", clr);
		DispatchKeyValue(iEntCaseData[client][3], "renderamt", "255");
		DispatchKeyValue(iEntCaseData[client][3], "model", "sprites/glow01.spr");
		DispatchKeyValueVector(iEntCaseData[client][3], "origin", fPos);
		DispatchSpawn(iEntCaseData[client][3]);
		
		SetVariantString("!activator");
		AcceptEntityInput(iEntCaseData[client][3], "SetParent", iEntCaseData[client][1]);

		hTimers[client][2] = CreateTimer(fOpenSpeedScroll, Scrolling, GetClientUserId(client), TIMER_REPEAT);
		hTimers[client][0] = CreateTimer(fOpenSpeed, SpawnReward, GetClientUserId(client));
		hTimers[client][1] = CreateTimer(fOpenSpeed, SoundOpen, GetClientUserId(client));
	}
}

void AddDataToDB(int client) 
{
	if(!IsValidHumanClient(client) || gDatabase == null)
		return;

	GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
	SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "SELECT `steam` FROM `opener_base` WHERE `steam`='%s'", auth);
	gDatabase.Query(SQLAddClientData, sQuery, GetClientUserId(client), DBPrio_High);
}

float[] SpawnCase(int iClient, float fPos[3], float fAng[3]) 
{
	char sTargetName[64];

	fAng[x] = 0.0;
	fAng[y] += 90.0;

	iEntCaseData[iClient][0] = CreateEntityByName("prop_dynamic");
	if(!IsValidEntity(iEntCaseData[iClient][0]))
	{
		ResetClientState(iClient);
		return fPos;
	}

	Format(sTargetName, sizeof(sTargetName), "case_%i", iClient);
	DispatchKeyValue(iEntCaseData[iClient][0], "targetname", sTargetName);

	DispatchKeyValue(iEntCaseData[iClient][0], "model", sCrates[GetRandomInt(0, sizeof(sCrates)-1)]);
	DispatchKeyValueVector(iEntCaseData[iClient][0], "origin", fPos);
	DispatchKeyValueVector(iEntCaseData[iClient][0], "angles", fAng);

	DispatchSpawn(iEntCaseData[iClient][0]);

	SetVariantString("fall");
	AcceptEntityInput(iEntCaseData[iClient][0], "SetAnimation", -1, -1, -1);
	DispatchKeyValueFloat(iEntCaseData[iClient][0], "playbackrate", 1.1);
	EmitSoundToAll("ui/panorama/case_drop_01.wav", iEntCaseData[iClient][0], SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, fPos);
	
	fPos[z] += 20.0;
	
	return fPos;
}

bool TRFilter(int client, int mask) 
{ 
	return client > 0 && client <= MaxClients ? false : true;
}

void CreateTableDB() 
{
	char Query[512];
	SQL_FormatQuery(gDatabase, Query, sizeof(Query), "CREATE TABLE IF NOT EXISTS `opener_base` (\
														`steam` VARCHAR(24) NOT NULL PRIMARY KEY, \
														`last_open` INTEGER(20) NOT NULL, \
														`available` INTEGER(8) NOT NULL, \
														`name` VARCHAR(64) NOT NULL, \
														`cases_opened` INTEGER(20) NOT NULL, \
														`vips_total` INTEGER(20) NOT NULL, \
														`exp_total` INTEGER(20) NOT NULL, \
														`credits_total` INTEGER(20) NOT NULL)");
	SQL_TQuery(gDatabase, SQLTQueryCallBack, Query);
}

void PreCacheFiles() 
{
	for(int i = 0; i < sizeof(sCrates); i++)
		PrecacheModel(sCrates[i]);

	for(int i = 0; i < sizeof(sRewardMDL); i++)
		PrecacheModel(sRewardMDL[i]);

	PrecacheModel("sprites/glow01.spr", true);
	iExplode = PrecacheModel("materials/sprites/zerogxplode.vmt", true);
	g_HaloSprite = PrecacheModel("sprites/halo.vmt", true);
	g_BeamSprite = PrecacheModel("sprites/laserbeam.vmt", true);
	PrecacheSound("ui/csgo_ui_crate_item_scroll.wav", true);
	PrecacheSound("ui/csgo_ui_crate_display.wav", true);
	PrecacheSound("weapons/hegrenade/explode3.wav", true);
	PrecacheSound("ui/panorama/case_drop_01.wav", true);
	PrecacheSound("buttons/blip1.wav", true);
	PrecacheSound("ui/panorama/music_equip_01.wav", true);
}

void UpdateRating(int type, int client, int value)
{
	if(!IsValidHumanClient(client) || gDatabase == null || !GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)))
		return;

	if(type == vip) 
		SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "UPDATE `opener_base` SET `cases_opened`=`cases_opened`+1, `vips_total`=	`vips_total`+1 		WHERE `steam`='%s'", auth);
	else if(type == exp) 
		SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "UPDATE `opener_base` SET `cases_opened`=`cases_opened`+1, `exp_total`=		`exp_total`+%i 		WHERE `steam`='%s'", value, auth);
	else if(type == crd) 
		SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "UPDATE `opener_base` SET `cases_opened`=`cases_opened`+1, `credits_total`=	`credits_total`+%i 	WHERE `steam`='%s'", value, auth);
	else
		return;
		
	gDatabase.Query(UpdateSQLRateing, sQuery);
}

void OpenTopSub(int type, int client)
{
	DataPack dp = CreateDataPack();
	CreateTimer(0.1, SubSub, dp);
	dp.WriteCell(type);
	dp.WriteCell(GetClientUserId(client));
}

void OpenSubSub(int type, int client)
{
	if(!IsValidHumanClient(client))
		return;

	char buff[256];
	
	Panel hPanel = CreatePanel();
	if(type == open) 
		Format(buff, sizeof(buff), "%t", "top_cases");
	else if (type == vip) 
		Format(buff, sizeof(buff), "%t", "top_vip");
	else if (type == crd) 
		Format(buff, sizeof(buff), "%t", "top_credits");
	else if (type == exp) 
		Format(buff, sizeof(buff), "%t", "top_exp");
	hPanel.SetTitle(buff);

	hPanel.DrawItem("", ITEMDRAW_SPACER);
	for(int i = 0; i < aRating[0].Length; i++)
	{
		aRating[0].GetString(i ,buff, sizeof(buff));
		Format(buff, sizeof(buff), "%i. %s - %i", i+1, buff, aRating[1].Get(i));
		hPanel.DrawText(buff);
	}
	hPanel.DrawItem("", ITEMDRAW_SPACER);
	Format(buff, sizeof(buff), "%t", "BackPanel");
	hPanel.DrawItem(buff, ITEMDRAW_CONTROL);
	Format(buff, sizeof(buff), "%t", "ExitPanel");
	hPanel.DrawItem(buff, ITEMDRAW_CONTROL);
	
	hPanel.Send(client, MenuHandlers, MENU_TIME_FOREVER);
}

void OpenRatingMainCmdMenu(int client)
{
	char buff[256];
	Menu hMenu = CreateMenu(RatingMenu);
	Format(buff, sizeof(buff), "%t\n", "Rating_Menu");
	hMenu.SetTitle(buff);
	Format(buff, sizeof(buff), "%t", "top_cases");
	hMenu.AddItem("0", buff);
	Format(buff, sizeof(buff), "%t", "top_vip");
	hMenu.AddItem("1", buff);
	Format(buff, sizeof(buff), "%t", "top_credits");
	hMenu.AddItem("2", buff);
	Format(buff, sizeof(buff), "%t", "top_exp");
	hMenu.AddItem("3", buff);
	
	hMenu.ExitButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

void GetRatingNow(int filter, int client)
{
	if(!IsValidHumanClient(client) || gDatabase == null)
		return;

	if(filter == open) 
		SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "SELECT `name`, `cases_opened` FROM `opener_base` ORDER BY `cases_opened` DESC LIMIT 10");
	else if(filter == vip) 
		SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "SELECT `name`, `vips_total` FROM `opener_base` ORDER BY `vips_total` DESC LIMIT 10");
	else if(filter == crd) 
		SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "SELECT `name`, `credits_total` FROM `opener_base` ORDER BY `credits_total` DESC LIMIT 10");
	else if(filter == exp) 
		SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "SELECT `name`, `exp_total` FROM `opener_base` ORDER BY `exp_total` DESC LIMIT 10");
	else
		return;
		
	gDatabase.Query(Get10Rating, sQuery, GetClientUserId(client));
}
