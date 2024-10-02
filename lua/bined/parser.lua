local M = {}
local bit = require("bit")

local ffi = require("ffi")

---@alias base "bin"|"oct"|"hex"

ffi.cdef [[
void* malloc(size_t size);
void  free(void* ptr);
]]


---@param size integer
---@param data string?
---@return ffi.cdata*
function M.create_buffer(size, data)
    local buf = ffi.gc(ffi.C.malloc(size), ffi.C.free)
    if data then
        ffi.copy(buf, data, size)
    else
        ffi.fill(buf, size, 0)
    end
    
    return ffi.cast("uint8_t*", buf)
end

---@class bined_data
---@field length integer
---@field bytes ffi.cdata*
---@field line_starts integer[]
--- cache all the ones already prepared
---@field hex string[]?
---@field oct string[]?
---@field bin string[]?


---@param bufnum integer
---@return bined_data
function M.buffer_to_repr(bufnum)
    local lines = vim.api.nvim_buf_get_lines(bufnum, 0, -1, false)
    local starts = {}
    local offset = 0
    for _, line in ipairs(lines) do
        local off = offset + #line + 1
        table.insert(starts, { offset, off})
        offset = off
    end
    local joined = table.concat(lines, "\n") .. (vim.bo[bufnum].endofline and "\n" or "")
    local num_bytes = #joined
    local bytes = M.create_buffer(num_bytes, joined)

    return {
        length = num_bytes,
        bytes = bytes,
        line_starts = starts,
    }
end

M.base_data = {
    hex = {
        fmt = function(byte)
            return string.format("%02X", byte)
        end,
        -- number of chars needed for a byte
        word_size = 2.5,
        group = 2,
        max = 24,
        mult = 4,
        int_value = 16,
    },
    oct = {
        fmt = function(byte)
            return string.format("%03o", byte)
        end,
        word_size = 3.5,
        group = 2,
        max = 16,
        mult = 4,
        int_value = 8,
    },
    bin = {
        fmt = function(byte)
            local bin = ""
            for i = 7, 0, -1 do
                local b = bit.band(bit.rshift(byte, i), 1)
                bin = bin .. b
            end
            return bin
        end,
        word_size = 9,
        group = 1,
        max = 10,
        mult = 1,
        int_value = 2,
    }
}

return M
