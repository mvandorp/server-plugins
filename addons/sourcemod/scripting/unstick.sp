#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.0.0"

public Plugin:myinfo = 
{
    name = "Unstick",
    author = "KitRifty, HowIChrgeLazer",
    description = "Attempts to unstick you from certain places.",
    version = PLUGIN_VERSION,
    url = ""
}

enum
{
	GAME_UNKNOWN = -1,
	GAME_TF2 = 0,
	GAME_HL2DM,
	GAME_CSS,
	GAME_CSGO
};

new g_iGame = GAME_UNKNOWN;
new g_teleportsLeft[MAXPLAYERS]; // Client teleports left array
new Handle:g_hNumOfTeleports; // Handle for number of allowed teleports
new Handle:g_hPluginAnnounce; // Handle for plugin announcement
new Handle:ClientDelayTimers[MAXPLAYERS][2]; // Timers for teleport delays on clients

// TF2
new Handle:g_hAvoidTeammates;
new bool:g_bAvoidTeammates;

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("unstick");
	CreateNative("Unstick_TestPlayerPosition", Native_TestPlayerPosition);
	CreateNative("Unstick_AttemptUnstick", Native_AttemptUnstick);
	return APLRes_Success;
}

public OnPluginStart()
{
	LoadTranslations("core.phrases");
	LoadTranslations("common.phrases");

	decl String:sGame[PLATFORM_MAX_PATH];
	GetGameFolderName(sGame, sizeof(sGame));

	if (StrEqual(sGame, "tf", false) || StrEqual(sGame, "tf_beta", false))
	{
		g_iGame = GAME_TF2;
		g_hAvoidTeammates = FindConVar("tf_avoidteammates");
		HookConVarChange(g_hAvoidTeammates, OnConVarChanged);
	}

	// Cvar for number of teleports a client can have
	g_hNumOfTeleports = CreateConVar("l4d2unstick_teleports", "3", "Amount of times the client can use !stuck per map", FCVAR_PLUGIN);
	g_hPluginAnnounce = CreateConVar("l4d2unstick_announce", "0", "Announces at each map start that the !stuck command is available", FCVAR_PLUGIN);

	// Say command hooks
	RegConsoleCmd("sm_stuck", Command_Unstuck);
	RegConsoleCmd("sm_unstuck", Command_Unstuck);
	RegAdminCmd("sm_unstick", Command_Unstick, ADMFLAG_SLAY);
}

public OnConfigsExecuted()
{
	if (g_iGame == GAME_TF2)
	{
		g_bAvoidTeammates = GetConVarBool(g_hAvoidTeammates);
	}
}

public OnConVarChanged(Handle:cvar, const String:oldValue[], const String:newValue[])
{
	if (cvar == g_hAvoidTeammates) g_bAvoidTeammates = bool:StringToInt(newValue);
}

public OnClientPutInServer(client)
{
	g_teleportsLeft[client] = GetConVarInt(g_hNumOfTeleports); // Number of teleports for client

	// Lets check if we're allowing annoucements
	if(GetConVarInt(g_hPluginAnnounce) == 1)
	{
		ClientDelayTimers[client][1] = CreateTimer(50.0, StuckPluginAnnounce, client);
	}
}

public OnClientDisconnect(client)
{
	if (ClientDelayTimers[client][0] != INVALID_HANDLE)
	{
		KillTimer(ClientDelayTimers[client][0]);
		ClientDelayTimers[client][0] = INVALID_HANDLE;
	}

	if (ClientDelayTimers[client][1] != INVALID_HANDLE)
	{
		KillTimer(ClientDelayTimers[client][1]);
		ClientDelayTimers[client][1] = INVALID_HANDLE;
	}
}

public Action:StuckPluginAnnounce(Handle:timer, any:client)
{
	// Announcement message
	PrintToChat (client, "[SM] Survivors: If you become glitched and unable to move, type !stuck during the round to free yourself.");
	ClientDelayTimers[client][1] = INVALID_HANDLE;
}

public Action:Command_Unstick(client, args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_unstick <name|#userid>");
		return Plugin_Handled;
	}
	
	decl String:arg1[32];
	GetCmdArg(1, arg1, sizeof(arg1));
	
	decl String:target_name[MAX_TARGET_LENGTH];
	decl target_list[MAXPLAYERS], target_count, bool:tn_is_ml;
	
	if ((target_count = ProcessTargetString(
			arg1,
			client,
			target_list,
			MAXPLAYERS,
			COMMAND_FILTER_ALIVE,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for (new i = 0; i < target_count; i++)
	{
		new target = target_list[i];
		AttemptUnstick(target);
	}
	
	return Plugin_Handled;
}

public Action:Command_Unstuck(client,args)
{
	if (IsValidClient(client))
	{
		// We're checking for client to say !stuck here, also check if client is hanging from a ledge
		new CheckLedge = GetEntProp(client, Prop_Send, "m_isHangingFromLedge");

		if (g_teleportsLeft[client] > 0 && CheckLedge == 0)
		{
			PrintToChat (client, "[SM] Unsticking in 3 seconds...");
			ClientDelayTimers[client][0] = CreateTimer(3.0, DelayTeleport, client);
		}
		else if (g_teleportsLeft[client] == 0)
		{
			// Client has 0 teleports left
			PrintToChat (client, "[SM] You are out of teleports this round!");
		}
		else if (CheckLedge == 1)
		{
			// Client is hanging from a ledge
			PrintToChat (client, "[SM] You cannot use !stuck right now!");
		}
	}
}

public Action:DelayTeleport(Handle:timer, any:client)
{
	if (IsValidClient(client) && AttemptUnstick(client))
	{
		// Notify the client that they have been unstuck and take away a teleport use
		g_teleportsLeft[client] = g_teleportsLeft[client] - 1;

		if(g_teleportsLeft[client] > 1 || g_teleportsLeft[client] == 0)
		{
			PrintToChat (client, "[SM] You have been unstuck! You have \"%i\" attempts left this map.", g_teleportsLeft[client]);
		}
		else
		{
			PrintToChat (client, "[SM] You have been unstuck! You have \"%i\" attempt left this map.", g_teleportsLeft[client]);
		}

		ClientDelayTimers[client][0] = INVALID_HANDLE;
	}
}

bool AttemptUnstick(client, bool:bUsePlayerCollision=true, const Float:flMins[3]=NULL_VECTOR, const Float:flMaxs[3]=NULL_VECTOR)
{
	decl Float:flTargetPos[3];
	GetClientAbsOrigin(client, flTargetPos);

	if (!TestEntityPosition(client, flTargetPos, bUsePlayerCollision, flMins, flMaxs))
	{
		decl Float:flForward[3], Float:flRight[3], Float:flUp[3];
		decl Float:flEyeAng[3];
		GetClientEyeAngles(client, flEyeAng);
		GetAngleVectors(flEyeAng, flForward, flRight, flUp);
		NormalizeVector(flForward, flForward);
		NormalizeVector(flRight, flRight);
		NormalizeVector(flUp, flUp);
		
		if (!FindPassableSpace(client, flUp, 1.0, flTargetPos, bUsePlayerCollision, flMins, flMaxs) && 
			!FindPassableSpace(client, flUp, -1.0, flTargetPos, bUsePlayerCollision, flMins, flMaxs) &&
			!FindPassableSpace(client, flForward, 1.0, flTargetPos, bUsePlayerCollision, flMins, flMaxs) &&
			!FindPassableSpace(client, flRight, 1.0, flTargetPos, bUsePlayerCollision, flMins, flMaxs) &&
			!FindPassableSpace(client, flRight, -1.0, flTargetPos, bUsePlayerCollision, flMins, flMaxs) &&
			!FindPassableSpace(client, flForward, -1.0, flTargetPos, bUsePlayerCollision, flMins, flMaxs))
		{	
			PrintToServer("Client %d failed to unstick at position %f %f %f", client, flTargetPos[0], flTargetPos[1], flTargetPos[2]);
		}
		
		TeleportEntity(client, flTargetPos, NULL_VECTOR, NULL_VECTOR);

		return true;
	}

	return false;
}

stock bool:TestEntityPosition(client, Float:flPos[3], bool:bUsePlayerCollision=true, const Float:flMins[3]=NULL_VECTOR, const Float:flMaxs[3]=NULL_VECTOR)
{
	decl Float:flPlayerMins[3], Float:flPlayerMaxs[3];
	if (!bUsePlayerCollision)
	{
		for (new i = 0; i < 3; i++)
		{
			flPlayerMins[i] = flMins[i];
			flPlayerMaxs[i] = flMaxs[i];
		}
	}
	else
	{
		GetEntPropVector(client, Prop_Send, "m_vecMins", flPlayerMins);
		GetEntPropVector(client, Prop_Send, "m_vecMaxs", flPlayerMaxs);
	}
	
	new Handle:hTrace = TR_TraceHullFilterEx(flPos, flPos, flPlayerMins, flPlayerMaxs, MASK_PLAYERSOLID, TraceRayDontHitPlayer, client);
	new bool:bDidHit = TR_DidHit(hTrace);
	CloseHandle(hTrace);
	
	return !bDidHit;
}

stock bool:FindPassableSpace(client, const Float:flDirection[3], Float:flStep, Float:flOldPos[3], bool:bUsePlayerCollision=true, const Float:flMins[3]=NULL_VECTOR, const Float:flMaxs[3]=NULL_VECTOR)
{
	decl Float:flPos[3];
	GetClientAbsOrigin(client, flPos);
	decl Float:flStepPos[3];
	decl Float:flStepDirection[3];
	for (new i = 0; i < 3; i++) 
	{
		flStepPos[i] = flPos[i];
		flStepDirection[i] = flStep * flDirection[i];
	}
	
	for (new i = 0; i < 100; i++)
	{
		if (TestEntityPosition(client, flStepPos, bUsePlayerCollision, flMins, flMaxs))
		{
			for (new i2 = 0; i2 < 3; i2++) flOldPos[i2] = flStepPos[i2];
			return true;
		}
		
		AddVectors(flStepPos, flStepDirection, flStepPos);
	}
	
	return false;
}

public bool:TraceRayDontHitPlayer(entity, contentsMask, any:data)
{
	if (entity == data) return false;
	if (IsValidClient(data))
	{
		if (g_iGame == GAME_TF2)
		{
			if (g_bAvoidTeammates)
			{
				if (IsValidClient(entity))
				{
					if (GetClientTeam(entity) == GetClientTeam(data)) return false;
				}
			}
			
			if (!IsValidClient(entity))
			{
				if (GetEntProp(entity, Prop_Data, "m_iTeamNum") == GetClientTeam(data)) return false;
			}
		}
	}
	
	return true;
}

stock bool:IsValidClient(client)
{
	if (client <= 0 || client > MaxClients) return false;
	if (!IsClientInGame(client)) return false;
	return true;
}

public Native_TestPlayerPosition(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if (!IsValidClient(client)) 
	{
		ThrowNativeError(SP_ERROR_PARAM, "Entity %d is not a valid client!", client);
		return false;
	}
	
	decl Float:flPos[3];
	decl Float:flMins[3];
	decl Float:flMaxs[3];
	GetNativeArray(2, flPos, 3);
	GetNativeArray(4, flMins, 3);
	GetNativeArray(5, flMaxs, 3);
	return TestEntityPosition(client, flPos, bool:GetNativeCell(3), flMins, flMaxs);
}

public Native_AttemptUnstick(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if (!IsValidClient(client)) 
	{
		ThrowNativeError(SP_ERROR_PARAM, "Entity %d is not a valid client!", client);
		return;
	}
	
	decl Float:flMins[3];
	decl Float:flMaxs[3];
	GetNativeArray(3, flMins, 3);
	GetNativeArray(4, flMaxs, 3);
	AttemptUnstick(client, bool:GetNativeCell(2), flMins, flMaxs);
}
