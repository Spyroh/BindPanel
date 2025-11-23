--╔═══════════════════════════╗
--║ ┌┐ ┬┌┐┌┌┬┐┌─┐┌─┐┌┐┌┌─┐┬   ║
--║ ├┴┐││││ ││├─┘├─┤│││├┤ │   ║
--║ └─┘┴┘└┘─┴┘┴  ┴ ┴┘└┘└─┘┴─┘ ║
--╠═══════════════════════════╣
--║  By Spyro [Sanguino EU]   ║
--╚═══════════════════════════╝

--[[ Upvalues of frequently used functions ]]---------------------------------------------------------------------------------------------------------
local gsub, strlenutf8, CreateFrame, SetOverrideBinding, SetOverrideBindingClick, GetTalentTabInfo, GetTalentTreeRoles, GetSpecialization                                          , GetSpecializationInfo
    = gsub, strlenutf8, CreateFrame, SetOverrideBinding, SetOverrideBindingClick, GetTalentTabInfo, GetTalentTreeRoles, GetSpecialization or C_SpecializationInfo.GetSpecialization, GetSpecializationInfo or C_SpecializationInfo.GetSpecializationInfo

--[[ Local namespace vars ]]--------------------------------------------------------------------------------------------------------------------------
local _,_,_,TocVersion = GetBuildInfo()
local IsClassic = WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE
local IsPreCata = TocVersion < 40000
local HasSkyriding = TocVersion >= 100000
local Vehicle = HasSkyriding and "Vehicle/Skyriding" or "Vehicle"
local Event = CreateFrame("Frame") -- Frame for event processing
local Panel = CreateFrame("Frame", "BindPanel_Panel", UIParent, "ButtonFrameTemplate") -- Main panel
local BindCatcher = CreateFrame("Frame", "BindPanel_BindCatcher", UIParent) -- Catches the keybind pressed when creating/editing a macro
local MacroKeybindCatchDialog = CreateFrame("Frame", nil, UIParent, "DialogBoxFrame") -- Showed to the user when waiting to catch a keybind for a macro
local TotalMacroButtons = 0 -- Total of macro buttons created
local FreeMacroButtons = {} -- Stores the unused macro buttons, to be reused later
local KeybindToButton = {} -- Stores each keybind and the name of the macro button that it runs
local KeybindSelected -- Stores the keybind selected to be edited
local ScrollBox -- Scrollbox for the list of keybinds
local SpecMenu -- DropDown to select the current specialization in the main panel
local StackSplitCancel = StackSplitCancelButton or StackSplitFrame.CancelButton -- Button for closing the StackSplitFrame
local Dialog -- Defined later

-- SavedVariable
BindPanelDB = BindPanelDB or {}
local DB = BindPanelDB

-- Font for the keybind list buttons
CreateFont("BindPanel_BindFont")
local BindPanel_BindFont = BindPanel_BindFont -- Upvalue
BindPanel_BindFont:SetFont("Fonts/FRIZQT__.TTF", 16, "")
BindPanel_BindFont:SetShadowOffset(1, -1)

-- FontString similar to the ones inside the buttons of the keybind list
-- Used in UpdateKeybindListWidth() to generate the real width from the keybind text
local KeybindString = Panel:CreateFontString(nil, "ARTWORK", "BindPanel_BindFont")
KeybindString:Hide()

-- Data provider for the keybind list
local KeybindListDataProvider = CreateDataProvider()
KeybindListDataProvider:SetSortComparator(function(A, B) -- Sorting keybinds by alphabetical order ignoring the modifiers
  -- Removing modifiers
  local A_nomod = gsub(A, "%u+%-", "")
  local B_nomod = gsub(B, "%u+%-", "")

  if A_nomod == B_nomod then return strlenutf8(A) < strlenutf8(B) end -- If same key with different modifiers, put the shorter first
  return A_nomod < B_nomod
end, true)

--[[ General functions ]]-----------------------------------------------------------------------------------------------------------------------------
-- Msg()
-- Shows messages in the chat window.
local function Msg(Text, ...)
  print("|cFFFFFF00[BindPanel]|r", format(Text, ...))
end

-- InCombat()
-- Returns if the player is in combat. If true, it shows an alert message because this
-- function is called before trying to edit macros, which can't be done in combat.
local function InCombat()
  local PlayerInCombat = InCombatLockdown()

  if PlayerInCombat then
    Msg("You have to be out of combat to perform that action.")
    PlaySound(847)
  end

  return PlayerInCombat
end

-- GetNumSpecs()
-- Return the total numbers of specializations.
local GetNumSpecs = GetNumSpecializations or GetNumTalentTabs -- Retail/MoP or Vanilla/TBC/WotLK/Cata

-- GetPlayerSpec()
-- Returns the current class specialization index.
local function GetPlayerSpec()
  local SpecIndex

  if GetSpecialization then -- Retail/MoP
    Spec = GetSpecialization()
    if Spec ~= 5 then SpecIndex = Spec end
  else -- Vanilla/TBC/WotLK/Cata
    SpecIndex = GetPrimaryTalentTree(false, false, GetActiveTalentGroup()) -- Talent tree with the most points spent
  end

  return SpecIndex
end

-- GetSpecName()
-- Returns the name of a specialization.
local function GetSpecName(SpecIndex)
  if GetSpecializationInfo then -- Retail/MoP
    local _,Name = GetSpecializationInfo(SpecIndex)
    return Name
  else -- Vanilla/TBC/WotLK/Cata
    local _,Name = GetTalentTabInfo(SpecIndex)
    return Name
  end 
end

-- GetKeybindVisual()
-- Returns a more aesthetically pleasing string of a keybind, removing the L from left
-- modifiers (LALT, LCTRL, LSHIFT) if it hasn't any right modifiers (RALT, RCTRL, RSHIFT).
local function GetKeybindVisual(Keybind)
  if not Keybind:match("R%u%u%u+%-") then Keybind = Keybind:gsub("L(%u%u%u+%-)", "%1") end
  return Keybind
end

-- GetKeybindInternal()
-- Returns the internal representation of a keybind, adding the L to left modifiers (ALT, CTRL, SHIFT) that don't have it coz they were parsed by
-- GetKeybindVisual(), which only happens when left modifiers are used alone without right modifiers (RALT, RCTRL, RSHIFT) in the same keybind.
local function GetKeybindInternal(Keybind)
  Keybind = Keybind:gsub("%u+%-", function(Mod) return Mod:gsub("^[^LR]%u+%-", "L%1") end) -- Adding the L to modifiers
  return Keybind
end

-- Bind()
-- Makes a keybind execute macro code when pressed and saves it in the DB for the current spec.
local function Bind(Keybind, Macro)
  if KeybindToButton[Keybind] then -- If it's already bound, just update the macro
    KeybindToButton[Keybind]:SetAttribute("macrotext", Macro)
  else -- If not, create a new bind
    local Button

    -- Creating a button that executes a macro when clicked
    if FreeMacroButtons[#FreeMacroButtons] then -- Checking if there is any unused button, to reuse it
      Button = FreeMacroButtons[#FreeMacroButtons]
      FreeMacroButtons[#FreeMacroButtons] = nil
    else -- If there's none, create a new one
      TotalMacroButtons = TotalMacroButtons + 1
      Button = CreateFrame("Button", "BindPanel_MacroButton"..TotalMacroButtons, nil, "SecureActionButtonTemplate")
      Button:RegisterForClicks("AnyDown")
      Button:SetAttribute("type", "macro")
    end

    Button:SetAttribute("macrotext", Macro)
    SetOverrideBindingClick(Panel, false, Keybind, Button:GetName()) -- Binding keybind to the button
    KeybindToButton[Keybind] = Button -- Keybind->Button relation to be able to update/delete after
    KeybindListDataProvider:Insert(GetKeybindVisual(Keybind))
  end

  DB[DB.CurrentSpec][Keybind] = Macro
end

-- Unbind()
-- Frees a keybind that is bound to a macro button.
-- SkipDB is used when changing specs to avoid removing the DB data from the previous spec.
local function Unbind(Keybind, SkipDB)
  if not KeybindToButton[Keybind] then return end -- Keybind is not bound

  SetOverrideBinding(Panel, false, Keybind, nil)
  KeybindToButton[Keybind]:SetAttribute("macrotext", nil)
  FreeMacroButtons[#FreeMacroButtons + 1] = KeybindToButton[Keybind]
  KeybindToButton[Keybind] = nil
  KeybindListDataProvider:Remove(GetKeybindVisual(Keybind))
  if not SkipDB then DB[DB.CurrentSpec][Keybind] = nil end
end

-- AddMacroKeybind()
-- Function executed when the user has pressed a keybind to create or locate a macro via the BindCatcher.
local function AddMacroKeybind(Keybind)
  if not Keybind then return end

  -- If it doesn't exist yet
  if not KeybindToButton[Keybind] then
    -- Left and Right of the same modifier, not supported by the current WoW API for SetOverrideBindingClick()
    if IsRightAltKeyDown() and IsLeftAltKeyDown() or IsRightControlKeyDown() and IsLeftControlKeyDown() or IsRightShiftKeyDown() and IsLeftShiftKeyDown() then
      Panel:Show()

      local LRmod
      if IsRightAltKeyDown()     and IsLeftAltKeyDown()     then LRmod = "alt"   end
      if IsRightControlKeyDown() and IsLeftControlKeyDown() then LRmod = "ctrl"  end
      if IsRightShiftKeyDown()   and IsLeftShiftKeyDown()   then LRmod = "shift" end

      Dialog("Same modifier", "Creating a keybind with both versions (Left and Right) of the same modifier is not supported by the current WoW API, but you can do that inside a macro with the [mod:l%s,mod:r%s] conditional.", LRmod, LRmod)
      Panel.EditBox:ClearFocus()
      RunNextFrame(function() Panel.EditBox:SetFocus() end) -- Delay needed so the pressed key is not written in the editbox
      return
    end

    Bind(Keybind, "")
  end

  Panel:Show()
  Panel.UpdateKeybindListWidth()
  Panel.EditBox:ClearFocus()
  RunNextFrame(function() ScrollBox:SelectElement(GetKeybindVisual(Keybind)) end) -- Delay needed so the pressed key is not written in the editbox
end

-- LoadSpecBindings()
-- Loads the keybindings that execute macro code.
local function LoadSpecBindings(SpecIndex)
  if not InCombat() then
    -- Unloading the bindings from the previous spec
    for Keybind, _ in pairs(DB[DB.CurrentSpec]) do
      Unbind(Keybind, true)
    end

    DB.CurrentSpec = SpecIndex -- New current specialization

    -- Loading the bindings of the new spec
    for Keybind, Macro in pairs(DB[SpecIndex]) do
      Bind(Keybind, Macro)
    end

    -- Cleaning panel
    KeybindSelected = nil
    Panel.UpdateKeybindListWidth()
    Panel.EditBox:SetText("")
    Panel.EditBox:Disable()
    Panel.SaveButton:Disable()
    Panel.CancelButton:Disable()
    Panel.DeleteButton:Disable()

    -- If the panel is visible, select the first keybind on the list
    if Panel:IsVisible() and not KeybindListDataProvider:IsEmpty() then
      ScrollBox:SelectFirstElement()
    end
  end

  if SpecMenu:IsVisible() then SpecMenu:GenerateMenu() end -- If the spec menu from the main panel is visible, update it
end

--[[ Main panel ]]------------------------------------------------------------------------------------------------------------------------------------
Panel.DefaultWidth = IsClassic and 820 or 824
Panel:SetFrameStrata("DIALOG")
Panel:SetMovable(true)
Panel:SetSize(Panel.DefaultWidth, 503)
Panel:Hide()
Panel:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
Panel.TitleContainer.TitleText:SetText("BindPanel")
Panel.TitleContainer.TitleText:ClearAllPoints()
Panel.TitleContainer.TitleText:SetPoint("CENTER", Panel.TitleContainer, "CENTER", 0, IsClassic and 1 or -1)
ButtonFrameTemplate_HidePortrait(Panel)
tinsert(UISpecialFrames, "BindPanel_Panel")

-- Position
if DB.PanelOffsetX then
  Panel:ClearAllPoints()
  Panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", DB.PanelOffsetX, DB.PanelOffsetY)
end

-- Frame to move the panel from the title bar
local TitleBarMover = CreateFrame("Frame", nil, Panel)
TitleBarMover:SetPoint("TOPLEFT", Panel, "TOPLEFT", 5, -1)
TitleBarMover:SetPoint("BOTTOMRIGHT", Panel, "TOPRIGHT", -23, -21)

TitleBarMover:SetScript("OnMouseDown", function()
  Panel:StartMoving()
  Panel:SetUserPlaced(false)
end)

TitleBarMover:SetScript("OnMouseUp", function()
  Panel:StopMovingOrSizing()
  DB.PanelOffsetX = Panel:GetLeft()
  DB.PanelOffsetY = Panel:GetBottom()
  Panel:ClearAllPoints()
  Panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", DB.PanelOffsetX, DB.PanelOffsetY)
end)

-- Inset for the left column
Panel.LeftInset = BindPanel_PanelInset -- Inset of the left column, already created in ButtonFrameTemplate
Panel.LeftInset.TopLeftOffset = IsClassic and 12 or 17
Panel.LeftInset.BottomRightOffset = Panel.LeftInset.TopLeftOffset + 153 -- Default horizontal offset of the 2nd anchor (determines the width)
Panel.LeftInset:ClearAllPoints()
Panel.LeftInset:SetPoint("TOPLEFT", Panel, "TOPLEFT", Panel.LeftInset.TopLeftOffset, -55)
Panel.LeftInset:SetPoint("BOTTOMRIGHT", Panel, "BOTTOMLEFT", Panel.LeftInset.BottomRightOffset, 27)

-- Label for the left column
local BindLabel = Panel:CreateFontString()
BindLabel:SetFont("Fonts/FRIZQT__.TTF", 20)
BindLabel:SetShadowOffset(1, -1)
BindLabel:SetPoint("BOTTOM", Panel.LeftInset, "TOP", 0, 0)
BindLabel:SetJustifyH("CENTER")
BindLabel:SetText("|cFFFFD100Bind")

-- Inset for the right column
Panel.RightInset = CreateFrame("Frame", nil, Panel, "InsetFrameTemplate") -- Inset for the right column
Panel.RightInset:SetPoint("TOPRIGHT", Panel, "TOPRIGHT", IsClassic and -14 or -13, -55)
Panel.RightInset:SetPoint("BOTTOMLEFT", Panel.LeftInset, "BOTTOMRIGHT", 10, 0)
Panel.RightInset.Bg:SetTexture(4185455)
if IsClassic then Panel.RightInset.Bg:SetColorTexture(0.086, 0.082, 0.118, 1)
else Panel.RightInset.Bg:SetVertexColor(0.09, 0.09, 0.18, 1) end

-- Label for the right column
local MacroLabel = Panel:CreateFontString()
MacroLabel:SetFont("Fonts/FRIZQT__.TTF", 20)
MacroLabel:SetShadowOffset(1, -1)
MacroLabel:SetPoint("BOTTOMLEFT", Panel.RightInset, "TOPLEFT", 4, 0)
MacroLabel:SetJustifyH("LEFT")
MacroLabel:SetText("|cFFFFD100Macro")

-- Function to adapt the width of the keybind list column (and its buttons coz they
-- automatically grow with it) to the widest FontString inside any of the buttons
function Panel.UpdateKeybindListWidth()
  local KeybindList = KeybindListDataProvider:GetCollection()
  local OffsetX = Panel.LeftInset.BottomRightOffset

  if #KeybindList > 0 then
    Panel:SetWidth(Panel.DefaultWidth)
    local DefaultWidth = Panel.LeftInset.BottomRightOffset - Panel.LeftInset.TopLeftOffset
    local WidestFontString = 0

    -- Finding the widest FontString inside the buttons
    for i = 1, #KeybindList do
      KeybindString:SetText(KeybindList[i]) -- FontString similar to the ones inside the buttons, to generate the width from the keybind text
      local FontStringWidth = KeybindString:GetUnboundedStringWidth() -- Real width of the FontString that shows the keybind
      if FontStringWidth > WidestFontString then WidestFontString = FontStringWidth end -- Storing the highest width found
    end

    local NeededWidth = WidestFontString + 37 -- FontString width + padding + button borders + inset borders
    if NeededWidth > DefaultWidth then
      OffsetX = Panel.LeftInset.TopLeftOffset + NeededWidth -- Offset needed to fit this FontString
      Panel:SetWidth(Panel.DefaultWidth + NeededWidth - DefaultWidth) -- Increasing the panel's width too so the Editor doesn't get smaller
    end
  end

  Panel.LeftInset:SetPoint("BOTTOMRIGHT", Panel, "BOTTOMLEFT", OffsetX, 27) -- Anchor that determines the width of the inset/column
  Panel.EditBox:UpdateWidth()
end

--[[ ScrollBox for the list of keybinds ]]------------------------------------------------------------------------------------------------------------
ScrollBox = CreateFrame("Frame", nil, Panel, "WowScrollBoxList")

-- Anchors for the ScrollBox
local AnchorsWithoutScrollBar = {
  CreateAnchor("TOPLEFT", Panel.LeftInset, "TOPLEFT", 2, -3),
  CreateAnchor("BOTTOMRIGHT", Panel.LeftInset, "BOTTOMRIGHT", -2, 2)
}
local AnchorsWithScrollBar = {
  CreateAnchor("TOPLEFT", Panel.LeftInset, "TOPLEFT", 2, -3),
  CreateAnchor("BOTTOMRIGHT", Panel.LeftInset, "BOTTOMRIGHT", -18, 2)
}

-- Function to select a keybind on the list
function ScrollBox:SelectElement(Keybind)
  self:ScrollToElementData(Keybind)
  self:FindFrame(Keybind):Click()
end

-- Function to select the first keybind on the list
function ScrollBox:SelectFirstElement()
  self:SelectElement(self:FindElementData(1))
end

-- ScrollBar
local ScrollBar = CreateFrame("EventFrame", nil, Panel, "MinimalScrollBar")
ScrollBar:ClearAllPoints()
ScrollBar:SetPoint("TOPRIGHT", Panel.LeftInset, "TOPRIGHT", IsClassic and -8 or -7, -3)
ScrollBar:SetPoint("BOTTOMLEFT", Panel.LeftInset, "BOTTOMRIGHT", -16, 1)
ScrollUtil.AddManagedScrollBarVisibilityBehavior(ScrollBox, ScrollBar, AnchorsWithScrollBar, AnchorsWithoutScrollBar)

local ScrollView = CreateScrollBoxListLinearView()
local function Initializer(Frame, Node) Frame:Init(Node) end
local function CustomFactory(Factory, Node) Factory(Node:GetData().Template, Initializer) end
ScrollView:SetElementFactory(CustomFactory)
ScrollView:SetDataProvider(KeybindListDataProvider)
ScrollUtil.InitScrollBoxListWithScrollBar(ScrollBox, ScrollBar, ScrollView)

-- Highlight for the selected keybind
local KeybindSelectedHighlight = Panel:CreateTexture(nil, "OVERLAY")
KeybindSelectedHighlight:SetTexture("Interface/Buttons/UI-Silver-Button-Highlight")
KeybindSelectedHighlight:SetTexCoord(0, 1.0, 0.03, 0.7175)
KeybindSelectedHighlight:SetBlendMode("ADD")
KeybindSelectedHighlight:Hide()
local function KeybindMarkSelected(Button, Keybind) -- This keybind comes parsed by GetKeybindVisual()
  KeybindSelectedHighlight:SetParent(Button)
  KeybindSelectedHighlight:ClearAllPoints()
  KeybindSelectedHighlight:SetAllPoints()
  KeybindSelectedHighlight:Show()
  KeybindSelected = Keybind
end

-- Initializer for the buttons in the keybind list. This is executed every time any of them appears
ScrollView:SetElementInitializer("UIMenuButtonStretchTemplate", function(Button, Keybind) -- This keybind comes parsed by GetKeybindVisual()
  Button:SetNormalFontObject(BindPanel_BindFont)
  Button:SetHighlightFontObject(BindPanel_BindFont)
  Button:SetText(Keybind)

  Button:SetScript("OnClick", function()
    if KeybindSelected then
      if KeybindSelected == Keybind then Panel.EditBox:SetFocus() return -- Already selected
      else Panel.SaveButton:Click() end -- Newly selected, saving the previously selected bind in case the user forgot to do it
    end

    KeybindMarkSelected(Button, Keybind)
    Panel.SaveButton:Enable()
    Panel.CancelButton:Enable()
    Panel.DeleteButton:Enable()
    Panel.EditBox:Enable()
    Panel.EditBox:SetText(DB[DB.CurrentSpec][GetKeybindInternal(Keybind)])
    Panel.EditBox:SetFocus()
  end)

  KeybindSelectedHighlight:Hide()
  KeybindSelectedHighlight:ClearAllPoints()

  if KeybindSelected then -- Highlighting the keybind currently selected for edition
    local SelectedButton = ScrollBox:FindFrame(KeybindSelected)
    if SelectedButton then KeybindMarkSelected(SelectedButton, KeybindSelected) end
  end
end)

--[[ EditBox to write the macro text ]]---------------------------------------------------------------------------------------------------------------
Panel.EditBox = CreateFrame("EditBox", nil, Panel)
local EditBox = Panel.EditBox
EditBox:Disable()
EditBox:SetAutoFocus(false)
EditBox:SetMultiLine(true)
EditBox:SetFontObject(GameFontNormalLarge)
EditBox:SetTextColor(1, 1, 1)
EditBox:SetCountInvisibleLetters(false)
EditBox:SetScript("OnEscapePressed", function() EditBox:ClearFocus() end)
EditBox:HookScript("OnShow", function() EditBox:SetFocus() end)
Panel:HookScript("OnMouseDown", function() EditBox:SetFocus() end)

-- Method to avoid triggering the SetText() hook coz it would cause an infinite loop
local OtherEditBox = CreateFrame("EditBox") -- Just to use its SetText method
OtherEditBox:Hide()
OtherEditBox:UnregisterAllEvents()
function EditBox:SilentSetText(Text)
  OtherEditBox.SetText(self, Text)
end

-- Method that returns the EditBox's text without syntax highlight colors
function EditBox:GetCleanText()
  return self:GetText():gsub("|cFF%x%x%x%x%x%x", ""):gsub("|r", "")
end

-- Method that adds macro syntax highlight to the EditBox's text
function EditBox:SyntaxHighlight()
  local CurPos = self:GetCursorPosition()
  local Text = self:GetText()

  Text = Text:sub(1, CurPos).."\2"..Text:sub(CurPos + 1) -- Inserting invisible character to locate the cursor's position after
  Text = Text:gsub("|cFF%x%x%x%x%x%x", ""):gsub("|r", "") -- Cleaning previous colors
  Text = Text:gsub("(%b[])", "|cFFFFFF00%1|r") -- Coloring (yellow conditional blocks)

  CurPos = Text:find("\2") -- New position for the cursor, which will be different than the initial due to the color codes added/removed
  Text = Text:gsub("\2", "") -- Removing locator character
  self:SilentSetText(Text)
  self:SetCursorPosition(CurPos - 1)
end

-- Hook to trigger syntax highlight when the text is programmatically changed
hooksecurefunc(EditBox, "SetText", function(self)
  self:SyntaxHighlight()
end)

-- Hook to trigger syntax highlight when the text is changed by the user
-- This can't be used for programmatically changes coz it would trigger an infinite loop
EditBox:HookScript("OnTextChanged", function(self, ChangedByUser)
  if ChangedByUser then self:SyntaxHighlight() end
end)

-- Function to insert an entity's name into the EditBox's text
function EditBox:InsertMacroEntity(Type, Name)
  if Type == "spell" and C_Spell.IsSpellPassive(Name) then return end

  local CursorPosition = self:GetCursorPosition()
  if CursorPosition == 0 or self:GetText():sub(CursorPosition, CursorPosition) == "\n" then
    if Type == "item" then -- Items
      if C_Item.GetItemSpell(Name) then self:Insert("/use "..Name.."\n")
      else self:Insert("/equip "..Name.."\n") end
    else -- Abilities
      self:Insert("/use "..Name.."\n") -- Using /use instead of /cast for abilities coz it's shorter and works the same
    end
  else
    self:Insert(Name)
  end
end

-- Drag & drop of items/abilities in the Editor
local function OnReceiveDrag()
  local Name
  local Type, Arg1, _, Arg3 = GetCursorInfo()
  ClearCursor()

  if     Type == "macro"     then Name = GetMacroBody(Arg1)
  elseif Type == "item"      then Name = C_Item.GetItemNameByID(Arg1)
  elseif Type == "spell"     then Name = C_Spell.GetSpellName(Arg3)..(IsPreCata and "("..GetSpellSubtext(Arg3)..")" or "")
  elseif Type == "petaction" then Name = C_Spell.GetSpellName(Arg1)
  elseif Type == "mount"     then Name = C_MountJournal.GetMountInfoByID(Arg1)
  elseif Type == "companion" then Name = C_MountJournal.GetDisplayedMountInfo(Arg1) -- Mounts in Cata
  elseif Type == "battlepet" then Name = select(8, C_PetJournal.GetPetInfoByPetID(Arg1)) end

  if not Name then return end
  EditBox:InsertMacroEntity(Type, Name)
  EditBox:SetFocus()
end
Panel:HookScript("OnReceiveDrag", OnReceiveDrag)
EditBox:HookScript("OnReceiveDrag", OnReceiveDrag)

-- Hook for linking spells to the Editor in Vanilla/TBC/WotLK, adding the spell rank
if IsPreCata then
  hooksecurefunc("SpellButton_OnModifiedClick", function(self)
    local Slot = SpellBook_GetSpellBookSlot(self)
    if Slot > MAX_SPELLS then return end

    if IsModifiedClick("CHATLINK") and EditBox:IsVisible() and EditBox:HasFocus() then
      local SpellName, SpellRank = GetSpellBookItemName(Slot, SpellBookFrame.bookType)
      if SpellName and not IsPassiveSpell(Slot, SpellBookFrame.bookType) then
        if SpellRank and strlen(SpellRank) > 0 then EditBox:InsertMacroEntity("spell", SpellName.."("..SpellRank..")")
        else EditBox:InsertMacroEntity("spell", SpellName) end
      end
    end
  end)
end

-- Hook for linking in Cata/MoP Classic
-- In these iterations of the game the Spellbook is bugged and doesn't have linking (SHIFT+Click doesn't do anything)
if WOW_PROJECT_ID == WOW_PROJECT_CATACLYSM_CLASSIC or WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC then
  for i = 1, 12 do
    local Button = _G["SpellButton"..i]
    Button:HookScript("OnClick", function(self)
      local Slot = SpellBook_GetSpellBookSlot(self)
      if Slot > MAX_SPELLS then return end

      if IsModifiedClick("CHATLINK") and EditBox:IsVisible() and EditBox:HasFocus() then
        local SpellName = GetSpellBookItemName(Slot, SpellBookFrame.bookType)
        if SpellName and not IsPassiveSpell(Slot, SpellBookFrame.bookType) then
          EditBox:InsertMacroEntity("spell", SpellName)
        end
      end
    end)
  end
end

-- General hook for linking stuff to the Editor
hooksecurefunc("ChatEdit_InsertLink", function(Link)
  if Link and EditBox:IsVisible() and EditBox:HasFocus() then
    local Type = LinkUtil.ExtractLink(Link)

    -- Linking only if it's a post-WotLK expansion or if it's pre-Cata and not a spell
    if not IsPreCata or IsPreCata and Type ~= "spell" and Type ~= nil then -- Type is nil in Vanilla
      EditBox:InsertMacroEntity(Type, StripHyperlinks(Link))
    end

    -- If it's an item, hide the StackSplitFrame for splittable items
    if Type == "item" then
      StackSplitFrame:SetAlpha(0) -- Hiding so it won't be shown for a microsecond before it's closed in the next frame
      RunNextFrame(function()
        StackSplitFrame:SetAlpha(1)
        StackSplitCancel:Click()
      end)
    end
  end
end)

-- Scroll for the EditBox
local ScrollFrame = CreateFrame("ScrollFrame", nil, Panel, "ScrollFrameTemplate")
ScrollFrame:SetPoint("TOPLEFT", Panel.RightInset, "TOPLEFT", 8, -8)
ScrollFrame:SetPoint("BOTTOMRIGHT", Panel.RightInset, "BOTTOMRIGHT", -8, 2)
ScrollFrame:SetScrollChild(EditBox)
EditBox:SetWidth(ScrollFrame:GetWidth())

-- ScrollBar
ScrollFrame.ScrollBar:Hide()
ScrollBar = ScrollFrame.ScrollBar
if IsClassic then -- Changing the ugly-ass scrollbar that appers in Classic for the modern one from Retail
  ScrollBar = CreateFrame("EventFrame", nil, ScrollFrame, "MinimalScrollBar")
  ScrollUtil.InitScrollFrameWithScrollBar(ScrollFrame, ScrollBar)
end
ScrollBar:SetHideIfUnscrollable(true)
ScrollBar:ClearAllPoints()
ScrollBar:SetPoint("TOPRIGHT", Panel.RightInset, "TOPRIGHT", -7, -3)
ScrollBar:SetPoint("BOTTOMLEFT", Panel.RightInset, "BOTTOMRIGHT", -16, 1)
ScrollBar:HookScript("OnHide", function() EditBox:UpdateWidth() end)
ScrollBar:HookScript("OnShow", function() EditBox:UpdateWidth() end)

-- Function to update the EditBox width
function EditBox:UpdateWidth()
  self:SetWidth(ScrollFrame:GetWidth() - (ScrollBar:IsVisible() and 12 or 0)) -- Less width if the ScrollBar is visible, to make room for it
end

-- Move the scrollbar down if we surpass the limit of the EditBox while writing
EditBox:HookScript("OnCursorChanged", function(self, NewX, NewY, CursorWidth, CursorHeight)
  local vs = ScrollFrame:GetVerticalScroll()
  if (vs + NewY) > 0 or (vs + NewY - CursorHeight + ScrollFrame:GetHeight()) < 0 then
    ScrollFrame:SetVerticalScroll(NewY * -1)
  end
end)

--[[ Character counter ]]-----------------------------------------------------------------------------------------------------------------------------
Panel.CharCounter = Panel:CreateFontString() 
Panel.CharCounter:Hide()
Panel.CharCounter:SetFont("Fonts/FRIZQT__.TTF", 11)
Panel.CharCounter:SetShadowOffset(1, -1)
Panel.CharCounter:SetPoint("TOP", Panel.RightInset, "BOTTOM", 0, -6)
Panel.CharCounter:SetJustifyH("RIGHT")
EditBox:HookScript("OnTextChanged", function()
  local MacroLength = EditBox:GetNumLetters()
  MacroLength = MacroLength > 255 and "|cFFFF0000"..MacroLength.."|r" or MacroLength -- Red if we surpass the limit
  Panel.CharCounter:SetText(MacroLength.."/"..255)
end)

-- Hiding character counter when the EditBox is disabled
hooksecurefunc(EditBox, "Disable", function() Panel.CharCounter:Hide() end)
hooksecurefunc(EditBox, "Enable", function() Panel.CharCounter:Show() end)

Panel:HookScript("OnShow", function()
  PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
  if not KeybindSelected and not KeybindListDataProvider:IsEmpty() then -- If no keybind selected, select the first one on the list
    ScrollBox:SelectFirstElement()
  end
end)

Panel:HookScript("OnHide", function()
  PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
  EditBox:ClearFocus()
end)

--[[ Buttons ]]---------------------------------------------------------------------------------------------------------------------------------------
Panel.AddButton = CreateFrame("Button", nil, Panel, "GameMenuButtonTemplate")
Panel.AddButton:SetText("Add / Locate")
Panel.AddButton:SetPoint("TOPLEFT", Panel.LeftInset, "BOTTOMLEFT", -1, -1)
Panel.AddButton:SetPoint("BOTTOMRIGHT", Panel.LeftInset, "BOTTOMRIGHT", 1, -22)
Panel.AddButton:SetScript("OnClick", function()
  if not InCombat() then BindCatcher:Run(MacroKeybindCatchDialog, AddMacroKeybind) end
end)

Panel.SaveButton = CreateFrame("Button", nil, Panel, "GameMenuButtonTemplate")
Panel.SaveButton:Disable()
Panel.SaveButton:SetWidth(100)
Panel.SaveButton:SetText("Save")
Panel.SaveButton:SetPoint("TOPLEFT", Panel.RightInset, "BOTTOMLEFT", -1, -1)
Panel.SaveButton:SetScript("OnClick", function()
  if InCombat() then return end
  PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
  Bind(GetKeybindInternal(KeybindSelected), EditBox:GetCleanText())
end)

Panel.CancelButton = CreateFrame("Button", nil, Panel, "GameMenuButtonTemplate")
Panel.CancelButton:Disable()
Panel.CancelButton:SetWidth(100)
Panel.CancelButton:SetText("Cancel")
Panel.CancelButton:SetPoint("LEFT", Panel.SaveButton, "RIGHT", -1, 0)
Panel.CancelButton:SetScript("OnClick", function()
  PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
  Panel.EditBox:SetText(DB[DB.CurrentSpec][GetKeybindInternal(KeybindSelected)])
  Panel.EditBox:SetFocus()
end)

Panel.ExitButton = CreateFrame("Button", nil, Panel, "GameMenuButtonTemplate")
Panel.ExitButton:SetWidth(100)
Panel.ExitButton:SetText("Exit")
Panel.ExitButton:SetPoint("TOPRIGHT", Panel.RightInset, "BOTTOMRIGHT", 1, -1)
Panel.ExitButton:SetScript("OnClick", function()
  if KeybindSelected then Panel.SaveButton:Click() end
  Panel:Hide()
end)
BindPanel_PanelCloseButton:HookScript("OnClick", function()
  if KeybindSelected then Panel.SaveButton:Click() end
  Panel:Hide()
end)

Panel.DeleteButton = CreateFrame("Button", nil, Panel, "GameMenuButtonTemplate")
Panel.DeleteButton:Disable()
Panel.DeleteButton:SetWidth(100)
Panel.DeleteButton:SetText("Delete")
Panel.DeleteButton:SetPoint("RIGHT", Panel.ExitButton, "LEFT", 1, 0)
Panel.DeleteButton:SetScript("OnClick", function()
  if InCombat() then return end
  PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
  Unbind(GetKeybindInternal(KeybindSelected))

  KeybindSelected = nil
  Panel.UpdateKeybindListWidth()
  Panel.EditBox:SetText("")
  Panel.EditBox:Disable()
  Panel.SaveButton:Disable()
  Panel.CancelButton:Disable()
  Panel.DeleteButton:Disable()
end)

--[[ Dialog to show messages to the user ]]-----------------------------------------------------------------------------------------------------------
local MsgDialogBase = CreateFrame("Frame", nil, Panel)
MsgDialogBase:SetSize(384, 164)
MsgDialogBase:SetPoint("TOPRIGHT", Panel, "TOPLEFT", IsClassic and 3 or 9, IsClassic and 6 or 5)
MsgDialogBase:Hide()
MsgDialogBase:HookScript("OnMouseDown", function() end) -- Needed to avoid clicking thru the panel

local MsgDialog = CreateFrame("Frame", nil, MsgDialogBase, "DialogBorderOpaqueTemplate")
MsgDialog:SetAllPoints()

MsgDialog.Title = MsgDialog:CreateFontString()
MsgDialog.Title:SetFont("Fonts/FRIZQT__.TTF", 20)
MsgDialog.Title:SetTextColor(1, 0.82, 0)
MsgDialog.Title:SetJustifyH("CENTER")
MsgDialog.Title:SetPoint("TOP", MsgDialog, "TOP", 0, -22)

MsgDialog.Icon = MsgDialog:CreateTexture()
MsgDialog.Icon:SetSize(20, 20)
MsgDialog.Icon:SetTexture("Interface/DialogFrame/UI-Dialog-Icon-AlertNew")
MsgDialog.Icon:SetPoint("RIGHT", MsgDialog.Title, "LEFT", -2, 0)

MsgDialog.Message = MsgDialog:CreateFontString()
MsgDialog.Message:SetWidth(331)
MsgDialog.Message:SetFont("Fonts/FRIZQT__.TTF", 14)
MsgDialog.Message:SetJustifyH("LEFT")
MsgDialog.Message:SetPoint("TOP", MsgDialog.Title, "BOTTOM", 1, -11)

MsgDialog.CloseButton = CreateFrame("Button", nil, MsgDialog, "GameMenuButtonTemplate")
MsgDialog.CloseButton:SetWidth(100)
MsgDialog.CloseButton:SetText("Close")
MsgDialog.CloseButton:SetPoint("TOP", MsgDialog.Message, "BOTTOM", 0, -10)
MsgDialog.CloseButton:SetScript("OnClick", function() MsgDialogBase:Hide() end)
Panel:HookScript("OnHide", function() MsgDialog.CloseButton:Click() end)

hooksecurefunc(MsgDialog.Message, "SetFormattedText", function() -- Adapting the height to the contents
  MsgDialogBase:SetHeight(MsgDialog:GetTop() - MsgDialog.CloseButton:GetBottom() + 22)
end)

Dialog = function(Title, Message, ...)
  MsgDialog.Title:SetText(Title)
  MsgDialog.Message:SetFormattedText(Message, ...)
  MsgDialogBase:Show()
end

--[[ Dialog to show to the user when waiting to catch a keybind for a macro ]]------------------------------------------------------------------------
MacroKeybindCatchDialog:GetChildren():Hide() -- Hiding the default button
MacroKeybindCatchDialog:Hide()
MacroKeybindCatchDialog:SetSize(640, 105)
MacroKeybindCatchDialog:SetPoint("TOP", UIParent, "TOP", 0, -200)
MacroKeybindCatchDialog.Center:SetColorTexture(0.15, 0.15, 0.14, 1)
MacroKeybindCatchDialog.Center:ClearAllPoints()
MacroKeybindCatchDialog.Center:SetPoint("TOPLEFT", MacroKeybindCatchDialog, "TOPLEFT", 6, -6)
MacroKeybindCatchDialog.Center:SetPoint("BOTTOMRIGHT", MacroKeybindCatchDialog, "BOTTOMRIGHT", -6, 6)
MacroKeybindCatchDialog.Message = MacroKeybindCatchDialog:CreateFontString()
MacroKeybindCatchDialog.Message:SetFont("Fonts/FRIZQT__.TTF", 20, "OUTLINE")
MacroKeybindCatchDialog.Message:SetPoint("CENTER")
MacroKeybindCatchDialog.Message:SetJustifyH("CENTER")
MacroKeybindCatchDialog.Message:SetText("Press the keybind that you want to bind to macro commands\n\n|cFFFFD100ESC|r to cancel")

--[[ System to capture the next keybind pressed ]]----------------------------------------------------------------------------------------------------
local IsModifierKey = {
  [ "SHIFT"] = 1, [ "ALT"] = 1, [ "CTRL"] = 1,
  ["LSHIFT"] = 1, ["LALT"] = 1, ["LCTRL"] = 1,
  ["RSHIFT"] = 1, ["RALT"] = 1, ["RCTRL"] = 1
}

BindCatcher:SetFrameStrata("TOOLTIP")
BindCatcher:SetFrameLevel(10000)
BindCatcher:SetPropagateKeyboardInput(false)
BindCatcher:SetAllPoints()
BindCatcher:Hide()

-- BindCatcher:Run()
-- Catches the next keybind pressed by the user.
-- > Dialog: Optional dialog to show to the user.
-- > Callback: Function that is run after the keybind has been caught, with the keybind as a parameter.
function BindCatcher:Run(Dialog, Callback)
  if Dialog then
    BindCatcher.Dialog = Dialog
    BindCatcher.Dialog:Show()
  end
  BindCatcher.Callback = Callback
  BindCatcher:Show()
end

-- BindCatcher:ProcessKeybind()
-- Function that is called from the widget scripts that process the keybind pressed by the user.
function BindCatcher:ProcessKeybind(Key)
  if IsModifierKey[Key] then return end

  if Key == "ESCAPE" then
    if self.Dialog then
      self.Dialog:Hide()
      self.Dialog = nil
    end

    self:Hide()
    self.Callback(nil) -- Sending nil to the callback coz the process was cancelled
    self.Callback = nil

    return
  end

  local Mod = ""

  -- Checking the modifiers pressed
  -- Right modifiers
  if IsRightAltKeyDown()     then Mod = Mod.."RALT-"   end
  if IsRightControlKeyDown() then Mod = Mod.."RCTRL-"  end
  if IsRightShiftKeyDown()   then Mod = Mod.."RSHIFT-" end
  -- Left modifiers
  if IsLeftAltKeyDown()      then Mod = Mod.."LALT-"   end
  if IsLeftControlKeyDown()  then Mod = Mod.."LCTRL-"  end
  if IsLeftShiftKeyDown()    then Mod = Mod.."LSHIFT-" end

  if self.Dialog then
    self.Dialog:Hide()
    self.Dialog = nil
  end

  self:Hide()
  self.Callback(Mod..Key) -- Sending the keybind caught to the callback
  self.Callback = nil
end

-- Intercepting pressed keys
BindCatcher:SetScript("OnKeyDown", function(self, Key)
  self:ProcessKeybind(Key)
end)

-- Intercepting mouse buttons
BindCatcher:SetScript("OnMouseDown", function(self, Button)
  local MouseKey = Button == "MiddleButton" and "BUTTON3" or Button == "Button4" and "BUTTON4" or Button == "Button5" and "BUTTON5"
  if MouseKey then self:ProcessKeybind(MouseKey) end
end)

-- Intercepting mousewheel
BindCatcher:SetScript("OnMouseWheel", function(self, Delta)
  self:ProcessKeybind(Delta == 1 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
end)

--[[ DropDown to select the current specialization ]]-------------------------------------------------------------------------------------------------
SpecMenu = CreateFrame("DropdownButton", nil, Panel, "WowStyle1DropdownTemplate")
SpecMenu:SetPoint("BOTTOMRIGHT", Panel.RightInset, "TOPRIGHT", IsClassic and -2 or -1, 2)
SpecMenu:HookScript("OnEnter", function() MenuUtil.HideTooltip(SpecMenu) end) -- Hiding the dropdown's tooltip

function SpecMenu.UpdateWidth() -- Adjusts the width of the DropDown to the selected element
  SpecMenu:SetWidth(SpecMenu.Text:GetUnboundedStringWidth() + 35)
end

local function SpecMenu_Radio_IsSelected(SpecIndex)
  RunNextFrame(SpecMenu.UpdateWidth)
  return SpecIndex == DB.CurrentSpec
end

local function SpecMenu_Radio_OnSelection(SpecIndex)
  RunNextFrame(SpecMenu.UpdateWidth)
  LoadSpecBindings(SpecIndex) -- This will update DB.CurrentSpec to the new specialization selected
  return MenuResponse.Close
end

local function SpecMenu_Checkbox_IsSelected()
  return DB.AutoDetectSpec
end

local function SpecMenu_Checkbox_OnSelection()
  DB.AutoDetectSpec = not DB.AutoDetectSpec

  if DB.AutoDetectSpec then
    local PlayerSpec = GetPlayerSpec()
    if PlayerSpec and PlayerSpec ~= DB.CurrentSpec then LoadSpecBindings(PlayerSpec) end
  end

  return MenuResponse.Refresh
end

-- Show only the selected Radio text in the DropDown, ignoring the Checkbox's text which by default also appears when checked
SpecMenu:SetSelectionText(function(Selection)
  return Selection[1].text
end)

-- Generator function. Will be used on PLAYER_ENTERING_WORLD when spec data is available
function SpecMenu.Generator(Owner, Root)
  for SpecIndex = 1, GetNumSpecs() do
    local Radio = Root:CreateRadio(GetSpecName(SpecIndex), SpecMenu_Radio_IsSelected, SpecMenu_Radio_OnSelection, SpecIndex)
  end

  Root:CreateDivider()
  Root:CreateCheckbox("Autodetect", SpecMenu_Checkbox_IsSelected, SpecMenu_Checkbox_OnSelection)
end

-- Label on the left of the menu
local DropDownLabel = SpecMenu:CreateFontString()
DropDownLabel:SetFont("Fonts/FRIZQT__.TTF", 13)
DropDownLabel:SetShadowOffset(1, -1)
DropDownLabel:SetPoint("RIGHT", SpecMenu, "LEFT", IsClassic and -5 or -2, 0)
DropDownLabel:SetTextColor(1, 0.82, 0)
DropDownLabel:SetText("Specialization:")

--[[ Context menu for the minimap button to select the current specialization ]]----------------------------------------------------------------------
local function Radio_IsSelected(SpecIndex)
  return SpecIndex == DB.CurrentSpec
end

local function Radio_OnSelection(SpecIndex)
  LoadSpecBindings(SpecIndex) -- This will update DB.CurrentSpec to the new specialization selected
  return MenuResponse.Close
end

local function Checkbox_IsSelected()
  return DB.AutoDetectSpec
end

local function Checkbox_OnSelection()
  DB.AutoDetectSpec = not DB.AutoDetectSpec
  return MenuResponse.Refresh
end

local function MinimapButtonMenuGenerator(_, Root)
  Root:CreateTitle("Specialization")

  for SpecIndex = 1, GetNumSpecs() do
    Root:CreateRadio(GetSpecName(SpecIndex), Radio_IsSelected, Radio_OnSelection, SpecIndex)
  end

  Root:CreateDivider()
  Root:CreateCheckbox("Autodetect", Checkbox_IsSelected, Checkbox_OnSelection)
end

--[[ Pet battle buttons ]]----------------------------------------------------------------------------------------------------------------------------
-- Hidden macro buttons that execute pet battle abilities, to click on them when the player
-- enters a pet battle, with the binds assigned by the user in the vehicle binds panel
local PetBattleButton = {}
for i = 1, 6 do
  PetBattleButton[i] = CreateFrame("Button", "BindPanel_PetBattleButton"..i, nil, "SecureActionButtonTemplate")
  PetBattleButton[i]:RegisterForClicks("AnyDown")
  PetBattleButton[i]:SetAttribute("type", "macro")
  if i <= 3 then PetBattleButton[i]:SetAttribute("macrotext", "/run PetBattleFrame.BottomFrame.abilityButtons["..i.."]:Click()") end
end

PetBattleButton[4]:SetAttribute("macrotext", "/run PetBattleFrame.BottomFrame.SwitchPetButton:Click()")
PetBattleButton[5]:SetAttribute("macrotext", "/run PetBattleFrame.BottomFrame.CatchButton:Click()")
PetBattleButton[6]:SetAttribute("macrotext", "/run PetBattleFrame.BottomFrame.ForfeitButton:Click()")

--[[ Vehicle/Skyriding bar ]]-------------------------------------------------------------------------------------------------------------------------
-- Hidden action bar to click on its buttons when the player enters a vehicle or
-- skyriding mount, with the binds assigned by the user in the vehicle binds panel
local VehicleBar = CreateFrame("Frame", nil, nil, "SecureHandlerAttributeTemplate")
VehicleBar:SetAttribute("actionpage", 1)
VehicleBar:Hide()

-- Creating buttons
local VehicleButton = {}
for i = 1, 12 do
  VehicleButton[i] = CreateFrame("Button", "BindPanel_VehicleButton"..i, VehicleBar, "SecureActionButtonTemplate")
  local B = VehicleButton[i]
  B:Hide()
  B:SetID(i)
  B:SetAttribute("type", "action")
  B:SetAttribute("action", i)
  B:SetAttribute("useparent-actionpage", true)
  B:RegisterForClicks("AnyDown")
end

-- Table that will store the keybinds for vehicles desired by the user
VehicleBar:Execute([[ VehicleKeybind = newtable() ]]) -- Key: Button index / Value: Keybind

-- Triggers
VehicleBar:SetAttribute("_onattributechanged", [[
  -- Actionpage update
  if name == "page" then
    if HasVehicleActionBar() then self:SetAttribute("actionpage", GetVehicleBarIndex())
    elseif HasOverrideActionBar() then self:SetAttribute("actionpage", GetOverrideBarIndex()) 
    elseif HasBonusActionBar() then self:SetAttribute("actionpage", GetBonusBarIndex())
    else self:SetAttribute("actionpage", GetActionBarPage()) end

  -- Setting binds of higher priority than the normal ones when the player enters a vehicle, to be able to use it
  elseif name == "vehicletype" then
    if value == "vehicle" then -- Vehicle/Skyriding
      for i = 1, 12 do
        if VehicleKeybind[i] then self:SetBindingClick(true, VehicleKeybind[i], "BindPanel_VehicleButton"..i) end
      end

    elseif value == "petbattle" then -- Pet battle
      for i = 1, 6 do
        if VehicleKeybind[i] then self:SetBindingClick(true, VehicleKeybind[i], "BindPanel_PetBattleButton"..i) end
      end

    elseif value == "none" then -- No vehicle, deleting vehicle binds
      self:ClearBindings()
    end
  end
]])

-- Trigger to update the actionpage of the hidden actionbar for vehicles
RegisterAttributeDriver(VehicleBar, "page",
  "[@vehicle,exists] A;".. -- Needed because [vehicleui] triggers before HasVehicleActionBar() is true
  "[vehicleui] B;"      ..
  "[possessbar] C;"     ..
  "[overridebar] D;"    ..
  "[bonusbar:5] E;"     .. -- Skyriding
  "F"
)

-- Trigger to detect vehicles to do the remapping to vehicle buttons while we are in one
RegisterAttributeDriver(VehicleBar, "vehicletype",
  "[vehicleui][possessbar][overridebar][bonusbar:5] vehicle;"..
  "[petbattle] petbattle;"..
  "none"
)

--[[ Vehicle/Skyriding binds panel ]]-----------------------------------------------------------------------------------------------------------------
local VehiclesPanel = CreateFrame("Frame", "BindPanel_VehiclesPanel", UIParent, "ButtonFrameTemplate")
VehiclesPanel.DefaultWidth = HasSkyriding and 412 or 340
VehiclesPanel.DefaultButtonWidth = 120
VehiclesPanel.Button = {}
VehiclesPanel:SetFrameStrata("HIGH")
VehiclesPanel:SetMovable(true)
VehiclesPanel:SetSize(VehiclesPanel.DefaultWidth, IsClassic and 548 or 550)
VehiclesPanel:Hide()
VehiclesPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
VehiclesPanel:HookScript("OnMouseDown", function() end) -- Needed to avoid clicking thru the panel
VehiclesPanel.TitleContainer.TitleText:SetText("BindPanel")
VehiclesPanel.TitleContainer.TitleText:ClearAllPoints()
VehiclesPanel.TitleContainer.TitleText:SetPoint("CENTER", VehiclesPanel.TitleContainer, "CENTER", IsClassic and -17 or 0, 0)
ButtonFrameTemplate_HidePortrait(VehiclesPanel)
BindPanel_VehiclesPanelTitleText:SetText("BindPanel")
BindPanel_VehiclesPanelInset:Hide()
tinsert(UISpecialFrames, "BindPanel_VehiclesPanel")

-- Position
if DB.VehiclesPanelOffsetX then
  VehiclesPanel:ClearAllPoints()
  VehiclesPanel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", DB.VehiclesPanelOffsetX, DB.VehiclesPanelOffsetY)
end

-- Frame to move the panel from the title bar
TitleBarMover = CreateFrame("Frame", nil, VehiclesPanel)
TitleBarMover:SetPoint("TOPLEFT", VehiclesPanel, "TOPLEFT", 5, -1)
TitleBarMover:SetPoint("BOTTOMRIGHT", VehiclesPanel, "TOPRIGHT", -23, -21)

TitleBarMover:SetScript("OnMouseDown", function()
  VehiclesPanel:StartMoving()
  VehiclesPanel:SetUserPlaced(false)
end)

TitleBarMover:SetScript("OnMouseUp", function()
  VehiclesPanel:StopMovingOrSizing()
  DB.VehiclesPanelOffsetX = VehiclesPanel:GetLeft()
  DB.VehiclesPanelOffsetY = VehiclesPanel:GetBottom()
  VehiclesPanel:ClearAllPoints()
  VehiclesPanel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", DB.VehiclesPanelOffsetX, DB.VehiclesPanelOffsetY)
end)

local VehiclesTitle = VehiclesPanel:CreateFontString()
VehiclesTitle:SetFont("Fonts/FRIZQT__.TTF", 20)
VehiclesTitle:SetJustifyH("CENTER")
VehiclesTitle:SetShadowOffset(1, -1)
VehiclesTitle:SetPoint("TOP", VehiclesPanel, "TOP", 0, -40)
VehiclesTitle:SetText(Vehicle.." binds")

-- Font for the vehicle bind buttons
CreateFont("BindPanel_VehicleBindFont")
local BindPanel_VehicleBindFont = BindPanel_VehicleBindFont -- Upvalue
BindPanel_VehicleBindFont:SetFont("Fonts/FRIZQT__.TTF", 14, "")

-- Function to adapt the width of the buttons to the widest FontString inside any of them. The panel is also adapted to their width.
function VehiclesPanel.UpdateVehicleButtonsWidth()
  local WidthForPanel = VehiclesPanel.DefaultWidth
  local WidthForButtons = VehiclesPanel.DefaultButtonWidth
  local WidestFontString = 0

  -- Finding the widest FontString inside the buttons
  for i = 1, 12 do
    local FontStringWidth = VehiclesPanel.Button[i].Text:GetUnboundedStringWidth()
    if FontStringWidth > WidestFontString then WidestFontString = FontStringWidth end -- Storing the highest width found
  end

  local NeededWidth = WidestFontString + 28 -- FontString width + padding + button borders
  if NeededWidth > VehiclesPanel.DefaultButtonWidth then
    WidthForButtons = NeededWidth
    WidthForPanel = VehiclesPanel.DefaultWidth + WidthForButtons - VehiclesPanel.DefaultButtonWidth
  end

  for i = 1, 12 do VehiclesPanel.Button[i]:SetWidth(WidthForButtons) end
  VehiclesPanel:SetWidth(WidthForPanel)
end

-- Creating buttons for binding
local LabelWidth = HasSkyriding and 197 or 125
for i = 1, 12 do
  VehiclesPanel.Button[i] = CreateFrame("Button", nil, VehiclesPanel, "KeyBindingFrameBindingButtonTemplateWithLabel")
  local Button = VehiclesPanel.Button[i]

  -- Label shown at the left of the button
  Button.KeyLabel:SetFontObject(BindPanel_VehicleBindFont)
  Button.KeyLabel:SetJustifyH("LEFT")
  Button.KeyLabel:SetWidth(LabelWidth)
  Button.KeyLabel:SetText(Vehicle.." button "..i)
  Button.KeyLabel:ClearAllPoints()
  if i == 1 then Button.KeyLabel:SetPoint("TOPLEFT", VehiclesPanel, "TOPLEFT", IsClassic and 42 or 45, -78)
  else Button.KeyLabel:SetPoint("TOPLEFT", VehiclesPanel.Button[i-1].KeyLabel, "BOTTOMLEFT", 0, -24) end

  -- Label shown when the user wants set to a keybind for the button
  Button.PressKeyLabel = Button:CreateFontString(nil, "ARTWORK", "BindPanel_VehicleBindFont")
  Button.PressKeyLabel:SetPoint("CENTER")
  Button.PressKeyLabel:SetText("Press key")
  Button.PressKeyLabel:Hide()

  -- Button settings
  Button:SetID(i)
  Button:SetNormalFontObject(BindPanel_VehicleBindFont)
  Button:SetDisabledFontObject(BindPanel_VehicleBindFont)
  Button:SetHighlightFontObject(BindPanel_VehicleBindFont)
  Button:SetWidth(VehiclesPanel.DefaultButtonWidth)
  Button:SetText("Unassigned")
  Button.Text:SetTextColor(0.6, 0.6, 0.6)
  Button.Text:SetWidth(0)
  Button.SelectedHighlight:ClearAllPoints()
  Button.SelectedHighlight:SetPoint("TOPLEFT", Button, "TOPLEFT", 0, -6)
  Button.SelectedHighlight:SetPoint("TOPRIGHT", Button, "TOPRIGHT", 0, 0)
  Button:SetPoint("LEFT", Button.KeyLabel, "RIGHT", 10, 0)

  -- Method to assing a keybind to this button
  function Button.Bind(Keybind)
    if InCombat() then return end
    Button.Text:Show()
    Button.PressKeyLabel:Hide()
    Button:SetSelected(false)
    if not Keybind then return end

    -- If there was a button with this keybind already assigned, unbind it before proceeding
    for i = 1, 12 do
      if VehiclesPanel.Button[i]:GetText() == Keybind then
        VehiclesPanel.Button[i].Unbind()
      end
    end

    Button:SetText(GetKeybindVisual(Keybind))
    Button.Text:SetTextColor(1, 1, 1)
    local i = Button:GetID()
    DB.VehicleKeybind[i] = Keybind

    VehicleBar:Execute(format([[
      VehicleKeybind[%d] = "%s"

      -- If the player is already in a vehicle, set the bind
      if SecureCmdOptionParse("[@vehicle,exists][vehicleui][possessbar][overridebar][bonusbar:5] true") then -- Vehicle
        self:SetBindingClick(true, "%s", "BindPanel_VehicleButton%d")
      elseif %s and %d <= 6 then -- Pet battle
        self:SetBindingClick(true, "%s", "BindPanel_PetBattleButton%d")
      end
    ]], i, Keybind, Keybind, i, tostring(C_PetBattles and C_PetBattles.IsInBattle()), i, Keybind, i))

    VehiclesPanel.UpdateVehicleButtonsWidth()
  end

  -- Method to free the button from its keybind
  function Button.Unbind()
    if InCombat() then return end
    local i = Button:GetID()

    VehicleBar:Execute(format([[
      VehicleKeybind[%d] = nil
      self:ClearBinding("%s")
    ]], i, GetKeybindInternal(Button:GetText())))

    DB.VehicleKeybind[i] = nil
    Button:SetText("Unassigned")
    Button.Text:SetTextColor(0.6, 0.6, 0.6)
    VehiclesPanel.UpdateVehicleButtonsWidth()
  end

  -- Clicks to bind/unbind
  Button:HookScript("OnClick", function(self, MouseButton, Down)
    if Down or InCombat() then return end -- Run only when the button is released

    if MouseButton == "LeftButton" then -- Bind
      self.Text:Hide()
      self.PressKeyLabel:Show()
      self:SetSelected(true)
      BindCatcher:Run(nil, self.Bind)

    elseif MouseButton == "RightButton" then -- Unbind
      self.Unbind()
    end
  end)
end

--[[ Panel for the Setting->Addons tab ]]-------------------------------------------------------------------------------------------------------------
local UI = CreateFrame("Frame")
local Category = Settings.RegisterCanvasLayoutCategory(UI, "BindPanel")
Settings.RegisterAddOnCategory(Category)

-- Title
UI.Title = UI:CreateFontString(nil, "ARTWORK")
UI.Title:SetFont("Fonts/FRIZQT__.TTF", 22, "OUTLINE")
UI.Title:SetPoint("TOPLEFT", 6, -10)
UI.Title:SetText("|cFF00FF00BindPanel")

-- Credits
UI.Credits = UI:CreateFontString(nil, "ARTWORK")
UI.Credits:SetFont("Fonts/FRIZQT__.TTF", 14)
UI.Credits:SetPoint("TOPRIGHT", -16, -12)
UI.Credits:SetText("By |cFFFFFF00Spyro|r [Sanguino EU]")

-- Addon instructions
UI.Tutorial = UI:CreateFontString(nil, "ARTWORK")
UI.Tutorial:SetFont("Fonts/FRIZQT__.TTF", 16)
UI.Tutorial:SetPoint("TOPLEFT", UI.Title, "BOTTOMLEFT", 1, -10)
UI.Tutorial:SetJustifyH("LEFT")
UI.Tutorial:SetText(format([[
Minimap button:
|cFFFF0000•|r |cFFFFD100Left click:|r Opens the main panel
|cFFFF0000•|r |cFFFFD100Middle click:|r Binds a keybind directly
|cFFFF0000•|r |cFFFFD100Right click:|r Selects specialization
|cFFFF0000•|r |cFFFFD100SHIFT+Left click:|r %s binds

Slash commands:
|cFFFF0000•|r |cFFFFD100/bindpanel:|r Opens the main panel
|cFFFF0000•|r |cFFFFD100/bindpanel catch:|r Binds a keybind directly
|cFFFF0000•|r |cFFFFD100/bindpanel spec NUMBER:|r Selects specialization
|cFFFF0000•|r |cFFFFD100/bindpanel vehicle:|r %s binds

Editor:
|cFFFF0000•|r You can drag & drop items/abilities to it

|cFF00FF00Tips|r:
|cFFFF0000•|r You can bind a key to |cFFFFD100/bindpanel|r with the addon itself
|cFFFF0000•|r If you run out of characters in a macro, split the modifiers in different
    macros. 255 characters per modifier is enough for any macro
]], Vehicle, Vehicle))

--[[ Minimap button ]]--------------------------------------------------------------------------------------------------------------------------------
local MinimapButton = LibStub("LibDataBroker-1.1"):NewDataObject("BindPanel", {
  type = "launcher",
  text = "BindPanel",
  icon = "Interface/MacroFrame/MacroFrame-Icon",

  OnEnter = function(Frame)
    GameTooltip:SetOwner(Frame, "ANCHOR_NONE")
    GameTooltip:SetPoint("RIGHT", Frame, "LEFT")
    GameTooltip:AddLine("|cFF00FF00BindPanel|r")
    GameTooltip:AddDoubleLine("|cFFFF0000•|r |cFFFFD100Left click|r"  , "|cFFFFFFFFOpens the main panel|r")
    GameTooltip:AddDoubleLine("|cFFFF0000•|r |cFFFFD100Middle click|r", "|cFFFFFFFFBinds a keybind directly|r")
    GameTooltip:AddDoubleLine("|cFFFF0000•|r |cFFFFD100Right click|r" , "|cFFFFFFFFSelects specialization|r")
    GameTooltip:AddDoubleLine("|cFFFF0000•|r |cFFFFD100SHIFT+Left click|r", "|cFFFFFFFF"..Vehicle.." binds|r")
    GameTooltip:Show()
  end,

  OnLeave = function(Frame)
    GameTooltip:Hide()
  end,

  OnClick = function(_, Button)
    if Button == "LeftButton" then -- Showing the main panel
      if IsShiftKeyDown() then VehiclesPanel:SetShown(not VehiclesPanel:IsShown())
      else Panel:SetShown(not Panel:IsShown()) end

    elseif Button == "MiddleButton" then -- Option for catching a keybind directly
      BindCatcher:Run(MacroKeybindCatchDialog, AddMacroKeybind)

    elseif Button == "RightButton" then
      if IsShiftKeyDown() then -- Opening panel in the Setting->Addons tab
        Settings.OpenToCategory(Category:GetID())
      else -- Spec selection menu
        GameTooltip:Hide()
        MenuUtil.CreateContextMenu(MinimapButton, MinimapButtonMenuGenerator)
      end
    end
  end
})

DB.minimap = DB.minimap or {}
LibStub("LibDBIcon-1.0"):Register("BindPanel", MinimapButton, DB.minimap)

--[[ Events ]]----------------------------------------------------------------------------------------------------------------------------------------
-- Event PET_BATTLE_OPENING_START
-- Triggers when a pet battle starts. Used only in MoP because it doesn't have the [petbattle]
-- macro condition to detect pet battles from the Restricted Environment like post-MoP expansions.
function Event:PET_BATTLE_OPENING_START()
  VehicleBar:Execute([[
    for i = 1, 6 do
      if VehicleKeybind[i] then self:SetBindingClick(true, VehicleKeybind[i], "BindPanel_PetBattleButton"..i) end
    end
  ]])
end

-- Event PET_BATTLE_CLOSE
-- Triggers when a pet battle starts. Used only in MoP because it doesn't have the [petbattle]
-- macro condition to detect pet battles from the Restricted Environment like post-MoP expansions.
function Event:PET_BATTLE_CLOSE()
  VehicleBar:Execute([[ self:ClearBindings() ]])
end

-- Event ACTIVE_PLAYER_SPECIALIZATION_CHANGED
-- Triggers when the player changes his active spec. Used in post-WoD.
function Event:ACTIVE_PLAYER_SPECIALIZATION_CHANGED()
  if not DB.AutoDetectSpec then return end

  local NewSpec = GetPlayerSpec()
  if NewSpec and NewSpec ~= DB.CurrentSpec then
    LoadSpecBindings(NewSpec) -- This will update DB.CurrentSpec to the new specialization selected
  end
end

-- Event ACTIVE_TALENT_GROUP_CHANGED
-- Triggers when a player switches his talent group (dual specialization). Used in pre-Legion.
function Event:ACTIVE_TALENT_GROUP_CHANGED()
  Event:ACTIVE_PLAYER_SPECIALIZATION_CHANGED()
end

-- Event PLAYER_ENTERING_WORLD
-- Fires whenever the loading screen appears. The first time it triggers spec data is already available.
function Event:PLAYER_ENTERING_WORLD()
  Event:UnregisterEvent("PLAYER_ENTERING_WORLD") -- Only needs to run one time
  LibDBIcon10_BindPanel.icon:SetRotation(-0.4) -- Aesthetic change for the minimap icon

  -- Adding specializations to the database
  for SpecIndex = 1, GetNumSpecs() do
    DB[SpecIndex] = DB[SpecIndex] or {}
  end

  -- Spec auto-detection
  if DB.AutoDetectSpec == nil then -- First run of the addon
    DB.AutoDetectSpec = false -- Disabled by default
  end

  -- If there isn't any spec selected (first run of the addon), detect the spec
  if DB.CurrentSpec == nil then
    DB.CurrentSpec = GetPlayerSpec()

    if not DB.CurrentSpec then -- If the spec can't be identified, set it as the first DPS spec found
      DB.CurrentSpec = 1 -- Default value coz GetTalentTreeRoles() always returns nil in Vanilla

      for i = 1, GetNumSpecs() do
        local Role = GetSpecializationInfo and select(5, GetSpecializationInfo(i)) or GetTalentTreeRoles(i)
        if Role == "DAMAGER" then DB.CurrentSpec = i break end
      end
    end
  end

  -- If auto-detection is enabled, detect the spec if possible
  if DB.AutoDetectSpec then
    local PlayerSpec = GetPlayerSpec()
    if PlayerSpec then DB.CurrentSpec = PlayerSpec end
  end

  SpecMenu:SetupMenu(SpecMenu.Generator) -- Generating the spec selection menu on the main panel
  LoadSpecBindings(DB.CurrentSpec) -- Loading bindings for the current spec

  -- Registering event to detect spec changes
  Event:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
  if TocVersion < 70000 then Event:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED") end

  -- Vehicle keybinds
  if not DB.VehicleKeybind then -- First run of the addon
    DB.VehicleKeybind = {}
    for i = 1, 9 do -- Adding the default vehicle keybinds
      DB.VehicleKeybind[i] = GetBindingKey("ACTIONBUTTON"..i) or tostring(i)
    end
  end

  -- Loading vehicle keybinds
  for i = 1, 12 do
    if DB.VehicleKeybind[i] then
      VehiclesPanel.Button[i].Bind(DB.VehicleKeybind[i])
    end
  end
end

-- Registration
Event:SetScript("OnEvent", function(self, event, ...) return self[event](self, ...) end)
Event:RegisterEvent("PLAYER_ENTERING_WORLD")
if WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC then
  Event:RegisterEvent("PET_BATTLE_OPENING_START")
  Event:RegisterEvent("PET_BATTLE_CLOSE")
end

--[[ Slash commands ]]--------------------------------------------------------------------------------------------------------------------------------
SLASH_BINDPANEL1 = "/bindpanel"
SlashCmdList["BINDPANEL"] = function(Args)
  if #Args == 0 then -- Main panel
    RunNextFrame(function() Panel:SetShown(not Panel:IsShown()) end) -- Delay needed so the Enter is not written in the editbox
    return
  end

  local Arg = {}
  for A in Args:gmatch("%S+") do tinsert(Arg, A:lower()) end -- Storing arguments in a table

  if Arg[1] == "catch" then -- Binds a keybind directly
    BindCatcher:Run(MacroKeybindCatchDialog, AddMacroKeybind)

  elseif Arg[1] == "spec" then -- Changes de spec
    local SpecIndex = tonumber(Arg[2])
    local TotalSpecs = GetNumSpecs()
    if SpecIndex and SpecIndex >= 1 and SpecIndex <= TotalSpecs then LoadSpecBindings(SpecIndex)
    else Msg("Invalid spec, must be a number from 1 to %d.", TotalSpecs) end

  elseif Arg[1] == "vehicle" then -- Vehicle/Skyriding binds panel
    VehiclesPanel:SetShown(not VehiclesPanel:IsShown())

  else
    Msg('Unknown option "%s".', Arg[1])
  end
end