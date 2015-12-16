#include <sourcemod>

#pragma semicolon 1

#define PLUGIN_VERSION "1.5.5"
#define CVAR_FLAGS FCVAR_PLUGIN
#define TEAM_SPECTATOR 1
#define TEAM_INFECTED 3
#define VOTE_DELAY 5.0

public Plugin:myinfo =
{
	name = "L4D Vote Manager 2",
	author = "Madcap",
	description = "Control permissions on voting and make voting respect admin levels.",
	version = PLUGIN_VERSION,
	url = "http://maats.org"
};

// cvar handles
new Handle:alltalkAccess;
new Handle:lobbyAccess;
new Handle:difficultyAccess;
new Handle:levelAccess;
new Handle:restartAccess;
new Handle:kickAccess;
new Handle:kickImmunity;
new Handle:tankKickImmunity;

public OnPluginStart()
{
	RegConsoleCmd("callvote", Callvote_Handler);

	alltalkAccess       = CreateConVar("l4d_vote_alltalk_access",         "",  "Access level needed to start a change all talk vote", CVAR_FLAGS);
	lobbyAccess         = CreateConVar("l4d_vote_lobby_access",           "",  "Access level needed to start a return to lobby vote", CVAR_FLAGS);
	difficultyAccess    = CreateConVar("l4d_vote_difficulty_access",      "",  "Access level needed to start a change difficulty vote", CVAR_FLAGS);
	levelAccess         = CreateConVar("l4d_vote_level_access",           "",  "Access level needed to start a change level vote", CVAR_FLAGS);
	restartAccess       = CreateConVar("l4d_vote_restart_access",         "",  "Access level needed to start a restart level vote", CVAR_FLAGS);
	kickAccess          = CreateConVar("l4d_vote_kick_access",            "",  "Access level needed to start a kick vote", CVAR_FLAGS);
	kickImmunity        = CreateConVar("l4d_vote_kick_immunity",          "1", "Make votekick respect admin immunity", CVAR_FLAGS, true, 0.0, true, 1.0);
	tankKickImmunity    = CreateConVar("l4d_vote_tank_kick_immunity",     "0", "Make tanks immune to vote kicking.", CVAR_FLAGS, true, 0.0, true, 1.0);

	AutoExecConfig(true, "sm_plugin_votemanager2");

	CreateConVar("l4d_votemanager2", PLUGIN_VERSION, "Version number for Vote Manager 2 Plugin", FCVAR_REPLICATED|FCVAR_NOTIFY);
}

// return true if client can make the vote
public hasVoteAccess(client, String:voteName[32])
{
	// rcon always has access
	if (client == 0) {
		return true;
	}

	new String:acclvl[16];

	if (strcmp(voteName, "ReturnToLobby", false) == 0) {
		GetConVarString(lobbyAccess, acclvl, sizeof(acclvl));
	}
	else if (strcmp(voteName, "ChangeAllTalk", false) == 0) {
		GetConVarString(alltalkAccess, acclvl, sizeof(acclvl));
	}
	else if (strcmp(voteName, "ChangeDifficulty", false) == 0) {
		GetConVarString(difficultyAccess, acclvl, sizeof(acclvl));
	}
	else if (strcmp(voteName, "ChangeMission", false) == 0 || strcmp(voteName, "ChangeChapter", false) == 0) {
		GetConVarString(levelAccess, acclvl, sizeof(acclvl));
	}
	else if (strcmp(voteName, "RestartGame", false) == 0) {
		GetConVarString(restartAccess, acclvl, sizeof(acclvl));
	}
	else if (strcmp(voteName, "Kick", false) == 0) {
		GetConVarString(kickAccess, acclvl, sizeof(acclvl));
	}
	// voteName does not match a known vote type
	else return false;

	// no permissions set
	if (strlen(acclvl) == 0)
		return true;

	// check permissions
	if (GetUserFlagBits(client) & ReadFlagString(acclvl) == 0)
		return false;

	return true;
}

// check a vote name against the known possible votes
public isValidVote(String:voteName[32])
{
	if ((strcmp(voteName, "Kick", false) == 0) ||
		(strcmp(voteName, "ReturnToLobby", false) == 0) ||
		(strcmp(voteName, "ChangeAllTalk", false) == 0) ||
		(strcmp(voteName, "ChangeDifficulty", false) == 0) ||
		(strcmp(voteName, "ChangeMission", false) == 0) ||
		(strcmp(voteName, "RestartGame", false) == 0) ||
		(strcmp(voteName, "Custom", false) == 0) ||
		(strcmp(voteName, "ChangeChapter", false) == 0)) {
		return true;
	}

	return false;
}

public Action:Callvote_Handler(client, args)
{
	decl String:voteName[32];
	decl String:initiatorName[MAX_NAME_LENGTH];
	GetClientName(client, initiatorName, sizeof(initiatorName));
	GetCmdArg(1, voteName, sizeof(voteName));

	if (GetClientTeam(client) == TEAM_SPECTATOR) {
		PrintToChat(client, "\x04[VOTE] \x01You cannot start a vote as spectator.");
		return Plugin_Handled;
	}

	// Someone is starting an unknown vote, fine, go ahead.
	if (!isValidVote(voteName)) {
		return Plugin_Continue;
	}

	if (hasVoteAccess(client, voteName)) {
		// confirmed player has access to the vote type, now handle any logic for specific types of vote
		// (currently only defined for kick votes)

		if (strcmp(voteName, "Kick", false) == 0) {
			// this function must return either Plugin_Handled or Plugin_Continue
			return Kick_Vote_Logic(client, args);
		}

		return Plugin_Continue;
	}
	else {
		// player does not have access to this vote
		PrintToChat(client, "\x04[VOTE] \x01You do not have sufficient access to start a %s vote.", voteName);

		return Plugin_Handled;
	}
}

// special logic for handling kick votes
public Action:Kick_Vote_Logic(client, args)
{
	// return Plugin_Handled;  - to prevent the vote from going through
	// return Plugin_Continue; - to allow the vote to go like normal

	decl String:initiatorName[MAX_NAME_LENGTH];
	GetClientName(client, initiatorName, sizeof(initiatorName));

	decl String:arg2[12];
	GetCmdArg(2, arg2, sizeof(arg2));
	new target = GetClientOfUserId(StringToInt(arg2));

	// check that the person targeted for kicking is actually a client
	if (target <= 0 || !IsClientInGame(target)) {
		PrintToChat(client, "\x04[VOTE] \x01%s is not a valid target.", arg2);
		PrintToChat(client, "\x04[VOTE] \x01If you are trying to call a manual kick vote the format is: 'callvote kick <user id>'");

		return Plugin_Handled;
	}

	decl String:targetName[MAX_NAME_LENGTH];
	GetClientName(target, targetName, sizeof(targetName));

	// tanks cannot be kicked if the convar is set to 1
	if (GetConVarBool(tankKickImmunity) && (GetClientTeam(target) == TEAM_INFECTED) && IsPlayerAlive(target)) {
		new String:model[128];
		GetClientModel(target, model, sizeof(model));

		if (StrContains(model, "hulk", false) > 0) {
			PrintToChat(client, "\x04[VOTE] \x01Tanks cannot be kicked.");

			return Plugin_Handled;
		}
	}

	// If the "kickImmunity" flag is set, we have to check admin rights of the client and target
	if (GetConVarBool(kickImmunity)) {
		new AdminId:clientAdminId = GetUserAdmin(client);
		new AdminId:targetAdminId = GetUserAdmin(target);

		// we only care about immunity if the target is admin
		if (isAdmin(targetAdminId)) {

			// based on admin access, can client kick the target?
			if (!CanAdminTarget(clientAdminId, targetAdminId)) {
				// client does not have permisison to kick target
				PrintToChat(client, "\x04[VOTE] \x01%s has immunity.", targetName);

				return Plugin_Handled;
			}
		}
	}

	return Plugin_Continue;
}

// this is for clarity only
public bool:isAdmin(AdminId:id)
{
	return id != INVALID_ADMIN_ID;
}
