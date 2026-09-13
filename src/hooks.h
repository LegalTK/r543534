#pragma once

class CBasePlayer;

namespace detours {
	extern bool updateClientSideAnimations(CBasePlayer* player, double ticks, bool rebuildBones = false);
	extern void callDMEViaContext();
	extern void hook();
	extern void postInit();
	extern void unHook();
} 