local fs
local onb = require("obsi2.audio.onbParser")
local nbs = require("obsi2.audio.nbsParser")
local t = os.clock()
---@class obsi.audio
local audio = {}

---@type Speaker[]
local channels = {}
local fakeSpeaker = false

---@class note
---@field speaker integer
---@field pitch number
---@field volume number
---@field instrument instrument?
---@field sound string?
---@field latency number?
---@field timing number?

---@class obsi.Audio
---@field name string
---@field description string
---@field bpm number
---@field duration number measured in seconds
---@field notes note[]

---@class obsi.PlayingAudio
---@field audio obsi.Audio
---@field startTime number
---@field holdTime number
---@field lastNote integer
---@field volume number
---@field loop boolean
---@field playing boolean

local audiobuffer = {}
---@type obsi.PlayingAudio[]
audiobuffer.sounds = {}
audiobuffer.max = 0

---@type note[]
local notebuffer = {}

-- Plays a single note. If you are not sure what channel to use, just use 1.
---@param channel integer
---@param instrument instrument
---@param pitch number  from 0 to 24
---@param volume number? from 0 to 3
---@param latency number? in seconds
function audio.playNote(channel, instrument, pitch, volume, latency)
	volume = math.max(math.min(volume or 1, 3), 0)
	pitch = math.max(math.min(pitch, 24), 0)
	latency = latency or 0
	notebuffer[#notebuffer+1] = {pitch = pitch, speaker = channel, instrument = instrument, volume = volume, latency = latency}
	table.sort(notebuffer, function (n1, n2)
		return n1.latency < n2.latency
	end)
end

-- Plays a single note. If you are not sure what channel to use, just use 1.
---@param channel integer
---@param sound string
---@param pitch number  from 0 to 24
---@param volume number? from 0 to 3
---@param latency number? in seconds
function audio.playSound(channel, sound, pitch, volume, latency)
	volume = math.max(math.min(volume or 1, 3), 0)
	pitch = math.max(math.min(pitch, 24), 0)
	latency = latency or 0
	notebuffer[#notebuffer+1] = {pitch = pitch, speaker = channel, sound = sound, volume = volume, latency = latency}
	table.sort(notebuffer, function (n1, n2)
		return n1.latency < n2.latency
	end)
end

function audio.isAvailable()
	return not fakeSpeaker
end

-- Refreshes the list of speakers (channels).
--
-- By default it should be called internally, but you can use it in your code if you want.
function audio.refreshChannels()
	local chans = {peripheral.find("speaker")}
	if #chans ~= 0 then
		channels = chans
		fakeSpeaker = false
	else
		if periphemu then
			periphemu.create("ObsiSpeaker", "speaker")
			channels[1] = peripheral.wrap("ObsiSpeaker") --[[@as Speaker]]
			fakeSpeaker = false
		else
			channels[1] = {
				playAudio = function() end,
				playNote = function() end,
				playSound = function() end,
				stop = function() end,
			}
			fakeSpeaker = true
		end
	end
end

function audio.getChannelCount()
	return #channels
end

function audio.isPlaying()
	return #notebuffer > 0 or #audiobuffer > 0
end

function audio.notesPlaying()
	return #notebuffer
end

---@param soundPath path
---@return obsi.Audio
function audio.newSound(soundPath)
	local contents, e = fs.read(soundPath)
	if not contents then
		error(e)
	end
	local mus, e1 = onb.parseONB(contents)
	if mus then
		return mus
	end
	local mus, e2 = nbs.parseNBS(contents)
	if mus then
		return mus
	end
	if soundPath:sub(-4):lower() == ".onb" then
		error(e1)
	elseif soundPath:sub(-4):lower() == ".nbs" then
		error(e2)
	else
		error(("Extension of the audio is not supported: %s"):format(soundPath), 2)
	end
end

---@param source obsi.Audio
---@param loop? boolean
---@return integer
function audio.play(source, loop)
	---@type obsi.PlayingAudio
	local paudio = {
		audio = source,
		startTime = os.clock(),
		holdTime = os.clock(),
		lastNote = 1,
		loop = loop or false,
		playing = true,
		volume = 1
	}
	for i = 1, audiobuffer.max+1 do
		if not audiobuffer.sounds[i] then
			audiobuffer.sounds[i] = paudio
			if i > audiobuffer.max then
				audiobuffer.max = i
			end
			return i
		end
	end
	return -1
end

---@param source obsi.Audio|integer
function audio.stop(source)
	if type(source) == "number" then
		audiobuffer.sounds[source] = nil
		return
	end
	for i = 1, audiobuffer.max do
		local s = audiobuffer.sounds[i]
		if s then
			if s.audio == source then
				audiobuffer.sounds[i] = nil
			end
		end
	end
end

---@param source obsi.Audio
---@param id integer
---@return boolean
function audio.isID(source, id)
	if audiobuffer.sounds[id] then
		return audiobuffer.sounds[id].audio == source
	end
	return false
end

---@param source obsi.PlayingAudio
local function pauseAudio(source)
	if source.playing then
		source.holdTime = os.clock()
		source.playing = false
	end
end

---@param source obsi.Audio|integer
function audio.pause(source)
	if type(source) == "number" then
		local s = audiobuffer.sounds[source]
		if s then
			pauseAudio(s)
		end
		return
	end
	for i = 1, audiobuffer.max do
		local s = audiobuffer.sounds[i]
		if s then
			if s.audio == source then
				pauseAudio(s)
			end
		end
	end
end

---@param source obsi.PlayingAudio
local function unpauseAudio(source)
	if not source.playing then
		source.startTime = os.clock()+source.startTime-source.holdTime
		source.playing = true
		local note = source.audio.notes[source.lastNote]
		while note and note.timing+source.startTime < t do
			source.lastNote = source.lastNote + 1
			note = source.audio.notes[source.lastNote]
		end
		if source.lastNote > #source.audio.notes then
			source.lastNote = 1
			source.startTime = os.clock()
		end
	end
end

---@param source obsi.Audio|integer
function audio.unpause(source)
	if type(source) == "number" then
		local s = audiobuffer.sounds[source]
		if s then
			unpauseAudio(s)
		end
		return
	end
	for i = 1, audiobuffer.max do
		local s = audiobuffer.sounds[i]
		if s and s.audio == source then
			unpauseAudio(s)
		end
	end
end

---@param source obsi.PlayingAudio
---@param volume number
local function setVolumeAudio(source, volume)
	source.volume = volume
end

---@param source obsi.Audio|integer
---@param volume number
function audio.setVolume(source, volume)
	if type(source) == "number" then
		local s = audiobuffer.sounds[source]
		if s then
			setVolumeAudio(s, volume)
		end
		return
	end
	for i = 1, audiobuffer.max do
		local s = audiobuffer.sounds[i]
		if s and s.audio == source then
			setVolumeAudio(s, volume)
		end
	end
end

---@param id integer
function audio.getVolume(id)
	return audiobuffer.sounds[id] and audiobuffer.sounds[id].volume or 0
end

---@param id integer
---@return boolean
function audio.isPaused(id)
	return audiobuffer.sounds[id] and audiobuffer.sounds[id].playing or false
end

---@param dt number
local function soundLoop(dt)
	if dt == 0 then
		dt = 0.025 -- Should, but most of the time doesn't fix crashing on non-Java platforms.
	end
	t = t + dt
	for i, note in ipairs(notebuffer) do
		note.latency = note.latency - dt
		if note.latency <= 0 then
			local speaker = channels[((note.speaker-1) % #channels)+1]
			if note.sound then
				speaker.playSound(note.sound, note.volume, note.pitch)
			else
				speaker.playNote(note.instrument, note.volume, note.pitch)
			end
			table.remove(notebuffer, i)
		end
	end
	for i = 1, audiobuffer.max do
		local s = audiobuffer.sounds[i]
		if s and s.playing then
			local nextCanPlay = true
			local r = 0
			while nextCanPlay do
				r = r + 1
				if r > 1000 then
					-- Yes, this is my fix for crashing in Minecraft.
					break
				end
				nextCanPlay = false
				local note = s.audio.notes[s.lastNote]
				if s.startTime+note.timing < t then
					local speaker = channels[(note.speaker-1)%#channels+1]
					speaker.playNote(note.instrument, math.min(note.volume*s.volume, 3), note.pitch)
					s.lastNote = s.lastNote + 1
				end
				if s.lastNote > #s.audio.notes then
					if s.loop then
					   s.lastNote = 1
					   s.startTime = t
					else
						audiobuffer.sounds[i] = nil
					end
				elseif s.audio.notes[s.lastNote].timing < t-s.startTime then
					nextCanPlay = true
				end
			end
		end
	end
end

local function init(obsifs)
	fs = obsifs
	audio.refreshChannels()
	return audio, soundLoop
end

return init