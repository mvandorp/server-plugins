#include <sourcemod>
#include <sdktools>

#define VOICE_NORMAL	0	/**< Allow the client to listen and speak normally. */
#define VOICE_MUTED		1	/**< Mutes the client from speaking to everyone. */
#define VOICE_SPEAKALL	2	/**< Allow the client to speak to everyone. */
#define VOICE_LISTENALL	4	/**< Allow the client to listen to everyone. */
#define VOICE_TEAM		8	/**< Allow the client to always speak to team, even when dead. */
#define VOICE_LISTENTEAM	16	/**< Allow the client to always hear teammates, including dead ones. */

#define TEAM_SPEC 1
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

Handle hCvarListenChatAccess = INVALID_HANDLE;
Handle hCvarListenVoiceAccess = INVALID_HANDLE;

public Plugin myinfo =
{
	name = "SpecLister",
	author = "waertf & bear modded by bman",
	description = "Allows spectator listen others team voice for l4d",
	version = "2.1.3",
	url = "http://forums.alliedmods.net/showthread.php?t=95474"
}

/*============================================================================*/
/* Global forwards                                                            */
/*============================================================================*/

public OnPluginStart()
{
	hCvarListenChatAccess = CreateConVar("speclistener_chat_access", "", "Access level needed to read teamchat as a spectator", FCVAR_PLUGIN);
	hCvarListenVoiceAccess = CreateConVar("speclistener_voice_access", "", "Access level needed to hear voicechat as a spectator", FCVAR_PLUGIN);

	HookEvent("player_team", Event_PlayerChangeTeam);

	//Fix for End of round all-talk.
	HookConVarChange(FindConVar("sv_alltalk"), OnAlltalkChange);

	RegConsoleCmd("hear", Command_Hear);
	RegConsoleCmd("say_team", Command_SayTeam);
}

/*============================================================================*/
/* Events / Commands                                                          */
/*============================================================================*/

public Action Command_Hear(int client, args)
{
	if (GetClientTeam(client) != TEAM_SPEC)
		return Plugin_Handled;

	if (!HasListenVoiceAccess(client)) {
		PrintToChat(client, "You do not have access to this command.");
		return Plugin_Handled;
	}

	Handle panel = CreatePanel();
	SetPanelTitle(panel, "Enable listen mode?");
	DrawPanelItem(panel, "Yes");
	DrawPanelItem(panel, "No");

	SendPanelToClient(panel, client, ListenPanelHandler, 20);

	CloseHandle(panel);

	return Plugin_Handled;
}

public Action Command_SayTeam(int client, args)
{
	if (client == 0)
		return Plugin_Continue;

	char buffermsg[256];
	char text[192];
	GetCmdArgString(text, sizeof(text));
	int senderteam = GetClientTeam(client);

	if (FindCharInString(text, '@') == 0)	//Check for admin messages
		return Plugin_Continue;

	int startidx = TrimQuotes(text);

	char name[32];
	GetClientName(client,name,31);

	char senderTeamName[10];
	switch (senderteam)
	{
		case 3:
			senderTeamName = "INFECTED"
		case 2:
			senderTeamName = "SURVIVORS"
		case 1:
			senderTeamName = "SPEC"
	}

	//Is not console, Sender is not on Spectators, and there are players on the spectator team
	if (client > 0 && senderteam != TEAM_SPEC && GetTeamClientCount(TEAM_SPEC) > 0)
	{
		for (new i = 1; i <= GetMaxClients(); i++)
		{
			if (IsClientInGame(i) && GetClientTeam(i) == TEAM_SPEC && HasListenChatAccess(i))
			{
				switch (senderteam)	//Format the color different depending on team
				{
					case 3:
						Format(buffermsg, 256, "\x01(%s) \x04%s\x05: %s", senderTeamName, name, text[startidx]);
					case 2:
						Format(buffermsg, 256, "\x01(%s) \x03%s\x05: %s", senderTeamName, name, text[startidx]);
				}
				//Format(buffermsg, 256, "\x01(TEAM-%s) \x03%s\x05: %s", senderTeamName, name, text[startidx]);
				SayText2(i, client, buffermsg);	//Send the message to spectators
			}
		}
	}
	return Plugin_Continue;
}

public ListenPanelHandler(Handle menu, MenuAction action, param1, param2)
{
	if (action == MenuAction_Select)
	{
		PrintToConsole(param1, "You selected item: %d", param2)
		if (param2 == 1)
		{
			SetClientListeningFlags(param1, VOICE_LISTENALL);
			PrintToChat(param1,"\x04[Listen Mode]\x03Enabled" );
		}
		else
		{
			SetClientListeningFlags(param1, VOICE_NORMAL);
			PrintToChat(param1,"\x04[Listen Mode]\x03Disabled" );
		}
	}
	else if (action == MenuAction_Cancel)
	{
		PrintToServer("Client %d's menu was cancelled.  Reason: %d", param1, param2);
	}
}

public Event_PlayerChangeTeam(Handle event, const char[] name, bool dontBroadcast)
{
	int userID = GetEventInt(event, "userid");
	int userTeam = GetEventInt(event, "team");
	int client = GetClientOfUserId(userID);

	if (client == 0)
		return;

	if (userTeam == TEAM_SPEC && IsValidClient(client) && HasListenVoiceAccess(client))
	{
		SetClientListeningFlags(client, VOICE_LISTENALL);
	}
	else
	{
		SetClientListeningFlags(client, VOICE_NORMAL);
	}
}

public OnAlltalkChange(Handle convar, const char[] oldValue, const char[] newValue)
{
	if (StringToInt(newValue) == 0)
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && GetClientTeam(i) == TEAM_SPEC && HasListenVoiceAccess(i))
			{
				SetClientListeningFlags(i, VOICE_LISTENALL);
			}
		}
	}
}

/*============================================================================*/
/* Helper functions                                                           */
/*============================================================================*/

static bool IsValidClient(int client)
{
	if (client == 0)
		return false;

	if (!IsClientConnected(client))
		return false;

	if (IsFakeClient(client))
		return false;

	if (!IsClientInGame(client))
		return false;

	return true;
}

static bool HasListenChatAccess(int client)
{
	return HasAccess(client, hCvarListenChatAccess);
}

static bool HasListenVoiceAccess(int client)
{
	return HasAccess(client, hCvarListenVoiceAccess);
}

static bool HasAccess(int client, Handle hCvarAccessFlag)
{
	char flagString[128];
	GetConVarString(hCvarAccessFlag, flagString, sizeof(flagString));

	if (strlen(flagString) == 0) return true;

	int accessFlags = ReadFlagString(flagString);

	return (GetUserFlagBits(client) & accessFlags) == accessFlags;
}

static int TrimQuotes(char[] text)
{
	new startidx = 0
	if (text[0] == '"')
	{
		startidx = 1
		/* Strip the ending quote, if there is one */
		new len = strlen(text);
		if (text[len-1] == '"')
		{
			text[len-1] = '\0'
		}
	}

	return startidx
}

static SayText2(int client, int author, const char[] message)
{
	Handle buffer = StartMessageOne("SayText2", client)
	if (buffer != INVALID_HANDLE)
	{
		BfWriteByte(buffer, author)
		BfWriteByte(buffer, true)
		BfWriteString(buffer, message)
		EndMessage()
	}
}
