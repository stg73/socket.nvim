local M = {}

function M.server(host,port)
    local o = {
        stop = function() end, -- サーバを終了する
        send = function() end, -- データを送る
        close = function() end, -- 接続を切る
        state = {
            -- 状態をここで管理する
        },
        on = {
            data = function() end, -- データが送られてきたときにデータを引数として呼び出される
            open = function() end, -- 接続したときに呼び出される
        },
    }

    local server = vim.uv.new_tcp()
    o.stop = function() server:close() end
    server:bind(host,port)
    server:listen(128,function(err)
        assert(not err,err)
        local sock = vim.uv.new_tcp()
        server:accept(sock)
        o.on.open()
        o.send = function(data,callback) sock:write(data,callback) end
        o.close = function() sock:close() end
        sock:read_start(function(err, chunk)
            assert(not err,err)
            if chunk then
                o.on.data(chunk)
            else
                sock:close()
            end
        end)
    end)

    return o
end

function M.client(host,port)
    local o = {
        send = function() end,
        close = function() end,
        state = {
            -- 状態はここで管理する
        },
        on = {
            data = function() end,
            open = function() end,
        }
    }

    local client = vim.uv.new_tcp()
    client:connect(host,port,function(err)
        assert(not err,err)
        o.send = function(data,callback)
            client:write(data,callback)
            client:read_start(function(err, chunk)
                assert(not err,err)
                o.close = function() client:close() end
                if chunk then
                    o.on.data(chunk)
                else
                    client:close()
                end
            end)
        end
        o.on.open()
    end)

    return o
end

function M.can_connect(host,port)
    local client = vim.uv.new_tcp()
    local connected
    client:connect(host,port,function(err)
        if err then
            connected = false
        else
            connected = true
        end
        client:close()
    end)

    local function wait_for_result()
        if connected == nil then
            vim.wait(1)
            wait_for_result()
        end
    end
    wait_for_result()

    return connected
end

local tbl = require("tbl")

function M.get_available_port()
    return tbl.match(function(port)
        return not M.can_connect("127.0.0.1",port)
    end)(tbl.range(1024)(49151))
end

return M
