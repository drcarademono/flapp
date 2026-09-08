local InputContainer=require("ui/widget/container/inputcontainer")
local RenderImage=require("ui/renderimage")
local UIManager=require("ui/uimanager")
local TextViewer=require("ui/widget/textviewer")
local ImageViewer=require("ui/widget/imageviewer")
local InfoMessage=require("ui/widget/infomessage")
local _=require("gettext")

local GameView=InputContainer:extend{}
local BOOK_TEXT_SIZE=12
local ACTIONS_PER_PAGE=6

function GameView:start(initial_result)
    local result,err=initial_result
    if not result then result,err=self.game:load(self.game.state.book,self.game.state.section) end
    if not result then UIManager:show(InfoMessage:new{text=_("Unable to start Fabled Lands:\n")..tostring(err)}); UIManager:close(self); return end
    self:render(result)
end

function GameView:render(result, action_page)
    if self.viewer then UIManager:close(self.viewer) end
    action_page=math.max(1,action_page or 1)
    local footer=string.format("\n\n[%s: %d/%d  •  %s: %d  •  %s: %d]",_("Stamina"),self.game.state.stamina,
        self.game.state.max_stamina,_("Rank"),self.game.state.rank,_("Shards"),self.game.state.shards)
    local buttons={}
    local action_count=#self.game.actions
    local page_count=math.max(1,math.ceil(action_count/ACTIONS_PER_PAGE))
    action_page=math.min(action_page,page_count)
    local first=(action_page-1)*ACTIONS_PER_PAGE+1
    local last=math.min(action_count,first+ACTIONS_PER_PAGE-1)
    for i=first,last do
        local a=self.game.actions[i]
        local index=i
        buttons[#buttons+1]={{text=tostring(i)..". "..a.label,text_font_size=BOOK_TEXT_SIZE,font_bold=false,callback=function()
            local next_result,err=self.game:choose(index)
            if next_result then self:render(next_result) else UIManager:show(InfoMessage:new{text=tostring(err)}) end
        end}}
    end
    if page_count>1 then
        local navigation={}
        if action_page>1 then navigation[#navigation+1]={text=_("Previous"),callback=function() self:render(result,action_page-1) end} end
        if action_page<page_count then navigation[#navigation+1]={text=_("Next"),callback=function() self:render(result,action_page+1) end} end
        buttons[#buttons+1]=navigation
    end
    buttons[#buttons+1]={
        {text=_("Map"),callback=function() self:showMap() end},
        {text=_("Sheet"),callback=function() self:showSheet() end},
        {text=_("Close"),callback=function() self.save:write(self.game.state); UIManager:close(self.viewer); UIManager:close(self) end},
    }
    local title=result.title
    if page_count>1 then title=string.format("%s — %d/%d",title,action_page,page_count) end
    self.viewer=TextViewer:new{title=title,text=result.text..footer,fullscreen=true,
        text_size=BOOK_TEXT_SIZE,font_size=BOOK_TEXT_SIZE,
        buttons_table=buttons}
    UIManager:show(self.viewer)
    self.save:write(self.game.state)
end

function GameView:showMap()
    local book=self.game.catalog.books[self.game.state.book]
    local map_name=book and book.properties.Map
    local map_path=map_name and self.game.catalog:asset_path(self.game.state.book,map_name)
    if not map_path then UIManager:show(InfoMessage:new{text=_("No map is available for this book.")}); return end
    local image=RenderImage:renderImageFile(map_path,false)
    if not image then UIManager:show(InfoMessage:new{text=_("Unable to open this book's map.")}); return end
    UIManager:show(ImageViewer:new{image=image,image_disposable=true,fullscreen=true,with_title_bar=true,
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
