-- Snake, in Lua.
--
-- A faithful port of the compiled AppSnake.h, using nothing but the public
-- bindings: same board, same pacing, same screens, same gestures. If something
-- here needed a binding that did not exist, the API was incomplete - that is
-- what this app is for.
--
-- EDGES WRAP. On a 1.69" panel a wall death is over before you have seen it
-- coming, so running off one edge reappears on the other. There is no border
-- drawn, because there is no wall.
--
-- GESTURES. All four swipes are consumed while playing, which means swipe-up
-- cannot be the way out - the system only falls through to back() on an
-- UNHANDLED swipe-up, and here it is a turn. So a long press pauses, and the
-- pause card carries the exit. In every state where the game is NOT running,
-- swipe-up is released back to the system by returning false.
--
-- STATE. A ring buffer of cells plus an occupancy grid. The grid is the point:
-- self-collision and "is this square free for food" are both one table lookup
-- instead of a walk down a 300-segment body.

local COLS, ROWS = 18, 19
local CELL       = 12
local HEADER_Y   = 14
local HEADER_H   = 34
local BOARD_X    = (screen.w - COLS * CELL) // 2   -- 12
local BOARD_Y    = HEADER_H                        -- 34 .. 262
local MAX_LEN    = COLS * ROWS                     -- 342

-- 170ms is about as slow as feels deliberate rather than sluggish; 70ms is the
-- floor where a swipe still lands in the right cell. The step is per apple, so
-- the ramp is earned rather than timed.
local TICK_START = 170
local TICK_MIN = 70
local TICK_STEP = 4

local state, last_tick
local bufx, bufy, grid, head, len
local dirx, diry, pendx, pendy, pending
local foodx, foody 
local score, best
local btn_a, btn_b

local function gi(x, y) return y * COLS + x end

local function tick_interval()
  local drop = score * TICK_STEP
  if drop >= TICK_START - TICK_MIN then return TICK_MIN end
  return TICK_START - drop
end

-- Picks uniformly among the FREE cells rather than retrying random squares.
-- Retrying is fine early and pathological late, when the snake owns most of the
-- board and a blind guess almost always lands on a body segment.
local function place_food()
  local free = MAX_LEN - len
  if free <= 0 then return end
  local pick = math.random(0, free - 1)
  for x = 0, COLS - 1 do
    for y = 0, ROWS - 1 do
      if not grid[gi(x, y)] then
        if pick == 0 then foodx, foody = x, y return end
        pick = pick - 1
      end
    end
  end
end

local function reset()
  grid = {}
  bufx, bufy = {}, {}
  len   = 3
  score = 0
  dirx, diry   = 1, 0
  pendx, pendy = 1, 0
  pending = false

  -- Start mid-board facing right, tail trailing behind the head.
  local cx, cy = COLS // 2, ROWS // 2
  head = 0
  for i = 0, len - 1 do
    local idx = (MAX_LEN - i) % MAX_LEN     -- head at 0
    bufx[idx] = cx - i
    bufy[idx] = cy
    grid[gi(cx - i, cy)] = true
  end

  place_food()
  state = 'playing'
  last_tick = sys.uptime()
end

local function resume()
  state = 'playing'
  last_tick = sys.uptime()   -- don't burn a tick on the pause gap
  dirty()
end

local function game_over()
  state = 'over'
  if score > best then
    best = score
    -- One write per game, and only on a genuine record. Writing the score
    -- every death would grind the flash for nothing.
    store.set('hi', best)
  end
  dirty()
end

-- Queue a turn. Validated against the PENDING direction, not the live one: two
-- swipes inside a single tick would otherwise let you fold back into your own
-- neck (right, then up, then left before the snake has moved).
local function turn(dx, dy)
  if pendx == -dx and pendy == -dy then return end   -- no 180s
  if pendx ==  dx and pendy ==  dy then return end   -- no-op
  pendx, pendy = dx, dy
  pending = true
end

local function step()
  if pending then
    dirx, diry = pendx, pendy
    pending = false
  end

  local nx = bufx[head] + dirx
  local ny = bufy[head] + diry

  -- Wrap, rather than die, at every edge.
  if nx < 0 then nx = COLS - 1 elseif nx >= COLS then nx = 0 end
  if ny < 0 then ny = ROWS - 1 elseif ny >= ROWS then ny = 0 end

  local eating = (nx == foodx and ny == foody)

  -- Vacate the tail BEFORE testing the new head. Chasing your own tail into the
  -- square it is leaving this same tick is legal, and checking in the other
  -- order would kill you for it.
  if not eating then
    local tail = (head + MAX_LEN - (len - 1)) % MAX_LEN
    grid[gi(bufx[tail], bufy[tail])] = nil
    len = len - 1
  end

  if grid[gi(nx, ny)] then
    game_over()
    return
  end

  head = (head + 1) % MAX_LEN
  bufx[head] = nx
  bufy[head] = ny
  grid[gi(nx, ny)] = true
  len = len + 1

  if eating then
    score = score + 1
    if len >= MAX_LEN then game_over() return end   -- board filled: a win
    place_food()
  end
end

function on_enter()
  best  = store.get('hi', 0)
  score = 0
  state = 'ready'
end

function on_exit()
  -- Leaving mid-run counts as ending it. Coming back to a half-eaten board you
  -- had forgotten the direction of is worse than just starting over.
  if state == 'playing' or state == 'paused' then state = 'ready' end
end

function update(now)
  if state ~= 'playing' then return end -- if state does not equal 'playing', return
  if now - last_tick < tick_interval() then return end -- else if now minus last_tick is less than tick_interval(), return
  last_tick = now -- update last_tick to now
  step() -- call step() to update the game state
  dirty() -- mark the screen as needing to be redrawn
end

-- ---- drawing --------------------------------------------------------------
-- Everything is inset by theme.PAD. The panel's corners are rounded, so the far
-- corners of a full-bleed 240x280 rectangle are not actually on the glass.
-- Treat PAD as the safe area, not decoration.

local function draw_header()
  gfx.text('SCORE ' .. score, theme.PAD, HEADER_Y, 1, theme.TEXT)
  ui.right_text('BEST ' .. best, screen.w - theme.PAD, HEADER_Y, 1, theme.TEXT_DIM)
  gfx.line(theme.PAD, HEADER_H - 6, screen.w - theme.PAD - 1, HEADER_H - 6, theme.SURFACE)
end

local function draw_board()
  -- Food first, so a head landing on it this frame paints over it cleanly.
  gfx.circle(BOARD_X + foodx * CELL + CELL // 2,
             BOARD_Y + foody * CELL + CELL // 2,
             CELL // 2 - 1, theme.WARN, true)

  for i = 0, len - 1 do
    local idx = (head + MAX_LEN - i) % MAX_LEN
    local px = BOARD_X + bufx[idx] * CELL
    local py = BOARD_Y + bufy[idx] * CELL
    if i == 0 then
      gfx.fill_round_rect(px, py, CELL - 1, CELL - 1, 3, theme.ACCENT)
    else
      gfx.fill_rect(px + 1, py + 1, CELL - 3, CELL - 3, theme.GOOD)
    end
  end
end

local function draw_ready()
  ui.center_text('SNAKE', 96, 3, theme.GOOD)
  ui.center_text('tap to start',      146, 1, theme.TEXT_DIM)
  ui.center_text('swipe to steer',    172, 1, theme.TEXT_DIM)
  ui.center_text('edges wrap around', 190, 1, theme.TEXT_DIM)
  ui.center_text('hold to pause',     216, 1, theme.TEXT_DIM)
end

-- Full-width buttons rather than a side-by-side pair: the touch chip reports a
-- tap at the release point, which drifts a few pixels off where you aimed, and
-- a 168x30 target absorbs that where a half-width one would not.
local function big_button(y, label, filled)
  return ui.button(theme.PAD + 12, y, screen.w - (theme.PAD + 12) * 2, 30,
                   label, filled, 1)
end

local function draw_paused()
  local top, h = 86, 124
  ui.panel(theme.PAD, top, screen.w - theme.PAD * 2, h)
  ui.center_text('PAUSED', top + 16, 2, theme.TEXT)
  btn_a = big_button(top + 46, 'RESUME', true)
  btn_b = big_button(top + 84, 'EXIT',   false)
end

local function draw_game_over()
  local top, h = 62, 158
  ui.panel(theme.PAD, top, screen.w - theme.PAD * 2, h)

  local won    = (len >= MAX_LEN)
  local record = (score == best and score > 0)

  ui.center_text(won and 'YOU WIN' or 'GAME OVER', top + 14, 2,
                 won and theme.GOOD or theme.WARN)
  ui.center_text(tostring(score), top + 42, 3, theme.TEXT)
  if record then
    ui.center_text('NEW BEST', top + 72, 1, theme.ACCENT)
  end

  btn_a = big_button(top + 84,  'PLAY AGAIN', true)
  btn_b = big_button(top + 120, 'EXIT',       false)
end

function render()
  gfx.clear(theme.BG)
  draw_header()

  if state == 'ready' then
    draw_ready()                        -- no board: nothing has started yet
  elseif state == 'playing' then
    draw_board()
  elseif state == 'paused' then
    draw_board() draw_paused()
  elseif state == 'over' then
    draw_board() draw_game_over()
  end
end

-- ---- input ----------------------------------------------------------------

local function tapped(rect, x, y)
  -- Slop, for the same reason the buttons are full width.
  return rect ~= nil and ui.hit(x, y, rect, 6)
end

function on_event(kind, x, y)
  if state == 'ready' then
    if kind == 'tap'        then reset() dirty() return true end
    if kind == 'long_press' then quit() return true end
    return false                        -- swipe-up bubbles to system back

  elseif state == 'playing' then
    -- Left/right are crossed relative to the naive mapping on purpose: the
    -- touch chip reports in its own physical frame, and Input.h's transform
    -- gets the axis right but not the handedness at this rotation. Verified on
    -- hardware; the compiled Snake carries the same correction.
    if kind == 'swipe_up'    then turn( 0, -1) return true end
    if kind == 'swipe_down'  then turn( 0,  1) return true end
    if kind == 'swipe_left'  then turn( 1,  0) return true end
    if kind == 'swipe_right' then turn(-1,  0) return true end

    if kind == 'long_press' then
      state = 'paused'
      dirty()
      return true
    end

    -- A bare tap does nothing mid-run. Pausing on a stray touch while threading
    -- a gap is worse than not pausing at all.
    return true

  elseif state == 'paused' then
    if kind == 'tap' then
      if tapped(btn_a, x, y) then resume() return true end
      if tapped(btn_b, x, y) then quit()   return true end
      return true                       -- swallow misses so a fat tap can't restart
    end
    if kind == 'long_press' then resume() return true end
    return false

  elseif state == 'over' then
    if kind == 'tap' then
      if tapped(btn_a, x, y) then reset() dirty() return true end
      if tapped(btn_b, x, y) then quit()  return true end
      return true
    end
    if kind == 'long_press' then quit() return true end
    return false
  end

  return false
end
