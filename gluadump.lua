-- gluadump by billy
-- http://github.com/WilliamVenner/gluadump
-- dont tell the bogs

-- put this in your lua/ folder, then add:
-- include("gluadump.lua")
-- at the bottom of lua/includes/init.lua and lua/includes/init_menu.lua
-- then, open gmod, start a new game and select "2 Players"
-- dumped files can be found in data/gluadump/
-- recommended: -noworkshop -noaddons

local function gluadump()

local filter = {
	["_PACKAGE"] = true,
	["_NAME"] = true,
	["_G"] = true,
	["_M"] = true,
	["package.loaded"] = true,
	["SpawniconGenFunctions"] = true,
	["_E"] = true,
	["g_SBoxObjects"] = true,
	["ComboBox_Emitter_Options"] = true,
	["Morph"] = true,
	["__index"] = true,
}

local gluadump = { metatables = {} }

local realm = (MENU_DLL and "MENU") or (SERVER and "SERVER") or (CLIENT and "CLIENT") or "UNKNOWN"

if realm == "MENU" then
	file.CreateDir("gluadump")
	file.Delete("gluadump/client.json")
	file.Delete("gluadump/server.json")
	file.Delete("gluadump/menu.json")
end

MsgC(Color(255, 0, 255) , "[" .. realm .. "] gluadump started\n")

local cyclic = {}
local function dump(tbl, store, id)
	for i, v in pairs(tbl) do
		if type(i) ~= "string" then continue end
		if filter[i] or filter[id .. i] then continue end

		local typeof = type(v)

		local def = { type = { [realm] = typeof } }
		store[i] = def

		if typeof == "table" or IsColor(v) then
			if v.r and v.g and v.b then
				def.type = { [realm] = "color" }
				def.value = { [realm] = { v.r, v.g, v.b, v.a or 255 } }
			elseif not table.IsEmpty(v) then
				if not cyclic[v] then
					cyclic[v] = id .. i

					def.members = {}
					dump(v, def.members, id .. i .. ".")
				else
					def.cyclic = { [realm] = cyclic[v] }
				end
			end
		elseif typeof == "function" then
			local src = debug.getinfo(v, "S")
			if src.short_src ~= "[C]" and (src.short_src ~= "lua/includes/util.lua" or ((src.linedefined ~= 182 or src.lastlinedefined ~= 182) and (src.linedefined ~= 196 or src.lastlinedefined ~= 196))) then -- HACK! filter out AccessorFunc
				def.src = { [realm] = { src.short_src, src.linedefined, src.lastlinedefined } }
			end
		elseif typeof == "number" then
			if v == math.huge then
				def.value = { [realm] = "inf" }
			else
				def.value = { [realm] = v }
			end
		elseif typeof == "boolean" then
			def.value = { [realm] = v }
		else
			def.value = { [realm] = tostring(v) }
		end
	end
end
dump(_G, gluadump, "")

local R = debug.getregistry()
for i, v in pairs(R) do
	if isstring(i) and istable(R[v]) then
		gluadump.metatables[i] = {}
		dump(R[v], gluadump.metatables[i])
	end
end

file.Write("gluadump/" .. realm:lower() .. ".json", util.TableToJSON(gluadump))

MsgC(Color(0, 255, 0) , "[" .. realm .. "] gluadump complete\n")

if file.Exists("gluadump/client.json", "DATA") and file.Exists("gluadump/server.json", "DATA") and file.Exists("gluadump/menu.json", "DATA") then
	MsgC(Color(255, 0, 255) , "gluadump compiling\n")
	
	--[[
	uncomment to compress down realms

	local all_realms = {"MENU", "SERVER", "CLIENT"}
	local compiled = util.JSONToTable(file.Read("gluadump/menu.json", "DATA"))
	local function realm_compare(realm1, realm2, weed)
		local typeof = type(realm1)
		if typeof ~= type(realm2) then return false end
		if typeof == "table" then
			for i, v in pairs(realm1) do
				local typeof = type(v)
				if typeof ~= type(realm2[i]) then return false end
				if typeof == "table" then
					if realm_compare(v, realm2[i]) == false then return false end
				else
					if v ~= realm2[i] then return false end
				end
			end
			return true
		else
			return realm1 == realm2
		end
	end
	local function compile(tbl, store, compare_realms, id)
		for i, v in pairs(tbl) do
			if i == "metatables" then
				store[i]["metatables"] = store[i]["metatables"] or {}
				compile(v, store[i]["metatables"], compare_realms)
				continue
			end
			
			if not store[i] then
				store[i] = v
			elseif compare_realms then
				local stored = store[i]
				for key, entry in pairs(v) do
					if key == "members" or not istable(entry) then continue end
					if not stored[key] then stored[key] = entry continue end

					local myRealm, realm2 = next(entry)

					local identical = true
					local realms, realms_n = { [myRealm] = realm2 }, 1
					for realm, realm1 in pairs(stored[key]) do
						realms[realm] = realm1
						realms_n = realms_n + 1
						if not realm_compare(realm1, realm2, i == "CLIENT") then
							identical = false
						end
					end
					
					if identical then
						if realms_n == 3 then
							stored[key] = { SHAREDMENU = realm2 }
						elseif realms_n == 2 then
							if realms.CLIENT ~= nil and realms.SERVER ~= nil then
								stored[key] = { SHARED = realm2 }
							elseif realms.MENU ~= nil and realms.CLIENT ~= nil then
								stored[key] = { CLIENTMENU = realm2 }
							elseif realms.MENU and realms.SERVER then
								MsgC(Color(255, 0, 0), "HOW DID WE GET HERE\n")
								PrintTable(realms)
								error("AAAAAAAAAAAAAAAAAAAAAAAAA")
							else
								stored[key] = realms
							end
						else
							stored[key] = realms
						end
					else
						print("Values differ on realms: ", id..i)
						stored[key][myRealm] = realm2
					end
				end
			else
				for key, val in pairs(v) do
					if key == "members" then continue end
					local realm, val = next(val)
					store[i][key][realm] = val
				end
			end
			if v.members then
				if not store[i].members then store[i].members = v.members end
				compile(v.members, store[i].members, compare_realms, id..i)
			end
		end
	end
	compile(util.JSONToTable(file.Read("gluadump/server.json", "DATA")), compiled, false, "")
	compile(util.JSONToTable(file.Read("gluadump/client.json", "DATA")), compiled, true, "")

	file.Write("gluadump/compiled.json", util.TableToJSON(compiled))]]

	file.Write("gluadump/compiled.json", util.TableToJSON(
		table.Merge(util.JSONToTable(file.Read("gluadump/menu.json", "DATA")),
		table.Merge(util.JSONToTable(file.Read("gluadump/client.json", "DATA")),
		util.JSONToTable(file.Read("gluadump/server.json", "DATA"))
	))))

	MsgC(Color(0, 255, 0) , "gluadump complete\n")
end

end

if CLIENT and not MENU_DLL then
	hook.Add("Think", "gluadump", function()
		if DListView then
			hook.Remove("Think", "gluadump")
			gluadump()
		end
	end)
else
	gluadump()
end
