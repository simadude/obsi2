local nfp = {}

---Takes inconsistent 2D array as an argument and returns a consistent one instead.
---@param data integer[][]
---@param width integer
---@param height integer
---@return integer[][]
function nfp.consise(data, width, height)
	for y = 1, height do
		data[y] = data[y] or {}
		for x = 1, width do
			data[y][x] = data[y][x] or -1
		end
	end
	return data
end

---@param text string
---@return obsi.Image?, string?
function nfp.parse(text)
	local x, y = 1, 1
	local width = 0
	local img = {}
	local data = {}
	img.data = data
	for i = 1, #text do
		local char = text:sub(i, i)
		if not tonumber(char, 16) and char ~= "\n" and char ~= " " then
			return nil, ("Unknown character (%s) at %s\nMake sure your image is valid .nfp"):format(char, i)
		end
		if char == "\n" then
			y = y + 1
			x = 1
		else
			if not data[y] then
				data[y] = {}
			end
			data[y][x] = (char == " ") and -1 or 2^tonumber(char, 16)
			width = math.max(width, x)
			x = x + 1
		end
	end
	img.width = width
	img.height = y
	nfp.consise(data, width, y)
	return img
end

return nfp