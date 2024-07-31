---@class obsi.fs
local obsifs = {}
local useGamePath = false
local gamePath = ""
local fs = vfs or fs

---@param path string
---@return string
local function getPath(path)
	-- if useGamePath then
	-- 	local s = fs.combine(gamePath, path):reverse():sub(-#gamePath):reverse()
	-- 	if s ~= gamePath then
	-- 		return nil, ("Attempt to get outside of the game's directory: %s"):format(s)
	-- 	end
	-- end
	return useGamePath and fs.combine(gamePath, path) or path
end

---@param dirPath any
---@return boolean, string?
function obsifs.createDirectory(dirPath)
	local dp, e = getPath(dirPath)
	if not dp then
		return false, e
	end
	local suc = pcall(fs.makeDir, dp)
	return suc
end

---@param dirPath any
---@return table|nil, string?
function obsifs.getDirectoryItems(dirPath)
	local dp, e = getPath(dirPath)
	if not dp then
		return nil, e
	end
	local suc, res = pcall(fs.list, dp)
	return suc and res or {}
end

---Creates a new obsi.File object. Does not necessarily create a new file. Needs to be opened manually for writing.
---@param filePath string
---@param fileMode? fileMode
---@return obsi.File?, string?
function obsifs.newFile(filePath, fileMode)
	local fp, e = getPath(filePath)
	if not fp then
		return nil, e
	end
	fileMode = fileMode or "c"

	---@class obsi.File
	local file = {}

	file.path = fp
	file.name = fs.getName(filePath)

	---@alias fileMode "c"|"r"|"w"|"a"
	---@type fileMode
	file.mode = fileMode

	---@param mode fileMode
	function file:open(mode)
		if mode == "c" then
			return
		end
		local f, e = fs.open(self.path, mode and mode.."b")
		if not f then
			return false, e
		end
		self.file = f
		return true
	end

	if fileMode ~= "c" then
		local b, e = file:open(fileMode)
		if not b then
			return nil, e
		end
	end

	function file:getMode()
		return self.mode
	end

	function file:write(data, size)
		if self.file and (self.mode == "w" or self.mode == "a") then
			size = size or #data
			self.file.write(data:sub(size))
			return true
		else
			return false, "File is not opened for writing"
		end
	end

	function file:flush()
		if self.mode == "w" and self.file then
			self.file.flush()
			return true
		else
			return false, "File is not opened for writing"
		end
	end

	function file:read(count)
		if not self.file then
			local _, r = self:open("r")
			if r then
				return nil, r
			end
		elseif self.mode ~= "r" then
			return nil, "File is not opened for reading"
		end
		return count and self.file.read(count) or self.file.readAll()
	end

	function file:lines()
		if not self.file then
			local _, r = self:open("r")
			if r then
				error(r)
			end
		elseif self.mode ~= "r" then
			return nil, "File is not opened for reading"
		end
		return function ()
			return self.file.readLine(false)
		end
	end

	function file:seek(pos)
		if self.file then
			self.file.seek("set", pos)
		end
	end

	function file:tell()
		if self.file then
			return self.file.seek("cur", 0)
		end
	end

	function file:close()
		if self.file then
			self.file.close()
		end
		self.file = nil
		self.mode = "c"
	end

	return file
end

---@class obsi.FileInfo
---@field type "directory"|"file"
---@field size number
---@field modtime number
---@field createtime number
---@field readonly boolean

---@param filePath string
---@return obsi.FileInfo?
function obsifs.getInfo(filePath)
	filePath = getPath(filePath)
	local e, info = pcall(fs.attributes, filePath)
	if not info then
		return nil
	end
	return {
		type = (info.isDir and "directory" or "file"),
		size = info.size,
		modtime = info.modified,
		createtime = info.created,
		readonly = info.isReadOnly
	}
end

---Returns contents of the file in a form of a string.
---If the file can't be read, then nil and an error message is returned.
---@param filePath string
---@return string|nil, nil|string
function obsifs.read(filePath)
	filePath = getPath(filePath)
	local fh, e = fs.open(filePath, "rb")
	if not fh then
		return nil, e
	end
	local contents = fh.readAll() or ""
	fh.close()
	return contents
end

---@param filePath string
---@param data string
---@return boolean, string?
function obsifs.write(filePath, data)
	filePath = getPath(filePath)
	local fh, e = fs.open(filePath, "wb")
	if not fh then
		return false, e
	end
	fh.write(data)
	fh.close()
	return true
end

---@param path string
---@return boolean, string?
function obsifs.remove(path)
	path = getPath(path)
	local r, e = pcall(fs.delete, path)
	return r, e
end

---Returns an iterator, similar to `io.lines`.
---If the file can't be read, then the function errors.
---@param filePath string
---@return fun(): string|nil
function obsifs.lines(filePath)
	filePath = getPath(filePath)
	local fh, e = fs.open(filePath, "rb")
	if not fh then
		error(e)
	end
	return function ()
		return fh.readLine(false) or fh.close()
	end
end

local function init(path)
	gamePath = fs.combine(path)
	return obsifs, function() useGamePath = true end
end

return init