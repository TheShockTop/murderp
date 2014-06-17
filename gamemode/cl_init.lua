include("sh_translate.lua")
include("shared.lua")
include("cl_hud.lua")
include("cl_scoreboard.lua")
include("cl_footsteps.lua")
include("cl_respawn.lua")
include("cl_murderer.lua")
include("cl_player.lua")
include("cl_fixplayercolor.lua")
include("cl_ragdoll.lua")
include("cl_chattext.lua")
include("cl_voicepanels.lua")
include("cl_rounds.lua")
include("cl_endroundboard.lua")
include("cl_qmenu.lua")
include("cl_spectate.lua")
include("cl_adminpanel.lua")
include("cl_flashlight.lua")

GM.Debug = CreateClientConVar( "mu_debug", 0, true, true )
GM.HaloRender = CreateClientConVar( "mu_halo_render", 1, true, true ) // should we render halos
GM.HaloRenderLoot = CreateClientConVar( "mu_halo_loot", 1, true, true ) // shouuld we render loot halos
GM.HaloRenderKnife = CreateClientConVar( "mu_halo_knife", 1, true, true ) // shouuld we render murderer's knife halos

function GM:Initialize()
	MsgN("Murder Client Initializing...") -- Fuck it, adding debug because it's pissing me off
	self:FootStepsInit()
end

function GM:InitPostEntity()
   MsgN("Murder Client post-init...")

   if not game.SinglePlayer() then
      timer.Create("idlecheck", 5, 0, CheckIdle)
   end
end

GM.FogEmitters = {}
if GAMEMODE then GM.FogEmitters = GAMEMODE.FogEmitters end
function GM:Think()
	for k, ply in pairs(player.GetAll()) do
		if ply:Alive() && ply:GetNWBool("MurdererFog") then
			if !ply.FogEmitter then
				ply.FogEmitter = ParticleEmitter(ply:GetPos())
				self.FogEmitters[ply] = ply.FogEmitter
			end
			if !ply.FogNextPart then ply.FogNextPart = CurTime() end

			local pos = ply:GetPos() + Vector(0,0,30)
			local client = LocalPlayer()

			if ply.FogNextPart < CurTime() then

				if client:GetPos():Distance(pos) > 1000 then return end

				ply.FogEmitter:SetPos(pos)
				ply.FogNextPart = CurTime() + math.Rand(0.01, 0.03)
				local vec = Vector(math.Rand(-8, 8), math.Rand(-8, 8), math.Rand(10, 55))
				local pos = ply:LocalToWorld(vec)
				local particle = ply.FogEmitter:Add( "particle/snow.vmt", pos)
				particle:SetVelocity(  Vector(0,0, 4) + VectorRand() * 3 )
				particle:SetDieTime( 5 )
				particle:SetStartAlpha( 180 )
				particle:SetEndAlpha( 0 )
				particle:SetStartSize( 6 )
				particle:SetEndSize( 7 )   
				particle:SetRoll( 0 )
				particle:SetRollDelta( 0 )
				particle:SetColor( 0, 0, 0 )
				//particle:SetGravity( Vector( 0, 0, 10 ) )
			end
		else
			if ply.FogEmitter then
				ply.FogEmitter:Finish()
				ply.FogEmitter = nil
				self.FogEmitters[ply] = nil
			end
		end
	end

	// clean up old fog emitters
	for ply, emitter in pairs(self.FogEmitters) do
		if !IsValid(ply) || !ply:IsPlayer() then
			emitter:Finish()
			self.FogEmitters[ply] = nil
		end
	end
end

function GM:CleanUpMap()
   -- Ragdolls sometimes stay around on clients. Deleting them can create issues
   -- so all we can do is try to hide them.
   for _, ent in pairs(ents.FindByClass("prop_ragdoll")) do
      if IsValid(ent) then
         ent:SetNoDraw(true)
         ent:SetSolid(SOLID_NONE)
         ent:SetColor(Color(0,0,0,0))

         -- Horrible hack to make targetid ignore this ent, because we can't
         -- modify the collision group clientside.
         ent.NoTarget = true
      end
   end

   -- This cleans up decals since GMod v100
   game.CleanUpMap()
end


function GM:EntityRemoved(ent)

end

function GM:PostDrawViewModel( vm, ply, weapon )

	if ( weapon.UseHands || !weapon:IsScripted() ) then

		local hands = LocalPlayer():GetHands()
		if ( IsValid( hands ) ) then hands:DrawModel() end

	end

end

function GM:RenderScene( origin, angles, fov )
	-- self:FootStepsRenderScene(origin, angles, fov)
end

function GM:PostDrawTranslucentRenderables()
	self:DrawFootprints()
end

function GM:PreDrawHalos()
	local client = LocalPlayer()

	if IsValid(client) && client:Alive() && self.HaloRender:GetBool() then
		if self.HaloRenderLoot:GetBool() then
			local tab = {}
			for k,v in pairs(ents.FindByClass( "weapon_mu_magnum" )) do
				if !IsValid(v.Owner) then
					table.insert(tab, v)
				end
			end
			table.Add(tab, ents.FindByClass( "mu_loot" ))
			halo.Add(tab, Color(0, 220, 0), 4, 4, 2, true, false)
		end

		if self:GetAmMurderer() && self.HaloRenderKnife:GetBool() then
			local tab = {}
			for k,v in pairs(ents.FindByClass( "weapon_mu_knife" )) do
				if !IsValid(v.Owner) then
					table.insert(tab, v)
				end
			end
			table.Add(tab, ents.FindByClass( "mu_knife" ))
			halo.Add(tab, Color(220, 0, 0), 5, 5, 5, true, false)
		end
	end
end

net.Receive("mu_tker", function (len)
	GAMEMODE.TKerPenalty = net.ReadUInt(8) != 0
end)

-- Simple client-based idle checking
local idle = {ang = nil, pos = nil, mx = 0, my = 0, t = 0}
function CheckIdle()
--   MsgN("Ping!") --debug
   local client = LocalPlayer()
   if not IsValid(client) then return end

   if not idle.ang or not idle.pos then
      -- init things
      idle.ang = client:GetAngles()
      idle.pos = client:GetPos()
      idle.mx = gui.MouseX()
      idle.my = gui.MouseY()
      idle.t = CurTime()

      return
   end

   if GAMEMODE.RoundStage == 1 and client:Alive() then
      local idle_limit = GetGlobalInt("ttt_idle_limit", 300) or 300
      if idle_limit <= 0 then idle_limit = 300 end -- networking sucks sometimes

      if client:GetAngles() != idle.ang then
         -- Normal players will move their viewing angles all the time
         idle.ang = client:GetAngles()
         idle.t = CurTime()
      elseif gui.MouseX() != idle.mx or gui.MouseY() != idle.my then
         -- Players in eg. the Help will move their mouse occasionally
         idle.mx = gui.MouseX()
         idle.my = gui.MouseY()
         idle.t = CurTime()
      elseif client:GetPos():Distance(idle.pos) > 10 then
         -- Even if players don't move their mouse, they might still walk
         idle.pos = client:GetPos()
         idle.t = CurTime()
      elseif CurTime() > (idle.t + idle_limit) then
		RunConsoleCommand("mu_afk")
      elseif CurTime() > (idle.t + (idle_limit / 2)) then
         -- will repeat
         client:PrintMessage( HUD_PRINTTALK, "If you delay any further, you will be moved to spectator.")
	end
	end
end
