-- Testing stuff
-- require "c4d_test"

local Color = {}
	Color.leds_number = 10
	Color.leds = Ledbar.new(Color.leds_number)
	Color.colors = {	red = 		{1, 0, 0},
						green = 	{0, 1, 0},
						blue = 		{0, 0, 1},
						purple = 	{0.5, 0, 0.5},
						cyan = 		{0, 0.5, 0.5},
						yellow = 	{0.5, 0.5, 0},
						white = 	{0.33, 0.33, 0.33},
						black = 	{0, 0, 0}
					}

function Color.setAllLEDs(r, g, b)
	for i = 0, (Color.leds_number - 1), 1 do
		Color.leds:set(i, r, g, b)
	end
end

function Color.setInfoLEDs(r, g, b)
	for i = 0, 3, 1 do
		Color.leds:set(i, r, g, b)
	end
end

local Position = {}
	Position.setPosition = ap.goToLocalPoint

local function getGlobalTime()
	return time() + deltaTime()
end

local tblUnpack = table.unpack

local Animation = {}
function Animation.new()

	local state = {stop = 0, idle = 1, flight = 2, landing = 3, test = 4}
	
	local obj = {}
		obj.state = state.stop
		obj.armed = false
		obj.global_time_0 = 0
		obj.t_init = NandLua.readTimeStart()
		obj.period_position = 1/NandLua.readFreqPositions()
		obj.period_color = 1/NandLua.readFreqColors()
		obj.number_positions = NandLua.readNumberPositions()
		obj.number_colors = NandLua.readNumberColors()
		obj.origin_lat, obj.origin_lon, obj.origin_alt = NandLua.readPositionOrigin()
		obj.origin_rotation = NandLua.readChunk(30, 4) -- 30 - offset, 4 - size

	local Config = {}

	function obj:setConfig(cfg)
		Config.init_index = cfg.init_index or 0
		Config.t_after_syncstart = cfg.time_ater_syncstart or 0.1
		Config.t_after_prepare = cfg.time_after_prepare or 5
		Config.t_after_takeoff = cfg.time_after_takeoff or 5
		Config.t_leds_after_fail = cfg.time_leds_after_fail or 30
		Config.lat = cfg.lat or self.origin_lat
		Config.lon = cfg.lon or self.origin_lon
		Config.alt = cfg.alt or self.origin_alt
		Config.rot = cfg.rot or self.origin_rotation
		if Config.lat ~= nil and Config.lon ~= nil and Config.alt ~= nil then
			ap.setGpsOrigin(Config.lat, Config.lon, Config.alt, Config.rot)
		end
		Config.light_onlanding = cfg.light_onlanding or false
		Config.edge_marker = cfg.edge_marker or false
	end

	function obj:eventHandler(e)
		if self.state ~= state.stop then
			if (e == Ev.CONTROL_FAIL or e == Ev.ENGINE_FAIL or e == Ev.SHOCK or e == Ev.COPTER_DISARMED or e == Ev.LOW_VOLTAGE2) then
				self.state = state.stop
				Color.setAllLEDs(tblUnpack(Color.colors.black))
				Timer.callLater(Config.t_leds_after_fail, function () Color.setInfoLEDs(tblUnpack(Color.colors.yellow)) end)
			end

			if e == Ev.ENGINES_STARTED and self.state == state.flight then
				self.armed = true
			end

			if Config.edge_marker then -- Takeoff and flight of corner drones for mark edges of start formation
				if e == Ev.SYNC_START and self.state == state.idle then
					Color.setInfoLEDs(tblUnpack(Color.colors.blue))
					self:startEdgeMarker()
				end
				if e == Ev.POINT_REACHED then
					sleep(10) -- For better RTK positioning
					ap.push(Ev.MCE_LANDING)
				end
			else
				if e == Ev.SYNC_START and self.state == state.idle then
					local t = Config.t_after_prepare + Config.t_after_takeoff
					self.global_time_0 = getGlobalTime() + self.t_init + t + Config.t_after_syncstart
					Color.setInfoLEDs(tblUnpack(Color.colors.blue))
					Timer.callAtGlobal(self.global_time_0 - t, function () self:animInit() end)
					logEnable(true)
					Timer.callLater(10 + self.t_init + Config.t_after_takeoff, function () if self.armed == false then logEnable(false) end end)
				end
			end
		end
	end

	function obj:animInit()
		self.state = state.flight
		ap.push(Ev.MCE_PREFLIGHT) 
		sleep(Config.t_after_prepare)
		Color.setInfoLEDs(tblUnpack(Color.colors.black))
		ap.push(Ev.MCE_TAKEOFF) -- Takeoff altitude should be set by AP parameter
		Timer.callAtGlobal(self.global_time_0, function () self:positionLoop(Config.init_index) end)
		Timer.callAtGlobal(self.global_time_0, function () self:colorLoop(Config.init_index) end)
	end

	function obj:positionLoop(point_index)
		local t = (point_index + 1) * self.period_position
		if self.state == state.flight and point_index < self.number_positions then
			Position.setPosition(NandLua.readPosition(point_index))
			Timer.callAtGlobal(self.global_time_0 + t, function () self:positionLoop(point_index + 1) end)
		elseif self.state == state.flight then
			local delay = 1
			Timer.callAtGlobal(self.global_time_0 + t + delay, function () self:landing() end)
		end
	end

	function obj:colorLoop(color_index)
		if self.state == state.flight and color_index < self.number_colors then
			local t = (color_index + 1) * self.period_color
			Color.setAllLEDs(NandLua.readColor(color_index))
			Timer.callAtGlobal(self.global_time_0 + t, function () self:colorLoop(color_index + 1) end)
		end
	end
	
	function obj:landing()
		if Config.light_onlanding == false then
			Color.setAllLEDs(tblUnpack(Color.colors.black))
			Color.setInfoLEDs(tblUnpack(Color.colors.purple))
		end
		self.state = state.landing
		ap.push(Ev.MCE_LANDING)
	end

	function obj:waitStartLoop()
		local _,_,_,_,_,ch6,_,ch8 = Sensors.rc() -- TODO fix channel 6
		if ch6 < 1 and ch8 > 0 then 
			local t = getGlobalTime()
			local leap_second = 19
			local t_period = 15 -- Time window
			local t_near = leap_second + t_period*(math.floor((t - leap_second)/t_period) + 1)
			Color.setInfoLEDs(tblUnpack(Color.colors.green))
			Timer.callAtGlobal(t_near, function () self:eventHandler(Ev.SYNC_START) end)
		else
			if self.state == state.idle then
				Timer.callLater(0.2, function () self:waitStartLoop() end)
			end
		end
	end

	function obj:spin()
		self.state = state.idle
		start_color = NandLua.readAnimationId() * 360 / 255 -- Convert from int format to hue
		Color.setInfoLEDs(fromHSV(start_color, 100, 100))
		self:waitStartLoop()
		-- self:startTest() -- For debugging
	end

	function obj:startEdgeMarker()
		ap.push(Ev.MCE_PREFLIGHT)
		sleep(Config.t_after_prepare)
		Color.setAllLEDs(tblUnpack(Color.colors.green))
		ap.push(Ev.MCE_TAKEOFF)
		sleep(Config.t_after_takeoff)
		Color.setAllLEDs(tblUnpack(Color.colors.red))
		Position.setPosition(NandLua.readPosition(Config.init_index))
	end

	function obj:startTest()
		self:eventHandler(Ev.SYNC_START)
	end

	Animation.__index = Animation 
	return setmetatable(obj, Animation)
end

function callback(event)
	anim:eventHandler(event)
end

local cfg = {}
	cfg.time_ater_syncstart = 0.1
	cfg.time_after_prepare = 10
	cfg.time_after_takeoff = 5
	cfg.light_onlanding = false
	cfg.edge_marker = false

if NandLua.checkFile() then
	anim = Animation.new()
	anim:setConfig(cfg)
	anim:spin()
else
	Color.setAllLEDs(tblUnpack(Color.colors.black))
	Color.setInfoLEDs(tblUnpack(Color.colors.yellow))
end