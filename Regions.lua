-- TwAuras file version: 0.1.20
-- Region helpers handle positioning, coloring, and drag behavior shared by all displays.
-- Shared color application lets the same helper tint textures, bars, and font strings.
local function SetColor(region, color)
  if not region then
    return
  end
  if not color then
    region:SetTextColor(1, 1, 1, 1)
    return
  end
  if region.SetTextColor then
    region:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
  elseif region.SetVertexColor then
    region:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
  end
end


-- Region positions are always reapplied from saved config so unlock-and-drag stays persistent.
local function ApplyPoint(frame, pos)
  frame:ClearAllPoints()
  frame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or 0)
end

-- Strata is a saved display option, so every region type routes through one setter.
local function ApplyStrata(frame, display)
  if frame and frame.SetFrameStrata then
    frame:SetFrameStrata((display and display.strata) or "MEDIUM")
  end
end

local TEXT_TOKEN_HELP =
  "%name: tracked spell, aura, or proc name.\n" ..
  "%label: display label chosen by the trigger.\n" ..
  "%source: source from the first active combat-log trigger.\n" ..
  "%unit: active unit like player or target.\n" ..
  "%time: remaining time on the active timer.\n" ..
  "%value: current numeric value.\n" ..
  "%max: maximum value, or total timer duration.\n" ..
  "%percent: current percent value.\n" ..
  "%stacks: current aura stack count.\n" ..
  "%realhp: estimated or exact target HP.\n" ..
  "%realmaxhp: estimated or exact target max HP.\n" ..
  "%realhpdeficit: missing target HP.\n" ..
  "%realmana: estimated or exact target mana.\n" ..
  "%realmaxmana: estimated or exact target max mana.\n" ..
  "%realmanadeficit: missing target mana."

-- Icon hue tinting is generated from a single hue slider rather than a full color picker.
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

-- Icon tinting either uses the explicit hue override or the normal display color.
local function GetIconTint(display)
  if display and display.iconHueEnabled then
    local r, g, b = HueToRGB(display.iconHue or 0)
    return { r, g, b, (display.color and display.color[4]) or 1 }
  end
  return display and display.color or {1, 1, 1, 1}
end

-- Cooldown swipes are best-effort: use whichever cooldown API the current client exposes.
local function SetCooldownFrameTimer(frame, startTime, duration)
  if not frame then
    return false
  end
  if not duration or duration <= 0 then
    return false
  end
  if CooldownFrame_SetTimer then
    CooldownFrame_SetTimer(frame, startTime or 0, duration or 0, 1)
    return true
  elseif frame.SetCooldown then
    frame:SetCooldown(startTime or 0, duration or 0)
    return true
  end
  return false
end

-- Text anchors are constrained to the simplified set the config UI exposes.
local function GetAnchorPoint(anchor)
  local normalized = string.upper(anchor or "CENTER")
  if normalized == "TOP" or normalized == "BOTTOM" or normalized == "LEFT" or normalized == "RIGHT" or normalized == "CENTER" then
    return normalized
  end
  return "CENTER"
end

-- All text pieces clear and re-anchor each refresh so changing display anchors applies immediately.
local function ClearAndSetAnchor(fontString, frame, anchor, inset)
  local point = GetAnchorPoint(anchor)
  local distance = inset or 2
  fontString:ClearAllPoints()
  if point == "TOP" then
    fontString:SetPoint("BOTTOM", frame, "TOP", 0, distance)
  elseif point == "BOTTOM" then
    fontString:SetPoint("TOP", frame, "BOTTOM", 0, -distance)
  elseif point == "LEFT" then
    fontString:SetPoint("RIGHT", frame, "LEFT", -distance, 0)
  elseif point == "RIGHT" then
    fontString:SetPoint("LEFT", frame, "RIGHT", distance, 0)
  else
    fontString:SetPoint("CENTER", frame, "CENTER", 0, 0)
  end
end

-- Font settings come from the resolved display so conditions can override them cleanly later.
local function ApplyFont(fontString, aura)
  local display = aura.__state and aura.__state.display or aura.display
  local flags = display.fontOutline or ""
  if flags == "NONE" then
    flags = ""
  end
  fontString:SetFont(STANDARD_TEXT_FONT, display.fontSize or 12, flags)
end

-- Glow frames are created lazily because many auras never enable glow at all.
local function EnsureGlow(frame)
  if frame.glowFrame then
    return frame.glowFrame
  end
  frame.glowFrame = CreateFrame("Frame", nil, frame)
  frame.glowFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", -4, 4)
  frame.glowFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -4)
  frame.glowFrame:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  })
  frame.glowFrame:Hide()
  return frame.glowFrame
end

-- Glow application is a visual toggle only; it never changes the aura's logical state.
local function ApplyGlow(frame, display)
  local glowFrame = EnsureGlow(frame)
  if display and display.glow then
    local color = display.glowColor or {1, 0.82, 0, 1}
    if glowFrame.SetBackdropBorderColor then
      glowFrame:SetBackdropBorderColor(color[1] or 1, color[2] or 0.82, color[3] or 0, color[4] or 1)
    end
    glowFrame:Show()
  else
    glowFrame:Hide()
  end
end

-- Shared region helpers keep icon, bar, and text implementations visually consistent.
-- Dragging writes directly back into the aura position so unlocked moves persist.
local function MakeMovable(frame)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function()
    if TwAuras.db and TwAuras.db.unlocked then
      this:StartMoving()
    end
  end)
  frame:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    local point, _, relativePoint, x, y = this:GetPoint()
    local aura = this.__aura
    if aura and aura.position then
      aura.position.point = point
      aura.position.relativePoint = relativePoint
      aura.position.x = x
      aura.position.y = y
    end
  end)
end

-- Timer formatting stays intentionally compact for icon and bar overlays.
function TwAuras:FormatRemainingTime(expirationTime, now, formatStyle)
  if not expirationTime then
    return ""
  end
  local remain = expirationTime - now
  local minutes
  local seconds
  if remain < 0 then remain = 0 end
  if formatStyle == "mmss" then
    minutes = math.floor(remain / 60)
    seconds = math.floor(math.fmod(remain, 60))
    return string.format("%d:%02d", minutes, seconds)
  elseif formatStyle == "seconds" then
    return string.format("%.0f", remain)
  elseif formatStyle == "decimal" then
    return string.format("%.1f", remain)
  end
  if remain >= 60 then
    return string.format("%dm", math.floor(remain / 60))
  elseif remain >= 10 then
    return string.format("%.0f", remain)
  end
  return string.format("%.1f", remain)
end

local function ShouldUseLowTimeColor(display, state)
  return display
    and state
    and state.expirationTime
    and (display.lowTimeThreshold or 0) > 0
    and (state.remaining or 0) > 0
    and (state.remaining or 0) <= (display.lowTimeThreshold or 0)
end

local function GetTimerTextColor(display, state)
  if ShouldUseLowTimeColor(display, state) and display.lowTimeTextColorEnabled then
    return display.lowTimeTextColor or display.textColor
  end
  return display.textColor
end

local function GetBarColor(display, state)
  if ShouldUseLowTimeColor(display, state) and display.lowTimeBarColorEnabled then
    return display.lowTimeBarColor or display.color
  end
  return display.color or {1, 1, 1, 1}
end

local function GetBarIconSide(display)
  local fillDirection = display and display.fillDirection or "ltr"
  local iconPosition = display and display.barIconPosition or "front"
  local frontSide = fillDirection == "rtl" and "right" or "left"
  local backSide = frontSide == "left" and "right" or "left"
  if iconPosition == "back" then
    return backSide
  end
  return frontSide
end

local function ApplyBarIconPoint(icon, frame, display)
  if not icon or not frame then
    return
  end
  icon:ClearAllPoints()
  if GetBarIconSide(display) == "right" then
    icon:SetPoint("LEFT", frame, "RIGHT", 4, 0)
  else
    icon:SetPoint("RIGHT", frame, "LEFT", -4, 0)
  end
end

local function GetNamedFrame(name)
  if _G and _G[name] then
    return _G[name]
  end
  if getglobal then
    return getglobal(name)
  end
  return nil
end

-- Unitframe overlays attach to stock party and raid frames by known Vanilla/Turtle names.
local function GetFrameTargetEntries(scope)
  local entries = {}
  local normalized = string.lower(scope or "party")
  local i
  if normalized == "party" or normalized == "both" then
    for i = 1, 4 do
      table.insert(entries, {
        unit = "party" .. i,
        frame = GetNamedFrame("PartyMemberFrame" .. i),
      })
    end
  end
  if normalized == "raid" or normalized == "both" then
    for i = 1, 40 do
      table.insert(entries, {
        unit = "raid" .. i,
        frame = GetNamedFrame("RaidGroupButton" .. i),
      })
    end
  end
  return entries
end

-- Unitframe icon anchors are intentionally limited to the top edge to match healer-style overlays.
local function NormalizeFrameAnchor(anchor)
  local normalized = string.upper(anchor or "TOPLEFT")
  if normalized == "TOP" or normalized == "TOPLEFT" or normalized == "TOPRIGHT" then
    return normalized
  end
  return "TOPLEFT"
end

-- Overlay spacing is recalculated from active states each refresh instead of keeping persistent slots.
local function BuildUnitFrameIconLayoutEntries(owner, unit, anchor)
  local entries = {}
  local auras = owner.GetAuraList and owner:GetAuraList() or {}
  local i
  local j

  for i = 1, table.getn(auras) do
    local aura = auras[i]
    local display = aura and aura.display or nil
    local unitStates = aura and aura.__unitStates or nil
    if aura
      and aura.regionType == "unitframes"
      and display
      and display.overlayStyle ~= "glow"
      and NormalizeFrameAnchor(display.frameAnchor) == anchor
      and unitStates then
      for j = 1, table.getn(unitStates) do
        local state = unitStates[j]
        if state and state.active and state.unit == unit then
          table.insert(entries, {
            auraId = aura.id,
            stateIndex = j,
            width = (display.width or 16),
          })
        end
      end
    end
  end

  return entries
end

-- Offset calculation makes multiple unitframe icons spread away from the chosen anchor without overlap.
local function GetUnitFrameIconOffset(owner, auraObj, state, stateIndex)
  local anchor = NormalizeFrameAnchor(auraObj and auraObj.display and auraObj.display.frameAnchor)
  local entries = BuildUnitFrameIconLayoutEntries(owner, state and state.unit or nil, anchor)
  local gap = 2
  local i
  local running
  local totalWidth

  if table.getn(entries) <= 1 then
    if anchor == "TOPRIGHT" then
      return -2
    elseif anchor == "TOP" then
      return 0
    end
    return 2
  end

  if anchor == "TOPLEFT" then
    running = 2
    for i = 1, table.getn(entries) do
      if entries[i].auraId == auraObj.id and entries[i].stateIndex == stateIndex then
        return running
      end
      running = running + entries[i].width + gap
    end
    return 2
  elseif anchor == "TOPRIGHT" then
    running = -2
    for i = 1, table.getn(entries) do
      if entries[i].auraId == auraObj.id and entries[i].stateIndex == stateIndex then
        return running
      end
      running = running - (entries[i].width + gap)
    end
    return -2
  end

  totalWidth = 0
  for i = 1, table.getn(entries) do
    totalWidth = totalWidth + entries[i].width
  end
  totalWidth = totalWidth + (math.max(table.getn(entries) - 1, 0) * gap)
  running = -(totalWidth / 2)
  for i = 1, table.getn(entries) do
    local centerOffset = running + (entries[i].width / 2)
    if entries[i].auraId == auraObj.id and entries[i].stateIndex == stateIndex then
      return centerOffset
    end
    running = running + entries[i].width + gap
  end

  return 0
end

-- Icon regions are the default display type for buffs, debuffs, and timer-style auras.
function TwAuras:CreateIconRegion(aura)
  local frame = CreateFrame("Frame", nil, UIParent)
  frame.__aura = aura
  frame:SetWidth(aura.display.width or 36)
  frame:SetHeight(aura.display.height or 36)
  ApplyPoint(frame, aura.position)
  MakeMovable(frame)

  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetAllPoints(frame)
  frame.cooldownOverlay = frame:CreateTexture(nil, "OVERLAY")
  frame.cooldownOverlay:SetAllPoints(frame)
  frame.cooldownOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
  frame.cooldownOverlay:SetVertexColor(0, 0, 0, 0.45)
  frame.cooldownOverlay:Hide()
  frame.cooldown = CreateFrame("Cooldown", nil, frame)
  frame.cooldown:SetAllPoints(frame)
  frame.cooldown:Hide()

  frame.timeText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

  frame.stackText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.stackText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)

  frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

  -- ApplyState converts one normalized runtime state into concrete frame updates.
  function frame:ApplyState(auraObj, state)
    local display = state.display or auraObj.display
    self.__aura = auraObj
    self:SetWidth(display.width or 36)
    self:SetHeight(display.height or 36)
    ApplyPoint(self, auraObj.position)
    ApplyStrata(self, display)
    self:SetAlpha(display.alpha or 1)
    ApplyFont(self.timeText, auraObj)
    ApplyFont(self.stackText, auraObj)
    ApplyFont(self.label, auraObj)
    ClearAndSetAnchor(self.timeText, self, display.timerAnchor, 2)
    ClearAndSetAnchor(self.label, self, display.labelAnchor, 2)
    self.icon:SetTexture((display.iconPath ~= "" and display.iconPath) or state.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    if self.icon.SetDesaturated then
      self.icon:SetDesaturated(display.iconDesaturate and true or false)
    end
    SetColor(self.icon, GetIconTint(display))
    if display.showCooldownSwipe and state.expirationTime and state.duration and state.duration > 0 then
      local cooldownStart = state.startTime or (state.expirationTime - state.duration)
      if SetCooldownFrameTimer(self.cooldown, cooldownStart, state.duration) then
        self.cooldown:Show()
      else
        self.cooldown:Hide()
      end
    else
      self.cooldown:Hide()
    end
    if display.showCooldownOverlay and state.expirationTime and state.duration and state.duration > 0 and state.expirationTime > GetTime() then
      self.cooldownOverlay:Show()
    else
      self.cooldownOverlay:Hide()
    end
    ApplyGlow(self, display)

    if display.showStackText and state.stacks and state.stacks > 1 then
      self.stackText:SetText(state.stacks)
      SetColor(self.stackText, display.textColor)
      self.stackText:Show()
    else
      self.stackText:Hide()
    end

    if display.showLabelText then
      local labelText = display.labelText ~= "" and display.labelText or (display.label ~= "" and display.label or "%label")
      self.label:SetText(TwAuras:FormatDynamicDisplayText(labelText, auraObj, state, GetTime()))
      SetColor(self.label, display.textColor)
      self.label:Show()
    else
      self.label:Hide()
    end

    self:RefreshTimeText(auraObj, state, GetTime())
  end

  function frame:RefreshTimeText(auraObj, state, now)
    local display = state and state.display or auraObj.display
    if display.showTimerText and state and state.expirationTime then
      local timerText = display.timerText ~= "" and display.timerText or "%time"
      self.timeText:SetText(TwAuras:FormatDynamicDisplayText(timerText, auraObj, state, now))
      SetColor(self.timeText, GetTimerTextColor(display, state))
      self.timeText:Show()
    else
      self.timeText:Hide()
    end
  end

  function frame:SetInactive(auraObj)
    self:SetAlpha((auraObj.display.alpha or 1) * 0.35)
    self.icon:SetTexture((auraObj.display.iconPath ~= "" and auraObj.display.iconPath) or "Interface\\Icons\\INV_Misc_QuestionMark")
    if self.icon.SetDesaturated then
      self.icon:SetDesaturated(1)
    end
    SetColor(self.icon, {0.6, 0.6, 0.6, 1})
    self.timeText:Hide()
    self.stackText:Hide()
    self.cooldown:Hide()
    self.cooldownOverlay:Hide()
  end

  function frame:SetMovableState(flag)
    if flag then
      self:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
      self:SetBackdropColor(0, 1, 0, 0.2)
    else
      self:SetBackdrop(nil)
    end
  end

  return frame
end

-- Bar regions support both numeric resources and countdown-style timers.
function TwAuras:CreateBarRegion(aura)
  local frame = CreateFrame("StatusBar", nil, UIParent)
  frame.__aura = aura
  frame:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
  frame:SetMinMaxValues(0, 1)
  frame:SetValue(1)
  frame:SetWidth(aura.display.width or 180)
  frame:SetHeight(aura.display.height or 16)
  ApplyPoint(frame, aura.position)
  MakeMovable(frame)

  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetAllPoints(frame)
  frame.bg:SetTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")

  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetWidth(frame:GetHeight())
  frame.icon:SetHeight(frame:GetHeight())
  ApplyBarIconPoint(frame.icon, frame, aura.display)

  frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

  frame.valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

  -- Bars can represent either live resource values or countdown timers from the same state shape.
  function frame:ApplyState(auraObj, state)
    local display = state.display or auraObj.display
    self.__aura = auraObj
    self:SetWidth(display.width or 180)
    self:SetHeight(display.height or 16)
    self.icon:SetWidth(self:GetHeight())
    self.icon:SetHeight(self:GetHeight())
    ApplyBarIconPoint(self.icon, self, display)
    ApplyPoint(self, auraObj.position)
    ApplyStrata(self, display)
    self:SetAlpha(display.alpha or 1)
    ApplyFont(self.label, auraObj)
    ApplyFont(self.valueText, auraObj)
    ClearAndSetAnchor(self.label, self, display.labelAnchor, 4)
    ClearAndSetAnchor(self.valueText, self, display.valueAnchor, 4)

    local color = GetBarColor(display, state)
    self:SetStatusBarColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    SetColor(self.bg, display.bgColor or {0, 0, 0, 0.5})
    if self.SetReverseFill then
      self:SetReverseFill(display.fillDirection == "rtl")
    end
    ApplyGlow(self, display)

    if display.showIcon and ((display.iconPath ~= "" and display.iconPath) or state.icon) then
      self.icon:SetTexture((display.iconPath ~= "" and display.iconPath) or state.icon)
      if self.icon.SetDesaturated then
        self.icon:SetDesaturated(display.iconDesaturate and true or false)
      end
      SetColor(self.icon, GetIconTint(display))
      self.icon:Show()
    else
      self.icon:Hide()
    end

    local value = state.value or 0
    local maxValue = state.maxValue or 1
    if state.expirationTime and state.duration and state.duration > 0 then
      value = state.expirationTime - GetTime()
      if value < 0 then value = 0 end
      maxValue = state.duration
    end
    if maxValue <= 0 then maxValue = 1 end

    self:SetMinMaxValues(0, maxValue)
    self:SetValue(value)

    SetColor(self.label, display.textColor)
    SetColor(self.valueText, GetTimerTextColor(display, state))

    if display.showLabelText then
      local labelText = display.labelText ~= "" and display.labelText or (display.label ~= "" and display.label or "%label")
      self.label:SetText(TwAuras:FormatDynamicDisplayText(labelText, auraObj, state, GetTime()))
      self.label:Show()
    else
      self.label:Hide()
    end

    self:RefreshTimeText(auraObj, state, GetTime())
  end

  function frame:RefreshTimeText(auraObj, state, now)
    local display = state and state.display or auraObj.display
    if display.showTimerText and state and state.expirationTime then
      local timerText = display.timerText ~= "" and display.timerText or "%time"
      self.valueText:SetText(TwAuras:FormatDynamicDisplayText(timerText, auraObj, state, now))
      SetColor(self.valueText, GetTimerTextColor(display, state))
    elseif state then
      local valueText = display.valueText ~= "" and display.valueText or "%value/%max"
      valueText = TwAuras:FormatDynamicDisplayText(valueText, auraObj, state, now)
      self.valueText:SetText(valueText)
      SetColor(self.valueText, display.textColor)
    else
      self.valueText:SetText("")
    end
  end

  function frame:SetInactive(auraObj)
    self:SetAlpha((auraObj.display.alpha or 1) * 0.35)
  end

  function frame:SetMovableState(flag)
    if flag then
      self:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
      self:SetBackdropColor(0, 1, 0, 0.2)
    else
      self:SetBackdrop(nil)
    end
  end

  return frame
end

-- Text regions are intentionally lightweight for values like combo points.
function TwAuras:CreateTextRegion(aura)
  local frame = CreateFrame("Frame", nil, UIParent)
  frame.__aura = aura
  frame:SetWidth(aura.display.width or 180)
  frame:SetHeight(aura.display.height or 24)
  ApplyPoint(frame, aura.position)
  MakeMovable(frame)

  frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")

  function frame:ApplyState(auraObj, state)
    local display = state.display or auraObj.display
    self.__aura = auraObj
    self:SetWidth(display.width or 180)
    self:SetHeight(display.height or 24)
    ApplyPoint(self, auraObj.position)
    ApplyStrata(self, display)
    self:SetAlpha(display.alpha or 1)
    ApplyFont(self.text, auraObj)
    ClearAndSetAnchor(self.text, self, display.textAnchor, 0)
    SetColor(self.text, GetTimerTextColor(display, state))
    ApplyGlow(self, display)

    if display.showTimerText and state.expirationTime then
      local timerText = display.timerText ~= "" and display.timerText or "%label: %time"
      self.text:SetText(TwAuras:FormatDynamicDisplayText(timerText, auraObj, state, GetTime()))
    elseif state.value ~= nil then
      local valueText = display.valueText ~= "" and display.valueText or "%label: %value"
      self.text:SetText(TwAuras:FormatDynamicDisplayText(valueText, auraObj, state, GetTime()))
    else
      local labelText = display.labelText ~= "" and display.labelText or (display.label ~= "" and display.label or "%label")
      self.text:SetText(TwAuras:FormatDynamicDisplayText(labelText, auraObj, state, GetTime()))
    end
  end

  function frame:RefreshTimeText(auraObj, state, now)
    local display = state and state.display or auraObj.display
    if display.showTimerText and state and state.expirationTime then
      local timerText = display.timerText ~= "" and display.timerText or "%label: %time"
      self.text:SetText(TwAuras:FormatDynamicDisplayText(timerText, auraObj, state, now))
      SetColor(self.text, GetTimerTextColor(display, state))
    end
  end

  function frame:SetMovableState(flag)
    if flag then
      self:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
      self:SetBackdropColor(0, 1, 0, 0.2)
    else
      self:SetBackdrop(nil)
    end
  end

  return frame
end

function TwAuras:CreateUnitFrameRegion(aura)
  local frame = CreateFrame("Frame", nil, UIParent)
  frame.__aura = aura
  frame.overlays = {}
  frame:SetWidth(1)
  frame:SetHeight(1)

  function frame:GetOverlay(index)
    if self.overlays[index] then
      return self.overlays[index]
    end
    local overlay = CreateFrame("Frame", nil, self)
    overlay.icon = overlay:CreateTexture(nil, "OVERLAY")
    overlay.icon:SetAllPoints(overlay)
    overlay:SetBackdrop({
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    overlay:Hide()
    self.overlays[index] = overlay
    return overlay
  end

  function frame:HideOverlays()
    local i
    for i = 1, table.getn(self.overlays) do
      local overlay = self.overlays[i]
      overlay.icon:Hide()
      overlay:Hide()
    end
  end

  function frame:ApplyUnitStates(auraObj, unitStates)
    local display = auraObj.display or {}
    local targets = GetFrameTargetEntries(display.frameScope)
    local targetByUnit = {}
    local i
    for i = 1, table.getn(targets) do
      if targets[i].frame then
        targetByUnit[targets[i].unit] = targets[i].frame
      end
    end

    self:HideOverlays()

    for i = 1, table.getn(unitStates or {}) do
      local state = unitStates[i]
      local targetFrame = targetByUnit[state.unit]
      if state and targetFrame then
        local overlay = self:GetOverlay(i)
        ApplyStrata(overlay, display)
        overlay:SetAlpha(display.alpha or 1)
        overlay:ClearAllPoints()
        if display.overlayStyle == "glow" then
          overlay:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", -2, 2)
          overlay:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOMRIGHT", 2, -2)
          overlay.icon:Hide()
          if overlay.SetBackdropBorderColor then
            local color = display.glowColor or display.color or {1, 0.2, 0.2, 1}
            overlay:SetBackdropBorderColor(color[1] or 1, color[2] or 0.2, color[3] or 0.2, color[4] or 1)
          end
        else
          local iconX = GetUnitFrameIconOffset(TwAuras, auraObj, state, i)
          overlay:SetWidth(display.width or 16)
          overlay:SetHeight(display.height or 16)
          overlay:SetPoint(NormalizeFrameAnchor(display.frameAnchor), targetFrame, NormalizeFrameAnchor(display.frameAnchor), iconX, display.frameYOffset or 0)
          overlay:SetBackdrop(nil)
          overlay.icon:SetTexture((display.iconPath ~= "" and display.iconPath) or state.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
          if overlay.icon.SetDesaturated then
            overlay.icon:SetDesaturated(display.iconDesaturate and true or false)
          end
          SetColor(overlay.icon, GetIconTint(display))
          overlay.icon:Show()
        end
        overlay:Show()
      end
    end
  end

  function frame:SetInactive()
    self:HideOverlays()
  end

  function frame:SetMovableState()
  end

  return frame
end

function TwAuras:CreateRegion(aura)
  local regionType = self:GetRegionType(aura.regionType)
  if regionType and regionType.create then
    return regionType.create(self, aura)
  end
  regionType = self:GetRegionType("icon")
  return regionType and regionType.create(self, aura) or nil
end

-- Region descriptors define both the runtime constructor and the editor fields for that type.
TwAuras:RegisterRegionType("icon", {
  displayName = "Icon",
  fields = {
    { key = "label", label = "Label", type = "text", width = 180, default = "" },
    { key = "iconPath", label = "Icon Path", type = "text", width = 250, default = "", help = "Leave blank to use trigger icon" },
    { key = "width", label = "Width", type = "number", width = 60, default = 36 },
    { key = "height", label = "Height", type = "number", width = 60, default = 36 },
    { key = "strata", label = "Layer", type = "select", width = 100, default = "MEDIUM", options = {"BACKGROUND", "LOW", "MEDIUM", "HIGH"} },
    { key = "fontSize", label = "Font Size", type = "number", width = 50, default = 12 },
    { key = "fontOutline", label = "Outline", type = "select", width = 100, default = "", options = {
      { value = "", label = "None" }, "OUTLINE", "THICKOUTLINE"
    } },
    { key = "labelAnchor", label = "Label Anchor", type = "select", width = 90, default = "BOTTOM", options = {"TOP", "BOTTOM", "LEFT", "RIGHT", "CENTER"} },
    { key = "timerAnchor", label = "Timer Anchor", type = "select", width = 90, default = "TOP", options = {"TOP", "BOTTOM", "LEFT", "RIGHT", "CENTER"} },
    { key = "textAnchor", label = "Text Anchor", type = "select", width = 90, default = "CENTER", options = {"TOP", "BOTTOM", "LEFT", "RIGHT", "CENTER"} },
    { key = "labelText", label = "Label Text", type = "text", width = 180, default = "%name", hoverText = TEXT_TOKEN_HELP },
    { key = "timerText", label = "Timer Text", type = "text", width = 180, default = "%time", hoverText = TEXT_TOKEN_HELP },
    { key = "timerFormat", label = "Timer Format", type = "select", width = 100, default = "smart", options = {
      { value = "smart", label = "Smart" }, { value = "mmss", label = "MM:SS" }, { value = "seconds", label = "Seconds" }, { value = "decimal", label = "Decimal" }
    } },
    { key = "showLabelText", label = "Show Label", type = "bool", default = false },
    { key = "showTimerText", label = "Show Timer Text", type = "bool", default = true },
    { key = "showStackText", label = "Show Stacks", type = "bool", default = true },
    { key = "showCooldownSwipe", label = "Show Cooldown Swipe", type = "bool", default = false },
    { key = "showCooldownOverlay", label = "Show Cooldown Overlay", type = "bool", default = false },
    { key = "desaturateInactive", label = "Desaturate Inactive", type = "bool", default = false },
    { key = "iconDesaturate", label = "Desaturate Icon", type = "bool", default = false },
    { key = "iconHueEnabled", label = "Enable Icon Hue", type = "bool", default = false },
    { key = "iconHue", label = "Icon Hue", type = "hue", width = 126, default = 0, hoverText = "Choose a hue tint for icon textures." },
    { key = "color", label = "Main RGBA", type = "color4", default = {1, 1, 1, 1} },
    { key = "textColor", label = "Text RGBA", type = "color4", default = {1, 1, 1, 1} },
    { key = "lowTimeThreshold", label = "Low Time Sec", type = "number", width = 60, default = 0 },
    { key = "lowTimeTextColorEnabled", label = "Low Time Text Color", type = "bool", default = false },
    { key = "lowTimeTextColor", label = "Low Text RGBA", type = "color4", default = {1, 0.2, 0.2, 1} },
  },
  create = function(self, aura)
    return self:CreateIconRegion(aura)
  end,
})

TwAuras:RegisterRegionType("bar", {
  displayName = "Bar",
  fields = {
    { key = "label", label = "Label", type = "text", width = 180, default = "" },
    { key = "iconPath", label = "Icon Path", type = "text", width = 250, default = "", help = "Leave blank to use trigger icon" },
    { key = "width", label = "Width", type = "number", width = 60, default = 180 },
    { key = "height", label = "Height", type = "number", width = 60, default = 18 },
    { key = "strata", label = "Layer", type = "select", width = 100, default = "MEDIUM", options = {"BACKGROUND", "LOW", "MEDIUM", "HIGH"} },
    { key = "fontSize", label = "Font Size", type = "number", width = 50, default = 12 },
    { key = "fontOutline", label = "Outline", type = "select", width = 100, default = "", options = {
      { value = "", label = "None" }, "OUTLINE", "THICKOUTLINE"
    } },
    { key = "labelAnchor", label = "Label Anchor", type = "select", width = 90, default = "LEFT", options = {"TOP", "BOTTOM", "LEFT", "RIGHT", "CENTER"} },
    { key = "valueAnchor", label = "Value Anchor", type = "select", width = 90, default = "RIGHT", options = {"TOP", "BOTTOM", "LEFT", "RIGHT", "CENTER"} },
    { key = "labelText", label = "Label Text", type = "text", width = 180, default = "%label", hoverText = TEXT_TOKEN_HELP },
    { key = "timerText", label = "Timer Text", type = "text", width = 180, default = "%time", hoverText = TEXT_TOKEN_HELP },
    { key = "valueText", label = "Value Text", type = "text", width = 180, default = "%value/%max", hoverText = TEXT_TOKEN_HELP },
    { key = "timerFormat", label = "Timer Format", type = "select", width = 100, default = "smart", options = {
      { value = "smart", label = "Smart" }, { value = "mmss", label = "MM:SS" }, { value = "seconds", label = "Seconds" }, { value = "decimal", label = "Decimal" }
    } },
    { key = "showIcon", label = "Show Icon", type = "bool", default = false },
    { key = "barIconPosition", label = "Icon Position", type = "select", width = 110, default = "front", options = {
      { value = "front", label = "Front" }, { value = "back", label = "Back" }
    } },
    { key = "showLabelText", label = "Show Label", type = "bool", default = true },
    { key = "showTimerText", label = "Show Timer Text", type = "bool", default = false },
    { key = "fillDirection", label = "Fill Direction", type = "select", width = 110, default = "ltr", options = {
      { value = "ltr", label = "Left To Right" }, { value = "rtl", label = "Right To Left" }
    } },
    { key = "iconDesaturate", label = "Desaturate Icon", type = "bool", default = false },
    { key = "iconHueEnabled", label = "Enable Icon Hue", type = "bool", default = false },
    { key = "iconHue", label = "Icon Hue", type = "hue", width = 126, default = 0, hoverText = "Choose a hue tint for bar icons." },
    { key = "color", label = "Main RGBA", type = "color4", default = {1, 1, 1, 1} },
    { key = "bgColor", label = "BG RGBA", type = "color4", default = {0, 0, 0, 0.5} },
    { key = "textColor", label = "Text RGBA", type = "color4", default = {1, 1, 1, 1} },
    { key = "lowTimeThreshold", label = "Low Time Sec", type = "number", width = 60, default = 0 },
    { key = "lowTimeTextColorEnabled", label = "Low Time Text Color", type = "bool", default = false },
    { key = "lowTimeTextColor", label = "Low Text RGBA", type = "color4", default = {1, 0.2, 0.2, 1} },
    { key = "lowTimeBarColorEnabled", label = "Low Time Bar Color", type = "bool", default = false },
    { key = "lowTimeBarColor", label = "Low Bar RGBA", type = "color4", default = {1, 0.2, 0.2, 1} },
  },
  create = function(self, aura)
    return self:CreateBarRegion(aura)
  end,
})

TwAuras:RegisterRegionType("text", {
  displayName = "Text",
  fields = {
    { key = "label", label = "Label", type = "text", width = 180, default = "" },
    { key = "width", label = "Width", type = "number", width = 60, default = 180 },
    { key = "height", label = "Height", type = "number", width = 60, default = 24 },
    { key = "strata", label = "Layer", type = "select", width = 100, default = "MEDIUM", options = {"BACKGROUND", "LOW", "MEDIUM", "HIGH"} },
    { key = "fontSize", label = "Font Size", type = "number", width = 50, default = 12 },
    { key = "fontOutline", label = "Outline", type = "select", width = 100, default = "", options = {
      { value = "", label = "None" }, "OUTLINE", "THICKOUTLINE"
    } },
    { key = "textAnchor", label = "Text Anchor", type = "select", width = 90, default = "CENTER", options = {"TOP", "BOTTOM", "LEFT", "RIGHT", "CENTER"} },
    { key = "labelText", label = "Label Text", type = "text", width = 180, default = "%name", hoverText = TEXT_TOKEN_HELP },
    { key = "timerText", label = "Timer Text", type = "text", width = 180, default = "%label: %time", hoverText = TEXT_TOKEN_HELP },
    { key = "valueText", label = "Value Text", type = "text", width = 180, default = "%label: %value", hoverText = TEXT_TOKEN_HELP },
    { key = "timerFormat", label = "Timer Format", type = "select", width = 100, default = "smart", options = {
      { value = "smart", label = "Smart" }, { value = "mmss", label = "MM:SS" }, { value = "seconds", label = "Seconds" }, { value = "decimal", label = "Decimal" }
    } },
    { key = "showTimerText", label = "Show Timer Text", type = "bool", default = true },
    { key = "textColor", label = "Text RGBA", type = "color4", default = {1, 1, 1, 1} },
    { key = "lowTimeThreshold", label = "Low Time Sec", type = "number", width = 60, default = 0 },
    { key = "lowTimeTextColorEnabled", label = "Low Time Text Color", type = "bool", default = false },
    { key = "lowTimeTextColor", label = "Low Text RGBA", type = "color4", default = {1, 0.2, 0.2, 1} },
  },
  create = function(self, aura)
    return self:CreateTextRegion(aura)
  end,
})

TwAuras:RegisterRegionType("unitframes", {
  displayName = "Party / Raid Frames",
  fields = {
    { key = "label", label = "Label", type = "text", width = 180, default = "" },
    { key = "overlayStyle", label = "Overlay Style", type = "select", width = 110, default = "icon", options = {
      { value = "icon", label = "Icon" }, { value = "glow", label = "Glow" }
    } },
    { key = "frameScope", label = "Frame Scope", type = "select", width = 100, default = "party", options = {
      { value = "party", label = "Party" }, { value = "raid", label = "Raid" }, { value = "both", label = "Both" }
    } },
    { key = "iconPath", label = "Icon Path", type = "text", width = 250, default = "", help = "Leave blank to use trigger icon" },
    { key = "width", label = "Icon Width", type = "number", width = 60, default = 16 },
    { key = "height", label = "Icon Height", type = "number", width = 60, default = 16 },
    { key = "frameAnchor", label = "Frame Anchor", type = "select", width = 100, default = "TOPLEFT", options = {"TOPLEFT", "TOP", "TOPRIGHT"} },
    { key = "frameYOffset", label = "Y Offset", type = "number", width = 60, default = 0 },
    { key = "strata", label = "Layer", type = "select", width = 100, default = "HIGH", options = {"BACKGROUND", "LOW", "MEDIUM", "HIGH"} },
    { key = "iconDesaturate", label = "Desaturate Icon", type = "bool", default = false },
    { key = "iconHueEnabled", label = "Enable Icon Hue", type = "bool", default = false },
    { key = "iconHue", label = "Icon Hue", type = "hue", width = 126, default = 0, hoverText = "Choose a hue tint for frame overlay icons." },
    { key = "color", label = "Icon RGBA", type = "color4", default = {1, 1, 1, 1} },
    { key = "glowColor", label = "Glow RGBA", type = "color4", default = {1, 0.2, 0.2, 1} },
  },
  create = function(self, aura)
    return self:CreateUnitFrameRegion(aura)
  end,
})

