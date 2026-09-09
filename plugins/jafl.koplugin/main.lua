local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")

-- Set up relative path resolution for plugin submodules.
local plugin_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
if plugin_dir then
    package.path =
        plugin_dir .. "?.lua;" ..
        plugin_dir .. "?/init.lua;" ..
        package.path
end

local Catalog = require("content/catalog")
local Game = require("core/game")
local Save = require("core/save")
local State = require("core/state")
local GameView = require("ui/gameview")

local JaFL = WidgetContainer:extend {
    name = "jafl",
    is_doc_only = false,
}

function JaFL:init()
    self.save = Save.new(
        DataStorage:getSettingsDir() .. "/jafl.lua",
        LuaSettings
    )

    -- Register this plugin so KOReader will call addToMainMenu().
    self.ui.menu:registerToMainMenu(self)
end

function JaFL:contentRoot()
    -- An installed plugin ships a complete, mutually consistent six-book pack.
    -- Prefer it over a stale jafl_content_root left by an older/source install.
    local bundled = plugin_dir .. "contentpack"
    local f = io.open(bundled .. "/books.ini", "rb")

    if f then
        f:close()
        return bundled
    end

    local configured = G_reader_settings:readSetting("jafl_content_root")
    if configured then
        return configured
    end

    return plugin_dir .. "../.."
end

function JaFL:open(new_game)
    local state,load_error

    if not new_game then
        state,load_error = self.save:load()
        if load_error then
            UIManager:show(InfoMessage:new{text=_("Unable to load the saved adventure:\n")..tostring(load_error)})
            return
        end
    end

    state = state or State.new()

    local game = Game.new(
        Catalog.new(self:contentRoot()),
        state
    )

    self.game_view = GameView:new {
        game = game,
        save = self.save,
        title = _("Fabled Lands"),
    }

    self.game_view:start(new_game and game:choose_starting_book() or nil)
end

function JaFL:addToMainMenu(menu_items)
    menu_items.jafl = {
        text = _("Fabled Lands"),
        sorting_hint = "more_tools",

        sub_item_table = {
            {
                text = _("Continue adventure"),
                callback = function()
                    self:open(false)
                end,
            },

            {
                text = _("New adventure"),
                callback = function()
                    self:open(true)
                end,
            },
        },
    }
end

return JaFL
