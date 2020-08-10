#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#include <tf2>
#include <tf2_stocks>
#include <tf_econ_data>
#include <playermodel>
#include <tf2items>

#pragma semicolon 1
#pragma newdecls required

ConVar mp_friendlyfire = null;
ConVar mp_autoteambalance = null;
ConVar sv_alltalk = null;
ConVar mp_allowspectators = null;
ConVar spec_freeze_time = null;
ConVar mp_waitingforplayers_time = null;

Handle hTimerStart = null;
ConVar ttt_preptime = null;
Handle hHudTimer[MAXPLAYERS+1] = {null, ...};
Handle hHud[MAXPLAYERS+1] = {null, ...};
int iKarma[MAXPLAYERS+1] = {1000, ...};
float flTimerStartTime = 0.0;

ConVar tf_dropped_weapon_lifetime = null;
ConVar tf_allow_player_use = null;
ArrayList hWeaponClasses = null;
Handle hDummyItemView = null;
ArrayList hWeapons = null;

Handle hDroppedWeaponCreate = null;
Handle hInitDroppedWeapon = null;
Handle hInitPickedUpWeapon = null;
Handle hPickupWeaponFromOther = null;
int m_Item = -1;
int iDroppedWeaponClip = -1;
int iDroppedWeaponAmmo = -1;

enum PlayerRole
{
	Innocent,
	Detective,
	Traitor,
};

PlayerRole nRole[MAXPLAYERS+1] = {Innocent, ...};

stock bool FilterWeapons(int itemdef, any data)
{
	for(TFClassType i = TFClass_Scout; i <= TFClass_Engineer; i++) {
		int slot = TF2Econ_GetItemSlot(itemdef, i);
		if(slot != -1) {
			hWeaponClasses.Push(-itemdef);
			hWeaponClasses.Push(i);
			if(slot < 3) {
				return true;
			}
		}
	}

	return false;
}

public void OnPluginStart()
{
	hWeaponClasses = new ArrayList();

	mp_friendlyfire = FindConVar("mp_friendlyfire");
	mp_autoteambalance = FindConVar("mp_autoteambalance");
	sv_alltalk = FindConVar("sv_alltalk");
	mp_allowspectators = FindConVar("mp_allowspectators");
	spec_freeze_time = FindConVar("spec_freeze_time");
	mp_waitingforplayers_time = FindConVar("mp_waitingforplayers_time");

	tf_allow_player_use = FindConVar("tf_allow_player_use");
	tf_dropped_weapon_lifetime = FindConVar("tf_dropped_weapon_lifetime");

	ttt_preptime = CreateConVar("ttt_preptime", "45.0");

	HookEvent("teamplay_round_start", teamplay_round_start);
	HookEvent("teamplay_round_active", teamplay_round_active);

	hDummyItemView = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
	TF2Items_SetClassname(hDummyItemView, "tf_weapon_fists");
	TF2Items_SetItemIndex(hDummyItemView, 5);
	TF2Items_SetQuality(hDummyItemView, 0);
	TF2Items_SetLevel(hDummyItemView, 0);
	TF2Items_SetNumAttributes(hDummyItemView, 0);

	m_Item = FindSendPropInfo("CTFWeaponBase", "m_Item");

	GameData gamedata = new GameData("ttt");

	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFDroppedWeapon::Create");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_QAngle, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	hDroppedWeaponCreate = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFDroppedWeapon::InitDroppedWeapon");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	hInitDroppedWeapon = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFDroppedWeapon::InitPickedUpWeapon");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	hInitPickedUpWeapon = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFPlayer::PickupWeaponFromOther");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	hPickupWeaponFromOther = EndPrepSDKCall();

	iDroppedWeaponClip = gamedata.GetOffset("DroppedWeaponClip");
	iDroppedWeaponAmmo = gamedata.GetOffset("DroppedWeaponAmmo");

	delete gamedata;

	//RegAdminCmd("ttt_randomweapon", ConCommand_RandomWeapon, ADMFLAG_GENERIC);
	RegConsoleCmd("ttt_randomweapon", ConCommand_RandomWeapon);

	/*
	HookEvent("teamplay_round_win", teamplay_round_win);
	HookEvent("teamplay_win_panel", teamplay_round_win);
	HookEvent("teamplay_round_stalemate", teamplay_round_win);

	HookEvent("player_spawn", player_spawn);
	HookEvent("player_team", player_team);
	HookEvent("player_death", player_death, EventHookMode_Pre);
	
	AddCommandListener(ConCommand_SayTeam, "say_team");
	*/

	HookEvent("post_inventory_application", post_inventory_application);

	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnAllPluginsLoaded()
{
	hWeapons = TF2Econ_GetItemList(FilterWeapons);
}

public void OnConfigsExecuted()
{
	//mp_waitingforplayers_time.IntValue = 1;
	sv_alltalk.BoolValue = false;
	mp_autoteambalance.BoolValue = false;
	//mp_allowspectators.BoolValue = false;
	//spec_freeze_time.IntValue = 10000000;

	tf_allow_player_use.BoolValue = true;
	tf_dropped_weapon_lifetime.IntValue = 999999999999;
}

public void OnMapStart()
{
	PrecacheModel("models/error.mdl");
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "tf_logic_arena") ||
		StrEqual(classname, "func_respawnroomvisualizer") ||
		StrEqual(classname, "team_control_point") ||
		StrEqual(classname, "item_teamflag") ||
		StrEqual(classname, "func_capturezone") ||
		StrEqual(classname, "func_regenerate") ||
		StrEqual(classname, "trigger_capture_area")) {
		AcceptEntityInput(entity, "Kill");
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitchPost);
	SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);

	hHud[client] = CreateHudSynchronizer();
	hHudTimer[client] = CreateTimer(0.1, Timer_Hud, client, TIMER_REPEAT);
}

public void OnClientDisconnect(int client)
{
	KillTimer(hHudTimer[client]);
	delete hHud[client];
}

stock int SpawnDroppedWeapon(int itemid, const float pos[3], int client = -1)
{
	bool created = false;
	if(client == -1) {
		int count = GetClientCount();
		if(count == 0) {
			client = CreateFakeClient("");
			created = true;
		} else {
			client = GetRandomInt(1, count);
		}
	}

	int entity = -1;

	int weapon = SpawnWeapon(client, itemid);
	if(weapon != -1) {
		char model[PLATFORM_MAX_PATH];
		if(TF2Econ_GetItemDefinitionString(itemid, "model_player", model, sizeof(model))) {
			Address itemview = (GetEntityAddress(weapon) + view_as<Address>(m_Item));
			float ang[3];
			entity = SDKCall(hDroppedWeaponCreate, client, pos, ang, model, itemview);
			if(entity != -1) {
				SDKCall(hInitDroppedWeapon, entity, client, weapon, true, true);
			}

			RemoveEntity(weapon);

			if(created) {
				KickClientEx(client);
			}
		}
	}

	return entity;
}

stock Action ConCommand_RandomWeapon(int client, int args)
{
	int itemid = hWeapons.Get(GetRandomInt(0, hWeapons.Length-1));
	if(TF2Econ_IsValidItemDefinition(itemid)) {
		float pos[3];
		pos[2] += 72.0;
		GetClientAbsOrigin(client, pos);

		int entity = SpawnDroppedWeapon(itemid, pos, client);

		char name[32];
		TF2Econ_GetItemName(itemid, name, sizeof(name));

		ReplyToCommand(client, "spawned %i - %s", itemid, name);
	} else {
		ReplyToCommand(client, "error getting itemid");
	}

	return Plugin_Handled;
}

stock TFClassType GetWeaponClass(int itemid)
{
	int pos = hWeaponClasses.FindValue(-itemid);
	if(pos == -1) {
		for(TFClassType i = TFClass_Scout; i <= TFClass_Engineer; i++) {
			if(TF2Econ_GetItemSlot(itemid, i) != -1) {
				hWeaponClasses.Push(-itemid);
				pos = hWeaponClasses.Push(i);
				return i;
			}
		}
		return TFClass_Unknown;
	} else {
		return hWeaponClasses.Get(pos+1);
	}
}

stock void OnWeaponEquipPost(int client, int weapon)
{

}

stock void OnWeaponSwitchPost(int client, int weapon)
{
	int itemid = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");

	TFClassType weaponclass = GetWeaponClass(itemid);

	if(weaponclass != TFClass_Unknown) {
		char classmodel[PLATFORM_MAX_PATH];
		GetModelForClass(weaponclass, classmodel, sizeof(classmodel));

		Playermodel_SetAnimation(client, classmodel);
	} else {
		Playermodel_Clear(client);
	}
}

stock void PickupWeapon(int client, int weapon)
{
	//if(!SDKCall(hPickupWeaponFromOther, client, weapon))
	{
		int itemid = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
		//int clip = GetEntData(weapon, iDroppedWeaponClip);
		//int ammo = GetEntData(weapon, iDroppedWeaponAmmo);
		RemoveEntity(weapon);
		int entity = GiveWeapon(client, itemid);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(buttons & IN_USE && !(GetEntProp(client, Prop_Data, "m_nOldButtons") & IN_USE)) {
		int aim = GetClientAimTarget(client, false);
		if(aim != -1) {
			char classname[64];
			GetEntityClassname(aim, classname, sizeof(classname));
			if(StrEqual(classname, "tf_dropped_weapon")) {
				PickupWeapon(client, aim);
			}
		}
	}

	return Plugin_Continue;
}

stock Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if(hTimerStart != null) {
		if(attacker != 0 && attacker != victim) {
			damage = 0.0;
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

stock int SpawnWeapon(int client, int itemid)
{
	int entity = -1;
	char classname[64];
	if(TF2Econ_GetItemClassName(itemid, classname, sizeof(classname)) &&
		TF2Econ_TranslateWeaponEntForClass(classname, sizeof(classname), TF2_GetPlayerClass(client))
	) {
		TF2Items_SetClassname(hDummyItemView, classname);
		TF2Items_SetItemIndex(hDummyItemView, itemid);
		entity = TF2Items_GiveNamedItem(client, hDummyItemView);
		if(entity != -1) {
			SetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity", 1);
		}
	}
	return entity;
}

stock int GiveWeapon(int client, int itemid)
{
	int slot = TF2Econ_GetItemSlot(itemid, TF2_GetPlayerClass(client));
	TF2_RemoveWeaponSlot(client, slot);
	int entity = SpawnWeapon(client, itemid);
	if(entity != -1) {
		EquipPlayerWeapon(client, entity);
		OnWeaponSwitchPost(client, entity);
	}
	return entity;
}

stock Action post_inventory_application(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	TF2_RemoveAllWeapons(client);
	GiveWeapon(client, 5);
	return Plugin_Continue;
}

stock Action teamplay_round_start(Event event, const char[] name, bool dontBroadcast)
{
	return Plugin_Continue;
}

stock Action teamplay_round_active(Event event, const char[] name, bool dontBroadcast) 
{
	float preptime = ttt_preptime.FloatValue;
	hTimerStart = CreateTimer(preptime, Timer_Start);
	PrintToChatAll("Round begins in %i seconds!", RoundFloat(preptime));
	flTimerStartTime = GetGameTime();

	CreateTimer(0.1, Timer_Doors);

	return Plugin_Continue;
}

stock Action Timer_Doors(Handle timer)
{
	int tmp = -1;
	while((tmp = FindEntityByClassname(tmp, "func_door")) != -1)
	{
		AcceptEntityInput(tmp, "Open");
	}

	return Plugin_Continue;
}

stock Action Timer_Start(Handle timer) 
{
	hTimerStart = null;
	flTimerStartTime = 0.0;

	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			if(!IsPlayerAlive(i)) {
				TF2_RespawnPlayer(i);
			}
		}
	}

	return Plugin_Continue;
}

stock Action Timer_Hud(Handle timer, int client)
{
	int r = 0; int g = 0; int b = 0;
	float x = 0.02; float y = 0.02;

	if(hTimerStart != null) {
		r = 125; g = 125; b = 125;
		SetHudTextParams(x, y, 0.1, r, g, b, 255);
		float preptime = ttt_preptime.FloatValue;
		preptime -= (GetGameTime() - flTimerStartTime);
		ShowSyncHudText(client, hHud[client], "Starting in %i seconds\nKarma: %i", RoundFloat(preptime), iKarma[client]);
	} else {
		switch(nRole[client]) {
			case Innocent: {
				g = 255;
				SetHudTextParams(x, y, 0.1, r, g, b, 255);
				ShowSyncHudText(client, hHud[client], "Innocent\nKarma: %i", iKarma[client]);
			}
			case Detective: {
				b = 255;
				SetHudTextParams(x, y, 0.1, r, g, b, 255);
				ShowSyncHudText(client, hHud[client], "Detective\nKarma: %i", iKarma[client]);
			}
			case Traitor: {
				r = 255;
				SetHudTextParams(x, y, 0.1, r, g, b, 255);
				ShowSyncHudText(client, hHud[client], "Traitor\nKarma: %i", iKarma[client]);
			}
		}
	}

	return Plugin_Continue;
}