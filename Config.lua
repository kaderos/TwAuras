-- TwAuras file version: 0.1.49
-- Config.lua owns editor-only concerns: aura CRUD, dynamic trigger lists, and descriptor-driven widgets.
-- Lowercasing editor strings in one place keeps select and free-text comparisons consistent.
local function SafeLower(value)
  if not value then
    return ""
  end
  return string.lower(value)
end

local generatedWidgetId = 0
local function NextWidgetName(prefix)
  generatedWidgetId = generatedWidgetId + 1
  return "TwAuras" .. tostring(prefix or "Widget") .. tostring(generatedWidgetId)
end

-- Keep config and popup windows interactable by forcing them above the main editor stack.
local function BringFrameToFront(frame, owner, isPopup)
  local baseLevel = 0
  local bump = isPopup and 40 or 20
  local wanted = bump
  if not frame then
    return
  end
  if owner and owner.GetFrameLevel then
    baseLevel = owner:GetFrameLevel() or 0
  end
  wanted = math.max(baseLevel + bump, 1)
  if frame.SetToplevel then
    frame:SetToplevel(true)
  end
  if frame.SetFrameStrata then
    frame:SetFrameStrata(isPopup and "FULLSCREEN_DIALOG" or "DIALOG")
  end
  if frame.SetFrameLevel then
    frame:SetFrameLevel(wanted)
  end
  if frame.Raise then
    frame:Raise()
  end
end

-- The config reuses the same hue math as the region runtime so previews match in-game rendering.
local function HueToRGB(hue)
  local normalized = (tonumber(hue) or 0) / 60
  local chroma = 1
  local x = chroma * (1 - math.abs(math.fmod(normalized, 2) - 1))
  if normalized < 1 then
    return chroma, x, 0
  elseif normalized < 2 then
    return x, chroma, 0
  elseif normalized < 3 then
    return 0, chroma, x
  elseif normalized < 4 then
    return 0, x, chroma
  elseif normalized < 5 then
    return x, 0, chroma
  end
  return chroma, 0, x
end

-- Small widget factories keep the large config builder readable and visually consistent.
local function MakeLabel(parent, text, x, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  return fs
end

-- Edit boxes stay non-autofocused so opening the config never steals movement keys unexpectedly.
local function MakeEditBox(parent, width, height, x, y)
  local eb = CreateFrame("EditBox", NextWidgetName("EditBox"), parent, "InputBoxTemplate")
  eb:SetAutoFocus(false)
  eb:SetWidth(width)
  eb:SetHeight(height)
  eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  return eb
end

-- Buttons all route through one helper so the config layout can be rebuilt with less repetition.
local function MakeButton(parent, text, width, height, x, y, onClick)
  local button = CreateFrame("Button", NextWidgetName("Button"), parent, "UIPanelButtonTemplate")
  button:SetWidth(width)
  button:SetHeight(height)
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  button:SetText(text)
  button:SetScript("OnClick", onClick)
  return button
end

-- Generic hover help is used for token reminders, field explanations, and other compact hints.
local function AttachHoverTooltip(widget, tooltipText)
  if not widget or not widget.SetScript or not tooltipText or tooltipText == "" then
    return
  end
  widget:SetScript("OnEnter", function()
    if not GameTooltip then
      return
    end
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(tooltipText, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
end

-- The object summary tooltip shares the runtime breakdown instead of duplicating its own counts.
local function AttachObjectSummaryTooltip(widget)
  if not widget or not widget.SetScript then
    return
  end
  widget:SetScript("OnEnter", function()
    if not GameTooltip then
      return
    end
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(TwAuras:GetObjectSummaryTooltipText(), 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
end

-- Select widgets accept either raw strings or { value, label } tables and normalize both shapes.
local function NormalizeSelectOptions(options)
  local normalized = {}
  local i
  for i = 1, table.getn(options or {}) do
    local option = options[i]
    if type(option) == "table" then
      table.insert(normalized, {
        value = option.value,
        label = option.label or tostring(option.value or ""),
      })
    else
      table.insert(normalized, {
        value = option,
        label = tostring(option),
      })
    end
  end
  return normalized
end

-- Looking up the selected option centrally keeps button labels and stored values in sync.
local function FindSelectOption(options, value)
  local normalized = NormalizeSelectOptions(options)
  local i
  for i = 1, table.getn(normalized) do
    if tostring(normalized[i].value or "") == tostring(value or "") then
      return normalized[i]
    end
  end
  return nil
end

-- TwAuras uses a lightweight custom select menu instead of Blizzard dropdowns for simpler control.
local function MakeSelect(parent, width, height, x, y, options, onChanged)
  local button = CreateFrame("Button", NextWidgetName("Select"), parent, "UIPanelButtonTemplate")
  button:SetWidth(width)
  button:SetHeight(height)
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  button.__options = options or {}
  button.__value = nil
  button.__onChanged = onChanged
  button:SetText("")
  button:SetScript("OnClick", function()
    TwAuras:OpenSelectMenu(this)
  end)
  return button
end

-- Sliders are thin wrappers around the stock template so labels and ranges are configured together.
local function MakeSlider(parent, name, minVal, maxVal, step, x, y, width)
  local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  slider:SetWidth(width)
  slider:SetMinMaxValues(minVal, maxVal)
  slider:SetValueStep(step)
  getglobal(name .. "Low"):SetText(tostring(minVal))
  getglobal(name .. "High"):SetText(tostring(maxVal))
  return slider
end

-- Checkboxes use Blizzard templates but are wrapped here to keep the frame builder compact.
local function MakeCheck(parent, globalName, text, x, y)
  if not globalName or globalName == "" then
    globalName = NextWidgetName("Check")
  end
  local check = CreateFrame("CheckButton", globalName, parent, "UICheckButtonTemplate")
  check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  getglobal(globalName .. "Text"):SetText(text)
  return check
end

-- Color swatches provide a persistent preview surface for RGBA-style config fields.
local function MakeSwatch(parent, x, y)
  local swatch = CreateFrame("Frame", nil, parent)
  swatch:SetWidth(18)
  swatch:SetHeight(18)
  swatch:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  swatch:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  swatch:SetBackdropColor(1, 0, 0, 1)
  return swatch
end

-- Human-readable lists in the UI use this helper so descriptor summaries stay short.
local function JoinKeys(keys)
  return table.concat(keys or {}, ", ")
end

local TRIGGER_MODE_OPTIONS = {
  { value = "all", label = "All" },
  { value = "any", label = "Any" },
  { value = "priority", label = "Priority" },
}

local CONDITION_CHECK_OPTIONS = {
  { value = "active", label = "Active" },
  { value = "remaining", label = "Remaining Time" },
  { value = "stacks", label = "Stacks" },
  { value = "value", label = "Value" },
  { value = "percent", label = "Percent" },
}

local OPERATOR_OPTIONS = {
  { value = "<", label = "<" },
  { value = "<=", label = "<=" },
  { value = ">", label = ">" },
  { value = ">=", label = ">=" },
  { value = "=", label = "=" },
  { value = "!=", label = "!=" },
}

local CLASS_OPTIONS = {
  { value = "", label = "All Classes" },
  { value = "DRUID", label = "Druid" },
  { value = "HUNTER", label = "Hunter" },
  { value = "MAGE", label = "Mage" },
  { value = "PALADIN", label = "Paladin" },
  { value = "PRIEST", label = "Priest" },
  { value = "ROGUE", label = "Rogue" },
  { value = "SHAMAN", label = "Shaman" },
  { value = "WARLOCK", label = "Warlock" },
  { value = "WARRIOR", label = "Warrior" },
}

local POINT_OPTIONS = {
  "TOPLEFT", "TOP", "TOPRIGHT",
  "LEFT", "CENTER", "RIGHT",
  "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}

local COMBAT_LOG_EVENT_OPTIONS = {
  "ANY",
  "CHAT_MSG_SPELL_SELF_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS",
  "CHAT_MSG_SPELL_PARTY_DAMAGE",
  "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE",
  "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE",
  "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
  "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
  "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
  "CHAT_MSG_SPELL_AURA_GONE_SELF",
  "CHAT_MSG_SPELL_AURA_GONE_OTHER",
}

-- The picker searches against a shared icon manifest loaded from IconList.lua.
local ICON_PICKER_TEXTURES = TwAurasIconList or {
  "Interface\\Icons\\INV_Misc_QuestionMark",
}

local SOUND_PICKER_SOUNDS = TwAurasSoundList or {
  "Sound\\Interface\\RaidWarning.wav",
  "Sound\\Interface\\MapPing.wav",
}

-- Selection helpers centralize which aura the editor is currently mutating.
function TwAuras:GetAuraById(id)
  local store = self:GetAuraStore()
  local auras = self:GetAuraList()
  local i
  if store and store.items[tostring(id)] then
    for i = 1, table.getn(auras) do
      if auras[i].id == id then
        return store.items[tostring(id)], i
      end
    end
    return store.items[tostring(id)], nil
  end
  return nil, nil
end

function TwAuras:GetSelectedAura()
  -- Selection is stored by aura id instead of list index so it survives deletion and reordering.
  if not self.db.selectedAuraId then
    local first = self:GetAuraList()[1]
    if first then
      self.db.selectedAuraId = first.id
    end
  end
  if not self.db.selectedAuraId then
    return nil
  end
  return self:GetAuraById(self.db.selectedAuraId)
end

function TwAuras:MarkAuraPreviewChoice(auraId)
  self.runtime.previewChoices = self.runtime.previewChoices or {}
  self.runtime.previewChoices[auraId] = true
end

function TwAuras:ClearAuraPreviewChoices()
  self.runtime.previewChoices = {}
end

function TwAuras:EnsureSelectedAuraPreview()
  local aura = self:GetSelectedAura()
  if not aura then
    return
  end
  self.runtime.previewChoices = self.runtime.previewChoices or {}
  if not self.runtime.previewChoices[aura.id] then
    self:SetAuraPreviewState(aura.id, true)
  end
end

function TwAuras:CreateAuraTemplate()
  -- This template is intentionally close to the normalized runtime shape so a new aura can be
  -- created, displayed, and edited immediately before the next full normalize pass runs.
  local id = self.db.nextId or 1
  self.db.nextId = id + 1
  local aura = {
    id = id,
    key = self:BuildAuraRecordKey(id),
    schemaVersion = 1,
    name = self:GetUniqueAuraName("New Aura"),
    enabled = true,
    regionType = "icon",
    triggerMode = "all",
    triggers = {
      self:CreateDefaultTrigger(),
    },
    display = {
      width = 36,
      height = 36,
      alpha = 1,
      color = {1, 1, 1, 1},
      bgColor = {0, 0, 0, 0.5},
      textColor = {1, 1, 1, 1},
      showIcon = true,
      showTimerText = true,
      showStackText = true,
      showLabelText = false,
      label = "",
      desaturateInactive = false,
      iconPath = "",
      iconDesaturate = false,
      iconHueEnabled = false,
      iconHue = 0,
      showCooldownSwipe = false,
      showCooldownOverlay = false,
      timerFormat = "smart",
      labelText = "%name",
      timerText = "%time",
      valueText = "%value/%max",
      lowTimeThreshold = 0,
      lowTimeTextColorEnabled = false,
      lowTimeTextColor = {1, 0.2, 0.2, 1},
      lowTimeBarColorEnabled = false,
      lowTimeBarColor = {1, 0.2, 0.2, 1},
      fillDirection = "ltr",
      strata = "MEDIUM",
      fontSize = 12,
      fontOutline = "",
      labelAnchor = "BOTTOM",
      timerAnchor = "TOP",
      valueAnchor = "RIGHT",
      textAnchor = "CENTER",
    },
    load = {
      inCombat = false,
      class = nil,
      requireTarget = false,
      allowWorld = true,
      allowDungeon = true,
      allowRaid = true,
      allowPvp = true,
      allowArena = true,
      zoneText = "",
      updateEvents = "",
    },
    debug = self:CreateDefaultDebugOptions(),
    position = {
      point = "CENTER",
      relativePoint = "CENTER",
      x = 0,
      y = 0,
    },
  }
  self:NormalizeAuraConfig(aura)
  self:EnsureSingleBlankTrigger(aura)
  return aura
end

-- New auras start from the normalized template, then are inserted into the persistent aura store.
function TwAuras:AddAura()
  local aura = self:CreateAuraTemplate()
  self:InsertAuraRecord(aura)
  self.regions[aura.id] = self:CreateRegion(aura)
  self.db.selectedAuraId = aura.id
  self.db.selectedTriggerIndex = 1
  self.db.selectedConditionIndex = 1
  self:RefreshAll()
  self:RefreshConfigUI()
end

-- Duplication is editor-driven glue around the core record-cloning helper.
function TwAuras:DuplicateAura(auraId)
  local aura = auraId and self:GetAuraById(auraId) or self:GetSelectedAura()
  local duplicate
  if not aura then
    return
  end
  duplicate = self:DuplicateAuraRecord(aura)
  if not duplicate then
    return
  end
  self:NormalizeAuraConfig(duplicate)
  self:EnsureSingleBlankTrigger(duplicate)
  self:InsertAuraRecord(duplicate)
  self.regions[duplicate.id] = self:CreateRegion(duplicate)
  self.db.selectedAuraId = duplicate.id
  self.db.selectedTriggerIndex = 1
  self.db.selectedConditionIndex = 1
  self:RefreshAll()
  self:RefreshConfigUI()
end

-- The row context menu keeps destructive actions out of the always-visible row buttons.
function TwAuras:OpenAuraRowMenu(row)
  if not self.configFrame or not row or not row.__auraId then
    return
  end
  local menu = self.configFrame.auraRowMenu
  if not menu then
    menu = CreateFrame("Frame", "TwAurasAuraRowMenu", self.configFrame)
    menu:SetWidth(96)
    menu:SetHeight(54)
    menu:SetFrameStrata("DIALOG")
    menu:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    menu:SetBackdropColor(0, 0, 0, 0.95)
    menu.duplicateButton = MakeButton(menu, "Duplicate", 78, 20, 8, -8, function()
      if not TwAuras.configFrame.auraRowMenu.__auraId then
        return
      end
      TwAuras:DuplicateAura(TwAuras.configFrame.auraRowMenu.__auraId)
      TwAuras.configFrame.auraRowMenu:Hide()
    end)
    menu.cancelButton = MakeButton(menu, "Close", 78, 20, 8, -30, function()
      TwAuras.configFrame.auraRowMenu:Hide()
    end)
    menu:Hide()
    self.configFrame.auraRowMenu = menu
  end
  menu.__auraId = row.__auraId
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", row, "TOPRIGHT", 2, 0)
  BringFrameToFront(menu, self.configFrame, true)
  menu:Show()
end

-- Wizard presets create practical starter auras, then drop the user into the normal editor flow.
function TwAuras:AddWizardAura(style)
  local aura = self:CreateAuraTemplate()
  local trigger

  if style == "buff" then
    aura.name = "New Buff Tracker"
    aura.regionType = "icon"
    trigger = aura.triggers[1]
    trigger.type = "buff"
    trigger.unit = "player"
    trigger.auraName = ""
    trigger.duration = 0
  elseif style == "debuff" then
    aura.name = "New Target Debuff Tracker"
    aura.regionType = "icon"
    trigger = aura.triggers[1]
    trigger.type = "debuff"
    trigger.unit = "target"
    trigger.auraName = ""
    trigger.useTrackedTimer = true
    aura.display.showTimerText = true
  elseif style == "cooldown" then
    aura.name = "New Cooldown Ready"
    aura.regionType = "icon"
    trigger = aura.triggers[1]
    trigger.type = "cooldown"
    trigger.spellName = ""
    trigger.cooldownState = "ready"
  else
    self:AddAura()
    return
  end

  self:NormalizeAuraConfig(aura)
  self:EnsureSingleBlankTrigger(aura)
  self:InsertAuraRecord(aura)
  self.regions[aura.id] = self:CreateRegion(aura)
  self.db.selectedAuraId = aura.id
  self.db.selectedTriggerIndex = 1
  self.db.selectedConditionIndex = 1
  self:RefreshAll()
  self:RefreshConfigUI()
end

-- Delete removes the selected aura from storage, regions, and preview state in one place.
function TwAuras:DeleteSelectedAura()
  -- Removing an aura also tears down its live region and runtime timers so no orphaned state
  -- lingers after deletion.
  local aura, index = self:GetSelectedAura()
  if not aura or not index then
    return
  end
  local region = self.regions[aura.id]
  if region then
    region:Hide()
    region:SetParent(nil)
    self.regions[aura.id] = nil
  end
  self:StopAuraTimersForAura(aura)
  self:RemoveAuraRecord(aura.id)
  local first = self:GetAuraList()[1]
  self.db.selectedAuraId = first and first.id or nil
  self.db.selectedTriggerIndex = 1
  self.db.selectedConditionIndex = 1
  self:RefreshAll()
  self:RefreshConfigUI()
end

-- Destructive actions route through a small confirmation popup so saved auras are not removed
-- accidentally from one stray click in the left list footer.
function TwAuras:BuildDeleteConfirmFrame()
  if self.deleteConfirmFrame then
    return
  end

  local frame = CreateFrame("Frame", "TwAurasDeleteConfirmFrame", UIParent)
  frame:SetWidth(360)
  frame:SetHeight(150)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
  })
  frame:Hide()

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("TOP", frame, "TOP", 0, -16)
  frame.title:SetText("Delete Aura")

  frame.help = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.help:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -44)
  frame.help:SetWidth(324)
  frame.help:SetJustifyH("LEFT")
  frame.help:SetText("This deletion is permanent. Are you sure you want to delete the selected aura?")

  frame.deleteButton = MakeButton(frame, "Delete", 90, 22, 86, -106, function()
    TwAuras:DeleteSelectedAura()
    TwAuras.deleteConfirmFrame:Hide()
  end)
  frame.cancelButton = MakeButton(frame, "Cancel", 90, 22, 186, -106, function()
    TwAuras.deleteConfirmFrame:Hide()
  end)

  self.deleteConfirmFrame = frame
end

function TwAuras:OpenDeleteConfirm()
  local aura = self:GetSelectedAura()
  if not aura then
    return
  end
  self:BuildDeleteConfirmFrame()
  BringFrameToFront(self.deleteConfirmFrame, self.configFrame, true)
  self.deleteConfirmFrame:Show()
end

-- When live update is disabled, closing the config can discard staged widget edits. This prompt
-- gives users one last chance to apply or discard those pending changes intentionally.
function TwAuras:BuildUnsavedCloseFrame()
  if self.unsavedCloseFrame then
    return
  end

  local frame = CreateFrame("Frame", "TwAurasUnsavedCloseFrame", UIParent)
  frame:SetWidth(360)
  frame:SetHeight(150)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
  })
  frame:Hide()

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("TOP", frame, "TOP", 0, -16)
  frame.title:SetText("Unsaved Changes")

  frame.help = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.help:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -44)
  frame.help:SetWidth(324)
  frame.help:SetJustifyH("LEFT")
  frame.help:SetText("You have unsaved changes:")

  frame.applyButton = MakeButton(frame, "Apply", 90, 22, 86, -106, function()
    TwAuras:ApplyEditorToSelectedAura(false)
    TwAuras.unsavedCloseFrame:Hide()
    if TwAuras.configFrame then
      TwAuras.configFrame:Hide()
    end
  end)
  frame.discardButton = MakeButton(frame, "Discard", 90, 22, 186, -106, function()
    TwAuras.unsavedCloseFrame:Hide()
    if TwAuras.configFrame then
      TwAuras.configFrame:Hide()
    end
  end)

  self.unsavedCloseFrame = frame
end

function TwAuras:RequestCloseConfigWindow()
  local frame = self.configFrame
  if not frame then
    return
  end
  if frame.liveUpdateCheck and not frame.liveUpdateCheck:GetChecked() and self:GetSelectedAura() then
    self:BuildUnsavedCloseFrame()
    BringFrameToFront(self.unsavedCloseFrame, self.configFrame, true)
    self.unsavedCloseFrame:Show()
    return
  end
  frame:Hide()
end

-- Region rebuilds are used after display-type changes so stale frame types never linger.
function TwAuras:RebuildSelectedRegion()
  local aura = self:GetSelectedAura()
  if not aura then
    return
  end
  local old = self.regions[aura.id]
  if old then
    old:Hide()
    old:SetParent(nil)
  end
  self.regions[aura.id] = self:CreateRegion(aura)
  if self.db.unlocked and self.regions[aura.id].SetMovableState then
    self.regions[aura.id]:SetMovableState(true)
  end
  self:RefreshAura(aura)
end

-- Descriptor widgets are the bridge between generic field metadata and actual editor controls.
function TwAuras:GetDescriptorWidgetValue(widget)
  if not widget or not widget.field then
    return nil
  end
  if widget.field.type == "bool" then
    return widget.control:GetChecked() and true or false
  elseif widget.field.type == "select" then
    return widget.control.__value ~= nil and widget.control.__value or widget.field.default or ""
  elseif widget.field.type == "hue" then
    return math.floor((widget.control:GetValue() or widget.field.default or 0) + 0.5)
  elseif widget.field.type == "number" then
    return tonumber(widget.control:GetText()) or widget.field.default or 0
  elseif widget.field.type == "color4" then
    return {
      tonumber(widget.controls[1]:GetText()) or ((widget.field.default and widget.field.default[1]) or 1),
      tonumber(widget.controls[2]:GetText()) or ((widget.field.default and widget.field.default[2]) or 1),
      tonumber(widget.controls[3]:GetText()) or ((widget.field.default and widget.field.default[3]) or 1),
      tonumber(widget.controls[4]:GetText()) or ((widget.field.default and widget.field.default[4]) or 1),
    }
  end
  return widget.control:GetText() or ""
end

-- Descriptor widget helpers let trigger and region editors be generated from metadata tables.
function TwAuras:SetDescriptorWidgetValue(widget, value)
  if not widget or not widget.field then
    return
  end
  if widget.field.type == "bool" then
    widget.control:SetChecked(value and true or false)
  elseif widget.field.type == "select" then
    self:SetSelectValue(widget.control, value, widget.field.options or {})
  elseif widget.field.type == "hue" then
    local hue = tonumber(value)
    if hue == nil then
      hue = tonumber(widget.field.default) or 0
    end
    if hue < 0 then hue = 0 end
    if hue > 360 then hue = 360 end
    widget.control:SetValue(hue)
    if widget.valueText then
      widget.valueText:SetText(string.format("%d", hue))
    end
    if widget.preview then
      local r, g, b = HueToRGB(hue)
      widget.preview:SetBackdropColor(r, g, b, 1)
    end
  elseif widget.field.type == "number" then
    widget.control:SetText(tostring(value ~= nil and value or (widget.field.default or 0)))
  elseif widget.field.type == "color4" then
    local color = value or widget.field.default or {1, 1, 1, 1}
    local i
    for i = 1, 4 do
      widget.controls[i]:SetText(string.format("%.2f", color[i] or 1))
    end
  else
    widget.control:SetText(value ~= nil and value or (widget.field.default or ""))
  end
end

-- Descriptor field groups let trigger and region editors share one metadata-driven rendering path.
function TwAuras:BuildDescriptorFieldGroup(parent, prefix, fields, startX, startY, columnWidth, rowHeight)
  -- Descriptor metadata becomes concrete widgets here. This is the key piece that lets trigger
  -- and region types grow without hand-coding every editor field.
  local widgets = {}
  local i
  local globalPrefix = "TwAuras" .. prefix
  for i = 1, table.getn(fields or {}) do
    local field = fields[i]
    local column = math.fmod(i - 1, 2)
    local row = math.floor((i - 1) / 2)
    local x = startX + (column * columnWidth)
    local y = startY - (row * rowHeight)
    local widget = { field = field }

    if field.type == "bool" then
      widget.control = MakeCheck(parent, globalPrefix .. field.key .. "Check", field.label, x, y)
    elseif field.type == "select" then
      widget.label = MakeLabel(parent, field.label, x, y)
      widget.control = MakeSelect(parent, field.width or 140, 20, x, y - 18, field.options or {}, function()
        if TwAuras.configFrame and TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
          TwAuras:ApplyEditorToSelectedAura(true)
        end
      end)
    elseif field.type == "hue" then
      widget.label = MakeLabel(parent, field.label, x, y)
      widget.control = MakeSlider(parent, globalPrefix .. field.key .. "HueSlider", 0, 360, 1, x, y - 8, field.width or 150)
      widget.control:SetScript("OnValueChanged", function()
        local hue = math.floor((this:GetValue() or 0) + 0.5)
        if widget.valueText then
          widget.valueText:SetText(string.format("%d", hue))
        end
        if widget.preview then
          local r, g, b = HueToRGB(hue)
          widget.preview:SetBackdropColor(r, g, b, 1)
        end
        if TwAuras.configFrame
          and not TwAuras.configFrame.__suppressLiveUpdate
          and TwAuras.configFrame.liveUpdateCheck
          and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
          TwAuras:ApplyEditorToSelectedAura(true)
        end
      end)
      widget.valueText = MakeLabel(parent, "0", x + (field.width or 150) + 12, y - 14)
      widget.preview = MakeSwatch(parent, x + (field.width or 150) + 44, y - 18)
    elseif field.type == "color4" then
      widget.label = MakeLabel(parent, field.label, x, y)
      widget.controls = {}
      widget.controls[1] = MakeEditBox(parent, 42, 20, x, y - 18)
      widget.controls[2] = MakeEditBox(parent, 42, 20, x + 48, y - 18)
      widget.controls[3] = MakeEditBox(parent, 42, 20, x + 96, y - 18)
      widget.controls[4] = MakeEditBox(parent, 42, 20, x + 144, y - 18)
    else
      widget.label = MakeLabel(parent, field.label, x, y)
      widget.control = MakeEditBox(parent, field.width or 120, 20, x, y - 18)
    end

    if field.help and field.help ~= "" then
      widget.help = MakeLabel(parent, field.help, x, y - 40)
    end

    if field.hoverText and field.hoverText ~= "" and field.type == "text" and widget.control then
      widget.helpIcon = MakeLabel(parent, "?", x + (field.width or 120) + 8, y - 14)
      widget.helpIcon:SetTextColor(1, 0.82, 0, 1)
    end

    if field.hoverText and field.hoverText ~= "" then
      AttachHoverTooltip(widget.label, field.hoverText)
      AttachHoverTooltip(widget.control, field.hoverText)
      if widget.controls then
        local controlIndex
        for controlIndex = 1, table.getn(widget.controls) do
          AttachHoverTooltip(widget.controls[controlIndex], field.hoverText)
        end
      end
      AttachHoverTooltip(widget.valueText, field.hoverText)
      AttachHoverTooltip(widget.preview, field.hoverText)
      AttachHoverTooltip(widget.helpIcon, field.hoverText)
    end

    self:SetDescriptorWidgetValue(widget, field.default)
    widgets[field.key] = widget
  end
  return widgets
end

function TwAuras:SetSelectValue(control, value, options)
  local option = FindSelectOption(options or control.__options or {}, value)
  control.__options = options or control.__options or {}
  if option then
    control.__value = option.value
    control:SetText(option.label)
  else
    control.__value = value
    control:SetText(tostring(value or ""))
  end
end

-- The custom select menu is reused for trigger types, region types, units, operators, and more.
function TwAuras:OpenSelectMenu(control)
  if not control then
    return
  end

  if not self.selectMenuFrame then
    local frame = CreateFrame("Frame", "TwAurasSelectMenu", UIParent)
    frame:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.95)
    frame.buttons = {}
    frame:Hide()
    self.selectMenuFrame = frame
  end

  local frame = self.selectMenuFrame
  local options = NormalizeSelectOptions(control.__options or {})
  local i
  local widest = control:GetWidth()
  frame.owner = control

  for i = 1, table.getn(options) do
    if not frame.buttons[i] then
      local button = CreateFrame("Button", nil, frame)
      button:SetWidth(10)
      button:SetHeight(18)
      button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      button.text:SetPoint("LEFT", button, "LEFT", 6, 0)
      button.text:SetJustifyH("LEFT")
      button.text:SetWidth(180)
      button.bg = button:CreateTexture(nil, "BACKGROUND")
      button.bg:SetAllPoints(button)
      button:SetScript("OnClick", function()
        local owner = frame.owner
        if owner then
          TwAuras:SetSelectValue(owner, this.__optionValue, owner.__options or {})
          if owner.__onChanged then
            owner.__onChanged(this.__optionValue, this.__optionLabel)
          end
        end
        frame:Hide()
      end)
      frame.buttons[i] = button
    end
    if string.len(options[i].label or "") > widest / 6 then
      widest = math.max(widest, string.len(options[i].label or "") * 7)
    end
  end

  frame:SetWidth(math.max(control:GetWidth(), widest + 18))
  frame:SetHeight(math.max(18, table.getn(options) * 18) + 8)
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", control, "BOTTOMLEFT", 0, 0)

  for i = 1, table.getn(frame.buttons) do
    local button = frame.buttons[i]
    local option = options[i]
    if option then
      button.__optionValue = option.value
      button.__optionLabel = option.label
      button:SetWidth(frame:GetWidth() - 8)
      button:SetHeight(18)
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4 - ((i - 1) * 18))
      button.text:SetText(option.label)
      button.bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
      if tostring(control.__value or "") == tostring(option.value or "") then
        button.bg:SetVertexColor(0.2, 0.8, 0.2, 0.35)
      else
        button.bg:SetVertexColor(1, 1, 1, 0.08)
      end
      button:Show()
    else
      button:Hide()
    end
  end

  BringFrameToFront(frame, self.configFrame, true)
  frame:Show()
end

function TwAuras:SetDescriptorGroupVisibility(widgets, visible)
  local _, widget
  for _, widget in pairs(widgets or {}) do
    if widget.label then if visible then widget.label:Show() else widget.label:Hide() end end
    if widget.help then if visible then widget.help:Show() else widget.help:Hide() end end
    if widget.valueText then if visible then widget.valueText:Show() else widget.valueText:Hide() end end
    if widget.preview then if visible then widget.preview:Show() else widget.preview:Hide() end end
    if widget.control then if visible then widget.control:Show() else widget.control:Hide() end end
    if widget.controls then
      local i
      for i = 1, table.getn(widget.controls) do
        if visible then widget.controls[i]:Show() else widget.controls[i]:Hide() end
      end
    end
  end
end

-- Descriptor groups are cached per type so swapping trigger/region types reuses widgets instead
-- of constantly recreating checkbox globals and edit boxes.
-- Cached descriptor groups keep the config responsive when switching trigger or region types repeatedly.
function TwAuras:EnsureDescriptorFieldGroup(cacheKey, parent, prefix, definition, startX, startY, columnWidth, rowHeight)
  local frame = self.configFrame
  if not frame then
    return {}
  end
  local descriptorKey = definition and definition.key or "none"
  local widgetsKey = cacheKey .. "Widgets"
  local cacheTableKey = widgetsKey .. "Cache"
  local cachedKey, cachedWidgets

  frame[cacheTableKey] = frame[cacheTableKey] or {}
  for cachedKey, cachedWidgets in pairs(frame[cacheTableKey]) do
    self:SetDescriptorGroupVisibility(cachedWidgets, cachedKey == descriptorKey)
  end
  if not frame[cacheTableKey][descriptorKey] then
    frame[cacheTableKey][descriptorKey] = self:BuildDescriptorFieldGroup(parent, prefix .. descriptorKey, definition and definition.fields or {}, startX, startY, columnWidth, rowHeight)
  end
  frame[widgetsKey] = frame[cacheTableKey][descriptorKey]
  self:SetDescriptorGroupVisibility(frame[widgetsKey], true)
  return frame[widgetsKey]
end

function TwAuras:GetDescriptorGroupHeight(definition, rowHeight)
  local fields = definition and definition.fields or {}
  local rows = math.ceil(table.getn(fields) / 2)
  return math.max(1, rows * rowHeight)
end

-- Picker filters are split from picker construction so searches can rerender existing rows cheaply.
function TwAuras:RefreshIconPickerFilter()
  -- The picker reuses a fixed button pool and simply paginates visible matches. That keeps it
  -- workable even with a large icon manifest on the old client.
  local frame = self.iconPickerFrame
  if not frame then
    return
  end

  local query = ""
  if frame.searchBox then
    query = string.lower(frame.searchBox:GetText() or "")
  end

  local columns = frame.columns or 8
  local rowsPerPage = frame.rowsPerPage or 6
  local pageSize = columns * rowsPerPage
  local matches = {}
  local i
  for i = 1, table.getn(frame.buttons or {}) do
    local button = frame.buttons[i]
    local iconPath = string.lower(button.__iconPath or "")
    if query == "" or string.find(iconPath, query, 1, true) then
      table.insert(matches, button)
    else
      button:Hide()
    end
  end

  local totalMatches = table.getn(matches)
  local totalPages = math.max(1, math.ceil(totalMatches / pageSize))
  if not frame.pageIndex or frame.pageIndex < 1 then
    frame.pageIndex = 1
  end
  if frame.pageIndex > totalPages then
    frame.pageIndex = totalPages
  end

  local startIndex = ((frame.pageIndex - 1) * pageSize) + 1
  local endIndex = math.min(totalMatches, startIndex + pageSize - 1)
  local visibleIndex = 0

  for i = startIndex, endIndex do
    local button = matches[i]
    if button then
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", frame, "TOPLEFT", 18 + (math.fmod(visibleIndex, columns) * 46), -90 - (math.floor(visibleIndex / columns) * 42))
      button:Show()
      visibleIndex = visibleIndex + 1
    end
  end

  if frame.noResultsText then
    if totalMatches == 0 then
      frame.noResultsText:Show()
    else
      frame.noResultsText:Hide()
    end
  end

  if frame.pageText then
    if totalMatches == 0 then
      frame.pageText:SetText("Page 0 / 0")
    else
      frame.pageText:SetText("Page " .. frame.pageIndex .. " / " .. totalPages)
    end
  end

  if frame.prevButton then
    if frame.pageIndex <= 1 then frame.prevButton:Disable() else frame.prevButton:Enable() end
  end
  if frame.nextButton then
    if frame.pageIndex >= totalPages then frame.nextButton:Disable() else frame.nextButton:Enable() end
  end
end

function TwAuras:BuildIconPicker()
  -- The picker is manifest-backed because the client does not offer a reliable runtime API for
  -- enumerating every icon texture dynamically.
  if self.iconPickerFrame then
    return
  end

  local columns = 8
  local rowsPerPage = 6
  local pickerHeight = 96 + (rowsPerPage * 42) + 28

  local frame = CreateFrame("Frame", "TwAurasIconPickerFrame", UIParent)
  frame:SetWidth(420)
  frame:SetHeight(pickerHeight)
  frame.columns = columns
  frame.rowsPerPage = rowsPerPage
  frame.pageIndex = 1
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
  })
  frame:SetScript("OnHide", function()
    TwAuras:ClearAuraPreviews()
    TwAuras:ClearAuraPreviewChoices()
    TwAuras:RefreshAll()
  end)
  frame:Hide()

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("TOP", frame, "TOP", 0, -16)
  frame.title:SetText("TwAuras Icon Picker")

  frame.searchLabel = MakeLabel(frame, "Search", 18, -42)
  frame.searchBox = MakeEditBox(frame, 240, 20, 70, -38)
  frame.searchBox:SetScript("OnTextChanged", function()
    TwAuras:RefreshIconPickerFilter()
  end)
  frame.searchHelp = MakeLabel(frame, "Type part of a file path like swipe, bear, or rejuvenation", 18, -60)
  frame.noResultsText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.noResultsText:SetPoint("TOP", frame, "TOP", 0, -128)
  frame.noResultsText:SetText("No matching icons in the current picker list.")
  frame.noResultsText:Hide()
  frame.pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.pageText:SetPoint("TOP", frame, "TOP", 0, -78)
  frame.pageText:SetText("Page 1 / 1")

  frame.buttons = {}
  local i
  for i = 1, table.getn(ICON_PICKER_TEXTURES) do
    local button = CreateFrame("Button", nil, frame)
    button:SetWidth(32)
    button:SetHeight(32)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", 18 + (math.fmod(i - 1, columns) * 46), -90 - (math.floor((i - 1) / columns) * 42))
    button.texture = button:CreateTexture(nil, "ARTWORK")
    button.texture:SetAllPoints(button)
    button.texture:SetTexture(ICON_PICKER_TEXTURES[i])
    button.__iconPath = ICON_PICKER_TEXTURES[i]
    button:SetScript("OnClick", function()
      local widget = TwAuras.configFrame and TwAuras.configFrame.regionFieldWidgets and TwAuras.configFrame.regionFieldWidgets.iconPath or nil
      if widget and widget.control then
        widget.control:SetText(this.__iconPath or "")
        if TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
          TwAuras:ApplyEditorToSelectedAura(true)
        end
      end
      TwAuras.iconPickerFrame:Hide()
    end)
    frame.buttons[i] = button
  end

  frame.prevButton = MakeButton(frame, "<", 28, 20, 146, -74, function()
    if not TwAuras.iconPickerFrame then
      return
    end
    TwAuras.iconPickerFrame.pageIndex = math.max(1, (TwAuras.iconPickerFrame.pageIndex or 1) - 1)
    TwAuras:RefreshIconPickerFilter()
  end)
  frame.nextButton = MakeButton(frame, ">", 28, 20, 246, -74, function()
    if not TwAuras.iconPickerFrame then
      return
    end
    TwAuras.iconPickerFrame.pageIndex = (TwAuras.iconPickerFrame.pageIndex or 1) + 1
    TwAuras:RefreshIconPickerFilter()
  end)

  frame.clearButton = MakeButton(frame, "Use Trigger Icon", 110, 22, 34, -(pickerHeight - 34), function()
    local widget = TwAuras.configFrame and TwAuras.configFrame.regionFieldWidgets and TwAuras.configFrame.regionFieldWidgets.iconPath or nil
    if widget and widget.control then
      widget.control:SetText("")
      if TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
        TwAuras:ApplyEditorToSelectedAura(true)
      end
    end
    TwAuras.iconPickerFrame:Hide()
  end)
  frame.closeButton = MakeButton(frame, "Close", 90, 22, 286, -(pickerHeight - 34), function()
    frame:Hide()
  end)

  self.iconPickerFrame = frame
  self:RefreshIconPickerFilter()
end

function TwAuras:RefreshSoundPickerFilter()
  local frame = self.soundPickerFrame
  if not frame then
    return
  end

  local query = ""
  if frame.searchBox then
    query = string.lower(frame.searchBox:GetText() or "")
  end

  local matches = {}
  local i
  for i = 1, table.getn(SOUND_PICKER_SOUNDS) do
    local soundPath = string.lower(SOUND_PICKER_SOUNDS[i] or "")
    if query == "" or string.find(soundPath, query, 1, true) then
      table.insert(matches, SOUND_PICKER_SOUNDS[i])
    end
  end

  frame.filteredSounds = matches

  if frame.noResultsText then
    if table.getn(matches) == 0 then
      frame.noResultsText:Show()
    else
      frame.noResultsText:Hide()
    end
  end

  if frame.scrollChild then
    frame.scrollChild:SetHeight(math.max(1, table.getn(matches) * 24))
  end

  for i = 1, table.getn(frame.rows or {}) do
    local row = frame.rows[i]
    local soundValue = matches[i]
    if soundValue then
      row.__soundPath = soundValue
      row:SetText(soundValue)
      row:Show()
      if frame.selectedSound == soundValue then
        row:LockHighlight()
      else
        row:UnlockHighlight()
      end
    else
      row.__soundPath = nil
      row:Hide()
    end
  end

  if frame.selectedText then
    if frame.selectedSound and frame.selectedSound ~= "" then
      frame.selectedText:SetText("Selected: " .. frame.selectedSound)
    else
      frame.selectedText:SetText("Selected: none")
    end
  end

  if frame.testSelectedButton then
    if frame.selectedSound and frame.selectedSound ~= "" then
      frame.testSelectedButton:Enable()
    else
      frame.testSelectedButton:Disable()
    end
  end
end

function TwAuras:BuildSoundPicker()
  if self.soundPickerFrame then
    return
  end

  local visibleRows = 10
  local pickerHeight = 170 + (visibleRows * 24)

  local frame = CreateFrame("Frame", "TwAurasSoundPickerFrame", UIParent)
  frame:SetWidth(470)
  frame:SetHeight(pickerHeight)
  frame.visibleRows = visibleRows
  frame.selectedSound = nil
  frame.filteredSounds = {}
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
  })
  frame:Hide()

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("TOP", frame, "TOP", 0, -16)
  frame.title:SetText("TwAuras Sound Picker")

  frame.searchLabel = MakeLabel(frame, "Search", 18, -42)
  frame.searchBox = MakeEditBox(frame, 260, 20, 70, -38)
  frame.searchBox:SetScript("OnTextChanged", function()
    TwAuras:RefreshSoundPickerFilter()
  end)
  frame.searchHelp = MakeLabel(frame, "Type part of a sound path like raidwarning, map, or quest", 18, -60)
  frame.targetText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.targetText:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -78)
  frame.targetText:SetWidth(300)
  frame.targetText:SetJustifyH("LEFT")
  frame.targetText:SetText("")
  frame.selectedText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.selectedText:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -96)
  frame.selectedText:SetWidth(360)
  frame.selectedText:SetJustifyH("LEFT")
  frame.selectedText:SetText("Selected: none")
  frame.noResultsText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.noResultsText:SetPoint("TOP", frame, "TOP", 0, -186)
  frame.noResultsText:SetText("No matching sounds in the current picker list.")
  frame.noResultsText:Hide()

  frame.scrollFrame = CreateFrame("ScrollFrame", "TwAurasSoundPickerScroll", frame, "UIPanelScrollFrameTemplate")
  frame.scrollFrame:SetWidth(430)
  frame.scrollFrame:SetHeight(visibleRows * 24)
  frame.scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -118)
  frame.scrollChild = CreateFrame("Frame", nil, frame.scrollFrame)
  frame.scrollChild:SetWidth(406)
  frame.scrollChild:SetHeight(1)
  frame.scrollFrame:SetScrollChild(frame.scrollChild)

  frame.rows = {}
  local i
  for i = 1, table.getn(SOUND_PICKER_SOUNDS) do
    local button = CreateFrame("Button", NextWidgetName("SoundRowButton"), frame.scrollChild, "UIPanelButtonTemplate")
    button:SetWidth(402)
    button:SetHeight(20)
    button:SetPoint("TOPLEFT", frame.scrollChild, "TOPLEFT", 0, -((i - 1) * 24))
    button:SetText("")
    button:SetScript("OnClick", function()
      TwAuras.soundPickerFrame.selectedSound = this.__soundPath or ""
      TwAuras:RefreshSoundPickerFilter()
    end)
    frame.rows[i] = button
  end

  frame.useSelectedButton = MakeButton(frame, "Use Selected", 100, 22, 18, -(pickerHeight - 34), function()
    local soundValue = TwAuras.soundPickerFrame and TwAuras.soundPickerFrame.selectedSound or ""
    local targetField = TwAuras.soundPickerFrame and TwAuras.soundPickerFrame.targetField or nil
    local control = targetField and TwAuras.configFrame and TwAuras.configFrame[targetField] or nil
    if control and soundValue and soundValue ~= "" then
      control:SetText(soundValue)
      if TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
        TwAuras:ApplyEditorToSelectedAura(true)
      end
      TwAuras.soundPickerFrame:Hide()
    end
  end)
  frame.testSelectedButton = MakeButton(frame, "Test Selected", 100, 22, 124, -(pickerHeight - 34), function()
    local soundValue = TwAuras.soundPickerFrame and TwAuras.soundPickerFrame.selectedSound or ""
    if soundValue and soundValue ~= "" then
      TwAuras:PlayConfiguredSound(soundValue)
    end
  end)
  frame.clearButton = MakeButton(frame, "Clear", 90, 22, 230, -(pickerHeight - 34), function()
    local targetField = TwAuras.soundPickerFrame and TwAuras.soundPickerFrame.targetField or nil
    local control = targetField and TwAuras.configFrame and TwAuras.configFrame[targetField] or nil
    if control then
      control:SetText("")
      if TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
        TwAuras:ApplyEditorToSelectedAura(true)
      end
    end
    TwAuras.soundPickerFrame:Hide()
  end)
  frame.closeButton = MakeButton(frame, "Close", 90, 22, 330, -(pickerHeight - 34), function()
    frame:Hide()
  end)

  self.soundPickerFrame = frame
  self:RefreshSoundPickerFilter()
end

-- The wizard is a lightweight launcher for common aura recipes, not a separate editing system.
function TwAuras:BuildWizardFrame()
  if self.wizardFrame then
    return
  end

  local frame = CreateFrame("Frame", "TwAurasWizardFrame", UIParent)
  frame:SetWidth(340)
  frame:SetHeight(190)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
  })
  frame:Hide()

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("TOP", frame, "TOP", 0, -16)
  frame.title:SetText("TwAuras Wizard")

  frame.help = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.help:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -42)
  frame.help:SetWidth(300)
  frame.help:SetJustifyH("LEFT")
  frame.help:SetText("Create a starter aura, then fill in the spell or aura name in the main editor.")

  frame.buffButton = MakeButton(frame, "Buff Tracker", 130, 24, 18, -82, function()
    TwAuras:AddWizardAura("buff")
    TwAuras.wizardFrame:Hide()
  end)
  frame.debuffButton = MakeButton(frame, "Target Debuff", 130, 24, 18, -114, function()
    TwAuras:AddWizardAura("debuff")
    TwAuras.wizardFrame:Hide()
  end)
  frame.cooldownButton = MakeButton(frame, "Cooldown Ready", 130, 24, 18, -146, function()
    TwAuras:AddWizardAura("cooldown")
    TwAuras.wizardFrame:Hide()
  end)

  frame.buffDesc = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.buffDesc:SetPoint("TOPLEFT", frame, "TOPLEFT", 160, -86)
  frame.buffDesc:SetWidth(155)
  frame.buffDesc:SetJustifyH("LEFT")
  frame.buffDesc:SetText("Track a named buff on the player, target, or pet.")

  frame.debuffDesc = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.debuffDesc:SetPoint("TOPLEFT", frame, "TOPLEFT", 160, -118)
  frame.debuffDesc:SetWidth(155)
  frame.debuffDesc:SetJustifyH("LEFT")
  frame.debuffDesc:SetText("Track a named debuff on your current target, with timer support.")

  frame.cooldownDesc = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.cooldownDesc:SetPoint("TOPLEFT", frame, "TOPLEFT", 160, -150)
  frame.cooldownDesc:SetWidth(155)
  frame.cooldownDesc:SetJustifyH("LEFT")
  frame.cooldownDesc:SetText("Show when a spell is ready or use it as a cooldown template.")

  frame.closeButton = MakeButton(frame, "Close", 90, 22, 228, -156, function()
    frame:Hide()
  end)

  self.wizardFrame = frame
end

function TwAuras:OpenWizard()
  self:BuildWizardFrame()
  BringFrameToFront(self.wizardFrame, self.configFrame, true)
  self.wizardFrame:Show()
end

-- The config window is split into a lightweight list pane and a descriptor-driven detail pane.
function TwAuras:OpenIconPicker()
  self:BuildIconPicker()
  if self.iconPickerFrame.searchBox then
    self.iconPickerFrame.searchBox:SetText("")
  end
  self.iconPickerFrame.pageIndex = 1
  self:RefreshIconPickerFilter()
  BringFrameToFront(self.iconPickerFrame, self.configFrame, true)
  self.iconPickerFrame:Show()
end

function TwAuras:OpenSoundPicker(targetField, label)
  self:BuildSoundPicker()
  self.soundPickerFrame.targetField = targetField
  self.soundPickerFrame.selectedSound = ""
  if self.soundPickerFrame.targetText then
    self.soundPickerFrame.targetText:SetText("Picking for: " .. (label or "Sound"))
  end
  if self.soundPickerFrame.searchBox then
    self.soundPickerFrame.searchBox:SetText("")
  end
  self.soundPickerFrame.pageIndex = 1
  self:RefreshSoundPickerFilter()
  BringFrameToFront(self.soundPickerFrame, self.configFrame, true)
  self.soundPickerFrame:Show()
end

-- The aura list is intentionally simple: select on the left, inspect and edit on the right.
-- Row builders create reusable buttons once, then refresh functions just bind aura data into them.
function TwAuras:BuildAuraListRows(parent)
  parent.__auraRows = parent.__auraRows or {}
  return parent.__auraRows
end

function TwAuras:EnsureAuraListRows(parent, wanted)
  local rows = parent.__auraRows or {}
  local i
  for i = table.getn(rows) + 1, wanted do
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(204)
    button:SetHeight(18)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((i - 1) * 20))
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints(button)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetWidth(14)
    button.icon:SetHeight(14)
    button.icon:SetPoint("LEFT", button, "LEFT", 4, 0)
    button.previewCheck = CreateFrame("CheckButton", NextWidgetName("AuraRowPreviewCheck"), button, "UICheckButtonTemplate")
    button.previewCheck:SetWidth(18)
    button.previewCheck:SetHeight(18)
    button.previewCheck:SetPoint("RIGHT", button, "RIGHT", 0, 0)
    button.previewCheck:SetScript("OnClick", function()
      if not this.__auraId then
        return
      end
      TwAuras:MarkAuraPreviewChoice(this.__auraId)
      TwAuras:SetAuraPreviewState(this.__auraId, this:GetChecked())
      TwAuras:RefreshAll()
      TwAuras:RefreshAuraList()
    end)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetPoint("LEFT", button.icon, "RIGHT", 4, 0)
    button.text:SetWidth(144)
    button.text:SetJustifyH("LEFT")
    button:SetScript("OnMouseUp", function()
      if arg1 == "RightButton" then
        TwAuras:OpenAuraRowMenu(this)
      else
        if TwAuras.configFrame and TwAuras.configFrame.auraRowMenu then
          TwAuras.configFrame.auraRowMenu:Hide()
        end
        TwAuras.db.selectedAuraId = this.__auraId
        TwAuras.db.selectedTriggerIndex = 1
        TwAuras.db.selectedConditionIndex = 1
        TwAuras:RefreshConfigUI()
      end
    end)
    rows[i] = button
  end
  parent.__auraRows = rows
  return rows
end

function TwAuras:BuildConditionListRows(parent)
  parent.__conditionRows = parent.__conditionRows or {}
  return parent.__conditionRows
end

function TwAuras:EnsureConditionListRows(parent, wanted)
  local rows = parent.__conditionRows or {}
  local i
  for i = table.getn(rows) + 1, wanted do
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(144)
    button:SetHeight(20)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((i - 1) * 22))
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints(button)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetPoint("LEFT", button, "LEFT", 4, 0)
    button.text:SetWidth(152)
    button.text:SetJustifyH("LEFT")
    button:SetScript("OnClick", function()
      TwAuras.db.selectedConditionIndex = this.__conditionIndex
      TwAuras:RefreshConfigUI()
    end)
    rows[i] = button
  end
  parent.__conditionRows = rows
  return rows
end

function TwAuras:BuildTriggerListRows(parent)
  parent.__triggerRows = parent.__triggerRows or {}
  return parent.__triggerRows
end

function TwAuras:EnsureTriggerListRows(parent, wanted)
  local rows = parent.__triggerRows or {}
  local i
  for i = table.getn(rows) + 1, wanted do
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(144)
    button:SetHeight(20)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((i - 1) * 22))
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints(button)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetPoint("LEFT", button, "LEFT", 4, 0)
    button.text:SetWidth(152)
    button.text:SetJustifyH("LEFT")
    button:SetScript("OnClick", function()
      TwAuras.db.selectedTriggerIndex = this.__triggerIndex
      TwAuras:RefreshConfigUI()
    end)
    rows[i] = button
  end
  parent.__triggerRows = rows
  return rows
end

-- List refreshes only repaint the visible editor state; they do not mutate the saved data themselves.
function TwAuras:RefreshAuraList()
  -- The left aura pane is intentionally dumb and cheap: just enough summary information to pick
  -- an aura, with all real editing work happening in the detail panel.
  if not self.configFrame or not self.configFrame.auraRows then
    return
  end
  local auras = self:GetAuraList()
  self.configFrame.auraRows = self:EnsureAuraListRows(self.configFrame.auraListContent, math.max(1, table.getn(auras)))
  self.configFrame.auraListContent:SetWidth(204)
  self.configFrame.auraListContent:SetHeight(math.max(1, table.getn(auras) * 20))
  local i
  for i = 1, table.getn(self.configFrame.auraRows) do
    local row = self.configFrame.auraRows[i]
    local aura = auras[i]
    if aura then
      local iconPath = self:GetAuraListPreviewIcon(aura)
      row.__auraId = aura.id
      row.previewCheck.__auraId = aura.id
      row.previewCheck:SetChecked(self:IsAuraPreviewing(aura.id) and true or false)
      row.text:SetText(aura.name)
      if iconPath and iconPath ~= "" then
        row.icon:SetTexture(iconPath)
        row.icon:Show()
      else
        row.icon:SetTexture(nil)
        row.icon:Hide()
      end
      if self.db.selectedAuraId == aura.id then
        row.bg:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.bg:SetVertexColor(0.2, 0.8, 0.2, 0.35)
      else
        row.bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        row.bg:SetVertexColor(1, 1, 1, 0.08)
      end
      row.previewCheck:Show()
      row:Show()
    else
      row.icon:SetTexture(nil)
      row.icon:Hide()
      row.previewCheck:SetChecked(false)
      row.previewCheck:Hide()
      row:Hide()
    end
  end
end

function TwAuras:RefreshObjectSummary()
  if not self.configFrame or not self.configFrame.objectSummaryText then
    return
  end
  local total = self:GetObjectSummaryCount()
  local r, g, b = self:GetObjectSummaryLoadColor(total)
  self.configFrame.objectSummaryText:SetText("Objects: " .. tostring(total))
  if self.configFrame.objectSummaryText.SetTextColor then
    self.configFrame.objectSummaryText:SetTextColor(r, g, b)
  end
  if self.configFrame.objectSummarySwatch and self.configFrame.objectSummarySwatch.SetBackdropColor then
    self.configFrame.objectSummarySwatch:SetBackdropColor(r, g, b, 1)
  end
end

-- The Apply button is only actionable when live update is off, so its enabled state is derived
-- from the checkbox instead of being managed ad hoc across many widget callbacks.
function TwAuras:RefreshLiveUpdateUI()
  local frame = self.configFrame
  local liveEnabled
  if not frame or not frame.liveUpdateCheck or not frame.applyButton then
    return
  end
  liveEnabled = frame.liveUpdateCheck:GetChecked() and true or false
  if liveEnabled then
    frame.applyButton:Disable()
  else
    frame.applyButton:Enable()
  end
end

-- Trigger rows are separate from trigger fields so one aura can own many conditions cleanly.
function TwAuras:RefreshTriggerList()
  -- Trigger rows are summaries only; the selected trigger's descriptor determines the actual
  -- editable controls shown to the right.
  local aura = self:GetSelectedAura()
  local frame = self.configFrame
  if not frame or not frame.triggerListRows or not frame.triggerListContent then
    return
  end
  if not aura then
    return
  end

  self:EnsureSingleBlankTrigger(aura)
  frame.triggerListRows = self:EnsureTriggerListRows(frame.triggerListContent, table.getn(aura.triggers))
  frame.triggerListContent:SetWidth(144)
  frame.triggerListContent:SetHeight(math.max(1, table.getn(aura.triggers) * 22))
  local selectedIndex = self:GetSelectedTriggerIndex(aura)
  local i
  for i = 1, table.getn(frame.triggerListRows) do
    local row = frame.triggerListRows[i]
    local trigger = aura.triggers[i]
    if trigger then
      row.__triggerIndex = i
      local triggerDefinition = self:GetTriggerTypeDefinition(trigger.type)
      local triggerName = triggerDefinition and triggerDefinition.displayName or (trigger.type or "none")
      local label = "Trigger " .. i .. ": " .. triggerName
      if trigger.auraName and trigger.auraName ~= "" then
        label = label .. " (" .. trigger.auraName .. ")"
      elseif trigger.powerType and trigger.type == "power" then
        label = label .. " (" .. trigger.powerType .. ")"
      end
      row.text:SetText(label)
      if selectedIndex == i then
        row.bg:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.bg:SetVertexColor(0.2, 0.8, 0.2, 0.35)
      else
        row.bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        row.bg:SetVertexColor(1, 1, 1, 0.08)
      end
      row:Show()
    else
      row:Hide()
    end
  end
end

function TwAuras:RefreshConditionList()
  -- Conditions mirror the trigger-editor pattern so developers can reason about both tabs the
  -- same way: ordered list on the left, field editor on the right.
  local aura = self:GetSelectedAura()
  local frame = self.configFrame
  if not frame or not frame.conditionListRows or not frame.conditionListContent then
    return
  end
  if not aura then
    return
  end

  frame.conditionListRows = self:EnsureConditionListRows(frame.conditionListContent, math.max(1, table.getn(aura.conditions or {})))
  frame.conditionListContent:SetWidth(144)
  frame.conditionListContent:SetHeight(math.max(1, math.max(1, table.getn(aura.conditions or {})) * 22))
  local selectedIndex = self:GetSelectedConditionIndex(aura)
  local i
  for i = 1, table.getn(frame.conditionListRows) do
    local row = frame.conditionListRows[i]
    local condition = aura.conditions and aura.conditions[i] or nil
    if condition then
      row.__conditionIndex = i
      row.text:SetText("Condition " .. i .. ": " .. (condition.check or "active"))
      if selectedIndex == i then
        row.bg:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.bg:SetVertexColor(0.2, 0.8, 0.2, 0.35)
      else
        row.bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        row.bg:SetVertexColor(1, 1, 1, 0.08)
      end
      row:Show()
    elseif i == 1 and table.getn(aura.conditions or {}) == 0 then
      row.__conditionIndex = nil
      row.text:SetText("No conditions")
      row.bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
      row.bg:SetVertexColor(1, 1, 1, 0.04)
      row:Show()
    else
      row:Hide()
    end
  end
end

-- Refreshing the editor from the selected aura keeps the UI stateless and easy to rebuild.
-- RefreshEditorFields pushes the selected aura's saved data into the current tab widgets.
function TwAuras:RefreshEditorFields()
  local aura = self:GetSelectedAura()
  local frame = self.configFrame
  if not frame then
    return
  end
  frame.__suppressLiveUpdate = true
  if not aura then
    frame.editorTitle:SetText("No aura selected")
    frame.__suppressLiveUpdate = false
    return
  end

  self:NormalizeAuraConfig(aura)
  self:EnsureSingleBlankTrigger(aura)
  frame.editorTitle:SetText("Edit: " .. aura.name)
  if frame.summaryText then
    frame.summaryText:SetText(self:GetAuraSummary(aura, 252))
  end
  frame.nameBox:SetText(aura.name or "")
  self:SetSelectValue(frame.triggerModeBox, aura.triggerMode or "all", TRIGGER_MODE_OPTIONS)
  self:RefreshTriggerList()
  self:RefreshConditionList()

  local trigger = self:GetSelectedTrigger(aura)
  if not trigger then
    trigger = self:CreateDisabledTrigger()
  end
  frame.triggerTypeBox.__options = self:GetAvailableTriggerTypes()
  self:SetSelectValue(frame.triggerTypeBox, trigger.type or "", frame.triggerTypeBox.__options)
  local triggerDefinition = self:GetTriggerTypeDefinition(trigger.type) or self:GetTriggerTypeDefinition("none")
  frame.triggerDescriptorTitle:SetText((triggerDefinition and triggerDefinition.displayName or "Trigger") .. " Fields")
  frame.triggerDescriptorHelp:SetText(triggerDefinition and JoinKeys(self:GetAvailableTriggerTypes()) or "")
  frame.triggerFieldWidgets = self:EnsureDescriptorFieldGroup("triggerField", frame.triggerFieldPanel, "Trigger", triggerDefinition, 0, 0, 170, 62)
  local _, triggerWidget
  for _, triggerWidget in pairs(frame.triggerFieldWidgets or {}) do
    self:SetDescriptorWidgetValue(triggerWidget, trigger[triggerWidget.field.key])
  end

  frame.regionTypeBox.__options = self:GetAvailableRegionTypes()
  self:SetSelectValue(frame.regionTypeBox, aura.regionType or "icon", frame.regionTypeBox.__options)
  local regionDefinition = self:GetRegionType(aura.regionType) or self:GetRegionType("icon")
  frame.regionDescriptorTitle:SetText((regionDefinition and regionDefinition.displayName or "Region") .. " Fields")
  frame.regionDescriptorHelp:SetText("Tokens: %name %label %time %value %max %percent %stacks %realhp %realmaxhp %realhpdeficit %realmana %realmaxmana %realmanadeficit")
  frame.regionFieldContent:SetHeight(self:GetDescriptorGroupHeight(regionDefinition, 62))
  frame.regionFieldWidgets = self:EnsureDescriptorFieldGroup("regionField", frame.regionFieldContent, "Region", regionDefinition, 0, 0, 230, 62)
  local _, regionWidget
  for _, regionWidget in pairs(frame.regionFieldWidgets or {}) do
    self:SetDescriptorWidgetValue(regionWidget, aura.display[regionWidget.field.key])
  end
  if frame.regionFieldWidgets and frame.regionFieldWidgets.iconPath then
    frame.iconPickerButton:Show()
  else
    frame.iconPickerButton:Hide()
  end

  frame.alphaSlider:SetValue(aura.display.alpha or 1)
  getglobal(frame.alphaSlider:GetName() .. "Text"):SetText("Alpha: " .. string.format("%.2f", aura.display.alpha or 1))
  frame.enabledCheck:SetChecked(aura.enabled and true or false)
  frame.displayDebugCheck:SetChecked(aura.debug and aura.debug.display and true or false)
  frame.triggerDebugCheck:SetChecked(aura.debug and aura.debug.trigger and true or false)
  frame.conditionsDebugCheck:SetChecked(aura.debug and aura.debug.conditions and true or false)
  frame.loadDebugCheck:SetChecked(aura.debug and aura.debug.load and true or false)
  frame.combatLogDebugCheck:SetChecked(aura.debug and aura.debug.combatlog and true or false)
  frame.timerDebugCheck:SetChecked(aura.debug and aura.debug.timer and true or false)
  frame.unitFramesDebugCheck:SetChecked(aura.debug and aura.debug.unitframes and true or false)
  frame.inCombatCheck:SetChecked(aura.load and aura.load.inCombat and true or false)
  frame.requireTargetCheck:SetChecked(aura.load and aura.load.requireTarget and true or false)
  frame.allowWorldCheck:SetChecked(aura.load and aura.load.allowWorld ~= false and true or false)
  frame.allowDungeonCheck:SetChecked(aura.load and aura.load.allowDungeon ~= false and true or false)
  frame.allowRaidCheck:SetChecked(aura.load and aura.load.allowRaid ~= false and true or false)
  frame.allowPvpCheck:SetChecked(aura.load and aura.load.allowPvp ~= false and true or false)
  frame.allowArenaCheck:SetChecked(aura.load and aura.load.allowArena ~= false and true or false)
  self:SetSelectValue(frame.classBox, (aura.load and aura.load.class) or "", CLASS_OPTIONS)
  frame.zoneTextBox:SetText((aura.load and aura.load.zoneText) or "")
  frame.updateEventsBox:SetText((aura.load and aura.load.updateEvents) or "")
  self:SetSelectValue(frame.pointBox, (aura.position and aura.position.point) or "CENTER", POINT_OPTIONS)
  self:SetSelectValue(frame.relativePointBox, (aura.position and aura.position.relativePoint) or "CENTER", POINT_OPTIONS)
  frame.xBox:SetText(tostring((aura.position and aura.position.x) or 0))
  frame.yBox:SetText(tostring((aura.position and aura.position.y) or 0))

  local condition = self:GetSelectedCondition(aura)
  if not condition then
    condition = self:CreateDefaultCondition()
  end
  frame.conditionEnabledCheck:SetChecked(condition.enabled and true or false)
  self:SetSelectValue(frame.conditionCheckBox, condition.check or "active", CONDITION_CHECK_OPTIONS)
  self:SetSelectValue(frame.conditionOperatorBox, condition.operator or "=", OPERATOR_OPTIONS)
  frame.conditionThresholdBox:SetText(tostring(condition.threshold or 0))
  frame.conditionUseAlphaCheck:SetChecked(condition.useAlpha and true or false)
  frame.conditionAlphaBox:SetText(tostring(condition.alpha or 1))
  frame.conditionGlowCheck:SetChecked(condition.useGlow and condition.glow and true or false)
  frame.conditionDesaturateCheck:SetChecked(condition.useDesaturate and condition.desaturate and true or false)
  frame.conditionUseColorCheck:SetChecked(condition.useColor and true or false)
  frame.conditionColor1:SetText(string.format("%.2f", (condition.color and condition.color[1]) or 1))
  frame.conditionColor2:SetText(string.format("%.2f", (condition.color and condition.color[2]) or 1))
  frame.conditionColor3:SetText(string.format("%.2f", (condition.color and condition.color[3]) or 1))
  frame.conditionColor4:SetText(string.format("%.2f", (condition.color and condition.color[4]) or 1))
  frame.conditionUseTextColorCheck:SetChecked(condition.useTextColor and true or false)
  frame.conditionTextColor1:SetText(string.format("%.2f", (condition.textColor and condition.textColor[1]) or 1))
  frame.conditionTextColor2:SetText(string.format("%.2f", (condition.textColor and condition.textColor[2]) or 1))
  frame.conditionTextColor3:SetText(string.format("%.2f", (condition.textColor and condition.textColor[3]) or 1))
  frame.conditionTextColor4:SetText(string.format("%.2f", (condition.textColor and condition.textColor[4]) or 1))
  frame.conditionUseBgColorCheck:SetChecked(condition.useBgColor and true or false)
  frame.conditionBgColor1:SetText(string.format("%.2f", (condition.bgColor and condition.bgColor[1]) or 0))
  frame.conditionBgColor2:SetText(string.format("%.2f", (condition.bgColor and condition.bgColor[2]) or 0))
  frame.conditionBgColor3:SetText(string.format("%.2f", (condition.bgColor and condition.bgColor[3]) or 0))
  frame.conditionBgColor4:SetText(string.format("%.2f", (condition.bgColor and condition.bgColor[4]) or 0.5))
  frame.soundStartBox:SetText((aura.soundActions and aura.soundActions.startSound) or "")
  frame.soundActiveBox:SetText((aura.soundActions and aura.soundActions.activeSound) or "")
  frame.soundActiveIntervalBox:SetText(tostring((aura.soundActions and aura.soundActions.activeInterval) or 2))
  frame.soundStopBox:SetText((aura.soundActions and aura.soundActions.stopSound) or "")
  frame.__suppressLiveUpdate = false
end

-- RefreshConfigUI is the main editor repaint entry point after selection changes or edits.
function TwAuras:RefreshConfigUI()
  if not self.configFrame then
    return
  end
  self:EnsureSelectedAuraPreview()
  self:RefreshAll()
  self:RefreshAuraList()
  self:RefreshObjectSummary()
  self:RefreshEditorFields()
end

-- Applying writes UI values back into saved config, then rebuilds the region so display changes
-- never leave stale frame state from an older trigger or region type behind.
-- Applying editor changes is where widget values get written back into the selected saved aura.
function TwAuras:ApplyEditorToSelectedAura(isLive)
  -- This is the editor commit point: read widgets, write aura fields, normalize, then rebuild
  -- or refresh the live region so the screen reflects the editor state.
  local aura = self:GetSelectedAura()
  local frame = self.configFrame
  if not aura or not frame then
    return
  end

  local wantedName = frame.nameBox:GetText()
  aura.name = self:GetUniqueAuraName(wantedName ~= "" and wantedName or ("New Aura " .. tostring(aura.id)), aura.id)
  frame.nameBox:SetText(aura.name)
  aura.triggerMode = SafeLower(frame.triggerModeBox.__value or "all")
  self:EnsureSingleBlankTrigger(aura)

  local trigger, triggerIndex = self:GetSelectedTrigger(aura)
  if trigger and triggerIndex then
    trigger.type = SafeLower(frame.triggerTypeBox.__value or "")
    local triggerDefinition = self:GetTriggerTypeDefinition(trigger.type) or self:GetTriggerTypeDefinition("none")
    local triggerWidgets = self:EnsureDescriptorFieldGroup("triggerField", frame.triggerFieldPanel, "Trigger", triggerDefinition, 0, 0, 170, 62)
    local _, triggerWidget
    for _, triggerWidget in pairs(triggerWidgets or {}) do
      trigger[triggerWidget.field.key] = self:GetDescriptorWidgetValue(triggerWidget)
    end
  end

  aura.regionType = SafeLower(frame.regionTypeBox.__value or "icon")
  local regionDefinition = self:GetRegionType(aura.regionType) or self:GetRegionType("icon")
  frame.regionFieldContent:SetHeight(self:GetDescriptorGroupHeight(regionDefinition, 62))
  local regionWidgets = self:EnsureDescriptorFieldGroup("regionField", frame.regionFieldContent, "Region", regionDefinition, 0, 0, 230, 62)
  local _, regionWidget
  for _, regionWidget in pairs(regionWidgets or {}) do
    aura.display[regionWidget.field.key] = self:GetDescriptorWidgetValue(regionWidget)
  end
  aura.display.alpha = frame.alphaSlider:GetValue() or 1

  local condition, conditionIndex = self:GetSelectedCondition(aura)
  if condition and conditionIndex then
    condition.enabled = frame.conditionEnabledCheck:GetChecked() and true or false
    condition.check = SafeLower(frame.conditionCheckBox.__value or "active")
    condition.operator = frame.conditionOperatorBox.__value ~= "" and frame.conditionOperatorBox.__value or "="
    condition.threshold = tonumber(frame.conditionThresholdBox:GetText()) or 0
    condition.useAlpha = frame.conditionUseAlphaCheck:GetChecked() and true or false
    condition.alpha = tonumber(frame.conditionAlphaBox:GetText()) or 1
    condition.useGlow = frame.conditionGlowCheck:GetChecked() and true or false
    condition.glow = frame.conditionGlowCheck:GetChecked() and true or false
    condition.useDesaturate = frame.conditionDesaturateCheck:GetChecked() and true or false
    condition.desaturate = frame.conditionDesaturateCheck:GetChecked() and true or false
    condition.useColor = frame.conditionUseColorCheck:GetChecked() and true or false
    condition.color = {
      tonumber(frame.conditionColor1:GetText()) or 1,
      tonumber(frame.conditionColor2:GetText()) or 1,
      tonumber(frame.conditionColor3:GetText()) or 1,
      tonumber(frame.conditionColor4:GetText()) or 1,
    }
    condition.useTextColor = frame.conditionUseTextColorCheck:GetChecked() and true or false
    condition.textColor = {
      tonumber(frame.conditionTextColor1:GetText()) or 1,
      tonumber(frame.conditionTextColor2:GetText()) or 1,
      tonumber(frame.conditionTextColor3:GetText()) or 1,
      tonumber(frame.conditionTextColor4:GetText()) or 1,
    }
    condition.useBgColor = frame.conditionUseBgColorCheck:GetChecked() and true or false
    condition.bgColor = {
      tonumber(frame.conditionBgColor1:GetText()) or 0,
      tonumber(frame.conditionBgColor2:GetText()) or 0,
      tonumber(frame.conditionBgColor3:GetText()) or 0,
      tonumber(frame.conditionBgColor4:GetText()) or 0.5,
    }
  end

  aura.soundActions = aura.soundActions or self:CreateDefaultSoundActions()
  aura.soundActions.startSound = frame.soundStartBox:GetText() or ""
  aura.soundActions.activeSound = frame.soundActiveBox:GetText() or ""
  aura.soundActions.activeInterval = tonumber(frame.soundActiveIntervalBox:GetText()) or 2
  aura.soundActions.stopSound = frame.soundStopBox:GetText() or ""

  aura.enabled = frame.enabledCheck:GetChecked() and true or false
  aura.debug = aura.debug or self:CreateDefaultDebugOptions()
  aura.debug.display = frame.displayDebugCheck:GetChecked() and true or false
  aura.debug.trigger = frame.triggerDebugCheck:GetChecked() and true or false
  aura.debug.conditions = frame.conditionsDebugCheck:GetChecked() and true or false
  aura.debug.load = frame.loadDebugCheck:GetChecked() and true or false
  aura.debug.combatlog = frame.combatLogDebugCheck:GetChecked() and true or false
  aura.debug.timer = frame.timerDebugCheck:GetChecked() and true or false
  aura.debug.unitframes = frame.unitFramesDebugCheck:GetChecked() and true or false
  aura.load.inCombat = frame.inCombatCheck:GetChecked() and true or false
  aura.load.requireTarget = frame.requireTargetCheck:GetChecked() and true or false
  aura.load.allowWorld = frame.allowWorldCheck:GetChecked() and true or false
  aura.load.allowDungeon = frame.allowDungeonCheck:GetChecked() and true or false
  aura.load.allowRaid = frame.allowRaidCheck:GetChecked() and true or false
  aura.load.allowPvp = frame.allowPvpCheck:GetChecked() and true or false
  aura.load.allowArena = frame.allowArenaCheck:GetChecked() and true or false
  aura.load.class = frame.classBox.__value
  aura.load.zoneText = frame.zoneTextBox:GetText() or ""
  aura.load.updateEvents = frame.updateEventsBox:GetText() or ""
  if aura.load.class == "" then
    aura.load.class = nil
  end

  aura.position.point = frame.pointBox.__value ~= "" and frame.pointBox.__value or "CENTER"
  aura.position.relativePoint = frame.relativePointBox.__value ~= "" and frame.relativePointBox.__value or "CENTER"
  aura.position.x = tonumber(frame.xBox:GetText()) or 0
  aura.position.y = tonumber(frame.yBox:GetText()) or 0

  self:NormalizeAuraConfig(aura)
  self:EnsureSingleBlankTrigger(aura)
  if frame.summaryText then
    frame.summaryText:SetText(self:GetAuraSummary(aura, 252))
  end
  self:StopAuraTimersForAura(aura)
  self:RebuildSelectedRegion()
  self:RefreshAll()
  if not isLive then
    self:RefreshConfigUI()
  end
end

-- BuildConfigFrame creates the static shell once; later updates only swap values and descriptor groups.
-- BuildConfigFrame creates the whole editor once; later calls simply show, hide, and refresh it.
function TwAuras:BuildConfigFrame()
  -- The config frame is built once and reused. This avoids recreating many widget globals and
  -- keeps editor refreshes about swapping values rather than rebuilding the shell.
  if self.configFrame then
    return
  end

  local frame = CreateFrame("Frame", "TwAurasConfigFrame", UIParent)
  frame:SetWidth(960)
  frame:SetHeight(620)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetToplevel(true)
  frame:SetFrameStrata("DIALOG")
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
  })
  frame:Hide()

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -10)
  frame.title:SetText("TwAuras Config")

  frame.leftPanel = CreateFrame("Frame", nil, frame)
  frame.leftPanel:SetWidth(226)
  frame.leftPanel:SetHeight(552)
  frame.leftPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -30)
  local leftBackground = frame.leftPanel:CreateTexture(nil, "BACKGROUND")
  leftBackground:SetAllPoints(frame.leftPanel)
  leftBackground:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  leftBackground:SetVertexColor(0, 0, 0, 0.25)
  frame.leftBackground = leftBackground
  MakeLabel(frame.leftPanel, "Auras", 6, -8)
  frame.addButton = MakeButton(frame.leftPanel, "[+]", 36, 22, 138, -4, function() TwAuras:AddAura() end)
  frame.wizardButton = MakeButton(frame.leftPanel, "Wizard", 72, 22, 178, -4, function() TwAuras:OpenWizard() end)
  frame.auraListPanel = CreateFrame("Frame", nil, frame.leftPanel)
  frame.auraListPanel:SetWidth(206)
  frame.auraListPanel:SetHeight(462)
  frame.auraListPanel:SetPoint("TOPLEFT", frame.leftPanel, "TOPLEFT", 6, -32)
  frame.auraListScroll = CreateFrame("ScrollFrame", "TwAurasAuraListScroll", frame.auraListPanel, "UIPanelScrollFrameTemplate")
  frame.auraListScroll:SetWidth(204)
  frame.auraListScroll:SetHeight(462)
  frame.auraListScroll:SetPoint("TOPLEFT", frame.auraListPanel, "TOPLEFT", 0, 0)
  frame.auraListContent = CreateFrame("Frame", nil, frame.auraListScroll)
  frame.auraListContent:SetWidth(186)
  frame.auraListContent:SetHeight(1)
  frame.auraListScroll:SetScrollChild(frame.auraListContent)
  frame.auraRows = self:BuildAuraListRows(frame.auraListContent)
  frame.deleteButton = MakeButton(frame.leftPanel, "Delete", 76, 22, 6, -502, function() TwAuras:OpenDeleteConfirm() end)
  frame.objectSummarySwatch = CreateFrame("Frame", nil, frame.leftPanel)
  frame.objectSummarySwatch:SetWidth(12)
  frame.objectSummarySwatch:SetHeight(12)
  frame.objectSummarySwatch:SetPoint("LEFT", frame.deleteButton, "RIGHT", 8, 0)
  frame.objectSummarySwatch:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  frame.objectSummarySwatch:SetBackdropColor(0.25, 0.95, 0.35, 1)
  frame.objectSummaryText = frame.leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.objectSummaryText:SetPoint("LEFT", frame.objectSummarySwatch, "RIGHT", 6, 0)
  frame.objectSummaryText:SetWidth(102)
  frame.objectSummaryText:SetJustifyH("LEFT")
  frame.objectSummaryText:SetText("Objects: 0")
  frame.objectSummaryHitbox = CreateFrame("Frame", nil, frame.leftPanel)
  frame.objectSummaryHitbox:SetWidth(122)
  frame.objectSummaryHitbox:SetHeight(18)
  frame.objectSummaryHitbox:SetPoint("LEFT", frame.objectSummarySwatch, "LEFT", 0, 0)
  frame.objectSummaryHitbox:EnableMouse(true)
  AttachObjectSummaryTooltip(frame.objectSummaryHitbox)

  frame.rightPanel = CreateFrame("Frame", nil, frame)
  frame.rightPanel:SetWidth(680)
  frame.rightPanel:SetHeight(552)
  frame.rightPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 262, -30)
  local rightBackground = frame.rightPanel:CreateTexture(nil, "BACKGROUND")
  rightBackground:SetAllPoints(frame.rightPanel)
  rightBackground:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  rightBackground:SetVertexColor(0, 0, 0, 0.18)
  frame.rightBackground = rightBackground
  frame.editorTitle = frame.rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.editorTitle:SetPoint("TOPLEFT", frame.rightPanel, "TOPLEFT", 8, -8)
  frame.editorTitle:SetText("Edit")
  frame.summaryText = frame.rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.summaryText:SetPoint("TOPLEFT", frame.rightPanel, "TOPLEFT", 8, -24)
  frame.summaryText:SetWidth(640)
  frame.summaryText:SetJustifyH("LEFT")
  frame.summaryText:SetText("")

  frame.tabButtons = {}
  local tabNames = {"Display", "Trigger", "Conditions", "Load"}
  local totalTabWidth = (table.getn(tabNames) * 102) + ((table.getn(tabNames) - 1) * 4)
  local tabStartX = math.floor((960 - totalTabWidth - 46 - 4) / 2)
  local i
  for i = 1, table.getn(tabNames) do
    local button = CreateFrame("Button", NextWidgetName("ConfigTabButton"), frame, "UIPanelButtonTemplate")
    button:SetWidth(102)
    button:SetHeight(20)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", tabStartX + ((i - 1) * 106), -8)
    button:SetText(tabNames[i])
    button.__tab = SafeLower(tabNames[i])
    button:SetScript("OnClick", function() TwAuras:ShowConfigTab(this.__tab) end)
    frame.tabButtons[i] = button
  end
  frame.minimizeButton = CreateFrame("Button", NextWidgetName("ConfigMinimizeButton"), frame, "UIPanelButtonTemplate")
  frame.minimizeButton:SetWidth(46)
  frame.minimizeButton:SetHeight(20)
  frame.minimizeButton:SetPoint("TOPLEFT", frame, "TOPLEFT", tabStartX + totalTabWidth + 4, -8)
  frame.minimizeButton:SetText("[ _ ]")
  frame.minimizeButton:SetScript("OnClick", function()
    TwAuras:ToggleConfigMinimized()
  end)

  -- Keep the header and summary fixed while each major editor tab scrolls independently.
  -- The actual tab panels stay as the scroll children so the existing widget parenting can remain intact.
  frame.tabScrolls = {
    trigger = CreateFrame("ScrollFrame", "TwAurasTriggerTabScroll", frame.rightPanel, "UIPanelScrollFrameTemplate"),
    display = CreateFrame("ScrollFrame", "TwAurasDisplayTabScroll", frame.rightPanel, "UIPanelScrollFrameTemplate"),
    conditions = CreateFrame("ScrollFrame", "TwAurasConditionsTabScroll", frame.rightPanel, "UIPanelScrollFrameTemplate"),
    load = CreateFrame("ScrollFrame", "TwAurasLoadTabScroll", frame.rightPanel, "UIPanelScrollFrameTemplate"),
  }
  frame.tabs = {
    trigger = CreateFrame("Frame", nil, frame.rightPanel),
    display = CreateFrame("Frame", nil, frame.rightPanel),
    conditions = CreateFrame("Frame", nil, frame.rightPanel),
    load = CreateFrame("Frame", nil, frame.rightPanel),
    position = CreateFrame("Frame", nil, frame.rightPanel),
  }
  local key, scrollFrame
  for key, scrollFrame in pairs(frame.tabScrolls) do
    scrollFrame:SetWidth(654)
    scrollFrame:SetHeight(470)
    scrollFrame:SetPoint("TOPLEFT", frame.rightPanel, "TOPLEFT", 10, -66)
    scrollFrame:Hide()
  end
  local key, panel
  for key, panel in pairs(frame.tabs) do
    panel:SetWidth(636)
    panel:SetHeight(470)
    if frame.tabScrolls[key] then
      frame.tabScrolls[key]:SetScrollChild(panel)
    else
      panel:SetPoint("TOPLEFT", frame.rightPanel, "TOPLEFT", 10, -66)
    end
  end

  local triggerTab = frame.tabs.trigger
  local regionTypeList = JoinKeys(self:GetAvailableRegionTypes())
  triggerTab:SetHeight(470)
  MakeLabel(triggerTab, "Logic", 300, -8)
  frame.triggerModeBox = MakeSelect(triggerTab, 90, 20, 352, -4, TRIGGER_MODE_OPTIONS, function()
    if TwAuras.configFrame and TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
      TwAuras:ApplyEditorToSelectedAura(true)
    end
  end)
  MakeLabel(triggerTab, "all, any, priority", 430, -8)
  frame.triggerDebugCheck = MakeCheck(triggerTab, "TwAurasTriggerDebugCheck", "Debug Trigger", 500, -8)
  frame.combatLogDebugCheck = MakeCheck(triggerTab, "TwAurasCombatLogDebugCheck", "Combat Log Debug", 500, -36)
  frame.timerDebugCheck = MakeCheck(triggerTab, "TwAurasTimerDebugCheck", "Timer Debug", 500, -64)

  frame.triggerListPanel = CreateFrame("Frame", nil, triggerTab)
  frame.triggerListPanel:SetWidth(170)
  frame.triggerListPanel:SetHeight(300)
  frame.triggerListPanel:SetPoint("TOPLEFT", triggerTab, "TOPLEFT", 8, -38)
  frame.triggerListScroll = CreateFrame("ScrollFrame", "TwAurasTriggerListScroll", frame.triggerListPanel, "UIPanelScrollFrameTemplate")
  frame.triggerListScroll:SetWidth(168)
  frame.triggerListScroll:SetHeight(300)
  frame.triggerListScroll:SetPoint("TOPLEFT", frame.triggerListPanel, "TOPLEFT", 0, 0)
  frame.triggerListContent = CreateFrame("Frame", nil, frame.triggerListScroll)
  frame.triggerListContent:SetWidth(144)
  frame.triggerListContent:SetHeight(1)
  frame.triggerListScroll:SetScrollChild(frame.triggerListContent)
  frame.triggerListRows = self:BuildTriggerListRows(frame.triggerListContent)
  frame.addTriggerButton = MakeButton(triggerTab, "Add", 50, 20, 8, -346, function()
    local aura = TwAuras:GetSelectedAura()
    if not aura then return end
    TwAuras:AddBlankTrigger(aura)
    TwAuras:RefreshConfigUI()
  end)
  frame.removeTriggerButton = MakeButton(triggerTab, "Remove", 55, 20, 64, -346, function()
    local aura = TwAuras:GetSelectedAura()
    local _, index = TwAuras:GetSelectedTrigger(aura)
    if not aura or not index then return end
    TwAuras:RemoveTrigger(aura, index)
    TwAuras:RefreshConfigUI()
  end)
  frame.triggerUpButton = MakeButton(triggerTab, "Up", 45, 20, 125, -346, function()
    local aura = TwAuras:GetSelectedAura()
    local _, index = TwAuras:GetSelectedTrigger(aura)
    if not aura or not index then return end
    TwAuras:MoveTrigger(aura, index, -1)
    TwAuras:RefreshConfigUI()
  end)
  frame.triggerDownButton = MakeButton(triggerTab, "Down", 50, 20, 176, -346, function()
    local aura = TwAuras:GetSelectedAura()
    local _, index = TwAuras:GetSelectedTrigger(aura)
    if not aura or not index then return end
    TwAuras:MoveTrigger(aura, index, 1)
    TwAuras:RefreshConfigUI()
  end)

  MakeLabel(triggerTab, "Selected Trigger", 200, -38)
  MakeLabel(triggerTab, "Type", 200, -80)
  frame.triggerTypeBox = MakeSelect(triggerTab, 120, 20, 250, -76, self:GetAvailableTriggerTypes(), function()
    if TwAuras.configFrame and TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
      TwAuras:ApplyEditorToSelectedAura(true)
    end
    TwAuras:RefreshConfigUI()
  end)
  frame.triggerDescriptorTitle = triggerTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.triggerDescriptorTitle:SetPoint("TOPLEFT", triggerTab, "TOPLEFT", 200, -112)
  frame.triggerDescriptorHelp = triggerTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.triggerDescriptorHelp:SetPoint("TOPLEFT", triggerTab, "TOPLEFT", 200, -128)
  frame.triggerDescriptorHelp:SetWidth(340)
  frame.triggerDescriptorHelp:SetJustifyH("LEFT")
  frame.triggerFieldPanel = CreateFrame("Frame", nil, triggerTab)
  frame.triggerFieldPanel:SetWidth(340)
  frame.triggerFieldPanel:SetHeight(210)
  frame.triggerFieldPanel:SetPoint("TOPLEFT", triggerTab, "TOPLEFT", 200, -148)
  -- Quick presets seed the selected trigger with a practical starter configuration, but they still
  -- leave the full trigger editor available for the user to refine afterward.
  MakeLabel(triggerTab, "Quick Presets (set selected trigger)", 200, -318)
  frame.presetBuff = MakeButton(triggerTab, "Buff", 60, 20, 200, -340, function()
    local aura = TwAuras:GetSelectedAura()
    local trigger = TwAuras:GetSelectedTrigger(aura)
    if not aura or not trigger then return end
    trigger.type = "buff"; trigger.unit = "player"; aura.regionType = "icon"; TwAuras:EnsureSingleBlankTrigger(aura); TwAuras:RefreshConfigUI()
  end)
  frame.presetDebuff = MakeButton(triggerTab, "Debuff", 60, 20, 266, -340, function()
    local aura = TwAuras:GetSelectedAura()
    local trigger = TwAuras:GetSelectedTrigger(aura)
    if not aura or not trigger then return end
    trigger.type = "debuff"; trigger.unit = "target"; aura.regionType = "icon"; TwAuras:EnsureSingleBlankTrigger(aura); TwAuras:RefreshConfigUI()
  end)
  frame.presetEnergy = MakeButton(triggerTab, "Energy", 60, 20, 332, -340, function()
    local aura = TwAuras:GetSelectedAura()
    local trigger = TwAuras:GetSelectedTrigger(aura)
    if not aura or not trigger then return end
    trigger.type = "power"; trigger.powerType = "energy"; trigger.unit = "player"; aura.regionType = "bar"; TwAuras:EnsureSingleBlankTrigger(aura); TwAuras:RefreshConfigUI()
  end)
  frame.presetCL = MakeButton(triggerTab, "Log Timer", 72, 20, 398, -340, function()
    local aura = TwAuras:GetSelectedAura()
    local trigger = TwAuras:GetSelectedTrigger(aura)
    if not aura or not trigger then return end
    -- "Log Timer" is meant to be a fast damage-alert starter, so it defaults to a bar and
    -- a self-damage creature spell event instead of the old generic ANY event.
    trigger.type = "combatlog"; trigger.combatLogEvent = "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"; trigger.duration = 10; aura.regionType = "bar"; TwAuras:EnsureSingleBlankTrigger(aura); TwAuras:RefreshConfigUI()
  end)

  local displayTab = frame.tabs.display
  displayTab:SetHeight(540)
  -- The aura's user-facing name now lives in Display so the creation flow matches the visual-first editor order.
  MakeLabel(displayTab, "Name", 8, -8)
  frame.nameBox = MakeEditBox(displayTab, 180, 20, 108, -4)
  MakeLabel(displayTab, "Region Type", 8, -40)
  frame.regionTypeBox = MakeSelect(displayTab, 120, 20, 108, -36, self:GetAvailableRegionTypes(), function()
    if TwAuras.configFrame and TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
      TwAuras:ApplyEditorToSelectedAura(true)
    end
    TwAuras:RefreshConfigUI()
  end)
  MakeLabel(displayTab, regionTypeList, 216, -40)
  frame.displayDebugCheck = MakeCheck(displayTab, "TwAurasDisplayDebugCheck", "Debug Display", 500, -8)
  frame.unitFramesDebugCheck = MakeCheck(displayTab, "TwAurasUnitFramesDebugCheck", "Unit Frame Debug", 500, -36)
  frame.regionDescriptorTitle = displayTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.regionDescriptorTitle:SetPoint("TOPLEFT", displayTab, "TOPLEFT", 8, -70)
  frame.regionDescriptorHelp = displayTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.regionDescriptorHelp:SetPoint("TOPLEFT", displayTab, "TOPLEFT", 8, -86)
  frame.regionDescriptorHelp:SetWidth(544)
  frame.regionDescriptorHelp:SetJustifyH("LEFT")
  frame.regionFieldPanel = CreateFrame("Frame", nil, displayTab)
  frame.regionFieldPanel:SetWidth(644)
  frame.regionFieldPanel:SetHeight(260)
  frame.regionFieldPanel:SetPoint("TOPLEFT", displayTab, "TOPLEFT", 8, -106)
  frame.regionFieldScroll = CreateFrame("ScrollFrame", "TwAurasRegionFieldScroll", frame.regionFieldPanel, "UIPanelScrollFrameTemplate")
  frame.regionFieldScroll:SetWidth(640)
  frame.regionFieldScroll:SetHeight(260)
  frame.regionFieldScroll:SetPoint("TOPLEFT", frame.regionFieldPanel, "TOPLEFT", 0, 0)
  frame.regionFieldContent = CreateFrame("Frame", nil, frame.regionFieldScroll)
  frame.regionFieldContent:SetWidth(620)
  frame.regionFieldContent:SetHeight(1)
  frame.regionFieldScroll:SetScrollChild(frame.regionFieldContent)
  frame.iconPickerButton = MakeButton(displayTab, "Pick Icon", 90, 20, 548, -36, function() TwAuras:OpenIconPicker() end)
  frame.alphaSlider = MakeSlider(displayTab, "TwAurasAlphaSlider", 0, 1, 0.05, 8, -376, 220)
  frame.alphaSlider:SetScript("OnValueChanged", function()
    getglobal(this:GetName() .. "Text"):SetText("Alpha: " .. string.format("%.2f", this:GetValue()))
    if TwAuras.configFrame
      and not TwAuras.configFrame.__suppressLiveUpdate
      and TwAuras.configFrame.liveUpdateCheck
      and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
      TwAuras:ApplyEditorToSelectedAura(true)
    end
  end)
  MakeLabel(displayTab, "The fields below are generated from the selected region type.", 250, -378)

  local conditionsTab = frame.tabs.conditions
  conditionsTab:SetHeight(560)
  frame.conditionsDebugCheck = MakeCheck(conditionsTab, "TwAurasConditionsDebugCheck", "Debug Conditions", 500, -8)
  frame.conditionListPanel = CreateFrame("Frame", nil, conditionsTab)
  frame.conditionListPanel:SetWidth(170)
  frame.conditionListPanel:SetHeight(300)
  frame.conditionListPanel:SetPoint("TOPLEFT", conditionsTab, "TOPLEFT", 8, -8)
  frame.conditionListScroll = CreateFrame("ScrollFrame", "TwAurasConditionListScroll", frame.conditionListPanel, "UIPanelScrollFrameTemplate")
  frame.conditionListScroll:SetWidth(168)
  frame.conditionListScroll:SetHeight(300)
  frame.conditionListScroll:SetPoint("TOPLEFT", frame.conditionListPanel, "TOPLEFT", 0, 0)
  frame.conditionListContent = CreateFrame("Frame", nil, frame.conditionListScroll)
  frame.conditionListContent:SetWidth(144)
  frame.conditionListContent:SetHeight(1)
  frame.conditionListScroll:SetScrollChild(frame.conditionListContent)
  frame.conditionListRows = self:BuildConditionListRows(frame.conditionListContent)
  frame.addConditionButton = MakeButton(conditionsTab, "Add", 50, 20, 8, -316, function()
    local aura = TwAuras:GetSelectedAura()
    if not aura then return end
    TwAuras:AddCondition(aura)
    TwAuras:RefreshConfigUI()
  end)
  frame.removeConditionButton = MakeButton(conditionsTab, "Remove", 55, 20, 64, -316, function()
    local aura = TwAuras:GetSelectedAura()
    local _, index = TwAuras:GetSelectedCondition(aura)
    if not aura or not index then return end
    TwAuras:RemoveCondition(aura, index)
    TwAuras:RefreshConfigUI()
  end)
  frame.conditionUpButton = MakeButton(conditionsTab, "Up", 45, 20, 125, -316, function()
    local aura = TwAuras:GetSelectedAura()
    local _, index = TwAuras:GetSelectedCondition(aura)
    if not aura or not index then return end
    TwAuras:MoveCondition(aura, index, -1)
    TwAuras:RefreshConfigUI()
  end)
  frame.conditionDownButton = MakeButton(conditionsTab, "Down", 50, 20, 176, -316, function()
    local aura = TwAuras:GetSelectedAura()
    local _, index = TwAuras:GetSelectedCondition(aura)
    if not aura or not index then return end
    TwAuras:MoveCondition(aura, index, 1)
    TwAuras:RefreshConfigUI()
  end)

  MakeLabel(conditionsTab, "Check", 200, -8)
  frame.conditionCheckBox = MakeSelect(conditionsTab, 130, 20, 260, -4, CONDITION_CHECK_OPTIONS, function()
    if TwAuras.configFrame and TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
      TwAuras:ApplyEditorToSelectedAura(true)
    end
  end)
  MakeLabel(conditionsTab, "active, remaining, stacks, value, percent", 370, -8)
  MakeLabel(conditionsTab, "Operator", 200, -40)
  frame.conditionOperatorBox = MakeSelect(conditionsTab, 70, 20, 260, -36, OPERATOR_OPTIONS, function()
    if TwAuras.configFrame and TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
      TwAuras:ApplyEditorToSelectedAura(true)
    end
  end)
  MakeLabel(conditionsTab, "Threshold", 330, -40)
  frame.conditionThresholdBox = MakeEditBox(conditionsTab, 70, 20, 400, -36)
  frame.conditionEnabledCheck = CreateFrame("CheckButton", "TwAurasConditionEnabledCheck", conditionsTab, "UICheckButtonTemplate")
  frame.conditionEnabledCheck:SetPoint("TOPLEFT", conditionsTab, "TOPLEFT", 200, -68)
  getglobal("TwAurasConditionEnabledCheckText"):SetText("Condition Enabled")
  frame.conditionUseAlphaCheck = CreateFrame("CheckButton", "TwAurasConditionUseAlphaCheck", conditionsTab, "UICheckButtonTemplate")
  frame.conditionUseAlphaCheck:SetPoint("TOPLEFT", conditionsTab, "TOPLEFT", 200, -96)
  getglobal("TwAurasConditionUseAlphaCheckText"):SetText("Override Alpha")
  frame.conditionAlphaBox = MakeEditBox(conditionsTab, 60, 20, 330, -92)
  frame.conditionGlowCheck = CreateFrame("CheckButton", "TwAurasConditionGlowCheck", conditionsTab, "UICheckButtonTemplate")
  frame.conditionGlowCheck:SetPoint("TOPLEFT", conditionsTab, "TOPLEFT", 200, -124)
  getglobal("TwAurasConditionGlowCheckText"):SetText("Glow")
  frame.conditionDesaturateCheck = CreateFrame("CheckButton", "TwAurasConditionDesaturateCheck", conditionsTab, "UICheckButtonTemplate")
  frame.conditionDesaturateCheck:SetPoint("TOPLEFT", conditionsTab, "TOPLEFT", 300, -124)
  getglobal("TwAurasConditionDesaturateCheckText"):SetText("Desaturate Icon")
  frame.conditionUseColorCheck = CreateFrame("CheckButton", "TwAurasConditionUseColorCheck", conditionsTab, "UICheckButtonTemplate")
  frame.conditionUseColorCheck:SetPoint("TOPLEFT", conditionsTab, "TOPLEFT", 200, -156)
  getglobal("TwAurasConditionUseColorCheckText"):SetText("Override Main Color")
  frame.conditionColor1 = MakeEditBox(conditionsTab, 40, 20, 200, -182)
  frame.conditionColor2 = MakeEditBox(conditionsTab, 40, 20, 246, -182)
  frame.conditionColor3 = MakeEditBox(conditionsTab, 40, 20, 292, -182)
  frame.conditionColor4 = MakeEditBox(conditionsTab, 40, 20, 338, -182)
  frame.conditionUseTextColorCheck = CreateFrame("CheckButton", "TwAurasConditionUseTextColorCheck", conditionsTab, "UICheckButtonTemplate")
  frame.conditionUseTextColorCheck:SetPoint("TOPLEFT", conditionsTab, "TOPLEFT", 200, -214)
  getglobal("TwAurasConditionUseTextColorCheckText"):SetText("Override Text Color")
  frame.conditionTextColor1 = MakeEditBox(conditionsTab, 40, 20, 200, -240)
  frame.conditionTextColor2 = MakeEditBox(conditionsTab, 40, 20, 246, -240)
  frame.conditionTextColor3 = MakeEditBox(conditionsTab, 40, 20, 292, -240)
  frame.conditionTextColor4 = MakeEditBox(conditionsTab, 40, 20, 338, -240)
  frame.conditionUseBgColorCheck = CreateFrame("CheckButton", "TwAurasConditionUseBgColorCheck", conditionsTab, "UICheckButtonTemplate")
  frame.conditionUseBgColorCheck:SetPoint("TOPLEFT", conditionsTab, "TOPLEFT", 200, -272)
  getglobal("TwAurasConditionUseBgColorCheckText"):SetText("Override Background Color")
  frame.conditionBgColor1 = MakeEditBox(conditionsTab, 40, 20, 200, -298)
  frame.conditionBgColor2 = MakeEditBox(conditionsTab, 40, 20, 246, -298)
  frame.conditionBgColor3 = MakeEditBox(conditionsTab, 40, 20, 292, -298)
  frame.conditionBgColor4 = MakeEditBox(conditionsTab, 40, 20, 338, -298)
  MakeLabel(conditionsTab, "Aura Lifecycle Sounds", 200, -332)
  MakeLabel(conditionsTab, "Start Sound", 200, -356)
  frame.soundStartBox = MakeEditBox(conditionsTab, 150, 20, 300, -352)
  frame.soundStartPickButton = MakeButton(conditionsTab, "Pick", 46, 20, 456, -352, function()
    TwAuras:OpenSoundPicker("soundStartBox", "Start Sound")
  end)
  frame.soundStartTestButton = MakeButton(conditionsTab, "Test", 46, 20, 506, -352, function()
    TwAuras:PlayConfiguredSound(TwAuras.configFrame.soundStartBox:GetText() or "")
  end)
  MakeLabel(conditionsTab, "Active Sound", 200, -384)
  frame.soundActiveBox = MakeEditBox(conditionsTab, 150, 20, 300, -380)
  frame.soundActivePickButton = MakeButton(conditionsTab, "Pick", 46, 20, 456, -380, function()
    TwAuras:OpenSoundPicker("soundActiveBox", "Active Sound")
  end)
  frame.soundActiveTestButton = MakeButton(conditionsTab, "Test", 46, 20, 506, -380, function()
    TwAuras:PlayConfiguredSound(TwAuras.configFrame.soundActiveBox:GetText() or "")
  end)
  MakeLabel(conditionsTab, "Repeat Seconds", 200, -412)
  frame.soundActiveIntervalBox = MakeEditBox(conditionsTab, 60, 20, 300, -408)
  MakeLabel(conditionsTab, "Stop Sound", 200, -440)
  frame.soundStopBox = MakeEditBox(conditionsTab, 150, 20, 300, -436)
  frame.soundStopPickButton = MakeButton(conditionsTab, "Pick", 46, 20, 456, -436, function()
    TwAuras:OpenSoundPicker("soundStopBox", "Stop Sound")
  end)
  frame.soundStopTestButton = MakeButton(conditionsTab, "Test", 46, 20, 506, -436, function()
    TwAuras:PlayConfiguredSound(TwAuras.configFrame.soundStopBox:GetText() or "")
  end)
  MakeLabel(conditionsTab, "Use a sound file path or numeric sound id. Start and Stop fire once, Active repeats while the aura stays active.", 200, -466)

  local loadTab = frame.tabs.load
  loadTab:SetHeight(470)
  frame.enabledCheck = CreateFrame("CheckButton", "TwAurasEnabledCheck", loadTab, "UICheckButtonTemplate")
  frame.enabledCheck:SetPoint("TOPLEFT", loadTab, "TOPLEFT", 8, -8)
  getglobal("TwAurasEnabledCheckText"):SetText("Enabled")
  frame.loadDebugCheck = MakeCheck(loadTab, "TwAurasLoadDebugCheck", "Debug Load", 500, -8)
  frame.inCombatCheck = CreateFrame("CheckButton", "TwAurasInCombatCheck", loadTab, "UICheckButtonTemplate")
  frame.inCombatCheck:SetPoint("TOPLEFT", loadTab, "TOPLEFT", 8, -36)
  getglobal("TwAurasInCombatCheckText"):SetText("Only In Combat")
  frame.requireTargetCheck = CreateFrame("CheckButton", "TwAurasRequireTargetCheck", loadTab, "UICheckButtonTemplate")
  frame.requireTargetCheck:SetPoint("TOPLEFT", loadTab, "TOPLEFT", 8, -64)
  getglobal("TwAurasRequireTargetCheckText"):SetText("Require Target")
  frame.allowWorldCheck = CreateFrame("CheckButton", "TwAurasAllowWorldCheck", loadTab, "UICheckButtonTemplate")
  frame.allowWorldCheck:SetPoint("TOPLEFT", loadTab, "TOPLEFT", 240, -8)
  getglobal("TwAurasAllowWorldCheckText"):SetText("World (No Instance)")
  frame.allowDungeonCheck = CreateFrame("CheckButton", "TwAurasAllowDungeonCheck", loadTab, "UICheckButtonTemplate")
  frame.allowDungeonCheck:SetPoint("TOPLEFT", loadTab, "TOPLEFT", 240, -36)
  getglobal("TwAurasAllowDungeonCheckText"):SetText("Dungeons")
  frame.allowRaidCheck = CreateFrame("CheckButton", "TwAurasAllowRaidCheck", loadTab, "UICheckButtonTemplate")
  frame.allowRaidCheck:SetPoint("TOPLEFT", loadTab, "TOPLEFT", 240, -64)
  getglobal("TwAurasAllowRaidCheckText"):SetText("Raids")
  frame.allowPvpCheck = CreateFrame("CheckButton", "TwAurasAllowPvpCheck", loadTab, "UICheckButtonTemplate")
  frame.allowPvpCheck:SetPoint("TOPLEFT", loadTab, "TOPLEFT", 240, -92)
  getglobal("TwAurasAllowPvpCheckText"):SetText("Battlegrounds")
  frame.allowArenaCheck = CreateFrame("CheckButton", "TwAurasAllowArenaCheck", loadTab, "UICheckButtonTemplate")
  frame.allowArenaCheck:SetPoint("TOPLEFT", loadTab, "TOPLEFT", 240, -120)
  getglobal("TwAurasAllowArenaCheckText"):SetText("Arenas")
  MakeLabel(loadTab, "Class", 8, -160)
  frame.classBox = MakeSelect(loadTab, 120, 20, 108, -156, CLASS_OPTIONS, function()
    if TwAuras.configFrame and TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
      TwAuras:ApplyEditorToSelectedAura(true)
    end
  end)
  MakeLabel(loadTab, "ROGUE, DRUID, WARRIOR, etc. Leave blank for all", 216, -160)
  MakeLabel(loadTab, "Zone Text", 8, -194)
  frame.zoneTextBox = MakeEditBox(loadTab, 280, 20, 108, -190)
  MakeLabel(loadTab, "Partial match against the current zone or sub zone.", 8, -220)
  MakeLabel(loadTab, "Update Events", 8, -254)
  frame.updateEventsBox = MakeEditBox(loadTab, 280, 20, 108, -250)
  MakeLabel(loadTab, "world, combat, target, auras, power, combo, health, zone", 8, -280)
  MakeLabel(loadTab, "Leave blank to infer updates from the aura's triggers and load conditions.", 8, -300)

  local positionTab = displayTab
  MakeLabel(positionTab, "Position", 8, -392)
  MakeLabel(positionTab, "Anchor Point", 8, -418)
  frame.pointBox = MakeSelect(positionTab, 120, 20, 108, -414, POINT_OPTIONS, function()
    if TwAuras.configFrame and TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
      TwAuras:ApplyEditorToSelectedAura(true)
    end
  end)
  MakeLabel(positionTab, "Relative Point", 230, -418)
  frame.relativePointBox = MakeSelect(positionTab, 120, 20, 340, -414, POINT_OPTIONS, function()
    if TwAuras.configFrame and TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
      TwAuras:ApplyEditorToSelectedAura(true)
    end
  end)
  MakeLabel(positionTab, "X", 8, -448)
  frame.xBox = MakeEditBox(positionTab, 80, 20, 108, -444)
  MakeLabel(positionTab, "Y", 230, -448)
  frame.yBox = MakeEditBox(positionTab, 80, 20, 340, -444)
  frame.unlockHelp = positionTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.unlockHelp:SetPoint("TOPLEFT", positionTab, "TOPLEFT", 8, -476)
  frame.unlockHelp:SetWidth(520)
  frame.unlockHelp:SetJustifyH("LEFT")
  frame.unlockHelp:SetText("Use Unlock and drag regions on screen. Use the Debug button below to inspect recent combat log lines and copy the event name plus match text into combat log triggers.")

  frame.liveUpdateCheck = CreateFrame("CheckButton", "TwAurasLiveUpdateCheck", frame, "UICheckButtonTemplate")
  frame.liveUpdateCheck:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 216, 18)
  getglobal("TwAurasLiveUpdateCheckText"):SetText("Live Update")
  frame.liveUpdateCheck:SetChecked(true)
  frame.liveUpdateCheck:SetScript("OnClick", function()
    TwAuras:RefreshLiveUpdateUI()
  end)
  frame.applyButton = MakeButton(frame, "Apply", 90, 22, 370, -578, function() TwAuras:ApplyEditorToSelectedAura(false) end)
  frame.closeButton = MakeButton(frame, "Close", 80, 20, 0, 0, function() TwAuras:RequestCloseConfigWindow() end)
  frame.closeButton:ClearAllPoints()
  frame.closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -6)
  frame.debugButton = MakeButton(frame, "Debug", 90, 22, 570, -578, function() TwAuras:DebugRecentCombatLog() end)
  frame.unlockButton = MakeButton(frame, "Unlock", 70, 22, 670, -578, function() TwAuras:SetUnlocked(true) end)
  frame.lockButton = MakeButton(frame, "Lock", 70, 22, 750, -578, function() TwAuras:SetUnlocked(false) end)

  self.configFrame = frame
  frame.currentTab = "display"
  frame.minimized = false
  self:RefreshLiveUpdateUI()
  self:ShowConfigTab("display")
end

-- Tab switching keeps one persistent frame and swaps visible panels instead of rebuilding windows.
-- Scroll positions reset on tab change so each tab reopens at the top of its own editor body.
function TwAuras:ShowConfigTab(tabName)
  if not self.configFrame or not self.configFrame.tabs then
    return
  end
  if self.configFrame.minimized then
    self:SetConfigMinimized(false)
  end
  self.configFrame.currentTab = tabName
  local key, panel
  for key, panel in pairs(self.configFrame.tabs) do
    if self.configFrame.tabScrolls and self.configFrame.tabScrolls[key] then
      if key == tabName then
        self.configFrame.tabScrolls[key]:SetVerticalScroll(0)
        self.configFrame.tabScrolls[key]:Show()
      else
        self.configFrame.tabScrolls[key]:Hide()
      end
      panel:Show()
    else
      if key == tabName then panel:Show() else panel:Hide() end
    end
  end
end

-- Minimize mode collapses the editor down to its banner so users can see the game world underneath.
function TwAuras:SetConfigMinimized(flag)
  local frame = self.configFrame
  local key, panel
  local i
  if not frame then
    return
  end

  frame.minimized = flag and true or false
  if frame.minimized then
    frame:SetWidth(472)
    frame:SetHeight(82)
    frame:SetBackdropColor(0, 0, 0, 0)
    if frame.leftPanel then
      frame.leftPanel:Hide()
      frame.leftPanel:EnableMouse(false)
    end
    if frame.rightPanel then
      frame.rightPanel:SetWidth(452)
      frame.rightPanel:SetHeight(54)
      frame.rightPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
      frame.rightPanel:EnableMouse(false)
    end
    if frame.leftBackground then
      frame.leftBackground:Hide()
    end
    if frame.rightBackground then
      frame.rightBackground:Hide()
    end
    if frame.title then frame.title:Hide() end
    if frame.editorTitle then frame.editorTitle:Hide() end
    if frame.summaryText then frame.summaryText:Hide() end
    if frame.liveUpdateCheck then frame.liveUpdateCheck:Hide() end
    if frame.applyButton then frame.applyButton:Hide() end
    if frame.debugButton then frame.debugButton:Hide() end
    if frame.unlockButton then frame.unlockButton:Hide() end
    if frame.lockButton then frame.lockButton:Hide() end
    if frame.tabScrolls then
      for key, panel in pairs(frame.tabScrolls) do
        panel:Hide()
      end
    end
    if frame.tabs then
      for key, panel in pairs(frame.tabs) do
        panel:Hide()
      end
    end
  else
    frame:SetWidth(960)
    frame:SetHeight(620)
    frame:SetBackdropColor(1, 1, 1, 1)
    if frame.leftPanel then
      frame.leftPanel:Show()
      frame.leftPanel:EnableMouse(true)
    end
    if frame.rightPanel then
      frame.rightPanel:SetWidth(680)
      frame.rightPanel:SetHeight(552)
      frame.rightPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 262, -30)
      frame.rightPanel:EnableMouse(true)
    end
    if frame.leftBackground then
      frame.leftBackground:Show()
    end
    if frame.rightBackground then
      frame.rightBackground:Show()
    end
    if frame.title then frame.title:Show() end
    if frame.editorTitle then frame.editorTitle:Show() end
    if frame.summaryText then frame.summaryText:Show() end
    if frame.liveUpdateCheck then frame.liveUpdateCheck:Show() end
    if frame.applyButton then frame.applyButton:Show() end
    if frame.debugButton then frame.debugButton:Show() end
    if frame.unlockButton then frame.unlockButton:Show() end
    if frame.lockButton then frame.lockButton:Show() end
    if frame.tabScrolls then
      for key, panel in pairs(frame.tabScrolls) do
        panel:Hide()
      end
    end
    self:ShowConfigTab(frame.currentTab or "display")
  end

  if frame.tabButtons then
    for i = 1, table.getn(frame.tabButtons) do
      if frame.tabButtons[i] then
        frame.tabButtons[i]:EnableMouse(true)
        frame.tabButtons[i]:Show()
      end
    end
  end
  if frame.minimizeButton then
    frame.minimizeButton:EnableMouse(true)
    frame.minimizeButton:Show()
  end
end

function TwAuras:ToggleConfigMinimized()
  if not self.configFrame then
    return
  end
  self:SetConfigMinimized(not self.configFrame.minimized)
end

-- Combat guards keep the editor out of risky in-combat mutation paths on old clients.
function TwAuras:IsPlayerInCombat()
  return UnitAffectingCombat and UnitAffectingCombat("player") and true or false
end

function TwAuras:HideConfigWindow()
  if not self.configFrame or not self.configFrame:IsShown() then
    return false
  end
  if self.configFrame.auraRowMenu then
    self.configFrame.auraRowMenu:Hide()
  end
  self.configFrame:Hide()
  return true
end

function TwAuras:OpenConfigWindow()
  self.runtime.pendingConfigOpen = nil
  self:BuildConfigFrame()
  self:SetConfigMinimized(false)
  BringFrameToFront(self.configFrame, UIParent, false)
  self.configFrame:Show()
  self:RefreshConfigUI()
end

function TwAuras:HandleCombatConfigState(eventName)
  self.runtime = self.runtime or {}
  if eventName == "PLAYER_ENTER_COMBAT" then
    if self:HideConfigWindow() then
      self.runtime.pendingConfigOpen = true
      self:Print("Config closed for combat.")
    end
  elseif eventName == "PLAYER_LEAVE_COMBAT" then
    if self.runtime.pendingConfigOpen then
      self:OpenConfigWindow()
      self:Print("Config reopened after combat.")
    end
  end
end

-- ToggleConfig is the only public entry point the slash command needs for config visibility.
function TwAuras:ToggleConfig()
  -- Slash commands and any future menu entry points all flow through this one toggle.
  if self.configFrame and self.configFrame:IsShown() then
    self.runtime.pendingConfigOpen = nil
    self:HideConfigWindow()
    return
  end

  if self:IsPlayerInCombat() then
    self.runtime.pendingConfigOpen = true
    self:Print("Config will open after combat.")
    return
  end

  self:OpenConfigWindow()
end
