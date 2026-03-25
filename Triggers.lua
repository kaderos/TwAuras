-- TwAuras file version: 0.1.24
-- Trigger evaluation helpers for aura scans, resource checks, and combat log timers.
local function CompareValue(value, op, threshold)
  if op == "<" then return value < threshold end
  if op == "<=" then return value <= threshold end
  if op == ">" then return value > threshold end
  if op == ">=" then return value >= threshold end
  if op == "=" then return value == threshold end
  return false
end

local function SafeLower(value)
  if not value then
    return ""
  end
  return string.lower(value)
end

-- Known player-applied debuffs let target timers use saved application times instead of guessed durations.
-- The durations here are Vanilla-focused approximations and can be extended over time.
local TRACKED_DEBUFF_CATALOG = {
  ["bash"] = { name = "Bash", class = "DRUID", duration = 4 },
  ["concussive shot"] = { name = "Concussive Shot", class = "HUNTER", duration = 4 },
  ["cone of cold"] = { name = "Cone of Cold", class = "MAGE", duration = 8 },
  ["concussion blow"] = { name = "Concussion Blow", class = "WARRIOR", duration = 5 },
  ["corruption"] = { name = "Corruption", class = "WARLOCK", duration = 18 },
  ["counterspell"] = { name = "Counterspell", class = "MAGE", duration = 4 },
  ["crippling poison"] = { name = "Crippling Poison", class = "ROGUE", duration = 12 },
  ["curse of agony"] = { name = "Curse of Agony", class = "WARLOCK", duration = 24 },
  ["curse of doom"] = { name = "Curse of Doom", class = "WARLOCK", duration = 60 },
  ["curse of elements"] = { name = "Curse of Elements", class = "WARLOCK", duration = 300 },
  ["curse of recklessness"] = { name = "Curse of Recklessness", class = "WARLOCK", duration = 120 },
  ["curse of shadow"] = { name = "Curse of Shadow", class = "WARLOCK", duration = 300 },
  ["curse of tongues"] = { name = "Curse of Tongues", class = "WARLOCK", duration = 30 },
  ["curse of weakness"] = { name = "Curse of Weakness", class = "WARLOCK", duration = 120 },
  ["deadly poison"] = { name = "Deadly Poison", class = "ROGUE", duration = 12 },
  ["death coil"] = { name = "Death Coil", class = "WARLOCK", duration = 3 },
  ["deep wounds"] = { name = "Deep Wounds", class = "WARRIOR", duration = 12 },
  ["demoralizing roar"] = { name = "Demoralizing Roar", class = "DRUID", duration = 30 },
  ["demoralizing shout"] = { name = "Demoralizing Shout", class = "WARRIOR", duration = 30 },
  ["devouring plague"] = { name = "Devouring Plague", class = "PRIEST", duration = 24 },
  ["earth shock"] = { name = "Earth Shock", class = "SHAMAN", duration = 2 },
  ["entangling roots"] = { name = "Entangling Roots", class = "DRUID", duration = 12 },
  ["expose armor"] = { name = "Expose Armor", class = "ROGUE", duration = 30 },
  ["faerie fire"] = { name = "Faerie Fire", class = "DRUID", duration = 40 },
  ["fear"] = { name = "Fear", class = "WARLOCK", duration = 20 },
  ["fireball"] = { name = "Fireball", class = "MAGE", duration = 8 },
  ["flame shock"] = { name = "Flame Shock", class = "SHAMAN", duration = 12 },
  ["frost nova"] = { name = "Frost Nova", class = "MAGE", duration = 8 },
  ["frost shock"] = { name = "Frost Shock", class = "SHAMAN", duration = 8 },
  ["frostbolt"] = { name = "Frostbolt", class = "MAGE", duration = 5 },
  ["garrote"] = { name = "Garrote", class = "ROGUE", duration = 18 },
  ["gouge"] = { name = "Gouge", class = "ROGUE", duration = 4 },
  ["hamstring"] = { name = "Hamstring", class = "WARRIOR", duration = 15 },
  ["hammer of justice"] = { name = "Hammer of Justice", class = "PALADIN", duration = 6 },
  ["hex of weakness"] = { name = "Hex of Weakness", class = "PRIEST", duration = 120 },
  ["hunter's mark"] = { name = "Hunter's Mark", class = "HUNTER", duration = 120 },
  ["immolate"] = { name = "Immolate", class = "WARLOCK", duration = 15 },
  ["insect swarm"] = { name = "Insect Swarm", class = "DRUID", duration = 12 },
  ["intimidating shout"] = { name = "Intimidating Shout", class = "WARRIOR", duration = 8 },
  ["judgement of justice"] = { name = "Judgement of Justice", class = "PALADIN", duration = 10 },
  ["judgement of light"] = { name = "Judgement of Light", class = "PALADIN", duration = 10 },
  ["judgement of wisdom"] = { name = "Judgement of Wisdom", class = "PALADIN", duration = 10 },
  ["judgement of the crusader"] = { name = "Judgement of the Crusader", class = "PALADIN", duration = 10 },
  ["kidney shot"] = { name = "Kidney Shot", class = "ROGUE", comboDurations = {1, 2, 3, 4, 5} },
  ["mind-numbing poison"] = { name = "Mind-numbing Poison", class = "ROGUE", duration = 14 },
  ["mocking blow"] = { name = "Mocking Blow", class = "WARRIOR", duration = 6 },
  ["moonfire"] = { name = "Moonfire", class = "DRUID", duration = 12 },
  ["piercing howl"] = { name = "Piercing Howl", class = "WARRIOR", duration = 6 },
  ["polymorph"] = { name = "Polymorph", class = "MAGE", duration = 20 },
  ["psychic scream"] = { name = "Psychic Scream", class = "PRIEST", duration = 8 },
  ["pounce"] = { name = "Pounce", class = "DRUID", duration = 2 },
  ["pounce bleed"] = { name = "Pounce Bleed", class = "DRUID", duration = 18 },
  ["rake"] = { name = "Rake", class = "DRUID", duration = 9 },
  ["rend"] = { name = "Rend", class = "WARRIOR", duration = 15 },
  ["repentance"] = { name = "Repentance", class = "PALADIN", duration = 6 },
  ["rip"] = { name = "Rip", class = "DRUID", comboDurations = {12, 16, 20, 24, 28} },
  ["rupture"] = { name = "Rupture", class = "ROGUE", comboDurations = {8, 10, 12, 14, 16} },
  ["sap"] = { name = "Sap", class = "ROGUE", duration = 25 },
  ["scorpid sting"] = { name = "Scorpid Sting", class = "HUNTER", duration = 20 },
  ["serpent sting"] = { name = "Serpent Sting", class = "HUNTER", duration = 15 },
  ["shadow word: pain"] = { name = "Shadow Word: Pain", class = "PRIEST", duration = 18 },
  ["silence"] = { name = "Silence", class = "PRIEST", duration = 5 },
  ["siphon life"] = { name = "Siphon Life", class = "WARLOCK", duration = 30 },
  ["stormstrike"] = { name = "Stormstrike", class = "SHAMAN", duration = 12 },
  ["sunder armor"] = { name = "Sunder Armor", class = "WARRIOR", duration = 30 },
  ["taunt"] = { name = "Taunt", class = "WARRIOR", duration = 3 },
  ["thunder clap"] = { name = "Thunder Clap", class = "WARRIOR", duration = 30 },
  ["viper sting"] = { name = "Viper Sting", class = "HUNTER", duration = 8 },
  ["wing clip"] = { name = "Wing Clip", class = "HUNTER", duration = 10 },
  ["wound poison"] = { name = "Wound Poison", class = "ROGUE", duration = 15 },
  ["wyvern sting"] = { name = "Wyvern Sting", class = "HUNTER", duration = 12 },
}

-- Triggers.lua owns both runtime trigger handlers and the metadata that drives the editor UI.
-- The goal is that adding a trigger type means defining behavior once and letting the config
-- window render its fields automatically from the descriptor.
function TwAuras:GetTrackedDebuffDefinition(name)
  return TRACKED_DEBUFF_CATALOG[SafeLower(name)]
end

function TwAuras:GetTrackedDebuffKey(targetName, debuffName)
  return SafeLower(targetName) .. "::" .. SafeLower(debuffName)
end

function TwAuras:GetTrackedDebuff(unit, debuffName)
  local unitName = unit and UnitName(unit) or nil
  local key
  local entry
  if not unitName or unitName == "" or not debuffName or debuffName == "" then
    return nil
  end

  key = self:GetTrackedDebuffKey(unitName, debuffName)
  entry = self.runtime.trackedDebuffs[key]
  if not entry then
    return nil
  end
  if entry.expirationTime and entry.expirationTime > GetTime() then
    return entry
  end

  self.runtime.trackedDebuffs[key] = nil
  return nil
end

function TwAuras:GetTrackedDebuffDuration(definition, comboPoints)
  local points = comboPoints or 0
  if definition and definition.comboDurations then
    if points < 1 then
      points = self.runtime.lastPlayerComboPoints or 0
    end
    if points < 1 then
      points = 1
    elseif points > table.getn(definition.comboDurations) then
      points = table.getn(definition.comboDurations)
    end
    return definition.comboDurations[points], points
  end
  return definition and definition.duration or 0, points
end

function TwAuras:GetPendingDebuffCast(spellName, targetName)
  local key = SafeLower(spellName)
  local pending = self.runtime.pendingDebuffCasts[key]
  if not pending then
    return nil
  end
  if (GetTime() - (pending.time or 0)) > 4 then
    self.runtime.pendingDebuffCasts[key] = nil
    return nil
  end
  if targetName and pending.targetName and pending.targetName ~= SafeLower(targetName) then
    return nil
  end
  return pending
end

function TwAuras:SnapshotPendingDebuffCast(spellName)
  local definition = self:GetTrackedDebuffDefinition(spellName)
  local targetName = UnitName("target")
  if not definition then
    return
  end
  self.runtime.pendingDebuffCasts[SafeLower(spellName)] = {
    spellName = definition.name,
    targetName = SafeLower(targetName),
    comboPoints = self.runtime.lastPlayerComboPoints or 0,
    time = GetTime(),
  }
end

function TwAuras:RefreshTrackedDebuffAuras(debuffName)
  local wanted = SafeLower(debuffName)
  local auras = self:GetAuraList()
  local i
  local j
  for i = 1, table.getn(auras) do
    local aura = auras[i]
    for j = 1, table.getn(aura.triggers or {}) do
      local trigger = aura.triggers[j]
      if trigger
        and trigger.type == "debuff"
        and SafeLower(trigger.unit or "target") == "target"
        and SafeLower(trigger.auraName) == wanted then
        self:RefreshAura(aura)
        break
      end
    end
  end
end

function TwAuras:StartTrackedDebuff(targetName, spellName, fromTick)
  local definition = self:GetTrackedDebuffDefinition(spellName)
  local pending = self:GetPendingDebuffCast(spellName, targetName)
  local duration
  local comboPoints
  local key
  local entry
  if not definition or not targetName or targetName == "" then
    return nil
  end

  key = self:GetTrackedDebuffKey(targetName, definition.name)
  entry = self.runtime.trackedDebuffs[key]
  if fromTick and entry and entry.expirationTime and entry.expirationTime > GetTime() then
    return entry
  end

  duration, comboPoints = self:GetTrackedDebuffDuration(definition, pending and pending.comboPoints or nil)
  if duration <= 0 then
    return nil
  end

  entry = {
    name = definition.name,
    targetName = SafeLower(targetName),
    comboPoints = comboPoints or 0,
    startTime = GetTime(),
    duration = duration,
    expirationTime = GetTime() + duration,
  }
  self.runtime.trackedDebuffs[key] = entry
  self.runtime.pendingDebuffCasts[SafeLower(spellName)] = nil
  self:RefreshTrackedDebuffAuras(definition.name)
  return entry
end

function TwAuras:ClearTrackedDebuff(targetName, spellName)
  local definition = self:GetTrackedDebuffDefinition(spellName)
  local key
  if not definition or not targetName or targetName == "" then
    return
  end
  key = self:GetTrackedDebuffKey(targetName, definition.name)
  if self.runtime.trackedDebuffs[key] then
    self.runtime.trackedDebuffs[key] = nil
    self:RefreshTrackedDebuffAuras(definition.name)
  end
end

function TwAuras:TrackPlayerDebuffsFromCombatLog(message)
  -- Target debuff timers are reconstructed from combat-log text because Vanilla/Turtle does not
  -- reliably expose exact hostile target aura durations the way modern WoW does.
  local lowerMessage = SafeLower(message)
  local castStartSpell = string.match(lowerMessage, "^you begin to cast (.+)%.?$")
    or string.match(lowerMessage, "^you begin to perform (.+)%.?$")
  local targetName
  local spellName

  if castStartSpell and self:GetTrackedDebuffDefinition(castStartSpell) then
    self:SnapshotPendingDebuffCast(castStartSpell)
  end

  targetName, spellName = string.match(lowerMessage, "^(.+) is afflicted by your (.+)%.$")
  if targetName and spellName then
    self:StartTrackedDebuff(targetName, spellName, false)
    return
  end

  spellName, targetName = string.match(lowerMessage, "^you cast (.+) on (.+)%.$")
  if spellName and targetName and self:GetTrackedDebuffDefinition(spellName) then
    self:StartTrackedDebuff(targetName, spellName, false)
    return
  end

  spellName, targetName = string.match(lowerMessage, "^you perform (.+) on (.+)%.$")
  if spellName and targetName and self:GetTrackedDebuffDefinition(spellName) then
    self:StartTrackedDebuff(targetName, spellName, false)
    return
  end

  targetName, spellName = string.match(lowerMessage, "^(.+) suffers .+ from your (.+)%.$")
  if targetName and spellName and self:GetTrackedDebuffDefinition(spellName) then
    self:StartTrackedDebuff(targetName, spellName, true)
    return
  end

  spellName, targetName = string.match(lowerMessage, "^your (.+) fades from (.+)%.$")
  if spellName and targetName and self:GetTrackedDebuffDefinition(spellName) then
    self:ClearTrackedDebuff(targetName, spellName)
    return
  end

  spellName, targetName = string.match(lowerMessage, "^(.+) fades from (.+)%.$")
  if spellName and targetName and self:GetTrackedDebuffDefinition(spellName) then
    self:ClearTrackedDebuff(targetName, spellName)
  end
end


-- Hostility checks need a fallback because Vanilla APIs are limited compared to modern WoW.
local function UnitIsHostileFallback(unit)
  if not UnitExists(unit) then
    return false
  end
  if UnitCanAttack and UnitCanAttack("player", unit) then
    return true
  end
  return false
end

local function TextMatches(actual, expected)
  local wanted = SafeLower(expected)
  if wanted == "" then
    return false
  end
  return SafeLower(actual) == wanted
end

local function TextContains(actual, expected)
  local wanted = SafeLower(expected)
  if wanted == "" then
    return false
  end
  return string.find(SafeLower(actual), wanted, 1, true) ~= nil
end

local function GetCombatLogSourceText(message)
  local source = string.match(message, "^(.+) begins to cast ")
    or string.match(message, "^(.+) begins to perform ")
    or string.match(message, "^(.+) casts ")
    or string.match(message, "^(.+) gains ")
    or string.match(message, "^(.+) is afflicted by ")
    or string.match(message, "^(.+) suffers ")
  if source then
    return source
  end
  if string.find(message, "^You ", 1, true) == 1 or string.find(message, "^Your ", 1, true) == 1 then
    return UnitName("player") or "Player"
  end
  return ""
end

local function ClearRuntimeTimerKeepFlags(timer)
  if not timer then
    return
  end
  timer.startTime = nil
  timer.duration = nil
  timer.expirationTime = nil
  timer.label = timer.label or nil
  timer.icon = timer.icon or nil
end

local function StartInternalCooldown(self, runtimeKey, duration, icon, label, source)
  local timer = self:GetAuraRuntime(runtimeKey)
  if timer.expirationTime and timer.expirationTime > GetTime() then
    return timer
  end
  self:StartAuraTimer(runtimeKey, duration or 0, icon, label, source)
  timer = self:GetAuraRuntime(runtimeKey)
  return timer
end

local function GetSpellBookType()
  return BOOKTYPE_SPELL or "spell"
end

local function GetCooldownWindow(startTime, duration)
  local startValue = tonumber(startTime) or 0
  local durationValue = tonumber(duration) or 0
  if durationValue <= 0 then
    return nil, nil, 0
  end
  return durationValue, startValue + durationValue, math.max((startValue + durationValue) - GetTime(), 0)
end

function TwAuras:FindSpellBookSlot(spellName)
  -- Several trigger types still depend on spellbook slot APIs on 1.12, so name-to-slot lookup
  -- lives in one helper instead of being repeated in every cooldown or known-spell trigger.
  local wanted = SafeLower(spellName)
  local bookType = GetSpellBookType()
  local index = 1
  if wanted == "" or not GetSpellName then
    return nil, nil
  end

  while true do
    local name, rank = GetSpellName(index, bookType)
    if not name then
      break
    end
    if SafeLower(name) == wanted then
      return index, rank
    end
    index = index + 1
  end

  return nil, nil
end

function TwAuras:GetSpellCooldownInfo(spellName)
  local index = self:FindSpellBookSlot(spellName)
  local bookType = GetSpellBookType()
  local texture = nil
  local startTime = 0
  local duration = 0
  local enabled = 0
  local cooldownDuration
  local expirationTime
  local remaining

  if not index then
    return nil
  end

  if GetSpellTexture then
    texture = GetSpellTexture(index, bookType)
  end
  if GetSpellCooldown then
    startTime, duration, enabled = GetSpellCooldown(index, bookType)
  end

  cooldownDuration, expirationTime, remaining = GetCooldownWindow(startTime, duration)

  return {
    found = true,
    icon = texture,
    name = spellName,
    startTime = tonumber(startTime) or 0,
    duration = cooldownDuration,
    expirationTime = expirationTime,
    remaining = remaining or 0,
    ready = (remaining or 0) <= 0,
    enabled = enabled,
  }
end

function TwAuras:GetSpellUsableInfo(spellName)
  local index = self:FindSpellBookSlot(spellName)
  local bookType = GetSpellBookType()
  local texture = nil
  local startTime = 0
  local duration = 0
  local enabled = 0
  local isUsable = false
  local notEnoughMana = false
  local inRange = nil
  local cooldownDuration
  local expirationTime
  local remaining

  if not index then
    return nil
  end

  if GetSpellTexture then
    texture = GetSpellTexture(index, bookType)
  end
  if GetSpellCooldown then
    startTime, duration, enabled = GetSpellCooldown(index, bookType)
  end
  if IsUsableSpell then
    isUsable, notEnoughMana = IsUsableSpell(index, bookType)
  end
  if IsSpellInRange then
    inRange = IsSpellInRange(index, bookType, "target")
  end

  cooldownDuration, expirationTime, remaining = GetCooldownWindow(startTime, duration)

  return {
    found = true,
    icon = texture,
    name = spellName,
    usable = isUsable and true or false,
    notEnoughMana = notEnoughMana and true or false,
    inRange = inRange,
    startTime = tonumber(startTime) or 0,
    duration = cooldownDuration,
    expirationTime = expirationTime,
    remaining = remaining or 0,
    ready = (remaining or 0) <= 0,
    enabled = enabled,
  }
end

function TwAuras:GetInventoryCooldownInfo(slot)
  local numericSlot = tonumber(slot)
  local texture = nil
  local startTime = 0
  local duration = 0
  local enabled = 0
  local cooldownDuration
  local expirationTime
  local remaining

  if not numericSlot or numericSlot <= 0 then
    return nil
  end

  if GetInventoryItemTexture then
    texture = GetInventoryItemTexture("player", numericSlot)
  end
  if GetInventoryItemCooldown then
    startTime, duration, enabled = GetInventoryItemCooldown("player", numericSlot)
  end

  cooldownDuration, expirationTime, remaining = GetCooldownWindow(startTime, duration)

  return {
    found = true,
    icon = texture,
    slot = numericSlot,
    startTime = tonumber(startTime) or 0,
    duration = cooldownDuration,
    expirationTime = expirationTime,
    remaining = remaining or 0,
    ready = (remaining or 0) <= 0,
    enabled = enabled,
  }
end

function TwAuras:GetEquippedItemInfo(itemName, wantedSlot)
  local wanted = SafeLower(itemName)
  local slotMode = SafeLower(wantedSlot or "any")
  local slots = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18}
  local i

  if wanted == "" or not GetInventoryItemLink then
    return nil
  end

  if slotMode ~= "any" then
    slots = { tonumber(slotMode) or 0 }
  end

  for i = 1, table.getn(slots) do
    local slot = slots[i]
    local link = GetInventoryItemLink("player", slot)
    if link and TextContains(link, wanted) then
      return {
        active = true,
        slot = slot,
        link = link,
        name = itemName,
        label = itemName,
        icon = GetInventoryItemTexture and GetInventoryItemTexture("player", slot) or nil,
      }
    end
  end

  return {
    active = false,
    name = itemName,
    label = itemName,
  }
end

function TwAuras:GetActiveFormInfo()
  local count = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
  local index
  for index = 1, count do
    local icon, name, active = GetShapeshiftFormInfo(index)
    if active then
      return {
        index = index,
        icon = icon,
        name = name,
        active = true,
      }
    end
  end
  return nil
end

function TwAuras:IsSpellKnown(spellName)
  return self:FindSpellBookSlot(spellName) ~= nil
end

function TwAuras:GetZoneInfo()
  local zoneName = GetRealZoneText and GetRealZoneText()
  if not zoneName or zoneName == "" then
    zoneName = GetZoneText and GetZoneText() or ""
  end
  return {
    zoneName = zoneName or "",
    subZoneName = GetSubZoneText and (GetSubZoneText() or "") or "",
  }
end

function TwAuras:GetActionUsableInfo(slot)
  local numericSlot = tonumber(slot)
  local isUsable
  local notEnoughMana
  local inRange
  local startTime = 0
  local duration = 0
  local enabled = 0
  local cooldownDuration
  local expirationTime
  local remaining
  local texture = nil

  if not numericSlot or numericSlot <= 0 then
    return nil
  end

  if IsUsableAction then
    isUsable, notEnoughMana = IsUsableAction(numericSlot)
  end
  if IsActionInRange then
    inRange = IsActionInRange(numericSlot)
  end
  if GetActionCooldown then
    startTime, duration, enabled = GetActionCooldown(numericSlot)
  end
  if GetActionTexture then
    texture = GetActionTexture(numericSlot)
  end

  cooldownDuration, expirationTime, remaining = GetCooldownWindow(startTime, duration)

  return {
    slot = numericSlot,
    icon = texture,
    usable = isUsable and true or false,
    notEnoughMana = notEnoughMana and true or false,
    inRange = inRange,
    duration = cooldownDuration,
    expirationTime = expirationTime,
    remaining = remaining or 0,
    ready = (remaining or 0) <= 0,
    enabled = enabled,
  }
end

function TwAuras:GetWeaponEnchantInfoForTrigger(hand)
  if not GetWeaponEnchantInfo then
    return nil
  end
  local hasMain, mainExpiration, mainCharges, hasOff, offExpiration, offCharges = GetWeaponEnchantInfo()
  local now = GetTime()
  local function build(whichHand, hasEnchant, expirationMs, charges)
    if not hasEnchant then
      return {
        hand = whichHand,
        active = false,
        charges = charges or 0,
        remaining = 0,
      }
    end
    local remaining = math.max((tonumber(expirationMs) or 0) / 1000, 0)
    return {
      hand = whichHand,
      active = true,
      charges = charges or 0,
      remaining = remaining,
      duration = remaining,
      expirationTime = now + remaining,
    }
  end

  if hand == "offhand" then
    return build("offhand", hasOff, offExpiration, offCharges)
  elseif hand == "either" then
    local main = build("mainhand", hasMain, mainExpiration, mainCharges)
    local off = build("offhand", hasOff, offExpiration, offCharges)
    if main.active and off.active then
      if (main.remaining or 0) >= (off.remaining or 0) then
        return main
      end
      return off
    end
    return main.active and main or off
  end

  return build("mainhand", hasMain, mainExpiration, mainCharges)
end

function TwAuras:GetBagItemCountByName(itemName)
  local wanted = SafeLower(itemName)
  local total = 0
  local bag
  if wanted == "" then
    return 0
  end

  if GetItemCount then
    local count = tonumber(GetItemCount(itemName))
    if count then
      return count
    end
  end

  if not GetContainerNumSlots or not GetContainerItemLink then
    return 0
  end

  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local slotCount = GetContainerNumSlots(bag) or 0
    local slot
    for slot = 1, slotCount do
      local link = GetContainerItemLink(bag, slot)
      if link then
        local name = string.match(link, "%[(.-)%]")
        if SafeLower(name) == wanted then
          local itemCount = 1
          if GetContainerItemInfo then
            local _, count = GetContainerItemInfo(bag, slot)
            itemCount = count or 1
          end
          total = total + (itemCount or 1)
        end
      end
    end
  end

  return total
end

function TwAuras:GetRangeInfo(trigger)
  local unit = trigger.rangeUnit or "target"
  local mode = trigger.rangeMode or "action"
  local active = false
  local raw = nil

  if not UnitExists(unit) then
    return nil
  end

  if mode == "interact" and CheckInteractDistance then
    raw = CheckInteractDistance(unit, tonumber(trigger.interactDistance) or 3)
    active = raw and true or false
  elseif IsActionInRange and tonumber(trigger.actionSlot) and tonumber(trigger.actionSlot) > 0 then
    raw = IsActionInRange(tonumber(trigger.actionSlot))
    active = raw == 1
  end

  return {
    unit = unit,
    raw = raw,
    inRange = active and true or false,
  }
end

function TwAuras:PlayerHasAggro()
  if UnitThreatSituation then
    return (UnitThreatSituation("player", "target") or 0) > 0
  end
  if UnitDetailedThreatSituation then
    local isTanking = UnitDetailedThreatSituation("player", "target")
    return isTanking and true or false
  end
  if UnitIsUnit and UnitExists("targettarget") then
    return UnitIsUnit("targettarget", "player") and true or false
  end
  if UnitExists("targettarget") then
    return SafeLower(UnitName("targettarget")) == SafeLower(UnitName("player"))
  end
  return false
end

function TwAuras:GetPlayerStateActive(stateName)
  local wanted = SafeLower(stateName or "mounted")
  if wanted == "resting" then
    return IsResting and IsResting() and true or false
  elseif wanted == "stealth" then
    if IsStealthed then
      return IsStealthed() and true or false
    end
    local stealthBuffs = {
      ["stealth"] = true,
      ["prowl"] = true,
      ["shadowmeld"] = true,
    }
    local i = 1
    while true do
      local texture = UnitBuff and UnitBuff("player", i) or nil
      local name = self:ExtractPlayerBuffAuraName(i, "HELPFUL")
      if not name and texture then
        name = self:ExtractTooltipAuraName(GameTooltip.SetUnitBuff, "player", i)
      end
      if not texture and not name then
        break
      end
      if stealthBuffs[SafeLower(name)] then
        return true
      end
      i = i + 1
    end
    return false
  end

  if IsMounted then
    return IsMounted() and true or false
  end
  return false
end

function TwAuras:GetGroupStateInfo()
  local raidCount = GetNumRaidMembers and (GetNumRaidMembers() or 0) or 0
  local partyCount = GetNumPartyMembers and (GetNumPartyMembers() or 0) or 0
  return {
    raidCount = raidCount,
    partyCount = partyCount,
    grouped = raidCount > 0 or partyCount > 0,
  }
end


-- Aura scanning is tooltip-backed so named buff/debuff tracking works on 1.12 APIs.
function TwAuras:ScanAura(unit, auraName, isDebuff)
  -- Hidden tooltip reads are the compatibility trick that lets us match by displayed aura name
  -- on the old client, where buff/debuff APIs do not always give us that directly.
  if not unit or unit == "" or not UnitExists(unit) then
    return { active = false }
  end

  local wanted = SafeLower(auraName)
  if wanted == "" then
    return { active = false }
  end

  if unit == "player" then
    local playerFilter = isDebuff and "HARMFUL" or "HELPFUL"
    local i = 1
    while true do
      local texture, count, spellId
      local name = self:ExtractPlayerBuffAuraName(i, playerFilter)
      if isDebuff then
        texture, count, spellId = UnitDebuff and UnitDebuff(unit, i) or nil, nil, nil
        if texture then
          local debuffTexture, debuffCount, debuffSpellId = UnitDebuff(unit, i)
          texture = debuffTexture
          count = debuffCount
          spellId = debuffSpellId
        end
      else
        texture, count, spellId = UnitBuff and UnitBuff(unit, i) or nil, nil, nil
        if texture then
          local buffTexture, buffCount, buffSpellId = UnitBuff(unit, i)
          texture = buffTexture
          count = buffCount
          spellId = buffSpellId
        end
      end
      if not name and texture then
        if isDebuff then
          name = self:ExtractTooltipAuraName(GameTooltip.SetUnitDebuff, unit, i)
        else
          name = self:ExtractTooltipAuraName(GameTooltip.SetUnitBuff, unit, i)
        end
      end
      if not name and not texture then
        break
      end
      if SafeLower(name) == wanted then
        return {
          active = true,
          name = name or auraName,
          icon = texture,
          stacks = count or 0,
          value = count or 0,
          maxValue = count or 0,
          duration = nil,
          expirationTime = nil,
          spellId = spellId,
        }
      end
      i = i + 1
    end
  end

  local i = 1
  while true do
    local texture, count, spellId
    local name
    if isDebuff then
      texture, count, spellId = UnitDebuff(unit, i)
      if not texture then
        break
      end
      name = self:ExtractTooltipAuraName(GameTooltip.SetUnitDebuff, unit, i)
    else
      texture, count, spellId = UnitBuff(unit, i)
      if not texture then
        break
      end
      name = self:ExtractTooltipAuraName(GameTooltip.SetUnitBuff, unit, i)
    end

    if SafeLower(name) == wanted then
      return {
        active = true,
        name = name or auraName,
        icon = texture,
        stacks = count or 0,
        value = count or 0,
        maxValue = count or 0,
        duration = nil,
        expirationTime = nil,
        spellId = spellId,
      }
    end
    i = i + 1
  end

  return { active = false }
end

-- Estimated durations are a best-effort fallback when the client does not expose real timers.
function TwAuras:ApplyEstimatedDuration(aura, state)
  if not aura or not aura.trigger or not state then
    return state
  end
  if not state.active then
    self:StopAuraTimer(self:GetTriggerRuntimeKey(aura, aura.trigger))
    return state
  end
  if (aura.trigger.duration or 0) <= 0 or state.expirationTime then
    return state
  end

  local runtimeKey = self:GetTriggerRuntimeKey(aura, aura.trigger)
  local timer = self:GetAuraRuntime(runtimeKey)
  if not timer.expirationTime or timer.icon ~= state.icon then
    self:StartAuraTimer(runtimeKey, aura.trigger.duration, state.icon, state.name or aura.name)
    timer = self:GetAuraRuntime(runtimeKey)
  end

  state.duration = timer.duration
  state.expirationTime = timer.expirationTime
  return state
end

-- Numeric triggers can compare either raw values or percentages from the same config field.
function TwAuras:EvaluateNumericTrigger(trigger, value, maxValue, label)
  local compareValue = value
  if trigger.valueMode == "percent" then
    if maxValue and maxValue > 0 then
      compareValue = math.floor((value / maxValue) * 100)
    else
      compareValue = 0
    end
  end

  return {
    active = CompareValue(compareValue, trigger.operator or ">=", trigger.threshold or 0),
    value = value,
    maxValue = maxValue,
    percent = maxValue and maxValue > 0 and math.floor((value / maxValue) * 100) or 0,
    compareValue = compareValue,
    label = label,
  }
end

function TwAuras:EvaluateSingleTrigger(aura, trigger)
  if not trigger or not trigger.type then
    return { active = false }
  end

  local handler = self:GetTriggerType(trigger.type)
  local state = handler and handler(self, aura, trigger) or { active = false }

  if trigger.trackMissing and (trigger.type == "buff" or trigger.type == "debuff") then
    local wasActive = state.active
    state.active = not wasActive
    if state.active then
      state.label = aura.name
      state.icon = state.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    end
  end

  if trigger.invert then
    state.active = not state.active
  end

  return state
end

-- Multiple triggers combine into one region state using all/any/priority rules.
function TwAuras:EvaluateTrigger(aura)
  -- Each trigger produces its own raw state first. Only after that do we apply the aura's
  -- all/any/priority rule to decide the single state the region should render.
  local triggers = aura and aura.triggers or nil
  if not triggers or table.getn(triggers) == 0 then
    return { active = false }
  end

  local mode = aura.triggerMode or "all"
  local triggerStates = {}
  local aggregateState = nil
  local activeCount = 0
  local relevantCount = 0
  local firstActiveState = nil
  local i

  for i = 1, table.getn(triggers) do
    if triggers[i].type ~= "none" then
      relevantCount = relevantCount + 1
    end
    aura.trigger = triggers[i]
    local state = self:EvaluateSingleTrigger(aura, triggers[i])
    triggerStates[i] = state
    if triggers[i].type ~= "none" and state and state.active then
      activeCount = activeCount + 1
      if not firstActiveState then
        firstActiveState = state
      end
    elseif triggers[i].type ~= "none" and not aggregateState then
      aggregateState = state
    end
  end

  aura.trigger = triggers[1]
  aura.__triggerStates = triggerStates

  if relevantCount == 0 then
    return { active = false }
  end

  if mode == "priority" then
    if firstActiveState then
      aggregateState = firstActiveState
      aggregateState.active = true
    else
      aggregateState = aggregateState or { active = false }
      aggregateState.active = false
    end
  elseif mode == "all" then
    aggregateState = firstActiveState or aggregateState or { active = false }
    aggregateState.active = activeCount == relevantCount
  else
    aggregateState = firstActiveState or aggregateState or { active = false }
    aggregateState.active = activeCount > 0
  end

  return aggregateState
end

-- The handlers below intentionally stay small and answer only "what is this trigger's raw state?"
-- Combination logic, inversion, and normalization all happen in shared code above.
local function BuffTriggerHandler(self, aura, trigger)
  local state = self:ScanAura(trigger.unit or "player", trigger.auraName, false)
  return self:ApplyEstimatedDuration(aura, state)
end

local function DebuffTriggerHandler(self, aura, trigger)
  -- Debuff triggers can blend a live aura scan with a combat-log tracked timer. This is what
  -- makes target debuff countdowns usable on the old client.
  local state = self:ScanAura(trigger.unit or "target", trigger.auraName, true)
  local tracked = nil
  if trigger.useTrackedTimer and SafeLower(trigger.unit or "target") == "target" then
    tracked = self:GetTrackedDebuff("target", trigger.auraName)
  end
  if trigger.sourceFilter == "player" and SafeLower(trigger.unit or "target") == "target" then
    if tracked then
      state.active = true
      state.name = state.name or tracked.name or trigger.auraName
      state.label = tracked.name or trigger.auraName
      state.source = tracked.source or UnitName("player") or "player"
      state.duration = tracked.duration
      state.expirationTime = tracked.expirationTime
      state.value = state.value or 0
      state.maxValue = state.maxValue or 0
    else
      state = {
        active = false,
        name = trigger.auraName,
        label = trigger.auraName,
      }
    end
    return self:ApplyEstimatedDuration(aura, state)
  end
  if trigger.sourceFilter == "other" and SafeLower(trigger.unit or "target") == "target" and tracked then
    if state.active then
      state.duration = nil
      state.expirationTime = nil
    else
      state = {
        active = false,
        name = trigger.auraName,
        label = trigger.auraName,
      }
    end
  end
  if tracked then
    state.active = true
    state.name = state.name or tracked.name or trigger.auraName
    state.label = tracked.name or trigger.auraName
    state.source = tracked.source or UnitName("player") or "player"
    state.duration = tracked.duration
    state.expirationTime = tracked.expirationTime
    state.value = state.value or 0
    state.maxValue = state.maxValue or 0
  end
  return self:ApplyEstimatedDuration(aura, state)
end

local function PowerTriggerHandler(self, _, trigger)
  local unit = trigger.unit or "player"
  local value = UnitMana(unit) or 0
  local maxValue = UnitManaMax(unit) or 100
  return self:EvaluateNumericTrigger(trigger, value, maxValue, string.upper(trigger.powerType or "POWER"))
end

local function ComboTriggerHandler(self, _, trigger)
  local value = GetComboPoints("player", "target") or 0
  return self:EvaluateNumericTrigger(trigger, value, 5, "Combo Points")
end

local function HealthTriggerHandler(self, _, trigger)
  local unit = trigger.unit or "player"
  local value = UnitHealth(unit) or 0
  local maxValue = UnitHealthMax(unit) or 1
  return self:EvaluateNumericTrigger(trigger, value, maxValue, "Health")
end

local function EnergyTickTriggerHandler(self, _, trigger)
  local info = self:GetEnergyTickInfo()
  local remaining = info.remaining or 0
  local isCooling = info.nextTickAt and remaining > 0
  local active
  if trigger.tickState == "ready" then
    active = not isCooling
  else
    active = isCooling and CompareValue(remaining, trigger.operator or ">=", trigger.threshold or 0)
  end
  return {
    active = active and true or false,
    name = "Energy Tick",
    label = "Energy Tick",
    duration = isCooling and info.duration or nil,
    expirationTime = isCooling and info.nextTickAt or nil,
    value = remaining,
    maxValue = info.duration or 2,
    percent = (info.duration and info.duration > 0) and ((remaining / info.duration) * 100) or 0,
    unit = "player",
  }
end

local function ManaRegenTriggerHandler(self, _, trigger)
  local info = self:GetManaFiveSecondRuleInfo()
  local active
  if trigger.ruleState == "outside" then
    active = not info.active
  else
    active = info.active and true or false
  end
  return {
    active = active and true or false,
    name = "Five Second Rule",
    label = trigger.ruleState == "outside" and "Mana Regen" or "Five Second Rule",
    duration = info.active and info.duration or nil,
    expirationTime = info.active and info.endsAt or nil,
    value = info.remaining or 0,
    maxValue = info.duration or 5,
    percent = (info.duration and info.duration > 0) and (((info.remaining or 0) / info.duration) * 100) or 0,
    unit = "player",
  }
end

local function CombatTriggerHandler()
  return { active = UnitAffectingCombat("player") and true or false, label = "Combat" }
end

local function TargetExistsTriggerHandler(_, _, trigger)
  local unit = trigger.unit or "target"
  return { active = UnitExists(unit) and true or false, label = unit .. " exists" }
end

local function TargetHostileTriggerHandler(_, _, trigger)
  local unit = trigger.unit or "target"
  return { active = UnitIsHostileFallback(unit), label = unit .. " hostile" }
end

local function CombatLogTriggerHandler(self, aura)
  local runtimeKey = self:GetTriggerRuntimeKey(aura, aura.trigger)
  local timer = self:GetAuraRuntime(runtimeKey)
  local active = timer.expirationTime and timer.expirationTime > GetTime()
  if not active then
    self:StopAuraTimer(runtimeKey)
    return {
      active = false,
      label = timer.label or aura.name,
      icon = timer.icon,
      source = timer.source or "",
    }
  end
  return {
    active = active and true or false,
    duration = timer.duration,
    expirationTime = timer.expirationTime,
    icon = timer.icon,
    label = timer.label or aura.name,
    source = timer.source or "",
  }
end

local function SpellCastTriggerHandler(self, aura, trigger)
  local runtimeKey = self:GetTriggerRuntimeKey(aura, trigger)
  local timer = self:GetAuraRuntime(runtimeKey)
  local active = timer.expirationTime and timer.expirationTime > GetTime()
  if not active then
    self:StopAuraTimer(runtimeKey)
    return {
      active = false,
      label = timer.label or trigger.spellName or aura.name,
      name = timer.label or trigger.spellName or aura.name,
      icon = timer.icon,
      source = timer.source or "",
    }
  end
  return {
    active = active and true or false,
    duration = timer.duration,
    expirationTime = timer.expirationTime,
    icon = timer.icon,
    label = timer.label or trigger.spellName or aura.name,
    name = timer.label or trigger.spellName or aura.name,
    source = timer.source or "",
  }
end

local function InternalCooldownTriggerHandler(self, aura, trigger)
  local runtimeKey = self:GetTriggerRuntimeKey(aura, trigger)
  local timer = self:GetAuraRuntime(runtimeKey)
  local detectMode = SafeLower(trigger.detectMode or "buff")
  local procState = nil
  local active
  local cooling

  if detectMode ~= "combatlog" then
    procState = self:ScanAura("player", trigger.procName, false)
    if procState.active and not timer.procActive then
      timer = StartInternalCooldown(self, runtimeKey, trigger.duration or 0, procState.icon or aura.display.iconPath, trigger.procName or aura.name, UnitName("player") or "Player")
    end
    timer.procActive = procState.active and true or false
  end

  active = timer.expirationTime and timer.expirationTime > GetTime()
  cooling = active and true or false
  if not cooling then
    ClearRuntimeTimerKeepFlags(timer)
  end

  if trigger.cooldownState == "ready" then
    active = not cooling
  else
    active = cooling
  end

  return {
    active = active and true or false,
    name = trigger.procName or aura.name,
    label = trigger.procName or aura.name,
    icon = timer.icon or (procState and procState.icon) or aura.display.iconPath,
    source = timer.source or "",
    value = cooling and math.max((timer.expirationTime or 0) - GetTime(), 0) or 0,
    maxValue = timer.duration or 0,
    percent = timer.duration and timer.duration > 0 and math.floor((math.max((timer.expirationTime or 0) - GetTime(), 0) / timer.duration) * 100) or 0,
    duration = timer.duration,
    expirationTime = timer.expirationTime,
  }
end

local function CooldownTriggerHandler(self, _, trigger)
  -- Cooldown triggers report more than a boolean so the same trigger can drive a bar, icon, or
  -- text display without any display-specific cooldown logic.
  local info = self:GetSpellCooldownInfo(trigger.spellName)
  local active
  if not info then
    return { active = false, label = trigger.spellName or "Spell Cooldown" }
  end

  if trigger.cooldownState == "cooldown" then
    active = not info.ready and CompareValue(info.remaining, trigger.operator or ">=", trigger.threshold or 0)
  else
    active = info.ready
  end

  return {
    active = active and true or false,
    name = info.name,
    label = info.name,
    icon = info.icon,
    value = info.remaining,
    maxValue = info.duration or 0,
    percent = info.duration and info.duration > 0 and math.floor((info.remaining / info.duration) * 100) or 0,
    startTime = info.duration and info.expirationTime and (info.expirationTime - info.duration) or nil,
    duration = info.duration,
    expirationTime = info.expirationTime,
  }
end

local function SpellUsableTriggerHandler(self, _, trigger)
  local info = self:GetSpellUsableInfo(trigger.spellName)
  local stateName = SafeLower(trigger.cooldownState or "usable")
  local active
  if not info then
    return { active = false, label = trigger.spellName or "Spell Usable" }
  end

  if stateName == "missingresource" then
    active = info.notEnoughMana and true or false
  elseif stateName == "cooldown" then
    active = not info.ready
  elseif stateName == "outrange" then
    active = info.inRange == 0
  else
    active = info.usable and not info.notEnoughMana
    if stateName == "usable" then
      active = active and info.ready
    end
  end

  return {
    active = active and true or false,
    name = info.name,
    label = info.name,
    icon = info.icon,
    value = info.remaining,
    maxValue = info.duration or 0,
    percent = info.duration and info.duration > 0 and math.floor((info.remaining / info.duration) * 100) or 0,
    startTime = info.duration and info.expirationTime and (info.expirationTime - info.duration) or nil,
    duration = info.duration,
    expirationTime = info.expirationTime,
  }
end

local function ItemCooldownTriggerHandler(self, _, trigger)
  local info = self:GetInventoryCooldownInfo(trigger.itemSlot)
  local label = "Item Slot " .. tostring(trigger.itemSlot or "")
  local active
  if not info then
    return { active = false, label = label }
  end

  if trigger.cooldownState == "cooldown" then
    active = not info.ready and CompareValue(info.remaining, trigger.operator or ">=", trigger.threshold or 0)
  else
    active = info.ready
  end

  return {
    active = active and true or false,
    name = label,
    label = label,
    icon = info.icon,
    value = info.remaining,
    maxValue = info.duration or 0,
    percent = info.duration and info.duration > 0 and math.floor((info.remaining / info.duration) * 100) or 0,
    startTime = info.duration and info.expirationTime and (info.expirationTime - info.duration) or nil,
    duration = info.duration,
    expirationTime = info.expirationTime,
  }
end

local function FormTriggerHandler(self, _, trigger)
  local activeForm = self:GetActiveFormInfo()
  local wanted = trigger.formName or ""
  local isActive

  if wanted == "" then
    isActive = activeForm ~= nil
  else
    isActive = activeForm and TextMatches(activeForm.name, wanted) or false
  end

  return {
    active = isActive and true or false,
    name = activeForm and activeForm.name or wanted,
    label = activeForm and activeForm.name or (wanted ~= "" and wanted or "Form"),
    icon = activeForm and activeForm.icon or nil,
  }
end

local function CastingTriggerHandler(self, _, trigger)
  -- The casting trigger currently targets player cast/channel state via the shared runtime
  -- snapshot Core.lua keeps up to date from spellcast events.
  local unit = SafeLower(trigger.unit or "player")
  local wantedType = SafeLower(trigger.castType or "any")
  local wantedSpell = SafeLower(trigger.spellName or "")
  local cast = nil
  local active = false

  if unit == "player" then
    cast = self.runtime.playerCast or {}
  end

  if cast and cast.active then
    active = true
    if wantedType == "cast" and cast.channel then
      active = false
    elseif wantedType == "channel" and not cast.channel then
      active = false
    end
    if active and wantedSpell ~= "" and SafeLower(cast.spellName) ~= wantedSpell then
      active = false
    end
  end

  return {
    active = active and true or false,
    name = cast and cast.spellName or trigger.spellName,
    label = cast and cast.spellName or (trigger.spellName ~= "" and trigger.spellName or "Casting"),
    icon = cast and cast.icon or nil,
  }
end

local function PetTriggerHandler()
  local active = UnitExists("pet") and true or false
  return {
    active = active,
    name = UnitName("pet") or "Pet",
    label = UnitName("pet") or "Pet",
  }
end

local function ZoneTriggerHandler(self, _, trigger)
  local info = self:GetZoneInfo()
  local wantedZone = SafeLower(trigger.zoneName or "")
  local wantedSubZone = SafeLower(trigger.subZoneName or "")
  local matchSubZone = trigger.matchSubZone and true or false
  local active = false

  if wantedZone == "" and wantedSubZone == "" then
    active = info.zoneName ~= ""
  elseif wantedZone ~= "" and TextMatches(info.zoneName, wantedZone) then
    active = true
  end

  if not active and (matchSubZone or wantedSubZone ~= "") then
    local subWanted = wantedSubZone ~= "" and wantedSubZone or wantedZone
    active = TextMatches(info.subZoneName, subWanted)
  end

  return {
    active = active and true or false,
    name = info.zoneName,
    label = info.subZoneName ~= "" and (info.zoneName .. " - " .. info.subZoneName) or info.zoneName,
  }
end

local function SpellKnownTriggerHandler(self, _, trigger)
  local known = self:IsSpellKnown(trigger.spellName)
  return {
    active = known and true or false,
    name = trigger.spellName,
    label = trigger.spellName ~= "" and trigger.spellName or "Known Spell",
  }
end

local function ActionUsableTriggerHandler(self, _, trigger)
  local info = self:GetActionUsableInfo(trigger.actionSlot)
  local actionState = SafeLower(trigger.actionState or "usable")
  local active
  if not info then
    return { active = false, label = "Action " .. tostring(trigger.actionSlot or "") }
  end

  if actionState == "missingresource" then
    active = info.notEnoughMana and true or false
  elseif actionState == "cooldown" then
    active = not info.ready
  elseif actionState == "outrange" then
    active = info.inRange == 0
  else
    active = info.usable and not info.notEnoughMana
    if trigger.requireReady then
      active = active and info.ready
    end
  end

  return {
    active = active and true or false,
    name = "Action " .. tostring(info.slot),
    label = "Action " .. tostring(info.slot),
    icon = info.icon,
    value = info.remaining,
    maxValue = info.duration or 0,
    percent = info.duration and info.duration > 0 and math.floor((info.remaining / info.duration) * 100) or 0,
    startTime = info.duration and info.expirationTime and (info.expirationTime - info.duration) or nil,
    duration = info.duration,
    expirationTime = info.expirationTime,
  }
end

local function WeaponEnchantTriggerHandler(self, _, trigger)
  local info = self:GetWeaponEnchantInfoForTrigger(trigger.weaponHand)
  local active
  if not info then
    return { active = false, label = "Weapon Enchant" }
  end
  active = info.active and true or false
  if trigger.enchantState == "inactive" then
    active = not active
  elseif active and (trigger.threshold or 0) > 0 then
    active = CompareValue(info.remaining or 0, trigger.operator or ">=", trigger.threshold or 0)
  end
  if active and (trigger.minCharges or 0) > 0 then
    active = (info.charges or 0) >= (trigger.minCharges or 0)
  end
  return {
    active = active and true or false,
    name = info.hand,
    label = (info.hand or "weapon") .. " enchant",
    value = info.remaining or 0,
    maxValue = info.duration or 0,
    duration = info.duration,
    expirationTime = info.expirationTime,
    stacks = info.charges or 0,
  }
end

local function ItemEquippedTriggerHandler(self, _, trigger)
  local info = self:GetEquippedItemInfo(trigger.itemName, trigger.equipmentSlot)
  if not info then
    return { active = false, label = trigger.itemName or "Equipped Item" }
  end
  return {
    active = info.active and true or false,
    name = info.name,
    label = info.label,
    icon = info.icon,
  }
end

local function ItemCountTriggerHandler(self, _, trigger)
  local count = self:GetBagItemCountByName(trigger.itemName)
  return {
    active = CompareValue(count, trigger.operator or ">=", trigger.threshold or 0),
    name = trigger.itemName,
    label = trigger.itemName ~= "" and trigger.itemName or "Item Count",
    value = count,
    maxValue = count,
  }
end

local function RangeTriggerHandler(self, _, trigger)
  local info = self:GetRangeInfo(trigger)
  local inRange = info and info.inRange and true or false
  local active = trigger.rangeState == "outrange" and not inRange or inRange
  return {
    active = active and true or false,
    label = (trigger.rangeUnit or "target") .. " range",
    value = inRange and 1 or 0,
    maxValue = 1,
  }
end

local function ThreatTriggerHandler(self, _, trigger)
  local hasAggro = self:PlayerHasAggro()
  local active = trigger.threatState == "notaggro" and not hasAggro or hasAggro
  return {
    active = active and true or false,
    label = "Threat",
    value = hasAggro and 1 or 0,
    maxValue = 1,
  }
end

local function PlayerStateTriggerHandler(self, _, trigger)
  local stateName = trigger.stateName or "mounted"
  local active = self:GetPlayerStateActive(stateName)
  return {
    active = active and true or false,
    name = stateName,
    label = "Player " .. stateName,
  }
end

local function GroupStateTriggerHandler(self, _, trigger)
  local info = self:GetGroupStateInfo()
  local wanted = SafeLower(trigger.groupState or "solo")
  local active = false
  if wanted == "raid" then
    active = info.raidCount > 0
  elseif wanted == "party" then
    active = info.partyCount > 0 and info.raidCount == 0
  elseif wanted == "grouped" then
    active = info.grouped
  else
    active = not info.grouped
  end
  return {
    active = active and true or false,
    name = wanted,
    label = "Group: " .. wanted,
    value = info.raidCount > 0 and info.raidCount or info.partyCount,
    maxValue = 40,
  }
end

local function AlwaysTriggerHandler(_, aura)
  return { active = true, label = aura.name }
end

local function NoneTriggerHandler()
  return { active = false, label = "" }
end

function TwAuras:TrackTargetHealthEstimateFromCombatLog(message)
  local targetName, damage
  if not message or message == "" then
    return
  end

  targetName, damage = string.match(message, "^You hit (.+) for (%d+)")
  if targetName and damage then
    self:AddObservedDamageToTarget(targetName, damage)
    return
  end

  targetName, damage = string.match(message, "^You crit (.+) for (%d+)")
  if targetName and damage then
    self:AddObservedDamageToTarget(targetName, damage)
    return
  end

  targetName, damage = string.match(message, "^Your .- hits (.+) for (%d+)")
  if targetName and damage then
    self:AddObservedDamageToTarget(targetName, damage)
    return
  end

  targetName, damage = string.match(message, "^Your .- crits (.+) for (%d+)")
  if targetName and damage then
    self:AddObservedDamageToTarget(targetName, damage)
    return
  end

  targetName, damage = string.match(message, "^(.+) suffers (%d+) .- from your ")
  if targetName and damage then
    self:AddObservedDamageToTarget(targetName, damage)
  end
end

function TwAuras:TrackTargetManaEstimateFromCombatLog(message)
  local targetName, amount
  if not message or message == "" then
    return
  end

  amount, targetName = string.match(message, "^Your .- drains (%d+) Mana from (.+)%.$")
  if amount and targetName then
    self:AddObservedManaChangeToTarget(targetName, amount)
    return
  end

  amount, targetName = string.match(message, "^Your .- drains (%d+) mana from (.+)%.$")
  if amount and targetName then
    self:AddObservedManaChangeToTarget(targetName, amount)
    return
  end

  targetName, amount = string.match(message, "^(.+) loses (%d+) Mana from your ")
  if targetName and amount then
    self:AddObservedManaChangeToTarget(targetName, amount)
    return
  end

  targetName, amount = string.match(message, "^(.+) loses (%d+) mana from your ")
  if targetName and amount then
    self:AddObservedManaChangeToTarget(targetName, amount)
  end
end

-- Combat-log triggers are string-based because Vanilla does not expose modern event payloads.
-- Descriptor metadata below serves two jobs:
-- 1. register the runtime handler
-- 2. tell Config.lua which fields and update events belong to that trigger type
function TwAuras:RecordCombatLog(chatEvent, message)
  -- Chat-based combat-log parsing feeds both debug output and timer-style trigger activation.
  -- This keeps all text-match trigger behavior in one place.
  if not message or message == "" then
    return
  end

  self:TrackPlayerDebuffsFromCombatLog(message)
  if self:AnyAuraUsesEstimatedHealthTokens() then
    self:TrackTargetHealthEstimateFromCombatLog(message)
  end
  if self:AnyAuraUsesEstimatedManaTokens() then
    self:TrackTargetManaEstimateFromCombatLog(message)
  end

  table.insert(self.runtime.recentCombatLog, 1, {
    event = chatEvent,
    message = message,
    time = date("%H:%M:%S"),
  })

  while table.getn(self.runtime.recentCombatLog) > 8 do
    table.remove(self.runtime.recentCombatLog)
  end

  local auras = self:GetAuraList()
  local i
  for i = 1, table.getn(auras) do
    local aura = auras[i]
    local j
    for j = 1, table.getn(aura.triggers or {}) do
      local trigger = aura.triggers[j]
      if trigger and trigger.type == "combatlog" then
        local wantedEvent = string.upper(trigger.combatLogEvent or "ANY")
        local pattern = trigger.combatLogPattern or ""
        local eventMatches = wantedEvent == "ANY" or wantedEvent == string.upper(chatEvent or "")
        local patternMatches = pattern ~= "" and string.find(string.lower(message), string.lower(pattern), 1, true)
        if eventMatches and patternMatches then
          self:StartAuraTimer(
            self:GetTriggerRuntimeKey(aura, trigger),
            trigger.duration or 0,
            aura.display.iconPath,
            aura.name,
            GetCombatLogSourceText(message)
          )
          self:RefreshAura(aura)
        end
      elseif trigger and trigger.type == "internalcooldown" then
        local detectMode = SafeLower(trigger.detectMode or "buff")
        local pattern = trigger.combatLogPattern or trigger.procName or ""
        if (detectMode == "combatlog" or detectMode == "either")
          and pattern ~= ""
          and string.find(string.lower(message), string.lower(pattern), 1, true) then
          StartInternalCooldown(
            self,
            self:GetTriggerRuntimeKey(aura, trigger),
            trigger.duration or 0,
            aura.display.iconPath,
            trigger.procName or aura.name,
            GetCombatLogSourceText(message)
          )
          self:RefreshAura(aura)
        end
      elseif trigger and trigger.type == "spellcast" then
        local spellName = trigger.spellName or ""
        local sourceUnit = trigger.sourceUnit or "player"
        local castPhase = trigger.castPhase or "any"
        local lowerMessage = string.lower(message)
        local lowerSpell = string.lower(spellName)
        local sourceName = sourceUnit == "target" and UnitName("target") or UnitName("player")
        local lowerSource = string.lower(sourceName or "")
        local isStartMessage = string.find(lowerMessage, "begins to cast", 1, true) ~= nil
          or string.find(lowerMessage, "begins to perform", 1, true) ~= nil
        local phaseMatches = castPhase == "any"
          or (castPhase == "start" and isStartMessage)
          or (castPhase == "success" and not isStartMessage)
        local sourceMatches = false

        if sourceUnit == "player" then
          sourceMatches = string.find(lowerMessage, "you ", 1, true) ~= nil
            or string.find(lowerMessage, "your ", 1, true) ~= nil
            or (lowerSource ~= "" and string.find(lowerMessage, lowerSource, 1, true) ~= nil)
        else
          sourceMatches = lowerSource ~= "" and string.find(lowerMessage, lowerSource, 1, true) ~= nil
        end

        if lowerSpell ~= "" and sourceMatches and phaseMatches and string.find(lowerMessage, lowerSpell, 1, true) ~= nil then
          self:StartAuraTimer(
            self:GetTriggerRuntimeKey(aura, trigger),
            trigger.duration or 2,
            aura.display.iconPath,
            trigger.spellName,
            GetCombatLogSourceText(message)
          )
          self:RefreshAura(aura)
        end
      end
    end
  end
end

-- Trigger descriptors are the first big step toward a metadata-driven WeakAuras-like system.
-- To add a new trigger type, define one handler and one descriptor; Config.lua will render the rest.
TwAuras:RegisterTriggerType("buff", {
  displayName = "Buff",
  handler = BuffTriggerHandler,
  events = {"auras", "world"},
  fields = {
    { key = "unit", label = "Unit", type = "select", width = 110, default = "player", options = {"player", "target", "targettarget", "pet", "focus"} },
    { key = "auraName", label = "Aura / Spell", type = "text", width = 180, default = "" },
    { key = "duration", label = "Duration", type = "number", width = 70, default = 0, help = "Estimated timer seconds" },
    { key = "trackMissing", label = "Track Missing Aura", type = "bool", default = false },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("debuff", {
  displayName = "Debuff",
  handler = DebuffTriggerHandler,
  events = {"auras", "target", "world"},
  fields = {
    { key = "unit", label = "Unit", type = "select", width = 110, default = "target", options = {"target", "targettarget", "player", "pet", "focus"} },
    { key = "auraName", label = "Aura / Spell", type = "text", width = 180, default = "" },
    { key = "sourceFilter", label = "Source", type = "select", width = 100, default = "any", options = {
      { value = "any", label = "Any Source" },
      { value = "player", label = "Cast By Player" },
      { value = "other", label = "Cast By Others" },
    } },
    { key = "useTrackedTimer", label = "Use Saved Timer", type = "bool", default = true },
    { key = "duration", label = "Duration", type = "number", width = 70, default = 0, help = "Estimated timer seconds" },
    { key = "trackMissing", label = "Track Missing Aura", type = "bool", default = false },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("power", {
  displayName = "Power",
  handler = PowerTriggerHandler,
  events = {"power", "world"},
  fields = {
    { key = "unit", label = "Unit", type = "select", width = 110, default = "player", options = {"player"} },
    { key = "powerType", label = "Power", type = "select", width = 90, default = "energy", options = {"energy", "mana", "rage"} },
    { key = "operator", label = "Operator", type = "select", width = 70, default = ">=", options = {"<", "<=", ">", ">=", "="} },
    { key = "threshold", label = "Threshold", type = "number", width = 70, default = 0 },
    { key = "valueMode", label = "Value Mode", type = "select", width = 90, default = "absolute", options = {"absolute", "percent"} },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("combo", {
  displayName = "Combo Points",
  handler = ComboTriggerHandler,
  events = {"combo", "target", "world"},
  fields = {
    { key = "operator", label = "Operator", type = "select", width = 70, default = ">=", options = {"<", "<=", ">", ">=", "="} },
    { key = "threshold", label = "Threshold", type = "number", width = 70, default = 0 },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("health", {
  displayName = "Health",
  handler = HealthTriggerHandler,
  events = {"health", "world"},
  fields = {
    { key = "unit", label = "Unit", type = "select", width = 110, default = "player", options = {"player", "target", "targettarget", "pet", "focus"} },
    { key = "operator", label = "Operator", type = "select", width = 70, default = ">=", options = {"<", "<=", ">", ">=", "="} },
    { key = "threshold", label = "Threshold", type = "number", width = 70, default = 0 },
    { key = "valueMode", label = "Value Mode", type = "select", width = 90, default = "absolute", options = {"absolute", "percent"} },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("energytick", {
  displayName = "Energy Tick",
  handler = EnergyTickTriggerHandler,
  events = {"power", "world"},
  fields = {
    { key = "tickState", label = "State", type = "select", width = 100, default = "cooldown", options = {
      { value = "cooldown", label = "Until Next Tick" },
      { value = "ready", label = "Tick Due" },
    } },
    { key = "operator", label = "Operator", type = "select", width = 70, default = ">=", options = {"<", "<=", ">", ">=", "="} },
    { key = "threshold", label = "Threshold", type = "number", width = 70, default = 0, help = "Seconds remaining when tracking the next tick" },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("manaregen", {
  displayName = "Mana Regen / FSR",
  handler = ManaRegenTriggerHandler,
  events = {"power", "casting", "world"},
  fields = {
    { key = "ruleState", label = "State", type = "select", width = 120, default = "inside", options = {
      { value = "inside", label = "Inside Five Second Rule" },
      { value = "outside", label = "Outside Five Second Rule" },
    } },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("combat", {
  displayName = "Combat",
  handler = CombatTriggerHandler,
  events = {"combat", "world"},
  fields = {
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("targetexists", {
  displayName = "Target Exists",
  handler = TargetExistsTriggerHandler,
  events = {"target", "world"},
  fields = {
    { key = "unit", label = "Unit", type = "select", width = 110, default = "target", options = {"target", "targettarget", "focus", "pet"} },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("targethostile", {
  displayName = "Target Hostile",
  handler = TargetHostileTriggerHandler,
  events = {"target", "world"},
  fields = {
    { key = "unit", label = "Unit", type = "select", width = 110, default = "target", options = {"target", "targettarget", "focus", "pet"} },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("combatlog", {
  displayName = "Combat Log",
  handler = CombatLogTriggerHandler,
  events = {"combatlog", "world"},
  fields = {
    { key = "combatLogEvent", label = "Combat Log Event", type = "select", width = 180, default = "ANY", options = {
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
    } },
    { key = "combatLogPattern", label = "Partial Combat Log Match", type = "text", width = 220, default = "", help = "Matches any part of the combat log line, such as boss casts or environmental warnings" },
    { key = "duration", label = "Duration", type = "number", width = 70, default = 10, help = "Timer seconds after a match" },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("spellcast", {
  displayName = "Spell Cast",
  handler = SpellCastTriggerHandler,
  events = {"combatlog", "target", "world"},
  fields = {
    { key = "sourceUnit", label = "Caster", type = "select", width = 90, default = "player", options = {"player", "target"} },
    { key = "spellName", label = "Spell Name", type = "text", width = 180, default = "" },
    { key = "castPhase", label = "Cast Phase", type = "select", width = 90, default = "any", options = {"any", "start", "success"} },
    { key = "duration", label = "Duration", type = "number", width = 70, default = 2, help = "Seconds to stay active after a match" },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("internalcooldown", {
  displayName = "Internal Cooldown",
  handler = InternalCooldownTriggerHandler,
  events = {"auras", "combatlog", "world"},
  fields = {
    { key = "procName", label = "Proc / Buff Name", type = "text", width = 180, default = "" },
    { key = "detectMode", label = "Detect From", type = "select", width = 110, default = "buff", options = {
      { value = "buff", label = "Player Buff Gain" },
      { value = "combatlog", label = "Combat Log Match" },
      { value = "either", label = "Either" },
    } },
    { key = "combatLogPattern", label = "Combat Log Match", type = "text", width = 220, default = "", help = "Optional partial combat log text for item procs or tier effects without a clean buff edge." },
    { key = "duration", label = "ICD Seconds", type = "number", width = 70, default = 45 },
    { key = "cooldownState", label = "Show", type = "select", width = 90, default = "cooldown", options = {
      { value = "cooldown", label = "While Cooling" },
      { value = "ready", label = "When Ready" },
    } },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("cooldown", {
  displayName = "Spell Cooldown",
  handler = CooldownTriggerHandler,
  events = {"cooldown", "spells", "world"},
  fields = {
    { key = "spellName", label = "Spell Name", type = "text", width = 180, default = "" },
    { key = "cooldownState", label = "State", type = "select", width = 90, default = "ready", options = {"ready", "cooldown"} },
    { key = "operator", label = "Operator", type = "select", width = 70, default = ">=", options = {"<", "<=", ">", ">=", "="} },
    { key = "threshold", label = "Threshold", type = "number", width = 70, default = 0, help = "Seconds remaining when using cooldown state" },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("spellusable", {
  displayName = "Spell Usable",
  handler = SpellUsableTriggerHandler,
  events = {"cooldown", "spells", "action", "target", "world"},
  fields = {
    { key = "spellName", label = "Spell Name", type = "text", width = 180, default = "" },
    { key = "cooldownState", label = "State", type = "select", width = 110, default = "usable", options = {
      { value = "usable", label = "Usable" },
      { value = "missingresource", label = "Missing Resource" },
      { value = "cooldown", label = "On Cooldown" },
      { value = "outrange", label = "Out Of Range" },
    } },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("itemcooldown", {
  displayName = "Item Cooldown",
  handler = ItemCooldownTriggerHandler,
  events = {"cooldown", "world"},
  fields = {
    { key = "itemSlot", label = "Inventory Slot", type = "select", width = 130, default = 13, options = {
      { value = 13, label = "Top Trinket (13)" },
      { value = 14, label = "Bottom Trinket (14)" },
      { value = 16, label = "Main Hand (16)" },
      { value = 17, label = "Off Hand (17)" },
      { value = 18, label = "Ranged / Relic (18)" },
    } },
    { key = "cooldownState", label = "State", type = "select", width = 90, default = "ready", options = {"ready", "cooldown"} },
    { key = "operator", label = "Operator", type = "select", width = 70, default = ">=", options = {"<", "<=", ">", ">=", "="} },
    { key = "threshold", label = "Threshold", type = "number", width = 70, default = 0, help = "Seconds remaining when using cooldown state" },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("form", {
  displayName = "Form / Stance",
  handler = FormTriggerHandler,
  events = {"form", "world"},
  fields = {
    { key = "formName", label = "Form Name", type = "text", width = 180, default = "", help = "Blank matches any active form" },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("casting", {
  displayName = "Casting / Channeling",
  handler = CastingTriggerHandler,
  events = {"casting", "world"},
  fields = {
    { key = "unit", label = "Unit", type = "select", width = 90, default = "player", options = {"player", "focus"} },
    { key = "spellName", label = "Spell Name", type = "text", width = 180, default = "", help = "Blank matches any spell" },
    { key = "castType", label = "Cast Type", type = "select", width = 90, default = "any", options = {"any", "cast", "channel"} },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("pet", {
  displayName = "Pet Exists",
  handler = PetTriggerHandler,
  events = {"pet", "world"},
  fields = {
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("zone", {
  displayName = "Zone",
  handler = ZoneTriggerHandler,
  events = {"zone", "world"},
  fields = {
    { key = "zoneName", label = "Zone", type = "text", width = 180, default = "" },
    { key = "subZoneName", label = "Sub Zone", type = "text", width = 180, default = "" },
    { key = "matchSubZone", label = "Match Sub Zone", type = "bool", default = false },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("spellknown", {
  displayName = "Spell Known",
  handler = SpellKnownTriggerHandler,
  events = {"spells", "world"},
  fields = {
    { key = "spellName", label = "Spell Name", type = "text", width = 180, default = "" },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("actionusable", {
  displayName = "Action Usable",
  handler = ActionUsableTriggerHandler,
  events = {"action", "cooldown", "world"},
  fields = {
    { key = "actionSlot", label = "Action Slot", type = "number", width = 70, default = 1 },
    { key = "actionState", label = "State", type = "select", width = 110, default = "usable", options = {
      { value = "usable", label = "Usable" },
      { value = "missingresource", label = "Missing Resource" },
      { value = "cooldown", label = "On Cooldown" },
      { value = "outrange", label = "Out Of Range" },
    } },
    { key = "requireReady", label = "Require Ready", type = "bool", default = true },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("weaponenchant", {
  displayName = "Weapon Enchant",
  handler = WeaponEnchantTriggerHandler,
  events = {"inventory", "world"},
  fields = {
    { key = "weaponHand", label = "Hand", type = "select", width = 110, default = "mainhand", options = {
      { value = "mainhand", label = "Main Hand" },
      { value = "offhand", label = "Off Hand" },
      { value = "either", label = "Either Hand" },
    } },
    { key = "enchantState", label = "State", type = "select", width = 100, default = "active", options = {
      { value = "active", label = "Active" },
      { value = "inactive", label = "Inactive" },
    } },
    { key = "operator", label = "Operator", type = "select", width = 70, default = ">=", options = {"<", "<=", ">", ">=", "="} },
    { key = "threshold", label = "Min Remaining", type = "number", width = 70, default = 0 },
    { key = "minCharges", label = "Min Charges", type = "number", width = 70, default = 0 },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("itemequipped", {
  displayName = "Item Equipped",
  handler = ItemEquippedTriggerHandler,
  events = {"inventory", "world"},
  fields = {
    { key = "itemName", label = "Item Name", type = "text", width = 180, default = "" },
    { key = "equipmentSlot", label = "Slot", type = "select", width = 120, default = "any", options = {
      { value = "any", label = "Any Equipped Slot" },
      { value = "13", label = "Top Trinket (13)" },
      { value = "14", label = "Bottom Trinket (14)" },
      { value = "16", label = "Main Hand (16)" },
      { value = "17", label = "Off Hand (17)" },
      { value = "18", label = "Ranged / Relic (18)" },
    } },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("itemcount", {
  displayName = "Inventory Item Count",
  handler = ItemCountTriggerHandler,
  events = {"inventory", "world"},
  fields = {
    { key = "itemName", label = "Item Name", type = "text", width = 180, default = "" },
    { key = "operator", label = "Operator", type = "select", width = 70, default = ">=", options = {"<", "<=", ">", ">=", "="} },
    { key = "threshold", label = "Threshold", type = "number", width = 70, default = 1 },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("range", {
  displayName = "Range",
  handler = RangeTriggerHandler,
  events = {"range", "target", "world"},
  fields = {
    { key = "rangeUnit", label = "Unit", type = "select", width = 90, default = "target", options = {"target", "focus", "pet"} },
    { key = "rangeMode", label = "Mode", type = "select", width = 90, default = "action", options = {
      { value = "action", label = "Action Slot" },
      { value = "interact", label = "Interact" },
    } },
    { key = "actionSlot", label = "Action Slot", type = "number", width = 70, default = 1 },
    { key = "interactDistance", label = "Interact Id", type = "select", width = 100, default = 3, options = {
      { value = 1, label = "1: Inspect" },
      { value = 2, label = "2: Trade" },
      { value = 3, label = "3: Duel" },
      { value = 4, label = "4: Follow" },
    } },
    { key = "rangeState", label = "State", type = "select", width = 90, default = "inrange", options = {
      { value = "inrange", label = "In Range" },
      { value = "outrange", label = "Out Of Range" },
    } },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("threat", {
  displayName = "Threat / Aggro",
  handler = ThreatTriggerHandler,
  events = {"threat", "target", "combat", "world"},
  fields = {
    { key = "threatState", label = "State", type = "select", width = 100, default = "aggro", options = {
      { value = "aggro", label = "Has Aggro" },
      { value = "notaggro", label = "No Aggro" },
    } },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("playerstate", {
  displayName = "Player State",
  handler = PlayerStateTriggerHandler,
  events = {"state", "auras", "world"},
  fields = {
    { key = "stateName", label = "State", type = "select", width = 110, default = "mounted", options = {
      { value = "mounted", label = "Mounted" },
      { value = "stealth", label = "Stealth" },
      { value = "resting", label = "Resting" },
    } },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("groupstate", {
  displayName = "Group / Raid State",
  handler = GroupStateTriggerHandler,
  events = {"group", "world"},
  fields = {
    { key = "groupState", label = "State", type = "select", width = 110, default = "solo", options = {
      { value = "solo", label = "Solo" },
      { value = "party", label = "Party" },
      { value = "raid", label = "Raid" },
      { value = "grouped", label = "Any Group" },
    } },
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("always", {
  displayName = "Always",
  handler = AlwaysTriggerHandler,
  events = {"world"},
  fields = {
    { key = "invert", label = "Invert Result", type = "bool", default = false },
  },
})

TwAuras:RegisterTriggerType("none", {
  displayName = "Unused",
  handler = NoneTriggerHandler,
  events = {},
  fields = {},
})

