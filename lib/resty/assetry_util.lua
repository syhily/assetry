local l_print = print
local l_io = io

if not ngx then
    ngx = { log = l_print, ERR = 0, INFO = 0, WARN = 0 }
end

local log = ngx.log
local ERR = ngx.ERR
local INFO = ngx.INFO
local WARN = ngx.WARN

local _M = {}

local function file_exists(file)
    local f = l_io.open(file, "rb")

    if f then
        f:close()
    end

    return f ~= nil
end

function _M.file_get_lines(file)
    if not file_exists(file) then
        return nil, "File does not exist"
    end

    local lines = {}

    for line in l_io.lines(file) do
        lines[#lines + 1] = line
    end

    return lines
end

function _M.log_info(...)
    log(INFO, "assetry: ", ...)
end

function _M.log_warn(...)
    log(WARN, "assetry: ", ...)
end

function _M.log_error(...)
    log(ERR, "assetry: ", ...)
end

return _M
