-- Typing Rhythm: a private typing-timing logger for Hammerspoon.
--
-- What it records: how long keys are held down and the gaps between key presses,
-- rolled up into hourly totals and histograms. That is all.
-- What it never records: which keys you press, what you type, or which app you're in.
-- Key codes live in memory for a fraction of a second (to pair each key-down with its
-- key-up) and are never written anywhere.
--
-- macOS also blocks this kind of monitoring in password fields ("Secure Input"),
-- so passwords can't reach this script at all.
--
-- Data: ~/TypingRhythm/data/YYYY-MM-DD.json   Report: python3 ~/TypingRhythm/report.py

local TR = {}

local HOME = os.getenv("HOME")
local DATA_DIR = HOME .. "/TypingRhythm/data"

-- Histogram settings (milliseconds)
local HOLD_BIN, HOLD_BINS = 5, 120        -- 0-600 ms in 5 ms bins, plus overflow
local GAP_BIN, GAP_BINS = 10, 150         -- 0-1500 ms in 10 ms bins, plus overflow
local PAUSE_MS = 2000                     -- a gap this long ends a typing burst
local MIN_HOLD, MAX_HOLD = 5, 2000        -- ignore impossible or stuck-key holds
local MIN_BURST_KEYS = 10                 -- bursts shorter than this don't count for speed
local SAVE_EVERY_SEC = 300

-- Keys that are navigation, function or modifier keys: skipped entirely.
local SKIP = {}
for _, k in ipairs({53, 48, 123, 124, 125, 126, 115, 119, 116, 121,  -- esc tab arrows home end pgup pgdn
                    122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
                    55, 54, 56, 60, 58, 61, 59, 62, 57, 63, 114}) do SKIP[k] = true end
local BACKSPACE = {[51] = true, [117] = true}
local SPACE = {[49] = true}
local ENTER = {[36] = true, [76] = true}

-- State ----------------------------------------------------------------------
local state = {
  day = nil,         -- "YYYY-MM-DD" currently loaded
  buckets = {},      -- key "HH|kbtype" -> bucket table
  pending = {},      -- keycode -> down time (ms), in memory only
  lastDown = nil,    -- ms of previous key-down
  burstStart = nil, burstKeys = 0, burstLast = nil,
  paused = false, pausedUntil = nil,
  keysToday = 0,
  dirty = false,
}

local function nowMs() return hs.timer.absoluteTime() / 1e6 end

local function zeros(n) local t = {} for i = 1, n do t[i] = 0 end return t end

local function newBucket(hour, kb)
  return {
    hour = hour, keyboard_type = kb,
    keys = 0, holds = 0, backspace = 0, space = 0, enter = 0,
    hold_mean = 0, hold_m2 = 0,                 -- running mean / sum of squares (Welford)
    hold_hist = zeros(HOLD_BINS + 1),
    gap_hist = zeros(GAP_BINS + 1),
    pauses = 0,
    bursts = 0, burst_keys = 0, burst_ms = 0,
  }
end

local function ensureDir()
  os.execute('mkdir -p "' .. DATA_DIR .. '"')
end

local function dayFile(day) return DATA_DIR .. "/" .. day .. ".json" end

local function save()
  if not state.day or not state.dirty then return end
  ensureDir()
  local list = {}
  for _, b in pairs(state.buckets) do table.insert(list, b) end
  table.sort(list, function(a, b) return (a.hour .. a.keyboard_type) < (b.hour .. b.keyboard_type) end)
  local out = { version = 1, day = state.day, buckets = list }
  local tmp = dayFile(state.day) .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then return end
  f:write(hs.json.encode(out, true))
  f:close()
  os.rename(tmp, dayFile(state.day))
  state.dirty = false
end

local function loadDay(day)
  state.day = day
  state.buckets = {}
  state.keysToday = 0
  local f = io.open(dayFile(day), "r")
  if f then
    local ok, data = pcall(hs.json.decode, f:read("a"))
    f:close()
    if ok and data and data.buckets then
      for _, b in ipairs(data.buckets) do
        state.buckets[b.hour .. "|" .. tostring(b.keyboard_type)] = b
        state.keysToday = state.keysToday + (b.keys or 0)
      end
    end
  end
end

local function bucketFor(kb)
  local day = os.date("%Y-%m-%d")
  if day ~= state.day then
    save()
    loadDay(day)
  end
  local hour = os.date("%H")
  local key = hour .. "|" .. tostring(kb)
  local b = state.buckets[key]
  if not b then b = newBucket(hour, kb); state.buckets[key] = b end
  return b
end

local function closeBurst(b)
  if state.burstStart and state.burstKeys >= MIN_BURST_KEYS and state.burstLast > state.burstStart then
    b.bursts = b.bursts + 1
    b.burst_keys = b.burst_keys + state.burstKeys
    b.burst_ms = b.burst_ms + (state.burstLast - state.burstStart)
  end
  state.burstStart, state.burstKeys, state.burstLast = nil, 0, nil
end

local function isPaused()
  if state.pausedUntil and os.time() >= state.pausedUntil then
    state.paused, state.pausedUntil = false, nil
    TR.updateMenu()
  end
  return state.paused
end

-- Event handling -----------------------------------------------------------------
local T = hs.eventtap.event.types
local P = hs.eventtap.event.properties

local function onKey(e)
  if isPaused() then return false end
  local code = e:getKeyCode()
  if SKIP[code] then return false end
  local t = nowMs()
  local etype = e:getType()

  if etype == T.keyDown then
    if e:getProperty(P.keyboardEventAutorepeat) == 1 then return false end
    local flags = e:getFlags()
    if flags.cmd or flags.ctrl then state.pending[code] = nil; return false end -- shortcuts aren't typing
    local kb = e:getProperty(P.keyboardEventKeyboardType) or 0
    local b = bucketFor(kb)
    b.keys = b.keys + 1
    state.keysToday = state.keysToday + 1
    if BACKSPACE[code] then b.backspace = b.backspace + 1
    elseif SPACE[code] then b.space = b.space + 1
    elseif ENTER[code] then b.enter = b.enter + 1 end

    if state.lastDown then
      local gap = t - state.lastDown
      if gap >= PAUSE_MS then
        b.pauses = b.pauses + 1
        closeBurst(b)
      elseif gap >= 0 then
        local i = math.floor(gap / GAP_BIN) + 1
        if i > GAP_BINS then i = GAP_BINS + 1 end
        b.gap_hist[i] = b.gap_hist[i] + 1
      end
    end
    if not state.burstStart then state.burstStart = t end
    state.burstKeys = state.burstKeys + 1
    state.burstLast = t
    state.lastDown = t
    state.pending[code] = { t = t, kb = kb }
    state.dirty = true

  elseif etype == T.keyUp then
    local p = state.pending[code]
    state.pending[code] = nil
    if p then
      local hold = t - p.t
      if hold >= MIN_HOLD and hold <= MAX_HOLD then
        local b = bucketFor(p.kb)
        b.holds = b.holds + 1
        local d = hold - b.hold_mean
        b.hold_mean = b.hold_mean + d / b.holds
        b.hold_m2 = b.hold_m2 + d * (hold - b.hold_mean)
        local i = math.floor(hold / HOLD_BIN) + 1
        if i > HOLD_BINS then i = HOLD_BINS + 1 end
        b.hold_hist[i] = b.hold_hist[i] + 1
      end
    end
  end
  return false -- never block or change the key
end

-- Menu bar -----------------------------------------------------------------------
function TR.updateMenu()
  if not TR.menu then return end
  TR.menu:setTitle(state.paused and "⌨︎ ‖" or "⌨︎")
  TR.menu:setTooltip("Typing Rhythm: " .. (state.paused and "paused" or "recording timing only"))
end

local function menuItems()
  local status
  if state.paused then
    status = state.pausedUntil and ("Paused until " .. os.date("%I:%M %p", state.pausedUntil)) or "Paused"
  else
    status = "Recording key timing (" .. tostring(state.keysToday) .. " keys today)"
  end
  return {
    { title = status, disabled = true },
    { title = "-" },
    { title = state.paused and "Resume" or "Pause", fn = function()
        state.paused = not state.paused; state.pausedUntil = nil; TR.updateMenu() end },
    { title = "Pause for 1 hour", disabled = state.paused, fn = function()
        state.paused = true; state.pausedUntil = os.time() + 3600; TR.updateMenu() end },
    { title = "-" },
    { title = "Open data folder", fn = function() ensureDir(); hs.execute('open "' .. DATA_DIR .. '"') end },
    { title = "Save now", fn = function() state.dirty = true; save(); hs.alert.show("Typing Rhythm saved") end },
    { title = "Run report", fn = function()
        state.dirty = true; save()
        hs.execute('cd "' .. HOME .. '/TypingRhythm" && /usr/bin/python3 report.py && open report.html', true) end },
  }
end

-- Start ----------------------------------------------------------------------------
function TR.start()
  ensureDir()
  loadDay(os.date("%Y-%m-%d"))
  TR.tap = hs.eventtap.new({ T.keyDown, T.keyUp }, onKey)
  TR.tap:start()
  -- macOS can switch off a tap if the system is busy; check and restart it.
  TR.watchdog = hs.timer.doEvery(30, function()
    if TR.tap and not TR.tap:isEnabled() then TR.tap:start() end
  end)
  TR.saver = hs.timer.doEvery(SAVE_EVERY_SEC, save)
  TR.menu = hs.menubar.new()
  if TR.menu then TR.menu:setMenu(menuItems) end
  TR.updateMenu()
  -- Save before Hammerspoon reloads or quits.
  TR.oldShutdown = hs.shutdownCallback
  hs.shutdownCallback = function()
    save()
    if TR.oldShutdown then TR.oldShutdown() end
  end
end

TR.save = save
TR._state = state
TR._onKey = onKey
TR.start()
TypingRhythm = TR   -- global handle, so the timers and tap aren't garbage-collected
return TR
