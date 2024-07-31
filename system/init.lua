---@class obsi.system
local system = {}
local isAdvanced
local isEmulated
local host = _HOST:match("%(.-%)"):sub(2, -2)
local ver = _HOST:sub(15, 21)

if _HOST:lower():match("minecraft") then
	isEmulated = false
else
	isEmulated = true
end

do
	local programs = shell.programs()
	for i = 1, #programs do
		if programs[i] == "multishell" then
			isAdvanced = true
		end
	end
end

function system.isAdvanced()
	return isAdvanced
end

function system.isEmulated()
	return isEmulated
end

function system.getHost()
	return host
end

function system.getVersion()
	return ver
end

function system.getClockSpeed()
	if config then
		return config.get("clockSpeed")
	end
	return 20
end

return system