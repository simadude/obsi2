---@class obsi.timer
local timer = {}
local initTime = os.clock()
local fps = 0

---@param n integer
local function setFPS(n)
	fps = n
end

---@return number # Time in seconds since the initialization of `timer` module.
function timer.getTime()
	return os.clock() - initTime
end

---@return integer # Returns how many Frames have been drawn since last second.
function timer.getFPS()
	return fps
end

return function() return timer, setFPS end