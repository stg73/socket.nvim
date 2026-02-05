local M = {}

local tbl = require("tbl")

M.status_codes = {
    [100] = "Continue",
    [101] = "Switching Protocols",
    [102] = "Processing",
    [200] = "OK",
    [201] = "Created",
    [202] = "Accepted",
    [203] = "Non-Authoritative Information",
    [204] = "No Content",
    [205] = "Reset Content",
    [206] = "Partial Content",
    [207] = "Multi-Status",
    [208] = "Already Reported",
    [226] = "IM Used",
    [300] = "Multiple Choices",
    [301] = "Moved Permanently",
    [302] = "Found",
    [303] = "See Other",
    [304] = "Not Modified",
    [305] = "Use Proxy",
    [306] = "Reserved",
    [307] = "Temporary Redirect",
    [308] = "Permanent Redirect",
    [400] = "Bad Request",
    [401] = "Unauthorized",
    [402] = "Payment Required",
    [403] = "Forbidden",
    [404] = "Not Found",
    [405] = "Method Not Allowed",
    [406] = "Not Acceptable",
    [407] = "Proxy Authentication Required",
    [408] = "Request Timeout",
    [409] = "Conflict",
    [410] = "Gone",
    [411] = "Length Required",
    [412] = "Precondition Failed",
    [413] = "Request Entity Too Large",
    [414] = "Request-URI Too Long",
    [415] = "Unsupported Media Type",
    [416] = "Requested Range Not Satisfiable",
    [417] = "Expectation Failed",
    [422] = "Unprocessable Entity",
    [423] = "Locked",
    [424] = "Failed Dependency",
    [426] = "Upgrade Required",
    [428] = "Precondition Required",
    [429] = "Too Many Requests",
    [431] = "Request Header Fields Too Large",
    [500] = "Internal Server Error",
    [501] = "Not Implemented",
    [502] = "Bad Gateway",
    [503] = "Service Unavailable",
    [504] = "Gateway Timeout",
    [505] = "HTTP Version Not Supported",
    [506] = "Variant Also Negotiates (Experimental)",
    [507] = "Insufficient Storage",
    [508] = "Loop Detected",
    [510] = "Not Extended",
    [511] = "Network Authentication Required",
}

function M.date(time)
    local day_name = {"Sun","Mon","Tue","Wed","Thu","Fri","Sat"}
    local month = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}
    local date = os.date("!*t",time)
    return day_name[date.wday] .. os.date("!, %d ",time) .. month[date.month] .. os.date("! %Y %H:%M:%S GMT",time)
end

function M.build(tbl)
    local header = {}
    for key,value in pairs(tbl.header) do
        table.insert(header,key .. ": " .. value)
    end
    local status_line = table.concat(vim.iter({ tbl.method, tbl.path, "HTTP/" .. tbl.version,tbl.status,M.status_codes[tbl.status] }):totable()," ") -- 歯抜けを修正するため vim.iter を使う
    local http_x = table.concat({ status_line, table.concat(header,"\r\n"), "", tbl.body }, "\r\n")

    return http_x
end

local normalize_field_name = string.lower

function M.parse(http_x)
    local function hoge(str)
        if str == "" then
            return nil
        else
            return str
        end
    end
    local method,path,version,status,header_chunk,body = string.match(http_x,"^(%S*) ?(%S*) ?HTTP/(%S+) ?(%S*).-\r\n(.+)\r\n\r\n(.*)")
    local header_lines = vim.split(header_chunk,"\r\n")
    local header = {}
    tbl.map(function(line)
        local key,value = string.match(line,"(.-): *(.+)")
        header[normalize_field_name(key)] = value
    end)(header_lines)
    return {
        method = hoge(method),
        path = hoge(path),
        status = tonumber(status), -- 空文字列の場合 nil になるので、 hoge() は必要ない
        version = version,
        header = header,
        body = body,
    }
end

function M.wrap(handler)
    return function(http_x)
        local parsed
        if http_x then
            parsed = M.parse(http_x)
        end
        local http_y = handler(parsed)
        if not http_y then
            return nil
        end
        if type(http_y) == "string" then
            http_y = {
                header = {
                    ["content-type"] = "text/plain",
                },
                body = http_y,
            }
        end
        -- 既定値
        http_y.version = http_y.version or "1.1"
        http_y.header = http_y.header or {}
        http_y.body = http_y.body or ""
        -- ヘッダフィールド名を正規化する
        for key,value in pairs(http_y.header) do
            http_y.header[key] = nil
            http_y.header[normalize_field_name(key)] = value
        end
        local is_response = http_y.method == nil
        if is_response then
            -- 既定値
            http_y.status = http_y.status or 200
            http_y.header.server = http_y.header.server or "Neovim"
            http_y.header.date = http_y.header.date or M.date()
        end

        return M.build(http_y)
    end
end

    return M
