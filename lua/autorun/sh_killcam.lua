----// Killcam //----
-- Author: Exho

killcam = {}

if SERVER then
	AddCSLuaFile()
	util.AddNetworkString("killcam_data")
	util.AddNetworkString("killcam_end")
	util.AddNetworkString("killcam_chat")
	
	local snapshotsEnabled = CreateConVar( "kc_snapshots", "1", {FCVAR_REPLICATED}, "Whether or not the killcam will routinely take 'snapshots' of the connected players to reenact their walking" )
	local snapshotMax = CreateConVar( "kc_snapshot_amount", "3", {FCVAR_PROTECTED}, "Max amount of snapshots kept per player" )
	local snapshotDelay = CreateConVar( "kc_snapshot_delay", "2", {FCVAR_PROTECTED}, "Seconds between when each snapshot is taken" )
	
	-- Track shooting
	hook.Add("EntityFireBullets", "killcam_trackbullets", function( ply, data )
		ply.lastShotData = {
			["time"] = CurTime(),
			["aMdl"] = ply:GetModel(),
			["aPos"] = ply:GetPos(),
			["aAng"] = ply:GetAngles(),
			["aCol"] = ply.GetPlayerColor and ply:GetPlayerColor() or ply:GetColor(),
			["aClass"] = ply:GetClass(),
			["aSequence"] = ply:GetSequence(),
			["aCycle"]   = ply:GetCycle(),
			["snapshots"] = ply.snapshots,
		}
		
		-- If they have a weapon, override these two keys
		if ply.GetActiveWeapon and IsValid(ply:GetActiveWeapon()) then
			ply.lastShotData.aClass = ply:GetActiveWeapon().GetClass and ply:GetActiveWeapon():GetClass()
			ply.lastShotData.aSound = ply:GetActiveWeapon().Primary and ply:GetActiveWeapon().Primary.Sound or "nil"
		end
	end)
	
	-- Erase any killcam data on a fresh spawn
	hook.Add("PlayerSpawn", "killcam_erasedata", function( ply )
		ply.lastShotData = {}
		ply.snapshots = {}
		ply:SetNWBool("inKillcam", false )
	end)
	
	-- Run snapshots
	local nextSnapshot = 0
	hook.Add("Tick", "killcam_getsnapshots", function()
		if snapshotsEnabled:GetBool() == false then return end
		
		if CurTime() > nextSnapshot then
			local tbl = player.GetAll()
			
			-- Snapshot NPCs
			for k, v in pairs( ents.GetAll() ) do
				if v:IsNPC() then
					table.insert( tbl, v )
				end
			end
			
			-- Snapshot players 
			for k, v in pairs( tbl ) do
				if v:IsPlayer() and v:Alive() or IsValid(v) then
					v.snapshots = v.snapshots or {}
					
					if #v.snapshots >= snapshotMax:GetInt() then
						table.remove( v.snapshots, 1 )
					end
					
					table.insert(v.snapshots, {v:GetPos(), v:GetAngles()})
				else
					v.snapshots = nil
				end
			end
			
			nextSnapshot = CurTime() + snapshotDelay:GetInt()
		end
	end)
	
	killcam.lastAttacker = nil
	killcam.lastVictim = nil

	-- Create the killcam data for the dead player
	hook.Add("DoPlayerDeath", "killcam_handler", function( ply, att, dmginfo )
		if ply != att then
			if att.lastShotData then -- Was shot
				if ply:GetInfoNum( "kc_enabled", "1" ) != 0 then -- The victim has killcams enabled
					killcam.sendKillcamData( ply, att )
				end
			end
			
			killcam.lastAttacker = att
			killcam.lastVictim = ply
		end
	end)
	
	-- Add a round winning kill for TTT
	hook.Add("TTTEndRound", "killcam_finalkill", function( result )
		if killcam.lastVictim != nil and killcam.lastAttacker != nil then
			killcam.sendKillcamData( killcam.lastVictim, killcam.lastAttacker, true )
		end
		
		killcam.lastAttacker = nil
		killcam.lastVictim = nil
	end)
	
	hook.Add("PlayerSay", "killcam_chat", function( ply, text )
		if string.sub( text, 1, 8 ):lower() == "!killcam" then
			net.Start("killcam_chat")
			net.Send( ply )
		end
	end)
	
	-- Prepare and send the killcam data to ply or all players if bBroadcast is true
	function killcam.sendKillcamData( ply, att, bBroadcast )
		if not att.lastShotData then 
			print("Failed to create killcam att.lastShotData = nil")
			return
		end
		
		att.lastShotData.time = att.lastShotData.time or CurTime()
		if CurTime() - att.lastShotData.time > 15 then return end
		
		local bone = att:LookupBone("ValveBiped.Bip01_Head1")

		-- Get their head for reference
		local bPos
		if bone then
			bPos = att:GetBonePosition( bone )
		end
		
		local fwd = att:GetForward()
		
		-- Find their arm to start the bullet trace at
		local bone = att:LookupBone("ValveBiped.Bip01_R_Forearm")
		local bPos2
		if bone then
			bPos2 = att:GetBonePosition( bone )
			if bPos2 then
				att.lastShotData.shooterPos = bPos2
			else
				att.lastShotData.shooterPos = Vector( bPos.x + (fwd.x * 5), bPos.y + (fwd.y * 5), bPos.z - 15 )
			end
		else
			-- No head bone..
			local pos = att:GetPos()
			att.lastShotData.shooterPos = Vector( pos.x, pos.y, pos.z )
		end
		
		if snapshotsEnabled:GetBool() == false then 
			att.lastShotData.snapshots = nil
		else
			att.lastShotData.snapshots = att.lastShotData.snapshots or {}
		end
		
		-- Fallbacks
		att.lastShotData.aMdl = att.lastShotData.aMdl or att:GetModel()
		att.lastShotData.vPos = ply:GetPos()
		att.lastShotData.vAng = ply:GetAngles()
		att.lastShotData.vSequence = ply:GetSequence()
		att.lastShotData.vCycle = ply:GetCycle()
		att.lastShotData.aPos = att.lastShotData.aPos or att:GetPos()
		att.lastShotData.aAng = att.lastShotData.aAng or att:GetAngles()
		att.lastShotData.aClass = att.lastShotData.aClass or "nil"
		att.lastShotData.aSound = att.lastShotData.aSound or "nil"
		
		if att.Nick then
			att.lastShotData.nick = att:Nick()
		elseif att:IsNPC() then
			att.lastShotData.nick = "an NPC"
		end
		
		att.lastShotData.hitgroup = ply:LastHitGroup()
		
		ply:Spectate( OBS_MODE_ROAMING )
		ply:SetNWBool("inKillcam", true )
		
		net.Start("killcam_data")
			local tbl = att.lastShotData
			
			-- Network every needed value to the client(s)
			-- It might be a bit more efficient than net.*Table but lord is it a pain to maintain
			net.WriteAngle( tbl.aAng )
			net.WriteAngle( tbl.vAng )
			if type( tbl.aCol ):lower() == "color" then
				net.WriteColor( tbl.aCol )
			else	
				tbl.aCol = tbl.aCol or color_white
				net.WriteColor( Color( tbl.aCol.r, tbl.aCol.g, tbl.aCol.b, tbl.aCol.a ) )
			end
			net.WriteVector( tbl.vPos )
			net.WriteVector( tbl.aPos )
			net.WriteVector( tbl.shooterPos )
			net.WriteInt( tbl.hitgroup, 3 )
			net.WriteString( tbl.aMdl )
			net.WriteString( tbl.nick )
			net.WriteString( tbl.aClass )
			net.WriteString( tbl.aSound )
			net.WriteFloat( tbl.aSequence )
			net.WriteFloat( tbl.aCycle )
			net.WriteFloat( tbl.vSequence )
			net.WriteFloat( tbl.vCycle )
			net.WriteBool( bBroadcast )
			net.WriteTable( tbl.snapshots ) -- Last instance of WriteTable
			
		if bBroadcast == true then
			net.Broadcast()
		else
			net.Send( ply )
		end
		
		-- Wipe their table
		att.lastShotData = {}
	end
	
	-- End a player's killcam
	net.Receive("killcam_end", function( len, ply )
		ply:UnSpectate()
		ply:SetNWBool("inKillcam", false )
	end)
	
	-- Override PlayerDeathThink so the player cannot spawn while the killcam is in progress
	hook.Add("Initialize", "killcam_override", function()
		if string.lower(engine.ActiveGamemode()) == "terrortown" then 
			-- TTT's PlayerDeathThink is renamed to SpectatorThink
			function GAMEMODE:SpectatorThink(ply)
				if ply:GetNWBool("inKillcam", false ) then return end
				
			   if ply:GetRagdollSpec() then
				  local to_switch, to_chase, to_roam = 2, 5, 8
				  local elapsed = CurTime() - ply.spec_ragdoll_start
				  local clicked = ply:KeyPressed(IN_ATTACK)
				  local m = ply:GetObserverMode()
				  if (m == OBS_MODE_CHASE and clicked) or elapsed > to_roam then
					 ply:SetRagdollSpec(false)
					 ply:Spectate(OBS_MODE_ROAMING)
					 local spec_spawns = ents.FindByClass("ttt_spectator_spawn")
					 if spec_spawns and #spec_spawns > 0 then
						local spawn = table.Random(spec_spawns)
						ply:SetPos(spawn:GetPos())
						ply:SetEyeAngles(spawn:GetAngles())
					 end
				  elseif (m == OBS_MODE_IN_EYE and clicked and elapsed > to_switch) or elapsed > to_chase then
					 ply:Spectate(OBS_MODE_CHASE)
				  end

				  if not IsValid(ply.server_ragdoll) then ply:SetRagdollSpec(false) end
			   elseif ply:GetMoveType() < MOVETYPE_NOCLIP and ply:GetMoveType() > 0 or ply:GetMoveType() == MOVETYPE_LADDER then
				  ply:Spectate(OBS_MODE_ROAMING)
			   end
			   if ply:GetObserverMode() != OBS_MODE_ROAMING and (not ply.propspec) and (not ply:GetRagdollSpec()) then
				  local tgt = ply:GetObserverTarget()
				  if IsValid(tgt) and tgt:IsPlayer() then
					 if (not tgt:IsTerror()) or (not tgt:Alive()) then
						ply:Spectate(OBS_MODE_ROAMING)
						ply:SpectateEntity(nil)
					 elseif GetRoundState() == ROUND_ACTIVE then
						ply:SetPos(tgt:GetPos())
					 end
				  end
			   end
			end
		else
			-- Regular Sandbox player think
			function GAMEMODE:PlayerDeathThink( pl )
				if not pl:GetNWBool("inKillcam", false ) then
					if ( pl.NextSpawnTime && pl.NextSpawnTime > CurTime() ) then return end
					if ( pl:KeyPressed( IN_ATTACK ) || pl:KeyPressed( IN_ATTACK2 ) || pl:KeyPressed( IN_JUMP ) ) then
						pl:Spawn()
					end
				end
			end
		end
	end)
end

local get = player.GetAll
if CLIENT then

	local killcamEnabled = CreateConVar( "kc_enabled", "1", {FCVAR_USERINFO}, "Do we show a killcam or not when we die?" )
	killcam.running = false
	
	concommand.Add("kc_end", function()
		killcam.endKillcam()
	end)
	
	concommand.Add("kc_panel", function()
		killcam.openPanel()
	end)
	
	concommand.Add("kc_load", function( ply, _, _, str )
		if not ply:GetNWBool("inKillcam", false ) then
			local fileName = str
			
			-- Strip the extension (if included) so we can add our own
			fileName = string.gsub( fileName, ".txt", "" )
			fileName = "killcam/"..fileName..".txt"
			
			if file.Exists( fileName, "DATA" ) then
				local json = file.Read( fileName, "DATA" )
				
				local tbl = util.JSONToTable( json )
				local bSuc, err = pcall(killcam.createKillcam, tbl )

				-- Catch errors
				if err then
					chat.AddText(Color(52, 73, 94), "[Killcam]: ", color_white, "Failed to load killcam due to Lua error: \r\n", Color( 255, 255, 100 ), err)
				end
				
				killcam.kcMsgC("Loading killcam from file")
			else
				killcam.kcMsgC("Cannot find saved killcam for garrysmod/data/"..fileName)
			end
		else
			killcam.kcMsgC("Cannot have multiple killcams running")
		end
	end)
	
	killcam.hitgroupBones = {
		[HITGROUP_GENERIC] = "ValveBiped.Bip01_Spine",
		[HITGROUP_HEAD] = "ValveBiped.Bip01_Head1",
		[HITGROUP_CHEST] = "ValveBiped.Bip01_Spine",
		[HITGROUP_STOMACH] = "ValveBiped.Bip01_Spine",
		[HITGROUP_LEFTARM] = "ValveBiped.Bip01_L_Forearm",
		[HITGROUP_RIGHTARM] = "ValveBiped.Bip01_R_Forearm",
		[HITGROUP_LEFTLEG] = "ValveBiped.Bip01_L_Thigh",
		[HITGROUP_RIGHTLEG] = "ValveBiped.Bip01_L_Thigh",
		[HITGROUP_GEAR] = "ValveBiped.Bip01_Spine",
	}
	
	killcam.shootSounds = {
		-- HL2
		["weapon_357"] = "weapons/357/357_fire2.wav",
		["weapon_pistol"] = "weapons/pistol/pistol_fire2.wav",
		["weapon_smg1"] = "weapons/smg1/smg1_fire1.wav",
		["weapon_ar2"] = "weapons/ar2/fire1.wav",
		["weapon_shotgun"] = "weapons/shotgun/shotgun_fire6.wav",
		["weapon_crossbow"] = "weapons/crossbow/fire1.wav",
		
		-- HL2 Entities
		["npc_turret_floor"] = "npc/turret_floor/shoot1.wav",
		["npc_combine_s"] = "weapons/shotgun/shotgun_fire6.wav",
		["npc_metropolice"] = "weapons/smg1/smg1_fire1.wav",
		--["npc_helicopter"] = "npc/combine_gunship/gunship_fire_loop1.wav",
		--["npc_combinegunship"] = "npc/combine_gunship/gunship_fire_loop1.wav",
		
		-- CSS/TTT
		["weapon_ttt_glock"] = "weapons/glock/glock18-1.wav",
		["weapon_ttt_m16"] = "weapons/m4a1/m4a1-1.wav",
		["weapon_ttt_sipistol"] = "weapons/usp/usp1.wav",
		["weapon_ttt_flaregun"] = "weapons/usp/usp1.wav",
		["weapon_ttt_push"] = "weapons/ar2/fire1.wav",
		["weapon_zm_mac10"] = "weapons/mac10/mac10-1.wav",
		["weapon_zm_pistol"] = "weapons/fiveseven/fiveseven-1.wav",
		["weapon_zm_revolver"] = "weapons/deagle/deagle-1.wav",
		["weapon_zm_shotgun"] = "weapons/xm1014/xm1014-1.wav",
		["weapon_zm_sledge"] = "weapons/m249/m249-1.wav",
	}
	
	surface.CreateFont( "Killcam_Large", {
		font = "Arial",
		size = 60,
		weight = 500,
		antialias = true,
	} )
	
	surface.CreateFont( "Killcam_Med", {
		font = "Arial",
		size = 25,
		weight = 500,
		antialias = true,
	} )
	
	surface.CreateFont( "Killcam_Small", {
		font = "Arial",
		size = 19,
		weight = 500,
		antialias = true,
	} )
	
	local function rgbTo255( col )
		return Color(col.r * 255, col.g * 255, col.b * 255)
	end
	
	function killcam.kcMsgC( text )
		MsgC( Color(200, 200, 100), "[Killcam]: ", color_white, text, "\n" )
	end
	
	function killcam.endKillcam( player, attacker, bullet )
		killcam.kcMsgC( "Ending killcam" )
		
		killcam.running = false
		
		hook.Remove( "Think", "killcam_prediction" )
		hook.Remove( "CalcView", "killcam_view" )
		hook.Remove( "HUDPaint", "killcam_hud")
		hook.Remove( "PostDrawOpaqueRenderables", "killcam_tracer" )
		
		net.Start("killcam_end")
		net.SendToServer()
		
		if IsValid(attacker) then
			attacker:Remove()
		end
		
		if IsValid(player) then
			player:Remove()
		end
		
		if IsValid(bullet) then
			bullet:Remove()
		end

		for k, v in pairs( ents.GetAll() ) do
			if v.killcamNoDraw then
				v:SetNoDraw( false )
				v.killcamNoDraw = nil
			end
		end
	end

	function killcam.createKillcam( data )
		local client = LocalPlayer() 
		
		killcam.kcMsgC("Creating killcam! End round? "..tostring(data.special==true))
		
		if client:GetNWBool("inKillcam", false ) or killcam.running == true then
			killcam.kcMsgC( "Cannot have multiple killcams running" )
			return
		end
		
		local bSnapshots = GetConVarNumber("kc_snapshots") == 1
		data.snapshots = data.snapshots or {}
		
		data.vMdl = data.vMdl or client:GetModel()
		data.vCol = data.vCol or client:GetPlayerColor()
		
		local attacker, player, bullet 
		local bSuc, err = pcall(function() 
			-- Attacker model
			attacker = ClientsideModel( data.aMdl, RENDERGROUP_OPAQUE )
			attacker:SetPos( data.aPos )
			local ang = data.aAng
			attacker:SetAngles( Angle( 0, ang.y, 0 ) )
			attacker:SetRenderMode( RENDERMODE_TRANSALPHA )
			if data.aCol.r <= 1 and data.aCol.g <= 1 and data.aCol.b <= 1 then -- This is a GetPlayerColor color object so we need to convert it
				data.aCol = rgbTo255( data.aCol )
			end
			attacker:SetColor( data.aCol )
			
			-- This poses the model according to how the player actually looked at the time of the killing
			-- Honestly, I don't understand it but it does the job
			if data.aSequence then
				attacker:SetSequence( data.aSequence )
				attacker:SetCycle( data.aCycle )
			end

			-- Victim model
			player = ClientsideModel( data.vMdl, RENDERGROUP_OPAQUE )
			player:SetPos( Vector(data.vPos.x, data.vPos.y, data.vPos.z) ) -- Victim's Z position seems to be floating in the air
			local ang = data.vAng
			player:SetAngles( Angle( 0, ang.y, 0 ) )
			player:SetRenderMode( RENDERMODE_TRANSALPHA ) 
			player:SetColor( rgbTo255( data.vCol ) )
			
			if data.vSequence then
				player:SetSequence( data.vSequence )
				player:SetCycle( data.vCycle )
			end
			
			-- Bullet model
			bullet = ClientsideModel( "models/Items/AR2_Grenade.mdl", RENDERGROUP_OPAQUE )
			bullet:SetPos( data.shooterPos )
		end)
		
		if err then
			chat.AddText(Color(52, 73, 94), "[Killcam]: ", color_white, "Failed to create killcam due to Lua error: \r\n", Color( 255, 255, 100 ), err)
			killcam.endKillcam( player, attacker, bullet )
			return
		end
		
		-- Drop the victim's model by crouch height for accuracy
		-- TODO: Get around this by using Sequence/Cycle functions to pose the ragdoll as crouching
		if client:Crouching() then
			local pos = player:GetPos()
			player:SetPos( Vector( pos.x, pos.y, pos.z - 36 ) )
		end
		
		local hitPos = player:GetPos()
		
		-- Get our bone for the specified hitgroup
		local bone = killcam.hitgroupBones[data.hitgroup]
		local boneID = player:LookupBone( bone )
		
		-- Okay, can't find that bone.. Try the spine
		if not boneID then
			killcam.kcMsgC("Cant find bone: "..bone)
			bone = "ValveBiped.Bip01_Spine"
			boneID = player:LookupBone( bone )
		end
		
		-- Get the original bone position or our spine fallback
		if boneID then
			killcam.kcMsgC("Hit at "..bone)
			local pos = player:GetBonePosition( boneID )
			hitPos = pos 
		else
			-- Some modellers don't seem to think spines are neccessary.. So the bullet will come from our player's foot
			hitPos = player:GetPos()
		end
		
		-- Expand the hit position forward by a bit so we are certain that the simulated bullet will hit the simulated player
		local fwd = attacker:GetForward()
		local oHitPos = hitPos
		hitPos = Vector( hitPos.x + ( fwd.x * 50), hitPos.y + ( fwd.y * 50), hitPos.z )
		
		-- Make sure the bullet is facing the right way
		bullet:SetAngles( (hitPos - bullet:GetPos()):Angle() )
		
		local followingBullet = !bSnapshots
		
		killcam.running = true

		-- CalcView hook to spectate the player
		hook.Add("CalcView", "killcam_view", function( ply, pos, ang )
			local view = {}
			
			if followingBullet then -- Watch the bullet
				local pos = bullet:GetPos()
				local fwd = bullet:GetForward()
				local r = bullet:GetRight()

				-- We will watch the bullet from behind it and to the right (sometimes its on the left)
				view.origin = Vector( pos.x + (r.x + 50) - (fwd.x - 25), pos.y + (r.y + 50) - (fwd.y - 25), pos.z + 25 )
				
				local ang = (oHitPos - view.origin):Angle()
				view.angles = Angle( ang.p, ang.y + 5, ang.r )
			else -- Watch the attacker
				local pos = attacker:GetPos()
				local fwd = attacker:GetForward()
				
				boneID = attacker:LookupBone( "ValveBiped.Bip01_Head1" )
				if boneID then
					pos = attacker:GetBonePosition( boneID )
				end
				
				-- A nice little first person view
				view.origin = Vector( pos.x + fwd.x*5, pos.y + fwd.y*5, pos.z )
				
				view.angles = attacker:GetAngles()
			end
		 
			return view
		end)

		-- Draw a tracer following the bullet
		local ID = Material( "cable/redlaser" )
		hook.Add( "PostDrawOpaqueRenderables", "killcam_tracer", function()
			if IsValid( bullet ) then
				render.SetMaterial( ID )
				render.DrawBeam( data.shooterPos, bullet:GetPos(), 10, 0, 3, Color(255,255,255) )
			else
				hook.Remove( "PostDrawOpaqueRenderables", "killcam" )
			end
		end)
		
		-- Hide other entities
		for k, v in pairs( ents.GetAll() ) do
			if v:IsNPC() or v:IsPlayer() or v:GetClass() == "prop_ragdoll" or v == client:GetViewModel(0) then
				v:SetNoDraw( true )
				v.killcamNoDraw = true
			end
		end
		
		local key = 1
		if bSnapshots then
			-- Make sure the player moves to the killing shot
			table.insert(data.snapshots, {attacker:GetPos(), attacker:GetAngles()} )
			
			-- Set up the positions and angles from the snap shot
			local from = data.snapshots[key][1]
			attacker:SetPos( Vector( from.x, from.y, from.z) )
			
			local fromA = data.snapshots[key][2]
			attacker:SetAngles( Angle( fromA.p, fromA.y, fromA.r ) )
			
			local to, toA
			if data.snapshots[key+1] != nil then
				toA = data.snapshots[key+1][2]
				to = data.snapshots[key+1][1]
			else
				toA = fromA
				to = from
			end
		end
		
		-- Draw the COD-like hud info
		hook.Add( "HUDPaint", "killcam_hud", function()
			local h = ScrH()/8
			
			surface.SetDrawColor( Color( 0, 0, 0, 240) )
			surface.DrawRect( 0, 0, ScrW(), h )
			
			surface.DrawRect( 0, ScrH() - h, ScrW(), h)
			
			if data.special then
				draw.DrawText( "Round winning kill", "Killcam_Large", ScrW()/2, h/2 - 30, color_white, TEXT_ALIGN_CENTER)
			else
				draw.DrawText( "Kill cam", "Killcam_Large", ScrW()/2, h/2 - 30, color_white, TEXT_ALIGN_CENTER)
			end
			
			local text = data.nick or "the world"
			draw.DrawText( "Killed by "..text, "Killcam_Med", ScrW()/2, h - 40, Color( 200, 200, 200 ), TEXT_ALIGN_CENTER)
			
			draw.DrawText( "Press 'spacebar' to skip", "Killcam_Med", ScrW()/2 , ScrH() - h/2 - 20, Color( 150, 150, 150 ), TEXT_ALIGN_CENTER)
			
			draw.DrawText( "The killcam is a reenactment,\nit can be wrong", "Killcam_Small", 10, 10, Color( 150, 150, 150 ), TEXT_ALIGN_LEFT)
		end)
		
		-- Plays the gunshot noise for the enemy's gun
		local heardGunshot = false
		local function playGunshot( pos, fireSound )
			local soundName = fireSound
			
			if not soundName then
				-- Check the table for a sound matching that weapon's class
				if killcam.shootSounds[data.aClass] then
					soundName = killcam.shootSounds[data.aClass]
				else
					-- Default to the 357
					soundName = killcam.shootSounds["weapon_357"]
				end
			end
			
			sound.Play( soundName, pos )
			heardGunshot = true
		end
		
		local cleanup = false
		local savedKillcam = false
		hook.Add("Think", "killcam_prediction", function()
			-- End the kill cam
			if input.IsKeyDown( KEY_SPACE ) then
				cleanup = true
			end
			
			-- Save the killcam data
			if input.IsKeyDown( KEY_K ) and not savedKillcam then
				local json = util.TableToJSON(data)
				
				local fileName = game.GetMap().."_"..os.time()..".txt"
				
				file.CreateDir("killcam")
				file.Write( "killcam/"..fileName, json )
				
				chat.AddText(Color(52, 73, 94), "[Killcam]: ", color_white, "Saved current killcam to "..fileName)
				
				savedKillcam = true
			end
			
			-- Move and angle the attacker according to the snapshots
			if bSnapshots then
				if data.snapshots[key+1] != nil then
					to = data.snapshots[key+1][1]
					local pos = LerpVector( 1 * FrameTime(), attacker:GetPos(), Vector( to.x, to.y, to.z ))
					attacker:SetPos( pos )
					
					toA = data.snapshots[key+1][2]
					local oAng = attacker:GetAngles()
					local ang = LerpAngle( 1 * FrameTime(), attacker:GetAngles(), Angle( 0, toA.y, 0 ))
					attacker:SetAngles( Angle( 0, ang.y, 0 ) )
				else
					to = attacker:GetPos()
				end
				
				-- Advance to the next snapshot if close enough
				local aPos = attacker:GetPos()
				if math.ceil(aPos:Distance( to )) <= 20 then	
					if key <= #data.snapshots then
						key = key + 1
					else
						followingBullet = true
					end
				end
			end
			
			-- Now our focus is on the bullet
			if followingBullet then
				-- Move the bullet
				local pos = bullet:GetPos() -- From attacker head
				pos = LerpVector( 1 * FrameTime(), pos, hitPos ) -- To body
				
				bullet:SetPos( pos )
				
				if not heardGunshot then
					playGunshot( pos, data.aSound )
				end
				
				-- Spin it
				local ang = bullet:GetAngles()
				ang:RotateAroundAxis( ang:Forward(), 1 )
				
				bullet:SetAngles( ang) 
				
				-- Stop the simulation if the bullet has entered the player
				local bPos = bullet:GetPos()
				local pPos = player:GetPos()
				local dist = math.ceil(math.abs(pPos.x) - math.abs(bPos.x) + math.abs(pPos.y) - math.abs(bPos.y))/2
				if dist > -5 and dist < 5 then
					-- Bullet has entered the player, wait 3 seconds then clean up the scene
					timer.Simple(3, function()
						cleanup = true
					end)
				end
			end
			
			-- Remove all hooks and fake players
			if cleanup then
				killcam.endKillcam( player, attacker, bullet )
			end
		end)
	end
	
	function killcam.openPanel()
		if IsValid(killcam.frame) then
			killcam.frame:Remove()
		end
		
		killcam.frame = vgui.Create( "DFrame" )
		killcam.frame:SetSize( 200, 300 )
		killcam.frame:SetPos( ScrW()/2 - killcam.frame:GetWide()/2, ScrH()/2 - killcam.frame:GetTall()/2 )
		killcam.frame:SetTitle( "Killcam" )
		killcam.frame:SetDraggable( false )
		killcam.frame:MakePopup( true )
		killcam.frame:SetDeleteOnClose( true )
		killcam.frame:ShowCloseButton( true )
		
		local saveSelector = vgui.Create( "DListView", killcam.frame )
		saveSelector:SetMultiSelect( false )
		saveSelector:SetSize( 150, 200 )
		saveSelector:SetPos( killcam.frame:GetWide()/2 - saveSelector:GetWide()/2, 40 )
		saveSelector:AddColumn( "Killcam Save" )
		
		local saves = file.Find( "killcam/*.txt", "DATA" )
		for key, save in pairs( saves ) do 
			saveSelector:AddLine( string.StripExtension( save ) )
		end
		
		local loadSave = vgui.Create("DButton", killcam.frame )
		loadSave:SetText("Load")
		loadSave:SetSize( 70, 30 )
		loadSave:SetPos( killcam.frame:GetWide()/2 - loadSave:GetWide()/2, 250 )
		loadSave.DoClick = function( self )
			killcam.frame:Remove()
			
			local index = saveSelector:GetSelectedLine()
			if index then
				-- GetLine returns a panel and not the string contents, which is an issue
				local pnl = saveSelector:GetLine( index )
				LocalPlayer():ConCommand( "kc_load "..saves[index] )
			end
		end
	end
	
	net.Receive("killcam_chat", function()
		killcam.openPanel()
	end)
	
	net.Receive("killcam_data", function()
		-- Read all the values from the server and assemble them back into a table
		local data = {}
		data.aAng = net.ReadAngle()
		data.vAng = net.ReadAngle()
		data.aCol = net.ReadColor()
		data.vPos = net.ReadVector()
		data.aPos = net.ReadVector()
		data.shooterPos = net.ReadVector()
		data.hitgroup = net.ReadInt( 3 )
		data.aMdl = net.ReadString()
		data.nick = net.ReadString()
		data.aClass = net.ReadString()
		data.aSound = net.ReadString()
		data.aSequence = net.ReadFloat()
		data.aCycle = net.ReadFloat()
		data.vSequence = net.ReadFloat()
		data.vCycle = net.ReadFloat()
		data.special = net.ReadBool()
		data.snapshots = net.ReadTable()
		
		for k, v in pairs(data) do
			if v == "nil" then
				data[k] = nil
			end
		end
		
		if killcamEnabled:GetBool() == false then 
			net.Start("killcam_end")
			net.SendToServer()
			return 
		end
		
		local bSuc, err = pcall(killcam.createKillcam, data )
		
		-- Catch errors
		if err then
			chat.AddText(Color(52, 73, 94), "[Killcam]: ", color_white, "Failed to create killcam due to Lua error: \r\n", Color( 255, 255, 100 ), err)
			net.Start("killcam_end")
			net.SendToServer()
		end
		
	end)
end