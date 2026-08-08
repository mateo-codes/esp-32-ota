-- Battery - a store app.
--
-- Declares "battery" in the catalog entry, so sys.battery() is granted.

local b

function on_enter()
  b = sys.battery()
end

function update(now)
  local fresh = sys.battery()
  if fresh and (not b or fresh.percent ~= b.percent) then
    b = fresh
    dirty()
  end
end

function render()
  gfx.clear(theme.BG)
  ui.header('BATTERY')

  if not b then
    ui.center_text('unavailable', screen.h // 2 - 8, 2, theme.WARN)
    ui.hint('swipe up to go back')
    return
  end

  local colour = theme.GOOD
  if b.percent < 20 then colour = theme.WARN
  elseif b.percent < 50 then colour = theme.ACCENT end

  ui.center_text(b.percent .. '%', 84, 4, colour)
  ui.progress_bar(theme.PAD, 140, screen.w - theme.PAD * 2, 18,
                  b.percent / 100, colour, theme.SURFACE, true)
  ui.center_text(string.format('%.2f V', b.volts), 176, 1, theme.TEXT_DIM)

  ui.hint('swipe up to go back')
end
