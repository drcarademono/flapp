local InputContainer=require("ui/widget/container/inputcontainer")
local UIManager=require("ui/uimanager")
local TextViewer=require("ui/widget/textviewer")
local ImageViewer=require("ui/widget/imageviewer")
local InfoMessage=require("ui/widget/infomessage")
local _=require("gettext")

local GameView=InputContainer:extend{}

function GameView:start()
    local result,err=self.game:load(self.game.state.book,self.game.state.section)
    if not result then UIManager:show(InfoMessage:new{text=_("Unable to start Fabled Lands:\n")..tostring(err)}); UIManager:close(self); return end
    self:render(result)
end

function GameView:render(result)
    if self.viewer then UIManager:close(self.viewer) end
    local footer=string.format("\n\n[%s: %d/%d  •  %s: %d  •  %s: %d]",_("Stamina"),self.game.state.stamina,
        self.game.state.max_stamina,_("Rank"),self.game.state.rank,_("Shards"),self.game.state.shards)
    local buttons={}
    for i,a in ipairs(self.game.actions) do
        local index=i
        buttons[#buttons+1]={{text=tostring(i)..". "..a.label,callback=function()
            local next_result,err=self.game:choose(index)
            if next_result then self:render(next_result) else UIManager:show(InfoMessage:new{text=tostring(err)}) end
        end}}
    end
    buttons[#buttons+1]={
        {text=_("Map"),callback=function() self:showMap() end},
        {text=_("Sheet"),callback=function() self:showSheet() end},
        {text=_("Close"),callback=function() self.save:write(self.game.state); UIManager:close(self.viewer); UIManager:close(self) end},
    }
    self.viewer=TextViewer:new{title=result.title,text=result.text..footer,fullscreen=true,
        buttons_table=buttons}
    UIManager:show(self.viewer)
    self.save:write(self.game.state)
end

function GameView:showMap()
    local book=self.game.catalog.books[self.game.state.book]
    local map_name=book and book.properties.Map
    local map_path=map_name and self.game.catalog:asset_path(self.game.state.book,map_name)
    if not map_path then UIManager:show(InfoMessage:new{text=_("No map is available for this book.")}); return end
    UIManager:show(ImageViewer:new{image=map_path,fullscreen=true,with_title_bar=true,
        title=book.properties["Map.Title"] or _("Map")})
end

function GameView:showSheet()
    local s=self.game.state; local lines={s.name~="" and s.name or _("New adventurer"),s.profession,""}
    for _,name in ipairs(require("core/state").ability_names) do lines[#lines+1]=name..": "..tostring(s.abilities[name] or "—") end
    lines[#lines+1]=""; lines[#lines+1]=_("Possessions:")
    for _,item in ipairs(s.items) do lines[#lines+1]="• "..item.name..((item.quantity or 1)>1 and (" ×"..item.quantity) or "") end
    UIManager:show(TextViewer:new{title=_("Adventure sheet"),text=table.concat(lines,"\n")})
end

return GameView
