local http = require "resty.http"
local url = require "net.url"
local lrucache = require "resty.lrucache"

local l_table_concat = table.concat
local l_setmetatable = setmetatable
local l_pairs = pairs
local l_string = string

local _M = {}

function _M.new(self, opts)
    if not opts then
        opts = {}
    end

    l_setmetatable(opts, {
        __index = {
            keepalive_timeout = 120,
            keepalive_pool_size = 24,
            request_timeout = 30,
            ssl_session_cache_size = 24,
            ssl_session_cache_ttl = 120,
            max_redirects = 3,
            max_body_size = 25 * 1024 * 1024
        }
    })

    opts.keepalive_timeout = opts.keepalive_timeout * 1000
    opts.request_timeout = opts.request_timeout * 1000

    local ssl_cache = lrucache.new(opts.ssl_session_cache_size)
    return l_setmetatable({ opts = opts, ssl_cache = ssl_cache }, { __index = _M })
end

local function ssl_handshake(self, httpclient, host, port)
    local cache_key = host .. ":" .. port
    local prev_session = self.ssl_cache:get(cache_key)
    local session, err = httpclient:ssl_handshake(prev_session, host, true)

    if not session then
        return nil, "failed to establish ssl connection: " .. err
    end

    self.ssl_cache:set(cache_key, session, self.opts.ssl_session_cache_ttl)
    return true, nil
end

local function read_response_body(res, max_body_size)
    local reader = res.body_reader

    if not reader then
        return nil, "no body to read"
    end

    local chunks = {}
    local c = 1

    local chunk, err
    repeat

        if c > max_body_size then
            return nil, "body size exceeds max_body_size"
        end

        chunk, err = reader()

        if err then
            return nil, err
        end

        if chunk then
            chunks[c] = chunk
            c = c + 1
        end

    until not chunk

    return l_table_concat(chunks)
end

function _M.get_url(self, image_url, redirects_left)
    local httpclient = http.new()

    local u = url.parse(image_url)

    if not u or not u.host then
        return nil, "failed to parse url: " .. image_url
    end

    local host = u.host
    local port

    if u.port then
        port = u.port
    else
        if u.scheme == "https" then
            port = 443
        else
            port = 80
        end
    end

    local ok, err = httpclient:connect(host, port)

    if not ok then
        return nil, "failed to fetch " .. image_url .. ": " .. err
    end

    if u.scheme == "https" then
        local ok, err = ssl_handshake(self, httpclient, host, port)

        if not ok then
            return nil, err
        end
    end

    local req_path = u.path .. (u.query and "?" .. url.buildQuery(u.query) or "")

    local res, err = httpclient:request{
        path = req_path,
        headers = {
            ["Host"] = host,
            ["User-Agent"] = "openresty/assetry",
            ["Connection"] = "Keep-Alive"
        }
    }

    if not res then
        return nil, err
    end

    if res.status >= 300 and res.status <= 399 then

        if redirects_left <= 0 then
            return nil, "too many redirects"
        end

        for name, value in l_pairs(res.headers) do
            if l_string.lower(name) == "location" then
                return self:get_url(value, redirects_left - 1)
            end
        end

        return nil, "received redirect status code but no location header"
    end

    if res.status < 200 or res.status > 299 then
        return nil, "received status code " .. res.status
    end

    local buffer, err = read_response_body(res, self.opts.max_body_size)

    if not buffer then
        return nil, err
    end

    httpclient:set_keepalive(self.opts.keepalive_timeout, self.opts.keepalive_pool_size)
    return buffer, nil
end

function _M.get(self, image_url)
    return self:get_url(image_url, self.opts.max_redirects)
end

return _M
