-- Small, data-only XML reader for the trusted JaFL content packs.  It preserves
-- mixed-content order, decodes numeric/named entities, and deliberately rejects
-- DTDs and processing instructions other than the XML declaration.
local XML = {}

local entities = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'" }

local function utf8char(n)
    if n < 0x80 then return string.char(n) end
    if n < 0x800 then return string.char(0xC0 + math.floor(n / 64), 0x80 + n % 64) end
    if n < 0x10000 then
        return string.char(0xE0 + math.floor(n / 4096), 0x80 + math.floor(n / 64) % 64, 0x80 + n % 64)
    end
    return string.char(0xF0 + math.floor(n / 262144), 0x80 + math.floor(n / 4096) % 64,
        0x80 + math.floor(n / 64) % 64, 0x80 + n % 64)
end

local function decode(s)
    return (s:gsub("&(#?x?[%w]+);", function(e)
        if entities[e] then return entities[e] end
        local n = e:match("^#x([%da-fA-F]+)$")
        if n then return utf8char(tonumber(n, 16)) end
        n = e:match("^#(%d+)$")
        if n then return utf8char(tonumber(n)) end
        error("unknown XML entity &" .. e .. ";")
    end))
end

local function attrs(s)
    local out, pos = {}, 1
    while true do
        local a, b, key, quote, value = s:find("%s+([%w_:.-]+)%s*=%s*(['\"])(.-)%2", pos)
        if not a then
            if s:sub(pos):match("^%s*$") then break end
            error("invalid XML attribute list near " .. s:sub(pos, pos + 30))
        end
        if s:sub(pos, a - 1):match("%S") then error("invalid XML attribute syntax") end
        out[key:lower()] = decode(value)
        pos = b + 1
    end
    return out
end

function XML.parse(source, limits)
    limits = limits or {}
    local max_nodes, max_depth = limits.max_nodes or 20000, limits.max_depth or 128
    if source:find("<!DOCTYPE", 1, true) or source:find("<!ENTITY", 1, true) then
        error("DTD/entity declarations are not supported")
    end
    source = source:gsub("^%s*<%?xml.-%?>", "", 1)
    local root, stack, pos, count = nil, {}, 1, 0
    local function text(s)
        if s ~= "" and #stack > 0 then table.insert(stack[#stack].children, decode(s)) end
    end
    while pos <= #source do
        local a, b = source:find("<", pos, true)
        if not a then text(source:sub(pos)); break end
        text(source:sub(pos, a - 1))
        if source:sub(a, a + 3) == "<!--" then
            local close = source:find("-->", a + 4, true); if not close then error("unclosed XML comment") end
            pos = close + 3
        else
            local close = source:find(">", a + 1, true); if not close then error("unclosed XML tag") end
            local body = source:sub(a + 1, close - 1)
            if body:sub(1, 1) == "/" then
                local name = body:sub(2):match("^%s*([%w_:.-]+)%s*$")
                if not name or #stack == 0 or stack[#stack].name ~= name:lower() then error("mismatched XML close tag") end
                table.remove(stack)
            elseif body:sub(1, 1) == "?" then
                error("unsupported processing instruction")
            else
                local empty = body:match("/%s*$") ~= nil
                if empty then body = body:gsub("/%s*$", "") end
                local name, rest = body:match("^%s*([%w_:.-]+)(.*)$")
                if not name then error("invalid XML tag") end
                count = count + 1; if count > max_nodes then error("XML node limit exceeded") end
                local node = { name = name:lower(), attr = attrs(rest), children = {} }
                if #stack > 0 then table.insert(stack[#stack].children, node)
                elseif root then error("multiple XML roots") else root = node end
                if not empty then
                    table.insert(stack, node); if #stack > max_depth then error("XML depth limit exceeded") end
                end
            end
            pos = close + 1
        end
    end
    if #stack ~= 0 then error("unclosed XML tag " .. stack[#stack].name) end
    if not root then error("empty XML document") end
    return root
end

function XML.read(path)
    local file, err = io.open(path, "rb"); if not file then return nil, err end
    local source = file:read("*a"); file:close()
    local ok, value = pcall(XML.parse, source)
    if not ok then return nil, value end
    return value
end

return XML
