-- TwAuras file version: 0.1.4
local stub = {}

local currentTime = 0
local unitData = {
  player = {
    name = "Player",
    exists = true,
    class = "DRUID",
    health = 1000,
    maxHealth = 1000,
    mana = 100,
    maxMana = 100,
    combat = false,
  },
  target = {
    name = "Target Dummy",
    exists = true,
    health = 1000,
    maxHealth = 1000,
    mana = 0,
    maxMana = 0,
    hostile = true,
  },
}

local comboPoints = 0
local messages = {}
local spellBook = {}
local spellCooldowns = {}
local inventoryCooldowns = {}
local inventoryTextures = {}
local bagContents = {}
local shapeshiftForms = {}
local zoneInfo = {
  zone = "Darnassus",
  subZone = "",
}
local actionSlots = {}
local weaponEnchantState = nil
local restingState = false
local mountedState = false
local stealthedState = false
local partyMembers = 0
local raidMembers = 0
local playedSounds = {}

local function ensureUnit(unit)
  unitData[unit] = unitData[unit] or {}
  return unitData[unit]
end

local function noop()
end

local function makeFrame()
  local frame = {
    scripts = {},
    events = {},
  }

  function frame:SetScript(name, fn)
    self.scripts[name] = fn
  end

  function frame:RegisterEvent(name)
    table.insert(self.events, name)
  end

  function frame:CreateTexture()
    return {
      SetAllPoints = noop,
      SetTexture = noop,
      SetVertexColor = noop,
      SetDesaturated = noop,
      SetWidth = noop,
      SetHeight = noop,
      SetPoint = noop,
      Show = noop,
      Hide = noop,
    }
  end

  function frame:CreateFontString()
    return {
      SetPoint = noop,
      SetJustifyH = noop,
      SetText = noop,
      SetWidth = noop,
      SetTextColor = noop,
      SetFont = noop,
      ClearAllPoints = noop,
      Show = noop,
      Hide = noop,
    }
  end

  function frame:SetWidth() end
  function frame:SetHeight() end
  function frame:SetPoint() end
  function frame:SetAllPoints() end
  function frame:SetBackdrop() end
  function frame:SetBackdropColor() end
  function frame:Hide() end
  function frame:Show() end
  function frame:SetMinMaxValues() end
  function frame:SetValue() end
  function frame:SetStatusBarTexture() end
  function frame:SetStatusBarColor() end
  function frame:SetAlpha() end
  function frame:SetMovable() end
  function frame:EnableMouse() end
  function frame:RegisterForDrag() end
  function frame:StartMoving() end
  function frame:StopMovingOrSizing() end
  function frame:SetCooldown() end
  function frame:GetPoint()
    return "CENTER", nil, "CENTER", 0, 0
  end
  function frame:IsShown()
    return true
  end

  return frame
end

function stub.install()
  -- The stub only implements the WoW APIs the current test suite actually touches.
  -- When new runtime features appear, extend this narrowly so the tests stay honest.
  _G.DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, message)
      table.insert(messages, message)
    end
  }

  _G.SlashCmdList = {}
  _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
  _G.BOOKTYPE_SPELL = "spell"
  _G.UIParent = {}
  _G.this = nil
  _G.event = nil
  _G.arg1 = nil

  _G.CreateFrame = function()
    return makeFrame()
  end

  _G.GetTime = function()
    return currentTime
  end

  _G.date = function()
    return "12:00:00"
  end

  _G.UnitClass = function(unit)
    local data = ensureUnit(unit)
    return data.class or "Druid", data.class or "DRUID"
  end

  _G.UnitName = function(unit)
    local data = ensureUnit(unit)
    return data.name
  end

  _G.UnitExists = function(unit)
    local data = ensureUnit(unit)
    return data.exists and true or false
  end

  _G.UnitCanAttack = function(_, unit)
    local data = ensureUnit(unit)
    return data.hostile and true or false
  end

  _G.UnitAffectingCombat = function(unit)
    local data = ensureUnit(unit)
    return data.combat and true or false
  end

  _G.UnitHealth = function(unit)
    local data = ensureUnit(unit)
    return data.health or 0
  end

  _G.UnitHealthMax = function(unit)
    local data = ensureUnit(unit)
    return data.maxHealth or 1
  end

  _G.UnitMana = function(unit)
    local data = ensureUnit(unit)
    return data.mana or 0
  end

  _G.UnitManaMax = function(unit)
    local data = ensureUnit(unit)
    return data.maxMana or 100
  end

  _G.GetComboPoints = function()
    return comboPoints
  end

  _G.UnitBuff = function()
    return nil
  end

  _G.UnitDebuff = function()
    return nil
  end

  _G.GetSpellName = function(index)
    local spell = spellBook[index]
    if spell then
      return spell.name, spell.rank
    end
    return nil
  end

  _G.GetSpellTexture = function(index)
    local spell = spellBook[index]
    return spell and spell.texture or nil
  end

  _G.GetSpellCooldown = function(index)
    local info = spellCooldowns[index]
    if info then
      return info.start or 0, info.duration or 0, info.enabled or 1
    end
    return 0, 0, 1
  end

  _G.GetInventoryItemTexture = function(_, slot)
    return inventoryTextures[slot]
  end

  _G.GetInventoryItemCooldown = function(_, slot)
    local info = inventoryCooldowns[slot]
    if info then
      return info.start or 0, info.duration or 0, info.enabled or 1
    end
    return 0, 0, 1
  end

  _G.GetWeaponEnchantInfo = function()
    if weaponEnchantState then
      return weaponEnchantState.hasMain, weaponEnchantState.mainExpiration, weaponEnchantState.mainCharges,
        weaponEnchantState.hasOff, weaponEnchantState.offExpiration, weaponEnchantState.offCharges
    end
    return nil, 0, 0, nil, 0, 0
  end

  _G.GetNumShapeshiftForms = function()
    return table.getn(shapeshiftForms)
  end

  _G.GetShapeshiftFormInfo = function(index)
    local form = shapeshiftForms[index]
    if not form then
      return nil
    end
    return form.icon, form.name, form.active and 1 or nil, form.castable and 1 or nil
  end

  _G.GetRealZoneText = function()
    return zoneInfo.zone
  end

  _G.GetZoneText = function()
    return zoneInfo.zone
  end

  _G.GetSubZoneText = function()
    return zoneInfo.subZone
  end

  _G.GetItemCount = function(itemName)
    local wanted = string.lower(itemName or "")
    local total = 0
    local bagIndex
    for bagIndex, bag in pairs(bagContents) do
      local slot
      for slot = 1, table.getn(bag) do
        if string.lower(bag[slot].name or "") == wanted then
          total = total + (bag[slot].count or 1)
        end
      end
    end
    return total
  end

  _G.GetContainerNumSlots = function(bag)
    local items = bagContents[bag] or {}
    return table.getn(items)
  end

  _G.GetContainerItemLink = function(bag, slot)
    local item = bagContents[bag] and bagContents[bag][slot] or nil
    if not item then
      return nil
    end
    return "|cffFFFFFF|Hitem:0:0:0:0|h[" .. item.name .. "]|h|r"
  end

  _G.GetContainerItemInfo = function(bag, slot)
    local item = bagContents[bag] and bagContents[bag][slot] or nil
    if not item then
      return nil
    end
    return nil, item.count or 1
  end

  _G.CheckInteractDistance = function(unit, distance)
    local data = ensureUnit(unit)
    if data.interactDistance and data.interactDistance[distance] ~= nil then
      return data.interactDistance[distance] and 1 or nil
    end
    return nil
  end

  _G.UnitIsUnit = function(unitA, unitB)
    return string.lower(UnitName(unitA) or "") == string.lower(UnitName(unitB) or "")
  end

  _G.IsResting = function()
    return restingState and true or false
  end

  _G.IsMounted = function()
    return mountedState and true or false
  end

  _G.IsStealthed = function()
    return stealthedState and true or false
  end

  _G.GetNumPartyMembers = function()
    return partyMembers
  end

  _G.GetNumRaidMembers = function()
    return raidMembers
  end

  _G.CooldownFrame_SetTimer = noop
  _G.PlaySound = function(soundId)
    table.insert(playedSounds, tostring(soundId))
  end
  _G.PlaySoundFile = function(soundPath)
    table.insert(playedSounds, tostring(soundPath))
  end

  _G.IsUsableAction = function(slot)
    local action = actionSlots[slot]
    if action then
      return action.usable and true or false, action.notEnoughMana and true or false
    end
    return false, false
  end

  _G.IsActionInRange = function(slot)
    local action = actionSlots[slot]
    if not action or action.inRange == nil then
      return nil
    end
    return action.inRange and 1 or 0
  end

  _G.GetActionCooldown = function(slot)
    local action = actionSlots[slot]
    if action then
      return action.start or 0, action.duration or 0, action.enabled or 1
    end
    return 0, 0, 1
  end

  _G.GetActionTexture = function(slot)
    local action = actionSlots[slot]
    return action and action.texture or nil
  end

  _G.getglobal = function()
    return {
      GetText = function()
        return nil
      end,
      SetText = noop,
    }
  end

  _G.GameTooltip = {
    SetOwner = noop,
    Hide = noop,
    SetUnitDebuff = noop,
    SetUnitBuff = noop,
  }
end

function stub.set_time(value)
  currentTime = value
end

function stub.advance_time(delta)
  currentTime = currentTime + delta
end

function stub.set_combo_points(value)
  comboPoints = value
end

function stub.set_unit(unit, values)
  local data = ensureUnit(unit)
  local key, value
  for key, value in pairs(values or {}) do
    data[key] = value
  end
end

function stub.get_messages()
  return messages
end

function stub.get_played_sounds()
  return playedSounds
end

function stub.clear_played_sounds()
  playedSounds = {}
end

function stub.set_spellbook(spells)
  spellBook = spells or {}
end

function stub.set_spell_cooldown(index, values)
  spellCooldowns[index] = values or {}
end

function stub.set_inventory_item(slot, values)
  inventoryTextures[slot] = values and values.texture or nil
  inventoryCooldowns[slot] = values or {}
end

function stub.set_bag_items(itemsByBag)
  bagContents = itemsByBag or {}
end

function stub.set_forms(forms)
  shapeshiftForms = forms or {}
end

function stub.set_zone(zoneName, subZoneName)
  zoneInfo.zone = zoneName or ""
  zoneInfo.subZone = subZoneName or ""
end

function stub.set_action(slot, values)
  actionSlots[slot] = values or {}
end

function stub.set_weapon_enchant(values)
  weaponEnchantState = values
end

function stub.set_player_state(values)
  restingState = values and values.resting and true or false
  mountedState = values and values.mounted and true or false
  stealthedState = values and values.stealthed and true or false
end

function stub.set_group_state(values)
  partyMembers = values and values.party or 0
  raidMembers = values and values.raid or 0
end

return stub
