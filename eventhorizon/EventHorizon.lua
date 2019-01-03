--[[

	Wow TBC 2.4.3 backport by null
	https://github.com/nullfoxh/

]]

--[[
TODOs
GCD Grid
Drawing order
Options GUI?
--]]
EventHorizon = {}
--e = EventHorizon
EventHorizonDB = {}
local EventHorizon = EventHorizon
EventHorizon.db = EventHorizonDB

local eventhandler
local spellbase = {}
local mainframe

local playerguid

local function printhelp(...) if select('#',...)>0 then return tostring((select(1,...))), printhelp(select(2,...)) end end
local function print(...)
	ChatFrame1:AddMessage(strjoin(',',printhelp(...)))
end

local function UnitDebuffByName(unit, debuff)
	for i = 1, 40 do
		local name, rank, icon, count, type, duration, timeLeft, isMine = UnitDebuff(unit, i)

		if not name then break end

		if name == debuff then
			if duration > 0 and (isMine == nil or isMine == true) then
				return name, rank, icon, count, type, duration, GetTime()+timeLeft
			end
		end
	end
end


function spellbase:NotInteresting(unitid, spellname) 
	return unitid ~= 'player' or spellname ~= self.spellname
end

--[[
Indicators represent a point in time. There are different types. The type determines the color, width and position.
--]]
local styles = {
	tick = {
		texture = {1,1,1,1},
		point1 = {'TOP', 'TOP'},
		point2 = {'BOTTOM', 'TOP', 0, -5},
	},
	start = {
		texture = {0,1,0,1},
	},
	stop = {
		texture = {1,0,0,1},
	},
	casting = {
		texture = {0,1,0,0.3},
	},
	cooldown = {
		texture = {1,1,1,0.3},
	},
	smalldebuff = {
		texture = {1,1,1,0.3},
		point1 = {'TOP', 'TOP', 0, -3},
		point2 = {'BOTTOM', 'TOP', -3, -6},
	},
	cantcast = {
		texture = {1,1,1,0.3},
		point1 = {'TOP', 'TOP', 0, -6},
	},
	debuff = {
		texture = {1,1,1,0.3},
	},
	ready = {
		texture = {1,0,1,1},
	},
	default = {
		texture = {1,1,1,1},
		point1 = {'TOP', 'TOP', 0, -5},
		point2 = {'BOTTOM', 'BOTTOM'},
	}
}
EventHorizon.styles = styles
function spellbase:AddIndicator(typeid, time)
	local indicator
	-- TODO recycling
	if #self.unused>0 then
		indicator = tremove(self.unused)
		indicator:ClearAllPoints()
		indicator.time = nil
		indicator.start = nil
		indicator.stop = nil
	else
		indicator = self:CreateTexture(nil, "BORDER")
	end
	local style = styles[typeid]
	local default = styles.default
	local tex = style and style.texture or default.texture
	local point1 = style and style.point1 or default.point1
	local point2 = style and style.point2 or default.point2
	indicator:SetTexture(unpack(tex))
	local a,c,d,e = unpack(point1)
	indicator:SetPoint(a,self,c,d,e)
	local a,c,d,e = unpack(point2)
	indicator:SetPoint(a,self,c,d,e)

	indicator:Hide()
	indicator:SetWidth(1)
	indicator.time = time
	indicator.typeid = typeid
	if indicator then
		tinsert(self.indicators, indicator)
	end
	return indicator
end

function spellbase:Remove(indicator)
	for k=1,#self.indicators do
		if self.indicators[k]==indicator then
			indicator:Hide()
			tinsert(self.unused, tremove(self.indicators,k))
			break
		end
	end
end

function spellbase:AddSegment(typeid, start, stop)
	local indicator = self:AddIndicator(typeid, start)
	indicator.time = nil
	indicator.start = start
	indicator.stop = stop
	--print(start,stop)
	return indicator
end

local timeunit = 1
local past = -3
local future = 9
local height = 18
local width = 150
local scale = 1/(future-past)
function spellbase:OnUpdate(elapsed)
	local now = GetTime()
	local diff = now+past
	for k=#self.indicators,1,-1 do
		local indicator = self.indicators[k]
		local time = indicator.time
		if time then
			-- Example: 
			-- [-------|------->--------]
			-- past    now     time     future
			-- now=795, time=800, past=-3, then time is time-now-past after past.
			local p = (time-diff)*scale
			if p<0 then
				indicator:Hide()
				tinsert(self.unused, tremove(self.indicators,k))
			elseif p<=1 then
				indicator:SetPoint("LEFT", self, 'LEFT', p*width, 0)
				indicator:Show()
			end
		else
			local start, stop = indicator.start, indicator.stop
			local p1 = (start-diff)*scale
			local p2 = (stop-diff)*scale
			if p2<0 then
				indicator:Hide()
				tinsert(self.unused, tremove(self.indicators,k))
			elseif 1<p1 then
				indicator:Hide()
			else
				indicator:Show()
				indicator:SetPoint("LEFT", self, 'LEFT', 0<=p1 and p1*width or 0, 0)
				indicator:SetPoint("RIGHT", self, 'LEFT', p2<=1 and p2*width+1 or width, 0)
			end
		end
	end
	if self.nexttick and self.nexttick <= now+future then
		if self.nexttick<=self.lasttick then
			self:AddIndicator('tick', self.nexttick)
			self.latesttick = self.nexttick
			self.nexttick = self.nexttick + self.dot
		else
			self.nexttick = nil
		end
	end
end
-- /run e.mf:AddIndicator(GetTime())

function spellbase:OnEvent(event, ...)
	local f = self[event]
	if f then 
		f(self,...) 
	end 
end

function spellbase:UNIT_SPELLCAST_SENT(unitid, spellname, spellrank, spelltarget)
	--print('UNIT_SPELLCAST_SENT',unitid, spellname, spellrank, spelltarget)
	local now = GetTime()
	if self:NotInteresting(unitid, spellname) then return end
	self:AddIndicator('sent', now)
end

function spellbase:UNIT_SPELLCAST_CHANNEL_START(unitid, spellname, spellrank)
	if self:NotInteresting(unitid, spellname) then return end
	local name, nameSubtext, text, texture, startTime, endTime, isTradeSkill = UnitChannelInfo(unitid)
	startTime, endTime = startTime/1000, endTime/1000
	self.casting = self:AddSegment('casting', startTime, endTime)
	--self:AddIndicator('start', startTime)
	--self.stop = self:AddIndicator('stop', endTime)
	if self.numhits then
		local casttime = endTime - startTime
		local tick = casttime/self.numhits
		self.ticks = {}
		for i=1,self.numhits do
			tinsert(self.ticks, self:AddIndicator('tick', startTime + i*tick))
		end
	end
end

function spellbase:UNIT_SPELLCAST_CHANNEL_UPDATE(unitid, spellname, spellrank)
	--print('UNIT_SPELLCAST_CHANNEL_UPDATE',unitid, spellname, spellrank)
	if self:NotInteresting(unitid, spellname) then return end
	local name, nameSubtext, text, texture, startTime, endTime, isTradeSkill = UnitChannelInfo(unitid)
	startTime, endTime = startTime/1000, endTime/1000
	if self.casting then
		self.casting.stop = endTime
	end
	local ticks = self.ticks
	if ticks then
		for i = #ticks,1,-1 do
			local tick = ticks[i]
			if tick.time > endTime then
				tick.time = past-1 -- flag for removal
				self.ticks[i] = nil
			end
		end
	end
end

function spellbase:UNIT_SPELLCAST_CHANNEL_STOP(unitid, spellname, spellrank)
	local now = GetTime()
	if self:NotInteresting(unitid, spellname) then return end
	if self.casting then
		self.casting.stop = now
		self.casting = nil
	end
	local ticks = self.ticks
	if ticks then
		for i = #ticks,1,-1 do
			local tick = ticks[i]
			if tick.time > now then
				tick.time = past-1 -- flag for removal
				self.ticks[i] = nil
			end
		end
		self.ticks = nil
	end
end

function spellbase:UNIT_SPELLCAST_START(unitid, spellname, spellrank, target)
	if self:NotInteresting(unitid, spellname) then return end
	local name, nameSubtext, text, texture, startTime, endTime, isTradeSkill = UnitCastingInfo(unitid)
	startTime, endTime = startTime/1000, endTime/1000
	self.casting = self:AddSegment('casting', startTime, endTime)
end

function spellbase:UNIT_SPELLCAST_STOP(unitid, spellname, spellrank)
	local now = GetTime()
	if self:NotInteresting(unitid, spellname) then return end
	if self.casting then
		self.casting.stop = now
		self.casting = nil
	end
end

function spellbase:UNIT_SPELLCAST_DELAYED(unitid, spellname, spellrank)
	--print('UNIT_SPELLCAST_CHANNEL_UPDATE',unitid, spellname, spellrank)
	if self:NotInteresting(unitid, spellname) then return end
	local name, nameSubtext, text, texture, startTime, endTime, isTradeSkill = UnitCastingInfo(unitid)
	startTime, endTime = startTime/1000, endTime/1000
	if self.casting and self.stop then
		self.stop.time = endTime
	end
end

function spellbase:UNIT_SPELLCAST_SUCCEEDED(unitid, spellname, spellrank)
	if self:NotInteresting(unitid, spellname) then return end
	self.succeeded = GetTime()
end

function spellbase:UNIT_AURA(unitid)
	if unitid~='target' then return end

	local name, rank, icon, count, debuffType, duration, expirationTime = UnitDebuffByName(unitid, self.spellname)
	local afflictedNow = name
	local addnew
	local now = GetTime()
	local start
	if afflictedNow then
		start = expirationTime-duration
		if self.debuff then
			if expirationTime~=self.debuff.stop then
				-- The debuff was replaced.
				self.debuff.stop = start-0.2
				for i = #self.indicators,1,-1 do
					local ind = self.indicators[i]
					if ind.typeid == 'tick' and ind.time>start then
						self:Remove(ind)
					end
				end
				self.nexttick = nil
				addnew = true
			end
		else
			addnew = true
		end
	else
		if self.debuff then
			if math.abs(self.debuff.stop - now)>0.3 then
				self.debuff.stop = now
				for i = #self.indicators,1,-1 do
					local ind = self.indicators[i]
					if ind.typeid == 'tick' and ind.time>now then
						self:Remove(ind)
					end
				end
			end
			self.debuff = nil
			self.nexttick = nil
		end
	end
	if addnew then
		if self.cast then
			self.debuff = self:AddSegment('smalldebuff', start, expirationTime)
			local casttime = select(7, GetSpellInfo(self.spellname))/1000
			self.cooldown = self:AddSegment('cantcast', start, expirationTime-casttime)
		else
			self.debuff = self:AddSegment('debuff', start, expirationTime)
		end
		if self.dot then
			local nexttick = start+self.dot
			self.nexttick = nil
			while nexttick<=expirationTime do
				if now+future<nexttick then
					self.nexttick = nexttick
					self.lasttick = expirationTime
					break
				end
				if now+past<=nexttick then
					self:AddIndicator('tick', nexttick)
					self.latesttick = nexttick
				end
				nexttick=nexttick+self.dot
			end
		end
	end
end

function spellbase:PLAYER_TARGET_CHANGED()
	if self.debuff then
		for i = #self.indicators,1,-1 do
			local ind = self.indicators[i]
			if ind.typeid == 'tick' or ind.typeid == 'cantcast' or ind.typeid == 'debuff' or ind.typeid == 'smalldebuff' then
				self:Remove(ind)
			end
		end
		self.debuff = nil
		self.nexttick = nil
	end

	if UnitExists('target') then
		self:UNIT_AURA('target')
	end
end

--[[
Refreshable debuffs are really ugly, because UnitDebuff won't tell us when the debuff was applied.
It gets complicated because a debuff might be [re]applied/refreshed when we're not looking.
Here's what can happen, and which point of time we have to assume as the start.
success applied -> applied
success applied refresh -> applied
applied success -> success
applied success refresh -> success
applied -> applied
applied refresh -> applied

So we need to keep track of every debuff currently applied, and the success events. 
When the target or debuff changes, we need to look at the time of the last success to see if we can trust UnitDebuff.
--]]
function spellbase:COMBAT_LOG_EVENT_UNFILTERED(time, event, srcguid,srcname,srcflags, destguid,destname,destflags, spellid,spellname)
	if srcguid~=playerguid or event:sub(1,5) ~= 'SPELL' or spellname~=self.spellname then return end
	local now = GetTime()
	if event == 'SPELL_CAST_SUCCESS' then
		--print('SPELL_CAST_SUCCESS',destguid)
		self.castsuccess[destguid] = now
	end
end

function spellbase:UNIT_AURA_refreshable(unitid)
	if unitid~='target' then return end
	local name, rank, icon, count, debuffType, duration, expirationTime = UnitDebuffByName(unitid, self.spellname)
	local afflicted = name
	local addnew, refresh
	local now = GetTime()
	local start
	local guid = UnitGUID('target')
	-- First find out if the debuff was refreshed.
	if afflicted then
		start = expirationTime-duration
		if self.targetdebuff then
			if self.targetdebuff.stop ~= expirationTime then
				local s=self.castsuccess[guid]
				if s then
					local diff = math.abs(s-start)
					--print('diff', diff)
					if diff>0.5 then
						-- The current debuff was refreshed.
						start = self.targetdebuff.start
						refresh = true
					end
				end
			else
				start = self.targetdebuff.start
			end
		end
		if self.debuff then
			if expirationTime~=self.debuff.stop and not refresh then
				-- The current debuff was replaced.
				self.debuff.stop = start-0.2
				for i = #self.indicators,1,-1 do
					local ind = self.indicators[i]
					if ind.typeid == 'tick' and ind.time>start then
						self:Remove(ind)
					end
				end
				self.nexttick = nil

				--print('replaced')
				addnew = true
			end
		else
			addnew = true
		end
	else
		if self.debuff then
			if math.abs(self.debuff.stop - now)>0.3 then
				-- The current debuff ended.
				self.debuff.stop = now
			end
			self.debuff = nil
		end
	end
	local addticks
	if addnew then
		--print('addnew', start, expirationTime)
		self.debuff = self:AddSegment('debuff', start, expirationTime)
		-- Add visible ticks.
		if self.dot then
			addticks = start
		end
		self.targetdebuff = {start=start, stop=expirationTime}
		self.debuffs[guid] = self.targetdebuff
	elseif refresh then
		--print('refresh', start, expirationTime)
		-- Note: refresh requires afflicted and self.targetdebuff. Also, afflicted and not self.debuff implies addnew.
		-- So we can get here only if afflicted and self.debuff and self.targetdebuff.
		self.debuff.stop = expirationTime
		self.targetdebuff.stop = expirationTime
		if self.latesttick then
			addticks = self.latesttick
		end
	end
	if addticks then
		local nexttick = addticks+self.dot
		self.nexttick = nil
		while nexttick<=expirationTime do
			if now+future<nexttick then
				self.nexttick = nexttick
				self.lasttick = expirationTime
				break
			end
			if now+past<=nexttick then
				self:AddIndicator('tick', nexttick)
				self.latesttick = nexttick
			end
			nexttick=nexttick+self.dot
		end
	end
end

function spellbase:PLAYER_TARGET_CHANGED_refreshable()
	if self.debuff then
		--print('removing old')
		for i = #self.indicators,1,-1 do
			local ind = self.indicators[i]
			if ind.typeid == 'tick' or ind.typeid == 'ready' or ind.typeid == 'debuff' then
				self:Remove(ind)
			end
		end
		self.debuff = nil
		self.targetdebuff = nil
		self.nexttick = nil
	end

	if UnitExists('target') then
		self.targetdebuff = self.debuffs[UnitGUID('target')]
		if self.targetdebuff then
			--print('have old')
		end
		self:UNIT_AURA('target')
	end
end

function spellbase:SPELL_UPDATE_COOLDOWN()
	local start, duration, enabled = GetSpellCooldown(self.spellname)
	if enabled==1 and start~=0 and duration and duration>1.5 then
		local ready = start + duration
		if self.cooldown ~= ready then
			self.coolingdown = self:AddSegment('cooldown', start, ready) 
			--self.ready = self:AddIndicator('ready', ready)
			self.cooldown = ready
		end
	else
		if self.coolingdown then
			self.coolingdown = nil
		end
		self.cooldown = nil
	end
end

--[[
spellid: number, rank doesn't matter
abbrev: string
config: table
{
	cast = <cast time in s>,
	channeled = <channel time in s>,
	numhits = <number of hits per channel>,
	cooldown = <boolean>,
	debuff = <duration in s>,
	dot = <tick interval in s, requires debuff>,
	refreshable = <boolean>,
}
--]]
function EventHorizon:NewSpell(spellid, abbrev, config)
	-- TODO check spellbook
	local spellframe = CreateFrame("Frame", nil, mainframe)
	self[abbrev] = spellframe
	mainframe.numframes = mainframe.numframes+1
	mainframe:SetHeight(mainframe.numframes * height)

	local spellname, rank, tex = GetSpellInfo(spellid)
	spellframe.spellname = spellname

	spellframe.indicators = {}
	spellframe.unused = {}
	spellframe:SetPoint("TOPLEFT", mainframe, "TOPLEFT", 0, -(mainframe.numframes-1) * height)
	spellframe:SetWidth(width)
	spellframe:SetHeight(height)
	spellframe:SetBackdrop{bgFile = [[Interface\Addons\EventHorizon\Smooth]]} -- TODO
	spellframe:SetBackdropColor(1,1,1,0.1)

	local icon = spellframe:CreateTexture(nil, "BORDER")
	icon:SetTexture(tex)
	icon:SetPoint("TOPRIGHT", spellframe, "TOPLEFT")
	icon:SetWidth(height)
	icon:SetHeight(height)

	local meta = getmetatable(spellframe)
	if meta and meta.__index then
		local metaindex = meta.__index
		setmetatable(spellframe, {__index = 
		function(self,k) 
			if spellbase[k] then 
				self[k]=spellbase[k] 
				return spellbase[k] 
			end 
			return metaindex[k] 
		end})
	else
		setmetatable(spellframe, {__index = spellbase})
	end
	spellframe:RegisterEvent("UNIT_SPELLCAST_SENT")
	if config.channeled then
		spellframe:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
		spellframe:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
		spellframe:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
		spellframe.numhits = config.numhits
	elseif config.cast then
		spellframe.cast = config.cast
		spellframe:RegisterEvent("UNIT_SPELLCAST_START")
		spellframe:RegisterEvent("UNIT_SPELLCAST_STOP")
		spellframe:RegisterEvent("UNIT_SPELLCAST_DELAYED")
	end
	if config.cooldown then
		spellframe:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	end

	if config.debuff then
		spellframe:RegisterEvent("UNIT_AURA")
		spellframe:RegisterEvent("PLAYER_TARGET_CHANGED")
		if config.dot then
			spellframe.dot = config.dot
			if config.refreshable then
				spellframe.UNIT_AURA = spellbase.UNIT_AURA_refreshable
				spellframe.PLAYER_TARGET_CHANGED = spellbase.PLAYER_TARGET_CHANGED_refreshable
				spellframe:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
				spellframe.debuffs = {}
				spellframe.castsuccess = {}
			end
		end
	end
	
	spellframe:SetScript("OnEvent", spellframe.OnEvent)
	spellframe:SetScript("OnUpdate", spellframe.OnUpdate)
end

--[[
Should only be called after the DB is loaded and spell information is available.
--]]
function EventHorizon:Initialize()
	--if not select(2,UnitClass("player"))== then return end
	local class = select(2,UnitClass("player"))
	playerguid = UnitGUID('player')
	if not playerguid then
		error('no playerguid')
	end
	EventHorizon.db = EventHorizonDB

	-- Create the main and spell frames.
	mainframe = CreateFrame("Frame",nil,UIParent)
	mainframe:SetWidth(width)
	mainframe:SetHeight(1)
	mainframe.numframes = 0
	if class == "PRIEST" then
			self:NewSpell(34917, 'vt', {
			cast = 1.5,
			debuff = 15,
			dot = 3,
		})
		
		self:NewSpell(10892, 'swp', {
			debuff = 18,
			dot = 3,
			refreshable = true,
		})
		

		self:NewSpell(25387, 'mf', {
			channeled = 3,
			numhits = 3,
		})
		
		self:NewSpell(8092, 'mb', {
			cast = 1.5,
			cooldown = 5.5,-- TODO check talents?
		})


	elseif class == "WARLOCK" then 
		self:NewSpell(27217, 'mf', {
			channeled = 15,
			numhits = 5,
		})
		self:NewSpell(686, 'sb', {
			cast = 2.2,
		})
		self:NewSpell(172, 'cor', {
			debuff = 12,
			dot = 3,
			refreshable = true,
		})
		self:NewSpell(348, 'fb', {
			debuff = 15,
			dot = 3,
			cast = 2,
		})
		self:NewSpell(5782, 'fear', {
			cast = 1.5,
			debuff = 10,
		})
		self:NewSpell(50511, 'cow', {
			debuff = 120,
		})
	else
		return
	end

	local nowIndicator = mainframe:CreateTexture(nil, 'BORDER')
	nowIndicator:SetPoint('BOTTOM',mainframe,'BOTTOM')
	nowIndicator:SetPoint('TOPLEFT',mainframe,'TOPLEFT', -past/(future-past)*width, 0)
	nowIndicator:SetWidth(1)
	nowIndicator:SetTexture(1,1,1,1)

	local handle = CreateFrame("Frame", "EventHorizonHandle", UIParent)
	mainframe:SetPoint("TOPRIGHT", handle, "BOTTOMRIGHT")
	self.handle = handle
	handle:SetPoint("CENTER")
	handle:SetWidth(10)
	handle:SetHeight(5)
	handle:EnableMouse(true)
	handle:SetMovable(true)
	handle:RegisterForDrag("LeftButton")
	handle:SetScript("OnDragStart", function(self, button) self:StartMoving() end)
	handle:SetScript("OnDragStop", function(frame) 
		frame:StopMovingOrSizing() 
		local a,b,c,d,e = frame:GetPoint(1)
		if type(b)=='frame' then
			b=b:GetName()
		end
		self.db.point = {a,b,c,d,e}
	end)
	if self.db.point then
		handle:SetPoint(unpack(self.db.point))
	end
	
	handle.tex = handle:CreateTexture(nil, "BORDER")
	handle.tex:SetAllPoints()
	handle:SetScript("OnEnter",function(frame) frame.tex:SetTexture(1,1,1,1) end)
	handle:SetScript("OnLeave",function(frame) frame.tex:SetTexture(1,1,1,0.1) end)
	handle.tex:SetTexture(1,1,1,0.1)
	-- Register slash commands. TODO
	
end

do
	local frame = CreateFrame("Frame")
	frame:SetScript("OnEvent", function(frame, event, ...) if frame[event] then frame[event](frame,...) end end)
	frame:RegisterEvent("PLAYER_LOGIN")
	function frame:PLAYER_LOGIN()
		EventHorizon:Initialize()
	end
end
