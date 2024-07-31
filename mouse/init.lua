---@class obsi.mouse
local mouse = {}
local buttons = {}
local mx, my = 0, 0

---Returns the position of the mouse on X axis. 
---@return integer
function mouse.getX()
	return mx
end

---Returns the position of the mouse on Y axis.
---@return integer
function mouse.getY()
	return my
end

---Returns the position of the mouse.
---@return integer, integer
function mouse.getPosition()
	return mx, my
end

---Returns either true or false if "mouse_move" event can fire on CraftOS-PC.
---@return boolean
function mouse.canMove()
	return not not (config and (config.get("mouse_move_throttle") >= 0))
end

---Returns if true or false if the mouse button is down.
---@param button integer
function mouse.isDown(button)
	return buttons[button] or false
end

---@param qx integer
---@param qy integer
---@param b integer
local function setMouseDown(qx, qy, b)
	mx, my = qx, qy
	buttons[b] = true
end

---@param qx integer
---@param qy integer
---@param b integer
local function setMouseUp(qx, qy, b)
	mx, my = qx, qy
	buttons[b] = false
end

---@param qx integer
---@param qy integer
local function setMousePos(qx, qy)
	mx, my = qx or mx, qy or my
end

return function ()
	return mouse, setMouseDown, setMouseUp, setMousePos
end