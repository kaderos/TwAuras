-- TwAuras file version: 0.1.23
-- Config.lua owns editor-only concerns: aura CRUD, dynamic trigger lists, and descriptor-driven widgets.
local function SafeLower(value)
  if not value then
    return ""
  end
  return string.lower(value)
end

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

local function MakeLabel(parent, text, x, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  return fs
end

local function MakeEditBox(parent, width, height, x, y)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetAutoFocus(false)
  eb:SetWidth(width)
  eb:SetHeight(height)
  eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  return eb
end

local function MakeButton(parent, text, width, height, x, y, onClick)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetWidth(width)
  button:SetHeight(height)
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  button:SetText(text)
  button:SetScript("OnClick", onClick)
  return button
end

local function AttachHoverTooltip(widget, tooltipText)
  if not widget or not tooltipText or tooltipText == "" then
    return
  end
  widget:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(tooltipText, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
end

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

local function MakeSelect(parent, width, height, x, y, options, onChanged)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
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

local function MakeCheck(parent, globalName, text, x, y)
  local check = CreateFrame("CheckButton", globalName, parent, "UICheckButtonTemplate")
  check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  getglobal(globalName .. "Text"):SetText(text)
  return check
end

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

function TwAuras:CreateAuraTemplate()
  -- This template is intentionally close to the normalized runtime shape so a new aura can be
  -- created, displayed, and edited immediately before the next full normalize pass runs.
  local id = self.db.nextId or 1
  self.db.nextId = id + 1
  local aura = {
    id = id,
    key = self:BuildAuraRecordKey(id),
    schemaVersion = 1,
    name = "New Aura " .. id,
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
      labelText = "%name",
      timerText = "%time",
      valueText = "%value/%max",
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
      updateEvents = "",
    },
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
        if TwAuras.configFrame and TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
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
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", 18 + (((i - 1) % columns) * 46), -90 - (math.floor((i - 1) / columns) * 42))
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

  local rowsPerPage = frame.rowsPerPage or 8
  local matches = {}
  local i
  for i = 1, table.getn(frame.buttons or {}) do
    local button = frame.buttons[i]
    local soundPath = string.lower(button.__soundPath or "")
    if query == "" or string.find(soundPath, query, 1, true) then
      table.insert(matches, button)
    else
      button:Hide()
    end
  end

  local totalMatches = table.getn(matches)
  local totalPages = math.max(1, math.ceil(totalMatches / rowsPerPage))
  if not frame.pageIndex or frame.pageIndex < 1 then
    frame.pageIndex = 1
  end
  if frame.pageIndex > totalPages then
    frame.pageIndex = totalPages
  end

  local startIndex = ((frame.pageIndex - 1) * rowsPerPage) + 1
  local endIndex = math.min(totalMatches, startIndex + rowsPerPage - 1)
  local visibleIndex = 0

  for i = startIndex, endIndex do
    local button = matches[i]
    if button then
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -94 - (visibleIndex * 28))
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

function TwAuras:BuildSoundPicker()
  if self.soundPickerFrame then
    return
  end

  local rowsPerPage = 8
  local pickerHeight = 96 + (rowsPerPage * 28) + 28

  local frame = CreateFrame("Frame", "TwAurasSoundPickerFrame", UIParent)
  frame:SetWidth(470)
  frame:SetHeight(pickerHeight)
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
  frame.noResultsText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.noResultsText:SetPoint("TOP", frame, "TOP", 0, -148)
  frame.noResultsText:SetText("No matching sounds in the current picker list.")
  frame.noResultsText:Hide()
  frame.pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.pageText:SetPoint("TOP", frame, "TOP", 0, -78)
  frame.pageText:SetText("Page 1 / 1")

  frame.buttons = {}
  local i
  for i = 1, table.getn(SOUND_PICKER_SOUNDS) do
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetWidth(430)
    button:SetHeight(22)
    button:SetText(SOUND_PICKER_SOUNDS[i])
    button.__soundPath = SOUND_PICKER_SOUNDS[i]
    button:SetScript("OnClick", function()
      local targetField = TwAuras.soundPickerFrame and TwAuras.soundPickerFrame.targetField or nil
      local control = targetField and TwAuras.configFrame and TwAuras.configFrame[targetField] or nil
      if control then
        control:SetText(this.__soundPath or "")
        if TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
          TwAuras:ApplyEditorToSelectedAura(true)
        end
      end
      TwAuras.soundPickerFrame:Hide()
    end)
    frame.buttons[i] = button
  end

  frame.prevButton = MakeButton(frame, "<", 28, 20, 170, -74, function()
    if not TwAuras.soundPickerFrame then
      return
    end
    TwAuras.soundPickerFrame.pageIndex = math.max(1, (TwAuras.soundPickerFrame.pageIndex or 1) - 1)
    TwAuras:RefreshSoundPickerFilter()
  end)
  frame.nextButton = MakeButton(frame, ">", 28, 20, 270, -74, function()
    if not TwAuras.soundPickerFrame then
      return
    end
    TwAuras.soundPickerFrame.pageIndex = (TwAuras.soundPickerFrame.pageIndex or 1) + 1
    TwAuras:RefreshSoundPickerFilter()
  end)
  frame.clearButton = MakeButton(frame, "Clear", 90, 22, 74, -(pickerHeight - 34), function()
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
  frame.closeButton = MakeButton(frame, "Close", 90, 22, 306, -(pickerHeight - 34), function()
    frame:Hide()
  end)

  self.soundPickerFrame = frame
  self:RefreshSoundPickerFilter()
end

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
  self.iconPickerFrame:Show()
end

function TwAuras:OpenSoundPicker(targetField, label)
  self:BuildSoundPicker()
  self.soundPickerFrame.targetField = targetField
  if self.soundPickerFrame.targetText then
    self.soundPickerFrame.targetText:SetText("Picking for: " .. (label or "Sound"))
  end
  if self.soundPickerFrame.searchBox then
    self.soundPickerFrame.searchBox:SetText("")
  end
  self.soundPickerFrame.pageIndex = 1
  self:RefreshSoundPickerFilter()
  self.soundPickerFrame:Show()
end

-- The aura list is intentionally simple: select on the left, inspect and edit on the right.
function TwAuras:BuildAuraListRows(parent)
  parent.__auraRows = parent.__auraRows or {}
  return parent.__auraRows
end

function TwAuras:EnsureAuraListRows(parent, wanted)
  local rows = parent.__auraRows or {}
  local i
  for i = table.getn(rows) + 1, wanted do
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(152)
    button:SetHeight(18)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((i - 1) * 20))
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints(button)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetPoint("LEFT", button, "LEFT", 4, 0)
    button.text:SetWidth(146)
    button.text:SetJustifyH("LEFT")
    button:SetScript("OnClick", function()
      TwAuras.db.selectedAuraId = this.__auraId
      TwAuras.db.selectedTriggerIndex = 1
      TwAuras.db.selectedConditionIndex = 1
      TwAuras:RefreshConfigUI()
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

function TwAuras:RefreshAuraList()
  -- The left aura pane is intentionally dumb and cheap: just enough summary information to pick
  -- an aura, with all real editing work happening in the detail panel.
  if not self.configFrame or not self.configFrame.auraRows then
    return
  end
  local auras = self:GetAuraList()
  self.configFrame.auraRows = self:EnsureAuraListRows(self.configFrame.auraListContent, math.max(1, table.getn(auras)))
  self.configFrame.auraListContent:SetWidth(152)
  self.configFrame.auraListContent:SetHeight(math.max(1, table.getn(auras) * 20))
  local i
  for i = 1, table.getn(self.configFrame.auraRows) do
    local row = self.configFrame.auraRows[i]
    local aura = auras[i]
    if aura then
      row.__auraId = aura.id
      row.text:SetText(aura.name .. " - " .. self:GetAuraSummary(aura, 96))
      if self.db.selectedAuraId == aura.id then
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
function TwAuras:RefreshEditorFields()
  local aura = self:GetSelectedAura()
  local frame = self.configFrame
  if not frame then
    return
  end
  if not aura then
    frame.editorTitle:SetText("No aura selected")
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
  frame.inCombatCheck:SetChecked(aura.load and aura.load.inCombat and true or false)
  frame.requireTargetCheck:SetChecked(aura.load and aura.load.requireTarget and true or false)
  self:SetSelectValue(frame.classBox, (aura.load and aura.load.class) or "", CLASS_OPTIONS)
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
end

function TwAuras:RefreshConfigUI()
  if not self.configFrame then
    return
  end
  self:RefreshAuraList()
  self:RefreshEditorFields()
end

-- Applying writes UI values back into saved config, then rebuilds the region so display changes
-- never leave stale frame state from an older trigger or region type behind.
function TwAuras:ApplyEditorToSelectedAura(isLive)
  -- This is the editor commit point: read widgets, write aura fields, normalize, then rebuild
  -- or refresh the live region so the screen reflects the editor state.
  local aura = self:GetSelectedAura()
  local frame = self.configFrame
  if not aura or not frame then
    return
  end

  aura.name = frame.nameBox:GetText()
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
  aura.load.inCombat = frame.inCombatCheck:GetChecked() and true or false
  aura.load.requireTarget = frame.requireTargetCheck:GetChecked() and true or false
  aura.load.class = frame.classBox.__value
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
function TwAuras:BuildConfigFrame()
  -- The config frame is built once and reused. This avoids recreating many widget globals and
  -- keeps editor refreshes about swapping values rather than rebuilding the shell.
  if self.configFrame then
    return
  end

  local frame = CreateFrame("Frame", "TwAurasConfigFrame", UIParent)
  frame:SetWidth(820)
  frame:SetHeight(620)
  frame:SetPoint("CENTER", UIParent, "CENTER", 240, 0)
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
  frame.title:SetText("TwAuras Config")

  frame.leftPanel = CreateFrame("Frame", nil, frame)
  frame.leftPanel:SetWidth(190)
  frame.leftPanel:SetHeight(490)
  frame.leftPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -42)
  local leftBackground = frame.leftPanel:CreateTexture(nil, "BACKGROUND")
  leftBackground:SetAllPoints(frame.leftPanel)
  leftBackground:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  leftBackground:SetVertexColor(0, 0, 0, 0.25)
  MakeLabel(frame.leftPanel, "Auras", 6, -8)
  frame.auraListPanel = CreateFrame("Frame", nil, frame.leftPanel)
  frame.auraListPanel:SetWidth(170)
  frame.auraListPanel:SetHeight(318)
  frame.auraListPanel:SetPoint("TOPLEFT", frame.leftPanel, "TOPLEFT", 6, -28)
  frame.auraListScroll = CreateFrame("ScrollFrame", "TwAurasAuraListScroll", frame.auraListPanel, "UIPanelScrollFrameTemplate")
  frame.auraListScroll:SetWidth(168)
  frame.auraListScroll:SetHeight(318)
  frame.auraListScroll:SetPoint("TOPLEFT", frame.auraListPanel, "TOPLEFT", 0, 0)
  frame.auraListContent = CreateFrame("Frame", nil, frame.auraListScroll)
  frame.auraListContent:SetWidth(152)
  frame.auraListContent:SetHeight(1)
  frame.auraListScroll:SetScrollChild(frame.auraListContent)
  frame.auraRows = self:BuildAuraListRows(frame.auraListContent)
  frame.addButton = MakeButton(frame.leftPanel, "New", 80, 22, 6, -366, function() TwAuras:AddAura() end)
  frame.deleteButton = MakeButton(frame.leftPanel, "Delete", 80, 22, 92, -366, function() TwAuras:DeleteSelectedAura() end)
  frame.wizardButton = MakeButton(frame.leftPanel, "Wizard", 166, 22, 6, -394, function() TwAuras:OpenWizard() end)

  frame.rightPanel = CreateFrame("Frame", nil, frame)
  frame.rightPanel:SetWidth(580)
  frame.rightPanel:SetHeight(490)
  frame.rightPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 220, -42)
  local rightBackground = frame.rightPanel:CreateTexture(nil, "BACKGROUND")
  rightBackground:SetAllPoints(frame.rightPanel)
  rightBackground:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  rightBackground:SetVertexColor(0, 0, 0, 0.18)
  frame.editorTitle = frame.rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.editorTitle:SetPoint("TOPLEFT", frame.rightPanel, "TOPLEFT", 8, -8)
  frame.editorTitle:SetText("Edit")
  frame.summaryText = frame.rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.summaryText:SetPoint("TOPLEFT", frame.rightPanel, "TOPLEFT", 8, -24)
  frame.summaryText:SetWidth(540)
  frame.summaryText:SetJustifyH("LEFT")
  frame.summaryText:SetText("")

  frame.tabButtons = {}
  local tabNames = {"Trigger", "Display", "Conditions", "Load", "Position"}
  local i
  for i = 1, table.getn(tabNames) do
    local button = CreateFrame("Button", nil, frame.rightPanel, "UIPanelButtonTemplate")
    button:SetWidth(90)
    button:SetHeight(20)
    button:SetPoint("TOPLEFT", frame.rightPanel, "TOPLEFT", 8 + ((i - 1) * 94), -48)
    button:SetText(tabNames[i])
    button.__tab = SafeLower(tabNames[i])
    button:SetScript("OnClick", function() TwAuras:ShowConfigTab(this.__tab) end)
    frame.tabButtons[i] = button
  end

  frame.tabs = {
    trigger = CreateFrame("Frame", nil, frame.rightPanel),
    display = CreateFrame("Frame", nil, frame.rightPanel),
    conditions = CreateFrame("Frame", nil, frame.rightPanel),
    load = CreateFrame("Frame", nil, frame.rightPanel),
    position = CreateFrame("Frame", nil, frame.rightPanel),
  }
  local key, panel
  for key, panel in pairs(frame.tabs) do
    panel:SetWidth(554)
    panel:SetHeight(390)
    panel:SetPoint("TOPLEFT", frame.rightPanel, "TOPLEFT", 10, -76)
  end

  local triggerTab = frame.tabs.trigger
  local regionTypeList = JoinKeys(self:GetAvailableRegionTypes())
  MakeLabel(triggerTab, "Name", 8, -8)
  frame.nameBox = MakeEditBox(triggerTab, 180, 20, 108, -4)
  MakeLabel(triggerTab, "Logic", 300, -8)
  frame.triggerModeBox = MakeSelect(triggerTab, 90, 20, 352, -4, TRIGGER_MODE_OPTIONS, function()
    if TwAuras.configFrame and TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
      TwAuras:ApplyEditorToSelectedAura(true)
    end
  end)
  MakeLabel(triggerTab, "all, any, priority", 430, -8)

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
  frame.presetCombo = MakeButton(triggerTab, "Combo", 60, 20, 398, -340, function()
    local aura = TwAuras:GetSelectedAura()
    local trigger = TwAuras:GetSelectedTrigger(aura)
    if not aura or not trigger then return end
    trigger.type = "combo"; aura.regionType = "text"; TwAuras:EnsureSingleBlankTrigger(aura); TwAuras:RefreshConfigUI()
  end)
  frame.presetCL = MakeButton(triggerTab, "Log Timer", 72, 20, 464, -340, function()
    local aura = TwAuras:GetSelectedAura()
    local trigger = TwAuras:GetSelectedTrigger(aura)
    if not aura or not trigger then return end
    trigger.type = "combatlog"; trigger.combatLogEvent = "ANY"; trigger.duration = 10; aura.regionType = "icon"; TwAuras:EnsureSingleBlankTrigger(aura); TwAuras:RefreshConfigUI()
  end)

  local displayTab = frame.tabs.display
  MakeLabel(displayTab, "Region Type", 8, -8)
  frame.regionTypeBox = MakeSelect(displayTab, 120, 20, 108, -4, self:GetAvailableRegionTypes(), function()
    if TwAuras.configFrame and TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
      TwAuras:ApplyEditorToSelectedAura(true)
    end
    TwAuras:RefreshConfigUI()
  end)
  MakeLabel(displayTab, regionTypeList, 216, -8)
  frame.regionDescriptorTitle = displayTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.regionDescriptorTitle:SetPoint("TOPLEFT", displayTab, "TOPLEFT", 8, -38)
  frame.regionDescriptorHelp = displayTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.regionDescriptorHelp:SetPoint("TOPLEFT", displayTab, "TOPLEFT", 8, -54)
  frame.regionDescriptorHelp:SetWidth(544)
  frame.regionDescriptorHelp:SetJustifyH("LEFT")
  frame.regionFieldPanel = CreateFrame("Frame", nil, displayTab)
  frame.regionFieldPanel:SetWidth(544)
  frame.regionFieldPanel:SetHeight(260)
  frame.regionFieldPanel:SetPoint("TOPLEFT", displayTab, "TOPLEFT", 8, -74)
  frame.regionFieldScroll = CreateFrame("ScrollFrame", "TwAurasRegionFieldScroll", frame.regionFieldPanel, "UIPanelScrollFrameTemplate")
  frame.regionFieldScroll:SetWidth(540)
  frame.regionFieldScroll:SetHeight(260)
  frame.regionFieldScroll:SetPoint("TOPLEFT", frame.regionFieldPanel, "TOPLEFT", 0, 0)
  frame.regionFieldContent = CreateFrame("Frame", nil, frame.regionFieldScroll)
  frame.regionFieldContent:SetWidth(520)
  frame.regionFieldContent:SetHeight(1)
  frame.regionFieldScroll:SetScrollChild(frame.regionFieldContent)
  frame.iconPickerButton = MakeButton(displayTab, "Pick Icon", 90, 20, 462, -4, function() TwAuras:OpenIconPicker() end)
  frame.alphaSlider = MakeSlider(displayTab, "TwAurasAlphaSlider", 0, 1, 0.05, 8, -344, 220)
  frame.alphaSlider:SetScript("OnValueChanged", function()
    getglobal(this:GetName() .. "Text"):SetText("Alpha: " .. string.format("%.2f", this:GetValue()))
    if TwAuras.configFrame and TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
      TwAuras:ApplyEditorToSelectedAura(true)
    end
  end)
  MakeLabel(displayTab, "The fields below are generated from the selected region type.", 250, -346)

  local conditionsTab = frame.tabs.conditions
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
  MakeLabel(conditionsTab, "Active Sound", 200, -384)
  frame.soundActiveBox = MakeEditBox(conditionsTab, 150, 20, 300, -380)
  frame.soundActivePickButton = MakeButton(conditionsTab, "Pick", 46, 20, 456, -380, function()
    TwAuras:OpenSoundPicker("soundActiveBox", "Active Sound")
  end)
  MakeLabel(conditionsTab, "Repeat Seconds", 200, -412)
  frame.soundActiveIntervalBox = MakeEditBox(conditionsTab, 60, 20, 300, -408)
  MakeLabel(conditionsTab, "Stop Sound", 200, -440)
  frame.soundStopBox = MakeEditBox(conditionsTab, 150, 20, 300, -436)
  frame.soundStopPickButton = MakeButton(conditionsTab, "Pick", 46, 20, 456, -436, function()
    TwAuras:OpenSoundPicker("soundStopBox", "Stop Sound")
  end)
  MakeLabel(conditionsTab, "Use a sound file path or numeric sound id. Start and Stop fire once, Active repeats while the aura stays active.", 200, -466)

  local loadTab = frame.tabs.load
  frame.enabledCheck = CreateFrame("CheckButton", "TwAurasEnabledCheck", loadTab, "UICheckButtonTemplate")
  frame.enabledCheck:SetPoint("TOPLEFT", loadTab, "TOPLEFT", 8, -8)
  getglobal("TwAurasEnabledCheckText"):SetText("Enabled")
  frame.inCombatCheck = CreateFrame("CheckButton", "TwAurasInCombatCheck", loadTab, "UICheckButtonTemplate")
  frame.inCombatCheck:SetPoint("TOPLEFT", loadTab, "TOPLEFT", 8, -36)
  getglobal("TwAurasInCombatCheckText"):SetText("Only In Combat")
  frame.requireTargetCheck = CreateFrame("CheckButton", "TwAurasRequireTargetCheck", loadTab, "UICheckButtonTemplate")
  frame.requireTargetCheck:SetPoint("TOPLEFT", loadTab, "TOPLEFT", 8, -64)
  getglobal("TwAurasRequireTargetCheckText"):SetText("Require Target")
  MakeLabel(loadTab, "Class", 8, -104)
  frame.classBox = MakeSelect(loadTab, 120, 20, 108, -100, CLASS_OPTIONS, function()
    if TwAuras.configFrame and TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
      TwAuras:ApplyEditorToSelectedAura(true)
    end
  end)
  MakeLabel(loadTab, "ROGUE, DRUID, WARRIOR, etc. Leave blank for all", 216, -104)
  MakeLabel(loadTab, "Update Events", 8, -138)
  frame.updateEventsBox = MakeEditBox(loadTab, 280, 20, 108, -134)
  MakeLabel(loadTab, "world, combat, target, auras, power, combo, health", 8, -164)
  MakeLabel(loadTab, "Leave blank to infer updates from the aura's triggers and load conditions.", 8, -184)

  local positionTab = frame.tabs.position
  MakeLabel(positionTab, "Anchor Point", 8, -8)
  frame.pointBox = MakeSelect(positionTab, 120, 20, 108, -4, POINT_OPTIONS, function()
    if TwAuras.configFrame and TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
      TwAuras:ApplyEditorToSelectedAura(true)
    end
  end)
  MakeLabel(positionTab, "Relative Point", 230, -8)
  frame.relativePointBox = MakeSelect(positionTab, 120, 20, 340, -4, POINT_OPTIONS, function()
    if TwAuras.configFrame and TwAuras.configFrame.liveUpdateCheck and TwAuras.configFrame.liveUpdateCheck:GetChecked() then
      TwAuras:ApplyEditorToSelectedAura(true)
    end
  end)
  MakeLabel(positionTab, "X", 8, -38)
  frame.xBox = MakeEditBox(positionTab, 80, 20, 108, -34)
  MakeLabel(positionTab, "Y", 230, -38)
  frame.yBox = MakeEditBox(positionTab, 80, 20, 340, -34)
  frame.unlockHelp = positionTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.unlockHelp:SetPoint("TOPLEFT", positionTab, "TOPLEFT", 8, -76)
  frame.unlockHelp:SetWidth(520)
  frame.unlockHelp:SetJustifyH("LEFT")
  frame.unlockHelp:SetText("Use Unlock and drag regions on screen. Use the Debug button below to inspect recent combat log lines and copy the event name plus match text into combat log triggers.")

  frame.liveUpdateCheck = CreateFrame("CheckButton", "TwAurasLiveUpdateCheck", frame, "UICheckButtonTemplate")
  frame.liveUpdateCheck:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 216, 18)
  getglobal("TwAurasLiveUpdateCheckText"):SetText("Live Update")
  frame.applyButton = MakeButton(frame, "Apply", 90, 22, 370, -578, function() TwAuras:ApplyEditorToSelectedAura(false) end)
  frame.closeButton = MakeButton(frame, "Close", 90, 22, 470, -578, function() frame:Hide() end)
  frame.debugButton = MakeButton(frame, "Debug", 90, 22, 570, -578, function() TwAuras:DebugRecentCombatLog() end)
  frame.unlockButton = MakeButton(frame, "Unlock", 70, 22, 670, -578, function() TwAuras:SetUnlocked(true) end)
  frame.lockButton = MakeButton(frame, "Lock", 70, 22, 750, -578, function() TwAuras:SetUnlocked(false) end)

  self.configFrame = frame
  self:ShowConfigTab("trigger")
end

function TwAuras:ShowConfigTab(tabName)
  if not self.configFrame or not self.configFrame.tabs then
    return
  end
  local key, panel
  for key, panel in pairs(self.configFrame.tabs) do
    if key == tabName then panel:Show() else panel:Hide() end
  end
end

function TwAuras:ToggleConfig()
  -- Slash commands and any future menu entry points all flow through this one toggle.
  self:BuildConfigFrame()
  if self.configFrame:IsShown() then
    self.configFrame:Hide()
  else
    self.configFrame:Show()
    self:RefreshConfigUI()
  end
end
