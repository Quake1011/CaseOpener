#define FEATURE_MAX_CASES 8
#define FEATURE_MAX_ID 32
#define FEATURE_MAX_TEXT 96
#define FEATURE_REQUEST_FACTOR 16

#define FEATURE_REWARD_CREDITS 0
#define FEATURE_REWARD_EXP 1
#define FEATURE_REWARD_VIP 2
#define FEATURE_REWARD_SHOP 3
#define FEATURE_REWARD_XP_MULTIPLIER 4
#define FEATURE_REWARD_EXTRA_CASE 5

char gFeatureCaseId[FEATURE_MAX_CASES][FEATURE_MAX_ID];
char gFeatureCaseName[FEATURE_MAX_CASES][FEATURE_MAX_TEXT];
char gFeatureCaseModel[FEATURE_MAX_CASES][PLATFORM_MAX_PATH];
char gFeatureCaseVipGroup[FEATURE_MAX_CASES][64];
char gFeatureCaseShopCategory[FEATURE_MAX_CASES][64];
char gFeatureCaseShopItem[FEATURE_MAX_CASES][64];

int gFeatureCaseCount;
int gFeatureCaseCooldown[FEATURE_MAX_CASES];
int gFeatureCaseCreditsMin[FEATURE_MAX_CASES];
int gFeatureCaseCreditsMax[FEATURE_MAX_CASES];
int gFeatureCaseExpMin[FEATURE_MAX_CASES];
int gFeatureCaseExpMax[FEATURE_MAX_CASES];
int gFeatureCaseVipTime[FEATURE_MAX_CASES];
int gFeatureCaseStreakRequired[FEATURE_MAX_CASES];
int gFeatureCaseStreakBonus[FEATURE_MAX_CASES];
int gFeatureCaseExtraCases[FEATURE_MAX_CASES];
float gFeatureCaseCreditsChance[FEATURE_MAX_CASES];
float gFeatureCaseExpChance[FEATURE_MAX_CASES];
float gFeatureCaseVipChance[FEATURE_MAX_CASES];
float gFeatureCaseShopChance[FEATURE_MAX_CASES];
float gFeatureCaseMultiplierChance[FEATURE_MAX_CASES];
float gFeatureCaseExtraChance[FEATURE_MAX_CASES];
float gFeatureCaseMultiplier[FEATURE_MAX_CASES];

int gFeatureActiveCase[MAXPLAYERS + 1] = {-1, ...};
int gFeatureActiveStreak[MAXPLAYERS + 1];
int gFeatureActiveBonus[MAXPLAYERS + 1];
int gFeatureRewardType[MAXPLAYERS + 1];
int gFeatureRewardValue[MAXPLAYERS + 1];
int gFeatureRewardVipTime[MAXPLAYERS + 1];
float gFeatureRewardMultiplier[MAXPLAYERS + 1];
bool gFeatureUseExtra[MAXPLAYERS + 1];
bool gFeatureReserved[MAXPLAYERS + 1];
char gFeatureRewardVipGroup[MAXPLAYERS + 1][64];
char gFeatureRewardShopCategory[MAXPLAYERS + 1][64];
char gFeatureRewardShopItem[MAXPLAYERS + 1][64];

KeyValues gFeatureKv;
File gFeatureExportFile;
int gFeatureExportMode;
int gFeatureExportAdmin;
bool gFeatureExportFirst;

void Feature_Init()
{
	Feature_LoadConfig();
	RegConsoleCmd("sm_dailycase", Feature_CommandDaily, "Open the daily case");
	RegConsoleCmd("sm_weeklycase", Feature_CommandWeekly, "Open the weekly case");
	RegConsoleCmd("sm_case_open", Feature_CommandOpen, "Open a configured case: sm_case_open <id>");
	RegConsoleCmd("sm_case_menu", Feature_CommandMenu, "Show configured cases and rewards");
	RegConsoleCmd("sm_case_info", Feature_CommandMenu, "Show configured cases and rewards");

	RegAdminCmd("sm_case_give", Feature_CommandGive, ADMFLAG_ROOT, "Give extra cases: sm_case_give <target> <case> [count]");
	RegAdminCmd("sm_case_take", Feature_CommandTake, ADMFLAG_ROOT, "Take extra cases: sm_case_take <target> <case> [count]");
	RegAdminCmd("sm_case_stats", Feature_CommandStats, ADMFLAG_ROOT, "Show case progress: sm_case_stats [target]");
	RegAdminCmd("sm_case_export", Feature_CommandExport, ADMFLAG_ROOT, "Export case statistics: sm_case_export <json|csv>");
}

void Feature_LoadConfig()
{
	gFeatureCaseCount = 0;
	Feature_AddDefaultCase("daily");
	Feature_AddDefaultCase("weekly");

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/CaseOpenerCases.ini");
	gFeatureKv = CreateKeyValues("Cases");
	if(!gFeatureKv.ImportFromFile(path))
	{
		LogError("[CASEOPENER] Cannot load %s; built-in daily and weekly definitions are used", path);
		return;
	}

	gFeatureKv.Rewind();
	if(!gFeatureKv.GotoFirstSubKey())
		return;

	do
	{
		char id[FEATURE_MAX_ID];
		gFeatureKv.GetSectionName(id, sizeof(id));
		int index = Feature_FindCase(id);
		if(index == -1 && gFeatureCaseCount < FEATURE_MAX_CASES)
		{
			index = gFeatureCaseCount++;
			strcopy(gFeatureCaseId[index], sizeof(gFeatureCaseId[]), id);
		}
		if(index != -1)
			Feature_ReadCase(index);
	}
	while(gFeatureKv.GotoNextKey());

	LogMessage("[CASEOPENER] Loaded %i configured case types", gFeatureCaseCount);
}

void Feature_AddDefaultCase(const char[] id)
{
	if(gFeatureCaseCount >= FEATURE_MAX_CASES)
		return;

	int i = gFeatureCaseCount++;
	strcopy(gFeatureCaseId[i], sizeof(gFeatureCaseId[]), id);
	FormatEx(gFeatureCaseName[i], sizeof(gFeatureCaseName[]), "%s Case", id);
	strcopy(gFeatureCaseModel[i], sizeof(gFeatureCaseModel[]), "models/props/crates/csgo_drop_crate_gamma.mdl");
	gFeatureCaseCooldown[i] = StrEqual(id, "weekly") ? 604800 : 86400;
	gFeatureCaseCreditsChance[i] = 0.50;
	gFeatureCaseExpChance[i] = 0.35;
	gFeatureCaseVipChance[i] = 0.10;
	gFeatureCaseShopChance[i] = 0.03;
	gFeatureCaseMultiplierChance[i] = 0.01;
	gFeatureCaseExtraChance[i] = 0.01;
	gFeatureCaseCreditsMin[i] = 500;
	gFeatureCaseCreditsMax[i] = 2500;
	gFeatureCaseExpMin[i] = 400;
	gFeatureCaseExpMax[i] = 1000;
	gFeatureCaseVipTime[i] = StrEqual(id, "weekly") ? 604800 : 86400;
	gFeatureCaseMultiplier[i] = 2.0;
	gFeatureCaseExtraCases[i] = 1;
	gFeatureCaseStreakRequired[i] = 7;
	gFeatureCaseStreakBonus[i] = 25;
}

void Feature_ReadCase(int index)
{
	if(index < 0 || index >= gFeatureCaseCount || gFeatureKv == null)
		return;

	gFeatureKv.GetString("name", gFeatureCaseName[index], sizeof(gFeatureCaseName[]), gFeatureCaseId[index]);
	gFeatureKv.GetString("model", gFeatureCaseModel[index], sizeof(gFeatureCaseModel[]), "models/props/crates/csgo_drop_crate_gamma.mdl");
	gFeatureKv.GetString("vip_group", gFeatureCaseVipGroup[index], sizeof(gFeatureCaseVipGroup[]), "");
	gFeatureKv.GetString("shop_category", gFeatureCaseShopCategory[index], sizeof(gFeatureCaseShopCategory[]), "");
	gFeatureKv.GetString("shop_item", gFeatureCaseShopItem[index], sizeof(gFeatureCaseShopItem[]), "");

	gFeatureCaseCooldown[index] = Feature_ClampInt(gFeatureKv.GetNum("cooldown", gFeatureCaseCooldown[index]), 1, 2592000);
	gFeatureCaseCreditsChance[index] = Feature_ClampFloat(gFeatureKv.GetFloat("credits_chance", gFeatureCaseCreditsChance[index]), 0.0, 100.0);
	gFeatureCaseExpChance[index] = Feature_ClampFloat(gFeatureKv.GetFloat("exp_chance", gFeatureCaseExpChance[index]), 0.0, 100.0);
	gFeatureCaseVipChance[index] = Feature_ClampFloat(gFeatureKv.GetFloat("vip_chance", gFeatureCaseVipChance[index]), 0.0, 100.0);
	gFeatureCaseShopChance[index] = Feature_ClampFloat(gFeatureKv.GetFloat("shop_chance", gFeatureCaseShopChance[index]), 0.0, 100.0);
	gFeatureCaseMultiplierChance[index] = Feature_ClampFloat(gFeatureKv.GetFloat("xp_multiplier_chance", gFeatureCaseMultiplierChance[index]), 0.0, 100.0);
	gFeatureCaseExtraChance[index] = Feature_ClampFloat(gFeatureKv.GetFloat("extra_case_chance", gFeatureCaseExtraChance[index]), 0.0, 100.0);
	gFeatureCaseCreditsMin[index] = Feature_ClampInt(gFeatureKv.GetNum("credits_min", gFeatureCaseCreditsMin[index]), 0, 2147483647);
	gFeatureCaseCreditsMax[index] = Feature_ClampInt(gFeatureKv.GetNum("credits_max", gFeatureCaseCreditsMax[index]), 0, 2147483647);
	gFeatureCaseExpMin[index] = Feature_ClampInt(gFeatureKv.GetNum("exp_min", gFeatureCaseExpMin[index]), 0, 2147483647);
	gFeatureCaseExpMax[index] = Feature_ClampInt(gFeatureKv.GetNum("exp_max", gFeatureCaseExpMax[index]), 0, 2147483647);
	gFeatureCaseVipTime[index] = Feature_ClampInt(gFeatureKv.GetNum("vip_time", gFeatureCaseVipTime[index]), 0, 2147483647);
	gFeatureCaseMultiplier[index] = Feature_ClampFloat(gFeatureKv.GetFloat("xp_multiplier", gFeatureCaseMultiplier[index]), 1.0, 100.0);
	gFeatureCaseExtraCases[index] = Feature_ClampInt(gFeatureKv.GetNum("extra_cases", gFeatureCaseExtraCases[index]), 1, 100);
	gFeatureCaseStreakRequired[index] = Feature_ClampInt(gFeatureKv.GetNum("streak_required", gFeatureCaseStreakRequired[index]), 0, 10000);
	gFeatureCaseStreakBonus[index] = Feature_ClampInt(gFeatureKv.GetNum("streak_bonus_percent", gFeatureCaseStreakBonus[index]), 0, 1000);
}

int Feature_ClampInt(int value, int min, int max)
{
	if(value < min)
		return min;
	if(value > max)
		return max;
	return value;
}

float Feature_ClampFloat(float value, float min, float max)
{
	if(value < min)
		return min;
	if(value > max)
		return max;
	return value;
}

int Feature_FindCase(const char[] id)
{
	for(int i = 0; i < gFeatureCaseCount; i++)
		if(StrEqual(gFeatureCaseId[i], id, false))
			return i;
	return -1;
}

bool Feature_GetModel(int index, char[] buffer, int maxlen)
{
	if(index < 0 || index >= gFeatureCaseCount)
		return false;
	strcopy(buffer, maxlen, gFeatureCaseModel[index]);
	return true;
}

void Feature_PrecacheModels()
{
	for(int i = 0; i < gFeatureCaseCount; i++)
	{
		if(gFeatureCaseModel[i][0] != '\0')
		{
			AddFileToDownloadsTable(gFeatureCaseModel[i]);
			PrecacheModel(gFeatureCaseModel[i], true);
		}
	}
}

void Feature_OnMapStart()
{
	// Models are precached from PreCacheFiles(). Kept as a lifecycle hook for future map-specific assets.
}

void Feature_CreateTableDB()
{
	if(!gDatabaseReady || gDatabase == null)
		return;

	char query[1024];
	SQL_FormatQuery(gDatabase, query, sizeof(query), "CREATE TABLE IF NOT EXISTS `opener_case_progress` ( `steam` VARCHAR(24) NOT NULL, `case_type` VARCHAR(32) NOT NULL, `last_open` INTEGER NOT NULL, `available` INTEGER NOT NULL, `streak` INTEGER NOT NULL, `extra_cases` INTEGER NOT NULL, `opened` INTEGER NOT NULL, PRIMARY KEY (`steam`, `case_type`) )");
	SQL_TQuery(gDatabase, Feature_SQLLog, query);
}

public void Feature_SQLLog(Handle owner, Handle handle, const char[] error, any data)
{
	if(error[0])
	{
		gDatabaseReady = false;
		LogError("[CASEOPENER] Database query failed: %s", error);
	}
}

void Feature_OnClientConnected(int client)
{
	if(!IsValidHumanClient(client) || !gDatabaseReady || gDatabase == null)
		return;

	char steam[32], name[MAX_NAME_LENGTH], query[512];
	if(!GetClientAuthId(client, AuthId_Steam2, steam, sizeof(steam)))
		return;
	GetClientName(client, name, sizeof(name));

	SQL_FormatQuery(gDatabase, query, sizeof(query), "UPDATE `opener_base` SET `name`='%s' WHERE `steam`='%s'", name, steam);
	SQL_TQuery(gDatabase, Feature_SQLLog, query);

	for(int i = 0; i < gFeatureCaseCount; i++)
	{
		SQL_FormatQuery(gDatabase, query, sizeof(query), "INSERT INTO `opener_case_progress` (`steam`,`case_type`,`last_open`,`available`,`streak`,`extra_cases`,`opened`) SELECT '%s','%s',0,1,0,0,0 WHERE NOT EXISTS (SELECT 1 FROM `opener_case_progress` WHERE `steam`='%s' AND `case_type`='%s')", steam, gFeatureCaseId[i], steam, gFeatureCaseId[i]);
		SQL_TQuery(gDatabase, Feature_SQLLog, query);
	}
}

void Feature_OnClientDisconnect(int client)
{
	if(client <= 0 || client > MaxClients)
		return;
	Feature_ResetClient(client);
}

void Feature_ResetClient(int client)
{
	if(client <= 0 || client > MaxClients)
		return;
	gFeatureActiveCase[client] = -1;
	gFeatureActiveStreak[client] = 0;
	gFeatureActiveBonus[client] = 0;
	gFeatureRewardType[client] = FEATURE_REWARD_CREDITS;
	gFeatureRewardValue[client] = 0;
	gFeatureRewardVipTime[client] = 0;
	gFeatureRewardMultiplier[client] = 1.0;
	gFeatureUseExtra[client] = false;
	gFeatureReserved[client] = false;
	gFeatureRewardVipGroup[client][0] = '\0';
	gFeatureRewardShopCategory[client][0] = '\0';
	gFeatureRewardShopItem[client][0] = '\0';
}

bool Feature_IsActive(int client)
{
	return client > 0 && client <= MaxClients && gFeatureActiveCase[client] >= 0 && gFeatureActiveCase[client] < gFeatureCaseCount;
}

int Feature_EncodeRequest(int userid, int caseIndex)
{
	return userid * FEATURE_REQUEST_FACTOR + caseIndex;
}

int Feature_RequestUserId(int data)
{
	return data / FEATURE_REQUEST_FACTOR;
}

int Feature_RequestCase(int data)
{
	return data % FEATURE_REQUEST_FACTOR;
}

public Action Feature_CommandDaily(int client, int args)
{
	return Feature_CommandOpenIndex(client, Feature_FindCase("daily"));
}

public Action Feature_CommandWeekly(int client, int args)
{
	return Feature_CommandOpenIndex(client, Feature_FindCase("weekly"));
}

public Action Feature_CommandOpen(int client, int args)
{
	if(!IsValidHumanClient(client))
		return Plugin_Handled;
	if(args < 1)
	{
		Feature_ShowMenu(client);
		return Plugin_Handled;
	}

	char id[FEATURE_MAX_ID];
	GetCmdArg(1, id, sizeof(id));
	return Feature_CommandOpenIndex(client, Feature_FindCase(id));
}

Action Feature_CommandOpenIndex(int client, int caseIndex)
{
	if(!IsValidHumanClient(client))
		return Plugin_Handled;
	if(caseIndex < 0 || caseIndex >= gFeatureCaseCount)
	{
		ReplyToCommand(client, "[CaseOpener] Unknown case type.");
		return Plugin_Handled;
	}
	Feature_StartCase(client, caseIndex);
	return Plugin_Handled;
}

void Feature_StartCase(int client, int caseIndex)
{
	if(!IsValidHumanClient(client))
		return;
	if(!IsPlayerAlive(client))
	{
		Feature_Refusal(client, caseIndex, "not_alive");
		if(bNotificationsEnabled && bCaseMessages)
			CGOPrintToChat(client, "%t%t", "prefix", "be_alive");
		return;
	}
	if(!gDatabaseReady || gDatabase == null)
	{
		Feature_Refusal(client, caseIndex, "database_unavailable");
		if(bNotificationsEnabled && bCaseMessages)
			CGOPrintToChat(client, "%t%t", "prefix", "feature_database_unavailable");
		return;
	}
	if(bCaseAccess && GetUserAdmin(client) == INVALID_ADMIN_ID)
	{
		Feature_Refusal(client, caseIndex, "permission");
		if(bNotificationsEnabled && bCaseMessages)
			CGOPrintToChat(client, "%t%t", "prefix", "not_admin");
		return;
	}
	if(bCaseRequestPending[client])
		return;
	if(iEntCaseData[client][0] != -1 || iEntCaseData[client][1] != -1 || iEntCaseData[client][2] != -1 || iEntCaseData[client][3] != -1 || iEntCaseData[client][4] != -1)
	{
		Feature_Refusal(client, caseIndex, "existing_case");
		if(bNotificationsEnabled && bCaseMessages)
			CGOPrintToChat(client, "%t%t", "prefix", "existing_case");
		return;
	}

	char steam[32], query[512];
	if(!GetClientAuthId(client, AuthId_Steam2, steam, sizeof(steam)))
		return;
	bCaseRequestPending[client] = true;
	SQL_FormatQuery(gDatabase, query, sizeof(query), "SELECT `last_open`,`available`,`streak`,`extra_cases` FROM `opener_case_progress` WHERE `steam`='%s' AND `case_type`='%s'", steam, gFeatureCaseId[caseIndex]);
	gDatabase.Query(Feature_SQLCheckProgress, query, Feature_EncodeRequest(GetClientUserId(client), caseIndex), DBPrio_High);
}

public void Feature_SQLCheckProgress(Database db, DBResultSet result, const char[] error, any data)
{
	int userid = Feature_RequestUserId(data);
	int caseIndex = Feature_RequestCase(data);
	int client = GetClientOfUserId(userid);
	if(client <= 0 || client > MaxClients)
		return;
	bCaseRequestPending[client] = false;
	if(!IsValidHumanClient(client) || caseIndex < 0 || caseIndex >= gFeatureCaseCount)
		return;
	if(error[0] || result == null)
	{
		Feature_Refusal(client, caseIndex, "database_error");
		if(bNotificationsEnabled && bCaseMessages)
			CGOPrintToChat(client, "%t%t", "prefix", "feature_database_unavailable");
		return;
	}

	if(!result.HasResults || !result.RowCount || !result.FetchRow())
	{
		Feature_InsertProgress(client, caseIndex);
		Feature_ContinueOpen(client, caseIndex, 0, 1, 0, 0);
		return;
	}

	Feature_ContinueOpen(client, caseIndex, result.FetchInt(0), result.FetchInt(1), result.FetchInt(2), result.FetchInt(3));
}

void Feature_InsertProgress(int client, int caseIndex)
{
	char steam[32], query[512];
	if(!GetClientAuthId(client, AuthId_Steam2, steam, sizeof(steam)))
		return;
	SQL_FormatQuery(gDatabase, query, sizeof(query), "INSERT INTO `opener_case_progress` (`steam`,`case_type`,`last_open`,`available`,`streak`,`extra_cases`,`opened`) VALUES ('%s','%s',0,1,0,0,0)", steam, gFeatureCaseId[caseIndex]);
	SQL_TQuery(gDatabase, Feature_SQLLog, query);
}

void Feature_ContinueOpen(int client, int caseIndex, int lastOpen, int available, int streak, int extraCases)
{
	if(!IsValidHumanClient(client) || !gDatabaseReady)
		return;

	int now = GetTime();
	int remaining = lastOpen + gFeatureCaseCooldown[caseIndex] - now;
	bool useExtra = !available && remaining > 0 && extraCases > 0;
	if(!available && remaining > 0 && !useExtra)
	{
		Feature_Refusal(client, caseIndex, "cooldown");
		if(bNotificationsEnabled && bCaseMessages)
			CGOPrintToChat(client, "%t%t", "prefix", "feature_cooldown", remaining / 86400, remaining / 3600 % 24, remaining / 60 % 60, remaining % 60);
		if(bSoundsEnabled)
			EmitSoundToClient(client, "buttons/blip1.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR);
		return;
	}

	if(!available && remaining <= 0)
		Feature_SetAvailable(client, caseIndex);

	gFeatureUseExtra[client] = useExtra;

	if(lastOpen > 0 && now - lastOpen <= gFeatureCaseCooldown[caseIndex] * 2)
		gFeatureActiveStreak[client] = streak + 1;
	else
		gFeatureActiveStreak[client] = 1;
	gFeatureActiveBonus[client] = gFeatureActiveStreak[client] >= gFeatureCaseStreakRequired[caseIndex] ? gFeatureCaseStreakBonus[caseIndex] : 0;

	float origin[3], angles[3], end[3];
	GetClientEyePosition(client, origin);
	GetClientEyeAngles(client, angles);
	Handle trace = TR_TraceRayFilterEx(origin, angles, CONTENTS_SOLID, RayType_Infinite, TRFilter, client);
	if(trace == INVALID_HANDLE || !TR_DidHit(trace))
	{
		if(trace != INVALID_HANDLE)
			delete trace;
		Feature_Refusal(client, caseIndex, "no_trace");
		return;
	}
	TR_GetEndPosition(end, trace);
	delete trace;

	float clientOrigin[3];
	GetClientAbsOrigin(client, clientOrigin);
	if(bSamePlat && FloatAbs(end[z] - clientOrigin[z]) >= 5.0)
	{
		Feature_Refusal(client, caseIndex, "same_level");
		if(bNotificationsEnabled && bCaseMessages)
			CGOPrintToChat(client, "%t%t", "prefix", "same_level_case");
		return;
	}
	if(bMaxPosition && GetVectorDistance(clientOrigin, end) > float(iMaxPositionValue * 100))
	{
		Feature_Refusal(client, caseIndex, "distance");
		if(bNotificationsEnabled && bCaseMessages)
			CGOPrintToChat(client, "%t%t", "prefix", "too_longer", iMaxPositionValue);
		if(bEffectsEnabled && bOutputBeam)
		{
			float distance = float(iMaxPositionValue * 100);
			TE_SetupBeamRingPoint(clientOrigin, 0.0, distance * 2.0, g_BeamSprite, g_HaloSprite, 0, 660, 1.0, 2.0, 0.0, {255, 255, 0, 255}, 1000, 0);
			TE_SendToClient(client);
		}
		return;
	}

	if(useExtra)
		Feature_TakeExtra(client, caseIndex);
	gFeatureActiveCase[client] = caseIndex;
	bRewardClaimed[client] = false;
	float position[3];
	position = SpawnCase(client, end, angles, caseIndex);
	DataPack pack = CreateDataPack();
	pack.WriteCell(GetClientUserId(client));
	pack.WriteFloat(position[0]);
	pack.WriteFloat(position[1]);
	pack.WriteFloat(position[2]);
	hTimers[client][4] = CreateTimer(1.4, FallAfterTimer, pack);
}

void Feature_SetAvailable(int client, int caseIndex)
{
	char steam[32], query[512];
	if(!GetClientAuthId(client, AuthId_Steam2, steam, sizeof(steam)))
		return;
	SQL_FormatQuery(gDatabase, query, sizeof(query), "UPDATE `opener_case_progress` SET `available`=1 WHERE `steam`='%s' AND `case_type`='%s'", steam, gFeatureCaseId[caseIndex]);
	SQL_TQuery(gDatabase, Feature_SQLLog, query);
}

void Feature_TakeExtra(int client, int caseIndex)
{
	char steam[32], query[512];
	if(!GetClientAuthId(client, AuthId_Steam2, steam, sizeof(steam)))
		return;
	SQL_FormatQuery(gDatabase, query, sizeof(query), "UPDATE `opener_case_progress` SET `extra_cases`=`extra_cases`-1 WHERE `steam`='%s' AND `case_type`='%s' AND `extra_cases`>0", steam, gFeatureCaseId[caseIndex]);
	SQL_TQuery(gDatabase, Feature_SQLLog, query);
}

void Feature_ReserveCase(int client)
{
	if(!Feature_IsActive(client) || gFeatureUseExtra[client] || gFeatureReserved[client])
		return;
	int caseIndex = gFeatureActiveCase[client];
	char steam[32], query[512];
	if(!GetClientAuthId(client, AuthId_Steam2, steam, sizeof(steam)))
		return;
	SQL_FormatQuery(gDatabase, query, sizeof(query), "UPDATE `opener_case_progress` SET `available`=0, `last_open`='%i' WHERE `steam`='%s' AND `case_type`='%s'", GetTime(), steam, gFeatureCaseId[caseIndex]);
	SQL_TQuery(gDatabase, Feature_SQLLog, query);
	gFeatureReserved[client] = true;
}

int Feature_SelectReward(int caseIndex)
{
	if(caseIndex < 0 || caseIndex >= gFeatureCaseCount)
		return FEATURE_REWARD_CREDITS;

	float credits = gFeatureCaseCreditsChance[caseIndex];
	float expChance = 0.0;
	float vipChance = 0.0;
	float shopChance = gFeatureCaseShopChance[caseIndex];
	float multiplierChance = 0.0;
	float extraChance = gFeatureCaseExtraChance[caseIndex];
#if defined _levelsranks_included_ || defined _fire_players_stats_included
	if(bGiveExp)
	{
		expChance = gFeatureCaseExpChance[caseIndex];
		multiplierChance = gFeatureCaseMultiplierChance[caseIndex];
	}
#endif
#if defined _vip_core_included
	if(bGiveVIP)
		vipChance = gFeatureCaseVipChance[caseIndex];
#endif

	float total = credits + expChance + vipChance + shopChance + multiplierChance + extraChance;
	if(total <= 0.0)
		return FEATURE_REWARD_CREDITS;

	float roll = GetRandomFloat(0.0, total);
	if(roll < credits)
		return FEATURE_REWARD_CREDITS;
	roll -= credits;
	if(roll < expChance)
		return FEATURE_REWARD_EXP;
	roll -= expChance;
	if(roll < vipChance)
		return FEATURE_REWARD_VIP;
	roll -= vipChance;
	if(roll < shopChance)
		return FEATURE_REWARD_SHOP;
	roll -= shopChance;
	if(roll < multiplierChance)
		return FEATURE_REWARD_XP_MULTIPLIER;
	return FEATURE_REWARD_EXTRA_CASE;
}

void Feature_PrepareReward(int client)
{
	int caseIndex = gFeatureActiveCase[client];
	int reward = Feature_SelectReward(caseIndex);
	gFeatureRewardType[client] = reward;
	gFeatureRewardValue[client] = 0;
	gFeatureRewardMultiplier[client] = gFeatureCaseMultiplier[caseIndex];
	gFeatureRewardVipTime[client] = gFeatureCaseVipTime[caseIndex];
	strcopy(gFeatureRewardVipGroup[client], sizeof(gFeatureRewardVipGroup[]), gFeatureCaseVipGroup[caseIndex]);
	strcopy(gFeatureRewardShopCategory[client], sizeof(gFeatureRewardShopCategory[]), gFeatureCaseShopCategory[caseIndex]);
	strcopy(gFeatureRewardShopItem[client], sizeof(gFeatureRewardShopItem[]), gFeatureCaseShopItem[caseIndex]);
	#if defined _vip_core_included
	if(reward == FEATURE_REWARD_VIP && !gFeatureRewardVipGroup[client][0])
	{
		int group;
		if(SelectVipGroup(group))
			hArrayList.GetString(group, gFeatureRewardVipGroup[client], sizeof(gFeatureRewardVipGroup[]));
	}
	#endif

	if(reward == FEATURE_REWARD_CREDITS)
		gFeatureRewardValue[client] = GetSafeRandomInt(gFeatureCaseCreditsMin[caseIndex], gFeatureCaseCreditsMax[caseIndex]);
	else if(reward == FEATURE_REWARD_EXP || reward == FEATURE_REWARD_XP_MULTIPLIER)
		gFeatureRewardValue[client] = GetSafeRandomInt(gFeatureCaseExpMin[caseIndex], gFeatureCaseExpMax[caseIndex]);
	else if(reward == FEATURE_REWARD_EXTRA_CASE)
		gFeatureRewardValue[client] = gFeatureCaseExtraCases[caseIndex];

	iReward[client] = reward;
	iEntCaseData[client][4] = gFeatureRewardValue[client];
}

void Feature_PrintScrollingHint(int client)
{
	if(!Feature_IsActive(client) || !bNotificationsEnabled)
		return;
	int index = gFeatureActiveCase[client];
	PrintHintText(client, "%t", "feature_case_hint", gFeatureCaseName[index]);
}

void Feature_PrintRewardHint(int client)
{
	if(!Feature_IsActive(client) || !bNotificationsEnabled)
		return;
	char reward[128];
	Feature_GetRewardName(client, reward, sizeof(reward));
	PrintHintText(client, "%t", "feature_reward_hint", reward, gFeatureActiveStreak[client], gFeatureActiveBonus[client]);
}

void Feature_GetRewardName(int client, char[] buffer, int maxlen)
{
	switch(gFeatureRewardType[client])
	{
		case FEATURE_REWARD_CREDITS:
			FormatEx(buffer, maxlen, "%t", "feature_reward_credits", gFeatureRewardValue[client]);
		case FEATURE_REWARD_EXP:
			FormatEx(buffer, maxlen, "%t", "feature_reward_exp", gFeatureRewardValue[client]);
		case FEATURE_REWARD_VIP:
			FormatEx(buffer, maxlen, "%t", "feature_reward_vip", gFeatureRewardVipGroup[client], gFeatureRewardVipTime[client]);
		case FEATURE_REWARD_SHOP:
			FormatEx(buffer, maxlen, "%t", "feature_reward_shop", gFeatureRewardShopItem[client]);
		case FEATURE_REWARD_XP_MULTIPLIER:
			FormatEx(buffer, maxlen, "%t", "feature_reward_multiplier", gFeatureRewardMultiplier[client]);
		case FEATURE_REWARD_EXTRA_CASE:
			FormatEx(buffer, maxlen, "%t", "feature_reward_extra", gFeatureRewardValue[client]);
		default:
			strcopy(buffer, maxlen, "unknown");
	}
}

void Feature_HandleRewardTouch(int client)
{
	if(!Feature_IsActive(client))
		return;
	int caseIndex = gFeatureActiveCase[client];
	if(bStartCounter)
		Feature_ReserveCase(client);

	int value = gFeatureRewardValue[client];
	if(gFeatureActiveBonus[client] > 0 && (gFeatureRewardType[client] == FEATURE_REWARD_CREDITS || gFeatureRewardType[client] == FEATURE_REWARD_EXP || gFeatureRewardType[client] == FEATURE_REWARD_XP_MULTIPLIER))
		value = RoundToFloor(float(value) * (1.0 + float(gFeatureActiveBonus[client]) / 100.0));
	if(value < 0)
		value = 0;

	bool granted = true;
	char reward[128];
	Feature_GetRewardName(client, reward, sizeof(reward));
	switch(gFeatureRewardType[client])
	{
		case FEATURE_REWARD_CREDITS:
		{
			Shop_GiveClientCredits(client, value, CREDITS_BY_NATIVE);
			if(bNotificationsEnabled && bCaseMessages)
				CGOPrintToChat(client, "%t%t", "prefix", "feature_received", reward);
		}
		case FEATURE_REWARD_EXP:
		{
#if defined _levelsranks_included_ || defined _fire_players_stats_included
			if(bGiveExp)
			{
	#if defined _levelsranks_included_ || !defined _fire_players_stats_included
				LR_ChangeClientValue(client, value);
	#elseif !defined _levelsranks_included_ || defined _fire_players_stats_included
				FPS_SetPoints(client, float(value), false);
	#endif
			}
			else
			{
				Shop_GiveClientCredits(client, value, CREDITS_BY_NATIVE);
			}
#else
			Shop_GiveClientCredits(client, value, CREDITS_BY_NATIVE);
#endif
			if(bNotificationsEnabled && bCaseMessages)
				CGOPrintToChat(client, "%t%t", "prefix", "feature_received", reward);
		}
		case FEATURE_REWARD_VIP:
		{
#if defined _vip_core_included
			if(!bGiveVIP || !gFeatureRewardVipGroup[client][0] || !VIP_IsValidVIPGroup(gFeatureRewardVipGroup[client]))
				granted = false;
			else if(!VIP_IsClientVIP(client))
			{
				VIP_GiveClientVIP(0, client, gFeatureRewardVipTime[client], gFeatureRewardVipGroup[client], true);
			}
			else
				granted = false;
#else
			granted = false;
#endif
		}
		case FEATURE_REWARD_SHOP:
		{
			CategoryId category = Shop_GetCategoryId(gFeatureRewardShopCategory[client]);
			ItemId item = INVALID_ITEM;
			if(category != INVALID_CATEGORY)
				item = Shop_GetItemId(category, gFeatureRewardShopItem[client]);
			if(item == INVALID_ITEM || !Shop_GiveClientItem(client, item, 1))
				granted = false;
		}
		case FEATURE_REWARD_XP_MULTIPLIER:
		{
#if defined _levelsranks_included_ || defined _fire_players_stats_included
			if(bGiveExp)
			{
				int multiplied = RoundToFloor(float(value) * gFeatureRewardMultiplier[client]);
	#if defined _levelsranks_included_ || !defined _fire_players_stats_included
				LR_ChangeClientValue(client, multiplied);
	#elseif !defined _levelsranks_included_ || defined _fire_players_stats_included
				FPS_SetPoints(client, float(multiplied), false);
	#endif
			}
			else
				granted = false;
#else
			granted = false;
#endif
		}
		case FEATURE_REWARD_EXTRA_CASE:
		{
			Feature_AddExtraCases(client, caseIndex, value);
			if(bNotificationsEnabled && bCaseMessages)
				CGOPrintToChat(client, "%t%t", "prefix", "feature_received", reward);
		}
	}

	if(!granted)
	{
		Feature_Refusal(client, caseIndex, "reward_unavailable");
		int fallbackValue = value > 0 ? value : iMinCredits;
		Shop_GiveClientCredits(client, fallbackValue, CREDITS_BY_NATIVE);
		gFeatureRewardType[client] = FEATURE_REWARD_CREDITS;
		gFeatureRewardValue[client] = fallbackValue;
		if(bNotificationsEnabled && bCaseMessages)
			CGOPrintToChat(client, "%t%t", "prefix", "feature_reward_fallback");
	}

	Feature_CompleteProgress(client, caseIndex);
	if(bSoundsEnabled)
		EmitSoundToClient(client, "ui/panorama/music_equip_01.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, NULL_VECTOR);

	if(IsValidEdict(iEntCaseData[client][1]))
	{
		iEntCaseData[client][2] = GetEntPropEnt(iEntCaseData[client][1], Prop_Send, "m_hEffectEntity");
		if(iEntCaseData[client][2] && IsValidEdict(iEntCaseData[client][2]))
			AcceptEntityInput(iEntCaseData[client][2], "Kill");
		AcceptEntityInput(iEntCaseData[client][1], "Kill");
	}
	if(hTimers[client][3] != null)
		KillTimer(hTimers[client][3]);
	hTimers[client][3] = CreateTimer(float(iCaseKillTimer), OnTouchDelete, GetClientUserId(client));
}

void Feature_CompleteProgress(int client, int caseIndex)
{
	char steam[32], query[512];
	if(!GetClientAuthId(client, AuthId_Steam2, steam, sizeof(steam)))
		return;
	SQL_FormatQuery(gDatabase, query, sizeof(query), "UPDATE `opener_case_progress` SET `streak`='%i', `opened`=`opened`+1 WHERE `steam`='%s' AND `case_type`='%s'", gFeatureActiveStreak[client], steam, gFeatureCaseId[caseIndex]);
	SQL_TQuery(gDatabase, Feature_SQLLog, query);

	if(gFeatureRewardType[client] == FEATURE_REWARD_CREDITS)
		Feature_UpdateBaseStats(client, "credits_total", gFeatureRewardValue[client]);
	else if(gFeatureRewardType[client] == FEATURE_REWARD_EXP || gFeatureRewardType[client] == FEATURE_REWARD_XP_MULTIPLIER)
		Feature_UpdateBaseStats(client, "exp_total", gFeatureRewardValue[client]);
	else if(gFeatureRewardType[client] == FEATURE_REWARD_VIP)
		Feature_UpdateBaseStats(client, "vips_total", 1);
	else
		Feature_UpdateBaseStats(client, "cases_opened", 0);
}

void Feature_UpdateBaseStats(int client, const char[] field, int value)
{
	char steam[32], query[512];
	if(!GetClientAuthId(client, AuthId_Steam2, steam, sizeof(steam)))
		return;
	if(StrEqual(field, "cases_opened"))
		SQL_FormatQuery(gDatabase, query, sizeof(query), "UPDATE `opener_base` SET `cases_opened`=`cases_opened`+1 WHERE `steam`='%s'", steam);
	else
		SQL_FormatQuery(gDatabase, query, sizeof(query), "UPDATE `opener_base` SET `cases_opened`=`cases_opened`+1, `%s`=`%s`+%i WHERE `steam`='%s'", field, field, value, steam);
	SQL_TQuery(gDatabase, Feature_SQLLog, query);
}

void Feature_AddExtraCases(int client, int caseIndex, int amount)
{
	char steam[32], query[512];
	if(!GetClientAuthId(client, AuthId_Steam2, steam, sizeof(steam)))
		return;
	SQL_FormatQuery(gDatabase, query, sizeof(query), "UPDATE `opener_case_progress` SET `extra_cases`=`extra_cases`+%i WHERE `steam`='%s' AND `case_type`='%s'", amount, steam, gFeatureCaseId[caseIndex]);
	SQL_TQuery(gDatabase, Feature_SQLLog, query);
}

void Feature_Refusal(int client, int caseIndex, const char[] reason)
{
	char steam[32];
	if(!GetClientAuthId(client, AuthId_Steam2, steam, sizeof(steam)))
		strcopy(steam, sizeof(steam), "unknown");
	char caseId[FEATURE_MAX_ID];
	if(caseIndex >= 0 && caseIndex < gFeatureCaseCount)
		strcopy(caseId, sizeof(caseId), gFeatureCaseId[caseIndex]);
	else
		strcopy(caseId, sizeof(caseId), "unknown");
	LogMessage("[CASEOPENER] refusal reason=%s client=%N steam=%s case=%s", reason, client, steam, caseId);
	if(bDropLog && sLog[0])
		LogToFileEx(sLog, "refusal reason=%s client=%N steam=%s case=%s", reason, client, steam, caseId);
}

public Action Feature_CommandMenu(int client, int args)
{
	if(IsValidHumanClient(client))
		Feature_ShowMenu(client);
	return Plugin_Handled;
}

void Feature_ShowMenu(int client)
{
	Menu menu = CreateMenu(Feature_MenuHandler);
	char title[128], item[128];
	FormatEx(title, sizeof(title), "%t", "feature_case_menu");
	menu.SetTitle(title);
	for(int i = 0; i < gFeatureCaseCount; i++)
	{
		FormatEx(item, sizeof(item), "%s (%s)", gFeatureCaseName[i], gFeatureCaseId[i]);
		char index[8];
		IntToString(i, index, sizeof(index));
		menu.AddItem(index, item);
	}
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Feature_MenuHandler(Menu menu, MenuAction action, int client, int item)
{
	if(action == MenuAction_Select)
	{
		char value[8];
		menu.GetItem(item, value, sizeof(value));
		int index = StringToInt(value);
		if(index >= 0 && index < gFeatureCaseCount)
			Feature_ShowDetails(client, index);
	}
	else if(action == MenuAction_End)
		delete menu;
	return 0;
}

void Feature_ShowDetails(int client, int index)
{
	Menu menu = CreateMenu(Feature_DetailHandler);
	char title[512], rewards[384], item[8];
	FormatEx(rewards, sizeof(rewards), "C %.1f%% | EXP %.1f%% | VIP %.1f%% | Shop %.1f%% | XP x%.1f %.1f%% | Extra %.1f%%", gFeatureCaseCreditsChance[index] * 100.0, gFeatureCaseExpChance[index] * 100.0, gFeatureCaseVipChance[index] * 100.0, gFeatureCaseShopChance[index] * 100.0, gFeatureCaseMultiplier[index], gFeatureCaseMultiplierChance[index] * 100.0, gFeatureCaseExtraChance[index] * 100.0);
	FormatEx(title, sizeof(title), "%s\nCooldown: %i sec\nStreak: %i -> +%i%%\n%s", gFeatureCaseName[index], gFeatureCaseCooldown[index], gFeatureCaseStreakRequired[index], gFeatureCaseStreakBonus[index], rewards);
	menu.SetTitle(title);
	IntToString(index, item, sizeof(item));
	menu.AddItem(item, "Open case");
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Feature_DetailHandler(Menu menu, MenuAction action, int client, int item)
{
	if(action == MenuAction_Select)
	{
		char value[8];
		menu.GetItem(item, value, sizeof(value));
		int index = StringToInt(value);
		Feature_CommandOpenIndex(client, index);
	}
	else if(action == MenuAction_Cancel && item == MenuCancel_ExitBack)
		Feature_ShowMenu(client);
	else if(action == MenuAction_End)
		delete menu;
	return 0;
}

public Action Feature_CommandGive(int client, int args)
{
	return Feature_CommandAdjust(client, args, true);
}

public Action Feature_CommandTake(int client, int args)
{
	return Feature_CommandAdjust(client, args, false);
}

Action Feature_CommandAdjust(int client, int args, bool give)
{
	if(!gDatabaseReady || gDatabase == null)
	{
		ReplyToCommand(client, "[CaseOpener] Database is unavailable.");
		return Plugin_Handled;
	}
	if(args < 2)
	{
		ReplyToCommand(client, "Usage: sm_case_%s <target> <case> [count]", give ? "give" : "take");
		return Plugin_Handled;
	}
	char targetName[64], id[FEATURE_MAX_ID], countText[16];
	GetCmdArg(1, targetName, sizeof(targetName));
	GetCmdArg(2, id, sizeof(id));
	int target = FindTarget(client, targetName, true, false);
	int caseIndex = Feature_FindCase(id);
	if(target <= 0 || caseIndex < 0)
	{
		ReplyToCommand(client, "[CaseOpener] Invalid target or case.");
		return Plugin_Handled;
	}
	int amount = 1;
	if(args >= 3)
	{
		GetCmdArg(3, countText, sizeof(countText));
		amount = Feature_ClampInt(StringToInt(countText), 1, 1000);
	}
	if(!give)
		amount *= -1;
	char steam[32], query[512];
	if(!GetClientAuthId(target, AuthId_Steam2, steam, sizeof(steam)))
		return Plugin_Handled;
	SQL_FormatQuery(gDatabase, query, sizeof(query), "UPDATE `opener_case_progress` SET `extra_cases`=MAX(0, `extra_cases`+%i) WHERE `steam`='%s' AND `case_type`='%s'", amount, steam, gFeatureCaseId[caseIndex]);
	SQL_TQuery(gDatabase, Feature_SQLLog, query);
	ReplyToCommand(client, "[CaseOpener] %s %i extra case(s) for %N (%s).", give ? "Granted" : "Removed", give ? amount : -amount, target, gFeatureCaseId[caseIndex]);
	return Plugin_Handled;
}

public Action Feature_CommandStats(int client, int args)
{
	if(!gDatabaseReady || gDatabase == null)
	{
		ReplyToCommand(client, "[CaseOpener] Database is unavailable.");
		return Plugin_Handled;
	}
	int target = client;
	if(args >= 1)
	{
		char targetName[64];
		GetCmdArg(1, targetName, sizeof(targetName));
		target = FindTarget(client, targetName, true, false);
	}
	if(target <= 0)
		return Plugin_Handled;
	char steam[32], query[512];
	if(!GetClientAuthId(target, AuthId_Steam2, steam, sizeof(steam)))
		return Plugin_Handled;
	SQL_FormatQuery(gDatabase, query, sizeof(query), "SELECT `case_type`,`last_open`,`streak`,`extra_cases`,`opened` FROM `opener_case_progress` WHERE `steam`='%s' ORDER BY `case_type`", steam);
	gDatabase.Query(Feature_SQLStats, query, GetClientUserId(client));
	ReplyToCommand(client, "[CaseOpener] Case statistics for %N:", target);
	return Plugin_Handled;
}

public void Feature_SQLStats(Database db, DBResultSet result, const char[] error, any data)
{
	int client = GetClientOfUserId(data);
	if(error[0] || result == null)
	{
		if(IsValidHumanClient(client))
			ReplyToCommand(client, "[CaseOpener] Database error: %s", error);
		return;
	}
	if(!IsValidHumanClient(client))
		return;
	char type[FEATURE_MAX_ID];
	for(int i = 0; i < result.RowCount; i++)
	{
		if(!result.FetchRow())
			break;
		result.FetchString(0, type, sizeof(type));
		ReplyToCommand(client, "[CaseOpener] %s: last=%i streak=%i extra=%i opened=%i", type, result.FetchInt(1), result.FetchInt(2), result.FetchInt(3), result.FetchInt(4));
	}
}

public Action Feature_CommandExport(int client, int args)
{
	if(!gDatabaseReady || gDatabase == null)
	{
		ReplyToCommand(client, "[CaseOpener] Database is unavailable.");
		return Plugin_Handled;
	}
	if(gFeatureExportFile != null)
	{
		ReplyToCommand(client, "[CaseOpener] Export is already running.");
		return Plugin_Handled;
	}
	char format[8], path[PLATFORM_MAX_PATH], query[512];
	GetCmdArg(1, format, sizeof(format));
	if(!StrEqual(format, "json", false) && !StrEqual(format, "csv", false))
	{
		ReplyToCommand(client, "Usage: sm_case_export <json|csv>");
		return Plugin_Handled;
	}
	gFeatureExportMode = StrEqual(format, "json", false) ? 1 : 2;
	BuildPath(Path_SM, path, sizeof(path), "data/CaseOpener/case_stats.%s", format);
	char directory[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, directory, sizeof(directory), "data/CaseOpener");
	CreateDirectory(directory, 511);
	gFeatureExportFile = OpenFile(path, "w");
	if(gFeatureExportFile == null)
	{
		ReplyToCommand(client, "[CaseOpener] Cannot open export file.");
		return Plugin_Handled;
	}
	gFeatureExportAdmin = GetClientUserId(client);
	gFeatureExportFirst = true;
	if(gFeatureExportMode == 1)
		gFeatureExportFile.WriteLine("[");
	else
		gFeatureExportFile.WriteLine("steam,name,case_type,last_open,streak,extra_cases,opened");
	SQL_FormatQuery(gDatabase, query, sizeof(query), "SELECT `steam`,`name`,`case_type`,`last_open`,`streak`,`extra_cases`,`opened` FROM `opener_case_progress` LEFT JOIN `opener_base` USING (`steam`) ORDER BY `opened` DESC");
	gDatabase.Query(Feature_SQLExport, query);
	ReplyToCommand(client, "[CaseOpener] Export started: %s", path);
	return Plugin_Handled;
}

public void Feature_SQLExport(Database db, DBResultSet result, const char[] error, any data)
{
	if(gFeatureExportFile == null)
		return;
	if(error[0] || result == null)
	{
		LogError("[CASEOPENER] Export failed: %s", error);
		delete gFeatureExportFile;
		gFeatureExportFile = null;
		return;
	}

	char steam[32], name[128], type[FEATURE_MAX_ID], escapedName[256], escapedSteam[64], escapedType[64];
	for(int i = 0; i < result.RowCount; i++)
	{
		if(!result.FetchRow())
			break;
		result.FetchString(0, steam, sizeof(steam));
		result.FetchString(1, name, sizeof(name));
		result.FetchString(2, type, sizeof(type));
		if(gFeatureExportMode == 1)
		{
			Feature_JsonEscape(steam, escapedSteam, sizeof(escapedSteam));
			Feature_JsonEscape(name, escapedName, sizeof(escapedName));
			Feature_JsonEscape(type, escapedType, sizeof(escapedType));
			if(!gFeatureExportFirst)
				gFeatureExportFile.WriteLine(",");
			gFeatureExportFirst = false;
			gFeatureExportFile.WriteLine("  {\"steam\":\"%s\",\"name\":\"%s\",\"case_type\":\"%s\",\"last_open\":%i,\"streak\":%i,\"extra_cases\":%i,\"opened\":%i}", escapedSteam, escapedName, escapedType, result.FetchInt(3), result.FetchInt(4), result.FetchInt(5), result.FetchInt(6));
		}
		else
		{
			Feature_CsvEscape(steam, escapedSteam, sizeof(escapedSteam));
			Feature_CsvEscape(name, escapedName, sizeof(escapedName));
			Feature_CsvEscape(type, escapedType, sizeof(escapedType));
			gFeatureExportFile.WriteLine("%s,%s,%s,%i,%i,%i,%i", escapedSteam, escapedName, escapedType, result.FetchInt(3), result.FetchInt(4), result.FetchInt(5), result.FetchInt(6));
		}
	}
	if(gFeatureExportMode == 1)
		gFeatureExportFile.WriteLine("]");
	delete gFeatureExportFile;
	gFeatureExportFile = null;
	int admin = GetClientOfUserId(gFeatureExportAdmin);
	if(IsValidHumanClient(admin))
		ReplyToCommand(admin, "[CaseOpener] Export completed.");
}

void Feature_JsonEscape(const char[] input, char[] output, int maxlen)
{
	int position = 0;
	for(int i = 0; input[i] != '\0' && position < maxlen - 1; i++)
	{
		if((input[i] == '"' || input[i] == '\\') && position < maxlen - 2)
			output[position++] = '\\';
		output[position++] = input[i];
	}
	output[position] = '\0';
}

void Feature_CsvEscape(const char[] input, char[] output, int maxlen)
{
	int position = 0;
	if(position < maxlen - 1)
		output[position++] = '"';
	for(int i = 0; input[i] != '\0' && position < maxlen - 2; i++)
	{
		if(input[i] == '"' && position < maxlen - 3)
			output[position++] = '"';
		output[position++] = input[i];
	}
	if(position < maxlen - 1)
		output[position++] = '"';
	output[position] = '\0';
}

public void OnPluginEnd()
{
	if(gFeatureExportFile != null)
		delete gFeatureExportFile;
	if(gFeatureKv != null)
		delete gFeatureKv;
}
