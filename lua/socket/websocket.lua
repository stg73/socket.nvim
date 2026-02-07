local M = {}

local ws = require("websocket")

function M.server(o)
    local new_o = {
        send = function(data)
            o.send(ws.wrap(function()
                return data
            end)())
        end,
        on = {
            data = function() end,
            open = function() end,
            close = function() end,
        },
    }

    local is_open
    o.on.open = function()
        is_open = false
    end
    o.on.data = function(data)
        if is_open then
            ws.wrap(new_o.on.data)(data)
        elseif ws.parse_frame(data).opcode == 8 then
            new_o.on.close()
        else
            o.send(require("http").wrap(ws.handshake)(data))
            is_open = true
            new_o.on.open()
        end
    end

    return new_o
end

return M
