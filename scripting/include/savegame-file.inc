/*
 * shavit's Timer - savegame-file
 * by: dez I愛D (github.com/happydez)
 */

#if defined _savegame_file_included
	#endinput
#endif
#define _savegame_file_included

#include <shavit/core>
#include <eventqueuefix>

#define FRAMES_PER_WRITE 100
#define CHECKPOINTS_PER_WRITE 100

#define SGDEBUG 0

enum struct savegame_header_t
{
	char sMap[PLATFORM_MAX_PATH];
	int iSteamID;
    int iStyle;
    int iTrack;
    float fTime;
    float fPC;
}

stock bool SaveGameFile_SaveGame(File file, int steamID, const char[] map, int iStyle, int iTrack, float fTime, float fPC, cp_cache_t cache)
{
    if (file == null)
    {
        LogError("[SaveGameFile]`SaveGame: file handle is null.");
        return false;
    }

    SaveGameFile_WriteHeader(file, steamID, map, iStyle, iTrack, fTime, fPC);
    SaveGameFile_WriteCPCache(file, cache);

    return true;
}

stock bool SaveGameFile_SaveCheckpoints(File file, int steamID, const char[] map, int iStyle, int iTrack, float fTime, float fPC, ArrayList checkpoints)
{
    if (file == null)
    {
        LogError("[SaveGameFile]`SaveGame: file handle is null.");
        return false;
    }

    SaveGameFile_WriteHeader(file, steamID, map, iStyle, iTrack, fTime, fPC);
    SaveGameFile_WriteCheckpoints(file, checkpoints, checkpoints.Length);

    return true;
}

stock File SaveGameFile_LoadCheckpoints(const char[] path, savegame_header_t header, ArrayList checkpoints)
{
    File file = SaveGameFile_ReadHeader(path, header);

    if (file == null)
    {
        LogError("[SaveGameFile]`LoadGame: file handle is null.");
        return null;
    }

    if (!SaveGameFile_ReadCheckpoints(file, checkpoints))
    {
        LogError("[SaveGameFile]`LoadGame: failed to read checkpoints.");
        return null;
    }
    
    return file;
}

stock File SaveGameFile_LoadGame(const char[] path, savegame_header_t header, cp_cache_t cache)
{
    File file = SaveGameFile_ReadHeader(path, header);

    if (file == null)
    {
        LogError("[SaveGameFile]`LoadGame: file handle is null.");
        return null;
    }

    if (!SaveGameFile_ReadCPCache(file, cache))
    {
        LogError("[SaveGameFile]`LoadGame: failed to read cp_cache_t.");
        return null;
    }

    return file;
}

stock void SaveGameFile_WriteHeader(File fFile, int iSteamID, const char[] sMap, int iStyle, int iTrack, float fTime, float pc)
{
	fFile.WriteString(sMap, true);
	fFile.WriteInt32(iSteamID);
    fFile.WriteInt8(iStyle);
    fFile.WriteInt8(iTrack);
    fFile.WriteInt32(view_as<int>(fTime));
    fFile.WriteInt32(view_as<int>(pc));
}

stock File SaveGameFile_ReadHeader(const char[] path, savegame_header_t header)
{
	savegame_header_t empty_header;
	header = empty_header;

	File file = OpenFile(path, "rb");

	if (file == null || file.Size() <= 0)
	{
		return null;
	}

	file.ReadString(header.sMap, PLATFORM_MAX_PATH);
	file.ReadInt32(header.iSteamID);
    file.ReadInt8(header.iStyle);
    file.ReadInt8(header.iTrack);
    
    int bits;
    file.ReadInt32(bits);
    header.fTime = view_as<float>(bits);

    file.ReadInt32(bits);
    header.fPC = view_as<float>(bits);

	return file;
}

// like WriteReplayFrames from include/shavit/replay-file.inc
stock void SaveGameFile_WriteReplayFrames(File file, ArrayList frames, int size)
{
    file.WriteInt32(size);

    any aFrameData[sizeof(frame_t)];
	any aWriteData[sizeof(frame_t) * FRAMES_PER_WRITE];
	int iFramesWritten = 0;

	for (int i = 0; i < size; i++)
	{
		frames.GetArray(i, aFrameData, sizeof(frame_t));

		for (int j = 0; j < sizeof(frame_t); j++)
		{
			aWriteData[(sizeof(frame_t) * iFramesWritten) + j] = aFrameData[j];
		}

		if ((++iFramesWritten == FRAMES_PER_WRITE) || (i == size - 1))
		{
			file.Write(aWriteData, sizeof(frame_t) * iFramesWritten, 4);
			iFramesWritten = 0;
		}
	}
}

stock bool SaveGameFile_ReadReplayFrames(File file, cp_cache_t cache)
{
    if (file == null)
    {
        LogError("[SaveGameFile]`ReadReplayFrames: file handle is null.");
        return false;
    }

    int size;
    file.ReadInt32(size);

    delete cache.aFrames;
    cache.aFrames = new ArrayList(8, size);

    if (size <= 0)
    {
        return false;
    }

    any buffer[sizeof(frame_t)];

    for (int i = 0; i < size; i++)
    {
        if (file.Read(buffer, 10, 4) >= 0)
        {
            cache.aFrames.SetArray(i, buffer, 8);
        }
    }

    return true;
}

stock bool SaveGameFile_WriteOutputWaits(File file, ArrayList outputWaits, int size)
{
    if (file == null)
    {
        LogError("[SaveGameFile]`WriteOutputWaits: file handle is null.");
        return false;
    }

    file.WriteInt32(size);
    any buffer[sizeof(entity_t)];

    for (int i = 0; i < size; i++)
    {
        outputWaits.GetArray(i, buffer, sizeof(entity_t));
        file.Write(buffer, sizeof(event_t), 4);
    }

    return true;
}

stock bool SaveGameFile_ReadOutputWaits(File file, cp_cache_t cache)
{
    if (file == null)
    {
        LogError("[SaveGameFile]`ReadOutputWaits: file handle is null.");
        return false;
    }

    int size;
    file.ReadInt32(size);

    delete cache.aOutputWaits;
    cache.aOutputWaits = new ArrayList(sizeof(entity_t));

    if (size <= 0)
    {
        return false;
    }

    any buffer[sizeof(entity_t)];
    for (int i = 0; i < size; i++)
    {
        file.Read(buffer, sizeof(entity_t), 4);
        cache.aOutputWaits.PushArray(buffer, sizeof(entity_t));
    }

    return true;
}

stock bool SaveGameFile_WriteEvents(File file, ArrayList events, int size)
{
    if (file == null)
    {
        LogError("[SaveGameFile]`WriteEvents: file handle is null.");
        return false;
    }

    file.WriteInt32(size);
    any buffer[sizeof(event_t)];

    for (int i = 0; i < size; i++)
    {
        events.GetArray(i, buffer, sizeof(event_t));
        file.Write(buffer, sizeof(event_t), 4);
    }

    return true;
}

stock bool SaveGameFile_ReadEvents(File file, cp_cache_t cache)
{
    if (file == null)
    {
        LogError("[SaveGameFile]`ReadEvents: file handle is null.");
        return false;
    }

    int size;
    file.ReadInt32(size);

    delete cache.aEvents;
    cache.aEvents = new ArrayList(sizeof(event_t));

    if (size <= 0)
    {
        return false;
    }

    any buffer[sizeof(event_t)];
    for (int i = 0; i < size; i++)
    {
        file.Read(buffer, sizeof(event_t), 4);
        cache.aEvents.PushArray(buffer, sizeof(event_t));
    }

    return true;
}


stock void SaveGameFile_WriteSnapshot(File file, timer_snapshot_t snapshot)
{
	file.WriteInt8(view_as<int>(snapshot.bTimerEnabled));
	file.WriteInt32(view_as<int>(snapshot.fCurrentTime));
	file.WriteInt8(view_as<int>(snapshot.bClientPaused));
	file.WriteInt32(snapshot.iJumps);
	file.WriteInt8(snapshot.bsStyle);
	file.WriteInt32(snapshot.iStrafes);
	file.WriteInt32(snapshot.iTotalMeasures);
	file.WriteInt32(snapshot.iGoodGains);
	file.WriteInt32(view_as<int>(snapshot.fServerTime));
	file.WriteInt32(snapshot.iKeyCombo);
	file.WriteInt32(snapshot.iTimerTrack);
	file.WriteInt32(snapshot.iTotalMeasures);
	file.WriteInt32(snapshot.iPerfectJumps);
	file.WriteInt32(view_as<int>(snapshot.fZoneOffset[0]));
	file.WriteInt32(view_as<int>(snapshot.fZoneOffset[1]));
	file.WriteInt32(view_as<int>(snapshot.fDistanceOffset[0]));
	file.WriteInt32(view_as<int>(snapshot.fDistanceOffset[1]));
	file.WriteInt32(view_as<int>(snapshot.fAvgVelocity));
	file.WriteInt32(view_as<int>(snapshot.fMaxVelocity));
	file.WriteInt32(view_as<int>(snapshot.fTimescale));
	file.WriteInt32(snapshot.iZoneIncrement);
	file.WriteInt32(snapshot.iFullTicks);
	file.WriteInt32(snapshot.iFractionalTicks);
	file.WriteInt8(view_as<int>(snapshot.bPracticeMode));
	file.WriteInt8(view_as<int>(snapshot.bJumped));
	file.WriteInt8(view_as<int>(snapshot.bCanUseAllKeys));
	file.WriteInt8(view_as<int>(snapshot.bOnGround));
	file.WriteInt32(snapshot.iLastButtons);
	file.WriteInt32(view_as<int>(snapshot.fLastAngle));
	file.WriteInt32(snapshot.iLandingTick);
	file.WriteInt8(view_as<int>(snapshot.iLastMoveType));
	file.WriteInt32(view_as<int>(snapshot.fStrafeWarning));
	file.WriteInt32(view_as<int>(snapshot.fLastInputVel[0]));
	file.WriteInt32(view_as<int>(snapshot.fLastInputVel[1]));
	file.WriteInt32(view_as<int>(snapshot.fplayer_speedmod));
	file.WriteInt32(view_as<int>(snapshot.fNextFrameTime));
	file.WriteInt32(view_as<int>(snapshot.iLastMoveTypeTAS));
}

stock bool SaveGameFile_ReadSnapshot(File file, timer_snapshot_t snapshot)
{
	if (file == null)
	{
		LogError("[SaveGameFile] Attempting to read timer_snapshot_t from a non-existent file.");
		return false;
	}

	timer_snapshot_t empty_snapshot;
	snapshot = empty_snapshot;

	int bits;

    file.ReadInt8(bits);
    snapshot.bTimerEnabled = view_as<bool>(bits);

    file.ReadInt32(bits);
    snapshot.fCurrentTime = view_as<float>(bits);

    file.ReadInt8(bits);
    snapshot.bClientPaused = view_as<bool>(bits);

    file.ReadInt32(bits);
    snapshot.iJumps = bits;

    file.ReadInt8(snapshot.bsStyle);

    file.ReadInt32(bits);
    snapshot.iStrafes = bits;

    file.ReadInt32(bits);
    snapshot.iTotalMeasures = bits;

    file.ReadInt32(bits);
    snapshot.iGoodGains = bits;

    file.ReadInt32(bits);
    snapshot.fServerTime = view_as<float>(bits);

    file.ReadInt32(bits);
    snapshot.iKeyCombo = bits;

    file.ReadInt32(bits);
    snapshot.iTimerTrack = bits;

    file.ReadInt32(bits);
    snapshot.iTotalMeasures = bits;

    file.ReadInt32(bits);
    snapshot.iPerfectJumps = bits;

    file.ReadInt32(bits);
    snapshot.fZoneOffset[0] = view_as<float>(bits);

    file.ReadInt32(bits);
    snapshot.fZoneOffset[1] = view_as<float>(bits);

    file.ReadInt32(bits);
    snapshot.fDistanceOffset[0] = view_as<float>(bits);

    file.ReadInt32(bits);
    snapshot.fDistanceOffset[1] = view_as<float>(bits);

    file.ReadInt32(bits);
    snapshot.fAvgVelocity = view_as<float>(bits);

    file.ReadInt32(bits);
    snapshot.fMaxVelocity = view_as<float>(bits);

    file.ReadInt32(bits);
    snapshot.fTimescale = view_as<float>(bits);

    file.ReadInt32(bits);
    snapshot.iZoneIncrement = bits;

    file.ReadInt32(bits);
    snapshot.iFullTicks = bits;

    file.ReadInt32(bits);
    snapshot.iFractionalTicks = bits;

    file.ReadInt8(bits);
    snapshot.bPracticeMode = view_as<bool>(bits);

    file.ReadInt8(bits);
    snapshot.bJumped = view_as<bool>(bits);

    file.ReadInt8(bits);
    snapshot.bCanUseAllKeys = view_as<bool>(bits);

    file.ReadInt8(bits);
    snapshot.bOnGround = view_as<bool>(bits);

    file.ReadInt32(bits);
    snapshot.iLastButtons = bits;

    file.ReadInt32(bits);
    snapshot.fLastAngle = view_as<float>(bits);

    file.ReadInt32(bits);
    snapshot.iLandingTick = bits;

    file.ReadInt8(snapshot.iLastMoveType);

    file.ReadInt32(bits);
    snapshot.fStrafeWarning = view_as<float>(bits);

    file.ReadInt32(bits);
    snapshot.fLastInputVel[0] = view_as<float>(bits);

    file.ReadInt32(bits);
    snapshot.fLastInputVel[1] = view_as<float>(bits);

    file.ReadInt32(bits);
    snapshot.fplayer_speedmod = view_as<float>(bits);

    file.ReadInt32(bits);
    snapshot.fNextFrameTime = view_as<float>(bits);

    file.ReadInt32(bits);
    snapshot.iLastMoveTypeTAS = view_as<MoveType>(bits);

	return true;
}

// Do not use this func to record too many checkpoints. Otherwise, overwrite them using chunks.
stock bool SaveGameFile_WriteCheckpoints(File file, ArrayList checkpoints, int size)
{
    if (file == null)
    {
        LogError("[SaveGameFile]`WriteOutputWaits: file handle is null.");
        return false;
    }

    file.WriteInt32(size);

    cp_cache_t cache;

    for (int i = 0; i < size; i++)
    {
        checkpoints.GetArray(i, cache, sizeof(cp_cache_t));
        SaveGameFile_WriteCPCache(file, cache);
    }

    return true;
}

stock bool SaveGameFile_ReadCheckpoints(File file, ArrayList checkpoints)
{
    if (file == null)
    {
        LogError("[SaveGameFile]`ReadEvents: file handle is null.");
        return false;
    }

    int size;
    file.ReadInt32(size);

    if (size < 0)
    {
        return false;
    }

    cp_cache_t cache;

    for (int i = 0; i < size; i++)
    {
        SaveGameFile_ReadCPCache(file, cache);
        checkpoints.PushArray(cache, sizeof(cp_cache_t));
    }

    
    return true;
}

stock void SaveGameFile_WriteCPCache(File file, cp_cache_t cache)
{
    file.WriteInt32(view_as<int>(cache.fPosition[0]));
    file.WriteInt32(view_as<int>(cache.fPosition[1]));
    file.WriteInt32(view_as<int>(cache.fPosition[2]));

    file.WriteInt32(view_as<int>(cache.fAngles[0]));
    file.WriteInt32(view_as<int>(cache.fAngles[1]));
    file.WriteInt32(view_as<int>(cache.fAngles[2]));

    file.WriteInt32(view_as<int>(cache.fVelocity[0]));
    file.WriteInt32(view_as<int>(cache.fVelocity[1]));
    file.WriteInt32(view_as<int>(cache.fVelocity[2]));

    file.WriteInt32(view_as<int>(cache.iMoveType));
    file.WriteInt32(view_as<int>(cache.fGravity));
    file.WriteInt32(view_as<int>(cache.fSpeed));
    file.WriteInt32(view_as<int>(cache.fStamina));

    file.WriteInt8(view_as<int>(cache.bDucked));
    file.WriteInt8(view_as<int>(cache.bDucking));

    file.WriteInt32(view_as<int>(cache.fDucktime));
    file.WriteInt32(view_as<int>(cache.fDuckSpeed));
	
    file.WriteInt32(cache.iFlags);

    SaveGameFile_WriteSnapshot(file, cache.aSnapshot);

    file.WriteString(cache.sTargetname, true);
    file.WriteString(cache.sClassname, true);

    SaveGameFile_WriteReplayFrames(file, cache.aFrames, cache.aFrames.Length);

    file.WriteInt32(cache.iPreFrames);
    file.WriteInt8(view_as<int>(cache.bSegmented));
    file.WriteInt32(cache.iGroundEntity);
    file.WriteInt32(cache.iSteamID);
    
    SaveGameFile_WriteEvents(file, cache.aEvents, cache.aEvents.Length);
    SaveGameFile_WriteOutputWaits(file, cache.aOutputWaits, cache.aOutputWaits.Length);

    file.WriteInt32(view_as<int>(cache.vecLadderNormal[0]));
    file.WriteInt32(view_as<int>(cache.vecLadderNormal[1]));
    file.WriteInt32(view_as<int>(cache.vecLadderNormal[2]));
}

stock bool SaveGameFile_ReadCPCache(File file, cp_cache_t cache)
{
	if (file == null)
	{
		LogError("[SaveGameFile] Attempting to read cp_cache_t from a non-existent file.");
		return false;
	}

	cp_cache_t empty_cache;
	cache = empty_cache;

	int bits;

    file.ReadInt32(bits);
    cache.fPosition[0] = view_as<float>(bits);
    file.ReadInt32(bits);
    cache.fPosition[1] = view_as<float>(bits);
    file.ReadInt32(bits);
    cache.fPosition[2] = view_as<float>(bits);

    file.ReadInt32(bits);
    cache.fAngles[0] = view_as<float>(bits);
    file.ReadInt32(bits);
    cache.fAngles[1] = view_as<float>(bits);
    file.ReadInt32(bits);
    cache.fAngles[2] = view_as<float>(bits);

    file.ReadInt32(bits);
    cache.fVelocity[0] = view_as<float>(bits);
    file.ReadInt32(bits);
    cache.fVelocity[1] = view_as<float>(bits);
    file.ReadInt32(bits);
    cache.fVelocity[2] = view_as<float>(bits);

    file.ReadInt32(bits);
    cache.iMoveType = view_as<MoveType>(bits);

    file.ReadInt32(bits);
    cache.fGravity = view_as<float>(bits);

    file.ReadInt32(bits);
    cache.fSpeed = view_as<float>(bits);

    file.ReadInt32(bits);
    cache.fStamina = view_as<float>(bits);

    file.ReadInt8(bits);
    cache.bDucked = view_as<bool>(bits);

    file.ReadInt8(bits);
    cache.bDucking = view_as<bool>(bits);

    file.ReadInt32(bits);
    cache.fDucktime = view_as<float>(bits);

    file.ReadInt32(bits);
    cache.fDuckSpeed = view_as<float>(bits);

    file.ReadInt32(cache.iFlags);
	
    SaveGameFile_ReadSnapshot(file, cache.aSnapshot);

    file.ReadString(cache.sTargetname, 64);
    file.ReadString(cache.sClassname, 64);

    SaveGameFile_ReadReplayFrames(file, cache);

    file.ReadInt32(cache.iPreFrames);

    file.ReadInt8(bits);
    cache.bSegmented = view_as<bool>(bits);

    file.ReadInt32(cache.iGroundEntity);
    file.ReadInt32(cache.iSteamID);

    SaveGameFile_ReadEvents(file, cache);
    SaveGameFile_ReadOutputWaits(file, cache);

    file.ReadInt32(bits);
    cache.vecLadderNormal[0] = view_as<float>(bits);
    file.ReadInt32(bits);
    cache.vecLadderNormal[1] = view_as<float>(bits);
    file.ReadInt32(bits);
    cache.vecLadderNormal[2] = view_as<float>(bits);

    return true;
}

stock void SaveGameFile_CreateDir(const char[] dir)
{
    if (!DirExists(dir) && !CreateDirectory(dir, 511))
	{
        LogError("[SaveGameFile] Failed to create savegame folder (%s).", dir);
	}
}
