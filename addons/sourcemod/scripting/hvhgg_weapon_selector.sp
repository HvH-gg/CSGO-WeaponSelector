#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <clientprefs>


public Plugin:myinfo = 
{ 
	name = "HvH.gg Weapon Selector", 
	author = "imi-tat0r & NeDIAD", 
	description = "Allows players to set a preference for weapons after CS:GO inventory services got shut down.", 
	version = "v1.3.0"
};

bool g_bPrefersR8[MAXPLAYERS + 1] = {false};
bool g_bPrefersUSP[MAXPLAYERS + 1] = {false};
bool g_bPrefersCZ[MAXPLAYERS + 1] = {false};
bool g_bPrefersM4A1S[MAXPLAYERS + 1] = {false};
int g_iPlayerNotified[MAXPLAYERS + 1] = {0};
int g_iPendingCookies[MAXPLAYERS + 1] = {0};
Handle g_hR8Cookie;
Handle g_hUSPCookie;
Handle g_hCZCookie;
Handle g_hM4A1SCookie;
#define PREF_R8 1
#define PREF_USP 2
#define PREF_CZ 4
#define PREF_M4A1S 8
ConVar g_cvDefaultR8;
ConVar g_cvDefaultUSP;
ConVar g_cvDefaultCZ;
ConVar g_cvDefaultM4A1S;
int r8Price = 600;
int deaglePrice = 700;
int p2000UspPrice = 200;
int czTecPrice = 500;
int m4a1sPrice = 2900;
int m4a4Price = 3100;

public void OnPluginStart()
{
	RegConsoleCmd("deagle", Command_Deagle);
	RegConsoleCmd("r8", Command_Revolver);
	RegConsoleCmd("revolver", Command_Revolver);

	RegConsoleCmd("usp", Command_USP);
	RegConsoleCmd("p2000", Command_P2000);
	RegConsoleCmd("p2k", Command_P2000);

	RegConsoleCmd("cz", Command_CZ);
	RegConsoleCmd("tec", Command_NotCZ);
	RegConsoleCmd("tec9", Command_NotCZ);
	RegConsoleCmd("fiveseven", Command_NotCZ);
	RegConsoleCmd("57", Command_NotCZ);

	RegConsoleCmd("m4a1s", Command_M4A1S);
	RegConsoleCmd("m4a4", Command_M4A4);

	HookEvent("player_spawn", Player_Spawn);

	g_cvDefaultR8 = CreateConVar("hvh_default_r8", "0", "Whether players prefer the R8 Revolver over the Desert Eagle by default", _, true, 0.0, true, 1.0);
	g_cvDefaultUSP = CreateConVar("hvh_default_usp", "0", "Whether players prefer the USP-S over the P2000 by default", _, true, 0.0, true, 1.0);
	g_cvDefaultCZ = CreateConVar("hvh_default_cz", "0", "Whether players prefer the CZ75-Auto over the Tec-9/Five-Seven by default", _, true, 0.0, true, 1.0);
	g_cvDefaultM4A1S = CreateConVar("hvh_default_m4a1s", "0", "Whether players prefer the M4A1-S over the M4A4 by default", _, true, 0.0, true, 1.0);
	g_hR8Cookie = RegClientCookie("hvhgg_weapon_r8", "R8 Revolver preference", CookieAccess_Private);
	g_hUSPCookie = RegClientCookie("hvhgg_weapon_usp", "USP-S preference", CookieAccess_Private);
	g_hCZCookie = RegClientCookie("hvhgg_weapon_cz", "CZ75-Auto preference", CookieAccess_Private);
	g_hM4A1SCookie = RegClientCookie("hvhgg_weapon_m4a1s", "M4A1-S preference", CookieAccess_Private);
	AutoExecConfig(true, "hvhgg_weapon_selector");

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientConnected(client))
		{
			ResetUserPreference(client);
			if (!IsFakeClient(client) && AreClientCookiesCached(client))
				OnClientCookiesCached(client);
		}
	}
}

public void OnClientConnected(int client)
{
	ResetUserPreference(client);
}

public void OnClientDisconnect(int client)
{
	ResetUserPreference(client);
}

public void OnClientCookiesCached(int client)
{
	if (!IsClientConnected(client) || IsFakeClient(client))
		return;

	SyncPreference(client, g_hR8Cookie, g_bPrefersR8[client], PREF_R8);
	SyncPreference(client, g_hUSPCookie, g_bPrefersUSP[client], PREF_USP);
	SyncPreference(client, g_hCZCookie, g_bPrefersCZ[client], PREF_CZ);
	SyncPreference(client, g_hM4A1SCookie, g_bPrefersM4A1S[client], PREF_M4A1S);
	g_iPendingCookies[client] = 0;

	// cookies can arrive after player spawn
	if (IsClientInGame(client) && GetClientTeam(client) == CS_TEAM_CT && IsPlayerAlive(client) && g_bPrefersUSP[client])
		ReplaceSpawnPistol(client, "weapon_hkp2000", "weapon_usp_silencer");

	if (IsClientInGame(client) && GetClientTeam(client) > CS_TEAM_SPECTATOR)
		ShowPreferences(client);
}

void SyncPreference(int client, Handle cookie, bool &preference, int flag)
{
	if (g_iPendingCookies[client] & flag)
	{
		SetClientCookie(client, cookie, preference ? "1" : "0");
		return;
	}

	char value[4];
	GetClientCookie(client, cookie, value, sizeof(value));
	if (StrEqual(value, "1"))
		preference = true;
	else if (StrEqual(value, "0"))
		preference = false;
}

void SavePreference(int client, Handle cookie, bool preference, int flag)
{
	if (IsFakeClient(client))
		return;

	if (AreClientCookiesCached(client))
		SetClientCookie(client, cookie, preference ? "1" : "0");
	else
		g_iPendingCookies[client] |= flag;
}

void Player_Spawn(Event event, const char[] name, bool dB)
{
	CreateTimer(0.1, HandleSpawn, event.GetInt("userid"));
}

public Action HandleSpawn(Handle timer, any userId)
{
	int client = GetClientOfUserId(view_as<int>(userId));
	if (!client)
		return Plugin_Stop;

	if (GetClientTeam(client) <= CS_TEAM_SPECTATOR)
		return Plugin_Stop;

	// Apply saved preferences before replacing the spawn pistol. The cookie
	// callback handles players who spawned while their cookies were loading.
	if (!IsFakeClient(client) && !AreClientCookiesCached(client))
		return Plugin_Stop;

	// default CT pistol is always the P2000, swap it for free if USP-S is preferred
	if (IsPlayerAlive(client) && g_bPrefersUSP[client] && GetClientTeam(client) == CS_TEAM_CT)
		ReplaceSpawnPistol(client, "weapon_hkp2000", "weapon_usp_silencer");

	ShowPreferences(client);
	return Plugin_Stop;
}

void ShowPreferences(int client)
{
	if (g_iPlayerNotified[client] >= 1)
		return;

	PrintToChat(client, "[\x07Hv\x02H\x01.gg] Use \x07!deagle\x01 or \x07!r8\x01 at any time to set your preference.");
	PrintToChat(client, "[\x07Hv\x02H\x01.gg] Use \x07!p2000\x01 or \x07!usp\x01 at any time to set your preference.");
	PrintToChat(client, "[\x07Hv\x02H\x01.gg] Use \x07!tec9\x01/\x07!fiveseven\x01 or \x07!cz\x01 at any time to set your preference.");
	PrintToChat(client, "[\x07Hv\x02H\x01.gg] Use \x07!m4a4\x01 or \x07!m4a1s\x01 at any time to set your preference.");

	if (g_bPrefersR8[client])
		PrintToChat(client, "[\x07Hv\x02H\x01.gg] Current preference: \x07R8 Revolver");
	else
		PrintToChat(client, "[\x07Hv\x02H\x01.gg] Current preference: \x07Desert Eagle");
	
	if (g_bPrefersUSP[client])
		PrintToChat(client, "[\x07Hv\x02H\x01.gg] Current preference: \x07USP-S");
	else
		PrintToChat(client, "[\x07Hv\x02H\x01.gg] Current preference: \x07P2000");

	if (g_bPrefersCZ[client])
		PrintToChat(client, "[\x07Hv\x02H\x01.gg] Current preference: \x07CZ75-Auto");
	else
		PrintToChat(client, "[\x07Hv\x02H\x01.gg] Current preference: \x07Tec-9/Five-Seven");

	if (g_bPrefersM4A1S[client])
		PrintToChat(client, "[\x07Hv\x02H\x01.gg] Current preference: \x07M4A1-S");
	else
		PrintToChat(client, "[\x07Hv\x02H\x01.gg] Current preference: \x07M4A4");

	g_iPlayerNotified[client]++;
}

public Action Command_Deagle(int client, int args)
{
	return Command_Handler("deagle", client, args);
}

public Action Command_Revolver(int client, int args)
{
	return Command_Handler("r8", client, args);
}

public Action Command_USP(int client, int args)
{
	return Command_Handler("usp", client, args);
}

public Action Command_P2000(int client, int args)
{
	return Command_Handler("p2000", client, args);
}

public Action Command_CZ(int client, int args)
{
	return Command_Handler("cz", client, args);
}

public Action Command_NotCZ(int client, int args)
{
	return Command_Handler("tec9", client, args);
}

public Action Command_M4A1S(int client, int args)
{
	return Command_Handler("m4a1s", client, args);
}

public Action Command_M4A4(int client, int args)
{
	return Command_Handler("m4a4", client, args);
}

public Action Command_Handler(const char[] command, int client, int args)
{
	if (client <= 0 || !IsClientInGame(client))
		return Plugin_Handled;

	if (args > 1)
	{
		char com[128] = "[\x07Hv\x02H\x01.gg] Usage: !";
		StrCat(com, sizeof(com), command);
		
		ReplyToCommand(client, com);
		return Plugin_Handled;
	}
	
	char weapon[32] = "";

	if (StrEqual(command, "deagle"))
	{
		g_bPrefersR8[client] = false;
		SavePreference(client, g_hR8Cookie, false, PREF_R8);
		weapon = "Desert Eagle";
	}
	else if (StrEqual(command, "r8"))
	{
		g_bPrefersR8[client] = true;
		SavePreference(client, g_hR8Cookie, true, PREF_R8);
		weapon = "R8 Revolver";
	}
	else if (StrEqual(command, "p2000"))
	{
		g_bPrefersUSP[client] = false;
		SavePreference(client, g_hUSPCookie, false, PREF_USP);
		weapon = "P2000";
	}
	else if (StrEqual(command, "usp"))
	{
		g_bPrefersUSP[client] = true;
		SavePreference(client, g_hUSPCookie, true, PREF_USP);
		weapon = "USP-S";
	}
	else if (StrEqual(command, "m4a1s"))
	{
		g_bPrefersM4A1S[client] = true;
		SavePreference(client, g_hM4A1SCookie, true, PREF_M4A1S);
		weapon = "M4A1-S";
	}
	else if (StrEqual(command, "m4a4"))
	{
		g_bPrefersM4A1S[client] = false;
		SavePreference(client, g_hM4A1SCookie, false, PREF_M4A1S);
		weapon = "M4A4";
	}
	else if (StrEqual(command, "cz"))
	{
		g_bPrefersCZ[client] = true;
		SavePreference(client, g_hCZCookie, true, PREF_CZ);
		weapon = "CZ75-Auto";
	}
	else
	{
		g_bPrefersCZ[client] = false;
		SavePreference(client, g_hCZCookie, false, PREF_CZ);
		weapon = "Tec-9/Five-Seven";
	}

	char com[128] = "[\x07Hv\x02H\x01.gg] Current preference: \x07";
	StrCat(com, sizeof(com), weapon);
	ReplyToCommand(client, com);

	return Plugin_Handled;
}

public Action CS_OnBuyCommand(int client, const char [] szWeapon)
{
	if(!IsClientInGame(client) || !IsPlayerAlive(client) || GetEntProp(client, Prop_Send, "m_bInBuyZone") == 0)
		return Plugin_Continue;
	
	if(GetClientTeam(client) <= CS_TEAM_SPECTATOR)
		return Plugin_Continue;
	
	char str[128] = "weapon_";
	StrCat(str, sizeof(str), szWeapon);

	if (StrEqual(str, "weapon_deagle"))
		return HandleBuyEvent(client, "weapon_revolver", r8Price, g_bPrefersR8[client]);
	else if (StrEqual(str, "weapon_revolver"))
		return HandleBuyEvent(client, "weapon_deagle", deaglePrice, !g_bPrefersR8[client]);
	else if (StrEqual(str, "weapon_hkp2000"))
		return HandleBuyEvent(client, "weapon_usp_silencer", p2000UspPrice, g_bPrefersUSP[client]);
	else if (StrEqual(str, "weapon_usp_silencer"))
		return HandleBuyEvent(client, "weapon_hkp2000", p2000UspPrice, !g_bPrefersUSP[client]);
	else if (StrEqual(str, "weapon_m4a4"))
		return HandleBuyEvent(client, "weapon_m4a1_silencer", m4a1sPrice, g_bPrefersM4A1S[client], CS_SLOT_PRIMARY);
	else if (StrEqual(str, "weapon_m4a1_silencer"))
		return HandleBuyEvent(client, "weapon_m4a4", m4a4Price, !g_bPrefersM4A1S[client], CS_SLOT_PRIMARY);
	else if (StrEqual(str, "weapon_tec9") || StrEqual(str, "weapon_fiveseven"))
		return HandleBuyEvent(client, "weapon_cz75a", czTecPrice, g_bPrefersCZ[client]);
	else if (StrEqual(str, "weapon_cz75a"))
	{
		if (GetClientTeam(client) == CS_TEAM_T)
			return HandleBuyEvent(client, "weapon_tec9", czTecPrice, !g_bPrefersCZ[client]);
		else
			return HandleBuyEvent(client, "weapon_fiveseven", czTecPrice, !g_bPrefersCZ[client]);
	}
	else
		return Plugin_Continue;
}

public Action CS_OnGetWeaponPrice(int client, const char[] weapon, int& price)
{
	// only deagle and r8 differ in price
	if (StrEqual(weapon, "weapon_deagle") || StrEqual(weapon, "weapon_revolver"))
	{
		price = g_bPrefersR8[client] ? r8Price : deaglePrice;
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

Action HandleBuyEvent(int client, const char[] weapon_replace, int price_replace, bool prefers, int slot = CS_SLOT_SECONDARY)
{
	if (!prefers)
		return Plugin_Continue;

	// can we afford the weapon?
	int money = GetClientMoney(client);
	if (money < price_replace)
		return Plugin_Handled;
	// if player already has the weapon, do nothing
	else if (HasPlayerWeapon(client, weapon_replace))
		return Plugin_Handled;
	else
	{
		DropWeaponInSlot(client, slot);
		SetClientMoney(client, money - price_replace);
		GivePlayerItem(client, weapon_replace);

		return Plugin_Handled;
	}		
}

public bool HasPlayerWeapon(int client, const char[] weapon)
{
	int m_hMyWeapons = FindSendPropInfo("CBasePlayer", "m_hMyWeapons");
	if(m_hMyWeapons == -1)
		return false;

	for(int offset = 0; offset < 128; offset += 4)
	{
		int weap = GetEntDataEnt2(client, m_hMyWeapons+offset);

		if(IsValidEdict(weap))
		{
			char classname[32];
			GetWeaponClassname(weap, -1, classname, 32);

			if(StrEqual(classname, weapon))
				return true;
		}
	}

	return false;
}

public void DropWeaponInSlot(int client, int slot)
{
	int weapon = GetPlayerWeaponSlot(client, slot);

	if (weapon != -1)
	{
		CS_DropWeapon(client, weapon, false);
	}
}

public void ReplaceSpawnPistol(int client, const char[] weapon_from, const char[] weapon_to)
{
	int weapon = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
	if (weapon == -1)
		return;

	char classname[32];
	GetWeaponClassname(weapon, -1, classname, sizeof(classname));

	if (!StrEqual(classname, weapon_from))
		return;

	// remove instead of drop so no free pistol is left on the ground
	RemovePlayerItem(client, weapon);
	AcceptEntityInput(weapon, "Kill");
	GivePlayerItem(client, weapon_to);
}

public int GetClientMoney(int client)
{
	return GetEntProp(client, Prop_Send, "m_iAccount");
}

public void SetClientMoney(int client, int money)
{
	SetEntProp(client, Prop_Send, "m_iAccount", money);
}

void ResetUserPreference(int client)
{
	g_bPrefersR8[client] = g_cvDefaultR8.BoolValue;
	g_bPrefersUSP[client] = g_cvDefaultUSP.BoolValue;
	g_bPrefersCZ[client] = g_cvDefaultCZ.BoolValue;
	g_bPrefersM4A1S[client] = g_cvDefaultM4A1S.BoolValue;
	g_iPlayerNotified[client] = false;	
	g_iPendingCookies[client] = 0;
}

stock void GetWeaponClassname(int weapon, int index = -1, char[] classname, int maxLen)
{
	GetEdictClassname(weapon, classname, maxLen);

	if(index == -1)
		index = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");

	switch(index)
	{
		case 60: strcopy(classname, maxLen, "weapon_m4a1_silencer");
		case 61: strcopy(classname, maxLen, "weapon_usp_silencer");
		case 63: strcopy(classname, maxLen, "weapon_cz75a");
		case 64: strcopy(classname, maxLen, "weapon_revolver");
	}
}
