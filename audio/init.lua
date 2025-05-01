local fs
local onb = require("obsi2.audio.onbParser")
local nbs = require("obsi2.audio.nbsParser")
local dfpwm = require("cc.audio.dfpwm").make_decoder()
local function clock()
	return periphemu and os.epoch(("nano")--[[@as "local"]])/10^9 or os.clock()
end
local t = os.clock()
---@class obsi.audio
local audio = {}

---@type ccTweaked.peripherals.Speaker[]
local channels = {}
local fakeSpeaker = false

---@class note
---@field speaker integer
---@field pitch number
---@field volume number
---@field instrument ccTweaked.peripherals.speaker.instrument?
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

---@class obsi.AudioDFPWM
---@field name string
---@field sampleRate number
---@field samples number[]

---@class obsi.PlayingAudioDFPWM
---@field channel number
---@field audio obsi.AudioDFPWM
---@field lastSample number Index of the sample
---@field lastSampleTime number The last time previous buffer was played
---@field volume number
---@field loop boolean
---@field playing boolean

local dfpwmbuffers = {}

---@type table<integer, integer[]>
dfpwmbuffers.channels = {}
---@type table<integer, obsi.PlayingAudioDFPWM>
dfpwmbuffers.sounds = {}
dfpwmbuffers.size = 24000 -- 48k = 1s, 24k = 0.5s (this is to sync stuff ig)

local audiobuffer = {}
---@type obsi.PlayingAudio[]
audiobuffer.sounds = {}
audiobuffer.max = 0

---@type note[]
local notebuffer = {}

-- Plays a single note. If you are not sure what channel to use, just use 1.
---@param channel integer
---@param instrument ccTweaked.peripherals.speaker.instrument
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

-- Plays a single sound. If you are not sure what channel to use, just use 1.
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
		for k, v in ipairs(channels) do
			if dfpwmbuffers.channels[k] then
				local buffer = dfpwmbuffers.channels[k]
				for i = 1, dfpwmbuffers.size do
					buffer[i] = 0
				end
			else
				local buffer = {}
				for i = 1, dfpwmbuffers.size do
					buffer[i] = 0
				end
				dfpwmbuffers.channels[k] = buffer
			end
		end
	else
		if periphemu then
			periphemu.create("ObsiSpeaker", "speaker")
			channels[1] = peripheral.wrap("ObsiSpeaker") --[[@as ccTweaked.peripherals.Speaker]]
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
		for k, v in ipairs(channels) do
			if dfpwmbuffers.channels[k] then
				local buffer = dfpwmbuffers.channels[k]
				for i = 1, dfpwmbuffers.size do
					buffer[i] = 0
				end
			else
				local buffer = {}
				for i = 1, dfpwmbuffers.size do
					buffer[i] = 0
				end
				dfpwmbuffers.channels[k] = buffer
			end
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

---@param soundPath string
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

---@param soundPath string
---@param sampleRate? integer
---@return obsi.AudioDFPWM
function audio.newSoundDFPWM(soundPath, sampleRate)
	sampleRate = sampleRate or 48000
	local contents, e = fs.read(soundPath)
	if not contents then
		error(e)
	end
	local samp = dfpwm(contents) -- fuck ram, man
	return {
		name = soundPath,
		samples = samp,
		sampleRate = sampleRate
	}
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

---@param channel integer|nil
---@param source obsi.AudioDFPWM
---@param loop? boolean
---@return integer
function audio.playDFPWM(channel, source, loop)
	if not channel then
		local choseChannel = false
		for k, _ in ipairs(channels) do
			if not dfpwmbuffers.channels[k] then
				channel = k
				choseChannel = true
			end
		end
		if not choseChannel then
			return -1
		end
	end
	---@cast channel integer

	---@type obsi.PlayingAudioDFPWM
	local paudio = {
		channel = channel,
		audio = source,
		lastSample = 1,
		loop = loop or false,
		playing = true,
		lastSampleTime = os.clock(),
		volume = 1
	}
	dfpwmbuffers.sounds[channel] = paudio
	return channel
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

--- Stops a speaker at that channel by calling `speaker.stop()`.
---@param channelID integer
function audio.stopSpeaker(channelID)
	if channels[channelID] then
		channels[channelID].stop()
	end
end

--- Removes a DFPWM sound from a channel.
---@param channelID integer
function audio.stopDFPWM(channelID)
	if dfpwmbuffers.sounds[channelID] then
		dfpwmbuffers.sounds[channelID] = nil
	end
end

--- Stops whatever sound any speaker is playing by calling `speaker.stop()` on each.
function audio.stopAll()
	for _, speaker in pairs(channels) do
		speaker.stop()
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

---@param source obsi.AudioDFPWM
---@param channelID integer
---@return boolean
function audio.isIDDFPWM(source, channelID)
	if dfpwmbuffers.sounds[channelID] then
		return dfpwmbuffers.sounds[channelID].audio == source
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

function audio.pauseDFPWM(channel)
	if dfpwmbuffers.sounds[channel] then
		dfpwmbuffers.sounds[channel].playing = false
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

function audio.unpauseDFPWM(channel)
	if dfpwmbuffers.sounds[channel] then
		dfpwmbuffers.sounds[channel].playing = true
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

function audio.setVolumeDFPWM(channel, volume)
	if dfpwmbuffers.sounds[channel] then
		dfpwmbuffers.sounds[channel].volume = volume
	end
end

---@param id integer
function audio.getVolume(id)
	return audiobuffer.sounds[id] and audiobuffer.sounds[id].volume or 0
end

function audio.getVolumeDFPWM(channel)
	if dfpwmbuffers.sounds[channel] then
		return dfpwmbuffers.sounds[channel].volume
	end
	return 0
end

---@param id integer
---@return boolean
function audio.isPaused(id)
	return audiobuffer.sounds[id] and audiobuffer.sounds[id].playing or false
end

function audio.isPausedDFPWM(channel)
	if dfpwmbuffers.sounds[channel] then
		return dfpwmbuffers.sounds[channel].playing
	end
	return false
end

---@param channel integer
---@return number # Returns the total duration (in seconds) of the playing DFPWM at the specified channel
function audio.getDurationDFPWM(channel)
	local au = dfpwmbuffers.sounds[channel]
	if au then
		return #au.audio.samples/au.audio.sampleRate
	end
	return 0
end

---@param channel integer
---@return number # Returns the current playback (in seconds) of the playing DFPWM at the specified channel
function audio.getPlaybackDFPWM(channel)
	local au = dfpwmbuffers.sounds[channel]
	if au then
		return (#au.audio.samples - au.lastSample)/au.audio.sampleRate -- + au.lastSampleTime - clock()
	end
	return 0
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

---@param speakerName? string
local function DFPWMLoop(speakerName)
	local time = clock()
	if speakerName then
		local cid = 0 -- Channel index
		for k, channel in pairs(channels) do
			if not channel.fakeSpeaker and peripheral.getName(channel) == speakerName then
				cid = k
				break
			end
		end
		if cid == 0 then
			return
		end
		local sound = dfpwmbuffers.sounds[cid]
		if sound and sound.playing then
			local samples = sound.audio.samples
			local speed = sound.audio.sampleRate/48000
			if time-sound.lastSampleTime >= 0.45 then -- idk why, but this is needed
				local buf = dfpwmbuffers.channels[cid]
				local j = 1
				for i = 1, dfpwmbuffers.size do
					buf[i] = samples[sound.lastSample + math.floor(j)]
					j = j + speed
				end
				channels[cid].playAudio(buf)
				sound.lastSample = sound.lastSample + math.floor(j)
				if sound.lastSample > #samples then
					if sound.loop then
						sound.lastSample = 1
					else
						dfpwmbuffers.sounds[cid] = nil
					end
				else
					sound.lastSampleTime = time
				end
			end
		end
	else
		for cid, sound in pairs(dfpwmbuffers.sounds) do
			if sound.playing then
				local samples = sound.audio.samples
				local speed = sound.audio.sampleRate/48000
				if time-sound.lastSampleTime > 0.5 then
					local buf = dfpwmbuffers.channels[cid]
					local j = 1
					for i = 1, dfpwmbuffers.size do
						buf[i] = samples[sound.lastSample + math.floor(j)]
						j = j + speed
					end
					channels[cid].playAudio(buf)
					sound.lastSample = sound.lastSample + math.floor(j)
					if sound.lastSample > #samples then
						if sound.loop then
							sound.lastSample = 1
						else
							dfpwmbuffers.sounds[cid] = nil
						end
					else
						sound.lastSampleTime = time
					end
				end
			end
		end
	end
end

local function init(obsifs)
	fs = obsifs
	audio.refreshChannels()
	return audio, soundLoop, DFPWMLoop
end

return init