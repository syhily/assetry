local util = require "resty.assetry_util"

local l_assert       = assert
local l_table_insert = table.insert
local l_tonumber     = tonumber
local l_pairs        = pairs
local l_rawset       = rawset
local l_setmetatable = setmetatable

local supported_operations = {
    CROP   = "crop",
    BLUR   = "blur",
    RESIZE = "resize",
    ROUND  = "round",
    NAMED  = "named",
    FORMAT = "format",
    OPTION = "option"
}

local supported_modes = {
    fit  = true,
    fill = true,
    crop = true,
}

local supported_gravity = {
    n      = true,
    ne     = true,
    e      = true,
    se     = true,
    s      = true,
    sw     = true,
    w      = true,
    nw     = true,
    center = true,
    smart  = true,
}

local _M = {
    named_ops = {},
    ops       = {},
    supported_formats = {}
}

local function validate_always_valid()
    return true
end

local function to_boolean(str)
    if not str then
        return false
    end

    if str == "1" or str == "true" or str == "yes" then
        return true
    else
        return false
    end
end


local function parse_color(str)
    if not str then
        return nil, 'empty color string'
    end

    if str:len() == 3 then

        r = l_tonumber("0x" .. str:sub(1, 1)) * 17
        g = l_tonumber("0x" .. str:sub(2, 2)) * 17
        b = l_tonumber("0x" .. str:sub(3, 3)) * 17

    elseif str:len() == 6 then

        r = l_tonumber("0x" .. str:sub(1, 2))
        g = l_tonumber("0x" .. str:sub(3, 4))
        b = l_tonumber("0x" .. str:sub(5, 6))

    else
        return nil, "malformed color string " .. str
    end

    return {
        r = r,
        g = g,
        b = b,
    }
end


local function validate_width(width)
    return width and width < _M.opts.max_width and width > 0
end

local function validate_height(height)
    return height and height < _M.opts.max_height and height > 0
end

local function validate_sigma(sigma)
    return sigma and sigma >= 0.0
end

local function validate_quality(quality)
    return quality and quality >= 1 and quality <= 100
end

local function validate_format(str)
    return str and _M.supported_formats[str] ~= nil
end

local function validate_resize_mode(str)
    return str and supported_modes[str] ~= nil
end

local function validate_gravity(str)
    return str and supported_gravity[str] ~= nil
end

local function validate_color(color)
    if not color then
        return false
    end

    return color.r >= 0 and color.r <= 255 and color.g >= 0 and color.g <= 255 and color.b >= 0 and color.b <= 255
end

local function make_boolean_arg()
    return {
        convert_fn  = to_boolean,
        validate_fn = validate_always_valid
    }
end

local function make_number_arg(validate_fn)
    return {
        convert_fn  = l_tonumber,
        validate_fn = validate_fn,
    }
end

local function make_string_arg(validate_fn)
    return { validate_fn = validate_fn, }
end

local function make_color_arg(validate_fn)
    return {
        convert_fn  = parse_color,
        validate_fn = validate_fn,
    }
end

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
                w  = make_number_arg(validate_width),
                h  = make_number_arg(validate_height),
                g  = make_string_arg(validate_gravity),  -- gravity
            },
            validate_fn = function(p)
                if not p.w and not p.h then
                    return nil, 'missing w= and h= for crop'
                end
                return true
            end
        },

        option = {
            params = {
                c = make_color_arg(validate_color),
            },
        },

        blur = {
            params = {
                s  = make_number_arg(validate_sigma),
            },
            validate_fn = function(p)
                if not p.s then
                    return nil, 'missing s= (sigma) for blur'
                end
                return true
            end
        },

        resize = {
            params = {
                w  = make_number_arg(validate_width),
                h  = make_number_arg(validate_height),
                m  = make_string_arg(validate_resize_mode),
            },
            validate_fn = function(p)
                if not p.w and not p.h then
                    return nil, 'missing both w= and h= for resize'
                end
                return true
            end
        },

        round = {
            params = {
                p = make_number_arg(validate_percentage),
                x = make_number_arg(validate_width),
                y = make_number_arg(validate_height),
            },
            validate_fn = function(p)
                if not p.p then
                    if not p.x and not p.y then
                        return nil, 'round needs either p= or both x= and y='
                    end
                end
                return true
            end
        },

        named = {
            params = {
                n = make_string_arg(validate_name)
            },
            validate_fn = function(p)
                if not p.n then
                    return nil, 'named operation is missing n= param'
                end
                if not _M.named_ops[p.n] then
                    return nil, 'the named operation ' .. p.n .. ' does not exist'
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
                return {
                    t = opts.default_format,
                    q = opts.default_quality,
                    s = opts.default_strip
                }
            end
        }
    }

    if opts.named_operations_file then
        local lines, err = util.file_get_lines(opts.named_operations_file)

        if not lines then
            return nil, "Failed to read named operations file(" .. opts.named_operations_file .. "): " .. err
        end

        for n, line in l_pairs(lines) do

            local name, operation = line:match('(.+)%s?:%s?(.+)')

            if not name or not operation then
                return nil, "Failed to parse line (" .. n .."): " .. err
            else

                local parsed, err = _M.parse(operation)

                if not parsed then
                    return nil, "Failed to parse named operation: " .. err
                else
                    _M.named_ops[name] = parsed
                end
            end
        end
    end

    return true
end

local function ordered_table()
    local key2val, next_key, first_key = {}, {}, {}
    next_key[next_key] = first_key

    local function on_next(self, key)
        while key ~= nil do
            key = next_key[key]
            local val = self[key]
            if val ~= nil then return key, val end
        end
    end

    local self_meta = first_key
    self_meta.__next_key = next_key

    function self_meta:__newindex(key, val)
        l_rawset(self, key, val)
        if next_key[key] == nil then -- adding a new key
            next_key[next_key[next_key]] = key
            next_key[next_key] = key
        end
    end

    function self_meta:__pairs() return on_next, self, first_key end

    return l_setmetatable(key2val, self_meta)
end

local function new_manifest()
    return {
        format     = nil,
        option     = nil,
        operations = ordered_table()
    }
end

function _M.parse(str)
    local manifest = new_manifest()
    local err

    for name, params in str:gmatch('([^/]+)/([^/]+)') do

        local op_definition = _M.ops[name]

        if op_definition then
            local fn_params = {}

            if op_definition.get_default_params then
                fn_params = op_definition.get_default_params()
            end

            -- Loop through recognized params
            for n, def in l_pairs(op_definition.params) do

                local value = params:match(n .. '=([^,/]+)')

                if value then
                    if def.convert_fn then
                        value, err = def.convert_fn(value)

                        if value == nil then
                            return nil, (err or "Failed to convert param")
                        end
                    end

                    if def.validate_fn then
                        if not def.validate_fn(value) then
                            return nil, name .. "->" .. n .. '(value: ' .. (value or 'nil') .. ') failed validation'
                        end
                    end
                    fn_params[n] = value
                end
            end

            if op_definition.validate_fn then
                local ok, err = op_definition.validate_fn(fn_params)

                if not ok then
                    return nil, err
                end
            end

            -- Return named operation if exists
            if name == supported_operations.NAMED then
                return _M.named_ops[fn_params["n"]]
            elseif name == supported_operations.FORMAT then
                manifest.format = fn_params
            elseif name == supported_operations.OPTION then
                manifest.option = fn_params
            else
                l_table_insert(manifest.operations, {
                    name   = name,
                    params = fn_params
                })
            end

        else
            return nil, 'unrecognized operation ' .. name
        end
    end

    if #manifest.operations == 0 then
        return nil, 'did not find valid operations'
    end

    if #manifest.operations > _M.opts.max_operations then
        return nil, 'amount of operations exceeds configured maximum'
    end

    if not manifest.format then
        manifest.format = _M.ops[supported_operations.FORMAT].get_default_params()
    end

    return manifest, nil
end

return _M
