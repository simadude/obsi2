local gamePath = fs.getDir(shell.getRunningProgram())

---@class obsi
local obsi = {}

---@class obsi.Config
---@field maxfps number
---@field mintps number
---@field multiUpdate boolean
---@field renderingAPI obsi.RenderingName
---@field sleepOption 1|2
local config = {
	maxfps = 20,
	mintps = 60,
	multiUpdate = true,
	renderingAPI = "pixelbox",
	sleepOption = 1
}

local canvas
local winh
---@type fun(), fun(), fun(), fun(), fun()
local soundLoop, mouseDown, mouseMove, mouseUp, setFps
local emptyFunc = function(...) end
---@type fun()
local fsInit
obsi.fs, fsInit = require("obsi2.fs")(gamePath)
obsi.system = require("obsi2.system")
if obsi.system.getClockSpeed() == 20 then
	config.sleepOption = 2
end
---@type obsi.graphics, obsi.InternalCanvas, Window
obsi.graphics, canvas, winh = require("obsi2.graphics")(obsi.fs, config.renderingAPI)
obsi.timer, setFps = require("obsi2.timer")()
obsi.keyboard = require("obsi2.keyboard")
obsi.mouse, mouseDown, mouseUp, mouseMove = require("obsi2.mouse")()
obsi.audio, soundLoop = require("obsi2.audio")(obsi.fs)
obsi.state = require("obsi2.state")
obsi.debug = false
obsi.version = "2.0.1"

obsi.load = emptyFunc
---@type fun(dt: number)
obsi.update = emptyFunc
---@type fun(dt: number)
obsi.draw = emptyFunc
---@type fun(x: number, y: number, button: integer)
obsi.onMousePress = emptyFunc
---@type fun(x: number, y: number, button: integer)
obsi.onMouseRelease = emptyFunc
---@type fun(x: number, y: number)
obsi.onMouseMove = emptyFunc
---@type fun(key: integer)
obsi.onKeyPress = emptyFunc
---@type fun(key: integer)
obsi.onKeyRelease = emptyFunc
---@type fun(wind: Window)
obsi.onWindowFlush = emptyFunc -- sends a window object as a first argument, which you can mutate if you wish.
---@type fun(w: integer, h: integer)
obsi.onResize = emptyFunc	-- sends width and height of the window in characters, not pixels. 
---@type fun(eventData: table)
obsi.onEvent = emptyFunc -- for any events that aren't caught! Runs last so that you won't mutate it.
---@type fun()
obsi.onQuit = emptyFunc -- called when Obsi recieves "terminate" event.

local quit = false
function obsi.quit()
	quit = true
end

local function clock()
	return periphemu and os.epoch(("nano")--[[@as "local"]])/10^9 or os.clock()
end

---@param time number
local function sleepRaw(time)
	local timerID = os.startTimer(time)
	while true do
		local _, tID = os.pullEventRaw("timer")
		if tID == timerID then
			break
		end
	end
end

local t = clock()
local dt = 1/config.maxfps

local drawTime = t
local updateTime = t
local frameTime = t
local lastSecond = t
local frames = 0

fsInit() -- use game's path

local function gameLoop()
	obsi.load()
	while true do
		local startTime = clock()
		if config.multiUpdate then
			local updated = false
			for _ = 1, dt/(1/config.mintps) do
				obsi.update(1/config.mintps)
				updated = true
			end
			if not updated then
				obsi.update(dt)
			end
		else
			obsi.update(dt)
		end
		updateTime = clock() - startTime
		obsi.draw(dt)
		drawTime = clock() - updateTime - startTime
		obsi.graphics.setCanvas()
		soundLoop(dt)
		if obsi.debug then
			local bg, fg = obsi.graphics.bgColor, obsi.graphics.fgColor
			obsi.graphics.bgColor, obsi.graphics.fgColor = colors.black, colors.white
			obsi.graphics.write("Obsi "..obsi.version, 1, 1)
			obsi.graphics.write(obsi.system.getHost(), 1, 2)
			obsi.graphics.write(("rendering: %s [%sx%s -> %sx%s]"):format(obsi.graphics.getRenderer(), obsi.graphics.getWidth(), obsi.graphics.getHeight(), obsi.graphics.getPixelSize()), 1, 3)
			obsi.graphics.write(("%s FPS"):format(obsi.timer.getFPS()), 1, 4)
			obsi.graphics.write(("%0.2fms update"):format(updateTime*1000), 1, 5)
			obsi.graphics.write(("%0.2fms draw"):format(drawTime*1000), 1, 6)
			obsi.graphics.write(("%0.2fms frame"):format(frameTime*1000), 1, 7)
			obsi.graphics.bgColor, obsi.graphics.fgColor = bg, fg
		end
		-- obsi.debugger.print(("%0.2fms frame [%sx%s]"):format(frameTime*1000, obsi.graphics.getPixelSize()))
		obsi.graphics.flushAll()
		obsi.onWindowFlush(winh)
		obsi.graphics.show()
		if clock() > lastSecond+1 then
			lastSecond = clock()
			setFps(frames/1)
			frames = 0
		else
			frames = frames + 1
		end
		frameTime = clock() - startTime
		if config.sleepOption == 1 then
			if frameTime > 1/config.maxfps then
				sleepRaw(0)
			else
				sleepRaw((1/config.maxfps-frameTime)/1.1)
			end
		else
			sleepRaw(0)
		end
		obsi.graphics.clear()
		obsi.graphics.bgColor, obsi.graphics.fgColor = colors.black, colors.white
		obsi.graphics.resetOrigin()
		dt = clock()-t
		t = clock()
	end
end

local function eventLoop()
	while true do
		local eventData = {os.pullEventRaw()}
		if eventData[1] == "mouse_click" then
			mouseDown(eventData[3], eventData[4], eventData[2])
			obsi.onMousePress(eventData[3], eventData[4], eventData[2])
		elseif eventData[1] == "mouse_up" then
			mouseUp(eventData[3], eventData[4], eventData[2])
			obsi.onMouseRelease(eventData[3], eventData[4], eventData[2])
		elseif eventData[1] == "mouse_move" then -- apparently the second index is only there for compatibility? Alright.
			mouseMove(eventData[3], eventData[4])
			obsi.onMouseMove(eventData[3], eventData[4])
		elseif eventData[1] == "mouse_drag" then
			mouseMove(eventData[3], eventData[4])
			obsi.onMouseMove(eventData[3], eventData[4])
		elseif eventData[1] == "term_resize" or eventData[1] == "monitor_resize" then
			local w, h = term.getSize()
			winh.reposition(1, 1, w, h)
			canvas:resize(w, h)
			obsi.graphics.pixelWidth, obsi.graphics.pixelHeight = canvas.width, canvas.height
			obsi.graphics.width, obsi.graphics.height = w, h
			obsi.onResize(w, h)
		elseif eventData[1] == "key" and not eventData[3] then
			obsi.keyboard.keys[keys.getName(eventData[2])] = true
			obsi.keyboard.scancodes[eventData[2]] = true
			obsi.onKeyPress(eventData[2])

			-- --the code below is only for testing!

			-- if eventData[2] == keys.l then
			-- 	local rentab = {
			-- 		["pixelbox"] = "neat",
			-- 		["neat"] = "basic",
			-- 		["basic"] = "pixelbox",
			-- 	}
			-- 	obsi.graphics.setRenderer(rentab[obsi.graphics.getRenderer()] or "neat")
			-- elseif eventData[2] == keys.p then
			-- 	obsi.debug = not obsi.debug
			-- end
		elseif eventData[1] == "key_up" then
			obsi.keyboard.keys[keys.getName(eventData[2])] = false
			obsi.keyboard.scancodes[eventData[2]] = false
			obsi.onKeyRelease(eventData[2])
		elseif eventData[1] == "terminate" or quit then
			obsi.onQuit()
			obsi.graphics.clearPalette()
			term.setBackgroundColor(colors.black)
			term.clear()
			term.setCursorPos(1, 1)
			return
		end
		obsi.onEvent(eventData)
	end
end

local function catch(err)
	obsi.graphics.clearPalette()
	term.setBackgroundColor(colors.black)
	term.clear()
	term.setCursorPos(1, 1)
	os.pullEvent()
	printError(debug.traceback(err, 2))
	-- if obsi.debugger then
	-- 	obsi.debugger.print(debug.traceback(err, 2))
	-- end
end

function obsi.init()
	parallel.waitForAny(function() xpcall(gameLoop, catch) end, function() xpcall(eventLoop, catch) end)
end

return obsi
