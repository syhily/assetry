local ffi = require "ffi"

-- Load native library
local lib_assetry = ffi.load("AssetryHelper")

-- ---------------------------------------------------------------------------
-- FFI Definitions
-- ---------------------------------------------------------------------------
ffi.cdef [[
typedef enum {
    ResizeModeFill,
    ResizeModeFit,
    ResizeModeCrop
} ResizeMode;

typedef enum {
    GravityNorth,
    GravityNorthEast,
    GravityEast,
    GravitySouthEast,
    GravitySouth,
    GravitySouthWest,
    GravityWest,
    GravityNorthWest,
    GravityCenter,
    GravitySmart
} Gravity;

typedef struct Assetry Assetry;

bool assetry_ginit(const char *name);
const char **assetry_get_formats(size_t *num_formats);
void assetry_gshutdown();

Assetry *Assetry_new_from_buffer(unsigned char *buf, size_t len);

int Assetry_get_width(Assetry *img);
int Assetry_get_height(Assetry *img);

bool Assetry_resize(Assetry *img, int width, int height, ResizeMode);
bool Assetry_crop(Assetry *img, int width, int height, Gravity);
bool Assetry_round(Assetry *img, int x, int y);
bool Assetry_blur(Assetry *img, double sigma);

bool Assetry_set_background_color(Assetry *img, int r, int g, int b);

unsigned char *Assetry_to_buffer(Assetry *img, const char *format, int quality,
                                 bool strip, size_t *len);

void Assetry_gc(Assetry *img);
void Assetry_gc_buffer(void *buf);
]]

-- ---------------------------------------------------------------------------
-- Metatype and Methods
-- ---------------------------------------------------------------------------

local mt = {}
mt.__index = mt

-- Enum tables
mt.ResizeMode = {
    fill = lib_assetry.ResizeModeFill,
    fit = lib_assetry.ResizeModeFit,
    crop = lib_assetry.ResizeModeCrop
}

mt.Gravity = {
    n = lib_assetry.GravityNorth,
    ne = lib_assetry.GravityNorthEast,
    e = lib_assetry.GravityEast,
    se = lib_assetry.GravitySouthEast,
    s = lib_assetry.GravitySouth,
    sw = lib_assetry.GravitySouthWest,
    w = lib_assetry.GravityWest,
    nw = lib_assetry.GravityNorthWest,
    center = lib_assetry.GravityCenter,
    smart = lib_assetry.GravitySmart
}

-- Static methods
mt.init = lib_assetry.assetry_ginit
mt.shutdown = lib_assetry.assetry_gshutdown
mt.get_width = lib_assetry.Assetry_get_width
mt.get_height = lib_assetry.Assetry_get_height
mt.resize = lib_assetry.Assetry_resize
mt.crop = lib_assetry.Assetry_crop
mt.round = lib_assetry.Assetry_round
mt.blur = lib_assetry.Assetry_blur
mt.set_background_color = lib_assetry.Assetry_set_background_color

-- New from buffer wrapper
function mt.new_from_buffer(str, len)
    local buf = ffi.cast("unsigned char*", str)
    local rc = lib_assetry.Assetry_new_from_buffer(buf, len)

    if rc == ffi.NULL then
        return nil, "Error loading image"
    end

    return ffi.gc(rc, lib_assetry.Assetry_gc)
end

-- Fetch supported formats
function mt.get_formats()
    local len_ptr = ffi.new("size_t[1]")
    local arr = lib_assetry.assetry_get_formats(len_ptr)
    local n = tonumber(len_ptr[0])

    local out = {}
    for i = 0, n - 1 do
        out[ffi.string(arr[i])] = true
    end

    return out
end

-- Convert image to buffer
function mt.to_buffer(o, format, quality, strip)
    local len_ptr = ffi.new("size_t[1]")
    local rc = lib_assetry.Assetry_to_buffer(o, format, quality, strip, len_ptr)

    if rc == ffi.NULL then
        return nil, "Error writing image"
    end

    local buf = ffi.gc(rc, lib_assetry.Assetry_gc_buffer)
    return ffi.string(buf, len_ptr[0])
end

-- Create metatype
local Assetry = ffi.metatype("Assetry", mt)

-- ---------------------------------------------------------------------------
-- High-level API
-- ---------------------------------------------------------------------------

local _M = { Assetry = Assetry, opts = {} }

function _M.init(opts)
    assert(mt.init("resty-assetry"))
    assert(opts.default_format)
    assert(opts.default_quality)
    assert(opts.default_strip ~= nil)

    _M.opts = opts
end

function _M.get_formats()
    return Assetry.get_formats()
end

-- ---------------------------------------------------------------------------
-- Image Transform Operations
-- ---------------------------------------------------------------------------

local transform = {}

function transform.resize(img, params)
    params = setmetatable(params or {},
                          { __index = { w = 0, h = 0, m = lib_assetry.ResizeModeFit } })

    local w = params.w
    local h = params.h
    local mode = params.m

    if type(mode) == "string" then
        mode = Assetry.ResizeMode[mode]
    end

    if not mode then
        return nil, "unknown mode"
    end

    return img:resize(w, h, mode)
end

function transform.crop(img, params)
    params = setmetatable(params or {},
                          { __index = { w = 0, h = 0, g = lib_assetry.GravityCenter } })

    local w = params.w
    local h = params.h
    local g = params.g

    if type(g) == "string" then
        g = Assetry.Gravity[g]
    end

    if not g then
        return nil, "unknown gravity"
    end

    return img:crop(w, h, g)
end

function transform.round(img, params)
    params = setmetatable(params or {}, { __index = { x = 0, y = 0, p = 0 } })

    local x = params.x
    local y = params.y
    local p = params.p

    if p > 0 then
        local w = img:get_width()
        local h = img:get_height()
        local R = (w < h) and w or h
        x = R / 2
        y = R / 2
    end

    return img:round(x, y)
end

function transform.blur(img, params)
    params = setmetatable(params or {}, { __index = { s = 0.0 } })
    return img:blur(params.s)
end

-- ---------------------------------------------------------------------------
-- Dispatcher
-- ---------------------------------------------------------------------------

function _M.operate(src_image, manifest)
    local img = Assetry.new_from_buffer(src_image, #src_image)
    if not img then
        return nil, "failed to read the image"
    end

    if manifest.option and manifest.option.c then
        local c = manifest.option.c
        if not img:set_background_color(c.r, c.g, c.b) then
            return nil, "failed to set background color"
        end
    end

    for _, entry in ipairs(manifest.operations) do
        local fn = transform[entry.name]
        if not fn then
            return nil, "unknown operation " .. entry.name
        end

        local ok, err = fn(img, entry.params or {})
        if not ok then
            return nil, "failed to execute " .. entry.name .. ": " .. (err or "unknown error")
        end
    end

    local buf, err = img:to_buffer(manifest.format.t, manifest.format.q, manifest.format.s)

    if not buf then
        return nil, err
    end

    return buf, manifest.format.t
end

return _M
