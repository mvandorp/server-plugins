#include <sourcemod>

#define ERR_SQL_CONNECT_FAILED          "Failed to connect to SQL database. %s"
#define ERR_SQL_CREATE_TABLES_FAILED    "Failed to create SQL tables. %s"
#define ERR_SQL_EXECUTE_QUERY_FAILED    "Failed to execute SQL query. %s"
#define ERR_SQL_PREPARE_QUERY_FAILED    "Failed to prepare SQL query. %s"
#define ERR_HOOK_EVENT_FAILED           "Failed to hook event '%s'."

#undef MAX_NAME_LENGTH

#define MAX_NAME_LENGTH                 (32 + 1)
#define MAX_TEAM_LENGTH                 (10 + 1)
#define MAX_IP_LENGTH                   (15 + 1)
#define MAX_STEAMID_LENGTH              (20 + 1)
#define MAX_DATETIME_LENGTH             (19 + 1)
#define MAX_ARG_SIZE                    33

#define TEAM_UNASSIGNED 0
#define TEAM_SPECTATORS 1
#define TEAM_SURVIVORS 2
#define TEAM_INFECTED 3

#define IS_VALID_CLIENT(%1)             ((%1) > 0 && (%1) <= MaxClients)
#define IS_VALID_INGAME(%1)             (IS_VALID_CLIENT(%1) && IsClientInGame(%1))

#define EVENTFLAGS_CHAT                 (1 << 0)
#define EVENTFLAGS_TEAMCHAT             (1 << 1)
#define EVENTFLAGS_TEAM_SPECTATORS      (TEAM_SPECTATORS << 2)
#define EVENTFLAGS_TEAM_SURVIVORS       (TEAM_SURVIVORS << 2)
#define EVENTFLAGS_TEAM_INFECTED        (TEAM_INFECTED << 2)

public Plugin myinfo =
{
    name = "Logger",
    author = "Martijn",
    description = "Logs things.",
    version = "0.8",
    url = "http://www.sourcemod.net/"
};

static Database g_hDatabase = Database:INVALID_HANDLE;
static int g_iLogID = 0;
static int g_iPlayerIds[MAXPLAYERS + 1] = { 0, ... };
static bool g_bTeamSay[MAXPLAYERS + 1] = { false, ... };

public void OnPluginStart()
{
    g_hDatabase = ConnectToDatabase("sourcebans");

    RegConsoleCmd("say", OnSay);
    RegConsoleCmd("say_team", OnSayTeam);

    // TryHookEvent("player_connect", OnPlayerConnect);
    TryHookEvent("player_disconnect", OnPlayerDisconnect);
    TryHookEvent("player_changename", OnPlayerChangeName);
    TryHookEvent("player_say", OnPlayerChat);
    TryHookEvent("player_team", OnPlayerChangeTeam);

    HookUserMessage(GetUserMessageId("VoteStart"), OnVoteStart);
    HookUserMessage(GetUserMessageId("VotePass"), OnVotePass);
    HookUserMessage(GetUserMessageId("VoteFail"), OnVoteFail);
}

public void OnPluginEnd()
{
    CloseHandle(g_hDatabase);
}

//===========================================================================//
// Logging stuff                                                             //
//===========================================================================//

static int LogPlayerId(const char[] steamid)
{
    char query[256];
    Format(query, sizeof(query), "INSERT INTO sb_player_ids (steamid) VALUES ('%s') ON DUPLICATE KEY UPDATE id=LAST_INSERT_ID(id)", steamid);

    SQL_LockDatabase(g_hDatabase);
    FastQuery(g_hDatabase, query);
    int playerid = SQL_GetInsertId(g_hDatabase);
    SQL_UnlockDatabase(g_hDatabase);

    return playerid;
}

static void LogPlayerIP(int playerid, const char[] ip)
{
    // Get the current date and time
    char datetime[MAX_DATETIME_LENGTH];
    FormatTime(datetime, sizeof(datetime), "%Y-%m-%d %H:%M:%S");

    char query[256];
    Format(query, sizeof(query), "INSERT INTO sb_player_ips (playerid, ip, last_seen) VALUES (%d, '%s', '%s') ON DUPLICATE KEY UPDATE last_seen = '%s'", playerid, ip, datetime, datetime);

    g_hDatabase.Query(OnQueryCompleted, query);
}

static void LogPlayerName(int playerid, const char[] name)
{
    char escapedName[2 * MAX_NAME_LENGTH];
    g_hDatabase.Escape(name, escapedName, sizeof(escapedName));

    // Get the current date and time
    char datetime[MAX_DATETIME_LENGTH];
    FormatTime(datetime, sizeof(datetime), "%Y-%m-%d %H:%M:%S");

    char query[256];
    Format(query, sizeof(query), "INSERT INTO sb_player_names (playerid, name, last_seen) VALUES (%d, '%s', '%s') ON DUPLICATE KEY UPDATE last_seen = '%s'", playerid, escapedName, datetime, datetime);

    g_hDatabase.Query(OnQueryCompleted, query);
}

static void LogServerEvent(int playerid, const char[] text, any ...)
{
    char formattedText[256];

    // Format the text
    VFormat(formattedText, sizeof(formattedText), text, 3);

    LogEvent(playerid, "CONSOLE", GetEventFlags(false, false, 0), formattedText);
}

static void LogChatEvent(int playerid, const char[] name, bool teamChat, int team, const char[] text)
{
    LogEvent(playerid, name, GetEventFlags(true, teamChat, team), text);
}

static void LogEvent(int playerid, const char[] name, int flags, const char[] text)
{
    char query1[512], query2[128];
    char formattedText[256], escapedText[256], escapedName[64];
    char datetime[MAX_DATETIME_LENGTH];

    // Ensure that a log is opened
    if (g_iLogID == 0)
        g_iLogID = CreateLog(g_hDatabase);

    // Format the text
    VFormat(formattedText, sizeof(formattedText), text, 4);

    // Escape the text and name so that it is safe to insert into a query
    g_hDatabase.Escape(formattedText, escapedText, sizeof(escapedText));
    g_hDatabase.Escape(name, escapedName, sizeof(escapedName));

    // Get the current date and time
    FormatTime(datetime, sizeof(datetime), "%Y-%m-%d %H:%M:%S");

    // Format the query
    Format(query1, sizeof(query1), "INSERT INTO sb_game_events (gameid, playerid, time, name, flags, text) VALUES (%d, NULLIF(%d, 0), '%s', '%s', %d, '%s')",
        g_iLogID, playerid, datetime, escapedName, flags, escapedText);

    Format(query2, sizeof(query2), "UPDATE sb_games SET ended_at='%s' WHERE id=%d", datetime, g_iLogID);

    g_hDatabase.Query(OnQueryCompleted, query1);
    g_hDatabase.Query(OnQueryCompleted, query2);
}

static void LinkPlayerWithLog(int playerid)
{
    // Ensure that a log is opened
    if (g_iLogID == 0)
        g_iLogID = CreateLog(g_hDatabase);

    char query[256];
    Format(query, sizeof(query), "INSERT IGNORE INTO sb_game_players (gameid, playerid) VALUES (%d, %d)", g_iLogID, playerid);

    g_hDatabase.Query(OnQueryCompleted, query);
}

static int CreateLog(Database database)
{
    // Get the server's hostname
    char hostname[128];
    char escapedHostname[128];

    ServerCommand("sn_hostname");
    GetConVarString(FindConVar("hostname"), hostname, sizeof(hostname));
    g_hDatabase.Escape(hostname, escapedHostname, sizeof(escapedHostname));

    // Get the current date and time
    char datetime[MAX_DATETIME_LENGTH];
    FormatTime(datetime, sizeof(datetime), "%Y-%m-%d %H:%M:%S");

    // Get the server's IP
    char ip[MAX_IP_LENGTH];
    GetConVarString(FindConVar("ip"), ip, sizeof(ip));

    // Get the server's hostport
    int port = GetConVarInt(FindConVar("hostport"));

    SQL_LockDatabase(database);

    int serverid = FetchServerId(database, ip, port);

    // Build the query
    char query[256];
    Format(query, sizeof(query), "INSERT IGNORE INTO sb_games (serverid, hostname, started_at, ended_at) VALUES (%d, '%s', '%s', '%s')", serverid, escapedHostname, datetime, datetime);
    FastQuery(database, query);
    int logID = SQL_GetInsertId(database);

    SQL_UnlockDatabase(database);

    return logID;
}

static int FetchServerId(Database database, const char[] ip, int port)
{
    char query[256];
    Format(query, sizeof(query), "SELECT sid FROM sb_servers WHERE ip='%s' AND port=%d", ip, port);

    DBResultSet result = Query(database, query);

    if (!result.FetchRow() || SQL_IsFieldNull(result, 0)) {
        CloseHandle(result);
        SetFailState(ERR_SQL_EXECUTE_QUERY_FAILED, "Unable to retrieve the sid (server id) for this server.");
        return -1;
    }

    int serverid = result.FetchInt(0);
    CloseHandle(result);
    return serverid;
}

static int GetEventFlags(bool chat, bool teamchat, int team)
{
    return (chat ? EVENTFLAGS_CHAT : 0) | (teamchat ? EVENTFLAGS_TEAMCHAT : 0) | (team << 2);
}

static int GetClientPlayerId(int client)
{
    return g_iPlayerIds[client];
}

static int SetClientPlayerId(int client, int id)
{
    g_iPlayerIds[client] = id;
}

//===========================================================================//
// Database stuff                                                            //
//===========================================================================//

public Database ConnectToDatabase(const char[] confName)
{
    char error[128];
    Database database = SQL_Connect(confName, true, error, sizeof(error));

    if (database == INVALID_HANDLE) {
        SetFailState(ERR_SQL_CONNECT_FAILED, error);
    }

    CreateTables(database);

    return database;
}

static void CreateTables(Database database)
{
    Transaction createTables = new Transaction();

    database.SetCharset("utf8");

    createTables.AddQuery(
        "CREATE TABLE IF NOT EXISTS sb_player_ids (\
            id INT NOT NULL AUTO_INCREMENT,\
            steamid VARCHAR(20) NOT NULL,\
            PRIMARY KEY (steamid),\
            KEY(id)\
        ) DEFAULT CHARSET=utf8;");

    createTables.AddQuery(
        "CREATE TABLE IF NOT EXISTS sb_player_ips (\
            playerid INT NOT NULL,\
            ip VARCHAR(15) NOT NULL,\
            last_seen DATETIME NOT NULL,\
            PRIMARY KEY (playerid, ip),\
            FOREIGN KEY (playerid) REFERENCES sb_player_ids(id) ON DELETE CASCADE\
        ) DEFAULT CHARSET=utf8;");

    createTables.AddQuery(
        "CREATE TABLE IF NOT EXISTS sb_player_names (\
            playerid INT NOT NULL,\
            name VARCHAR(32) NOT NULL,\
            last_seen DATETIME NOT NULL,\
            PRIMARY KEY (playerid, name),\
            FOREIGN KEY (playerid) REFERENCES sb_player_ids(id) ON DELETE CASCADE\
        ) DEFAULT CHARSET=utf8;");

    createTables.AddQuery(
        "CREATE TABLE IF NOT EXISTS sb_games (\
            id INT NOT NULL AUTO_INCREMENT,\
            serverid INT NOT NULL,\
            hostname VARCHAR(64) NOT NULL,\
            started_at DATETIME NOT NULL,\
            ended_at DATETIME NOT NULL,\
            PRIMARY KEY (id),\
            KEY(serverid, started_at)\
        ) DEFAULT CHARSET=utf8;");

    createTables.AddQuery(
        "CREATE TABLE IF NOT EXISTS sb_game_events (\
            id INT NOT NULL AUTO_INCREMENT,\
            gameid INT NOT NULL,\
            playerid INT,\
            time DATETIME NOT NULL,\
            name VARCHAR(32) NOT NULL,\
            flags INT,\
            text TEXT,\
            PRIMARY KEY (id),\
            FOREIGN KEY (gameid) REFERENCES sb_games(id) ON DELETE CASCADE,\
            FOREIGN KEY (playerid) REFERENCES sb_player_ids(id) ON DELETE SET NULL\
        ) DEFAULT CHARSET=utf8;");

    createTables.AddQuery(
        "CREATE TABLE IF NOT EXISTS sb_game_players (\
            gameid INT NOT NULL,\
            playerid INT,\
            PRIMARY KEY (gameid, playerid),\
            FOREIGN KEY (gameid) REFERENCES sb_games(id) ON DELETE CASCADE,\
            FOREIGN KEY (playerid) REFERENCES sb_player_ids(id) ON DELETE CASCADE\
        ) DEFAULT CHARSET=utf8;");

    database.Execute(createTables, OnCreateTables, OnCreateTablesFailed);
}

public void OnCreateTables(Database db, any data, int numQueries, Handle[] results, any[] queryData)
{
}

public void OnCreateTablesFailed(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    SetFailState(ERR_SQL_CREATE_TABLES_FAILED, error);
}

public void OnQueryCompleted(Handle owner, Handle query, const char[] error, any data)
{
    if (query == INVALID_HANDLE) {
        LogError(ERR_SQL_EXECUTE_QUERY_FAILED, error);
    }
    else {
        CloseHandle(query);
    }
}

static void FastQuery(Database database, const char[] query)
{
    CloseHandle(Query(database, query));
}

static DBResultSet Query(Database database, const char[] query)
{
    DBResultSet result = SQL_Query(database, query);

    if (result == INVALID_HANDLE) {
        char error[128];

        SQL_GetError(database, error, sizeof(error));
        SQL_UnlockDatabase(database);

        SetFailState(ERR_SQL_EXECUTE_QUERY_FAILED, error);

        return DBResultSet:INVALID_HANDLE;
    }

    return result;
}

//===========================================================================//
// Events stuff                                                              //
//===========================================================================//

public Action OnSay(client, args)
{
    g_bTeamSay[client] = false;
}

public Action OnSayTeam(client, args)
{
    g_bTeamSay[client] = true;
}

public void OnClientAuthorized(int client, const char[] auth)
{
    if (!IS_VALID_CLIENT(client) || IsFakeClient(client) || GetClientPlayerId(client) != 0)
        return;

    char name[MAX_NAME_LENGTH];
    char ip[MAX_IP_LENGTH];

    GetClientName(client, name, sizeof(name));
    GetClientIP(client, ip, sizeof(ip));

    int playerid = LogPlayerId(auth);
    LogPlayerIP(playerid, ip);
    LogPlayerName(playerid, name);
    LogServerEvent(playerid, "%s connected", name);
    LinkPlayerWithLog(playerid);

    SetClientPlayerId(client, playerid);
}

public Action OnPlayerDisconnect(Event event, const char[] eventName, bool dontBroadcast) {
    // BUG: The event's bot flag is broken, we have to use the client id instead to check if we're dealing with a bot
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);
    int playerid = GetClientPlayerId(client);

    if (!IS_VALID_CLIENT(client) || IsFakeClient(client) || playerid == 0)
        return Plugin_Continue;

    char name[MAX_NAME_LENGTH];
    char reason[128];

    event.GetString("name", name, sizeof(name));
    event.GetString("reason", reason, sizeof(reason));

    LogServerEvent(playerid, "%s disconnected - %s", name, reason);

    SetClientPlayerId(client, 0);

    if (GetPlayerCount(client) == 0) {
        g_iLogID = 0;
    }

    return Plugin_Continue;
}

public Action OnPlayerChangeName(Event event, const char[] eventName, bool dontBroadcast)
{
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);
    int playerid = GetClientPlayerId(client);

    if (!IS_VALID_INGAME(client) || IsFakeClient(client))
        return Plugin_Continue;

    char oldname[MAX_NAME_LENGTH];
    char newname[MAX_NAME_LENGTH];
    char steamid[MAX_STEAMID_LENGTH];

    event.GetString("oldname", oldname, sizeof(oldname));
    event.GetString("newname", newname, sizeof(newname));
    GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));

    LogPlayerName(playerid, newname);
    LogServerEvent(playerid, "* %s changed name to %s", oldname, newname);

    return Plugin_Continue;
}

public Action OnPlayerChangeTeam(Event event, const char[] eventName, bool dontBroadcast)
{
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);
    int playerid = GetClientPlayerId(client);

    if (!IS_VALID_INGAME(client) || IsFakeClient(client) || event.GetBool("disconnect") || event.GetInt("oldteam") == TEAM_UNASSIGNED)
        return Plugin_Continue;

    char name[MAX_NAME_LENGTH];
    char team[MAX_TEAM_LENGTH];
    char oldteam[MAX_TEAM_LENGTH];

    GetTeamString(event.GetInt("team"), team, sizeof(team));
    GetTeamString(event.GetInt("oldteam"), oldteam, sizeof(oldteam));
    GetClientName(client, name, sizeof(name));

    LogServerEvent(playerid, "* %s changed from team %s to %s", name, oldteam, team);

    return Plugin_Continue;
}

public Action OnPlayerChat(Event event, const char[] eventName, bool dontBroadcast)
{
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);
    int playerid = g_iPlayerIds[client];

    if (!IS_VALID_INGAME(client) || IsFakeClient(client))
        return Plugin_Continue;

    char name[MAX_NAME_LENGTH];
    char text[128];

    GetClientName(client, name, sizeof(name));
    event.GetString("text", text, sizeof(text));

    LogChatEvent(playerid, name, g_bTeamSay[client], GetClientTeam(client), text);

    return Plugin_Continue;
}

static void GetTeamString(int teamid, char[] nameBuffer, int nameBufferSize)
{
    // Note: SourcePawn cases are not fall-through, so no break keyword.
    switch (teamid) {
        case TEAM_SPECTATORS:
            Format(nameBuffer, nameBufferSize, "spectators");

        case TEAM_INFECTED:
            Format(nameBuffer, nameBufferSize, "infected");

        case TEAM_SURVIVORS:
            Format(nameBuffer, nameBufferSize, "survivors");

        default:
            Format(nameBuffer, nameBufferSize, "unassigned");
    }
}

static int GetPlayerCount(int exclude=0)
{
    int players = 0;

    for (int client = 1; client <= MaxClients; client++) {
        if (client == exclude)
            continue;

        if (IS_VALID_INGAME(client) && !IsFakeClient(client))
            players++;
    }

    return players;
}

static void TryHookEvent(const char[] name, EventHook callback)
{
    if (!HookEventEx(name, callback, EventHookMode_Post))
        LogError(ERR_HOOK_EVENT_FAILED, name);
}

//===========================================================================//
// Vote hook stuff                                                           //
//===========================================================================//

public Action:OnVoteStart(UserMsg msg_id, Handle bf, const players[], int playersNum, bool reliable, bool init)
{
    char name[MAX_NAME_LENGTH];
    char details[MAX_ARG_SIZE];
    char argument[MAX_ARG_SIZE];

    BfReadByte(bf);
    int client = BfReadByte(bf);
    BfReadString(bf, details, sizeof(details));
    BfReadString(bf, argument, sizeof(argument));

    GetClientName(client, name, sizeof(name));
    int playerid = GetClientPlayerId(client);

    LogServerEvent(playerid, "* %s called vote: %s \"%s\"", name, details, argument);

    return Plugin_Continue;
}

public Action:OnVotePass(UserMsg msg_id, Handle bf, const players[], int playersNum, bool reliable, bool init)
{
    char details[MAX_ARG_SIZE];
    char param1[MAX_ARG_SIZE];

    BfReadByte(bf);
    BfReadString(bf, details, sizeof(details));
    BfReadString(bf, param1, sizeof(param1));

    LogServerEvent(0, "* Vote passed: %s \"%s\"", details, param1);

    return Plugin_Continue;
}

public Action:OnVoteFail(UserMsg msg_id, Handle bf, const players[], int playersNum, bool reliable, bool init)
{
    LogServerEvent(0, "* Vote failed");

    return Plugin_Continue;
}
