---@class obsi.keyboard
local keyboard = {}
---@type table<string, number>
keyboard.keys = {}
---@type table<integer, number>
keyboard.scancodes = {}

---@param key string
---@return boolean
function keyboard.isDown(key)
   return keyboard.keys[key] ~= nil
end

---@param scancode integer
---@return boolean
function keyboard.isScancodeDown(scancode)
   return keyboard.scancodes[scancode] ~= nil
end

---Returns true if the user has pressed down the key in this tick, or the specified duration has
---elapsed since pressed (in ticks).
---@param key string
---@param duration number?
---@return boolean
function keyboard.isDownNow(key, duration)
   return keyboard.keys[key] == (duration or 0)
end

---Returns true if the user has pressed down the key in this tick, or the specified duration has
---elapsed since pressed (in ticks).
---@param scancode integer
---@param duration number?
---@return boolean
function keyboard.isScancodeDownNow(scancode, duration)
   return keyboard.scancodes[scancode] == (duration or 0)
end

return keyboard
