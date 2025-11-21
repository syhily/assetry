local cjson = require "cjson"
local upload = require "resty.upload"
local sha256 = require "resty.sha256"
local str = require "resty.string"

local data_root = "/data"

local _M = {}

-- Safe mkdir recursive without lfs
local function mkdir_p(path)
    local current = ""
    for dir in path:gmatch("[^/]+") do
        current = current .. "/" .. dir
        local ok = os.execute("mkdir -p \"" .. current .. "\"")
        if not ok then
            return nil, "failed to mkdir " .. current
        end
    end
    return true
end

local function is_file(path)
    local p = io.popen("test -f \"" .. path .. "\" && echo yes || echo no")
    local res = p:read("*l")
    p:close()
    return res == "yes"
end

-- List files with SHA256 without creating directory
local function list_files_sha(dir)
    local files = {}

    -- Check if directory exists
    local f = io.open(dir, "r")
    if not f then
        return files -- return empty list if dir doesn't exist
    end
    f:close()

    -- Iterate over entries
    local p = io.popen("ls -A \"" .. dir .. "\" 2>/dev/null")
    if not p then
        return files
    end

    for entry in p:lines() do
        local fpath = dir .. "/" .. entry
        if is_file(fpath) then
            local file = io.open(fpath, "rb")
            if file then
                local data = file:read("*a") or ""
                file:close()
                local sha_obj = sha256:new()
                sha_obj:update(data)
                local digest = str.to_hex(sha_obj:final())
                files[#files + 1] = { name = entry, type = "file", sha256 = digest }
            end
        else
            -- Treat as directory
            files[#files + 1] = { name = entry, type = "dir" }
        end
    end

    p:close()
    
    if #files == 0 then
        return cjson.empty_array
    end
    return files
end

-- Initialize module
function _M.init(config)
    _M.api_key = config.upload_api_key
end

-- Validate API key
local function validate_api_key(args)
    local api_key = args and args["api_key"] or nil
    if _M.api_key and _M.api_key ~= api_key then
        ngx.status = 403
        ngx.header["content-type"] = "application/json"
        ngx.say(cjson.encode({ error = "forbidden" }))
        return false
    end
    return true
end

-- Validate upload path
local function validate_path(path)
    if not path or path == "" then
        ngx.status = 400
        ngx.header["content-type"] = "application/json"
        ngx.say(cjson.encode({ error = "missing path" }))
        return false
    end
    if path:find("%.%.") or path:sub(1, 1) == "/" then
        ngx.status = 400
        ngx.header["content-type"] = "application/json"
        ngx.say(cjson.encode({ error = "invalid path" }))
        return false
    end
    if not path:match("^[A-Za-z0-9_%-. /]+$") then
        ngx.status = 400
        ngx.header["content-type"] = "application/json"
        ngx.say(cjson.encode({ error = "unsupported characters in path" }))
        return false
    end
    return true
end

-- Handle GET requests
local function handle_list_files(path)
    local dir = data_root .. "/" .. path
    local files = list_files_sha(dir)
    ngx.header["content-type"] = "application/json"
    ngx.say(cjson.encode({ path = path, files = files }))
end

-- Handle POST requests
local function handle_upload_file(path)
    local dir = data_root .. "/" .. path
    local form, err = upload:new(4096)
    if not form then
        ngx.status = 500
        ngx.header["content-type"] = "application/json"
        ngx.say(cjson.encode({ error = "upload init failed", detail = err }))
        return
    end
    form:set_timeout(5000)

    local ok, err = mkdir_p(dir)
    if not ok then
        ngx.status = 500
        ngx.header["content-type"] = "application/json"
        ngx.say(cjson.encode({ error = "the upload path can't be created", detail = err }))
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
                local m = ngx.re.match(value, "filename=\"?([^\";]+)\"?", "jo")
                if m then
                    filename = m[1]
                end
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
            if file then
                file:close()
                file = nil
            end
        elseif typ == "eof" then
            break
        end
    end

    ngx.status = 201
    ngx.header["content-type"] = "application/json"
    ngx.say(cjson.encode({ path = path, file = filename, size = size }))
end

-- Main entry point
function _M.handle_upload()
    local method = ngx.req.get_method()
    local path = ngx.var.upload_path
    local args = ngx.req.get_uri_args()

    if not validate_api_key(args) then
        return
    end

    if method == "GET" then
        handle_list_files(path)
    elseif method == "POST" then
        if not validate_path(path) then
            return
        end
        handle_upload_file(path)
    else
        ngx.status = 405
        ngx.header["Allow"] = "GET, POST"
        return
    end
end

return _M
