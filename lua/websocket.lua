local M = {}

local http = require("http")
local base = require("convert_base")
local tbl = require("tbl")

--[[
f は以下を含むテーブル
    fin
    rsv1
    rsv2
    rsv3
    opcode
    mask
    payload_length
    masking_key
    payload_data
]]

-- 参考にした記事: https://zenn.dev/fukurose/articles/79a0dac7d19091
function M.parse_frame(binary)
    -- 状態を持つ関数 これを使って頭から順番にバイトを読み取っていく
    local frame = { string.byte(binary,1,-1) }
    local current_head = 1
    local function take_bytes(n)
        local t = vim.list_slice(frame,current_head,current_head + n - 1)
        current_head = current_head + n
        return t
    end

    local f = {}

    local byte1 = take_bytes(1)[1]
    f.fin = bit.rshift(bit.band(byte1,0x80),7)
    f.rsv1 = bit.rshift(bit.band(byte1,0x40),6)
    f.rsv2 = bit.rshift(bit.band(byte1,0x20),5)
    f.rsv3 = bit.rshift(bit.band(byte1,0x10),4)
    f.opcode = bit.band(byte1,0x0f)

    local byte2 = take_bytes(1)[1]
    f.mask = bit.rshift(bit.band(byte2,0x80),7)
    f._payload_length = bit.band(byte2,0x7f)
    local join_bytes = base.from(math.pow(2,8))
    if f._payload_length == 126 then
        f.payload_length = join_bytes(take_bytes(2))
    elseif f._payload_length == 127 then
        f.payload_length = join_bytes(take_bytes(8))
    else
        f.payload_length = f._payload_length
    end

    if f.mask > 0 then
        f.masking_key = take_bytes(4) 
    end

    f._payload_data = take_bytes(f.payload_length)
    if f.mask == 0 then
        f.payload_data = f._payload_data
    else
        f.payload_data = {}
        for i,val in pairs(f._payload_data) do
            f.payload_data[i] = bit.bxor(val,f.masking_key[((i - 1) % 4) + 1])
        end
    end

    return f
end

-- M.parse_frame() の返り値から _* を除いたものからフレームを組み立てる
function M.build_frame(f)
    local frame = {}
    local function insert(list)
        vim.list_extend(frame,list)
    end

    local byte1 = 0
    byte1 = bit.bor(byte1,bit.lshift(f.fin,7))
    byte1 = bit.bor(byte1,bit.lshift(f.rsv1,6))
    byte1 = bit.bor(byte1,bit.lshift(f.rsv1,5))
    byte1 = bit.bor(byte1,bit.lshift(f.rsv1,4))
    byte1 = bit.bor(byte1,f.opcode)
    insert({byte1})

    local byte2 = 0
    byte2 = bit.bor(byte2,bit.lshift(f.mask,7))
    local len_bytes = {} -- payload_length を表すバイト列
    if f.payload_length >= 126 then
        len_bytes = base.to(math.pow(2,8))(f.payload_length)
        if #len_bytes <= 2 then
            f.payload_length = 126
            len_bytes = base.align(2)(len_bytes)
        else
            f.payload_length = 127
            len_bytes = base.align(8)(len_bytes)
        end
    end
    byte2 = bit.bor(byte2,f.payload_length)
    insert({byte2})
    insert(len_bytes)

    insert(f.payload_data)

    local binary = table.concat(tbl.map(string.char)(frame))
    return binary
end

function M.sec_websocket_accept(key)
    local guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    return vim.base64.encode(require("sha1").sha1(key .. guid))
end

function M.handshake(request)
    local header = request.header
    if not (header["connection"] == "Upgrade"
        and header.upgrade == "websocket"
        and header["sec-websocket-key"]
        and header["sec-websocket-version"] == "13") then
        vim.notify("websocket ハンドシェイクでないリクエスト:" ..
        "\n" .. vim.inspect(request),vim.log.levels.ERROR)
        return
    end
    local response = {
        version = "1.1",
        status = 101,
        header = {
            ["sec-websocket-accept"] = M.sec_websocket_accept(request.header["sec-websocket-key"]),
            upgrade = "websocket",
            connection = "Upgrade",
            server = "Neovim",
            date = http.date(),
        },
        body = "",
    }

    return response
end

function M.wrap(handler)
    return function(frame)
        -- 本体
        local data_x
        if frame then
            local parsed = M.parse_frame(frame)
            data_x = table.concat(tbl.map(string.char)(parsed.payload_data))
        end
        local data_y = handler(data_x)
        if data_y then
            return M.build_frame({
                fin = 1,
                rsv1 = 0,
                rsv2 = 0,
                rsv3 = 0,
                opcode = 1,
                mask = 0,
                payload_length = string.len(data_y),
                payload_data = { string.byte(data_y,1,-1) },
            })
        else
            return nil
        end
    end
end

return M
