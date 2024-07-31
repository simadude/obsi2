---@type obsi.fs
local fs
local renderers = {}
renderers.neat = require("obsi2.graphics.neat")
renderers.pixelbox = require("obsi2.graphics.pixelbox")
renderers.basic = require("obsi2.graphics.basic")
local nfp = require("obsi2.graphics.nfpParser")
local orli = require("obsi2.graphics.orliParser")
---@type Window
local wind
do
	local w, h = term.getSize()
	wind = window.create(term.current(), 1, 1, w, h, false)
end

---@class obsi.graphics
local graphics = {}

local floor, ceil, abs, max, min = math.floor, math.ceil, math.abs, math.max, math.min

---@alias obsi.InternalCanvas neat.Canvas|pixelbox.box|basic.Canvas
---@alias obsi.RenderingName "basic"|"neat"|"pixelbox"

---@type obsi.InternalCanvas
local internalCanvas
---@type obsi.Canvas|obsi.InternalCanvas
local currentCanvas

---@class obsi.TextPiece
---@field x integer
---@field y integer
---@field text string
---@field fgColor string?
---@field bgColor string?

---@type obsi.TextPiece[]
local textBuffer = {}

graphics.originX = 1
graphics.originY = 1

graphics.width, graphics.height = term.getSize()

graphics.fgColor = colors.white
graphics.bgColor = colors.black

---@param value any
---@param paramName string
---@param expectedType type
local function checkType(value, paramName, expectedType)
	if type(value) ~= expectedType then
		error(("Argument '%s' must be a %s, not a %s"):format(paramName, expectedType, type(value)), 3)
	end
end

---@type table<integer, string>
local toBlit = {}
for i = 0, 15 do
	toBlit[2^i] = ("%x"):format(i)
end

local function getBlit(color)
	return toBlit[color]
end

---Sets a specific palette color
---@param color string|color
---@param r number value within the range [0-1]
---@param g number value within the range [0-1]
---@param b number value within the range [0-1]
function graphics.setPaletteColor(color, r, g, b)
	if type(color) == "string" then
		if #color ~= 1 then
			error(("Argument `color: string` must be 1 character long, not %s"):format(#color))
		end
		color = tonumber(color, 16)
		if not color then
			error(("Argument `color: string` must be a valid hex character, not %s"):format(color))
		end
		color = 2^color
	elseif type(color) ~= "number" then
		error(("Argument `color` must be either integer or string, not %s"):format(type(color)))
	end
	checkType(r, "r", "number")
	checkType(g, "g", "number")
	checkType(b, "b", "number")
	wind.setPaletteColor(color, r, g, b)
end

---@param x integer
---@param y integer
function graphics.offsetOrigin(x, y)
	checkType(x, "x", "number")
	checkType(y, "y", "number")
	graphics.originX = graphics.originX + floor(x)
	graphics.originY = graphics.originY + floor(y)
end

---@param x integer
---@param y integer
function graphics.setOrigin(x, y)
	checkType(x, "x", "number")
	checkType(y, "y", "number")
	graphics.originX = floor(x)
	graphics.originY = floor(y)
end

function graphics.resetOrigin()
	graphics.originX = 1
	graphics.originY = 1
end

---@return integer, integer
function graphics.getOrigin()
	return graphics.originX, graphics.originY
end

function graphics.getPixelWidth()
	return graphics.pixelWidth
end

function graphics.getPixelHeight()
	return graphics.pixelHeight
end

function graphics.getWidth()
	return graphics.width
end

function graphics.getHeight()
	return graphics.height
end

function graphics.getSize()
	return graphics.width, graphics.height
end

function graphics.getPixelSize()
	return graphics.pixelWidth, graphics.pixelHeight
end

function graphics.termToPixelCoordinates(x, y)
	if internalCanvas.owner == "basic" then
		return x, y
	elseif internalCanvas.owner == "neat" then
		return x, floor(y*1.5)
	elseif internalCanvas.owner == "pixelbox" then
		return x*2, y*3
	end
end

function graphics.pixelToTermCoordinates(x, y)
	if internalCanvas.owner == "basic" then
		return x, y
	elseif internalCanvas.owner == "neat" then
		return x, floor(y/1.5)
	elseif internalCanvas.owner == "pixelbox" then
		return floor(x/2), floor(y/3)
	end
end

---@param col color|string
---@return color
local function toColor(col)
	if type(col) == "string" then
		return 2^tonumber(col, 16)
	end
	return col
end

---@param color color|string
function graphics.setBackgroundColor(color)
	graphics.bgColor = toColor(color)
end

---@param color color|string
function graphics.setForegroundColor(color)
	graphics.fgColor = toColor(color)
end

---@return color
function graphics.getBackgroundColor()
	return graphics.bgColor
end

---@return color
function graphics.getForegroundColor()
	return graphics.fgColor
end

---@param x number
---@param y number
---@return boolean
local function inBounds(x, y)
	return (x >= 1) and (y >= 1) and (x <= currentCanvas.width) and (y <= currentCanvas.height)
end

---@param x number
---@param y number
---@param color? color
local function safeOffsetPixel(x, y, color)
	color = color or graphics.fgColor
	x, y = floor(x-graphics.originX+1), floor(y-graphics.originY+1)
	if inBounds(x, y) then
		currentCanvas:setPixel(x, y, color)
	end
end

---@param x number
---@param y number
function graphics.point(x, y)
	checkType(x, "x", "number")
	checkType(y, "y", "number")

	safeOffsetPixel(x, y)
end

---@param points table[]
function graphics.points(points)
	for i = 1, #points do
		local point = points[i]
		safeOffsetPixel(point[1], point[2])
	end
end

---Asked Claude to optimize this function.
---@param mode "fill"|"line"
---@param x integer
---@param y integer
---@param width integer
---@param height integer
function graphics.rectangle(mode, x, y, width, height)
	checkType(x, "x", "number")
	checkType(y, "y", "number")
	checkType(width, "width", "number")
	checkType(height, "height", "number")

	-- Get screen dimensions
	local screenWidth, screenHeight = graphics.getPixelSize()

	-- Adjust coordinates based on origin
	x = floor(x - graphics.originX + 1)
	y = floor(y - graphics.originY + 1)

	-- Clamp rectangle coordinates and dimensions to screen bounds
	local startX = max(1, x)
	local startY = max(1, y)
	local endX = min(screenWidth, x + width - 1)
	local endY = min(screenHeight, y + height - 1)

	-- If the rectangle is completely offscreen, return early
	if startX > endX or startY > endY then
		return
	end

	if mode == "fill" then
		for ry = startY, endY do
			for rx = startX, endX do
				currentCanvas:setPixel(rx, ry, graphics.fgColor)
			end
		end
	elseif mode == "line" then
		-- Left vertical line
		if x >= 1 and x <= screenWidth then
			for ry = startY, endY do
				currentCanvas:setPixel(x, ry, graphics.fgColor)
			end
		end
		-- Right vertical line
		local rightX = x + width - 1
		if rightX >= 1 and rightX <= screenWidth then
			for ry = startY, endY do
				currentCanvas:setPixel(rightX, ry, graphics.fgColor)
			end
		end
		-- Top horizontal line
		if y >= 1 and y <= screenHeight then
			for rx = startX, endX do
				currentCanvas:setPixel(rx, y, graphics.fgColor)
			end
		end
		-- Bottom horizontal line
		local bottomY = y + height - 1
		if bottomY >= 1 and bottomY <= screenHeight then
			for rx = startX, endX do
				currentCanvas:setPixel(rx, bottomY, graphics.fgColor)
			end
		end
	end
end

function graphics.line(point1, point2)
	local x1, y1 = floor(point1[1]), floor(point1[2])
	local x2, y2 = floor(point2[1]), floor(point2[2])
	local dx, dy = abs(x2-x1), abs(y2-y1)
	local sx, sy = (x1 < x2) and 1 or -1, (y1 < y2) and 1 or -1
	local err = dx-dy
	while x1 ~= x2 or y1 ~= y2 do
		safeOffsetPixel(x1, y1)
		local err2 = err * 2
		if err2 > -dy then
			err = err - dy
			x1 = x1 + sx
		end
		if err2 < dx then
			err = err + dx
			y1 = y1 + sy
		end
	end
	safeOffsetPixel(x2, y2)
end

---@class obsi.Image
---@field data integer[][]
---@field width integer
---@field height integer

local function getCorrectImage(imagePath, contents)
	local image, e2, e1
	image, e1 = orli.parse(contents)
	if image then
		return image
	end
	image, e2 = nfp.parse(contents)
	if image then
		return image
	end
	if imagePath:sub(-5):lower() == ".orli" then
		error(e1)
	elseif imagePath:sub(-4):lower() == ".nfp" then
		error(e2)
	else
		error(("Extension of the image is not supported: %s"):format(imagePath), 2)
	end
end

---@param imagePath string
---@return obsi.Image
function graphics.newImage(imagePath)
	local contents, e = fs.read(imagePath)
	if not contents then
		error(e)
	end
	local image = getCorrectImage(imagePath, contents)
	return image
end

---Returns a blank obsi.Image with a solid color. 
---@param width integer
---@param height integer
---@param filler? color|string
---@return obsi.Image
function graphics.newBlankImage(width, height, filler)
	checkType(width, "width", "number")
	checkType(height, "height", "number")

	filler = filler and toColor(filler) or -1
	width = floor(max(width, 1))
	height = floor(max(height, 1))

	local image = {}
	image.data = {}
	for y = 1, height do
		image.data[y] = {}
		for x = 1, width do
			image.data[y][x] = filler
		end
	end
	image.width = width
	image.height = height

	return image
end


---Returns an array of obsi.Image objects that represent the tiles on the Tilemap.
---@param imagePath string
---@return obsi.Image[]
function graphics.newImagesFromTilesheet(imagePath, tileWidth, tileHeight)
	local contents, e = fs.read(imagePath)
	if not contents then
		error(e)
	end
	local map = getCorrectImage(imagePath, contents)

	if map.width % tileWidth ~= 0 then
		error(("Tilemap width can't be divided by tile's width: %s and %s"):format(map.width, tileWidth))
	elseif map.height % tileHeight ~= 0 then
		error(("Tilemap height can't be divided by tile's height: %s and %s"):format(map.height, tileHeight))
	end

	local images = {}

	for ty = tileHeight, map.height, tileHeight do
		for tx = tileWidth, map.width, tileWidth do
			local image = graphics.newBlankImage(tileWidth, tileHeight, -1)
			for py = 1, tileHeight do
				for px = 1, tileWidth do
					image.data[py][px] = map.data[ty-tileHeight+py][tx-tileWidth+px]
				end
			end
			images[#images+1] = image
		end
	end

	return images
end

---Creates a new obsi.Canvas object.
---@param width integer?
---@param height integer?
---@return obsi.Canvas
function graphics.newCanvas(width, height)
	width, height = floor(width or internalCanvas.width), floor(height or internalCanvas.height)

	---@class obsi.Canvas
	local canvas = {}
	canvas.width = width
	canvas.height = height
	canvas.data = {}
	for y = 1, height do
		canvas.data[y] = {}
		for x = 1, width do
			canvas.data[y][x] = colors.black
		end
	end

	---@param x integer
	---@param y integer
	---@param color color
	function canvas:setPixel(x, y, color)
		self.data[y][x] = color
	end

	---@param x integer
	---@param y integer
	---@return color
	function canvas:getPixel(x, y)
		return self.data[y][x]
	end

	function canvas:clear()
		for y = 1, self.height do
			for x = 1, self.width do
				self.data[y][x] = graphics.bgColor
			end
		end
	end

	return canvas
end

---@param image obsi.Image
---@param x integer
---@param y integer
local function drawNoScale(image, x, y)
	local data = image.data
	for iy = 1, image.height do
		for ix = 1, image.width do
			if not data[iy] then
				error(("iy: %s, #image.data: %s"):format(iy, #data))
			end
			local pix = data[iy][ix]
			if pix > 0 then
				safeOffsetPixel(x+ix-1, y+iy-1, pix)
			end
		end
	end
end

---Draws an obsi.Image or obsi.Canvas at certain coordinates.
---@param image obsi.Image|obsi.Canvas
---@param x integer x position
---@param y integer y position
---@param sx? number x scale
---@param sy? number y scale
function graphics.draw(image, x, y, sx, sy)
	---@cast image obsi.Image
	checkType(x, "x", "number")
	checkType(y, "y", "number")
	sx = sx or 1
	sy = sy or 1

	-- check if the image out of the screen or if it's too small to be drawn
	if sx == 0 or sy == 0 then
		return
	elseif (sx > 0 and x-graphics.originX > currentCanvas.width) or (sy > 0 and y-graphics.originY > currentCanvas.height) then
		return
	end

	-- a little optimization to not bother with scaling
	if sx == 1 and sy == 1 then
		drawNoScale(image, x, y)
		return
	end
	local signsx = abs(sx)/sx
	local signsy = abs(sy)/sy
	sx = abs(sx)
	sy = abs(sy)
	-- variable naming:
	-- i_ - iterative variable
	-- p_ - pixel position on the image
	-- s_ - scale for each axis

	for iy = 1, image.height*sy do
		local py = ceil(iy/sy)
		for ix = 1, image.width*sx do
			local px = ceil(ix/sx)
			if not image.data[py] then
				error(("py: %s, #image.data: %s"):format(py, #image.data))
			end
			local pix = image.data[py][px]
			if pix > 0 then
				safeOffsetPixel(x+ix*signsx-signsx, y+iy*signsy-signsy, pix)
			end
		end
	end
end

--- Writes a text on the terminal.
---
--- Beware that it uses terminal coordinates and not pixel coordinates.
---@param text string
---@param x integer
---@param y integer
---@param fgColor? string|color
---@param bgColor? string|color
function graphics.write(text, x, y, fgColor, bgColor)
	checkType(text, "text", "string")
	checkType(x, "x", "number")
	checkType(y, "y", "number")
	local textPiece = {}
	textPiece.text = text
	textPiece.x = x
	textPiece.y = y

	fgColor = fgColor or graphics.fgColor
	bgColor = bgColor or graphics.bgColor

	if type(fgColor) == "number" then
		fgColor = getBlit(fgColor):rep(#text)
	elseif type(fgColor) == "string" and #fgColor == 1 then
		fgColor = fgColor:rep(#text)
	end
	---@cast fgColor string|nil

	if type(bgColor) == "number" then
		bgColor = getBlit(bgColor):rep(#text)
	elseif type(bgColor) == "string" and #bgColor == 1 then
		bgColor = bgColor:rep(#text)
	end
	---@cast bgColor string|nil

	if type(fgColor) ~= "string" then
		error("fgColor is not a number or a string!")
	elseif type(bgColor) ~= "string" then
		error("bgColor is not a number or a string!")
	end

	textPiece.fgColor = fgColor
	textPiece.bgColor = bgColor

	textBuffer[#textBuffer+1] = textPiece
end

---@class obsi.Palette
---@field data number[][]

---Creates a new obsi.Palette object.
---@param palettePath string
---@return obsi.Palette
function graphics.newPalette(palettePath)
	checkType(palettePath, "palettePath", "string")
	local fh, e = fs.newFile(palettePath, "r")
	if not fh then
		error(e)
	end

	local cols = {}
	for i = 1, 16 do
		local line = fh.file.readLine()
		if not line then
			error("File could not be read completely!")
		end
		local occurrences = {}
		for str in line:gmatch("%d+") do
			if not tonumber(str) then
				error(("Can't put %s as a number"):format(str))
			end
			occurrences[#occurrences+1] = tonumber(str)/255
		end
		if #occurrences > 3 then
			error("More colors than should be possible!")
		end
		cols[i] = {table.unpack(occurrences)}
	end

	fh:close()
	return {data = cols}
end

---@param palette obsi.Palette
function graphics.setPalette(palette)
	for i = 1, 16 do
		local colors = palette.data[i]
		wind.setPaletteColor(2^(i-1), colors[1], colors[2], colors[3])
	end
end

---@return obsi.Palette
function graphics.getPallete()
	local cols = {}
	local pal = {data = cols}
	for i = 1, 16 do
		cols[i] = {term.getPaletteColor(2^(i-1))}
	end
	return pal
end

function graphics.clearPalette()
	shell.run("clear", "palette")
end

---@param canvas obsi.Canvas|nil
function graphics.setCanvas(canvas)
	currentCanvas = canvas or internalCanvas
end

---@return obsi.Canvas|obsi.InternalCanvas
function graphics.getCanvas()
	return currentCanvas
end

---Internal function that clears the canvas.
function graphics.clear()
	for y = 1, currentCanvas.height do
		for x = 1, currentCanvas.width do
			currentCanvas:setPixel(x, y, graphics.bgColor)
		end
	end
end

---@param rend obsi.RenderingName
function graphics.setRenderer(rend)
	local renderer = renderers[rend]
	if renderer then
		renderer.own(internalCanvas)
		local w, h = graphics.getSize()
		internalCanvas:resize(w, h)
		graphics.pixelWidth, graphics.pixelHeight = internalCanvas.width, internalCanvas.height
	else
		error(("Unknown renderer name: %s"):format(rend))
	end
end

function graphics.getRenderer()
	return internalCanvas.owner
end

---Internal function that draws the canvas.
function graphics.flushCanvas()
	internalCanvas:render()
end

---Internal function that draws all the texts.
function graphics.flushText()
	for i = 1, #textBuffer do
		local textPiece = textBuffer[i]
		local text = textPiece.text
		if textPiece.x+#text >= 1 and textPiece.y >= 1 and textPiece.x <= graphics.getWidth() and textPiece.y <= graphics.getHeight() then
			wind.setCursorPos(textPiece.x, textPiece.y)
			wind.blit(text, textPiece.fgColor or getBlit(graphics.fgColor):rep(#text), textPiece.bgColor or getBlit(graphics.bgColor):rep(#text))
		end
	end
	textBuffer = {}
end

function graphics.flushAll()
	graphics.flushCanvas()
	graphics.flushText()
end

function graphics.show()
	wind.setVisible(true)
	wind.setVisible(false)
end

return function (obsifs, renderingAPI)
	internalCanvas = renderers[renderingAPI].newCanvas(wind)
	graphics.pixelWidth, graphics.pixelHeight = internalCanvas.width, internalCanvas.height
	currentCanvas = internalCanvas
	fs = obsifs
	return graphics, internalCanvas, wind
end
