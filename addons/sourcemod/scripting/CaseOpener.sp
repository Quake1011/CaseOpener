#pragma tabsize 0
#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <csgo_colors>
#include <shop>
#tryinclude <vip_core>
#tryinclude <lvl_ranks>
#tryinclude <FirePlayersStats>

#if defined _vip_core_included
	bool bGiveVIP;
	ConVar g_hGiveVIP;
	ArrayList hArrayList;
	#warning "VIP LOADED"
#else
	#warning "VIP NOT LOADED"
#endif

#if defined _levelsranks_included_ || defined _fire_players_stats_included
#if defined _levelsranks_included_
	#warning "LR LOADED"
#endif
#if defined _fire_players_stats_included
	#warning "FPS LOADED"
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
	#warning "LR/FPS NOT LOADED"  
#endif

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
	g_BeamSprite,
	iClientParticle[MAXPLAYERS+1];

bool 
	bEnableBoom, 
	bWarn[MAXPLAYERS+1],
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
	bStartCounter,
	bLate = false;

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

#include "CaseOpener/files.sp"

static char sLog[PLATFORM_MAX_PATH];

static char sColor[][] = {"FF0000", "00FF00"};

enum {x = 0,y,z};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) 
{
	if(GetEngineVersion() != Engine_CSGO) 
	{
		SetFailState("[CASEOPENER] Error loading plugin: Only for CS:GO");
		return APLRes_Failure;
	}

	if(error[0]) 
	{
		SetFailState("[CASEOPENER] Error loading plugin: %s", error);
		return APLRes_Failure;
	}
	if(late) bLate = true;
	return APLRes_Success;
}

public Plugin myinfo = 
{
	name = "Case Opener",
	author = "Quake1011",
	description = "Spawning case with reward",
	version = "1.3.1",
	url = "https://github.com/Quake1011/"
}

public void OnPluginStart() 
{
	if(!SQL_CheckConfig("case_opener")) SetFailState("[CASEOPENER] Section \"case_opener\" is not found in databases.cfg");

	Database.Connect(SQLConnectGlobalDB, "case_opener");

	HookEvent("round_start", EventRoundStart, EventHookMode_Post);

	for(int i = 1;i <= MaxClients; i++) 
		NullClient(i);

	LoadTranslations("CaseOpener.phrases.txt");
	
#if defined _vip_core_included
	HookConVarChange((g_hGiveVIP =                  	CreateConVar("sm_opener_give_vip","1","Give the VIP Group [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bGiveVIP = g_hGiveVIP.BoolValue;
#endif
#if defined _levelsranks_included_ || defined _fire_players_stats_included
	HookConVarChange((g_hGiveExp =                  	CreateConVar("sm_opener_give_exp","1","Give the experience [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bGiveExp = g_hGiveExp.BoolValue;

	HookConVarChange((g_hMinExp =                       CreateConVar("sm_opener_min_exp","400","Minimum number of received experience.",0)), OnConvarChanged);
	iMinExp = g_hMinExp.IntValue;

	HookConVarChange((g_hMaxExp =                       CreateConVar("sm_opener_max_exp","1000","Maximum number of received experience.",0)), OnConvarChanged);
	iMaxExp = g_hMaxExp.IntValue;
#endif
	HookConVarChange((g_hResetCounter =                 CreateConVar("sm_opener_reset_counter","1","Allow admins to reset the counter [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bResetCounter = g_hResetCounter.BoolValue;

	HookConVarChange((g_hDropLog =                      CreateConVar("sm_opener_log","1","Enable logging case drops [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bDropLog = g_hDropLog.BoolValue;

	HookConVarChange((g_hPrintAll =                     CreateConVar("sm_opener_print_all","1","Print for all when player items drops [1 - For all | 0 - For self]. When enabled sm_opener_case_messages",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bPrintAll = g_hPrintAll.BoolValue;

	HookConVarChange((g_hTimeBeforeNextOpen =           CreateConVar("sm_opener_time_before_next_open",  "604800", "Time between case openings in seconds.",0)), OnConvarChanged);
	iTimeBeforeNextOpen = g_hTimeBeforeNextOpen.IntValue;

	HookConVarChange((g_hOpenSpeedAnim =                CreateConVar("sm_opener_open_anim_speed","0.1","The animation speed of the case. It is configured together with sm_opener_open_speed.",0)), OnConvarChanged);
	fOpenSpeedAnim = g_hOpenSpeedAnim.FloatValue;

	HookConVarChange((g_hOpenSpeed =                    CreateConVar("sm_opener_open_speed","11.5","Case opening speed. It is configured together with sm_opener_open_anim_speed.",0)), OnConvarChanged);
	fOpenSpeed = g_hOpenSpeed.FloatValue;

	HookConVarChange((g_hOpenSpeedScroll =              CreateConVar("sm_opener_open_speed_scroll","0.25","Speed of scrolls.",0)), OnConvarChanged);
	fOpenSpeedScroll = g_hOpenSpeedScroll.FloatValue;

	HookConVarChange((g_hOutputBeam =                   CreateConVar("sm_opener_open_output_beam","1","Display the maximum spawn radius of the case [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bOutputBeam = g_hOutputBeam.BoolValue;

	HookConVarChange((g_hMinCredits =                   CreateConVar("sm_opener_min_credits","500","Minimum number of credits received.",0)), OnConvarChanged);
	iMinCredits = g_hMinCredits.IntValue;

	HookConVarChange((g_hMaxCredits =                   CreateConVar("sm_opener_max_credits","2500","Maximum number of credits received.",0)), OnConvarChanged);
	iMaxCredits = g_hMaxCredits.IntValue;

	HookConVarChange((g_hMaxPositionValue =             CreateConVar("sm_opener_max_position_value","3","The maximum distance to case spawn. Depends by sm_opener_max_position",0)), OnConvarChanged);
	iMaxPositionValue = g_hMaxPositionValue.IntValue;

	HookConVarChange((g_hCaseKillTimer =                CreateConVar("sm_opener_case_kill_time","3","The time after which the case will disappear in seconds.",0)), OnConvarChanged);     
	iCaseKillTimer = g_hCaseKillTimer.IntValue;

	HookConVarChange((g_hSamePlat =                     CreateConVar("sm_opener_same_plat","1","Spawn the case on the same plane with the owner [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bSamePlat = g_hSamePlat.BoolValue;

	HookConVarChange((g_hKillCaseSound =                CreateConVar("sm_opener_kill_case_sound","1","Turn on the sound of the case disappearing [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bKillCaseSound = g_hKillCaseSound.BoolValue;

	HookConVarChange((g_hCaseOpeningSound =             CreateConVar("sm_opener_case_opening_sound","1","Enable case opening sounds [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bCaseOpeningSound = g_hCaseOpeningSound.BoolValue;

	HookConVarChange((g_hCaseMessages =                 CreateConVar("sm_opener_case_messages","1","Enable chat messages [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bCaseMessages = g_hCaseMessages.BoolValue;

	HookConVarChange((g_hCaseMessagesHint =             CreateConVar("sm_opener_case_messages_hint","1","Enable messages in the hint [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bCaseMessagesHint = g_hCaseMessagesHint.BoolValue;

	HookConVarChange((g_hCaseAccess =                   CreateConVar("sm_opener_case_access","0","Access only for admins [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bCaseAccess = g_hCaseAccess.BoolValue;

	HookConVarChange((g_hMaxPosition =                  CreateConVar("sm_opener_max_position","1","Restrict distance for spawn case [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bMaxPosition = g_hMaxPosition.BoolValue;

	HookConVarChange((g_hEnableBoom =                   CreateConVar("sm_opener_no_boom","1","Disable the explosion when removing the case [1 - Yes | 0 - No]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bEnableBoom = g_hEnableBoom.BoolValue;

	HookConVarChange((g_hStartCounter =                 CreateConVar("sm_opener_start_counter","1","To start counter [1 - after touch, 0 - after open]",0, true, 0.0, true, 1.0)), OnConvarChanged);
	bStartCounter = g_hStartCounter.BoolValue;
	
	AutoExecConfig(true, "CaseOpener");
	
	char sPath[PLATFORM_MAX_PATH];	
	hArrayList = new ArrayList(ByteCountToCells(64));
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/Opener.ini");
	kv = CreateKeyValues("Settings");
	
	if(kv.ImportFromFile(sPath)) 
	{
		char buffer[64];
		float fChance;
		kv.Rewind();
		kv.GotoFirstSubKey();
		do{
			kv.GetSectionName(buffer, sizeof(buffer));
			fChance = kv.GetFloat("chance");
			LogMessage("VIP founded in Opener.ini: %s | chance: %.3f", buffer, fChance);
			hArrayList.PushString(buffer);
		} while(kv.GotoNextKey())
		
		RegCommandsFromKv("cmds_case", Command_Case, "Spawn case in view direction point");
		RegCommandsFromKv("cmds_reset_me", CommandResetCounter, "Fast reset self counter");
		RegCommandsFromKv("cmds_reset_all", CommandResetFor, "List of players for reset anybody counter");
	}
	
	if(bDropLog == true)
	{
		BuildPath(Path_SM, sLog, sizeof(sLog), "logs/CaseOpener.log");
		File hFile = OpenFile(sLog, "a+");
		CloseHandle(hFile);
	}
	
	if(bLate) return;
}

public Action CommandResetFor(int client, int args)
{
	if(bResetCounter)
	{
		AdminId AdminID = GetUserAdmin(client);
		if(AdminID != INVALID_ADMIN_ID)
		{
			Menu hMenu = CreateMenu(SelectPlayer);
			hMenu.SetTitle("Select player");
			char temp[2][256];
			for(int i = 1;i <= MaxClients; i++)
			{
				if(IsClientInGame(i) && !IsFakeClient(i) && !IsClientSourceTV(i))
				{
					Format(temp[0], 256, "%i", i);
					Format(temp[1], 256, "%N(%i)", i, GetClientUserId(i))
					hMenu.AddItem(temp[0], temp[1]);
				}               
			}
			hMenu.ExitButton = true;
			hMenu.Display(client, 0);			
		}
	}
	else 
	{
		if(bCaseMessages) CGOPrintToChat(client, "%t%t", "prefix", "not_works");
		EmitSoundToClient(client, "buttons/blip1.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR);
	}
	return Plugin_Handled;
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
			int idx = StringToInt(tmp);
			char sQuery[256], auth[22];
			GetClientAuthId(idx, AuthId_Steam2, auth, sizeof(auth));

			SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "SELECT * FROM `opener_base` WHERE `steam`='%s'", auth);
			gDatabase.Query(SQLResetCounterCB, sQuery, idx, DBPrio_High);

			Menu hMenu = CreateMenu(SelectPlayer);
			hMenu.SetTitle("Select player");
			char temp[2][256];
			for(int i = 1;i <= MaxClients; i++)
			{
				if(IsClientInGame(i) && !IsFakeClient(i) && !IsClientSourceTV(i))
				{
					Format(temp[0], 256, "%i", i);
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

public void SQLResetCounterCB(Database db, DBResultSet result, const char[] error, int client)
{
	if(result != INVALID_HANDLE && !error[0])
	{
		if(result.HasResults) 
		{
			if(result.RowCount > 0) 
			{
				char sQuery[256], auth[22];
				GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
				
				SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "UPDATE `opener_base` SET `available`='1', `last_open`='0' WHERE `steam`='%s'", auth);
				SQL_FastQuery(gDatabase, sQuery);
				
				if(bCaseMessages) CGOPrintToChat(client, "%t%t", "prefix", "counter_reseted");
			}
		}
	}
    else PrintError(error);
}

public void SQLConnectGlobalDB(Database db, const char[] error, any data) 
{
	if (db == null || error[0]) SetFailState("[CASEOPENER] Problem with connection to Database");

	LogMessage("Connection is READY!");
	gDatabase = db;
	CreateTableDB();
}

public void SQLTQueryCallBack(Handle owner, Handle hndl, const char[] error, any data) 
{
	if(!error[0] && hndl != INVALID_HANDLE) LogMessage("[CASEOPENER] The table has been created");
	else 
	{
		SetFailState("[CASEOPENER] Cant create a table \"opener_base\"");
		LogError(error);
	}
}

public void OnConvarChanged(ConVar convar, const char[] oldValue, const char[] newValue) 
{
	if(convar != INVALID_HANDLE) 
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
		else if(convar == g_hEnableBoom) bEnableBoom = convar.BoolValue;
		else if(convar == g_hStartCounter) bStartCounter = convar.BoolValue;
	}
}

public void OnMapStart() 
{
	for(int i = 0;i < sizeof(sDownloadPaths); i++) 
		AddFileToDownloadsTable(sDownloadPaths[i]);	

	for(int i = 0;i < sizeof(downloadparticles); i++) 
		AddFileToDownloadsTable(downloadparticles[i]);

	for(int i = 0;i < sizeof(materials); i++) 
		AddFileToDownloadsTable(materials[i]);		
	
	PreCacheFiles();
}

public void OnClientPostAdminCheck(int client) 
{
	if(!IsFakeClient(client)) 
	{
		AddDataToDB(client);
		for(int i = 0;i <= 4; i++) 
			iEntCaseData[client][i] = -1;		
	}
}

public void SQLAddClientData(Database db, DBResultSet result, const char[] error, int client)
{
	if(result != INVALID_HANDLE && !error[0])
	{
		if(result.HasResults) 
		{
			if(result.RowCount == 0) 
			{
				char sQuery[256], auth[22];
				GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
				
				SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "INSERT INTO `opener_base` (`steam`, `last_open`, `available`) VALUES ('%s', '0', 1)", auth);
				SQL_FastQuery(gDatabase, sQuery);
				
				LogMessage("[CASEOPENER] The player has been added to the database");
			}
			else LogMessage("[CASEOPENER] The player %N is already in the database", client);
		}
	}
	else  SetFailState("[CASEOPENER] Error adding player %N data", client);
}

public void EventRoundStart(Event hEvent, const char[] sEvent, bool bdb) 
{
	for(int i = 1; i <= MaxClients; i++) 
		if(IsClientInGame(i) && !IsFakeClient(i)) NullClient(i);
}

public void OnClientDisconnect(int client) 
{
	if(!IsFakeClient(client)) 
	{
		NullClient(client);
		for(int edict = 0;edict <= 4; edict++) 
			if(iEntCaseData[client][edict] != -1) AcceptEntityInput(iEntCaseData[client][edict] ,"kill");		
	}
}

public Action CommandResetCounter(int client, int args) 
{
	if(bResetCounter) 
	{
		AdminId AdminID = GetUserAdmin(client);
		if(AdminID != INVALID_ADMIN_ID)
		{
			char sQuery[256], auth[22];
			GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
			
			SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "SELECT * FROM `opener_base` WHERE `steam`='%s'", auth);
			gDatabase.Query(SQLResetedCounterCB, sQuery, client, DBPrio_High);			
		}
	}
	else 
	{
		if(bCaseMessages) CGOPrintToChat(client, "%t%t", "prefix", "not_works");
		EmitSoundToClient(client, "buttons/blip1.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR);
	}
	return Plugin_Handled;
}

public void SQLResetedCounterCB(Database db, DBResultSet result, const char[] error, int client)
{
	if(result != INVALID_HANDLE && !error[0])
	{
		if(result.HasResults) 
		{
			if(result.RowCount > 0) 
			{
				char sQuery[256], auth[22];
				GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
				
				SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "UPDATE `opener_base` SET `available`='1', `last_open`='0' WHERE `steam`='%s'", auth);
				SQL_FastQuery(gDatabase, sQuery);
				
				if(bCaseMessages) CGOPrintToChat(client, "%t%t", "prefix", "counter_reseted");
			}
		}
	}
    else PrintError(error);
}

public Action Command_Case(int client, int args) 
{
	if(IsPlayerAlive(client)) 
	{
		char auth[22], sQuery[256];
		GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
		SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "SELECT * FROM `opener_base` WHERE `steam`='%s'", auth);
		gDatabase.Query(SQLCheckTimeStatusCaseClient, sQuery, client, DBPrio_High);
		SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "SELECT * FROM `opener_base` WHERE `steam`='%s' AND `available`='1'", auth);
		gDatabase.Query(SQLCreatingCaseQuery, sQuery, client, DBPrio_High);
	}
	else 
	{
		if(bCaseMessages) CGOPrintToChat(client, "%t%t", "prefix", "be_alive");
		EmitSoundToClient(client, "buttons/blip1.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR);
	}
	return Plugin_Handled;
}

public void SQLCreatingCaseQuery(Database db, DBResultSet result, const char[] error, int client)
{
	if(result != INVALID_HANDLE && !error[0])
	{
		if(result.HasResults) 
		{
			if(result.RowCount > 0)
			{
				if(iEntCaseData[client][0] == -1 && iEntCaseData[client][1] == -1 && iEntCaseData[client][2] == -1 && iEntCaseData[client][3] == -1 && iEntCaseData[client][4] == -1) 
				{
					if(bCaseAccess) 
					{
						AdminId AdminID = GetUserAdmin(client);
						if(AdminID == INVALID_ADMIN_ID) 
						{
							if(bCaseMessages) CGOPrintToChat(client, "%t%t", "prefix", "not_admin");
							EmitSoundToClient(client, "buttons/blip1.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR);
							return;
						}
					}
					if(!IsFakeClient(client)) 
					{
						float fOrig[3], fAng[3], fEndOfTrace[3];
						GetClientEyePosition(client, fOrig);
						GetClientEyeAngles(client, fAng);
						Handle hTrace = TR_TraceRayFilterEx(fOrig, fAng, CONTENTS_SOLID, RayType_Infinite, TRFilter, client);
						if(TR_DidHit(hTrace) && hTrace != INVALID_HANDLE) 
						{
							float fClientOrigin[3];
							TR_GetEndPosition(fEndOfTrace, hTrace);
							GetClientAbsOrigin(client, fClientOrigin);
							if(fEndOfTrace[z] - fClientOrigin[z] >= 5.0 || fClientOrigin[z] - fEndOfTrace[z] <= -5.0 && bSamePlat)  
							{
								if(bCaseMessages) CGOPrintToChat(client, "%t%t", "prefix", "same_level_case");
							}
							else if(GetVectorDistance(fClientOrigin, fEndOfTrace) > float(iMaxPositionValue * 100) && bMaxPosition) 
							{
								if(bCaseMessages) CGOPrintToChat(client, "%t%t", "prefix", "too_longer", iMaxPositionValue);
								if(bOutputBeam) 
								{
									float fDist = float(iMaxPositionValue * 100);
									TE_SetupBeamRingPoint(fClientOrigin, 0.0, fDist * 2, g_BeamSprite, g_HaloSprite, 0, 660, 1.0, 2.0, 0.0, {255, 255, 0, 255}, 1000, 0);  
									TE_SendToClient(client);                                      
								}
								EmitSoundToClient(client, "buttons/blip1.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR);
							}
							else 
							{
								DataPack dp = CreateDataPack();
								float fPosit[3]; 
								fPosit = SpawnCase(client, fEndOfTrace, fAng);
								hTimers[client][4] = CreateTimer(1.4, FallAfterTimer, dp);
								dp.WriteCell(client);
								dp.WriteFloat(fPosit[0]);
								dp.WriteFloat(fPosit[1]);
								dp.WriteFloat(fPosit[2]);
							}
						}
						delete hTrace;
					}
				}
				else 
				{
					if(bCaseMessages) CGOPrintToChat(client, "%t%t", "prefix", "existing_case");
					EmitSoundToClient(client, "buttons/blip1.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR);
				}
			}
			else
			{
				char auth[22], sQuery[256];
				GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
				
				SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "SELECT * FROM `opener_base` WHERE `steam`='%s'", auth);
				gDatabase.Query(SQLTCheckStatusForTime, sQuery, client, DBPrio_High);
			}
		}
	}
    else PrintError(error);
}

public void SQLTCheckStatusForTime(Database db, DBResultSet result, const char[] error, int client)
{
	if(result != INVALID_HANDLE && !error[0])
	{
		if(result.HasResults) 
		{
			if(result.RowCount > 0) 
			{
				result.FetchRow();
				int time = (result.FetchInt(1) + iTimeBeforeNextOpen) - GetTime();
				if(time >= 0) CGOPrintToChat(client, "%t%t", "prefix", "wait_next_case", time/3600/24, time/3600%24, time/60%60, time%60);
				EmitSoundToClient(client, "buttons/blip1.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR);
				LogMessage("[CASEOPENER] The player %N trying to use !case command but already has active block after opening", client);
			}
		}		
	}
    else PrintError(error);
}

public void SQLCheckTimeStatusCaseClient(Database db, DBResultSet result, const char[] error, int client)
{
	if(result != INVALID_HANDLE && !error[0])
	{
		if(result.HasResults)
		{
			if(result.RowCount > 0) 
			{
				result.FetchRow();
				if((result.FetchInt(1) + iTimeBeforeNextOpen) <= GetTime()) 
				{
					char auth[22], sQuery[256];
					result.FetchString(0, auth, sizeof(auth));
					
					SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "UPDATE `opener_base` SET `available`='1' WHERE `steam`='%s'", auth);
					SQL_FastQuery(gDatabase, sQuery);
				}
			}
		}
	}
    else PrintError(error);
}

public Action FallAfterTimer(Handle hTimer, Handle dp) 
{
	float fPos[3];
	
	DataPack hPack = view_as<DataPack>(dp);
	hPack.Reset();
	int client = hPack.ReadCell();
	fPos[0] = hPack.ReadFloat();
	fPos[1] = hPack.ReadFloat();
	fPos[2] = hPack.ReadFloat();
	delete hPack;
	
	SpawningReward(fPos, client);
	
	return Plugin_Continue;
}

public Action Scrolling(Handle hNewTimer, int client) 
{
	int clr[4];
	float fPos[3];
	clr[0] = GetRandomInt(0,255);
	clr[1] = GetRandomInt(0,255);
	clr[2] = GetRandomInt(0,255);
	clr[3] = 255;

	GetEntPropVector(iEntCaseData[client][0], Prop_Data, "m_vecAbsOrigin", fPos);

	if(bCaseOpeningSound) EmitSoundToAll("ui/csgo_ui_crate_item_scroll.wav", iEntCaseData[client][0], SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, fPos);

	SetVariantColor(clr);
	AcceptEntityInput(iEntCaseData[client][3], "color");

	if(bCaseMessagesHint) PrintToHintScrolling(client);

	return Plugin_Continue;
}

public Action SoundOpen(Handle hNewTimer, int client) 
{
	if(hTimers[client][2] != INVALID_HANDLE) 
	{
		KillTimer(hTimers[client][2]);
		hTimers[client][2] = null;
	}

	if(hTimers[client][1] != INVALID_HANDLE) hTimers[client][1] = null;

	float fPos[3];
	GetEntPropVector(iEntCaseData[client][0], Prop_Data, "m_vecAbsOrigin", fPos);
	if(bCaseOpeningSound) EmitSoundToAll("ui/csgo_ui_crate_display.wav", iEntCaseData[client][0], SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, fPos);
	switch(iReward[client]) 
	{
		case 0: 
		{
			while(iEntCaseData[client][4] == -1) iEntCaseData[client][4] = GetRandomInt(iMinCredits,iMaxCredits);
			if(bCaseMessagesHint) PrintHintText(client, "%t", "credits_scroll", sColor[1], iEntCaseData[client][4]);
		}
#if (defined _levelsranks_included_ || defined _fire_players_stats_included)
		case 1: 
		{
			while(iEntCaseData[client][4] == -1) iEntCaseData[client][4] = GetRandomInt(iMinExp,iMaxExp);
			if(bGiveExp) if(bCaseMessagesHint) PrintHintText(client, "%t", "exp_scroll", sColor[1], iEntCaseData[client][4]);                
			else if(bCaseMessagesHint) PrintHintText(client, "%t", "credits_scroll", sColor[1], iEntCaseData[client][4]);
		}
#endif
#if defined _vip_core_included
		case 2: 
		{
			if(bGiveVIP)
			{
				char buffer[64];
				do{
					iEntCaseData[client][4] = GetRandomInt(0, hArrayList.Length - 1);
					hArrayList.GetString(iEntCaseData[client][4], buffer, sizeof(buffer));
					kv.Rewind();
					kv.JumpToKey(buffer);
				} while(ReturnAccept(kv.GetFloat("chance")) == false)

				if(bCaseMessagesHint) 
				{
					hArrayList.GetString(iEntCaseData[client][4], buffer,sizeof(buffer))
					PrintHintText(client, "%t", "vip_scroll", sColor[1], buffer);
				}
			}
			else 
			{
				iEntCaseData[client][4] = GetRandomInt(iMinCredits,iMaxCredits);
				if(bCaseMessagesHint) PrintHintText(client, "%t", "credits_scroll", sColor[1], iEntCaseData[client][4]);
			}
		}
#endif
	}
	return Plugin_Continue;
}

public Action SpawnReward(Handle hNewTimer, int client) 
{
	DispatchKeyValue(iEntCaseData[client][1], "modelscale", "1.0");
	DispatchSpawn(iEntCaseData[client][1]);
	if(!bStartCounter)
	{
		char sQuery[256], auth[22];
		GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
		
		SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "SELECT * FROM `opener_base` WHERE `steam`='%s'", auth);
		gDatabase.Query(SQLOnRewardSpawn, sQuery, client, DBPrio_High);                   
	}
	SDKHook(iEntCaseData[client][1], SDKHook_StartTouch, Hook_ModelStartTouch);
	CreateParticle(iEntCaseData[client][0], particles[GetRandomInt(0, sizeof(particles)-1)], client);
	if(hTimers[client][0] != INVALID_HANDLE) hTimers[client][0] = null;
	return Plugin_Continue;
}

public void SQLOnRewardSpawn(Database db, DBResultSet result, const char[] error, int client)
{
	if(result != INVALID_HANDLE && !error[0])
	{
		if(result.HasResults) 
		{
			if(result.RowCount > 0) 
			{
				char sQuery[256], auth[22];
				GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
				SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "UPDATE `opener_base` SET `available`='0', `last_open`='%i' WHERE `steam`='%s'", GetTime(), auth);
				SQL_FastQuery(gDatabase, sQuery);                
			}
		}
	}
    else PrintError(error);
}

public Action OnTouchDelete(Handle hNewTimer, int activator) 
{
	float fPos[3];
	GetEntPropVector(iEntCaseData[activator][0], Prop_Data, "m_vecAbsOrigin", fPos);
	if(bKillCaseSound) EmitSoundToAll("weapons/hegrenade/explode3.wav", iEntCaseData[activator][0], SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, fPos);

	if(bEnableBoom)
	{
		TE_SetupExplosion(fPos, iExplode, 10.0, 1, 0, 275, 160);
		TE_SendToAll();	
	}

	AcceptEntityInput(iEntCaseData[activator][0], "Kill");

	if(hTimers[activator][3] != INVALID_HANDLE) hTimers[activator][3] = null;

	for(int i = 0;i <= 4; i++) 
		iEntCaseData[activator][i] = -1;

	iReward[activator] = -1;
	bWarn[activator] = false;
	return Plugin_Continue;
}

public Action Hook_ModelStartTouch(int iEntity, int activator) 
{
	if(activator > 0 && activator <= MaxClients)
	{
		if(iEntCaseData[activator][1] == iEntity && iEntity > MaxClients)
		{
			char sTime[32];
			FormatTime(sTime, sizeof(sTime), "%X", GetTime());
			DeleteParticle(iClientParticle[activator]);
			switch (iReward[activator]) 
			{
				case 0: 
				{
					Shop_GiveClientCredits(activator, iEntCaseData[activator][4], CREDITS_BY_NATIVE);
					if(bCaseMessages)
					{
						if(bPrintAll) CGOPrintToChatAll("%t%t", "prefix", "received_credits_all", activator, iEntCaseData[activator][4]);
						else CGOPrintToChat(activator, "%t%t", "prefix", "received_credits", iEntCaseData[activator][4]);
					}
					LogMessage("[CASEOPENER] The player %N received %i credits", activator, iEntCaseData[activator][4]);
					if(bDropLog) LogToFileEx(sLog, "[ %s ] The player %N got %i credits ", sTime, activator, iEntCaseData[activator][4]);
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
						if(bCaseMessages) 
						{   
							if(bPrintAll) CGOPrintToChatAll("%t%t", "prefix", "received_exp_all", activator, iEntCaseData[activator][4]);
							else CGOPrintToChat(activator, "%t%t", "prefix", "received_exp", iEntCaseData[activator][4]);
						}
						LogMessage("[CASEOPENER] The player %N received %i experience", activator, iEntCaseData[activator][4]);
						if(bDropLog) LogToFileEx(sLog, "[ %s ] The player %N got %i experience ", sTime, activator, iEntCaseData[activator][4]);
					}
					else 
					{
						Shop_GiveClientCredits(activator, iEntCaseData[activator][4], CREDITS_BY_NATIVE);
						if(bCaseMessages) 
						{
							if(bPrintAll) CGOPrintToChatAll("%t%t", "prefix", "received_credits_all", activator, iEntCaseData[activator][4]);
							else CGOPrintToChat(activator, "%t%t", "prefix", "received_credits", iEntCaseData[activator][4]);
						}
						LogMessage("[CASEOPENER] The player %N received %i credits", activator, iEntCaseData[activator][4]);
						if(bDropLog) LogToFileEx(sLog, "[ %s ] The player %N got %i credits ", sTime, activator, iEntCaseData[activator][4]);
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
							if(bCaseMessages) 
							{
								if(bPrintAll) 
								{
									if(kv.GetNum("time") == 0) CGOPrintToChatAll("%t%t", "prefix", "got_vip_all_forever", activator, buffer);
									else CGOPrintToChatAll("%t%t", "prefix", "got_vip_all", activator, buffer, kv.GetNum("time"));
								}
							}
							LogMessage("[CASEOPENER] The player %N received a privilege: %s", activator, buffer);
							if(bDropLog) LogToFileEx(sLog, "[ %s ] The player %N got %s for %i seconds ", sTime, activator, buffer, kv.GetNum("time"));
						}
						else 
						{
							if(bCaseMessages) 
							{
								if(bPrintAll) CGOPrintToChatAll("%t%t", "prefix", "nothing", activator);
								else CGOPrintToChat(activator, "%t%t", "prefix", "already_has_vip");
							}
							LogMessage("[CASEOPENER] The player %N already has vip", activator);
						}					
					}
					else 
					{
						Shop_GiveClientCredits(activator, iEntCaseData[activator][4], CREDITS_BY_NATIVE);
						if(bCaseMessages)
						{
							if(bPrintAll) CGOPrintToChatAll("%t%t", "prefix", "received_credits_all", activator, iEntCaseData[activator][4]);
							else CGOPrintToChat(activator, "%t%t", "prefix", "received_credits", iEntCaseData[activator][4]);
						}
						LogMessage("[CASEOPENER] The player %N received %i credits", activator, iEntCaseData[activator][4]);
						if(bDropLog) LogToFileEx(sLog, "[ %s ] The player %N got %i credits ", sTime, activator, iEntCaseData[activator][4]);
					}
				}
#endif
			}
			EmitSoundToClient(activator, "ui/panorama/music_equip_01.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR);
			if(bStartCounter)
			{
				char sQuery[256], auth[22];
				GetClientAuthId(activator, AuthId_Steam2, auth, sizeof(auth));
				
				SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "SELECT * FROM `opener_base` WHERE `steam`='%s'", auth);
				gDatabase.Query(SQLSetUnavailableCase, sQuery, activator, DBPrio_High);                 
			}

			if(IsValidEdict(iEntCaseData[activator][1])) 
			{
				iEntCaseData[activator][2] = GetEntPropEnt(iEntCaseData[activator][1], Prop_Send, "m_hEffectEntity");
				if(iEntCaseData[activator][2] && IsValidEdict(iEntCaseData[activator][2])) AcceptEntityInput(iEntCaseData[activator][2], "Kill");
				AcceptEntityInput(iEntCaseData[activator][1], "Kill");
				hTimers[activator][3] = CreateTimer(float(iCaseKillTimer), OnTouchDelete, activator);
			}  
		}
		else if(bCaseMessages) 
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

public void SQLSetUnavailableCase(Database db, DBResultSet result, const char[] error, int client)
{
	if(result != INVALID_HANDLE && !error[0]) 
	{
		if(result.HasResults) 
		{
			if(result.RowCount > 0) 
			{
				char auth[22], sQuery[256];
				GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
				SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "UPDATE `opener_base` SET `available`='0', `last_open`='%i' WHERE `steam`='%s'", GetTime(), auth);
				SQL_FastQuery(gDatabase, sQuery);                
			}
		}                
	}
    else PrintError(error);
}

public void OnMapEnd()
{
	for(int j = 1; j <= MaxClients; j++)
		for(int i = 0; i <= 4; i++)
			if(hTimers[j][i] != INVALID_HANDLE) delete hTimers[j][i];		

	for(int i = 1; i <= MaxClients; i++)
		NullClient(i);
}

void RegCommandsFromKv(const char[] key, ConCmd Callback, const char[] desc)
{
    char keybuffer[2048], cmds[32][64];
	kv.Rewind();
    kv.GetString(key, keybuffer, sizeof(keybuffer));
    ExplodeString(keybuffer, ";", cmds, sizeof(cmds), 64);
    for(int i = 0; i < sizeof(cmds); i++) 
	{
		if(cmds[i][0] == '!') ReplaceString(cmds[i], sizeof(cmds), "!", "sm_", true);
        RegConsoleCmd(cmds[i], Callback, desc);
	}
}

void PrintToHintScrolling(int client) 
{
	int Random = 0; 
#if ((defined _levelsranks_included_ || defined _fire_players_stats_included) && !defined _vip_core_included)
	Random = GetRandomInt(0,1);
#elseif (!(defined _levelsranks_included_ || defined _fire_players_stats_included) && defined _vip_core_included)
	Random = (GetRandomInt(0,100) > 50) ? 2 : 0;
#else 
	Random = GetRandomInt(0,2);
#endif
	switch(Random) 
	{
		case 0: PrintHintText(client, "%t", "credits_scroll", sColor[0], GetRandomInt(iMinCredits,iMaxCredits));
#if defined _levelsranks_included_ || defined _fire_players_stats_included
		case 1: 
		{
			if(bGiveExp) PrintHintText(client, "%t", "exp_scroll", sColor[0], GetRandomInt(iMinExp,iMaxExp));
			else PrintHintText(client, "%t", "credits_scroll", sColor[0], GetRandomInt(iMinCredits,iMaxCredits));
		}
#endif
#if defined _vip_core_included
		case 2: 
		{
			if(bGiveVIP) 
			{
				char buffer[32];
				hArrayList.GetString(GetRandomInt(0,hArrayList.Length - 1), buffer,sizeof(buffer));
				PrintHintText(client, "%t", "vip_scroll", sColor[0], buffer);			
			}
			else PrintHintText(client, "%t", "credits_scroll", sColor[0], GetRandomInt(iMinCredits,iMaxCredits));
		}
#endif
	}
}

void PrintError(const char[] error)
{
    LogMessage("Query ERROR: %s", error);
}

void NullClient(int client) 
{

	if(hTimers[client][0] != INVALID_HANDLE) 
	{
		KillTimer(hTimers[client][0]);
		hTimers[client][0] = null;
	}

	if(hTimers[client][1] != INVALID_HANDLE) 
	{
		KillTimer(hTimers[client][1]);
		hTimers[client][1] = null;
	}

	if(hTimers[client][2] != INVALID_HANDLE) 
	{
		KillTimer(hTimers[client][2]);
		hTimers[client][2] = null;
	}

	if(hTimers[client][3] != INVALID_HANDLE) 
	{
		KillTimer(hTimers[client][3]);
		hTimers[client][3] = null;
	}

	if(hTimers[client][4] != INVALID_HANDLE) hTimers[client][4] = null;

	if(hTimers[client][5] != INVALID_HANDLE) hTimers[client][5] = null;
	
	for(int i = 0;i <= 4; i++) 
		iEntCaseData[client][i] = -1;

	iReward[client] = -1;
	bWarn[client] = false;
}

bool ReturnAccept(float fChance)
{
	return (GetRandomInt(1, 1000) > RoundToFloor(fChance * 1000.0)) ? false : true;
}

void SpawningReward(float fPos[3], int client) 
{
	SetVariantString("open");
	AcceptEntityInput(iEntCaseData[client][0], "SetAnimation", -1, -1, -1);
	DispatchKeyValueFloat(iEntCaseData[client][0], "playbackrate", fOpenSpeedAnim);
	kv.Rewind();
	bool ex = false;
	int R;
#if ((defined _levelsranks_included_ || defined _fire_players_stats_included) && defined _vip_core_included)
	do{
		R = GetRandomInt(0,2);
		if(R == 0) 
		{
			ex = ReturnAccept(kv.GetFloat("_credits"));
		}			
		else if(R == 1) 
		{
			ex = ReturnAccept(kv.GetFloat("_exps"));
		}
		else if(R == 2) 
		{
			ex = ReturnAccept(kv.GetFloat("_vips"));
		}
	} while(ex == false)
	iReward[client] = R;
	#elseif ((defined _levelsranks_included_ || defined _fire_players_stats_included) && !defined _vip_core_included)
	do{
		R = GetRandomInt(0,1);
		if(R == 0) 
		{
			ex = ReturnAccept(kv.GetFloat("_credits"));
		}		
		else if(R == 1) 
		{
			ex = ReturnAccept(kv.GetFloat("_exps"));
		}
	} while(ex == false)
	iReward[client] = R;
	#elseif (defined _vip_core_included && !(defined _levelsranks_included_ || defined _fire_players_stats_included))
	do{
		(GetRandomInt(0,100) > 50) ? R = 0 : R = 2
		if(R == 0) 
		{
			ex = ReturnAccept(kv.GetFloat("_credits"));
		}			
		else if(R == 2) 
		{
			ex = ReturnAccept(kv.GetFloat("_vips"));
		}
	} while(ex == false)
	iReward[client] = R;
	#elseif !((defined _levelsranks_included_ || defined _fire_players_stats_included) && defined _vip_core_included)
	iReward[client] = 0;
#endif

	if(client && IsClientInGame(client)) 
	{
		char clr[20], sTargetName[32], sBufer[70];

		iEntCaseData[client][1] = CreateEntityByName("prop_dynamic");

		Format(sTargetName, sizeof(sTargetName), "Reward_%i", iEntCaseData[client][1]);
		DispatchKeyValue(iEntCaseData[client][1], "targetname", sTargetName);
		DispatchKeyValueVector(iEntCaseData[client][1], "origin", fPos);
		DispatchKeyValue(iEntCaseData[client][1], "modelscale", "0.1");
		DispatchKeyValue(iEntCaseData[client][1], "solid", "6");
		switch(iReward[client]) 
		{
			case 0: DispatchKeyValue(iEntCaseData[client][1], "model", sRewardMDL[iReward[client]]);
#if (defined _levelsranks_included_ || defined _fire_players_stats_included)
			case 1: 
			{
				if(bGiveExp) DispatchKeyValue(iEntCaseData[client][1], "model", sRewardMDL[iReward[client]]);				
				else DispatchKeyValue(iEntCaseData[client][1], "model", sRewardMDL[0]);	
			}
#endif
#if defined _vip_core_included
			case 2: 
			{
				if(bGiveVIP) DispatchKeyValue(iEntCaseData[client][1], "model", sRewardMDL[iReward[client]]);				
				else DispatchKeyValue(iEntCaseData[client][1], "model", sRewardMDL[0]);
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

		DispatchKeyValue(iEntCaseData[client][3], "rendermode", "5");
		DispatchKeyValue(iEntCaseData[client][3], "rendercolor", view_as<char>(clr));
		DispatchKeyValue(iEntCaseData[client][3], "renderamt", "255");
		DispatchKeyValueFloat(iEntCaseData[client][3], "scale", 1.0);
		DispatchKeyValue(iEntCaseData[client][3], "model", "sprites/glow01.spr");
		DispatchKeyValueVector(iEntCaseData[client][3], "origin", fPos);
		DispatchSpawn(iEntCaseData[client][3]);
		SetVariantString("!activator");
		AcceptEntityInput(iEntCaseData[client][3], "SetParent", iEntCaseData[client][1]);

		hTimers[client][2] = CreateTimer(fOpenSpeedScroll, Scrolling, client, TIMER_REPEAT);
		hTimers[client][0] = CreateTimer(fOpenSpeed, SpawnReward, client);
		hTimers[client][1] = CreateTimer(fOpenSpeed, SoundOpen, client);
	}
}

void AddDataToDB(int client) 
{
	char sQuery[256], auth[22];
	GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
	
	SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "SELECT * FROM `opener_base` WHERE `steam`='%s'", auth);
	gDatabase.Query(SQLAddClientData, sQuery, client, DBPrio_High);
}

float[] SpawnCase(int iClient, float fPos[3], float fAng[3]) 
{
	char sTargetName[64];

	fAng[x] = 0.0;
	fAng[y] += 90.0;

	iEntCaseData[iClient][0] = CreateEntityByName("prop_dynamic");

	Format(sTargetName, sizeof(sTargetName), "case_%i", iClient);
	DispatchKeyValue(iEntCaseData[iClient][0], "targetname", sTargetName);

	DispatchKeyValue(iEntCaseData[iClient][0], "model", sCrates[GetRandomInt(0, sizeof(sCrates)-1)]);
	DispatchKeyValue(iEntCaseData[iClient][0], "modelscale", "1.0");
	DispatchKeyValue(iEntCaseData[iClient][0], "spawnflags", "16");
	DispatchKeyValue(iEntCaseData[iClient][0], "solid", "6");
	DispatchKeyValueVector(iEntCaseData[iClient][0], "origin", fPos);
	DispatchKeyValueVector(iEntCaseData[iClient][0], "angles", fAng);

	DispatchSpawn(iEntCaseData[iClient][0]);

	SetVariantString("fall");
	AcceptEntityInput(iEntCaseData[iClient][0], "SetAnimation", -1, -1, -1);
	AcceptEntityInput(iEntCaseData[iClient][0], "EnableCollision");
	DispatchKeyValueFloat(iEntCaseData[iClient][0], "playbackrate", 1.1);
	EmitSoundToAll("ui/panorama/case_drop_01.wav", iEntCaseData[iClient][0], SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, fPos);
	fPos[z] += 20.0;
	return fPos;
}

bool TRFilter(int client, int mask) 
{ 
	return client ? false : true;
}

void CreateTableDB() 
{
	char sQuery[512];
	SQL_FormatQuery(gDatabase, sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `opener_base` (\
														`steam` VARCHAR(24) NOT NULL PRIMARY KEY, \
														`last_open` INTEGER(20) NOT NULL, \
														`available` INTEGER(8) NOT NULL)");
	SQL_TQuery(gDatabase, SQLTQueryCallBack, sQuery);
}

void PreCacheFiles() 
{
	for(int i = 0; i < sizeof(sCrates); i++) PrecacheModel(sCrates[i]);

	for(int i = 0; i < sizeof(sRewardMDL); i++) PrecacheModel(sRewardMDL[i]);

	for(int i = 0; i < sizeof(downloadparticles); i++) PrecacheGeneric(downloadparticles[i], true);	

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

stock void CreateParticle(int ent, char[] particleType, int client)
{
    int particle = CreateEntityByName("info_particle_system");
    
    char name[64];
    float position[3];
    if(IsValidEdict(particle))
    {
        GetEntPropVector(ent, Prop_Send, "m_vecOrigin", position);
		position[z]+=20.0;
        TeleportEntity(particle, position, NULL_VECTOR, NULL_VECTOR);
        GetEntPropString(ent, Prop_Data, "m_iName", name, sizeof(name));
        DispatchKeyValue(particle, "targetname", "tf2particle");
        DispatchKeyValue(particle, "parentname", name);
        DispatchKeyValue(particle, "effect_name", particleType);
        DispatchSpawn(particle);
        SetVariantString(name);
        AcceptEntityInput(particle, "SetParent", particle, particle, 0);
        ActivateEntity(particle);
        AcceptEntityInput(particle, "start");
		iClientParticle[client] = particle;
        //hTimers[client][5] = CreateTimer(time, DeleteParticle, particle);
    }
}

void DeleteParticle(any particle)
{
    if(IsValidEntity(particle))
    {
        char classN[64];
        GetEdictClassname(particle, classN, sizeof(classN));
        if (StrEqual(classN, "info_particle_system", false)) RemoveEdict(particle);
    }
}