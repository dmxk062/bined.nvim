local M = {}
local bit = require("bit")

local ffi = require("ffi")

ffi.cdef [[
void* malloc(size_t size);
void  free(void* ptr);
]]

---@param size integer
---@param data string
---@return ffi.cdata*
local function create_buffer(size, data)
    local buf = ffi.gc(ffi.C.malloc(size), ffi.C.free)
    ffi.copy(buf, data, size)
    return ffi.cast("uint8_t*", buf)
end

---@param data ffi.cdata*
---@param num_bytes integer
---@param base "bin"|"oct"|"hex"
---@return string
local function format_data(data, num_bytes, base)
    local res = {}

    if base == "hex" then
        for i=0, num_bytes, 2 do
            table.insert(res, string.format("%02X%02X", data[i], data[i+1]))
        end
    elseif base == "oct" then
        for i=0, num_bytes, 2 do
            table.insert(res, string.format("%03o%03o", data[i], data[i+1]))
        end
    else
        for i=0, num_bytes do
            table.insert(res, string.format("%08B", data[i]))
        end
    end
    return table.concat(res, " ")
end

local word_size = {
    hex = 2.5,
    oct = 3.5,
    bin = 9,
}

local byte_to_str = {
    hex = function(byte)
        return string.format("%02X", byte)
    end,
    oct = function(byte)
        return string.format("%03o", byte)
    end,
    bin = function(byte)
        local bin=""
        for i = 7, 0, -1 do
            local b = bit.band(byte, i)
            bin = bin .. b
        end
        return bin
    end
}

local function get_byte_per_line(len, size, mult, max)
    local usable_line_length = len - 20 -- reserve for address
    local bytes_per_line = math.floor(usable_line_length / size)
    if bytes_per_line % mult ~= 0 then
        bytes_per_line = bytes_per_line - 1
    end

    return math.min(max, bytes_per_line)
end

---@param bufnum integer
---@param base "bin"|"oct"|"hex"
---@param line_length integer
---@return string[] text
function M.buffer_to_repr(bufnum, base, line_length)
    local step = base ~= "bin" and 2 or 1
    local bytes_per_line = get_byte_per_line(line_length, word_size[base], step, 24)

    local text = table.concat(vim.api.nvim_buf_get_lines(bufnum, 0, -1, false), "\n")
    local num_bytes = #text
    local bytes = create_buffer(num_bytes, text)

    local num_lines = math.ceil(num_bytes / bytes_per_line)
    local lines = {}

    local line = {}
    local byte2str = byte_to_str[base]
    for i=0, num_bytes-1 do
        if i % bytes_per_line == 0 then
            if #line > 0 then
                table.insert(lines, table.concat(line))
            end
            line = {string.format("%08X:", i)}
        end
        if i % step == 0 then
            table.insert(line, " ")
        end
        table.insert(line, byte2str(bytes[i]))
    end
    if #line > 0 then
        table.insert(lines, table.concat(line))
    end


    return lines
end

return M
