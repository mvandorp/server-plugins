#pragma semicolon 1

#include <sourcemod>
#include <l4d2_direct>
#define L4D2UTIL_STOCKS_ONLY
#include <l4d2util>
#undef REQUIRE_PLUGIN
#include <readyup>
#include <colors>

public Plugin:myinfo =
{
	name = "L4D2 Boss Flow Announce (Back to roots edition)",
	author = "ProdigySim, Jahze, Stabby, CircleSquared, CanadaRox, Visor",
	version = "1.6.1",
	description = "Announce boss flow percents!",
	url = "https://github.com/ConfoglTeam/ProMod"
};

new iWitchPercent = 0;
new iTankPercent = 0;

new Handle:g_hVsBossBuffer;
new Handle:hCvarPrintToEveryone;
new Handle:hCvarTankPercent;
new Handle:hCvarWitchPercent;
new bool:readyUpIsAvailable;
new bool:readyFooterAdded;

#define MAX(%0,%1) (((%0) > (%1)) ? (%0) : (%1))

//new Handle:hCvarPrintToEveryone;
new Handle:survivor_limit;
new Handle:z_max_player_zombies;

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("UpdateBossPercents", Native_UpdateBossPercents);
	MarkNativeAsOptional("AddStringToReadyFooter");
	RegPluginLibrary("l4d_boss_percent");
	return APLRes_Success;
}

public OnPluginStart()
{
	g_hVsBossBuffer = FindConVar("versus_boss_buffer");

	hCvarPrintToEveryone = CreateConVar("l4d_global_percent", "1", "Display boss percentages to entire team when using commands", FCVAR_PLUGIN);
	hCvarTankPercent = CreateConVar("l4d_tank_percent", "1", "Display Tank flow percentage in chat", FCVAR_PLUGIN);
	hCvarWitchPercent = CreateConVar("l4d_witch_percent", "1", "Display Witch flow percentage in chat", FCVAR_PLUGIN);

	RegConsoleCmd("sm_boss", BossCmd);
	RegConsoleCmd("sm_tank", BossCmd);
	RegConsoleCmd("sm_witch", BossCmd);

	HookEvent("player_left_start_area", LeftStartAreaEvent, EventHookMode_PostNoCopy);
	HookEvent("round_start", RoundStartEvent, EventHookMode_PostNoCopy);
	
	/*
	hCvarPrintToEveryone =
		CreateConVar("l4d_global_percent", "1",
				"Display boss percentages to entire team when using commands",
				FCVAR_PLUGIN);
	*/
	RegConsoleCmd("sm_cur", CurrentCmd);
	RegConsoleCmd("sm_current", CurrentCmd);

	survivor_limit = FindConVar("survivor_limit");
	z_max_player_zombies = FindConVar("z_max_player_zombies");
}

public OnAllPluginsLoaded()
{
	readyUpIsAvailable = LibraryExists("readyup");
}

public OnLibraryRemoved(const String:name[])
{
	if (StrEqual(name, "readyup")) readyUpIsAvailable = false;
}

public OnLibraryAdded(const String:name[])
{
	if (StrEqual(name, "readyup")) readyUpIsAvailable = true;
}

public LeftStartAreaEvent(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!readyUpIsAvailable)
		for (new client = 1; client <= MaxClients; client++)
			if (IsClientConnected(client) && IsClientInGame(client))
				PrintBossPercents(client);
}

public OnRoundIsLive()
{
	for (new client = 1; client <= MaxClients; client++)
		if (IsClientConnected(client) && IsClientInGame(client))
			PrintBossPercents(client);
}

public RoundStartEvent(Handle:event, const String:name[], bool:dontBroadcast)
{
	readyFooterAdded = false;

	CreateTimer(5.0, SaveBossFlows);
	CreateTimer(6.0, AddReadyFooter); // workaround for boss equalizer
}

public Native_UpdateBossPercents(Handle:plugin, numParams)
{
	CreateTimer(0.1, SaveBossFlows);
	CreateTimer(0.2, AddReadyFooter);
	return true;
}

public Action:SaveBossFlows(Handle:timer)
{
	if (!InSecondHalfOfRound())
	{
		iWitchPercent = 0;
		iTankPercent = 0;

		if (L4D2Direct_GetVSWitchToSpawnThisRound(0))
		{
			iWitchPercent = RoundToNearest(GetWitchFlow(0)*100.0);
		}
		if (L4D2Direct_GetVSTankToSpawnThisRound(0))
		{
			iTankPercent = RoundToNearest(GetTankFlow(0)*100.0);
		}
	}
	else
	{
		if (iWitchPercent != 0)
		{
			iWitchPercent = RoundToNearest(GetWitchFlow(1)*100.0);
		}
		if (iTankPercent != 0)
		{
			iTankPercent = RoundToNearest(GetTankFlow(1)*100.0);
		}
	}
}

public Action:AddReadyFooter(Handle:timer)
{
	if (readyFooterAdded) return;
	if (readyUpIsAvailable)
	{
		decl String:readyString[65];
		if (iWitchPercent && iTankPercent)
			Format(readyString, sizeof(readyString), "Tank: %d%%, Witch: %d%%", iTankPercent, iWitchPercent);
		else if (iTankPercent)
			Format(readyString, sizeof(readyString), "Tank: %d%%, Witch: None", iTankPercent);
		else if (iWitchPercent)
			Format(readyString, sizeof(readyString), "Tank: None, Witch: %d%%", iWitchPercent);
		else
			Format(readyString, sizeof(readyString), "Tank: None, Witch: None");
		AddStringToReadyFooter(readyString);
		readyFooterAdded = true;
	}
}

stock PrintBossPercents(client)
{
	if(GetConVarBool(hCvarTankPercent))
	{
		if (iTankPercent)
			CPrintToChat(client, "<{red}Tank{default}> {olive}%d%%{default}", iTankPercent);
		else
			CPrintToChat(client, "<{red}Tank{default}> {olive}None{default}");
	}

	if(GetConVarBool(hCvarWitchPercent))
	{
		if (iWitchPercent)
			CPrintToChat(client, "<{red}Witch{default}> {olive}%d%%{default}", iWitchPercent);
		else
			CPrintToChat(client, "<{red}Witch{default}> {olive}None{default}");
	}
}

public Action:BossCmd(client, args)
{
	new L4D2_Team:iTeam = L4D2_Team:GetClientTeam(client);
	if (iTeam == L4D2Team_Spectator)
	{
		PrintBossPercents(client);
		PrintCurrentToClient(client);
		return Plugin_Handled;
	}

	if (GetConVarBool(hCvarPrintToEveryone))
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i) && IsClientInGame(i) && L4D2_Team:GetClientTeam(i) == iTeam)
			{
				PrintBossPercents(i);
				PrintCurrentToClient(i);																//HERE
			}
		}
	}
	else
	{
		PrintBossPercents(client);
		PrintCurrentToClient(client);																	//HERE
	}

	return Plugin_Handled;
}

stock Float:GetTankFlow(round)
{
	return L4D2Direct_GetVSTankFlowPercent(round) -
		( Float:GetConVarInt(g_hVsBossBuffer) / L4D2Direct_GetMapMaxFlowDistance() );
}

stock Float:GetWitchFlow(round)
{
	return L4D2Direct_GetVSWitchFlowPercent(round) -
		( Float:GetConVarInt(g_hVsBossBuffer) / L4D2Direct_GetMapMaxFlowDistance() );
}

public Action:CurrentCmd(client, args)
{
	new L4D2_Team:team = L4D2_Team:GetClientTeam(client);
	if (team == L4D2Team_Spectator)
	{
		PrintCurrentToClient(client);
	}
	else
	{
		if (GetConVarBool(hCvarPrintToEveryone))
		{
			PrintCurrentToTeam(team);																	//HERE
		}
		else
		{
			PrintCurrentToClient(client);
		}
	}
}

stock PrintCurrentToClient(client)
{
	CPrintToChat(client, "<{green}Current{default}> {olive}%d%%", GetMaxSurvivorCompletion());
}
																										//HERE
stock PrintCurrentToTeam(L4D2_Team:team)
{
	new members_found;
	new team_max = GetTeamMaxHumans(team);
	new max_completion = GetMaxSurvivorCompletion();
	for (new client = 1;
			client <= MaxClients && members_found < team_max;
			client++)
	{
		if(IsClientInGame(client) && !IsFakeClient(client) &&
				L4D2_Team:GetClientTeam(client) == team)
		{
			members_found++;
			CPrintToChat(client, "<{green}Current{default}> {olive}%d%%", max_completion);
		}
	}
}

stock GetMaxSurvivorCompletion()
{
	new Float:flow = 0.0;
	decl Float:tmp_flow;
	decl Float:origin[3];
	decl Address:pNavArea;
	for (new client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client) &&
			L4D2_Team:GetClientTeam(client) == L4D2Team_Survivor)
		{
			GetClientAbsOrigin(client, origin);
			pNavArea = L4D2Direct_GetTerrorNavArea(origin);
			if (pNavArea != Address_Null)
			{
				tmp_flow = L4D2Direct_GetTerrorNavAreaFlow(pNavArea);
				flow = MAX(flow, tmp_flow);
			}
		}
	}
	return RoundToNearest(flow * 100 / L4D2Direct_GetMapMaxFlowDistance());
}

stock GetTeamMaxHumans(L4D2_Team:team)
{
	if (team == L4D2Team_Survivor)
	{
		return GetConVarInt(survivor_limit);
	}
	else if (team == L4D2Team_Infected)
	{
		return GetConVarInt(z_max_player_zombies);
	}
	return MaxClients;
}
