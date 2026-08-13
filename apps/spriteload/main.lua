-- Sprite Load -- the reference app for sidecar sprite files.
--
-- spritedemo (in lua/, seeded into the firmware) is the reference for the
-- OTHER way to ship sprites: base64 text pasted into main.lua, decoded with
-- sprite.decode(). Read that one first if you are drawing sprites at all.
-- This one covers the case spritedemo cannot: art too big to live inside the
-- script.
--
-- WHY THIS APP IS IN store-apps/ AND NOT lua/
-- It started seeded and was moved, which is the whole lesson. A seeded app's
-- assets are compiled into the FIRMWARE as byte arrays: these three frames
-- cost 55KB of every OTA image, carried by every watch that updates whether
-- or not anyone opens this app, plus ~530KB of generated C that the compiler
-- rebuilds every time. As a store app they cost the firmware nothing and land
-- on LittleFS only where someone installs them.
--
-- Seeding is for what must work on a watch that has never reached the store.
-- Art-heavy apps belong here.
--
-- WHAT IT COSTS INLINE
-- Three 120x120 frames as base64 in main.lua would be ~115KB of source, all
-- of it charged against STORE_MAX_SCRIPT. As .spr files they cost this script
-- nothing: main.lua stays 4KB of readable Lua, and the art is bounded only by
-- the asset budget.
--
-- The rule of thumb: icon-scale art stays inline (simpler, one file, nothing
-- to publish alongside). Large or numerous frames go in assets/.
--
-- MAKING THE FILES
--   python3 tools/png_to_sprite.py f1.png f2.png f3.png \
--       --raw --name frame -o store-apps/spriteload/assets/
--   python3 tools/generate_catalog.py
--
-- The .spr file carries its own width and height in an 8-byte header, so the
-- dimensions below are READ FROM THE FILE rather than typed here. That is the
-- point of the header: hand-typed dimensions drift from the art they describe,
-- and gfx.sprite cannot catch 120x120 typed where 100x144 was meant -- the
-- byte count matches, so it draws garbage rather than complaining.

local FRAME_FILES = { 'frame_1.spr', 'frame_2.spr', 'frame_3.spr' }
local FRAME_MS    = 180

local frames = {}      -- { data = <string>, w = <int>, h = <int> }
local err            -- set if anything failed to load; app shows it and stops
local current  = 1
local last     = 0
local paused   = false

function on_enter()
  -- LOAD ONCE. Same rule as sprite.decode(): never call this from render() or
  -- update(). Reading a file is far more expensive than decoding a string, and
  -- the whole reason the budget forgives filesystem time (see LuaVm.h) is that
  -- it expects this to happen here, a bounded number of times.
  frames = {}
  err = nil

  for i, name in ipairs(FRAME_FILES) do
    -- NOTE THE RETURN SHAPE: data, w, h on success -- but nil, message on
    -- failure. The second value is a width or an error string depending on
    -- the first, which is why this checks `data` before trusting `w`.
    local data, w, h = sprite.load(name)
    if not data then
      err = w                            -- `w` is the message here
      return
    end
    frames[i] = { data = data, w = w, h = h }
  end

  current = 1
  last = 0
end

function update(now)
  if err or paused or #frames == 0 then return end
  if now - last < FRAME_MS then return end
  last = now
  current = current % #frames + 1
  dirty()
end

function render()
  gfx.clear(theme.BG)
  ui.header('SPRITE LOAD')

  if err then
    ui.center_text('load failed', 90, 2, theme.WARN)
    -- The message is longer than one line at size 1, so it is left to wrap
    -- naturally rather than truncated -- when something has gone wrong the
    -- whole string is worth more than a tidy layout.
    ui.center_text(err, 120, 1, theme.TEXT_DIM)
    ui.hint('swipe up to go back')
    return
  end

  local f = frames[current]
  if not f then return end

  -- Centred from the dimensions the FILE reported, not from constants in this
  -- script. Swap the art for something a different size and this still works.
  local x = (screen.w - f.w) // 2
  local y = (screen.h - f.h) // 2 - 10
  gfx.sprite(f.data, x, y, f.w, f.h)

  ui.center_text(f.w .. 'x' .. f.h .. '  frame ' .. current .. '/' .. #frames,
                 screen.h - 58, 1, theme.TEXT_DIM)
  ui.hint(paused and 'tap to play' or 'tap to pause')
end

function on_event(kind)
  if kind == 'tap' then
    paused = not paused
    dirty()
    return true
  end
  return false   -- swipe up stays with the system, so back still works
end
