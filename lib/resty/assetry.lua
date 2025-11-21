local vips = require "resty.assetry_vips"
local http = require "resty.assetry_http"
local stats = require "resty.assetry_stats"
local params = require "resty.assetry_params"
local pretty = require "resty.prettycjson"
local util = require "resty.assetry_util"
local upload = require "resty.assetry_upload"

local ngx_ctx = ngx.ctx
local to_number = tonumber
local ngx_now = ngx.now
local ngx_var = ngx.var
local ngx_update_time = ngx.update_time

local log_error = util.log_error
local log_warn = util.log_warn
local log_info = util.log_info

local _M = {}

local function getenv_number(var_name, default)
    local v = os.getenv(var_name)
    return v and to_number(v) or default
end

local function getenv_string(var_name, default)
    local v = os.getenv(var_name)
    return v and v or default
end

local function getenv_boolean(var_name, default)
    local v = os.getenv(var_name)
    if v then
        if v == "1" or v == "true" or v == "yes" then
            return true
        else
            return false
        end
    end

    return default
end

function _M.init(config)
    if not config then
        config = {}
    end

    log_info("Openresty Init")

    setmetatable(config, {
        __index = {
            shm_name = "assetry",
            max_width = getenv_number("ASSETRY_MAX_WIDTH", 4096),
            max_height = getenv_number("ASSETRY_MAX_HEIGHT", 4096),
            max_operations = getenv_number("ASSETRY_MAX_OPERATIONS", 10),
            default_quality = getenv_number("ASSETRY_DEFAULT_QUALITY", 90),
            default_strip = getenv_boolean("ASSETRY_DEFAULT_STRIP", true),
            default_format = getenv_string("ASSETRY_DEFAULT_FORMAT", "webp"),
            max_concurrency = getenv_number("ASSETRY_MAX_CONCURRENCY", 24),
            named_operations_file = getenv_string("ASSETRY_NAMED_OPERATIONS_FILE", nil),
            default_params = getenv_string("ASSETRY_DEFAULT_PARAMS", "/resize/w=1024,h=1024,m=fit"),
            upload_api_key = getenv_string("ASSETRY_UPLOAD_API_KEY", nil)
        }
    })

    -- Store config
    _M.config = config

    -- Init vips lib
    vips.init(config)

    local supported_formats = vips.get_formats()
    local ok, err = params.init(supported_formats, config)

    if not ok then
        util.log_error(err)
    end

    local formats = "Supported Image Formats: "

    for key, value in pairs(supported_formats) do
        formats = formats .. ", " .. key
    end

    util.log_info(formats)
    stats.init(config)
    upload.init(config)

    -- HTTP Client
    _M.http = http:new()
end

function _M.access_phase()
    local url_params = ngx.var.assetry_params
    local image_url = ngx.var.assetry_url

    if not url_params or url_params == "" then
        url_params = _M.config.default_params
    end

    if not url_params or url_params == "" then
        log_error("missing params")
        return ngx.exit(400)
    end

    if not image_url or image_url == "" then
        log_error("missing image url")
        return ngx.exit(400)
    end

    local parsed, err = params.parse(url_params)

    if not parsed then
        log_error("unable to parse parameters: ", err)
        return ngx.exit(400)
    end

    ngx_ctx.assetry = { manifest = parsed, image_url = image_url }
end

local function _fetch_image(image_url)
    local image, err = _M.http:get(image_url)

    if not image then
        return nil, "error loading image: " .. err
    end
    return image
end

function _M.request_handler()
    local image_url = ngx_ctx.assetry.image_url
    local manifest = ngx_ctx.assetry.manifest

    local start_fetch = ngx_now()

    local fetched, err = _fetch_image(image_url)

    if not fetched then
        log_warn(err)
        return ngx.exit(500)
    end

    ngx_update_time()
    local start_processing = ngx_now()

    local image, format = vips.operate(fetched, manifest)

    if not image then
        log_warn(format)
        return ngx.exit(500)
    end

    ngx_update_time()
    local end_time = ngx_now()

    stats.log_fetch_time(start_processing - start_fetch)
    stats.log_operating_time(end_time - start_processing)

    ngx.header["content-type"] = "image/" .. format
    ngx.say(image)
end

function _M.log_phase()
    local values = {
        connect_time = to_number(ngx_var.upstream_connect_time),
        response_time = to_number(ngx_var.upstream_response_time),
        response_status = to_number(ngx_var.upstream_status),
        cache_status = ngx_var.upstream_cache_status,
        response_length = to_number(ngx_var.upstream_response_length)
    }
    stats.log_upstream_response(values)
end

function _M.status_page()
    local service_stats = stats.get_stats()

    ngx.header["content-type"] = "application/json"
    ngx.header["cache-control"] = "no-cache"

    ngx.say(pretty(service_stats, nil, "  "))
    return ngx.exit(200)
end

function _M.upload_handler()
    upload.handle_upload()
end

return _M
