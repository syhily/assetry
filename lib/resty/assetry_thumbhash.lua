-- thumbhash_jit.lua
-- LuaJIT + OpenResty friendly ThumbHash implementation (ported + optimized)
local ffi = require "ffi"
local bit = require "bit"
local math = math
local cos = math.cos
local floor = math.floor
local abs = math.abs

local PI = math.pi

local _M = {}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- Helper: create/reserve a C buffer for output bytes (hash are small; 1024 is safe)
local function new_out_buf(cap)
  cap = cap or 1024
  return ffi.new("uint8_t[?]", cap), cap
end

----------------------------------------------------------------
-- rgba_to_thumb_hash (expects rgba as a Lua string of length w*h*4)
-- returns binary string (Lua string) with the thumbhash bytes
----------------------------------------------------------------
function _M.rgba_to_thumb_hash(w, h, rgba_str)
  assert(w <= 100 and h <= 100, "max 100x100")
  local npx = w * h
  assert(#rgba_str == npx * 4, "rgba length mismatch")

  -- cast input string to const uint8_t*
  local in_ptr = ffi.cast("const uint8_t *", rgba_str)

  -- compute average color (premultiplied handling as in Rust)
  local avg_r, avg_g, avg_b, avg_a = 0.0, 0.0, 0.0, 0.0
  for i = 0, npx - 1 do
    local base = i * 4
    local r = in_ptr[base + 0]
    local g = in_ptr[base + 1]
    local b = in_ptr[base + 2]
    local a = in_ptr[base + 3] / 255.0
    avg_r = avg_r + (a / 255.0) * r
    avg_g = avg_g + (a / 255.0) * g
    avg_b = avg_b + (a / 255.0) * b
    avg_a = avg_a + a
  end
  if avg_a > 0.0 then
    avg_r = avg_r / avg_a
    avg_g = avg_g / avg_a
    avg_b = avg_b / avg_a
  end

  local has_alpha = (avg_a < (npx))
  local l_limit = has_alpha and 5 or 7
  local lx = math.max(1, math.floor((l_limit * w) / math.max(w, h) + 0.5))
  local ly = math.max(1, math.floor((l_limit * h) / math.max(w, h) + 0.5))

  -- allocate float buffers for channels (ffi arrays)
  local L = ffi.new("float[?]", npx)
  local P = ffi.new("float[?]", npx)
  local Q = ffi.new("float[?]", npx)
  local A = ffi.new("float[?]", npx)

  -- convert RGBA -> LPQA (composite atop average color)
  for i = 0, npx - 1 do
    local base = i * 4
    local pr = in_ptr[base + 0]
    local pg = in_ptr[base + 1]
    local pb = in_ptr[base + 2]
    local pa = in_ptr[base + 3] / 255.0
    local r = avg_r * (1.0 - pa) + (pa / 255.0) * pr
    local g = avg_g * (1.0 - pa) + (pa / 255.0) * pg
    local b = avg_b * (1.0 - pa) + (pa / 255.0) * pb
    L[i] = (r + g + b) / 3.0
    P[i] = (r + g) / 2.0 - b
    Q[i] = r - g
    A[i] = pa
  end

  -- encode_channel using DCT
  local function encode_channel(channel_ptr, nx, ny)
    local dc = 0.0
    local ac = {} -- Lua table for variable-length ACs (small)
    local scale = 0.0
    local fx = ffi.new("float[?]", w) -- pre-alloc per call (w <= 100)
    for cy = 0, ny - 1 do
      local cx = 0
      while cx * ny < nx * (ny - cy) do
        -- precompute fx for this cx
        for x = 0, w - 1 do
          fx[x] = cos(PI / w * cx * (x + 0.5))
        end
        local f = 0.0
        for y = 0, h - 1 do
          local fy = cos(PI / h * cy * (y + 0.5))
          local base = y * w
          for x = 0, w - 1 do
            f = f + channel_ptr[base + x] * fx[x] * fy
          end
        end
        f = f / (w * h)
        if cx > 0 or cy > 0 then
          ac[#ac + 1] = f
          local af = abs(f)
          if af > scale then scale = af end
        else
          dc = f
        end
        cx = cx + 1
      end
    end
    if scale > 0.0 then
      for i = 1, #ac do
        ac[i] = 0.5 + 0.5 * ac[i] / scale
      end
    end
    return dc, ac, scale
  end

  local l_dc, l_ac, l_scale = encode_channel(L, math.max(3, lx), math.max(3, ly))
  local p_dc, p_ac, p_scale = encode_channel(P, 3, 3)
  local q_dc, q_ac, q_scale = encode_channel(Q, 3, 3)
  local a_dc, a_ac, a_scale = 1.0, {}, 1.0
  if has_alpha then
    a_dc, a_ac, a_scale = encode_channel(A, 5, 5)
  end

  -- write header fields (bit ops via bit)
  local is_landscape = (w > h)
  local header24 =
    floor(63.0 * l_dc + 0.5)
    + bit.lshift(floor(31.5 + 31.5 * p_dc + 0.5), 6)
    + bit.lshift(floor(31.5 + 31.5 * q_dc + 0.5), 12)
    + bit.lshift(floor(31.0 * l_scale + 0.5), 18)
    + (has_alpha and bit.lshift(1, 23) or 0)

  local header16 =
    (is_landscape and ly or lx)
    + bit.lshift(floor(63.0 * p_scale + 0.5), 3)
    + bit.lshift(floor(63.0 * q_scale + 0.5), 9)
    + (is_landscape and bit.lshift(1, 15) or 0)

  local out_buf, _ = new_out_buf(1024)
  local out_len = 0
  local function push_byte(b)
    out_len = out_len + 1
    out_buf[out_len - 1] = bit.band(b, 0xFF)
  end

  push_byte(bit.band(header24, 255))
  push_byte(bit.band(bit.rshift(header24, 8), 255))
  push_byte(bit.band(bit.rshift(header24, 16), 255))
  push_byte(bit.band(header16, 255))
  push_byte(bit.band(bit.rshift(header16, 8), 255))

  local is_odd = false
  if has_alpha then
    local hb = floor(15.0 * a_dc + 0.5) + bit.lshift(floor(15.0 * a_scale + 0.5), 4)
    push_byte(hb)
  end

  -- helper to write ACs (packs nibbles)
  local function write_ac_vec(vec)
    for i = 1, #vec do
      local u = floor(15.0 * vec[i] + 0.5)
      if is_odd then
        -- set upper nibble of last byte
        local last_idx = out_len - 1
        out_buf[last_idx] = bit.band(out_buf[last_idx] + bit.lshift(u, 4), 0xFF)
      else
        push_byte(u)
      end
      is_odd = not is_odd
    end
  end

  write_ac_vec(l_ac)
  write_ac_vec(p_ac)
  write_ac_vec(q_ac)
  if has_alpha then write_ac_vec(a_ac) end

  -- return as Lua string
  return ffi.string(out_buf, out_len)
end

----------------------------------------------------------------
-- thumb_hash_to_approximate_aspect_ratio
----------------------------------------------------------------
function _M.thumb_hash_to_approximate_aspect_ratio(hash_str)
  if #hash_str < 5 then return nil, "hash too short" end
  local hptr = ffi.cast("const uint8_t *", hash_str)
  local b2 = hptr[2]
  local has_alpha = bit.band(b2, 0x80) ~= 0
  local l_max = has_alpha and 5 or 7
  local l_min = bit.band(hptr[3], 7)
  local is_landscape = bit.band(hptr[4], 0x80) ~= 0
  local lx = is_landscape and l_max or l_min
  local ly = is_landscape and l_min or l_max
  return lx / ly
end

----------------------------------------------------------------
-- thumb_hash_to_rgba (decode)
-- returns w, h, rgba_string
----------------------------------------------------------------
function _M.thumb_hash_to_rgba(hash_str)
  if #hash_str < 5 then return nil, "hash too short" end
  local hptr = ffi.cast("const uint8_t *", hash_str)

  -- reuse aspect ratio helper
  local ratio = _M.thumb_hash_to_approximate_aspect_ratio(hash_str)
  if not ratio then return nil, "bad aspect" end

  -- read header bytes sequentially
  local idx = 0
  local function rb() local v = hptr[idx]; idx = idx + 1; return v end
  local b0 = rb(); local b1 = rb(); local b2 = rb()
  local header24 = b0 + bit.lshift(b1, 8) + bit.lshift(b2, 16)
  local b3 = rb(); local b4 = rb()
  local header16 = b3 + bit.lshift(b4, 8)

  local l_dc = bit.band(header24, 63) / 63.0
  local p_dc = (bit.band(bit.rshift(header24, 6), 63) / 31.5) - 1.0
  local q_dc = (bit.band(bit.rshift(header24, 12), 63) / 31.5) - 1.0
  local l_scale = bit.band(bit.rshift(header24, 18), 31) / 31.0
  local has_alpha = bit.band(bit.rshift(header24, 23), 1) ~= 0

  local p_scale = bit.band(bit.rshift(header16, 3), 63) / 63.0
  local q_scale = bit.band(bit.rshift(header16, 9), 63) / 63.0
  local is_landscape = bit.band(bit.rshift(header16, 15), 1) ~= 0

  local l_max = has_alpha and 5 or 7
  local lx = math.max(3, (is_landscape and l_max or bit.band(header16, 7)))
  local ly = math.max(3, (is_landscape and bit.band(header16, 7) or l_max))

  local a_dc, a_scale = 1.0, 1.0
  if has_alpha then
    local h8 = rb()
    a_dc = bit.band(h8, 15) / 15.0
    a_scale = bit.rshift(h8, 4) / 15.0
  end

  -- decode AC channels (reads packed nibbles)
  local prev_nibble = nil
  local function read_ac_channel(nx, ny, scale)
    local ac = {}
    for cy = 0, ny - 1 do
      local cx = (cy > 0) and 0 or 1
      while cx * ny < nx * (ny - cy) do
        local bits
        if prev_nibble ~= nil then
          bits = prev_nibble
          prev_nibble = nil
        else
          local byte = rb()
          prev_nibble = bit.rshift(byte, 4)
          bits = bit.band(byte, 15)
        end
        ac[#ac + 1] = (bits / 7.5 - 1.0) * scale
        cx = cx + 1
      end
    end
    return ac
  end

  local l_ac = read_ac_channel(lx, ly, l_scale)
  local p_ac = read_ac_channel(3, 3, p_scale * 1.25)
  local q_ac = read_ac_channel(3, 3, q_scale * 1.25)
  local a_ac = has_alpha and read_ac_channel(5, 5, a_scale) or {}

  -- dimensions for rendering
  local w, h
  if ratio > 1.0 then
    w = 32
    h = floor(32.0 / ratio + 0.5)
  else
    w = floor(32.0 * ratio + 0.5)
    h = 32
  end

  -- prepare output buffer
  local out_n = w * h * 4
  local out_buf = ffi.new("uint8_t[?]", out_n)
  local oidx = 0

  -- fx/fy buffers (max 7)
  local fx = ffi.new("float[7]")
  local fy = ffi.new("float[7]")

  -- decode per pixel
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local L = l_dc
      local P = p_dc
      local Q = q_dc
      local A = a_dc

      -- precompute fx/fy
      local maxcx = math.max(lx, has_alpha and 5 or 3)
      local maxcy = math.max(ly, has_alpha and 5 or 3)
      for cx = 0, maxcx - 1 do fx[cx] = cos(PI / w * (x + 0.5) * cx) end
      for cy = 0, maxcy - 1 do fy[cy] = cos(PI / h * (y + 0.5) * cy) end

      -- L channel
      do
        local j = 1
        for cy = 0, ly - 1 do
          local cx = (cy > 0) and 0 or 1
          local fy2 = fy[cy] * 2.0
          while cx * ly < lx * (ly - cy) do
            L = L + l_ac[j] * fx[cx] * fy2
            j = j + 1
            cx = cx + 1
          end
        end
      end

      -- P/Q channels
      do
        local j = 1
        for cy = 0, 2 do
          local cx = (cy > 0) and 0 or 1
          local fy2 = fy[cy] * 2.0
          while cx < 3 - cy do
            local f = fx[cx] * fy2
            P = P + p_ac[j] * f
            Q = Q + q_ac[j] * f
            j = j + 1
            cx = cx + 1
          end
        end
      end

      -- Alpha
      if has_alpha then
        local j = 1
        for cy = 0, 4 do
          local cx = (cy > 0) and 0 or 1
          local fy2 = fy[cy] * 2.0
          while cx < 5 - cy do
            A = A + a_ac[j] * fx[cx] * fy2
            j = j + 1
            cx = cx + 1
          end
        end
      end

      local b = L - (2.0/3.0) * P
      local r = (3.0 * L - b + Q) / 2.0
      local g = r - Q

      -- write clamped bytes
      out_buf[oidx]     = floor(clamp(r,0,1) * 255.0 + 0.5); oidx = oidx + 1
      out_buf[oidx]     = floor(clamp(g,0,1) * 255.0 + 0.5); oidx = oidx + 1
      out_buf[oidx]     = floor(clamp(b,0,1) * 255.0 + 0.5); oidx = oidx + 1
      out_buf[oidx]     = floor(clamp(A,0,1) * 255.0 + 0.5); oidx = oidx + 1
    end
  end

  return w, h, ffi.string(out_buf, out_n)
end

return _M
