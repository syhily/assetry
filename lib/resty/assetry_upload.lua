local cjson  = require "cjson"
local upload = require "resty.upload"
local util   = require "resty.assetry_util"

local random_api_key = util.random_api_key
local log_error      = util.log_error
local log_warn       = util.log_warn
local log_info       = util.log_info

local _M = {}

-- Safe mkdir recursive without lfs
local function mkdir_p(path)
    local current = ""
    for dir in path:gmatch("[^/]+") do
        current = current .. "/" .. dir
        local ok = os.execute('mkdir -p "' .. current .. '"')
        if not ok then return nil, "failed to mkdir " .. current end
    end
    return true
end

-- List files in directory
local function list_files(dir)
    local files = {}
    local p = io.popen('ls -A "' .. dir .. '" 2>/dev/null')
    if p then
        for file in p:lines() do
            files[#files+1] = file
        end
        p:close()
    end
    return files
end

function _M.init(config)
    _M.api_key = config.upload_api_key
    _M.data_root = "/data"
end

function _M.handle_upload()
    local method = ngx.req.get_method()
    local path   = ngx.var.upload_path
    local args   = ngx.req.get_uri_args()

    -- Verify the API KEY
    local api_key = args and args["api_key"] or nil
    if _M.api_key and _M.api_key ~= api_key then
        ngx.status = 403
        ngx.header["content-type"] = "application/json"
        ngx.say(cjson.encode({ error = "forbidden" }))
        return
    end

    -- Validate upload path
    if not path or path == "" then
        ngx.status = 400
        ngx.header["content-type"] = "application/json"
        ngx.say(cjson.encode({ error = "missing path" }))
        return
    end
    if path:find("%.%.") or path:sub(1,1) == "/" then
        ngx.status = 400
        ngx.header["content-type"] = "application/json"
        ngx.say(cjson.encode({ error = "invalid path" }))
        return
    end
    if not path:match("^[A-Za-z0-9_%-. /]+$") then
        ngx.status = 400
        ngx.header["content-type"] = "application/json"
        ngx.say(cjson.encode({ error = "unsupported characters in path" }))
        return
    end

    local dir = _M.data_root .. "/" .. path

    if method == "GET" then
        local ok, err = mkdir_p(dir)
        if not ok then
            ngx.status = 500
            ngx.header["content-type"] = "application/json"
            ngx.say(cjson.encode({ error = "mkdir failed", detail = err }))
            return
        end
        local files = list_files(dir)
        ngx.header["content-type"] = "application/json"
        ngx.say(cjson.encode({ path = path, files = files }))
        return

    elseif method == "POST" then
        local form, err = upload:new(4096)
        if not form then
            ngx.status = 500
            ngx.header["content-type"] = "application/json"
            ngx.say(cjson.encode({ error = "upload init failed", detail = err }))
            return
        end
        form:set_timeout(1000)

        local ok, err = mkdir_p(dir)
        if not ok then
            ngx.status = 500
            ngx.header["content-type"] = "application/json"
            ngx.say(cjson.encode({ error = "mkdir failed", detail = err }))
            return
        end

        local file, filename, size = nil, nil, 0

        while true do
            local typ, res, err = form:read()
            if not typ then
                ngx.status = 400
                ngx.header["content-type"] = "application/json"
                ngx.say(cjson.encode({ error = "read failed", detail = err }))
                return
            end

            if typ == "header" then
                local name, value = res[1], res[2]
                if name == "Content-Disposition" then
                    local m = ngx.re.match(value, 'filename="?([^";]+)"?', "jo")
                    if m then filename = m[1] end
                end
            elseif typ == "body" then
                if res then
                    if not file then
                        filename = filename and filename:gsub("^.*[\\/]", "") or "upload.bin"
                        if not filename:match("^[A-Za-z0-9_%-.]+$") then
                            filename = "upload.bin"
                        end
                        file = io.open(dir .. "/" .. filename, "w")
                        if not file then
                            ngx.status = 500
                            ngx.header["content-type"] = "application/json"
                            ngx.say(cjson.encode({ error = "file open failed" }))
                            return
                        end
                    end
                    file:write(res)
                    size = size + #res
                end
            elseif typ == "part_end" then
                if file then file:close(); file = nil end
            elseif typ == "eof" then
                break
            end
        end

        ngx.status = 201
        ngx.header["content-type"] = "application/json"
        ngx.say(cjson.encode({ path = path, file = filename, size = size }))
        return
    else
        ngx.status = 405
        ngx.header["Allow"] = "GET, POST"
        return
    end
end

return _M
