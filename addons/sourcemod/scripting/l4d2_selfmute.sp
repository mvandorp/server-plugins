#include <sourcemod>
#include <sdktools>

#include <scp>

#pragma semicolon 1

#define L4D2SELFM_VERSION   "0.4"

public Plugin:myinfo = {
    name = "L4D2 Self Mute",
    author = "Blade & Chdata",
    description = "Allows a player to local mute another client's text and voice chat.",
    version = L4D2SELFM_VERSION,
    url = "https://github.com/thebladeee/l4d2_selfmute"
};

enum Targeting
{
	String:arg[MAX_NAME_LENGTH],
	buffer[MAXPLAYERS],
	buffersize,
	String:targetname[MAX_TARGET_LENGTH],
	bool:tn_is_ml
};

static Target[Targeting];

enum IgnoreStatus
{
	bool:Chat,
	bool:Voice
};

static bool:IgnoreMatrix[MAXPLAYERS + 1][MAXPLAYERS + 1][IgnoreStatus];

public OnPluginStart()
{
	CreateConVar(
        "sm_l4d2sgag_version", L4D2SELFM_VERSION,
        "L4D2 Self Gag Version",
        FCVAR_REPLICATED|FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_DONTRECORD|FCVAR_NOTIFY
    );

	LoadTranslations("common.phrases"); //ignore <player>

	RegConsoleCmd("sm_smute", Command_Ignore, "Usage: sm_smute <#userid|name>\nSet target's chat and voice to be ignored.");

	RegConsoleCmd("sm_sunmute", Command_UnIgnore, "Usage: sm_sunmute <#userid|name>\nUnmutes target.");
}

/*
Check for necessary plugin dependencies and shut down this plugin if not found.

*/
public OnAllPluginsLoaded()
{
    if (!LibraryExists("scp"))
    {
        SetFailState("Simple Chat Processor is not loaded. It is required for this plugin to work.");
    }
}

/*
If a necessary plugin is removed, also shut this one down.

*/
public OnLibraryRemoved(const String:name[])
{
    if (StrEqual(name, "scp"))
    {
        SetFailState("Simple Chat Processor Unloaded. Plugin Disabled.");
    }
}

public OnClientDisconnect(client)
{
	for (new i = 0; i <= MAXPLAYERS; i++)
	{
		IgnoreMatrix[client][i][Chat] = false;
		IgnoreMatrix[client][i][Voice] = false;
	}
}

public Action:OnChatMessage(&author, Handle:recipients, String:name[], String:message[])
{
	if ((author < 0) || (author > MaxClients))
	{
		LogError("[Ignore list] Warning: author is out of bounds: %d", author);
		return Plugin_Continue;
	}
	new i = 0;
	new client;
	while (i < GetArraySize(recipients))
	{
		client = GetArrayCell(recipients, i);
		if ((client < 0) || (client > MaxClients))
		{
			LogError("[L4D2 Self Mute] Warning: client is out of bounds: %d, Try updating SCP", client);
			i++;
			continue;
		}
		if (IgnoreMatrix[client][author][Chat])
		{
			RemoveFromArray(recipients, i);
		}
		else
		{
			i++;
		}
	}
	return Plugin_Changed;
}

public Action:Command_Ignore(client, args)
{
	if (args == 0)
	{
		ReplyToCommand(client, "Usage: sm_smute <#userid|name>");
		return Plugin_Handled;
	}

	ProcessIgnore(client, true, true, 3);

	return Plugin_Handled;
}

/*
client is the person ignoring someone
the chat/voice bool says what we want to set their status to
which says whether or not we're actually changing chat 1, voice 2, or both 3

*/
stock ProcessIgnore(client, const bool:chat = false, const bool:voice = false, const which)
{
	GetCmdArg(1, Target[arg], MAX_NAME_LENGTH);

	new bool:bTargetAll = false;

	if (strcmp(Target[arg], "@all", false) == 0)
	{
		bTargetAll = true;
	}

	Target[buffersize] = ProcessTargetString(Target[arg], client, Target[buffer], MAXPLAYERS, COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_IMMUNITY, Target[targetname], MAX_TARGET_LENGTH, Target[tn_is_ml]);

	if (Target[buffersize] <= 0)
	{
		ReplyToTargetError(client, Target[buffersize]);
		return;
	}

	for (new i = 0; i < Target[buffersize]; i++)
	{
		ToggleIgnoreStatus(client, Target[buffer][i], chat, voice, which, bTargetAll);
	}

	if (bTargetAll)
	{
		decl String:s[MAXLENGTH_MESSAGE];

		Format(s, sizeof(s), "[SM] All Players - Chat: %s | Voice: %s",
			!(which & 1) ? "Unchanged" : chat ? "OFF" : "ON",
			!(which & 2) ? "Unchanged" : voice ? "OFF" : "ON"
		);

		ReplyToCommand(client, s);
	}

	return;
}

ToggleIgnoreStatus(const client, const target, const bool:chat, const bool:voice, const which, const bool:bTargetAll)
{
	if (which & 1)
	{
		IgnoreMatrix[client][target][Chat] = chat;
	}

	if (which & 2)
	{
		IgnoreMatrix[client][target][Voice] = voice;

		if (IgnoreMatrix[client][target][Voice])
		{
			SetListenOverride(client, target, Listen_No);
		}
		else
		{
			SetListenOverride(client, target, Listen_Default);
		}
	}

	if (bTargetAll)
	{
		return;
	}

	decl String:s[MAXLENGTH_MESSAGE];

	Format(s, sizeof(s), "[SM] %N - Chat: %s | Voice: %s",
		target,
		IgnoreMatrix[client][target][Chat] ? "OFF" : "ON",
		IgnoreMatrix[client][target][Voice] ? "OFF" : "ON"
	);

	ReplyToCommand(client, s);
	return;
}

public Action:Command_UnIgnore(client, args)
{
	if (args == 0)
	{
		ReplyToCommand(client, "Usage: sm_sunmute <#userid|name>");
		return Plugin_Handled;
	}

	ProcessIgnore(client, false, false, 3);

	return Plugin_Handled;
}

/*
Sets up a native to send whether or not a client is ignoring a specific target's chat

*/
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("GetIgnoreMatrix", Native_GetIgnoreMatrix);

	RegPluginLibrary("ignorematrix");

	return APLRes_Success;
}

/*
The native itself

*/
public Native_GetIgnoreMatrix(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	new target = GetNativeCell(2);

	return IgnoreMatrix[client][target][Chat];
}