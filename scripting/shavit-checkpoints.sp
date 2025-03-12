/*
 * shavit's Timer - Checkpoints
 * by: shavit, kidfearless, Nairda, GAMMA CASE, rumour, rtldg, sh4hrazad, Ciallo-Ani, OliviaMourning, Nuko, yupi2, dez I愛D (Restore & SaveGame)
 *
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#include <sourcemod>
#include <convar_class>
#include <clientprefs>
#include <dhooks>

#include <shavit/core>
#include <shavit/checkpoints>
#include <shavit/zones>
#include <shavit/physicsuntouch>

// SaveGame
#include <pc>
#include <savegame-file>
// `SaveGame

#undef REQUIRE_PLUGIN
#include <shavit/replay-recorder>
#include <shavit/replay-playback>
#include <eventqueuefix>

#pragma newdecls required
#pragma semicolon 1

#define DEBUG 0

#define CP_ANGLES				(1 << 0)
#define CP_VELOCITY				(1 << 1)

#define CP_DEFAULT				(CP_ANGLES|CP_VELOCITY)

enum TimerAction
{
	TimerAction_OnStart,
	TimerAction_OnTeleport
}

enum struct persistent_data_t
{
	int iSteamID;
	int iDisconnectTime;
	int iTimesTeleported;
	ArrayList aCheckpoints;
	int iCurrentCheckpoint;
	cp_cache_t cpcache;
}

char gS_Map[PLATFORM_MAX_PATH];
char gS_PreviousMap[PLATFORM_MAX_PATH];
EngineVersion gEV_Type = Engine_Unknown;
bool gB_Late = false;

Convar gCV_Checkpoints = null;
Convar gCV_UseOthers = null;
Convar gCV_RestoreStates = null;
Convar gCV_PersistData = null;
Convar gCV_MaxCP = null;
Convar gCV_MaxCP_Segmented = null;

Handle gH_CheckpointsCookie = null;

Handle gH_Forwards_OnSave = null;
Handle gH_Forwards_OnTeleport = null;
Handle gH_Forwards_OnSavePre = null;
Handle gH_Forwards_OnTeleportPre = null;
Handle gH_Forwards_OnDelete = null;
Handle gH_Forwards_OnCheckpointMenuMade = null;
Handle gH_Forwards_OnCheckpointMenuSelect = null;
Handle gH_Forwards_OnCheckpointCacheSaved = null;
Handle gH_Forwards_OnCheckpointCacheLoaded = null;

chatstrings_t gS_ChatStrings;

int gI_Style[MAXPLAYERS+1];

ArrayList gA_Checkpoints[MAXPLAYERS+1];
int gI_CurrentCheckpoint[MAXPLAYERS+1];
int gI_TimesTeleported[MAXPLAYERS+1];
bool gB_InCheckpointMenu[MAXPLAYERS+1];

int gI_UsingCheckpointsOwner[MAXPLAYERS+1]; // 0 = use player's own checkpoints

int gI_CheckpointsSettings[MAXPLAYERS+1];

// save states
bool gB_SaveStates[MAXPLAYERS+1]; // whether we have data for when player rejoins from spec
ArrayList gA_PersistentData = null;

bool gB_Eventqueuefix = false;
bool gB_ReplayRecorder = false;

DynamicHook gH_CommitSuicide = null;
float gF_NextSuicide[MAXPLAYERS+1];

#if MORE_LADDER_CHECKPOINT_STUFF
int gI_Offset_m_lastStandingPos = 0;
int gI_Offset_m_ladderSurpressionTimer = 0;
int gI_Offset_m_lastLadderNormal = 0;
int gI_Offset_m_lastLadderPos = 0;
#endif

// SaveGame
#define AVAILABLE_SLOTS 9

int gI_AvailableSlots = AVAILABLE_SLOTS;
char gS_SaveGameClientFolder[MAXPLAYERS + 1][PLATFORM_MAX_PATH];
float gF_LastTargetPC[MAXPLAYERS + 1];
bool gB_IsEmptySlot[MAXPLAYERS + 1][AVAILABLE_SLOTS];
int gI_SaveGameEnabled[MAXPLAYERS + 1];
savegame_header_t gA_SaveGameHeader[MAXPLAYERS + 1][AVAILABLE_SLOTS];
// `SaveGame

public Plugin myinfo =
{
	name = "[shavit] Checkpoints",
	author = "shavit, KiD Fearless, Nairda, GAMMA CASE, rumour, rtldg, sh4hrazad, Ciallo-Ani, OliviaMourning, Nuko, yupi2, dez I愛D (Restore & SaveGame)",
	description = "Checkpoints for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_GetCheckpoint", Native_GetCheckpoint);
	CreateNative("Shavit_SetCheckpoint", Native_SetCheckpoint);
	CreateNative("Shavit_ClearCheckpoints", Native_ClearCheckpoints);
	CreateNative("Shavit_TeleportToCheckpoint", Native_TeleportToCheckpoint);
	CreateNative("Shavit_GetTotalCheckpoints", Native_GetTotalCheckpoints);
	CreateNative("Shavit_SaveCheckpoint", Native_SaveCheckpoint);
	CreateNative("Shavit_GetCurrentCheckpoint", Native_GetCurrentCheckpoint);
	CreateNative("Shavit_SetCurrentCheckpoint", Native_SetCurrentCheckpoint);
	CreateNative("Shavit_GetTimesTeleported", Native_GetTimesTeleported);
	CreateNative("Shavit_SetTimesTeleported", Native_SetTimesTeleported);
	CreateNative("Shavit_HasSavestate", Native_HasSavestate);
	CreateNative("Shavit_LoadCheckpointCache", Native_LoadCheckpointCache);
	CreateNative("Shavit_SaveCheckpointCache", Native_SaveCheckpointCache);

	// Restore
	CreateNative("Shavit_PersistData", Native_PersistData);
	// `Restore

	if (!FileExists("cfg/sourcemod/plugin.shavit-checkpoints.cfg") && FileExists("cfg/sourcemod/plugin.shavit-misc.cfg"))
	{
		File source = OpenFile("cfg/sourcemod/plugin.shavit-misc.cfg", "r");
		File destination = OpenFile("cfg/sourcemod/plugin.shavit-checkpoints.cfg", "w");

		if (source && destination)
		{
			char line[512];

			while (!source.EndOfFile() && source.ReadLine(line, sizeof(line)))
			{
				ReplaceString(line, sizeof(line), "_misc_", "_checkpoints_");
				destination.WriteLine("%s", line);
			}
		}

		delete destination;
		delete source;
	}

	RegPluginLibrary("shavit-checkpoints");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	gH_Forwards_OnSave = CreateGlobalForward("Shavit_OnSave", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnTeleport = CreateGlobalForward("Shavit_OnTeleport", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnSavePre = CreateGlobalForward("Shavit_OnSavePre", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnTeleportPre = CreateGlobalForward("Shavit_OnTeleportPre", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnCheckpointMenuMade = CreateGlobalForward("Shavit_OnCheckpointMenuMade", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnCheckpointMenuSelect = CreateGlobalForward("Shavit_OnCheckpointMenuSelect", ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnDelete = CreateGlobalForward("Shavit_OnDelete", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnCheckpointCacheSaved = CreateGlobalForward("Shavit_OnCheckpointCacheSaved", ET_Ignore, Param_Cell, Param_Array, Param_Cell, Param_Cell);
	gH_Forwards_OnCheckpointCacheLoaded = CreateGlobalForward("Shavit_OnCheckpointCacheLoaded", ET_Ignore, Param_Cell, Param_Array, Param_Cell);

	gEV_Type = GetEngineVersion();

	// Restore
	RegConsoleCmd("sm_restore", Command_Restore, "Restore");
	// `Restore

	// SaveGame
	RegConsoleCmd("sm_savegame", Command_Savegame, "SaveGame");
	RegConsoleCmd("sm_sg", Command_Savegame, "SaveGame");

	AddCommandListener(CommandListener_Stop, "sm_stop");
	// `SaveGame

	RegConsoleCmd("sm_cpmenu", Command_Checkpoints, "Opens the checkpoints menu.");
	RegConsoleCmd("sm_cp", Command_Checkpoints, "Opens the checkpoints menu. Alias for sm_cpmenu.");
	RegConsoleCmd("sm_checkpoint", Command_Checkpoints, "Opens the checkpoints menu. Alias for sm_cpmenu.");
	RegConsoleCmd("sm_checkpoints", Command_Checkpoints, "Opens the checkpoints menu. Alias for sm_cpmenu.");
	RegConsoleCmd("sm_save", Command_Save, "Saves a checkpoint.");
	RegConsoleCmd("sm_tele", Command_Tele, "Teleports to a checkpoint. Usage: sm_tele [number]");
	RegConsoleCmd("sm_teleport", Command_Tele, "Teleports to a checkpoint. Usage: sm_tele [number]");
	RegConsoleCmd("sm_prevcp", Command_PrevCheckpoint, "Selects the previous checkpoint.");
	RegConsoleCmd("sm_nextcp", Command_NextCheckpoint, "Selects the next checkpoint.");
	RegConsoleCmd("sm_deletecp", Command_DeleteCheckpoint, "Deletes the current checkpoint.");
	gH_CheckpointsCookie = RegClientCookie("shavit_checkpoints", "Checkpoints settings", CookieAccess_Protected);
	gA_PersistentData = new ArrayList(sizeof(persistent_data_t));

	AddCommandListener(Command_Jointeam, "jointeam");

	HookEvent("player_spawn", Player_Spawn);
	HookEvent("player_team", Player_Notifications, EventHookMode_Pre);
	HookEvent("player_death", Player_Notifications, EventHookMode_Pre);

	LoadTranslations("common.phrases");
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-misc.phrases");

	gCV_Checkpoints = new Convar("shavit_checkpoints_enabled", "1", "Allow players to save and teleport to checkpoints.", 0, true, 0.0, true, 1.0);
	gCV_UseOthers = new Convar("shavit_checkpoints_useothers", "1", "Allow players to use or duplicate another player's checkpoints.", 0, true, 0.0, true, 1.0);
	gCV_RestoreStates = new Convar("shavit_checkpoints_restorestates", "1", "Save the players' timer/position etc.. when they die/change teams,\nand load the data when they spawn?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_MaxCP = new Convar("shavit_checkpoints_maxcp", "1000", "Maximum amount of checkpoints.\nNote: Very high values will result in high memory usage!", 0, true, 1.0, true, 10000.0);
	gCV_MaxCP_Segmented = new Convar("shavit_checkpoints_maxcp_seg", "10", "Maximum amount of segmented checkpoints. Make this less or equal to shavit_checkpoints_maxcp.\nNote: Very high values will result in HUGE memory usage! Segmented checkpoints contain frame data!", 0, true, 1.0, true, 50.0);
	gCV_PersistData = new Convar("shavit_checkpoints_persistdata", "600", "How long to persist timer data for disconnected users in seconds?\n-1 - Until map change\n0 - Disabled", 0, true, -1.0);

	Convar.AutoExecConfig();

	CreateTimer(10.0, Timer_Cron, 0, TIMER_REPEAT);
	CreateTimer(0.5, Timer_PersistCPMenu, 0, TIMER_REPEAT);

	LoadDHooks();

	// modules
	gB_Eventqueuefix = LibraryExists("eventqueuefix");
	gB_ReplayRecorder = LibraryExists("shavit-replay-recorder");

	if (gB_Late)
	{
		Shavit_OnChatConfigLoaded();
	}
}

void LoadDHooks()
{
	Handle hGameData = LoadGameConfigFile("shavit.games");

	if (hGameData == null)
	{
		SetFailState("Failed to load shavit gamedata");
	}

	LoadPhysicsUntouch(hGameData);

	if (gEV_Type == Engine_CSS)
	{
#if MORE_LADDER_CHECKPOINT_STUFF
		if ((gI_Offset_m_lastStandingPos = GameConfGetOffset(hGameData, "CCSPlayer::m_lastStandingPos")) == -1)
		{
			SetFailState("Couldn't get the offset for \"CCSPlayer::m_lastStandingPos\"!");
		}

		if ((gI_Offset_m_ladderSurpressionTimer = GameConfGetOffset(hGameData, "CCSPlayer::m_ladderSurpressionTimer")) == -1)
		{
			SetFailState("Couldn't get the offset for \"CCSPlayer::m_ladderSurpressionTimer\"!");
		}

		if ((gI_Offset_m_lastLadderNormal = GameConfGetOffset(hGameData, "CCSPlayer::m_lastLadderNormal")) == -1)
		{
			SetFailState("Couldn't get the offset for \"CCSPlayer::m_lastLadderNormal\"!");
		}

		if ((gI_Offset_m_lastLadderPos = GameConfGetOffset(hGameData, "CCSPlayer::m_lastLadderPos")) == -1)
		{
			SetFailState("Couldn't get the offset for \"CCSPlayer::m_lastLadderPos\"!");
		}
#endif
	}

	delete hGameData;
	hGameData = LoadGameConfigFile("sdktools.games");
	int iOffset;

	if ((iOffset = GameConfGetOffset(hGameData, "CommitSuicide")) == -1)
	{
		SetFailState("Couldn't get the offset for \"CommitSuicide\"!");
	}

	gH_CommitSuicide = new DynamicHook(iOffset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity);
	gH_CommitSuicide.AddParam(HookParamType_Bool);
	gH_CommitSuicide.AddParam(HookParamType_Bool);

	delete hGameData;
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "shavit-replay-recorder"))
	{
		gB_ReplayRecorder = true;
	}
	else if (StrEqual(name, "eventqueuefix"))
	{
		gB_Eventqueuefix = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "shavit-replay-recorder"))
	{
		gB_ReplayRecorder = false;
	}
	else if (StrEqual(name, "eventqueuefix"))
	{
		gB_Eventqueuefix = false;
	}
}

public void OnMapStart()
{
	GetLowercaseMapName(gS_Map);

	// SaveGame
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, PLATFORM_MAX_PATH, "data/savegame");

    if (!DirExists(path) && !CreateDirectory(path, 511))
    {
        SetFailState("Failed to create savegame folder (%s). Make sure you have file permissions", path);
    }
	// `SaveGame

	if (gB_Late)
	{
		gB_Late = false;

		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);

				if (AreClientCookiesCached(i))
				{
					OnClientCookiesCached(i);
					Shavit_OnStyleChanged(i, 0, Shavit_GetBhopStyle(i), Shavit_GetClientTrack(i), false);
				}
			}
		}
	}

	if (!StrEqual(gS_Map, gS_PreviousMap, false))
	{
		int iLength = gA_PersistentData.Length;

		for(int i = iLength - 1; i >= 0; i--)
		{
			persistent_data_t aData;
			gA_PersistentData.GetArray(i, aData);
			DeletePersistentData(i, aData);
		}
	}
}

public void OnMapEnd()
{
	gS_PreviousMap = gS_Map;
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(gS_ChatStrings);
}

public void Shavit_OnPause(int client, int track)
{
	if (!gB_SaveStates[client])
	{
		PersistData(client, false);
	}
}

public void Shavit_OnResume(int client, int track)
{
	if (gB_SaveStates[client])
	{
		// events&outputs won't work properly unless we do this next frame...
		RequestFrame(LoadPersistentData, GetClientSerial(client));
	}
}

// public void Shavit_OnStop(int client, int track)
// {
// 	if (gB_SaveStates[client])
// 	{
// 		DeletePersistentDataFromClient(client);
// 	}
// }

public Action Command_Jointeam(int client, const char[] command, int args)
{
	if (!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	if (!gB_SaveStates[client])
	{
		PersistData(client, false);
	}

	return Plugin_Continue;
}

public MRESReturn CBasePlayer__CommitSuicide(int client, DHookParam params)
{
	//bool bExplode = params.Get(1);
	bool bForce = params.Get(2);

	if (IsPlayerAlive(client) && (bForce || gF_NextSuicide[client] <= GetGameTime()))
	{
		gF_NextSuicide[client] = GetGameTime() + 5.0;
		PersistData(client, false);
	}

	return MRES_Ignored;
}

public Action Timer_Cron(Handle timer)
{
	if (gCV_PersistData.IntValue < 0)
	{
		return Plugin_Continue;
	}

	int iTime = GetTime();
	int iLength = gA_PersistentData.Length;

	for(int i = iLength - 1; i >= 0; i--)
	{
		persistent_data_t aData;
		gA_PersistentData.GetArray(i, aData);

		if(aData.iDisconnectTime && (iTime - aData.iDisconnectTime >= gCV_PersistData.IntValue))
		{
			DeletePersistentData(i, aData);
		}
	}

	return Plugin_Continue;
}

public Action Timer_PersistCPMenu(Handle timer)
{
	if (!gCV_Checkpoints.BoolValue)
	{
		return Plugin_Continue;
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && IsPlayerAlive(i) && !IsFakeClient(i) && ShouldReopenCheckpointMenu(i))
		{
			OpenCPMenu(i);
		}
	}

	return Plugin_Continue;
}

public void OnClientCookiesCached(int client)
{
	if (IsFakeClient(client))
	{
		return;
	}

	char sSetting[8];
	GetClientCookie(client, gH_CheckpointsCookie, sSetting, sizeof(sSetting));

	if (strlen(sSetting) == 0)
	{
		IntToString(CP_DEFAULT, sSetting, 8);
		SetClientCookie(client, gH_CheckpointsCookie, sSetting);
		gI_CheckpointsSettings[client] = CP_DEFAULT;
	}
	else
	{
		gI_CheckpointsSettings[client] = StringToInt(sSetting);
	}

	// TODO: BAD
	gI_Style[client] = Shavit_GetBhopStyle(client);
}

public void OnClientPutInServer(int client)
{
	gF_NextSuicide[client] = GetGameTime();

	if (IsFakeClient(client))
	{
		return;
	}

	// SaveGame
	BuildPath(Path_SM, gS_SaveGameClientFolder[client], PLATFORM_MAX_PATH, "data/savegame/%d", GetSteamAccountID(client));
	SaveGameFile_CreateDir(gS_SaveGameClientFolder[client]);

	File file;
	savegame_header_t header;
	char path[PLATFORM_MAX_PATH];
	for (int i = 0; i < gI_AvailableSlots; i++)
	{
		FormatEx(path, PLATFORM_MAX_PATH, "%s/%d", gS_SaveGameClientFolder[client], i);
		file = SaveGameFile_ReadHeader(path, header);
		gB_IsEmptySlot[client][i] = file == null;
		gA_SaveGameHeader[client][i] = header;
	}

	delete file;

	gI_SaveGameEnabled[client] = -1;
	// `SaveGame

	if (gH_CommitSuicide != null)
	{
		gH_CommitSuicide.HookEntity(Hook_Pre,  client, CBasePlayer__CommitSuicide);
	}

	if (!AreClientCookiesCached(client))
	{
		gI_Style[client] = Shavit_GetBhopStyle(client);
		gI_CheckpointsSettings[client] = CP_DEFAULT;
	}

	if(gA_Checkpoints[client] == null)
	{
		gA_Checkpoints[client] = new ArrayList(sizeof(cp_cache_t));
	}
	else
	{
		ResetCheckpoints(client);
	}

	gB_SaveStates[client] = false;
	gI_UsingCheckpointsOwner[client] = 0;
}

public void OnClientDisconnect(int client)
{
	if (IsFakeClient(client))
	{
		return;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (gI_UsingCheckpointsOwner[i] == client)
		{
			gI_UsingCheckpointsOwner[i] = 0;
			gI_CurrentCheckpoint[i] = gA_Checkpoints[i].Length;
		}
	}

	gI_UsingCheckpointsOwner[client] = 0;

	// SaveGame
	if (gI_SaveGameEnabled[client] != -1)
	{
		if (CanRestore(client))
		{
			gF_LastTargetPC[client] = Shavit_GetTargetPC(client);
			PersistData(client, false);
		}

		SaveGame_Save(client, gI_SaveGameEnabled[client]);
		// Shavit_PrintToChat(client, "Your progress has been saved to slot %s%d", gS_ChatStrings.sVariable, gI_SaveGameEnabled[client] + 1);
		gI_SaveGameEnabled[client] = -1;
	}
	// `SaveGame
	else
	{
		PersistData(client, true);
	}

	// if data wasn't persisted, then we have checkpoints to reset...
	ResetCheckpoints(client);
	delete gA_Checkpoints[client];
}



void DeletePersistentDataFromClient(int client)
{
	persistent_data_t aData;
	int iIndex = FindPersistentData(client, aData);

	if (iIndex != -1)
	{
		DeletePersistentData(iIndex, aData);
	}

	gB_SaveStates[client] = false;
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
	gI_Style[client] = newstyle;

	bool bSegmented = Shavit_GetStyleSettingBool(newstyle, "segments");
	bool bKzcheckpoints = Shavit_GetStyleSettingBool(newstyle, "kzcheckpoints");

	if (gB_SaveStates[client] && manual)
	{
		DeletePersistentDataFromClient(client);
	}

	if (bSegmented || bKzcheckpoints)
	{
		// Gammacase somehow had this callback fire before OnClientPutInServer.
		// OnClientPutInServer will still fire but we need a valid arraylist in the mean time.
		if(gA_Checkpoints[client] == null)
		{
			gA_Checkpoints[client] = new ArrayList(sizeof(cp_cache_t));
		}

		if (bKzcheckpoints)
		{
			gI_UsingCheckpointsOwner[client] = 0;
		}

		OpenCheckpointsMenu(client);

		if (!Shavit_GetStyleSettingBool(oldstyle, "segments") && !Shavit_GetStyleSettingBool(oldstyle, "kzcheckpoints"))
		{
			Shavit_PrintToChat(client, "%T", "MiscSegmentedCommand", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
		}
	}
}

public Action Shavit_OnStart(int client)
{
	gI_TimesTeleported[client] = 0;

	// shavit-kz
	if(Shavit_GetStyleSettingBool(gI_Style[client], "kzcheckpoints"))
	{
		ResetCheckpoints(client);
		UpdateKZStyle(client, TimerAction_OnStart);
	}

	return Plugin_Continue;
}

public void Shavit_OnRestart(int client, int track)
{
	if(gB_InCheckpointMenu[client] &&
		Shavit_GetStyleSettingInt(gI_Style[client], "kzcheckpoints") &&
		GetClientMenu(client, null) == MenuSource_None &&
		IsPlayerAlive(client) && GetClientTeam(client) >= 2)
	{
		OpenCPMenu(client);
	}
}

public bool Shavit_OnStopPre(int client, int track)
{
	// SaveGame
	if (gI_SaveGameEnabled[client] != -1)
	{
		if (CanRestore(client))
		{
			gF_LastTargetPC[client] = Shavit_GetTargetPC(client);
			PersistData(client, false);
		}

		SaveGame_Save(client, gI_SaveGameEnabled[client]);
		Shavit_PrintToChat(client, "Your progress has been saved to slot %s%d", gS_ChatStrings.sVariable, gI_SaveGameEnabled[client] + 1);
		gI_SaveGameEnabled[client] = -1;
	}
	// `SaveGame

	return true;
}

public void Player_Spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (IsFakeClient(client))
	{
		return;
	}

	// SaveGame
	// AdminId admID;
	// AdminFlag flag;
	// if ((admID = GetUserAdmin(client)) != INVALID_ADMIN_ID)
	if (GetUserAdmin(client) != INVALID_ADMIN_ID)
	{
		// if (GetAdminFlag(admID, flag) && (flag == Admin_RCON))
		// {
			Shavit_PrintToChat(client, "%s`SAVEGAME:", gS_ChatStrings.sWarning);
			Shavit_PrintToChat(client, "This plugin is a %sraw version%s and has not been thoroughly tested. It is just an attempt to implement a cool savegame plugin similar to the one on the FuckitHops bhop server. Therefore, use this plugin only on your LAN server. If you are a server owner and want to enable this plugin, make sure to test it properly and refine/optimize the necessary functionality.", gS_ChatStrings.sWarning, gS_ChatStrings.sText);
			Shavit_PrintToChat(client, "%sNOTE:%s For replay frames to be saved correctly, your server needs a good disk capable of fast read and write operations.", gS_ChatStrings.sWarning, gS_ChatStrings.sText);
			Shavit_PrintToChat(client, "Additionally, the commands %s!restore%s and %s!pc%s have been implemented", gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
			Shavit_PrintToChat(client, "%sNOTE:%s The plugin has also not been tested after the 18.02.2025 update, so testing and recompilation with the latest bhoptimer commits are required.", gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		// }
	}
	// `SaveGame

	int serial = GetClientSerial(client);

	if (gB_SaveStates[client])
	{
		if(gCV_RestoreStates.BoolValue)
		{
			// events&outputs won't work properly unless we do this next frame...
			RequestFrame(LoadPersistentData, serial);

			// SaveGame
			if (gI_SaveGameEnabled[client] == -1)
			{
				Shavit_PrintToChat(client, "Autosave is %sdisabled%s. Use %s!savegame%s to save your progress.", gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
			}
			// `SaveGame
		}
	}
	else
	{
		persistent_data_t aData;
		int iIndex = FindPersistentData(client, aData);

		if (iIndex != -1)
		{
			gB_SaveStates[client] = true;
			// events&outputs won't work properly unless we do this next frame...
			RequestFrame(LoadPersistentData, serial);
		}
	}

	// refreshes kz cp menu if there is nothing open
	if (gB_InCheckpointMenu[client] &&
		Shavit_GetStyleSettingInt(gI_Style[client], "kzcheckpoints") &&
		GetClientMenu(client, null) == MenuSource_None &&
		IsPlayerAlive(client) && GetClientTeam(client) >= 2)
	{
		OpenCPMenu(client);
	}
}

public Action Player_Notifications(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (!IsFakeClient(client))
	{
		if (!gB_SaveStates[client])
		{
			PersistData(client, false);
		}
	}

	return Plugin_Continue;
}

bool CanSegment(int client)
{
	return Shavit_GetStyleSettingBool(gI_Style[client], "segments");
}

int GetMaxCPs(int client)
{
	return CanSegment(client)? gCV_MaxCP_Segmented.IntValue:gCV_MaxCP.IntValue;
}

int FindPersistentData(int client, persistent_data_t aData)
{
	int iSteamID;

	if((iSteamID = GetSteamAccountID(client)) != 0)
	{
		int index = gA_PersistentData.FindValue(iSteamID, 0);

		if (index != -1)
		{
			gA_PersistentData.GetArray(index, aData);
			return index;
		}
	}

	return -1;
}

void PersistData(int client, bool disconnected)
{
	if(!IsClientInGame(client) ||
		(!IsPlayerAlive(client) && !disconnected) ||
		(!IsPlayerAlive(client) && disconnected && !gB_SaveStates[client]) ||
		GetSteamAccountID(client) == 0 ||
		//Shavit_GetTimerStatus(client) == Timer_Stopped ||
		(!gCV_RestoreStates.BoolValue && !disconnected) ||
		(gCV_PersistData.IntValue == 0 && disconnected))
	{
		return;
	}

	persistent_data_t aData;
	int iIndex = FindPersistentData(client, aData);

	aData.iSteamID = GetSteamAccountID(client);
	aData.iTimesTeleported = gI_TimesTeleported[client];

	if (disconnected)
	{
		aData.iDisconnectTime = GetTime();
		aData.iCurrentCheckpoint = gI_CurrentCheckpoint[client] > gA_Checkpoints[client].Length ? gA_Checkpoints[client].Length : gI_CurrentCheckpoint[client];
		aData.aCheckpoints = gA_Checkpoints[client];
		gA_Checkpoints[client] = null;

		if (gB_ReplayRecorder && aData.cpcache.aFrames == null)
		{
			aData.cpcache.aFrames = Shavit_GetReplayData(client, true);
			aData.cpcache.iPreFrames = Shavit_GetPlayerPreFrames(client);
		}
	}
	else
	{
		aData.iDisconnectTime = 0;
	}

	if (!gB_SaveStates[client])
	{
		SaveCheckpointCache(client, client, aData.cpcache, -1, INVALID_HANDLE);
	}

	gB_SaveStates[client] = true;

	if (iIndex == -1)
	{
		gA_PersistentData.PushArray(aData);
	}
	else
	{
		gA_PersistentData.SetArray(iIndex, aData);
	}
}

void DeletePersistentData(int index, persistent_data_t data)
{
	gA_PersistentData.Erase(index);
	DeleteCheckpointCache(data.cpcache);
	DeleteCheckpointCacheList(data.aCheckpoints);
	delete data.aCheckpoints;
}

void LoadPersistentData(int serial)
{
	int client = GetClientFromSerial(serial);

	if(client == 0 ||
		GetSteamAccountID(client) == 0 ||
		GetClientTeam(client) < 2 ||
		!IsPlayerAlive(client))
	{
		return;
	}

	persistent_data_t aData;
	int iIndex = FindPersistentData(client, aData);

	if (iIndex == -1)
	{
		return;
	}

	gB_SaveStates[client] = false;

	bool bKzcheckpoints = Shavit_GetStyleSettingBool(aData.cpcache.aSnapshot.bsStyle, "kzcheckpoints");

	if (LoadCheckpointCache(client, aData.cpcache, -1, bKzcheckpoints))
	{
		gI_TimesTeleported[client] = aData.iTimesTeleported;

		if (aData.aCheckpoints != null)
		{
			DeleteCheckpointCacheList(gA_Checkpoints[client]);
			delete gA_Checkpoints[client];
			gI_CurrentCheckpoint[client] = aData.iCurrentCheckpoint;
			gA_Checkpoints[client] = aData.aCheckpoints;
			aData.aCheckpoints = null;

			if (gA_Checkpoints[client].Length > 0)
			{
				OpenCheckpointsMenu(client);
			}
		}
	}

	DeletePersistentData(iIndex, aData);
}

void DeleteCheckpointCache(cp_cache_t cache)
{
	delete cache.aFrames;
	delete cache.aEvents;
	delete cache.aOutputWaits;
	delete cache.customdata;
}

void DeleteCheckpointCacheList(ArrayList cps, int client_for_callback=0)
{
	if (cps != null)
	{
		for (int i = cps.Length - 1; i >= 0; i--)
		{
			if (client_for_callback)
			{
				Call_StartForward(gH_Forwards_OnDelete);
				Call_PushCell(client_for_callback);
				Call_PushCell(i+1);
				Call_PushCell(true);
				Call_Finish();
			}

			cp_cache_t cache;
			cps.GetArray(i, cache);
			DeleteCheckpointCache(cache);
		}

		cps.Clear();
	}
}

void ResetCheckpoints(int client)
{
	gI_CurrentCheckpoint[client] = 0;
	DeleteCheckpointCacheList(gA_Checkpoints[client], client);
}

bool ShouldReopenCheckpointMenu(int client)
{
	return gB_InCheckpointMenu[client];
}

public Action Command_Checkpoints(int client, int args)
{
	if(client == 0)
	{
		ReplyToCommand(client, "This command may be only performed in-game.");

		return Plugin_Handled;
	}

	if (!gA_Checkpoints[client]) // probably got here from another plugin doing `FakeClientCommandEx(param1, "sm_checkpoints");` too early or too late
	{
		return Plugin_Handled;
	}

	return OpenCheckpointsMenu(client);
}

public Action Command_Save(int client, int args)
{
	if(client == 0)
	{
		ReplyToCommand(client, "This command may be only performed in-game.");

		return Plugin_Handled;
	}

	bool bSegmenting = CanSegment(client);

	if(!gCV_Checkpoints.BoolValue && !bSegmenting)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if(SaveCheckpoint(client))
	{
		Shavit_PrintToChat(client, "%T", "MiscCheckpointsSaved", client, gI_CurrentCheckpoint[client], gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		if (ShouldReopenCheckpointMenu(client))
		{
			OpenCheckpointsMenu(client);
		}
	}

	return Plugin_Handled;
}

public Action Command_Tele(int client, int args)
{
	if(client == 0)
	{
		ReplyToCommand(client, "This command may be only performed in-game.");

		return Plugin_Handled;
	}

	if(!gCV_Checkpoints.BoolValue)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	int index = gI_CurrentCheckpoint[client];

	if(args > 0)
	{
		char arg[8];
		GetCmdArg(1, arg, sizeof(arg));

		int parsed = StringToInt(arg);

		if(0 < parsed <= gCV_MaxCP.IntValue)
		{
			index = parsed;
		}
	}

	TeleportToCheckpoint(client, index, true, client);

	return Plugin_Handled;
}

public Action Command_PrevCheckpoint(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "This command may be only performed in-game.");
		return Plugin_Handled;
	}

	if (!gCV_Checkpoints.BoolValue)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		return Plugin_Handled;
	}

	if (gI_CurrentCheckpoint[client] > 1)
	{
		gI_CurrentCheckpoint[client]--;

		if (ShouldReopenCheckpointMenu(client))
		{
			OpenCheckpointsMenu(client);
		}
	}

	return Plugin_Handled;
}

public Action Command_NextCheckpoint(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "This command may be only performed in-game.");
		return Plugin_Handled;
	}

	if (!gCV_Checkpoints.BoolValue)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		return Plugin_Handled;
	}

	if (gI_CurrentCheckpoint[client] < gA_Checkpoints[client].Length)
	{
		gI_CurrentCheckpoint[client]++;

		if (ShouldReopenCheckpointMenu(client))
		{
			OpenCheckpointsMenu(client);
		}
	}

	return Plugin_Handled;
}

public Action Command_DeleteCheckpoint(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "This command may be only performed in-game.");
		return Plugin_Handled;
	}

	if (!gCV_Checkpoints.BoolValue)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		return Plugin_Handled;
	}

	if (DeleteCheckpoint(client, gI_CurrentCheckpoint[client]))
	{
		if (gI_CurrentCheckpoint[client] > gA_Checkpoints[client].Length)
		{
			gI_CurrentCheckpoint[client] = gA_Checkpoints[client].Length;
		}

		if (ShouldReopenCheckpointMenu(client))
		{
			OpenCheckpointsMenu(client);
		}
	}

	return Plugin_Handled;
}

public Action OpenCheckpointsMenu(int client)
{
	OpenCPMenu(client);

	return Plugin_Handled;
}

void OpenCPMenu(int client)
{
	bool bSegmented = CanSegment(client);
	bool bKzcheckpoints = Shavit_GetStyleSettingBool(gI_Style[client], "kzcheckpoints");

	if(!gCV_Checkpoints.BoolValue && !bSegmented && !bKzcheckpoints)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return;
	}

	int iUsingOwner = GetUsingCheckpointsOwner(client);

	if (gI_CurrentCheckpoint[client] > gA_Checkpoints[iUsingOwner].Length)
	{
		gI_CurrentCheckpoint[client] = gA_Checkpoints[iUsingOwner].Length;
	}

	if (gI_CurrentCheckpoint[client] == 0 && gA_Checkpoints[iUsingOwner].Length != 0)
	{
		gI_CurrentCheckpoint[client] = 1;
	}

	Menu menu = new Menu(MenuHandler_Checkpoints, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem|MenuAction_Display);

	if (!bSegmented || iUsingOwner != client)
	{
		char sInfo[64];

		FormatEx(sInfo, sizeof(sInfo), "%T\n", "MiscCheckpointMenu", client);

		if (!bKzcheckpoints)
		{
			FormatEx(sInfo, sizeof(sInfo), "%s%T\n ", sInfo, "MiscCheckpointWarning", client);
		}
		else
		{
			StrCat(sInfo, sizeof(sInfo), " ");
		}

		menu.SetTitle(sInfo);
	}
	else
	{
		menu.SetTitle("%T\n ", "MiscCheckpointMenuSegmented", client);
	}

	char sDisplay[64];
	int newcount = gA_Checkpoints[client].Length + 1;
	int maxcps = GetMaxCPs(client);

	FormatEx(sDisplay, 64, "%T", (iUsingOwner == client) ? "MiscCheckpointSave" : "MiscCheckpointDuplicate", client, (newcount > maxcps ? maxcps : newcount), maxcps);
	menu.AddItem("save", sDisplay, (iUsingOwner == client || gA_Checkpoints[iUsingOwner].Length > 0) ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	if (gA_Checkpoints[iUsingOwner].Length > 0)
	{
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointTeleport", client, gI_CurrentCheckpoint[client]);
		menu.AddItem("tele", sDisplay, ITEMDRAW_DEFAULT);
	}
	else
	{
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointTeleport", client, 1);
		menu.AddItem("tele", sDisplay, ITEMDRAW_DISABLED);
	}

	FormatEx(sDisplay, 64, "%T", "MiscCheckpointPrevious", client);
	menu.AddItem("prev", sDisplay, (gI_CurrentCheckpoint[client] > 1) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	FormatEx(sDisplay, 64, "%T%s", "MiscCheckpointNext", client, (bKzcheckpoints) ? "" : "\n ");
	menu.AddItem("next", sDisplay, (gI_CurrentCheckpoint[client] < gA_Checkpoints[iUsingOwner].Length) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);


	if((Shavit_CanPause(client) & CPR_ByConVar) == 0 && bKzcheckpoints)
	{
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointPause", client);
		menu.AddItem("pause", sDisplay);
	}

	// apparently this is the fix
	// menu.AddItem("spacer", "", ITEMDRAW_RAWLINE);

	bool tas_timescale = (Shavit_GetStyleSettingFloat(Shavit_GetBhopStyle(client), "tas_timescale") == -1.0);

	if (tas_timescale)
	{
		float ts = Shavit_GetClientTimescale(client);
		char buf[10];
		PrettyishTimescale(buf, sizeof(buf), ts, 0.1, 1.0, 0.0);
		FormatEx(sDisplay, 64, "--%T\n%T: %s", "Timescale", client, "CurrentTimescale", client, buf);
		menu.AddItem("tsminus", sDisplay, (ts > 0.1) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
		FormatEx(sDisplay, 64, "++%T\n ", "Timescale", client);
		menu.AddItem("tsplus", sDisplay, (ts != 1.0) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}

	if(!bKzcheckpoints)
	{
		if (iUsingOwner == client || !gCV_UseOthers.BoolValue)
		{
			FormatEx(sDisplay, 64, "%T", "MiscCheckpointDeleteCurrent", client);
			menu.AddItem("del", sDisplay, (gA_Checkpoints[client].Length > 0) ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

			FormatEx(sDisplay, 64, "%T", "MiscCheckpointReset", client);
			menu.AddItem("reset", sDisplay);

			if (gCV_UseOthers.BoolValue)
			{
				FormatEx(sDisplay, 64, "%T", "MiscCheckpointUseOthers", client);
				menu.AddItem("useothers", sDisplay);
			}
		}
		else
		{
			FormatEx(sDisplay, 64, "%T", "MiscCheckpointBack", client);
			menu.AddItem("useselfs", sDisplay);
		}

		if(!bSegmented)
		{
			char sInfo[16];
			IntToString(CP_ANGLES, sInfo, 16);
			FormatEx(sDisplay, 64, "%T", "MiscCheckpointUseAngles", client);
			menu.AddItem(sInfo, sDisplay);

			IntToString(CP_VELOCITY, sInfo, 16);
			FormatEx(sDisplay, 64, "%T", "MiscCheckpointUseVelocity", client);
			menu.AddItem(sInfo, sDisplay);
		}
	}

	menu.Pagination = MENU_NO_PAGINATION;
	menu.ExitButton = true;

	Call_StartForward(gH_Forwards_OnCheckpointMenuMade);
	Call_PushCell(client);
	Call_PushCell(bSegmented);
	Call_PushCell(menu);

	Action result = Plugin_Continue;
	Call_Finish(result);

	if(result != Plugin_Continue && result != Plugin_Changed)
	{
		return;
	}

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Checkpoints(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		int iMaxCPs = GetMaxCPs(param1);
		int iCurrent = gI_CurrentCheckpoint[param1];
		int iUsingOwner = GetUsingCheckpointsOwner(param1);

		Call_StartForward(gH_Forwards_OnCheckpointMenuSelect);
		Call_PushCell(param1);
		Call_PushCell(param2);
		Call_PushStringEx(sInfo, 16, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
		Call_PushCell(16);
		Call_PushCell(iCurrent);
		Call_PushCell(iMaxCPs);
		Call_PushCell(iUsingOwner);

		Action result = Plugin_Continue;
		Call_Finish(result);

		if (result == Plugin_Stop)
		{
			gB_InCheckpointMenu[param1] = false;
		}

		if(result != Plugin_Continue)
		{
			return 0;
		}

		if(StrEqual(sInfo, "save"))
		{
			SaveCheckpoint(param1, (iUsingOwner != param1));
		}
		else if(StrEqual(sInfo, "tele"))
		{
			TeleportToCheckpoint(param1, iCurrent, true, iUsingOwner);
		}
		else if(StrEqual(sInfo, "prev"))
		{
			if (gI_CurrentCheckpoint[param1] > 1)
			{
				gI_CurrentCheckpoint[param1]--;
			}
		}
		else if(StrEqual(sInfo, "next"))
		{
			if (gI_CurrentCheckpoint[param1] < gA_Checkpoints[iUsingOwner].Length)
			{
				gI_CurrentCheckpoint[param1]++;
			}
		}
		else if(StrEqual(sInfo, "pause"))
		{
			if(Shavit_CanPause(param1) == 0)
			{
				if(Shavit_IsPaused(param1))
				{
					Shavit_ResumeTimer(param1, true);
				}
				else
				{
					Shavit_PauseTimer(param1);
				}
			}
		}
		else if (StrEqual(sInfo, "useothers"))
		{
			gB_InCheckpointMenu[param1] = false;
			SelectCheckpointsOwnerMenu(param1);

			return 0;
		}
		else if (StrEqual(sInfo, "useselfs"))
		{
			gI_UsingCheckpointsOwner[param1] = 0;
			gI_CurrentCheckpoint[param1] = gA_Checkpoints[param1].Length;
		}
		else if(StrEqual(sInfo, "del"))
		{
			if(DeleteCheckpoint(param1, gI_CurrentCheckpoint[param1]))
			{
				if(gI_CurrentCheckpoint[param1] > gA_Checkpoints[param1].Length)
				{
					gI_CurrentCheckpoint[param1] = gA_Checkpoints[param1].Length;
				}
			}
		}
		else if(StrEqual(sInfo, "reset"))
		{
			gB_InCheckpointMenu[param1] = false;
			ConfirmCheckpointsDeleteMenu(param1);

			return 0;
		}
		else if (StrEqual(sInfo, "tsplus"))
		{
			if (Shavit_GetStyleSettingFloat(Shavit_GetBhopStyle(param1), "tas_timescale") == -1.0)
			{
				FakeClientCommand(param1, "sm_tsplus");
			}
		}
		else if (StrEqual(sInfo, "tsminus"))
		{
			if (Shavit_GetStyleSettingFloat(Shavit_GetBhopStyle(param1), "tas_timescale") == -1.0)
			{
				FakeClientCommand(param1, "sm_tsminus");
			}
		}
		else if(!StrEqual(sInfo, "spacer"))
		{
			char sCookie[8];
			gI_CheckpointsSettings[param1] ^= StringToInt(sInfo);
			IntToString(gI_CheckpointsSettings[param1], sCookie, 16);

			SetClientCookie(param1, gH_CheckpointsCookie, sCookie);
		}

		OpenCheckpointsMenu(param1);
	}
	else if(action == MenuAction_DisplayItem)
	{
		char sInfo[16];
		char sDisplay[64];
		int style = 0;
		menu.GetItem(param2, sInfo, 16, style, sDisplay, 64);

		if(StringToInt(sInfo) == 0)
		{
			return 0;
		}

		Format(sDisplay, 64, "[%s] %s", ((gI_CheckpointsSettings[param1] & StringToInt(sInfo)) > 0)? "x":" ", sDisplay);

		return RedrawMenuItem(sDisplay);
	}
	else if (action == MenuAction_Display)
	{
		gB_InCheckpointMenu[param1] = true;
	}
	else if (action == MenuAction_Cancel)
	{
		gB_InCheckpointMenu[param1] = false;
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void SelectCheckpointsOwnerMenu(int client)
{
	if (!gCV_UseOthers.BoolValue)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		OpenCPMenu(client);
		return;
	}

	Menu hMenu = new Menu(MenuHandler_CheckpointsOwner);
	hMenu.SetTitle("%T\n ", "MiscCheckpointUseOthers", client);

	char sDisplay[64];
	char sInfo[8];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && !IsFakeClient(i) && i != client)
		{
			GetClientName(i, sDisplay, sizeof(sDisplay));
			IntToString(i, sInfo, sizeof(sInfo));

			hMenu.AddItem(sInfo, sDisplay);
		}
	}

	if (hMenu.ItemCount == 0)
	{
		Shavit_PrintToChat(client, "%T", "MiscCheckpointNoOtherPlayers", client);
		delete hMenu;
		OpenCPMenu(client);
		return;
	}

	hMenu.ExitButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_CheckpointsOwner(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		int iUsingOwner = StringToInt(sInfo);

		if (!IsValidClient(iUsingOwner) || !gA_Checkpoints[iUsingOwner])
		{
			Shavit_PrintToChat(param1, "%T", "MiscCheckpointOwnerInvalid", param1);
			SelectCheckpointsOwnerMenu(param1);

			return 0;
		}

		gI_UsingCheckpointsOwner[param1] = iUsingOwner;
		gI_CurrentCheckpoint[param1] = gA_Checkpoints[iUsingOwner].Length;

		OpenCheckpointsMenu(param1);
	}
	else if (action == MenuAction_Cancel)
	{
		OpenCPMenu(param1);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

int GetUsingCheckpointsOwner(int client)
{
	return gI_UsingCheckpointsOwner[client] ? gI_UsingCheckpointsOwner[client] : client;
}

void ConfirmCheckpointsDeleteMenu(int client)
{
	Menu hMenu = new Menu(MenuHandler_CheckpointsDelete);
	hMenu.SetTitle("%T\n ", "ClearCPWarning", client);

	char sDisplay[64];
	FormatEx(sDisplay, 64, "%T", "ClearCPYes", client);
	hMenu.AddItem("yes", sDisplay);

	FormatEx(sDisplay, 64, "%T", "ClearCPNo", client);
	hMenu.AddItem("no", sDisplay);

	hMenu.ExitButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_CheckpointsDelete(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		if(StrEqual(sInfo, "yes"))
		{
			ResetCheckpoints(param1);
		}

		OpenCheckpointsMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

bool SaveCheckpoint(int client, bool duplicate = false)
{
	// ???
	// nairda somehow triggered an error that requires this
	if(!IsValidClient(client))
	{
		return false;
	}

	int target = GetSpectatorTarget(client, client);

	if (target > MaxClients)
	{
		// TODO: Replay_Prop...
		return false;
	}

	if(target == client && !IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "CommandAliveSpectate", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return false;
	}

	if(Shavit_IsPaused(client) || Shavit_IsPaused(target))
	{
		Shavit_PrintToChat(client, "%T", "CommandNoPause", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return false;
	}

	if(Shavit_GetStyleSettingInt(gI_Style[client], "kzcheckpoints"))
	{
		if (client != target)
		{
			Shavit_PrintToChat(client, "%T", "CommandSaveCPKZInvalid", client);
			return false;
		}

		if (!(GetEntityFlags(target) & FL_ONGROUND) && (!Shavit_GetStyleSettingBool(gI_Style[client], "kzcheckpoints_ladders") || GetEntityMoveType(client) != MOVETYPE_LADDER))
		{
			Shavit_PrintToChat(client, "%T", "CommandSaveCPKZInvalid", client);
			return false;
		}

		if(Shavit_InsideZone(client, Zone_Start, -1))
		{
			Shavit_PrintToChat(client, "%T", "CommandSaveCPKZZone", client);
			return false;
		}
	}

	if (IsFakeClient(target))
	{
		int style = Shavit_GetReplayBotStyle(target);
		int track = Shavit_GetReplayBotTrack(target);

		if(style < 0 || track < 0)
		{
			Shavit_PrintToChat(client, "%T", "CommandAliveSpectate", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

			return false;
		}
	}

	int iMaxCPs = GetMaxCPs(client);
	bool overflow = (gA_Checkpoints[client].Length >= iMaxCPs);
	int index = (overflow ? iMaxCPs : gA_Checkpoints[client].Length+1);

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_OnSavePre);
	Call_PushCell(client);
	Call_PushCell(index);
	Call_PushCell(overflow);
	Call_PushCell(duplicate);
	Call_Finish(result);

	if(result != Plugin_Continue)
	{
		return false;
	}

	cp_cache_t cpcache;

	if (!duplicate)
	{
		SaveCheckpointCache(client, target, cpcache, index, INVALID_HANDLE);
		gI_CurrentCheckpoint[client] = index;
	}
	else
	{
		gA_Checkpoints[gI_UsingCheckpointsOwner[client]].GetArray(gI_CurrentCheckpoint[client]-1, cpcache, sizeof(cp_cache_t));

		if (cpcache.aFrames)
			cpcache.aFrames = view_as<ArrayList>(CloneHandle(cpcache.aFrames));
		if (cpcache.aEvents)
			cpcache.aEvents = view_as<ArrayList>(CloneHandle(cpcache.aEvents));
		if (cpcache.aOutputWaits)
			cpcache.aOutputWaits = view_as<ArrayList>(CloneHandle(cpcache.aOutputWaits));
		if (cpcache.customdata)
			cpcache.customdata = view_as<StringMap>(CloneHandle(cpcache.customdata));
	}

	if(overflow)
	{
		DeleteCheckpoint(client, 1, true);

		if (gA_Checkpoints[client].Length >= iMaxCPs)
		{
			gA_Checkpoints[client].ShiftUp(iMaxCPs-1);
			gA_Checkpoints[client].SetArray(iMaxCPs-1, cpcache);
		}
		else
		{
			gA_Checkpoints[client].PushArray(cpcache);
		}
	}
	else
	{
		gA_Checkpoints[client].PushArray(cpcache);
	}

	Call_StartForward(gH_Forwards_OnSave);
	Call_PushCell(client);
	Call_PushCell(index);
	Call_PushCell(overflow);
	Call_PushCell(duplicate);
	Call_Finish();

	return true;
}

void SaveCheckpointCache(int saver, int target, cp_cache_t cpcache, int index, Handle plugin)
{
	GetClientAbsOrigin(target, cpcache.fPosition);
	GetClientEyeAngles(target, cpcache.fAngles);
	GetEntPropVector(target, Prop_Data, "m_vecAbsVelocity", cpcache.fVelocity);

	if (gEV_Type != Engine_TF2)
	{
		GetEntPropVector(target, Prop_Data, "m_vecLadderNormal", cpcache.vecLadderNormal);
	}

	if (gEV_Type == Engine_CSS)
	{
#if MORE_LADDER_CHECKPOINT_STUFF
		GetEntDataVector(target, gI_Offset_m_lastStandingPos, cpcache.m_lastStandingPos);
		cpcache.m_ladderSurpressionTimer[0] = GetEntDataFloat(target, gI_Offset_m_ladderSurpressionTimer + 4);
		cpcache.m_ladderSurpressionTimer[1] = GetEntDataFloat(target, gI_Offset_m_ladderSurpressionTimer + 8) - GetGameTime();
		GetEntDataVector(target, gI_Offset_m_lastLadderNormal, cpcache.m_lastLadderNormal);
		GetEntDataVector(target, gI_Offset_m_lastLadderPos, cpcache.m_lastLadderPos);
#endif
	}
	else if (gEV_Type == Engine_CSGO)
	{
		cpcache.m_bHasWalkMovedSinceLastJump = 0 != GetEntProp(target, Prop_Data, "m_bHasWalkMovedSinceLastJump", 1);
		cpcache.m_ignoreLadderJumpTime = GetEntPropFloat(target, Prop_Data, "m_ignoreLadderJumpTime") - GetGameTime();
	}

	cpcache.iMoveType = GetEntityMoveType(target);
	cpcache.fGravity = GetEntityGravity(target);
	cpcache.fSpeed = GetEntPropFloat(target, Prop_Send, "m_flLaggedMovementValue");

	if(IsFakeClient(target))
	{
		cpcache.iGroundEntity = -1;

		if (cpcache.iMoveType == MOVETYPE_NOCLIP)
		{
			cpcache.iMoveType = MOVETYPE_WALK;
		}
	}
	else
	{
		cpcache.iGroundEntity = GetEntPropEnt(target, Prop_Data, "m_hGroundEntity");

		if (cpcache.iGroundEntity != -1)
		{
			cpcache.iGroundEntity = EntIndexToEntRef(cpcache.iGroundEntity);
		}

		GetEntityClassname(target, cpcache.sClassname, 64);
		GetEntPropString(target, Prop_Data, "m_iName", cpcache.sTargetname, 64);
	}

	if (cpcache.iMoveType == MOVETYPE_NONE || (cpcache.iMoveType == MOVETYPE_NOCLIP && index != -1))
	{
		cpcache.iMoveType = MOVETYPE_WALK;
	}

	cpcache.iFlags = GetEntityFlags(target) & ~(FL_ATCONTROLS|FL_FAKECLIENT);

	if(gEV_Type != Engine_TF2)
	{
		cpcache.fStamina = GetEntPropFloat(target, Prop_Send, "m_flStamina");
		cpcache.bDucked = view_as<bool>(GetEntProp(target, Prop_Send, "m_bDucked"));
		cpcache.bDucking = view_as<bool>(GetEntProp(target, Prop_Send, "m_bDucking"));
	}

	if(gEV_Type == Engine_CSS)
	{
		cpcache.fDucktime = GetEntPropFloat(target, Prop_Send, "m_flDucktime");
	}
	else if(gEV_Type == Engine_CSGO)
	{
		cpcache.fDucktime = GetEntPropFloat(target, Prop_Send, "m_flDuckAmount");
		cpcache.fDuckSpeed = GetEntPropFloat(target, Prop_Send, "m_flDuckSpeed");
	}

	timer_snapshot_t snapshot;

	if(IsFakeClient(target))
	{
		// unfortunately replay bots don't have a snapshot, so we can generate a fake one
		snapshot.bTimerEnabled = true;
		snapshot.fCurrentTime = Shavit_GetReplayTime(target);
		snapshot.bClientPaused = false;
		snapshot.bsStyle = Shavit_GetReplayBotStyle(target);
		snapshot.iJumps = 0;
		snapshot.iStrafes = 0;
		snapshot.iTotalMeasures = 0;
		snapshot.iGoodGains = 0;
		snapshot.fServerTime = GetEngineTime();
		snapshot.iKeyCombo = -1;
		snapshot.iTimerTrack = Shavit_GetReplayBotTrack(target);
		snapshot.fTimescale = 1.0;
		snapshot.fplayer_speedmod = 1.0;

		float ticks = float(Shavit_GetReplayBotCurrentFrame(target) - Shavit_GetReplayCachePreFrames(target));
		float fraction = FloatFraction(ticks);
		snapshot.iFullTicks = RoundFloat(ticks-fraction);
		snapshot.iFractionalTicks = RoundFloat(fraction * 10000.0);

		cpcache.fSpeed = Shavit_GetStyleSettingFloat(snapshot.bsStyle, "timescale") * Shavit_GetStyleSettingFloat(snapshot.bsStyle, "speed");
		ScaleVector(cpcache.fVelocity, 1 / cpcache.fSpeed);
		cpcache.fGravity = Shavit_GetStyleSettingFloat(target, "gravity");
	}
	else
	{
		Shavit_SaveSnapshot(target, snapshot);
	}

	cpcache.aSnapshot = snapshot;
	cpcache.bSegmented = CanSegment(target);

	// if (cpcache.bSegmented && gB_ReplayRecorder && index != -1 && cpcache.aFrames == null)
	// Restore
	if (gB_ReplayRecorder && cpcache.aFrames == null)
	// `Restore
	{
		ArrayList frames = Shavit_GetReplayData(target, false);

		if (plugin != INVALID_HANDLE)
		{
			cpcache.aFrames = view_as<ArrayList>(CloneHandle(frames, plugin));
			delete frames;
		}
		else
		{
			cpcache.aFrames = frames;
		}

		cpcache.iPreFrames = Shavit_GetPlayerPreFrames(target);
	}

	if (gB_Eventqueuefix && !IsFakeClient(target))
	{
		eventpack_t ep;

		if (GetClientEvents(target, ep))
		{
			if (plugin != INVALID_HANDLE)
			{
				cpcache.aEvents = view_as<ArrayList>(CloneHandle(ep.playerEvents, plugin));
				delete ep.playerEvents;
				cpcache.aOutputWaits = view_as<ArrayList>(CloneHandle(ep.outputWaits, plugin));
				delete ep.outputWaits;
			}
			else
			{
				cpcache.aEvents = ep.playerEvents;
				cpcache.aOutputWaits = ep.outputWaits;
			}
		}
	}

	cpcache.iSteamID = GetSteamAccountID(target);

#if 0
	if (cpcache.iSteamID != GetSteamAccountID(saver))
	{
		cpcache.aSnapshot.bPracticeMode = true;
	}
#endif

	StringMap cd = new StringMap();

	if (plugin != INVALID_HANDLE)
	{
		cpcache.customdata = view_as<StringMap>(CloneHandle(cd, plugin));
		delete cd;
	}
	else
	{
		cpcache.customdata = cd;
	}

	Call_StartForward(gH_Forwards_OnCheckpointCacheSaved);
	Call_PushCell(saver);
	Call_PushArray(cpcache, sizeof(cpcache));
	Call_PushCell(index);
	Call_PushCell(target);
	Call_Finish();
}

void TeleportToCheckpoint(int client, int index, bool suppressMessage, int target=0)
{
	if(index < 1 || index > gCV_MaxCP.IntValue || (!gCV_Checkpoints.BoolValue && !CanSegment(client)))
	{
		return;
	}

	if(Shavit_IsPaused(client))
	{
		Shavit_PrintToChat(client, "%T", "CommandNoPause", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return;
	}

	target = target ? target : client;

	if (index > gA_Checkpoints[target].Length)
	{
		Shavit_PrintToChat(client, "%T", "MiscCheckpointsEmpty", client, index, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		return;
	}

	cp_cache_t cpcache;
	gA_Checkpoints[target].GetArray(index - 1, cpcache, sizeof(cp_cache_t));

	if(Shavit_GetStyleSettingInt(gI_Style[client], "kzcheckpoints") != Shavit_GetStyleSettingInt(cpcache.aSnapshot.bsStyle, "kzcheckpoints"))
	{
		Shavit_PrintToChat(client, "%T", "CommandTeleCPInvalid", client);

		return;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "CommandAlive", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return;
	}

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_OnTeleportPre);
	Call_PushCell(client);
	Call_PushCell(index);
	Call_PushCell(target);
	Call_Finish(result);

	if(result != Plugin_Continue)
	{
		return;
	}

	gI_TimesTeleported[client]++;

	if(Shavit_InsideZone(client, Zone_Start, -1))
	{
		Shavit_StopTimer(client);
	}

	bool bKzcheckpoints = Shavit_GetStyleSettingBool(gI_Style[client], "kzcheckpoints");

	if (!LoadCheckpointCache(client, cpcache, index, bKzcheckpoints))
	{
		return;
	}

	Shavit_ResumeTimer(client);

	Call_StartForward(gH_Forwards_OnTeleport);
	Call_PushCell(client);
	Call_PushCell(index);
	Call_PushCell(target);
	Call_Finish();

	// shavit-kz
	if(bKzcheckpoints)
	{
		UpdateKZStyle(client, TimerAction_OnTeleport);
	}

	if(!suppressMessage)
	{
		Shavit_PrintToChat(client, "%T", "MiscCheckpointsTeleported", client, index, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
	}
}

// index = -1 when persistent data. index = 0 when Shavit_LoadCheckpointCache() usually. index > 0 when "actually a checkpoint"
bool LoadCheckpointCache(int client, cp_cache_t cpcache, int index, bool force = false)
{
	// ripped this out and put it here since Shavit_LoadSnapshot() checks this and we want to bail early if LoadSnapShot would fail
	if (!force && !Shavit_HasStyleAccess(client, cpcache.aSnapshot.bsStyle))
	{
		return false;
	}

	bool isPersistentData = (index == -1);

	SetEntityMoveType(client, cpcache.iMoveType);
	SetEntityFlags(client, cpcache.iFlags);

	int ground = (cpcache.iGroundEntity != -1) ? EntRefToEntIndex(cpcache.iGroundEntity) : -1;
	SetEntPropEnt(client, Prop_Data, "m_hGroundEntity", ground);

	if(gEV_Type != Engine_TF2)
	{
		SetEntPropVector(client, Prop_Data, "m_vecLadderNormal", cpcache.vecLadderNormal);
		SetEntPropFloat(client, Prop_Send, "m_flStamina", cpcache.fStamina);
		SetEntProp(client, Prop_Send, "m_bDucked", cpcache.bDucked);
		SetEntProp(client, Prop_Send, "m_bDucking", cpcache.bDucking);
	}

	if(gEV_Type == Engine_CSS)
	{
#if MORE_LADDER_CHECKPOINT_STUFF
		SetEntDataVector(client, gI_Offset_m_lastStandingPos,           cpcache.m_lastStandingPos);
		SetEntDataFloat(client, gI_Offset_m_ladderSurpressionTimer + 4, cpcache.m_ladderSurpressionTimer[0]);
		SetEntDataFloat(client, gI_Offset_m_ladderSurpressionTimer + 8, cpcache.m_ladderSurpressionTimer[1] + GetGameTime());
		SetEntDataVector(client, gI_Offset_m_lastLadderNormal,          cpcache.m_lastLadderNormal);
		SetEntDataVector(client, gI_Offset_m_lastLadderPos,             cpcache.m_lastLadderPos);
#endif
		SetEntPropFloat(client, Prop_Send, "m_flDucktime", cpcache.fDucktime);
	}
	else if(gEV_Type == Engine_CSGO)
	{
		SetEntProp(client, Prop_Data, "m_bHasWalkMovedSinceLastJump", cpcache.m_bHasWalkMovedSinceLastJump, 1);
		SetEntPropFloat(client, Prop_Data, "m_ignoreLadderJumpTime", cpcache.m_ignoreLadderJumpTime + GetGameTime());
		SetEntPropFloat(client, Prop_Send, "m_flDuckAmount", cpcache.fDucktime);
		SetEntPropFloat(client, Prop_Send, "m_flDuckSpeed", cpcache.fDuckSpeed);
	}

	// this is basically the same as normal checkpoints except much less data is used
	if(!isPersistentData && Shavit_GetStyleSettingInt(gI_Style[client], "kzcheckpoints"))
	{
		TeleportEntity(client, cpcache.fPosition, cpcache.fAngles, view_as<float>({ 0.0, 0.0, 0.0 }));

		Call_StartForward(gH_Forwards_OnCheckpointCacheLoaded);
		Call_PushCell(client);
		Call_PushArray(cpcache, sizeof(cp_cache_t));
		Call_PushCell(index);
		Call_Finish();

		return true;
	}

	if (cpcache.aSnapshot.bPracticeMode || !(cpcache.bSegmented || isPersistentData) || GetSteamAccountID(client) != cpcache.iSteamID)
	{
		cpcache.aSnapshot.bPracticeMode = true;

		// Do this here to trigger practice mode alert
		Shavit_SetPracticeMode(client, true, true);
	}

	Shavit_LoadSnapshot(client, cpcache.aSnapshot, sizeof(timer_snapshot_t), force);

	Shavit_UpdateLaggedMovement(client, true);
	SetEntPropString(client, Prop_Data, "m_iName", cpcache.sTargetname);
	SetEntPropString(client, Prop_Data, "m_iClassname", cpcache.sClassname);

	TeleportEntity(client, cpcache.fPosition,
		((gI_CheckpointsSettings[client] & CP_ANGLES)   > 0 || cpcache.bSegmented || isPersistentData) ? cpcache.fAngles   : NULL_VECTOR,
		((gI_CheckpointsSettings[client] & CP_VELOCITY) > 0 || cpcache.bSegmented || isPersistentData) ? cpcache.fVelocity : NULL_VECTOR);

	// Used to trigger all endtouch booster events which are then wiped via eventqueuefix :)
	MaybeDoPhysicsUntouch(client);

	if (!cpcache.aSnapshot.bPracticeMode)
	{
		if (gB_ReplayRecorder)
		{
			Shavit_HijackAngles(client, cpcache.fAngles[0], cpcache.fAngles[1], -1);
		}
	}

	SetEntityGravity(client, cpcache.fGravity);

	if (gB_ReplayRecorder && cpcache.aFrames != null)
	{
		// if isPersistentData, then CloneHandle() is done instead of ArrayList.Clone()
		Shavit_SetReplayData(client, cpcache.aFrames, isPersistentData);
		Shavit_SetPlayerPreFrames(client, cpcache.iPreFrames);
	}

	if (gB_Eventqueuefix && cpcache.aEvents != null && cpcache.aOutputWaits != null)
	{
		eventpack_t ep;
		ep.playerEvents = cpcache.aEvents;
		ep.outputWaits = cpcache.aOutputWaits;
		SetClientEvents(client, ep);

#if DEBUG
		PrintToConsole(client, "targetname='%s'", cpcache.sTargetname);

		for (int i = 0; i < cpcache.aEvents.Length; i++)
		{
			event_t e;
			cpcache.aEvents.GetArray(i, e);
			PrintToConsole(client, "%s %s %s %f %i %i %i", e.target, e.targetInput, e.variantValue, e.delay, e.activator, e.caller, e.outputID);
		}
#endif
	}

	Call_StartForward(gH_Forwards_OnCheckpointCacheLoaded);
	Call_PushCell(client);
	Call_PushArray(cpcache, sizeof(cp_cache_t));
	Call_PushCell(index);
	Call_Finish();

	return true;
}

bool DeleteCheckpoint(int client, int index, bool force=false)
{
	if (index < 1 || index > gA_Checkpoints[client].Length)
	{
		return false;
	}

	Action result = Plugin_Continue;

	if (!force)
	{
		Call_StartForward(gH_Forwards_OnDelete);
		Call_PushCell(client);
		Call_PushCell(index);
		Call_PushCell(false);
		Call_Finish(result);
	}

	if (result != Plugin_Continue)
	{
		return false;
	}

	cp_cache_t cpcache;
	gA_Checkpoints[client].GetArray(index-1, cpcache);
	gA_Checkpoints[client].Erase(index-1);
	DeleteCheckpointCache(cpcache);

	return true;
}

bool UpdateKZStyle(int client, TimerAction timerAction)
{
	int iTargetStyle = -1;

	if(timerAction == TimerAction_OnStart)
	{
		iTargetStyle = Shavit_GetStyleSettingInt(gI_Style[client], "kzcheckpoints_onstart");
	}
	else if(timerAction == TimerAction_OnTeleport)
	{
		iTargetStyle = Shavit_GetStyleSettingInt(gI_Style[client], "kzcheckpoints_ontele");
	}

	if(iTargetStyle != -1)
	{
		Shavit_ChangeClientStyle(client, iTargetStyle, true, false, false);

		return true;
	}

	return false;
}

public any Native_GetCheckpoint(Handle plugin, int numParams)
{
	if(GetNativeCell(4) != sizeof(cp_cache_t))
	{
		return ThrowNativeError(200, "cp_cache_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins",
			GetNativeCell(4), sizeof(cp_cache_t));
	}

	int client = GetNativeCell(1);
	int index = GetNativeCell(2);

	cp_cache_t cpcache;
	if(gA_Checkpoints[client].GetArray(index-1, cpcache, sizeof(cp_cache_t)))
	{
		SetNativeArray(3, cpcache, sizeof(cp_cache_t));
		return true;
	}

	return false;
}

public any Native_SetCheckpoint(Handle plugin, int numParams)
{
	if(GetNativeCell(4) != sizeof(cp_cache_t))
	{
		return ThrowNativeError(200, "cp_cache_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins",
			GetNativeCell(4), sizeof(cp_cache_t));
	}

	int client = GetNativeCell(1);
	int position = GetNativeCell(2);

	cp_cache_t cpcache;
	GetNativeArray(3, cpcache, sizeof(cp_cache_t));

	int maxcps = GetMaxCPs(client);
	int numcps = gA_Checkpoints[client].Length;

	if (position <= -1)
	{
		position = numcps + 1;
	}

	if (position == 0 && numcps >= maxcps)
	{
		return false;
	}

	if (position > maxcps)
	{
		return false;
	}

	bool cheapCloneHandle = (numParams > 4) ? GetNativeCell(5) : true;

	if (cpcache.aFrames)
		cpcache.aFrames = cheapCloneHandle ? view_as<ArrayList>(CloneHandle(cpcache.aFrames)) : cpcache.aFrames.Clone();
	if (cpcache.aEvents)
		cpcache.aEvents = cheapCloneHandle ? view_as<ArrayList>(CloneHandle(cpcache.aEvents)) : cpcache.aEvents.Clone();
	if (cpcache.aOutputWaits)
		cpcache.aOutputWaits = cheapCloneHandle ? view_as<ArrayList>(CloneHandle(cpcache.aOutputWaits)) : cpcache.aOutputWaits.Clone();
	if (cpcache.customdata)
		cpcache.customdata = view_as<StringMap>(CloneHandle(cpcache.customdata)); //cheapCloneHandle ? view_as<StringMap>(CloneHandle(cpcache.customdata)) : cpcache.customdata.Clone();

	if (numcps == 0)
	{
		gA_Checkpoints[client].PushArray(cpcache);
		gI_CurrentCheckpoint[client] = 1;
	}
	else if (position == 0)
	{
		gA_Checkpoints[client].ShiftUp(0);
		gA_Checkpoints[client].SetArray(0, cpcache);
		++gI_CurrentCheckpoint[client];
	}
	else
	{
		DeleteCheckpoint(client, position, true);

		if (gA_Checkpoints[client].Length >= position)
		{
			gA_Checkpoints[client].ShiftUp(position-1);
			gA_Checkpoints[client].SetArray(position-1, cpcache);
		}
		else
		{
			gA_Checkpoints[client].PushArray(cpcache);
		}
	}

	return true;
}

public any Native_ClearCheckpoints(Handle plugin, int numParams)
{
	ResetCheckpoints(GetNativeCell(1));
	return 0;
}

public any Native_TeleportToCheckpoint(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int position = GetNativeCell(2);
	bool suppress = GetNativeCell(3);
	int target = (numParams > 3) ? GetNativeCell(4) : 0;

	TeleportToCheckpoint(client, position, suppress, target);
	return 0;
}

public any Native_HasSavestate(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (gB_SaveStates[client])
	{
		return true;
	}

	persistent_data_t aData;
	int iIndex = FindPersistentData(client, aData);

	if (iIndex != -1)
	{
		gB_SaveStates[client] = true;
	}

	return gB_SaveStates[client];
}

public any Native_GetTimesTeleported(Handle plugin, int numParams)
{
	return gI_TimesTeleported[GetNativeCell(1)];
}

public any Native_SetTimesTeleported(Handle plugin, int numParams)
{
	gI_TimesTeleported[GetNativeCell(1)] = GetNativeCell(2);
	return 1;
}

public any Native_GetTotalCheckpoints(Handle plugin, int numParams)
{
	return gA_Checkpoints[GetNativeCell(1)].Length;
}

public any Native_GetCurrentCheckpoint(Handle plugin, int numParams)
{
	return gI_CurrentCheckpoint[GetNativeCell(1)];
}

public any Native_SetCurrentCheckpoint(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int index = GetNativeCell(2);

	gI_CurrentCheckpoint[client] = index;
	return 0;
}

public any Native_SaveCheckpoint(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if(!CanSegment(client) && gA_Checkpoints[client].Length >= GetMaxCPs(client))
	{
		return -1;
	}

	SaveCheckpoint(client);
	return gI_CurrentCheckpoint[client];
}

public any Native_LoadCheckpointCache(Handle plugin, int numParams)
{
	if (GetNativeCell(4) != sizeof(cp_cache_t))
	{
		return ThrowNativeError(200, "cp_cache_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins", GetNativeCell(4), sizeof(cp_cache_t));
	}

	int client = GetNativeCell(1);
	cp_cache_t cache;
	GetNativeArray(2, cache, sizeof(cp_cache_t));
	int index = GetNativeCell(3);
	bool force = GetNativeCell(5);

	return LoadCheckpointCache(client, cache, index, force);
}

public any Native_SaveCheckpointCache(Handle plugin, int numParams)
{
	if (GetNativeCell(5) != sizeof(cp_cache_t))
	{
		return ThrowNativeError(200, "cp_cache_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins", GetNativeCell(5), sizeof(cp_cache_t));
	}

	int saver = GetNativeCell(1);
	int target = GetNativeCell(2);
	cp_cache_t cache;
	int index = GetNativeCell(4);
	SaveCheckpointCache(saver, target, cache, index, plugin);
	return SetNativeArray(3, cache, sizeof(cp_cache_t));
}

// Restore
public Action Command_Restore(int client, int args)
{
	if (gB_SaveStates[client])
	{
		persistent_data_t data;
		int index = FindPersistentData(client, data);

		if (index != -1)
		{
			RequestFrame(LoadPersistentData, GetClientSerial(client));
		}
		else
		{
			gB_SaveStates[client] = false;
		}
	}

	return Plugin_Continue;
}

// public Action CommandListener_SaveState(int client, const char[] command, int args)
// {
//     if (!IsValidClient(client))
//     {
//         return Plugin_Handled;
//     }

//     if (CanRestore(client))
//     {
//         PersistData(client, false);
// 		Shavit_PrintToChat(client, "Restore your run with %s!restore", gS_ChatStrings.sVariable2);
//     }

//     return Plugin_Continue;
// }

bool CanRestore(int client)
{
    // bool canSegment = CanSegment(client);
    TimerStatus timerStatus = Shavit_GetTimerStatus(client);
    bool isRestoreTimerStatus = (timerStatus != Timer_Stopped) && !Shavit_IsPracticeMode(client);

    return !gB_SaveStates[client] && isRestoreTimerStatus;// && !canSegment;
}

public any Native_PersistData(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (IsValidClient(client) && CanRestore(client))
	{
		PersistData(client, false);
		return true;
	}

	return false;
}

// `Restore


// SaveGame
public Action Command_Savegame(int client, int args)
{
	if (IsValidClient(client))
	{
		if (gI_SaveGameEnabled[client] == -1)
		{
			SaveGame_OpenMainMenu(client);
		}
		else
		{
			Shavit_PrintToChat(client, "Autosave is %senabled%s, type %s!stop%s if you want to save your progress now.", gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
		}
		
	}

	return Plugin_Handled;
}

public void Shavit_OnFinish(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp)
{
	if (gB_SaveStates[client])
	{
		DeletePersistentDataFromClient(client);
	}

	if (gI_SaveGameEnabled[client] != -1)
	{
		File file;
		char path[PLATFORM_MAX_PATH];
		FormatEx(path, PLATFORM_MAX_PATH, "%s/%d", gS_SaveGameClientFolder[client], gI_SaveGameEnabled[client]);

		if ((file = OpenFile(path, "wb")) != null)
		{
			file.Close();
		}

		gB_IsEmptySlot[client][gI_SaveGameEnabled[client]] = true;
		Shavit_PrintToChat(client, "Map completed. Slot %s%d%s has been deleted.", gS_ChatStrings.sVariable, gI_SaveGameEnabled[client] + 1, gS_ChatStrings.sText);
		gI_SaveGameEnabled[client] = -1;
	}
}

public Action CommandListener_Stop(int client, const char[] command, int args)
{
	if (IsValidClient(client) && (gI_SaveGameEnabled[client] != -1))
	{
		if (CanRestore(client))
		{
			gF_LastTargetPC[client] = Shavit_GetTargetPC(client);
			PersistData(client, false);
		}

		SaveGame_Save(client, gI_SaveGameEnabled[client]);
		Shavit_PrintToChat(client, "Your progress has been saved to slot %s%d", gS_ChatStrings.sVariable, gI_SaveGameEnabled[client] + 1);
		gI_SaveGameEnabled[client] = -1;
	}

	return Plugin_Continue;
}


// The function is always called only for valid clients
// void SaveGame_BuildMenuTitle(int client, char[] title, int size = 512)
// {
// 	FormatEx(title, size, "%s\n \n", gS_Map);

// 	TimerStatus ts = Shavit_GetTimerStatus(client);

// 	if (ts != Timer_Stopped)
// 	{
// 		int style = Shavit_GetBhopStyle(client);
// 		int track = Shavit_GetClientTrack(client);
// 		float time = Shavit_GetClientTime(client);

// 		char buff[32];
// 		Shavit_GetStyleSetting(style, "name", buff, 32);

// 		float pc = Shavit_GetTargetPC(client);

// 		FormatEx(title, size, "%sTrack: %s\n", title, track == Track_Main ? "Main" : "Bonus");
// 		if (pc != -1.0)
// 		{
// 			FormatEx(title, size, "%sProgress: ~%.2f％\n \n", title, pc);
// 		}
// 		else
// 		{
// 			FormatEx(title, size, "%s \n", title);
// 		}

// 		FormatEx(title, size, "%sStyle: %s\n", title, buff);

// 		FormatSeconds(time, buff, 32);

// 		FormatEx(title, size, "%sTime: %s\n \n", title, buff);
// 	}
// 	else
// 	{
// 		FormatEx(title, size, "%sNothing to save\n \n", title);
// 	}
// }

void SaveGame_OpenMainMenu(int client)
{
	Menu menu = new Menu(SaveGame_MainMenuHandler);

	char title[512];
	// TODO:
	// SaveGame_BuildMenuTitle(client, title);

	FormatEx(title, 512, "%s\n \n", gS_Map);
	
	TimerStatus ts = Shavit_GetTimerStatus(client);

	if (ts != Timer_Stopped)
	{
		int style = Shavit_GetBhopStyle(client);
		int track = Shavit_GetClientTrack(client);
		float time = Shavit_GetClientTime(client);

		char buff[32];
		Shavit_GetStyleSetting(style, "name", buff, 32);

		float pc = Shavit_GetTargetPC(client);

		FormatEx(title, 512, "%sTrack: %s\n", title, track == Track_Main ? "Main" : "Bonus");
		if (pc != -1.0)
		{
			FormatEx(title, 512, "%sProgress: ~%.2f％\n \n", title, pc);
		}
		else
		{
			FormatEx(title, 512, "%s \n", title);
		}

		FormatEx(title, 512, "%sStyle: %s\n", title, buff);

		FormatSeconds(time, buff, 32);

		FormatEx(title, 512, "%sTime: %s\n \n", title, buff);
	}
	else
	{
		FormatEx(title, 512, "%sNothing to save\n \n", title);
	}

	menu.SetTitle(title);

	menu.AddItem("save", "Save game", Shavit_GetTimerStatus(client) != Timer_Stopped ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("load", "Load game");

	menu.ExitButton = true;
	menu.Display(client, 120);
}

public int SaveGame_MainMenuHandler(Menu menu, MenuAction action, int client, int info)
{
	if (action == MenuAction_Select)
	{
		char buff[32];
		menu.GetItem(info, buff, 32);

		if (StrEqual(buff, "save"))
		{
			SaveGame_OpenSaveMenu(client);
		}
		else if (StrEqual(buff, "load"))
		{
			SaveGame_OpenLoadMenu(client);
		}
	}
	else if (action == MenuAction_End)
    {
        delete menu;
    }

	return 0;
}

void SaveGame_OpenSaveMenu(int client)
{
	Menu menu = new Menu(SaveGame_SaveMenuHandler);

	menu.Pagination = gI_AvailableSlots > 10 ? true : false;

	menu.SetTitle("Save Game\n \n");

	for (int i = 0; i < gI_AvailableSlots; i++)
	{
		char buff[128], slot[8], style[32], time[32];
		FormatEx(slot, sizeof(slot), "%d", i);

		if (gB_IsEmptySlot[client][i])
		{
			menu.AddItem(slot, "empty slot");
		}
		else
		{
			/*
				TODO:
				What if the server owner deletes the style and 
				the style itself is stored in the savegame folder?
			*/
			if (!Shavit_GetStyleSetting(gA_SaveGameHeader[client][i].iStyle, "name", style, 32))
			{
				FormatEx(style, 32, "Undefined");
			}

			FormatSeconds(gA_SaveGameHeader[client][i].fTime, time, 32);

			FormatEx(buff, 128, "%s / %s (%s)", gA_SaveGameHeader[client][i].sMap, style, time);
			menu.AddItem(slot, buff);
		}
	}

	menu.ExitButton = true;
	// menu.ExitBackButton = true;
	menu.Display(client, 120);
}

// The function is always called only for valid clients
bool SaveGame_Save(int client, int slot)
{
	persistent_data_t data;
	int index = FindPersistentData(client, data);

	if (index == -1)
	{
		Shavit_PrintToChat(client, "Failed to save the game. No game progress found.");
	}
	else
	{
		File file = null;
		char path[PLATFORM_MAX_PATH];
		FormatEx(path, PLATFORM_MAX_PATH, "%s/%d", gS_SaveGameClientFolder[client], slot);
		
		if (!(file = OpenFile(path, "wb+")))
		{
			Shavit_PrintToChat(client, "Something went wrong. The server could not save your game progress.");
			LogError("[SaveGameFile] Failed to open savegame file for writing. ('%s')", path);
		}

		savegame_header_t header;

		header.sMap = gS_Map;
		header.iTrack = data.cpcache.aSnapshot.iTimerTrack;
		header.iStyle = data.cpcache.aSnapshot.bsStyle;
		header.iSteamID = GetSteamAccountID(client);
		header.fTime = data.cpcache.aSnapshot.fCurrentTime;
		header.fPC = gF_LastTargetPC[client];

		bool success = false;

		if (!Shavit_GetStyleSettingBool(data.cpcache.aSnapshot.bsStyle, "segments"))
		{
			success = SaveGameFile_SaveGame(file, header.iSteamID, header.sMap, header.iStyle, header.iTrack, header.fTime, header.fPC, data.cpcache);
		}
		else
		{
			success = SaveGameFile_SaveCheckpoints(file, header.iSteamID, header.sMap, header.iStyle, header.iTrack, header.fTime, header.fPC, gA_Checkpoints[client]);
		}

		delete file;

		if (success)
		{
			gB_IsEmptySlot[client][slot] = false;
			gA_SaveGameHeader[client][slot] = header;
			gI_SaveGameEnabled[client] = slot;
		}

		return success;
	}

	return false;
}

public int SaveGame_SaveMenuHandler(Menu menu, MenuAction action, int client, int info)
{
	if (action == MenuAction_Select)
	{
		char buff[32], slot[8];
		menu.GetItem(info, buff, 32);

		for (int i = 0; i < gI_AvailableSlots; i++)
		{
			FormatEx(slot, sizeof(slot), "%d", i);

			if (StrEqual(buff, slot))
			{
				if (gB_IsEmptySlot[client][i])
				{
					/*
						There doesn’t seem to be much point in writing data to a file here. 
						Instead, it would make more sense to simply mark that the client has 
						saved the game in a slot and only save the data before 
						!stop or upon exiting the game. 
						However, it's best to ensure that the server can successfully save 
						the data and write the file to prevent any potential issues.
					*/

					gI_SaveGameEnabled[client] = i;
					Shavit_PrintToChat(client, "Autosave has been %senabled%s. Your game will be saved to slot %s%d%s.", gS_ChatStrings.sVariable2, gS_ChatStrings.sText, gS_ChatStrings.sVariable, i + 1, gS_ChatStrings.sText);

					// if (CanRestore(client))
					// {
					// 	gF_LastTargetPC[client] = Shavit_GetTargetPC(client);
					// 	PersistData(client, false);
					// }

					// if (SaveGame_Save(client, i))
					// {
					//  #if DEBUG
					// 	Shavit_PrintToChat(client, "game saved!");
					// }
				}
				else
				{
					SaveGame_OpenOverwriteMenu(client, StringToInt(slot));
				}

				break;
			}
		}
	}
	// else if (action == MenuAction_Cancel)
	// {
	// 	if (info == MenuCancel_ExitBack)
	// 	{
	// 		SaveGame_OpenMainMenu(client);
	// 	}
	// }
	else if (action == MenuAction_End)
    {
        delete menu;
    }

	return 0;
}

void SaveGame_OpenOverwriteMenu(int client, int slot)
{
	Menu menu = new Menu(SaveGame_OverwriteMenuHandler);

	char title[512];

	// TODO:
	// SaveGame_BuildMenuTitle(client, title);

	FormatEx(title, 512, "%s\n \n", gA_SaveGameHeader[client][slot].sMap);

	int style = gA_SaveGameHeader[client][slot].iStyle;
	int track = gA_SaveGameHeader[client][slot].iTrack;
	float time = gA_SaveGameHeader[client][slot].fTime;

	char buff[32];
	Shavit_GetStyleSetting(style, "name", buff, 32);

	float pc = gA_SaveGameHeader[client][slot].fPC;

	FormatEx(title, 512, "%sTrack: %s\n", title, track == Track_Main ? "Main" : "Bonus");
	if (pc != -1.0)
	{
		FormatEx(title, 512, "%sProgress: ~%.2f％\n \n", title, pc);
	}
	else
	{
		FormatEx(title, 512, "%s \n", title);
	}

	FormatEx(title, 512, "%sStyle: %s\n", title, buff);

	FormatSeconds(time, buff, 32);

	FormatEx(title, 512, "%sTime: %s\n \n", title, buff);

	menu.SetTitle(title);

	menu.Pagination = false;

	FormatEx(buff, 32, "%d", slot);
	menu.AddItem(buff, "Overwrite");

	menu.ExitButton = true;
	menu.Display(client, 120);
}

public int SaveGame_OverwriteMenuHandler(Menu menu, MenuAction action, int client, int info)
{
	if (action == MenuAction_Select)
	{
		char buff[8];
		menu.GetItem(info, buff, 8);

		int iSlot = StringToInt(buff);
		SaveGame_OpenOverwriteWarningMenu(client, iSlot);
	}
	else if (action == MenuAction_End)
    {
        delete menu;
    }

	return 0;
}

void SaveGame_OpenOverwriteWarningMenu(int client, int slot)
{
	Menu menu = new Menu(SaveGame_OverwriteWarningMenuHandler);

	menu.SetTitle("Are you sure you want to overwrite slot #%d?\n \n", slot + 1);

	char buff[8];
	FormatEx(buff, 8, "%d", (slot + 1));
	menu.AddItem(buff, "Yes");

	FormatEx(buff, 8, "%d", (slot + 1) * -1); // slot can be 0
	menu.AddItem(buff, "No");

	menu.ExitButton = true;
	menu.Display(client, 120);
}

public int SaveGame_OverwriteWarningMenuHandler(Menu menu, MenuAction action, int client, int info)
{
	if (action == MenuAction_Select)
	{
		char buff[8];
		menu.GetItem(info, buff, 8);

		int iSlot = StringToInt(buff);

		if (iSlot > 0)
		{
			// if (CanRestore(client))
			// {
			// 	gF_LastTargetPC[client] = Shavit_GetTargetPC(client);
			// 	PersistData(client, false);
			// }

			// if (SaveGame_Save(client, iSlot - 1))
			// {
			// 	Shavit_PrintToChat(client, "Slot #%d has been overwritten.", iSlot);
			// }

			gI_SaveGameEnabled[client] = iSlot - 1;
			Shavit_PrintToChat(client, "Slot %s%d%s has been overwritten.", gS_ChatStrings.sVariable, iSlot, gS_ChatStrings.sText);
		}
	}
	else if (action == MenuAction_End)
    {
        delete menu;
    }

	return 0;
}

// **

void SaveGame_OpenLoadMenu(int client)
{
	Menu menu = new Menu(SaveGame_LoadMenuHandler);

	menu.Pagination = gI_AvailableSlots > 10 ? true : false;

	menu.SetTitle("Load Game\n \n");

	for (int i = 0; i < gI_AvailableSlots; i++)
	{
		char buff[128], slot[8], style[32], time[32];
		FormatEx(slot, sizeof(slot), "%d", i);

		if (gB_IsEmptySlot[client][i])
		{
			menu.AddItem(slot, "empty slot", ITEMDRAW_DISABLED);
		}
		else
		{
			if (!Shavit_GetStyleSetting(gA_SaveGameHeader[client][i].iStyle, "name", style, 32))
			{
				FormatEx(style, 32, "Undefined");
			}

			FormatSeconds(gA_SaveGameHeader[client][i].fTime, time, 32);

			FormatEx(buff, 128, "%s / %s (%s)", gA_SaveGameHeader[client][i].sMap, style, time);
			menu.AddItem(slot, buff);
		}
	}

	menu.ExitButton = true;
	// menu.ExitBackButton = true;
	menu.Display(client, 120);
}

public int SaveGame_LoadMenuHandler(Menu menu, MenuAction action, int client, int info)
{
	if (action == MenuAction_Select)
	{
		char slot[8];
		menu.GetItem(info, slot, 8);

		int iSlot = StringToInt(slot);

		if (StrEqual(gA_SaveGameHeader[client][iSlot].sMap, gS_Map))
		{
			File file = null;
			char path[PLATFORM_MAX_PATH];
			FormatEx(path, PLATFORM_MAX_PATH, "%s/%s", gS_SaveGameClientFolder[client], slot);

			bool isSeg = Shavit_GetStyleSettingBool(gA_SaveGameHeader[client][iSlot].iStyle, "segments");

			savegame_header_t header;
			persistent_data_t data, currentData;

			if (!isSeg)
			{
				file = SaveGameFile_LoadGame(path, header, data.cpcache);
				if (file != null)
				{
					data.iSteamID = GetSteamAccountID(client);

					int index = FindPersistentData(client, currentData);

					if (index == -1)
					{
						gA_PersistentData.PushArray(data);
					}
					else
					{
						gA_PersistentData.SetArray(index, data);
					}

					RequestFrame(LoadPersistentData, GetClientSerial(client));
					Shavit_PrintToChat(client, "Game progress has been successfully loaded.");
				}
				else
				{
					Shavit_PrintToChat(client, "Something went wrong. The server could not load your game progress.");
					LogError("[SaveGameFile] Failed to open savegame file for reading. ('%s')", path);
				}
			}
			else
			{
				ResetCheckpoints(client);
				gA_Checkpoints[client] = new ArrayList(sizeof(cp_cache_t));

				file = SaveGameFile_LoadCheckpoints(path, header, gA_Checkpoints[client]);
				if (file != null)
				{
					gI_CurrentCheckpoint[client] = gA_Checkpoints[client].Length;
					Shavit_TeleportToCheckpoint(client, gI_CurrentCheckpoint[client]);
					OpenCPMenu(client);

					Shavit_PrintToChat(client, "Checkpoints has been successfully loaded.");
				}
			}

			gI_SaveGameEnabled[client] = iSlot;
			Shavit_PrintToChat(client, "Autosave has been %senabled%s. Your game will be saved to slot %s%d%s.", gS_ChatStrings.sVariable2, gS_ChatStrings.sText, gS_ChatStrings.sVariable, iSlot + 1, gS_ChatStrings.sText);

			delete file;
		}
		else
		{
			SaveGame_OpenNomMenu(client, iSlot);
		}
	}
	// else if (action == MenuAction_Cancel)
	// {
	// 	if (info == MenuCancel_ExitBack)
	// 	{
	// 		SaveGame_OpenMainMenu(client);
	// 	}
	// }
	else if (action == MenuAction_End)
    {
        delete menu;
    }

	return 0;
}

// If the map names do not match, suggest the player to nominate the correct map.
void SaveGame_OpenNomMenu(int client, int slot)
{
	Menu menu = new Menu(SaveGame_NomMenuHandler);

	char title[512];

	FormatEx(title, 512, "%s\n \n", gA_SaveGameHeader[client][slot].sMap);

	int style = gA_SaveGameHeader[client][slot].iStyle;
	int track = gA_SaveGameHeader[client][slot].iTrack;
	float time = gA_SaveGameHeader[client][slot].fTime;

	char buff[32];
	Shavit_GetStyleSetting(style, "name", buff, 32);

	float pc = gA_SaveGameHeader[client][slot].fPC;

	FormatEx(title, 512, "%sTrack: %s\n", title, track == Track_Main ? "Main" : "Bonus");
	if (pc != -1.0)
	{
		FormatEx(title, 512, "%sProgress: ~%.2f％\n \n", title, pc);
	}
	else
	{
		FormatEx(title, 512, "%s \n", title);
	}

	FormatEx(title, 512, "%sStyle: %s\n", title, buff);

	FormatSeconds(time, buff, 32);

	FormatEx(title, 512, "%sTime: %s\n \n", title, buff);

	menu.SetTitle(title);

	menu.Pagination = false;

	FormatEx(buff, 32, "%d", (slot + 1));
	menu.AddItem(buff, "Nominate");

	FormatEx(buff, 32, "%d", (slot + 1) * -1); // slot can be 0
	menu.AddItem(buff, "Delete");

	menu.ExitButton = true;
	// menu.ExitBackButton = true;
	menu.Display(client, 120);
}

public int SaveGame_NomMenuHandler(Menu menu, MenuAction action, int client, int info)
{
	if (action == MenuAction_Select)
	{
		char buff[8];
		menu.GetItem(info, buff, 8);

		int iSlot = StringToInt(buff);

		if (iSlot > 0)
		{
			FakeClientCommandEx(client, "sm_nominate %s", gA_SaveGameHeader[client][iSlot - 1].sMap);
		}
		else
		{
			SaveGame_OpenWarningMenu(client, (iSlot * -1) - 1);
		}
	}
	// else if (action == MenuAction_Cancel)
	// {
	// 	if (info == MenuCancel_ExitBack)
	// 	{
	// 		SaveGame_OpenLoadMenu(client);
	// 	}
	// }
	else if (action == MenuAction_End)
    {
        delete menu;
    }

	return 0;
}

void SaveGame_OpenWarningMenu(int client, int slot)
{
	Menu menu = new Menu(SaveGame_WarningMenuHandler);

	menu.SetTitle("Are you sure you want to delete slot #%d?\n \n", slot + 1);

	char buff[8];
	FormatEx(buff, 8, "%d", (slot + 1));
	menu.AddItem(buff, "Yes");

	FormatEx(buff, 8, "%d", (slot + 1) * -1); // slot can be 0
	menu.AddItem(buff, "No");

	menu.ExitButton = true;
	menu.Display(client, 120);
}

public int SaveGame_WarningMenuHandler(Menu menu, MenuAction action, int client, int info)
{
	if (action == MenuAction_Select)
	{
		char buff[8];
		menu.GetItem(info, buff, 8);

		int iSlot = StringToInt(buff);

		if (iSlot > 0)
		{
			File file;
			char path[PLATFORM_MAX_PATH];
			FormatEx(path, PLATFORM_MAX_PATH, "%s/%d", gS_SaveGameClientFolder[client], iSlot - 1);

			if ((file = OpenFile(path, "wb")) != null)
			{
				file.Close();
				gB_IsEmptySlot[client][iSlot - 1] = true;
				Shavit_PrintToChat(client, "Slot %s%d%s has been deleted.", gS_ChatStrings.sVariable, iSlot, gS_ChatStrings.sText);
			}

			delete file;
		}
	}
	else if (action == MenuAction_End)
    {
        delete menu;
    }

	return 0;
}

// `SaveGame
