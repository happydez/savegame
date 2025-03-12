#pragma newdecls required
#pragma semicolon 1

#include <shavit>
#include <closestpos>

#include <shavit/core>
#include <shavit/replay-file>
#include <shavit/replay-playback>
#include <shavit/replay-recorder>

#include <pc>

int gI_PCStyle = -1;

bool gB_ReplayPlayback = false;

ClosestPos gH_ClosestPos;
frame_cache_t gA_ReplayFrameCache;

chatstrings_t gS_ChatStrings;

public Plugin myinfo =
{
    name = "[shavit] pc",
    author = "dez I愛D",
    description = "Allows you to check a player's progress on the map.",
    version = "1.0.0",
    url = "https://github.com/happydez"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    CreateNative("Shavit_GetTargetPC", Native_GetTargetPC);

    RegPluginLibrary("shavit-pc");

    return APLRes_Success;
}

public void OnPluginStart()
{
    RegConsoleCmd("sm_pc", Command_PC, "Allows you to check a player's progress on the map.");
    
    gB_ReplayPlayback = LibraryExists("shavit-replay-playback");
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "shavit-replay-playback"))
    {
        gB_ReplayPlayback = true;
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "shavit-replay-playback"))
    {
        gB_ReplayPlayback = false;
    }
}

public void Shavit_OnReplaysLoaded()
{
    gI_PCStyle = -1;
    TryInitPC();
}

public void Shavit_OnWorldRecord(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldwr, float oldtime, float perfs, float avgvel, float maxvel, int timestamp)
{
    if (!IsPCAllowed())
    {
        TryInitPC();
    }
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(gS_ChatStrings);
}

public void Shavit_OnReplaySaved(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp, bool isbestreplay, bool istoolong, bool iscopy, const char[] replaypath, ArrayList frames, int preframes, int postframes, const char[] name)
{
    if (isbestreplay && !IsPCAllowed())
    {
        TryInitPC();
    }
}

public Action Command_PC(int client, int args)
{
    if (IsPCAllowed())
    {
        ShowPC(client);
    }
    else
    {
        Shavit_PrintToChat(client, "No records on %snormal %s/ %ssegment%s. The %sPC %scommand is not available.", gS_ChatStrings.sVariable, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
    }

    return Plugin_Continue;
}

void ShowPC(int client)
{
    int target = GetSpectatorTarget(client, client);

    float pc = GetTargetPC(target);

    if (target == client)
    {
        Shavit_PrintToChat(client, "You`re %s~%.2f%% %sinto the map.", gS_ChatStrings.sVariable, pc > 100.0 ? 100.0 : pc, gS_ChatStrings.sText);
    }
    else
    {
        Shavit_PrintToChat(client, "%s%N %sis %s~%.2f%% %sinto the map.", gS_ChatStrings.sVariable2, target, gS_ChatStrings.sText, gS_ChatStrings.sVariable, pc > 100.0 ? 100.0 : pc, gS_ChatStrings.sText);
    }
}

float GetTargetPC(int target)
{
    float pc = -1.0;

    if (IsPCAllowed())
    {
        float pos[3];
        GetEntPropVector(target, Prop_Send, "m_vecOrigin", pos);

        int closestFrame = gH_ClosestPos.Find(pos);
        if (Shavit_InsideZone(target, Zone_Start, Track_Main))
        {
            pc = 0.0;
        }
        else if (Shavit_InsideZone(target, Zone_End, Track_Main))
        {
            pc = 100.0;
        }
        else
        {
            pc = closestFrame * 100.0 / float(gA_ReplayFrameCache.iFrameCount);
        }

        pc = pc > 100.0 ? 100.0 : pc;
    }

    return pc;
}

bool IsPCAllowed()
{
    return (gI_PCStyle != -1) && gB_ReplayPlayback;
}

void TryInitPC()
{
    int styleCount = Shavit_GetStyleCount();

    for (int style = 0; style < styleCount; style++)
    {
        if (Shavit_GetReplayFrameCount(style, Track_Main) > 0)
        {
            char buff[32];
            Shavit_GetStyleSetting(style, "name", buff, sizeof(buff));

            if (StrEqual(buff, "Normal", false) || StrEqual(buff, "Segmented", false))
            {
                if (gH_ClosestPos != null)
                {
                    delete gA_ReplayFrameCache.aFrames;
                    delete gH_ClosestPos;
                }

                gI_PCStyle = style;

                gA_ReplayFrameCache.aFrames = Shavit_GetReplayFrames(style, Track_Main);
                gA_ReplayFrameCache.iPreFrames = Shavit_GetReplayPreFrames(style, Track_Main);
                gA_ReplayFrameCache.iPostFrames = Shavit_GetReplayPostFrames(style, Track_Main);
                gA_ReplayFrameCache.iFrameCount = Shavit_GetReplayFrameCount(style, Track_Main);

                gH_ClosestPos = new ClosestPos(gA_ReplayFrameCache.aFrames, 0, gA_ReplayFrameCache.iPreFrames, gA_ReplayFrameCache.iFrameCount);

                break;
            }
        }
    }
}

public any Native_GetTargetPC(Handle plugin, int numParams)
{
    return GetTargetPC(GetNativeCell(1));
}