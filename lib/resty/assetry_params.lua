local util = require "resty.assetry_util"

local l_assert = assert
local l_insert = table.insert
local l_tonumber = tonumber
local l_pairs = pairs
local l_rawset = rawset
local l_setmetatable = setmetatable

local supported_operations = {
    CROP = "crop",
    BLUR = "blur",
    RESIZE = "resize",
    ROUND = "round",
    NAMED = "named",
    FORMAT = "format",
    OPTION = "option"
}

local supported_modes = { fit = true, fill = true, crop = true }

local supported_gravity = {
    n = true,
    ne = true,
    e = true,
    se = true,
    s = true,
    sw = true,
    w = true,
    nw = true,
    center = true,
    smart = true
}

local _M = { named_ops = {}, ops = {}, supported_formats = {}, opts = {} }

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function validate_always_valid()
    return true
end

local function to_boolean(str)
    if not str then
        return false
    end

    return (str == "1" or str == "true" or str == "yes")
end

local function parse_color(str)
    if not str then
        return nil, "empty color string"
    end

    local r, g, b

    if #str == 3 then
        r = l_tonumber("0x" .. str:sub(1, 1)) * 17
        g = l_tonumber("0x" .. str:sub(2, 2)) * 17
        b = l_tonumber("0x" .. str:sub(3, 3)) * 17

    elseif #str == 6 then
        r = l_tonumber("0x" .. str:sub(1, 2))
        g = l_tonumber("0x" .. str:sub(3, 4))
        b = l_tonumber("0x" .. str:sub(5, 6))

    else
        return nil, "malformed color string " .. str
    end

    return { r = r, g = g, b = b }
end

local function validate_width(width)
    return width and width > 0 and width < _M.opts.max_width
end

local function validate_height(height)
    return height and height > 0 and height < _M.opts.max_height
end

local function validate_sigma(sigma)
    return sigma ~= nil and sigma >= 0.0
end

local function validate_format(fmt)
    return fmt and _M.supported_formats[fmt] ~= nil
end

local function validate_resize_mode(str)
    return str and supported_modes[str] ~= nil
end

local function validate_gravity(str)
    return str and supported_gravity[str] ~= nil
end

local function validate_color(color)
    return
        color and color.r >= 0 and color.r <= 255 and color.g >= 0 and color.g <= 255 and color.b >=
            0 and color.b <= 255
end

-- Missing in original code
local function validate_percentage(v)
    return v and v >= 0 and v <= 100
end

-- Missing in original code
local function validate_name(name)
    return name ~= nil and name ~= ""
end

-- ---------------------------------------------------------------------------
-- Arg builders
-- ---------------------------------------------------------------------------
local function make_boolean_arg()
    return { convert_fn = to_boolean, validate_fn = validate_always_valid }
end

local function make_number_arg(validate_fn)
    return { convert_fn = l_tonumber, validate_fn = validate_fn }
end

local function make_string_arg(validate_fn)
    return { validate_fn = validate_fn }
end

local function make_color_arg(validate_fn)
    return { convert_fn = parse_color, validate_fn = validate_fn }
end

-- ---------------------------------------------------------------------------
-- Initialize
-- ---------------------------------------------------------------------------
function _M.init(formats, opts)
    l_assert(opts.max_width)
    l_assert(opts.max_height)
    l_assert(opts.max_operations)
    l_assert(opts.default_format)
    l_assert(opts.default_quality)
    l_assert(opts.default_strip)

    _M.supported_formats = formats
    _M.opts = opts

    _M.ops = {

        crop = {
            params = {
                w = make_number_arg(validate_width),
                h = make_number_arg(validate_height),
                g = make_string_arg(validate_gravity)
            },
            validate_fn = function(p)
                if not p.w and not p.h then
                    return nil, "missing w= and h= for crop"
                end
                return true
            end
        },

        option = { params = { c = make_color_arg(validate_color) } },

        blur = {
            params = { s = make_number_arg(validate_sigma) },
            validate_fn = function(p)
                if not p.s then
                    return nil, "missing s= (sigma) for blur"
                end
                return true
            end
        },

        resize = {
            params = {
                w = make_number_arg(validate_width),
                h = make_number_arg(validate_height),
                m = make_string_arg(validate_resize_mode)
            },
            validate_fn = function(p)
                if not p.w and not p.h then
                    return nil, "missing both w= and h= for resize"
                end
                return true
            end
        },

        round = {
            params = {
                p = make_number_arg(validate_percentage),
                x = make_number_arg(validate_width),
                y = make_number_arg(validate_height)
            },
            validate_fn = function(p)
                if not p.p and (not p.x or not p.y) then
                    return nil, "round needs either p= or both x= and y="
                end
                return true
            end
        },

        named = {
            params = { n = make_string_arg(validate_name) },
            validate_fn = function(p)
                if not p.n then
                    return nil, "named operation missing n="
                end
                if not _M.named_ops[p.n] then
                    return nil, "named operation '" .. p.n .. "' does not exist"
                end
                return true
            end
        },

        format = {
            params = {
                t = make_string_arg(validate_format),
                q = make_number_arg(validate_percentage),
                s = make_boolean_arg()
            },
            get_default_params = function()
                return { t = opts.default_format, q = opts.default_quality, s = opts.default_strip }
            end
        }
    }

    -- Load named operations file
    if opts.named_operations_file then
        local lines, err = util.file_get_lines(opts.named_operations_file)
        if not lines then
            return nil, "Failed to read named operations file (" .. opts.named_operations_file ..
                       "): " .. err
        end

        for n, line in l_pairs(lines) do
            local name, operation = line:match("(.+)%s?:%s?(.+)")
            if not name or not operation then
                return nil, "Failed to parse line " .. n
            end

            local parsed, perr = _M.parse(operation)
            if not parsed then
                return nil, "Failed to parse named operation: " .. perr
            end

            _M.named_ops[name] = parsed
        end
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Ordered table
-- ---------------------------------------------------------------------------
local function ordered_table()
    local data = {}
    local next_key = {}
    local first_key = {}

    next_key[first_key] = nil

    local function iter(self, key)
        key = next_key[key]
        if key ~= nil then
            return key, self[key]
        end
    end

    local mt = {}

    function mt:__newindex(key, val)
        l_rawset(self, key, val)
        if next_key[key] == nil then
            local last = first_key
            while next_key[last] do
                last = next_key[last]
            end
            next_key[last] = key
            next_key[key] = nil
        end
    end

    function mt:__pairs()
        return iter, data, first_key
    end

    return l_setmetatable(data, mt)
end

-- ---------------------------------------------------------------------------
-- Manifest creation
-- ---------------------------------------------------------------------------
local function new_manifest()
    return { format = nil, option = nil, operations = ordered_table() }
end

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------
function _M.parse(str)
    local manifest = new_manifest()

    for op_name, params in str:gmatch("([^/]+)/([^/]+)") do
        local op_def = _M.ops[op_name]

        if not op_def then
            return nil, "unrecognized operation " .. op_name
        end

        local fn_params = op_def.get_default_params and op_def.get_default_params() or {}

        for p_name, def in l_pairs(op_def.params) do
            local raw = params:match(p_name .. "=([^,/]+)")
            if raw then
                local val = raw
                if def.convert_fn then
                    local converted, err = def.convert_fn(raw)
                    if not converted then
                        return nil, err or ("failed to convert " .. p_name)
                    end
                    val = converted
                end

                if def.validate_fn and not def.validate_fn(val) then
                    return nil, op_name .. "->" .. p_name .. " validation failed (value: " ..
                               tostring(val) .. ")"
                end

                fn_params[p_name] = val
            end
        end

        if op_def.validate_fn then
            local ok, err = op_def.validate_fn(fn_params)
            if not ok then
                return nil, err
            end
        end

        if op_name == supported_operations.NAMED then
            return _M.named_ops[fn_params.n]
        elseif op_name == supported_operations.FORMAT then
            manifest.format = fn_params
        elseif op_name == supported_operations.OPTION then
            manifest.option = fn_params
        else
            l_insert(manifest.operations, { name = op_name, params = fn_params })
        end
    end

    if #manifest.operations == 0 then
        return nil, "did not find valid operations"
    end

    if #manifest.operations > _M.opts.max_operations then
        return nil, "operation count exceeds max configured"
    end

    if not manifest.format then
        manifest.format = _M.ops.format.get_default_params()
    end

    return manifest
end

return _M
