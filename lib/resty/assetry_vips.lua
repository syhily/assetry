local ffi = require "ffi"
local util = require "resty.assetry_util"

local table_unpack = table.unpack
local table_insert = table.insert

-- Load VIPS
local lib_assetry = ffi.load("AssetryHelper")

-- vips definitions
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
    GravitySmart,
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

unsigned char *Assetry_to_buffer(Assetry *img, const char *format, int quality, bool strip, size_t *len);

void Assetry_gc(Assetry *img);

void Assetry_gc_buffer(void *buf);

]]

local mt = {
    -- Resize mode to string
    ResizeMode = { fill = lib_assetry.ResizeModeFill, fit = lib_assetry.ResizeModeFit, crop = lib_assetry.ResizeModeCrop },

    -- Gravity to string
    Gravity = {
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
    },

    -- Static calls
    init = lib_assetry.assetry_ginit,
    shutdown = lib_assetry.assetry_gshutdown,

    new_from_buffer = function(str, len)
        local buf = ffi.cast("void *", str)
        local rc = lib_assetry.Assetry_new_from_buffer(buf, len)

        if rc == ffi.NULL then
            return nil, "Error loading image"
        end

        return ffi.gc(rc, lib_assetry.Assetry_gc)
    end,

    get_formats = function()
        local formats = {}

        local len = ffi.new "size_t[1]"
        local arr = lib_assetry.assetry_get_formats(len)

        local num = tonumber(len[0])

        if num == 0 then
            return formats
        end

        for i = 0, num - 1 do
            formats[ffi.string(arr[i])] = true
        end

        return formats
    end,

    -- Methods
    get_width = lib_assetry.Assetry_get_width,
    get_height = lib_assetry.Assetry_get_height,

    resize = lib_assetry.Assetry_resize,
    crop = lib_assetry.Assetry_crop,
    round = lib_assetry.Assetry_round,
    blur = lib_assetry.Assetry_blur,

    set_background_color = lib_assetry.Assetry_set_background_color,

    to_buffer = function(o, format, quality, strip)
        local buf_size = ffi.new "size_t[1]"
        local rc = lib_assetry.Assetry_to_buffer(o, format, quality, strip, buf_size)

        if rc == ffi.NULL then
            return nil, "Error writing image"
        end

        local buf = ffi.gc(rc, lib_assetry.Assetry_gc_buffer)

        return ffi.string(buf, buf_size[0])
    end
}
mt.__index = mt

Assetry = ffi.metatype("Assetry", mt)

-- Higher level Lua interface
local _M = { Assetry = Assetry, opts = {} }

function _M.init(opts)
    assert(Assetry.init("resty-assetry") == true)
    assert(opts.default_format)
    assert(opts.default_quality)
    assert(opts.default_strip ~= nil)

    _M.opts = opts
end

function _M.get_formats()
    return Assetry.get_formats()
end

local transform = {}

transform.resize = function(image, params)

    setmetatable(params, { __index = { w = 0, h = 0, m = lib_assetry.ResizeModeFit } })

    local width = params.w
    local height = params.h
    local mode = params.m

    if type(mode) == "string" then
        mode = Assetry.ResizeMode[mode]
    end

    if not mode then
        return nil, "unknown mode"
    end

    return image:resize(width or 0, height or 0, mode)

end

transform.crop = function(image, params)
    setmetatable(params, { __index = { w = 0, h = 0, g = lib_assetry.GravityCenter } })

    local width = params.w
    local height = params.h
    local gravity = params.g

    if type(gravity) == "string" then
        gravity = Assetry.Gravity[gravity]
    end

    if not gravity then
        return nil, "unknown gravity"
    end

    return image:crop(width or 0, height or 0, gravity)

end

transform.round = function(image, params)
    setmetatable(params, { __index = { x = 0, y = 0, p = 0 } })

    local x = params.x
    local y = params.y
    local p = params.p

    if p > 0 then
        local width = image:get_width()
        local height = image:get_height()

        x = width / 2
        y = width / 2
    end

    return image:round(x, y)
end

transform.blur = function(image, params)
    setmetatable(params, { __index = { s = 0.0 } })

    local s = params.s
    return image:blur(s)
end

function _M.operate(src_image, manifest)
    local image = Assetry.new_from_buffer(src_image, src_image:len())

    if not image then
        return nil, "failed to read the image"
    end

    if manifest.option and manifest.option.c then
        local color = manifest.option.c
        local rc = image:set_background_color(color.r, color.g, color.b)

        if not rc then
            return nil, "failed to set background color"
        end
    end

    for _, entry in ipairs(manifest.operations) do
        local fn = transform[entry.name]
        assert(fn)

        if fn then
            local ok, err = fn(image, entry.params)

            if not ok then
                return nil, "failed to execute " .. entry.name .. ": " .. (err or "no error message")
            end
        end
    end

    return image:to_buffer(manifest.format.t, manifest.format.q, manifest.format.s), manifest.format.t
end

return _M
