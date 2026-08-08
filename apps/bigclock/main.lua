-- Big Clock - a store app.
--
-- Nothing about this file knows it was downloaded. It is the same contract as
-- a seeded app; only the delivery differs.
--
-- Declares "clock" in the catalog entry, so sys.time() is granted. Without
-- that declaration it would return nil, and the nil branch below is what the
-- app shows - which is also what happens on a watch whose RTC is missing.

local t

function on_enter()
  t = sys.time()
end

function update(now)
  local fresh = sys.time()
  if fresh and (not t or fresh.second ~= t.second) then
    t = fresh
    dirty()
  end
end

function render()
  gfx.clear(theme.BG)
  ui.header('CLOCK')

  if not t then
    ui.center_text('no clock', screen.h // 2 - 8, 2, theme.WARN)
    ui.hint('swipe up to go back')
    return
  end

  local hh = string.format('%02d:%02d', t.hour, t.minute)
  ui.center_text(hh, 90, 4, t.valid and theme.TEXT or theme.TEXT_DIM)
  ui.center_text(string.format('%02d', t.second), 140, 2, theme.ACCENT)
  ui.center_text(t.day_name .. ' ' .. t.month_name .. ' ' .. t.day, 176, 1, theme.TEXT_DIM)

  if not t.valid then
    -- The clock reports whether it has ever been set. Showing a confident
    -- wrong time is worse than saying so.
    ui.center_text('time not set', 200, 1, theme.WARN)
  end

  ui.hint('swipe up to go back')
end
