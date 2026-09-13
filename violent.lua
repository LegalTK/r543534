violent = violent or {}
violent.config = violent.config or {}

local config = violent.config
if config.loaded then
	MsgC(Color(168, 85, 247), "[violent] ", color_white,
		"Already loaded; run violent_unload 1 before executing the updated file.\n")
	return
end
config.loaded = true

local ROOT = "violent"
local EXT = ".json"
local DATA = "DATA"
local ACCENT = Color(168, 85, 247)
local CURRENT = "violent_config"

local registry = {}
local order = {}
local active = CreateClientConVar(CURRENT, "default", true, false, "Active configuration name")

local function notify(fmt, ...)
	if select("#", ...) > 0 then
		fmt = fmt:format(...)
	end
	MsgC(ACCENT, "[violent] ", color_white, fmt, "\n")
end

local function sanitize(name)
	local clean = tostring(name or ""):gsub("[^%w_%-%.]", "")
	clean = clean:gsub("%.%.", "")
	return clean ~= "" and clean or "default"
end

local function path(name)
	return ("%s/%s%s"):format(ROOT, sanitize(name), EXT)
end

function config.path(name)
	return path(name)
end

function config.Add(name, default, help, min, max)
	default = tostring(default)

	local cvar = CreateClientConVar(name, default, false, false, help or "", min, max)

	if not registry[name] then
		registry[name] = { cvar = cvar, default = default }
		order[#order + 1] = name
	end

	return cvar
end

function config.Get(name)
	local entry = registry[name]
	return entry and entry.cvar:GetString()
end

function config.GetNumber(name)
	local entry = registry[name]
	return entry and entry.cvar:GetFloat() or 0
end

function config.GetBool(name)
	local entry = registry[name]
	return entry and entry.cvar:GetBool() or false
end

function config.Set(name, value)
	local entry = registry[name]
	if entry then
		entry.cvar:SetString(tostring(value))
	end
end

function config.Reset()
	for i = 1, #order do
		local entry = registry[order[i]]
		entry.cvar:SetString(entry.default)
	end
end

local function collect()
	local vars = {}
	for i = 1, #order do
		local name = order[i]
		vars[name] = registry[name].cvar:GetString()
	end
	return vars
end

local function apply(vars)
	for i = 1, #order do
		local name = order[i]
		local value = vars[name]
		if value ~= nil then
			registry[name].cvar:SetString(tostring(value))
		end
	end
end

function config.Save(name)
	name = sanitize(name)

	local raw = util.TableToJSON({
		meta = { version = 1, saved = os.time() },
		vars = collect(),
	}, true)
	if not raw then return false end

	file.CreateDir(ROOT)
	file.Write(path(name), raw)

	return file.Read(path(name), DATA) == raw
end

function config.Load(name)
	name = sanitize(name)

	local p = path(name)
	local raw = file.Read(p, DATA)
	if not raw then
		return false
	end

	local payload = util.JSONToTable(raw)
	if not payload or type(payload.vars) ~= "table" then
		return false
	end

	apply(payload.vars)
	active:SetString(name)

	return true
end

function config.Delete(name)
	name = sanitize(name)

	if not file.Exists(path(name), DATA) then
		return false
	end

	file.Delete(path(name))

	return true
end

function config.List()
	local files = file.Find(("%s/*%s"):format(ROOT, EXT), DATA)
	local names = {}

	for i = 1, #files do
		names[i] = files[i]:sub(1, -#EXT - 1)
	end

	return names
end

local hvhCvars = {
	["cl_interp"] = "0",
	["cl_interp_ratio"] = "1",
	["cl_lagcompensation"] = "1",
	["cl_pred_optimize"] = "2",
	["cl_smooth"] = "0",
	["cl_smoothtime"] = "0.01",
	["cl_predict"] = "1",
	["rate"] = "100000",
	["cl_cmdrate"] = "128",
	["cl_updaterate"] = "128",
	["cl_timeout"] = "1337",
	["cl_showerror"] = "0",
}

local hvhDefaults = {}
local hvhSaved = false

local function saveCvars()
	if hvhSaved then return end
	hvhSaved = true
	for name in pairs(hvhCvars) do
		local cv = GetConVar(name)
		if cv then
			hvhDefaults[name] = cv:GetString()
		end
	end
end

local function applyCvars()
	if ded and ded.ConVarSetValue then
		for name, value in pairs(hvhCvars) do
			pcall(ded.ConVarSetValue, name, tonumber(value))
		end
	else
		for name, value in pairs(hvhCvars) do
			pcall(RunConsoleCommand, name, value)
		end
	end
end

local function restoreCvars()
	if not hvhSaved then return end
	if ded and ded.ConVarSetValue then
		for name, value in pairs(hvhDefaults) do
			local num = tonumber(value)
			if num then
				pcall(ded.ConVarSetValue, name, num)
			else
				pcall(RunConsoleCommand, name, value)
			end
		end
	else
		for name, value in pairs(hvhDefaults) do
			pcall(RunConsoleCommand, name, value)
		end
	end
end

local triggers = {}
local stopAnimations

local function unload()
	if stopAnimations then stopAnimations() end
	hook.Remove("PreFrameStageNotify", "violent.animations.sync")
	hook.Remove("PostFrameStageNotify", "violent.animations.update")
	hook.Remove("ShouldUpdateAnimation", "violent.animations.filter")
	restoreCvars()
	for i = 1, #order do
		local entry = registry[order[i]]
		entry.cvar:SetString(entry.default)
	end
	hook.Remove("CreateMove", "violent.aimbot")
	hook.Remove("PostCreateMove", "violent.antiaim.verify")
	hook.Remove("PostCreateMove", "violent.antiaim.enforce")
	hook.Remove("EntityFireBullets", "violent.spread")
	hook.Remove("CalcView", "violent.view")
	hook.Remove("CalcViewModelView", "violent.vmview")
	hook.Remove("HUDPaint", "violent.esp")
	hook.Remove("InitPostEntity", "violent.config.autoload")
	hook.Remove("ShutDown", "violent.config.autosave")
	hook.Remove("Think", "violent.unloadkey")
	for i = 1, #triggers do
		cvars.RemoveChangeCallback(triggers[i], "violent.trigger")
	end
	hook.Remove("violent.unload", "violent.core.unload")
	violent = nil
	violent_bhop = nil
	violent_strafer = nil
	violent_aimbot = nil
	violent_movement_fix = nil
	violent_esp = nil
	notify("unloaded")
end

hook.Add("violent.unload", "violent.core.unload", unload)

local function addTrigger(name, help, handler)
	local cvar = CreateClientConVar(name, "", false, false, help)

	cvars.AddChangeCallback(name, function(_, _, value)
		if value == "" then return end
		handler(value)
		cvar:SetString("")
	end, "violent.trigger")

	triggers[#triggers + 1] = name

	return cvar
end

local function resolve(value)
	if value == "" or value == "1" then
		return active:GetString()
	end
	return value
end

addTrigger("violent_config_save", "Save the active configuration, or the given name", function(value)
	local name = sanitize(resolve(value))
	local saved = config.Save(name)
	if saved then active:SetString(name) end
	notify(saved and "saved '%s'" or "failed to save '%s'", name)
end)

addTrigger("violent_config_load", "Load a configuration by name", function(value)
	local name = resolve(value)
	notify(config.Load(name) and "loaded '%s'" or "no configuration named '%s'", name)
end)

addTrigger("violent_config_delete", "Delete a configuration by name", function(value)
	local name = resolve(value)
	if config.Delete(name) then
		notify("deleted '%s'", name)
		hook.Run("violent.unload")
	else
		notify("no configuration named '%s'", name)
	end
end)

addTrigger("violent_config_reset", "Reset every variable to its default", function()
	config.Reset()
	notify("all variables reset to defaults")
end)

addTrigger("violent_config_list", "Print every saved configuration", function()
	local names = config.List()

	if #names == 0 then
		notify("no configurations saved")
		return
	end

	local current = active:GetString()

	notify("%d configuration(s):", #names)
	for i = 1, #names do
		MsgC(ACCENT, "  ", color_white, names[i], names[i] == current and " *" or "", "\n")
	end
end)

local autoLoad = CreateClientConVar("violent_config_autoload", "1", true, false, "Load the active configuration on spawn")
local autoSave = CreateClientConVar("violent_config_autosave", "0", true, false, "Save the active configuration on shutdown")

saveCvars()
applyCvars()

local configInitialized = false

local function initializeConfig()
	if configInitialized then return end
	configInitialized = true

	-- zxcmodule installs netchannel hooks, so load it only after joining a map.
	if not ded then
		local ok, err = pcall(require, "zxcmodule")
		if not ok then
			notify("zxcmodule unavailable; native nospread disabled: %s", tostring(err))
		end
	end

	local name = active:GetString()
	if autoLoad:GetBool() and file.Exists(path(name), DATA) then
		config.Load(name)
	end
	applyCvars()
end

hook.Add("ShutDown", "violent.config.autosave", function()
	if autoSave:GetBool() then
		config.Save(active:GetString())
	end
	if stopAnimations then stopAnimations() end
end)

addTrigger("violent_unload", "Unload the cheat completely", function()
	hook.Run("violent.unload")
end)

local deleteHeld = false

hook.Add("Think", "violent.unloadkey", function()
	local down = input.IsKeyDown(KEY_DELETE)
	if down and not deleteHeld then
		deleteHeld = true
		hook.Run("violent.unload")
		return
	end
	if not down then
		deleteHeld = false
	end
end)

config.Add("violent_bhop", 0, "Auto bunny hop", 0, 1)

function violent_bhop(cmd)
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() then return end
	if ply:GetMoveType() ~= MOVETYPE_WALK then return end
	if bit.band(ply:GetFlags(), FL_ONGROUND) ~= 0 then return end

	local buttons = cmd:GetButtons()
	if bit.band(buttons, IN_JUMP) == 0 then return end

	cmd:SetButtons(bit.band(buttons, bit.bnot(IN_JUMP)))
end

config.Add("violent_strafer", 0, "Rage air strafer", 0, 1)

config.Add("violent_antiaim", "backward", "At-targets anti-aim: backward, sideways or off")
config.Add("violent_pitch", "zero", "Anti-aim pitch: down, zero or up")
config.Add("violent_min_fakelag", 0, "Minimum fakelag ticks", 0, 23)
config.Add("violent_max_fakelag", 0, "Maximum fakelag ticks", 0, 23)

local function antiAimEnabled()
	local mode = string.lower(config.Get("violent_antiaim") or "")
	return mode == "backward" or mode == "sideways"
end

local function violentAntiAim(cmd, view)
	-- Fall back to the incoming command angle; never index a nil view.
	view = view or cmd:GetViewAngles()
	local direction = string.lower(config.Get("violent_antiaim") or "backward")
	local pitch = string.lower(config.Get("violent_pitch") or "zero")
	-- Never modify the stored camera angle; it is also the no-target fallback.
	local angles = Angle(view.p, view.y, 0)
	local ply = LocalPlayer()
	local nearest, nearestDistance = nil, math.huge

	if IsValid(ply) then
		local origin = ply:GetPos()
		for _, target in ipairs(player.GetAll()) do
			if target ~= ply and IsValid(target) and target:Alive() and not target:IsDormant() then
				local distance = origin:DistToSqr(target:GetPos())
				if distance < nearestDistance then
					nearest, nearestDistance = target, distance
				end
			end
		end
	end

	if IsValid(nearest) then
		local delta = nearest:EyePos() - ply:EyePos()
		if delta:Length2DSqr() > 0.0001 then angles.y = delta:Angle().y end
	end

	if direction == "sideways" then
		angles.y = angles.y + (cmd:CommandNumber() % 2 == 0 and 90 or -90)
	else
		angles.y = angles.y + 180
	end

	if pitch == "down" then
		angles.p = 89
	elseif pitch == "up" then
		angles.p = -89
	else
		angles.p = 0
	end

	angles:Normalize()
	cmd:SetViewAngles(angles)
end

local aaMicroSide = false

-- Idle nudge so the lower body keeps updating while anti-aim holds (rapehack micromovement).
local function antiAimMicro(cmd, ply)
	if bit.band(ply:GetFlags(), FL_ONGROUND) == 0 then return end
	if cmd:GetForwardMove() ~= 0 or cmd:GetSideMove() ~= 0 or cmd:GetUpMove() ~= 0 then return end

	aaMicroSide = not aaMicroSide
	cmd:SetSideMove(aaMicroSide and 15 or -15)
end

local function violentFakelag(cmd)
	if not ded or not ded.SetBSendPacket then return end
	local minTicks = math.Clamp(math.floor(config.GetNumber("violent_min_fakelag")), 0, 23)
	local maxTicks = math.Clamp(math.floor(config.GetNumber("violent_max_fakelag")), 0, 23)
	if maxTicks < minTicks then minTicks, maxTicks = maxTicks, minTicks end
	if maxTicks <= 0 then
		ded.SetBSendPacket(true)
		return
	end

	local span = maxTicks - minTicks + 1
	local choke = minTicks + (cmd:CommandNumber() % span)
	local tick = cmd:CommandNumber() % (maxTicks + 1)
	ded.SetBSendPacket(tick >= choke)
end

function violent_strafer(cmd)
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() then return end
	if ply:GetMoveType() ~= MOVETYPE_WALK then return end

	cmd:SetForwardMove(0)

	if bit.band(ply:GetFlags(), FL_ONGROUND) ~= 0 then
		cmd:SetForwardMove(10000)
	else
		local speed = math.max(ply:GetVelocity():Length2D(), 1)
		cmd:SetForwardMove(5850 / speed)
		cmd:SetSideMove(cmd:CommandNumber() % 2 == 0 and -400 or 400)
	end
end

local function movement(cmd)
	local jumping = bit.band(cmd:GetButtons(), IN_JUMP) ~= 0

	if config.GetBool("violent_bhop") then
		violent_bhop(cmd)
	end

	if jumping and config.GetBool("violent_strafer") then
		violent_strafer(cmd)
	end
end

config.Add("violent_aimbot", 0, "Aim at head when key held", 0, 1)
config.Add("violent_aimbot_bind", "MOUSE4", "Hold key for aimbot")
config.Add("violent_aimbot_autofire", 0, "Auto fire when target visible", 0, 1)
config.Add("violent_aimbot_silent", 0, "Silent aim with movement and screen fix", 0, 1)
config.Add("violent_aimbot_extrapolation_ticks", 1, "Target movement lead in ticks; 0 disables", 0, 8)
config.Add("violent_aimbot_nospread", 0, "Compensate spread on aimed primary shots", 0, 1)
config.Add("violent_aimbot_norecoil", 0, "Compensate view punch on aimed primary shots", 0, 1)
local animationCvar = config.Add("violent_aimbot_animations", 1, "Update target animations from simulation time", 0, 1)

-- Keep samples per weapon entity: another player's shots must not replace our cone.
local weaponCones = setmetatable({}, { __mode = "k" })

hook.Add("EntityFireBullets", "violent.spread", function(ent, data)
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) or (ent ~= ply and ent ~= wep) then return end
	if not isvector(data.Spread) then return end

	-- Zero is a valid update (e.g. aiming down sights); never keep an old nonzero cone.
	weaponCones[wep] = Vector(data.Spread.x, data.Spread.y, data.Spread.z)
end)

local function aimNoSpread(cmd, ang, ply, wep)
	local class = wep:GetClass()
	if class == "swb_knife" or class == "swb_knife_m" then return ang end
	local base = class:match("^([^_]+)_")

	if base == "swb" or base == "cw" then
		local cone = wep.CurCone
		if type(cone) ~= "number" then return ang end
		if base == "swb" and ply:Crouching() then cone = cone * 0.85 end

		-- These bases seed Lua's RNG from the command number before firing.
		math.randomseed(cmd:CommandNumber())
		return ang - Angle(math.Rand(-cone, cone), math.Rand(-cone, cone), 0) * 25
	end

	-- The donor has no TFA implementation; FAS2's time seed is not reliably shared.
	if base == "tfa" or base == "fas2" then return ang end

	local spread = weaponCones[wep]
	if not spread or not ded or not ded.PredictSpread then return ang end

	-- This module takes (UserCmd, Vector), NOT (UserCmd, Angle, Vector).
	local correction = ded.PredictSpread(cmd, -spread)
	local corrected = ang + correction:Angle()
	corrected:Normalize()
	return corrected
end

local function aimNoRecoil(ang, ply, wep)
	local class = wep:GetClass()
	-- These weapons do not add view punch to their bullet direction in the donor.
	if class == "weapon_pistol" or string.StartsWith(class, "m9k_")
		or string.StartsWith(class, "bb_") or string.StartsWith(class, "unclen8_") then
		return ang
	end
	return ang - ply:GetViewPunchAngles()
end

local function aimCompensate(cmd, ang, ply)
	if cmd:CommandNumber() == 0 or not cmd:KeyDown(IN_ATTACK) then return ang end
	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) or wep:Clip1() == 0 then return ang end

	if config.GetBool("violent_aimbot_norecoil") then
		ang = aimNoRecoil(ang, ply, wep)
	end
	if config.GetBool("violent_aimbot_nospread") then
		ang = aimNoSpread(cmd, ang, ply, wep)
	end
	ang:Normalize()
	ang.r = 0
	return ang
end

local aimMouseCodes = {
	MOUSE1 = 107, MOUSE_LEFT = 107,
	MOUSE2 = 108, MOUSE_RIGHT = 108,
	MOUSE3 = 109, MOUSE_MIDDLE = 109,
	MOUSE4 = 110, MOUSE_4 = 110,
	MOUSE5 = 111, MOUSE_5 = 111,
}

local function aimBindDown()
	local bind = config.Get("violent_aimbot_bind")
	if not bind or bind == "" or bind == "0" then return true end

	bind = tostring(bind):upper():gsub("%s+", "")
	if bind == "" or bind == "NONE" then return true end

	local mouse = aimMouseCodes[bind]
	if mouse then
		return input.IsMouseDown(mouse)
	end

	if bind == "ALT" then
		return input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT)
	end

	if bind == "SHIFT" then
		return input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
	end

	if bind == "CTRL" then
		return input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
	end

	local code = rawget(_G, bind) or rawget(_G, "KEY_" .. bind) or rawget(_G, "MOUSE_" .. bind) or tonumber(bind)
	if type(code) ~= "number" then return false end

	if code >= 107 then
		return input.IsMouseDown(code)
	end

	return input.IsKeyDown(code)
end

local HEADGROUP = HITGROUP_HEAD or 1

local function readHeadPos(ent)
	local set = ent:GetHitboxSet()
	if set then
		local count = ent:GetHitBoxCount(set)
		if count and count > 0 then
			for i = 0, count - 1 do
				if ent:GetHitBoxHitGroup(i, set) == HEADGROUP then
					local bone = ent:GetHitBoxBone(i, set)
					local mins, maxs = ent:GetHitBoxBounds(i, set)
					if bone and mins and maxs then
						local matrix = ent:GetBoneMatrix(bone)
						if matrix then
							return matrix * ((mins + maxs) * 0.5)
						end
					end
				end
			end
		end
	end
	return ent:EyePos()
end

local animationRecords = setmetatable({}, { __mode = "k" })
local animationModule, previousAnimFix
local animationFailed, animationWarned = false, false

stopAnimations = function()
	if animationModule then
		animationModule.EnableAnimFix(previousAnimFix)
		animationModule = nil
	end
	table.Empty(animationRecords)
end

local function syncAnimations()
	if not animationCvar:GetBool() or not config.GetBool("violent_aimbot") then
		if animationModule then stopAnimations() end
		animationFailed, animationWarned = false, false
		return false
	end

	if not IsValid(LocalPlayer()) then
		if animationModule then stopAnimations() end
		return false
	end
	if animationFailed then return false end
	if animationModule == ded and animationModule then return true end
	if animationModule then stopAnimations() end

	if not ded or not ded.UpdateClientSideAnimations or not ded.GetSimulationTime
		or not ded.GetAnimFixEnabled or not ded.EnableAnimFix then
		if not animationWarned then
			animationWarned = true
			notify("animation update unavailable; rebuild zxcmodule")
		end
		return false
	end

	animationModule = ded
	previousAnimFix = ded.GetAnimFixEnabled()
	ded.EnableAnimFix(true)
	return true
end

local function captureAnimationHead(ent, ticks)
	if not animationModule.UpdateClientSideAnimations(ent, ticks) then
		return nil, "native animation update rejected"
	end
	return readHeadPos(ent) - ent:GetPos()
end

local function updateAnimation(ent)
	if not animationModule or not IsValid(ent) or not ent:IsPlayer()
		or ent == LocalPlayer() or not ent:Alive() or ent:IsDormant() then
		animationRecords[ent] = nil
		return
	end

	local simtime = animationModule.GetSimulationTime(ent)
	if simtime ~= simtime or simtime <= 0 or simtime == math.huge then return end
	local model = ent:GetModel()
	local record = animationRecords[ent]
	if record and record.simtime == simtime and record.model == model then
		return record.offset
	end

	local ticks = 1
	if record and record.model == model and simtime > record.simtime then
		ticks = math.Clamp(math.floor((simtime - record.simtime) / engine.TickInterval() + 0.5), 1, 24)
	end

	local ok, offset, reason = pcall(captureAnimationHead, ent, ticks)
	if not ok or not offset then
		animationFailed = true
		stopAnimations()
		notify("animation update disabled: %s", tostring(ok and reason or offset))
		return
	end

	record = record or {}
	record.simtime, record.model, record.offset = simtime, model, offset
	animationRecords[ent] = record
	return offset
end

hook.Add("PreFrameStageNotify", "violent.animations.sync", function(stage)
	if stage == 0 then syncAnimations() end
end)

hook.Add("PostFrameStageNotify", "violent.animations.update", function(stage)
	if stage ~= 4 or not syncAnimations() then return end
	for _, ent in ipairs(player.GetAll()) do
		updateAnimation(ent)
		if not animationModule then break end
	end
end)

hook.Add("ShouldUpdateAnimation", "violent.animations.filter", function(ent)
	if not animationModule or not animationCvar:GetBool() or not config.GetBool("violent_aimbot") then return end
	if IsValid(ent) and ent:IsPlayer() and ent ~= LocalPlayer() and ent:Alive() and not ent:IsDormant() then
		return false
	end
end)

local function aimHeadPos(ent)
	if animationModule then
		local offset = updateAnimation(ent)
		if offset then return ent:GetPos() + offset end
	end
	return readHeadPos(ent)
end

local aimTrace = {
	mask = MASK_SHOT,
}

local function aimExtrapolate(target, head, leadTime)
	if leadTime <= 0 or target:GetMoveType() ~= MOVETYPE_WALK or target:InVehicle() then
		return head
	end

	local velocity = target:GetVelocity()
	velocity = Vector(velocity.x, velocity.y, velocity.z)
	-- A player spinning against a wall can report large velocity while its origin
	-- barely changes. Do not extrapolate that stale movement into the next shot.
	local previousPos = target:GetPos()
	if velocity:Length2DSqr() > 250000 then
		local probe = util.TraceHull({
			start = previousPos,
			endpos = previousPos + velocity * math.min(leadTime, engine.TickInterval()),
			mins = target:GetCollisionBounds(),
			maxs = select(2, target:GetCollisionBounds()),
			filter = target,
			mask = MASK_PLAYERSOLID,
			collisiongroup = COLLISION_GROUP_PLAYER_MOVEMENT,
		})
		if probe.StartSolid or probe.AllSolid or probe.Fraction < 0.05 then
			velocity = Vector(0, 0, velocity.z)
		end
	end
	local grounded = target:OnGround() and velocity.z <= 0
	if grounded and velocity:LengthSqr() == 0 then return head end

	local gravityCvar = GetConVar("sv_gravity")
	local gravityScale = target:GetGravity()
	if gravityScale == 0 then gravityScale = 1 end
	local gravity = (gravityCvar and gravityCvar:GetFloat() or 600) * gravityScale
	if target:WaterLevel() >= 2 then gravity = 0 end

	-- A small lift avoids treating contact with the floor as an embedded hull.
	local start = target:GetPos() + Vector(0, 0, 0.03125)
	local pos = start
	local mins, maxs = target:GetCollisionBounds()
	local hull = {
		mins = mins, maxs = maxs,
		filter = target,
		mask = MASK_PLAYERSOLID,
		collisiongroup = COLLISION_GROUP_PLAYER_MOVEMENT,
	}
	local tick = engine.TickInterval()
	local timeLeft = leadTime

	while timeLeft > 0 do
		local dt = math.min(tick, timeLeft)
		timeLeft = math.max(0, timeLeft - dt)

		if grounded then
			velocity.z = 0
		else
			velocity.z = velocity.z - gravity * dt * 0.5
		end

		local moveTime = dt
		for bump = 1, 4 do
			hull.start = pos
			hull.endpos = pos + velocity * moveTime
			local trace = util.TraceHull(hull)
			if trace.StartSolid or trace.AllSolid then return end
			pos = trace.HitPos
			if not trace.Hit then break end

			moveTime = moveTime * (1 - trace.Fraction)
			local into = velocity:Dot(trace.HitNormal)
			if into < 0 then
				velocity = velocity - trace.HitNormal * into
			end
			pos = pos + trace.HitNormal * 0.03125
			if moveTime <= 0 or velocity:LengthSqr() < 0.0001 then break end
		end

		-- Recheck support every step: walking off a ledge must start a fall.
		hull.start = pos
		hull.endpos = pos - Vector(0, 0, 2)
		local ground = util.TraceHull(hull)
		grounded = velocity.z <= 0 and ground.Hit and not ground.StartSolid
			and not ground.AllSolid and ground.HitNormal.z >= 0.7
		if grounded then
			pos = ground.HitPos + Vector(0, 0, 0.03125)
			velocity.z = 0
		else
			velocity.z = velocity.z - gravity * dt * 0.5
		end
	end

	-- Translate the existing head pose; never modify the entity or its network origin.
	return head + (pos - start)
end

local function aimPoint(target, ply, eyePos, leadTime)
	local head = aimHeadPos(target)
	local predicted = aimExtrapolate(target, head, leadTime)
	if not predicted then return end

	-- Check the future sightline, not the current one (which rejects emerging targets).
	-- First keep the target in the trace so an unchanged head behind its body is rejected.
	aimTrace.start = eyePos
	aimTrace.endpos = predicted
	aimTrace.filter = ply
	local trace = util.TraceLine(aimTrace)
	if trace.StartSolid or trace.AllSolid or trace.HitWorld then return end
	if trace.Hit and trace.Entity ~= target then return end

	if predicted:DistToSqr(head) < 0.0001 then
		if trace.Hit and trace.HitGroup ~= HEADGROUP then return end
	else
		-- The old target hull must not hide an obstacle on the rest of the future ray.
		aimTrace.filter = { ply, target }
		trace = util.TraceLine(aimTrace)
		if trace.Hit or trace.StartSolid or trace.AllSolid then return end
	end

	return predicted
end

local cachedAutoWep, cachedAuto = nil, false

local function isAutomaticWep(wep)
	if wep == cachedAutoWep then return cachedAuto end

	local automatic = false
	local ok, prim = pcall(function() return wep.Primary end)
	if ok and type(prim) == "table" and prim.Automatic then
		automatic = true
	end

	cachedAutoWep, cachedAuto = wep, automatic
	return automatic
end

local function aimAutoFire(cmd, ply)
	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) then return end

	local buttons = cmd:GetButtons()

	if isAutomaticWep(wep) then
		cmd:SetButtons(bit.bor(buttons, IN_ATTACK))
		return
	end

	if cmd:CommandNumber() % 3 == 0 then
		cmd:SetButtons(bit.band(buttons, bit.bnot(IN_ATTACK)))
	else
		cmd:SetButtons(bit.bor(buttons, IN_ATTACK))
	end
end

local silentView = nil
local silentOrigin = nil
local aaErrorNotified = false
local antiAimStatus = { stage = "CreateMove has not run", command = -1 }

addTrigger("violent_antiaim_status", "Print anti-aim runtime diagnostics", function()
	notify("AA diagnostics v2: mode=%s, stage=%s, cmd=%d, module=%s",
		tostring(config.Get("violent_antiaim")), antiAimStatus.stage,
		antiAimStatus.command, tostring(ded ~= nil))
	notify("AA expected=%s, PostCreateMove=%s", tostring(antiAimStatus.expected),
		tostring(antiAimStatus.observed))
end)

hook.Add("PostCreateMove", "violent.antiaim.verify", function(cmd)
	if cmd:CommandNumber() ~= antiAimStatus.command then return end
	local angles = cmd:GetViewAngles()
	antiAimStatus.observed = Angle(angles.p, angles.y, angles.r)
end)

local aaEnforce = nil

-- Runs after every Lua CreateMove hook (weapon bases, gamemodes) and right
-- before zxcmodule rewrites the verified command CRC. Anything that overwrote
-- our angles during the tick gets overwritten back here, so the anti-aim /
-- silent angle is what actually reaches the server. No-op without the module.
hook.Add("PostCreateMove", "violent.antiaim.enforce", function(cmd)
	if aaEnforce and cmd:CommandNumber() == antiAimStatus.command then
		local angles = cmd:GetViewAngles()
		if angles.p ~= aaEnforce.p or angles.y ~= aaEnforce.y or angles.r ~= aaEnforce.r then
			cmd:SetViewAngles(aaEnforce)
		end
	end
	aaEnforce = nil
end)

local function silentUpdate(cmd)
	local mYaw = GetConVar("m_yaw"):GetFloat()
	local mPitch = GetConVar("m_pitch"):GetFloat()

	silentView.p = math.Clamp(silentView.p + cmd:GetMouseY() * mPitch, -89, 89)
	silentView.y = silentView.y + cmd:GetMouseX() * -mYaw
	silentView.r = 0
	silentView:Normalize()
end

function violent_aimbot(cmd)
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() then return end
	if ply:GetMoveType() ~= MOVETYPE_WALK then return end
	if not aimBindDown() then return end

	local eyePos = ply:EyePos()
	local forward = cmd:GetViewAngles():Forward()
	local leadTime = math.Clamp(config.GetNumber("violent_aimbot_extrapolation_ticks"), 0, 8) * engine.TickInterval()

	local bestAngle, bestDot = nil, -2

	for _, target in ipairs(player.GetAll()) do
		if target == ply then continue end
		if not IsValid(target) or not target:Alive() then continue end
		if target:IsDormant() then continue end

		local head = aimPoint(target, ply, eyePos, leadTime)
		if not head then continue end

		local dot = forward:Dot((head - eyePos):GetNormalized())
		if dot > bestDot then
			bestDot = dot
			bestAngle = (head - eyePos):Angle()
		end
	end

	if bestAngle then
		if config.GetBool("violent_aimbot_autofire") and cmd:CommandNumber() ~= 0 then
			aimAutoFire(cmd, ply)
		end

		bestAngle = Angle(bestAngle.p, bestAngle.y, 0)
		local finalAngle = aimCompensate(cmd, bestAngle, ply)
		cmd:SetViewAngles(finalAngle)
	end
end

function violent_movement_fix(cmd, wish_yaw)
	local angles = cmd:GetViewAngles()

	local inverted = -1
	if math.NormalizeAngle(angles.p) > 89 or math.NormalizeAngle(angles.p) < -89 then
		inverted = 1
	end

	local diff = math.rad(math.NormalizeAngle((angles.y - wish_yaw) * inverted))

	local forwardMove, sideMove = cmd:GetForwardMove(), cmd:GetSideMove()
	cmd:SetForwardMove(forwardMove * -math.cos(diff) * inverted + sideMove * math.sin(diff))
	cmd:SetSideMove(forwardMove * math.sin(diff) * inverted + sideMove * math.cos(diff))
end

hook.Add("CreateMove", "violent.aimbot", function(cmd)
	if cmd:CommandNumber() ~= 0 then
		antiAimStatus.command = cmd:CommandNumber()
		antiAimStatus.stage = "syncAnimations"
		antiAimStatus.expected, antiAimStatus.observed = nil, nil
	end
	syncAnimations()

	if cmd:CommandNumber() == 0 then return end

	if config.GetBool("violent_aimbot_silent") or antiAimEnabled() then
		if not silentView then
			local init = cmd:GetViewAngles()
			silentView = Angle(init.p, init.y, 0)
		end

		silentUpdate(cmd)
		cmd:SetViewAngles(Angle(silentView.p, silentView.y, 0))
	else
		silentView = nil
		silentOrigin = nil
	end

	-- Keep strafing before aiming so the silent movement fix is applied last.
	if cmd:CommandNumber() ~= 0 then antiAimStatus.stage = "movement/fakelag" end
	movement(cmd)
	violentFakelag(cmd)

	-- Camera-relative yaw before the angle pipeline touches the command.
	local baseYaw = cmd:GetViewAngles().y
	local ply = LocalPlayer()
	local plyValid = IsValid(ply) and ply:Alive()
	local aaApplied = false

	-- Anti-aim first, exactly like rapehack: it is the base layer, and the
	-- aimbot overrides it afterwards only on ticks where AA steps aside
	-- (attack/use held). IN_ATTACK2 must never block it.
	antiAimStatus.stage = "antiaim"
	if not antiAimEnabled() then
		antiAimStatus.stage = "blocked: mode must be backward or sideways"
	elseif not plyValid then
		antiAimStatus.stage = "blocked: local player invalid/dead"
	elseif ply:GetMoveType() ~= MOVETYPE_WALK or ply:InVehicle() then
		antiAimStatus.stage = "blocked: movement type/vehicle"
	elseif cmd:KeyDown(IN_ATTACK) or cmd:KeyDown(IN_USE) then
		antiAimStatus.stage = "blocked: attack/use buttons=" .. cmd:GetButtons()
	else
		violentAntiAim(cmd, silentView)
		antiAimMicro(cmd, ply)
		aaApplied = true
		antiAimStatus.stage = "applied"
	end

	-- A failing aimbot must never take the anti-aim down with it.
	antiAimStatus.stage = antiAimStatus.stage .. "/aimbot"
	if config.GetBool("violent_aimbot") then
		local ok, err = pcall(violent_aimbot, cmd)
		if not ok and not aaErrorNotified then
			aaErrorNotified = true
			notify("aimbot error: %s", tostring(err))
		end
	end

	-- Re-assert our angle after every other CreateMove hook had its say.
	local finalAngles = cmd:GetViewAngles()
	if aaApplied or silentView or finalAngles.y ~= baseYaw then
		aaEnforce = Angle(finalAngles.p, finalAngles.y, finalAngles.r)
		antiAimStatus.expected = aaEnforce
	end

	-- One movement fix for the whole pipeline, based on the camera yaw.
	if finalAngles.y ~= baseYaw or finalAngles.p ~= 0 then
		violent_movement_fix(cmd, baseYaw)
	end
end)

hook.Add("CalcView", "violent.view", function(ply, origin, angles, fov, znear, zfar)
	if not config.GetBool("violent_aimbot_silent") and not antiAimEnabled() then return end
	if ply ~= LocalPlayer() then return end
	if not silentView then return end

	silentOrigin = origin

	return {
		origin = origin,
		angles = Angle(silentView.p, silentView.y, 0),
		fov = fov,
		znear = znear,
		zfar = zfar,
	}
end)

hook.Add("CalcViewModelView", "violent.vmview", function(wep, vm, oldPos, oldAng, pos, ang)
	if not config.GetBool("violent_aimbot_silent") and not antiAimEnabled() then return end
	if not silentView then return end

	return silentOrigin or pos, Angle(silentView.p, silentView.y, 0)
end)

local espFont = "violent_esp"
surface.CreateFont(espFont, { font = "Verdana", size = 12, antialias = false, outline = true })

local espCorners = {
	Vector(-1, -1, -1),
	Vector(-1, -1, 1),
	Vector(-1, 1, -1),
	Vector(-1, 1, 1),
	Vector(1, -1, -1),
	Vector(1, -1, 1),
	Vector(1, 1, -1),
	Vector(1, 1, 1),
}

local espBlack = Color(0, 0, 0, 255)
local espWhite = Color(255, 255, 255, 255)

local function espBounds(ent)
	local pos, mins, maxs = ent:GetPos(), ent:GetCollisionBounds()
	local size = (maxs - mins) * 0.5
	local center = pos + (mins + maxs) * 0.5

	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge

	for i = 1, 8 do
		local scr = (center + espCorners[i] * size):ToScreen()
		minX, minY = math.min(minX, scr.x), math.min(minY, scr.y)
		maxX, maxY = math.max(maxX, scr.x), math.max(maxY, scr.y)
	end

	return math.floor(minX), math.floor(minY), math.ceil(maxX), math.ceil(maxY)
end

function violent_esp()
	surface.SetFont(espFont)
	local lp = LocalPlayer()

	for _, ply in ipairs(player.GetAll()) do
		if ply == lp or not ply:Alive() then continue end

		local minX, minY, maxX, maxY = espBounds(ply)
		local w, h = maxX - minX, maxY - minY
		if w <= 0 or h <= 0 then continue end

		surface.SetAlphaMultiplier(ply:IsDormant() and 0.35 or 1)

		surface.SetDrawColor(espBlack)
		surface.DrawOutlinedRect(minX - 1, minY - 1, w + 2, h + 2, 3)

		surface.SetDrawColor(espWhite)
		surface.DrawOutlinedRect(minX, minY, w, h, 1)

		local health, maxHealth = ply:Health(), ply:GetMaxHealth()
		local frac = maxHealth > 0 and health / maxHealth or 0
		if frac > 1 then frac = 1 elseif frac < 0 then frac = 0 end

		surface.SetDrawColor(espBlack)
		surface.DrawRect(minX - 6, minY - 1, 4, h + 2)

		surface.SetDrawColor(255 - frac * 255, frac * 255, 0, 255)
		surface.DrawRect(minX - 5, minY + h * (1 - frac), 2, h * frac)

		local text = tostring(health)
		local tw, th = surface.GetTextSize(text)
		surface.SetTextColor(espWhite)
		surface.SetTextPos(minX - 6 - tw, minY)
		surface.DrawText(text)

		local name = ply:Nick()
		tw = surface.GetTextSize(name)
		surface.SetTextPos(minX + w / 2 - tw / 2, minY - th - 1)
		surface.DrawText(name)

		local wep = ply:GetActiveWeapon()
		local weapon = IsValid(wep) and wep:GetClass() or "none"
		tw = surface.GetTextSize(weapon)
		surface.SetTextPos(minX + w / 2 - tw / 2, maxY + 1)
		surface.DrawText(weapon)
	end

	surface.SetAlphaMultiplier(1)
end

config.Add("violent_esp", 0, "Player ESP", 0, 1)

hook.Add("HUDPaint", "violent.esp", function()
	if config.GetBool("violent_esp") then
		violent_esp()
	end
end)

-- Register every setting before loading, including when executed on an active map.
hook.Add("InitPostEntity", "violent.config.autoload", initializeConfig)
if IsValid(LocalPlayer()) then
	initializeConfig()
end
