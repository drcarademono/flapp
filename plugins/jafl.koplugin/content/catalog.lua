local Catalog = {}
Catalog.__index = Catalog

local function join(a, b)
    return a:gsub("/$", "") .. "/" .. b
end

local function exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

local function ini(path)
    local out = {}
    local last = nil

    local f = io.open(path, "rb")
    if not f then
        return out
    end

    for line in f:lines() do
        if line:match("^%s") and last then
            out[last] = out[last] .. line:gsub("^%s+", "")
        else
            local k, v = line:match("^%s*([^#;][^=]-)%s*=%s*(.-)%s*$")
            if k then
                last = k
                out[k] = v:gsub("\\$", "")
            else
                last = nil
            end
        end
    end

    f:close()
    return out
end

function Catalog.new(root)
    local self = setmetatable({
        root = root,
        books = {},
    }, Catalog)

    local listing = ini(join(root, "books.ini"))

    for key in (listing.Books or "1,2,3,4,5,6"):gmatch("[^,%s]+") do
        local dir = "book" .. key
        local path = join(root, dir)

        self.books[key] = {
            key = key,
            title = listing[key .. ".Title"] or ("Book " .. key),
            path = path,
            installed = exists(join(path, "book.ini")),
            properties = ini(join(path, "book.ini")),
        }
    end

    return self
end

function Catalog:section_path(book, section)
    local entry = self.books[tostring(book)]

    if not entry or not entry.installed then
        return nil, "Book " .. tostring(book) .. " is not installed"
    end

    local safe = tostring(section):match("^[%w _.-]+$")

    if not safe or safe:find("..", 1, true) then
        return nil, "Invalid section name"
    end

    local path = join(entry.path, safe .. ".xml")

    if not exists(path) then
        return nil, "Missing section " .. tostring(book) .. "/" .. safe
    end

    return path
end

function Catalog:asset_path(book, name)
    if not name
        or name:find("..", 1, true)
        or name:sub(1, 1) == "/"
    then
        return nil
    end

    local entry = self.books[tostring(book)]

    if not entry then
        return nil
    end

    local candidates = {
        join(entry.path, name),
        join(self.root, "illus" .. tostring(book) .. "/" .. name),
        join(self.root, name),
    }

    for _, path in ipairs(candidates) do
        if exists(path) then
            return path
        end
    end

    return nil
end

return Catalog
