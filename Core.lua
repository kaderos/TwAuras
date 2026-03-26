-- TwAuras file version: 0.1.44
-- Shared table helpers keep saved variables compatible as defaults evolve.
-- Defaults are copied recursively so adding new saved fields never wipes a user's profile.
local function CopyDefaults(src, dst)
  if type(src) ~= "table" then
    return dst
  end
  if type(dst) ~= "table" then
    dst = {}
  end
  local k, v
  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = CopyDefaults(v, dst[k])
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end


-- String and boolean normalization keep editor-entered values predictable.
local function SafeLower(value)
  if not value then
    return ""
  end
  return string.lower(value)
end

-- Boolean normalization collapses Lua's truthy values into explicit true/false flags for storage.
local function NormalizeBool(value)
  return value and true or false
end

-- Deep-copy helpers are used for duplication and migrations where saved aura tables must not alias.
local function DeepCopy(value)
  if type(value) ~= "table" then
    return value
  end
  local copy = {}
  local key
  for key in pairs(value) do
    copy[key] = DeepCopy(value[key])
  end
  return copy
end

-- Condition comparisons intentionally mirror trigger operators so the UI can reuse the same language.
local function CompareConditionValue(value, op, threshold)
  if op == "<" then return value < threshold end
  if op == "<=" then return value <= threshold end
  if op == ">" then return value > threshold end
  if op == ">=" then return value >= threshold end
  if op == "=" then return value == threshold end
  if op == "!=" or op == "~=" then return value ~= threshold end
  return false
end

-- Summaries and labels are truncated centrally so list rows and tooltip text stay consistent.
local function TruncateText(value, maxLength)
  local text = value or ""
  local limit = tonumber(maxLength) or 252
  if string.len(text) <= limit then
    return text
  end
  if limit <= 3 then
    return string.sub(text, 1, limit)
  end
  return string.sub(text, 1, limit - 3) .. "..."
end

-- Event aliases map raw WoW events and shorthand editor text onto the same internal keys.
local EVENT_KEY_ALIASES = {
  ["player_entering_world"] = "world",
  ["world"] = "world",
  ["entering_world"] = "world",
  ["player_enter_combat"] = "combat",
  ["player_leave_combat"] = "combat",
  ["combat"] = "combat",
  ["player_target_changed"] = "target",
  ["target"] = "target",
  ["player_auras_changed"] = "auras",
  ["auras"] = "auras",
  ["unit_energy"] = "power",
  ["unit_mana"] = "power",
  ["unit_rage"] = "power",
  ["power"] = "power",
  ["unit_combo_points"] = "combo",
  ["combo"] = "combo",
  ["unit_health"] = "health",
  ["unit_maxhealth"] = "health",
  ["health"] = "health",
  ["spells_changed"] = "spells",
  ["spell_update_cooldown"] = "cooldown",
  ["actionbar_update_cooldown"] = "cooldown",
  ["bag_update_cooldown"] = "cooldown",
  ["player_inventory_changed"] = "cooldown",
  ["update_shapeshift_forms"] = "form",
  ["spellcast_start"] = "casting",
  ["spellcast_stop"] = "casting",
  ["spellcast_failed"] = "casting",
  ["spellcast_interrupted"] = "casting",
  ["spellcast_delayed"] = "casting",
  ["spellcast_channel_start"] = "casting",
  ["spellcast_channel_stop"] = "casting",
  ["spellcast_channel_update"] = "casting",
  ["current_spell_cast_changed"] = "casting",
  ["zone_changed"] = "zone",
  ["zone_changed_indoors"] = "zone",
  ["zone_changed_new_area"] = "zone",
  ["bag_update"] = "inventory",
  ["inventory"] = "inventory",
  ["player_update_resting"] = "state",
  ["state"] = "state",
  ["party_members_changed"] = "group",
  ["raid_roster_update"] = "group",
  ["group"] = "group",
  ["range"] = "range",
  ["threat"] = "threat",
  ["actionbar_slot_changed"] = "action",
  ["actionbar_update_usable"] = "action",
  ["unit_pet"] = "pet",
  ["chat_msg"] = "combatlog",
  ["combatlog"] = "combatlog",
}

-- Core.lua is the addon's runtime spine:
-- it owns normalization, registry access, event routing, timer storage, condition resolution,
-- and the final bridge from evaluated trigger state to rendered regions.
-- Registry access and metadata helpers back the descriptor-driven trigger and region UI.
function TwAuras:Print(message)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TwAuras|r " .. message)
end

-- Trigger and region behavior is registered so the core does not need hardcoded type branches.
function TwAuras:RegisterTriggerType(name, definition)
  if not name or name == "" then
    return
  end
  local normalized = SafeLower(name)
  if type(definition) == "function" then
    definition = {
      handler = definition,
    }
  end
  if type(definition) ~= "table" or type(definition.handler) ~= "function" then
    return
  end
  definition.key = normalized
  definition.displayName = definition.displayName or name
  definition.fields = definition.fields or {}
  self.Private.triggerTypes[normalized] = definition
end

function TwAuras:GetTriggerType(name)
  if not name then
    return nil
  end
  local definition = self.Private.triggerTypes[SafeLower(name)]
  return definition and definition.handler or nil
end

function TwAuras:GetTriggerTypeDefinition(name)
  if not name then
    return nil
  end
  return self.Private.triggerTypes[SafeLower(name)]
end

function TwAuras:RegisterRegionType(name, definition)
  if not name or name == "" or type(definition) ~= "table" or type(definition.create) ~= "function" then
    return
  end
  local normalized = SafeLower(name)
  definition.key = normalized
  definition.displayName = definition.displayName or name
  definition.fields = definition.fields or {}
  self.Private.regionTypes[normalized] = definition
end

function TwAuras:GetRegionType(name)
  if not name then
    return nil
  end
  return self.Private.regionTypes[SafeLower(name)]
end

-- Sorted registry keys keep dropdowns stable between sessions instead of depending on table order.
function TwAuras:GetSortedRegistryKeys(registry)
  local keys = {}
  local key
  for key in pairs(registry or {}) do
    table.insert(keys, key)
  end
  table.sort(keys)
  return keys
end

function TwAuras:GetAvailableTriggerTypes()
  return self:GetSortedRegistryKeys(self.Private.triggerTypes)
end

function TwAuras:GetAvailableRegionTypes()
  return self:GetSortedRegistryKeys(self.Private.regionTypes)
end

-- Event key normalization lets old aliases, editor text, and raw WoW events converge on one map.
function TwAuras:NormalizeEventKey(value)
  local key = SafeLower(value or "")
  return EVENT_KEY_ALIASES[key] or key
end

-- Comma-separated load and update-event fields are parsed once here and reused elsewhere.
function TwAuras:SplitList(value)
  local items = {}
  local text = value or ""
  local token
  for token in string.gmatch(text, "([^,]+)") do
    token = string.gsub(token, "^%s+", "")
    token = string.gsub(token, "%s+$", "")
    if token ~= "" then
      table.insert(items, token)
    end
  end
  return items
end

function TwAuras:AddEventKey(target, key)
  key = self:NormalizeEventKey(key)
  if key and key ~= "" then
    target[key] = true
  end
end

function TwAuras:GetTriggerEventKeys(trigger)
  local definition = trigger and self:GetTriggerTypeDefinition(trigger.type) or nil
  return definition and definition.events or nil
end

-- Trigger list helpers keep the editor's dynamic multi-trigger model stable.
-- Trigger defaults define the editor's baseline shape for every newly created trigger row.
function TwAuras:CreateDefaultTrigger()
  return {
    type = "buff",
    unit = "player",
    auraName = "",
    procName = "",
    spellName = "",
    formName = "",
    zoneName = "",
    subZoneName = "",
    itemName = "",
    equipmentSlot = "any",
    stateName = "mounted",
    groupState = "solo",
    weaponHand = "mainhand",
    enchantState = "active",
    rangeUnit = "target",
    rangeMode = "action",
    rangeState = "inrange",
    threatState = "aggro",
    sourceUnit = "player",
    detectMode = "buff",
    sourceFilter = "any",
    castPhase = "any",
    castType = "any",
    powerType = "energy",
    operator = ">=",
    threshold = 1,
    duration = 0,
    cooldownState = "ready",
    actionState = "usable",
    tickState = "cooldown",
    ruleState = "inside",
    combatLogEvent = "ANY",
    combatLogPattern = "",
    interactDistance = 3,
    itemSlot = 13,
    actionSlot = 1,
    invert = false,
    trackMissing = false,
    useTrackedTimer = true,
    valueMode = "absolute",
    matchSubZone = false,
    requireReady = true,
    minCharges = 0,
  }
end

-- Disabled triggers are explicit placeholders so the editor can keep one trailing blank row.
function TwAuras:CreateDisabledTrigger()
  local trigger = self:CreateDefaultTrigger()
  trigger.type = "none"
  trigger.threshold = 0
  return trigger
end

-- Condition defaults seed the condition editor with a usable threshold rule and visual overrides.
function TwAuras:CreateDefaultCondition()
  return {
    enabled = true,
    check = "active",
    operator = "=",
    threshold = 1,
    useAlpha = false,
    alpha = 1,
    useColor = false,
    color = {1, 1, 1, 1},
    useTextColor = false,
    textColor = {1, 1, 1, 1},
    useBgColor = false,
    bgColor = {0, 0, 0, 0.5},
    useGlow = false,
    glow = false,
    glowColor = {1, 0.82, 0, 1},
    useDesaturate = false,
    desaturate = false,
  }
end

-- Sound defaults keep lifecycle audio fields present even on older saved auras.
function TwAuras:CreateDefaultSoundActions()
  return {
    startSound = "",
    activeSound = "",
    activeInterval = 2,
    stopSound = "",
  }
end

-- Debug flags are stored per aura so one noisy setup does not force chat spam for all auras.
function TwAuras:CreateDefaultDebugOptions()
  return {
    display = false,
    trigger = false,
    conditions = false,
    load = false,
    combatlog = false,
    timer = false,
    unitframes = false,
  }
end

function TwAuras:GetSelectedConditionIndex(aura)
  local index = self.db and self.db.selectedConditionIndex or nil
  local conditions = aura and aura.conditions or nil
  if not conditions or table.getn(conditions) == 0 then
    return nil
  end
  if not index or index < 1 or index > table.getn(conditions) then
    index = 1
  end
  self.db.selectedConditionIndex = index
  return index
end

function TwAuras:GetSelectedCondition(aura)
  local conditionAura = aura or self:GetSelectedAura()
  local index
  if not conditionAura then
    return nil, nil
  end
  index = self:GetSelectedConditionIndex(conditionAura)
  return conditionAura.conditions[index], index
end

function TwAuras:AddCondition(aura)
  if not aura then
    return
  end
  aura.conditions = aura.conditions or {}
  table.insert(aura.conditions, self:CreateDefaultCondition())
  self.db.selectedConditionIndex = table.getn(aura.conditions)
end

function TwAuras:RemoveCondition(aura, index)
  if not aura or not aura.conditions or not index then
    return
  end
  table.remove(aura.conditions, index)
  if self.db.selectedConditionIndex and self.db.selectedConditionIndex > table.getn(aura.conditions) then
    self.db.selectedConditionIndex = table.getn(aura.conditions)
  end
end

function TwAuras:MoveCondition(aura, index, direction)
  local newIndex
  local condition
  if not aura or not aura.conditions or not index then
    return
  end
  newIndex = index + direction
  if newIndex < 1 or newIndex > table.getn(aura.conditions) then
    return
  end
  condition = aura.conditions[index]
  aura.conditions[index] = aura.conditions[newIndex]
  aura.conditions[newIndex] = condition
  self.db.selectedConditionIndex = newIndex
end

-- Blank-trigger detection is what keeps dynamic trigger rows from multiplying forever in the editor.
function TwAuras:IsBlankTrigger(trigger)
  return not trigger or not trigger.type or trigger.type == "none"
end

function TwAuras:GetSelectedTriggerIndex(aura)
  local index = self.db and self.db.selectedTriggerIndex or nil
  if not aura or not aura.triggers or table.getn(aura.triggers) == 0 then
    return nil
  end
  if not index or index < 1 or index > table.getn(aura.triggers) then
    index = 1
  end
  self.db.selectedTriggerIndex = index
  return index
end

function TwAuras:GetSelectedTrigger(aura)
  local triggerAura = aura or self:GetSelectedAura()
  if not triggerAura then
    return nil, nil
  end
  local index = self:GetSelectedTriggerIndex(triggerAura)
  return triggerAura.triggers[index], index
end

-- The editor keeps one trailing blank trigger so "add trigger" feels like filling the next row.
function TwAuras:EnsureSingleBlankTrigger(aura)
  if not aura or not aura.triggers then
    return
  end

  local i = 1
  while i <= table.getn(aura.triggers) do
    if self:IsBlankTrigger(aura.triggers[i]) then
      table.remove(aura.triggers, i)
    else
      i = i + 1
    end
  end

  table.insert(aura.triggers, self:CreateDisabledTrigger())
end

function TwAuras:AddBlankTrigger(aura)
  if not aura then
    return
  end
  self:EnsureSingleBlankTrigger(aura)
  self.db.selectedTriggerIndex = table.getn(aura.triggers)
end

function TwAuras:RemoveTrigger(aura, index)
  if not aura or not aura.triggers or table.getn(aura.triggers) == 0 or not index then
    return
  end
  if table.getn(aura.triggers) == 1 then
    aura.triggers[1] = self:CreateDisabledTrigger()
  else
    table.remove(aura.triggers, index)
  end
  self:EnsureSingleBlankTrigger(aura)
  if self.db.selectedTriggerIndex and self.db.selectedTriggerIndex > table.getn(aura.triggers) then
    self.db.selectedTriggerIndex = table.getn(aura.triggers)
  end
end

function TwAuras:MoveTrigger(aura, index, direction)
  if not aura or not aura.triggers or not index then
    return
  end
  local newIndex = index + direction
  if newIndex < 1 or newIndex > table.getn(aura.triggers) then
    return
  end
  if self:IsBlankTrigger(aura.triggers[index]) or self:IsBlankTrigger(aura.triggers[newIndex]) then
    return
  end
  local trigger = aura.triggers[index]
  aura.triggers[index] = aura.triggers[newIndex]
  aura.triggers[newIndex] = trigger
  self.db.selectedTriggerIndex = newIndex
end

-- Saved variables are profile-scoped so future profiles can slot in cleanly.
function TwAuras:InitializeDB()
  TwAurasDB = CopyDefaults(self.defaults, TwAurasDB or {})
  self.db = TwAurasDB.profile
  self:MigrateAuraStore()
end

function TwAuras:GetDefaultAuraTemplate()
  return self.defaults
    and self.defaults.profile
    and self.defaults.profile.auras
    and self.defaults.profile.auras[1]
    or {}
end

-- The aura store is the canonical persistent layout used for backup, duplication, and ordering.
function TwAuras:GetAuraStore()
  if not self.db then
    return nil
  end
  self.db.auraStore = self.db.auraStore or {
    version = 1,
    order = {},
    items = {},
  }
  self.db.auraStore.version = self.db.auraStore.version or 1
  self.db.auraStore.order = self.db.auraStore.order or {}
  self.db.auraStore.items = self.db.auraStore.items or {}
  return self.db.auraStore
end

function TwAuras:BuildAuraRecordKey(id)
  return "aura_" .. tostring(id or 0)
end

-- User-visible names stay unique so duplicated auras and list rows remain distinguishable.
function TwAuras:GetUniqueAuraName(name, excludeId)
  local auras = self:GetAuraList()
  local wanted = name or "New Aura"
  local base = string.gsub(wanted, "%d+$", "")
  local maxSuffix = 0
  local hasBase = false
  local i
  if base == "" then
    base = wanted
  end
  for i = 1, table.getn(auras) do
    if auras[i].id ~= excludeId then
      local auraName = auras[i].name or ""
      if auraName == base then
        hasBase = true
      end
      local suffix = string.match(auraName, "^" .. string.gsub(base, "([^%w])", "%%%1") .. "(%d+)$")
      if suffix and tonumber(suffix) and tonumber(suffix) > maxSuffix then
        maxSuffix = tonumber(suffix)
      end
    end
  end
  if not hasBase and maxSuffix == 0 then
    return base
  end
  return base .. tostring(maxSuffix + 1)
end

-- Duplication clones the aura config but always assigns a fresh id, key, and collision-safe name.
function TwAuras:DuplicateAuraRecord(aura)
  local copy
  if not aura then
    return nil
  end
  copy = DeepCopy(aura)
  copy.id = self.db.nextId or 1
  self.db.nextId = copy.id + 1
  copy.key = self:BuildAuraRecordKey(copy.id)
  copy.schemaVersion = tonumber(copy.schemaVersion) or 1
  copy.name = self:GetUniqueAuraName(aura.name or ("Aura " .. tostring(copy.id)))
  copy.__state = nil
  copy.__triggerStates = nil
  copy.__unitStates = nil
  return copy
end

-- Runtime timers only count when they can still affect visible auras or debug output.
function TwAuras:GetActiveRuntimeTimerCount()
  local total = 0
  local now = GetTime()
  local key
  for key, timer in pairs(self.runtime and self.runtime.timers or {}) do
    if timer
      and timer.expirationTime
      and timer.expirationTime > now
      and (timer.duration or 0) > 0 then
      total = total + 1
    end
  end
  return total
end

-- Tracked runtime entries ignore expired placeholders so the object counter reflects live work.
function TwAuras:GetTrackedRuntimeEntryCount(entries)
  local total = 0
  local now = GetTime()
  local key
  for key, entry in pairs(entries or {}) do
    if entry then
      if entry.expirationTime then
        if entry.expirationTime > now then
          total = total + 1
        end
      elseif next(entry) ~= nil then
        total = total + 1
      else
        -- Empty placeholder tables should not inflate the debug object summary.
      end
    end
  end
  return total
end

-- Overlay counting treats each per-unit icon/glow state as a separate active object for debugging.
function TwAuras:GetActiveOverlayCount()
  local total = 0
  local auras = self:GetAuraList()
  local i
  for i = 1, table.getn(auras) do
    local aura = auras[i]
    if aura.__unitStates then
      total = total + table.getn(aura.__unitStates)
    end
  end
  return total
end

-- The object summary breakdown powers both the footer and the floating tracker tooltip.
function TwAuras:GetObjectSummaryBreakdown()
  local total = 0
  local auras = self:GetAuraList()
  local breakdown = {
    auras = 0,
    triggers = 0,
    conditions = 0,
    regions = 0,
    timers = 0,
    trackedBuffs = 0,
    trackedDebuffs = 0,
    overlays = 0,
  }
  local i
  local j
  for i = 1, table.getn(auras) do
    local aura = auras[i]
    breakdown.auras = breakdown.auras + 1
    total = total + 1
      for j = 1, table.getn(aura.triggers or {}) do
        if aura.triggers[j] and aura.triggers[j].type ~= "none" then
          breakdown.triggers = breakdown.triggers + 1
          total = total + 1
        end
      end
      breakdown.conditions = breakdown.conditions + table.getn(aura.conditions or {})
      total = total + table.getn(aura.conditions or {})
  end

  for i in pairs(self.regions or {}) do
    breakdown.regions = breakdown.regions + 1
    total = total + 1
  end

  breakdown.timers = self:GetActiveRuntimeTimerCount()
  breakdown.trackedBuffs = self:GetTrackedRuntimeEntryCount(self.runtime and self.runtime.trackedBuffs or nil)
  breakdown.trackedDebuffs = self:GetTrackedRuntimeEntryCount(self.runtime and self.runtime.trackedDebuffs or nil)
  breakdown.overlays = self:GetActiveOverlayCount()
  total = total + breakdown.timers
  total = total + breakdown.trackedBuffs
  total = total + breakdown.trackedDebuffs
  total = total + breakdown.overlays

  breakdown.total = total
  return breakdown
end

-- The total helper keeps callers simple when they only need the rolled-up number.
function TwAuras:GetObjectSummaryCount()
  return self:GetObjectSummaryBreakdown().total
end

-- Tooltip text is generated from the same breakdown table so totals and categories cannot drift apart.
function TwAuras:GetObjectSummaryTooltipText()
  local breakdown = self:GetObjectSummaryBreakdown()
  return "Object Breakdown\n"
    .. "Auras: " .. tostring(breakdown.auras) .. "\n"
    .. "Triggers: " .. tostring(breakdown.triggers) .. "\n"
    .. "Conditions: " .. tostring(breakdown.conditions) .. "\n"
    .. "Regions: " .. tostring(breakdown.regions) .. "\n"
    .. "Timers: " .. tostring(breakdown.timers) .. "\n"
    .. "Tracked Buffs: " .. tostring(breakdown.trackedBuffs) .. "\n"
    .. "Tracked Debuffs: " .. tostring(breakdown.trackedDebuffs) .. "\n"
    .. "Overlays: " .. tostring(breakdown.overlays) .. "\n"
    .. "Total: " .. tostring(breakdown.total)
end

-- Load colors are a rough troubleshooting aid, not a hard performance guarantee.
function TwAuras:GetObjectSummaryLoadColor(count)
  local total = tonumber(count) or 0
  if total <= 150 then
    return 0.25, 0.95, 0.35
  elseif total <= 250 then
    return 1.0, 0.82, 0.2
  end
  return 1.0, 0.32, 0.32
end

-- Debug displays are refreshed centrally so config and tracker stay in sync whenever state changes.
function TwAuras:RefreshDebugObjectDisplays()
  if self.configFrame and self.configFrame:IsShown() and self.RefreshObjectSummary then
    self:RefreshObjectSummary()
  end
  if self.RefreshObjectTracker then
    self:RefreshObjectTracker()
  end
end

-- Store migration upgrades legacy saved layouts into the compartmentalized auraStore model.
function TwAuras:MigrateAuraStore()
  local store = self:GetAuraStore()
  local legacy = self.db and self.db.auras or nil
  local migrated = false
  local i

  if table.getn(store.order) == 0 and type(legacy) == "table" and table.getn(legacy) > 0 then
    for i = 1, table.getn(legacy) do
      local aura = legacy[i]
      if aura and aura.id then
        aura.key = aura.key or self:BuildAuraRecordKey(aura.id)
        aura.schemaVersion = tonumber(aura.schemaVersion) or 1
        store.items[tostring(aura.id)] = aura
        table.insert(store.order, aura.id)
        migrated = true
      end
    end
  end

  if table.getn(store.order) == 0 and self.defaults and self.defaults.profile and self.defaults.profile.auras then
    for i = 1, table.getn(self.defaults.profile.auras) do
      local aura = CopyDefaults(self.defaults.profile.auras[i], {})
      aura.key = aura.key or self:BuildAuraRecordKey(aura.id)
      aura.schemaVersion = tonumber(aura.schemaVersion) or 1
      store.items[tostring(aura.id)] = aura
      table.insert(store.order, aura.id)
      migrated = true
    end
  end

  self.db.auras = nil

  local maxId = 0
  local cleanedOrder = {}
  local seen = {}
  for i = 1, table.getn(store.order) do
    local id = tonumber(store.order[i])
    local aura = id and store.items[tostring(id)] or nil
    if id and aura and not seen[id] then
      aura.id = id
      aura.key = aura.key or self:BuildAuraRecordKey(id)
      aura.schemaVersion = tonumber(aura.schemaVersion) or 1
      table.insert(cleanedOrder, id)
      seen[id] = true
      if id > maxId then
        maxId = id
      end
    end
  end
  store.order = cleanedOrder

  for i = 1, table.getn(store.order) do
    local id = store.order[i]
    local aura = store.items[tostring(id)]
    if aura and aura.id > maxId then
      maxId = aura.id
    end
  end

  if (self.db.nextId or 1) <= maxId then
    self.db.nextId = maxId + 1
  end

  if not self.db.selectedAuraId or not store.items[tostring(self.db.selectedAuraId)] then
    self.db.selectedAuraId = store.order[1] or nil
  end

  if migrated then
    self:Print("migrated aura data to compartmentalized storage")
  end
end

function TwAuras:InsertAuraRecord(aura, index)
  local store = self:GetAuraStore()
  if not store or not aura or not aura.id then
    return
  end
  aura.key = aura.key or self:BuildAuraRecordKey(aura.id)
  aura.schemaVersion = tonumber(aura.schemaVersion) or 1
  store.items[tostring(aura.id)] = aura
  if index and index >= 1 and index <= (table.getn(store.order) + 1) then
    table.insert(store.order, index, aura.id)
  else
    table.insert(store.order, aura.id)
  end
end

function TwAuras:RemoveAuraRecord(id)
  local store = self:GetAuraStore()
  local i
  if not store or not id then
    return
  end
  store.items[tostring(id)] = nil
  for i = 1, table.getn(store.order) do
    if store.order[i] == id then
      table.remove(store.order, i)
      break
    end
  end
end

-- Normalize edited and saved aura data before it is used anywhere else.
-- This is the compatibility layer between old saves, live editor input, and runtime evaluation.
-- Normalization is the compatibility layer between old saves, wizard presets, and live editor data.
function TwAuras:NormalizeAuraConfig(aura)
  -- Normalization is the safety net between old saved data, live editor input, and runtime code.
  -- Every major subsystem assumes this has already run before it reads the aura.
  aura.enabled = aura.enabled ~= false
  aura.regionType = SafeLower(aura.regionType or "icon")
  if not self:GetRegionType(aura.regionType) then
    aura.regionType = "icon"
  end

  aura.key = aura.key or self:BuildAuraRecordKey(aura.id)
  aura.schemaVersion = tonumber(aura.schemaVersion) or 1

  aura.display = CopyDefaults(self:GetDefaultAuraTemplate().display, aura.display or {})
  aura.load = CopyDefaults(self:GetDefaultAuraTemplate().load, aura.load or {})
  aura.position = CopyDefaults(self:GetDefaultAuraTemplate().position, aura.position or {})
  aura.soundActions = CopyDefaults(self:CreateDefaultSoundActions(), aura.soundActions or {})
  aura.debug = CopyDefaults(self:CreateDefaultDebugOptions(), aura.debug or {})
  aura.conditions = aura.conditions or {}
  aura.load.updateEvents = aura.load.updateEvents or ""
  aura.load.zoneText = aura.load.zoneText or ""
  aura.load.allowWorld = aura.load.allowWorld ~= false
  aura.load.allowDungeon = aura.load.allowDungeon ~= false
  aura.load.allowRaid = aura.load.allowRaid ~= false
  aura.load.allowPvp = aura.load.allowPvp ~= false
  aura.load.allowArena = aura.load.allowArena ~= false
  aura.display.width = tonumber(aura.display.width) or 36
  aura.display.height = tonumber(aura.display.height) or 36
  aura.display.alpha = tonumber(aura.display.alpha) or 1
  aura.display.fontSize = tonumber(aura.display.fontSize) or 12
  aura.display.fontOutline = string.upper(aura.display.fontOutline or "")
  aura.display.labelAnchor = string.upper(aura.display.labelAnchor or "BOTTOM")
  aura.display.timerAnchor = string.upper(aura.display.timerAnchor or "TOP")
  aura.display.valueAnchor = string.upper(aura.display.valueAnchor or "RIGHT")
  aura.display.textAnchor = string.upper(aura.display.textAnchor or "CENTER")
  aura.triggerMode = SafeLower(aura.triggerMode or "all")
  if aura.triggerMode == "and" then
    aura.triggerMode = "all"
  elseif aura.triggerMode == "or" then
    aura.triggerMode = "any"
  end
  if aura.triggerMode ~= "all" and aura.triggerMode ~= "any" and aura.triggerMode ~= "priority" then
    aura.triggerMode = "all"
  end

  if not aura.triggers or table.getn(aura.triggers) == 0 then
    local migratedTrigger = aura.trigger and CopyDefaults(aura.trigger, {}) or self:CreateDefaultTrigger()
    aura.triggers = { migratedTrigger }
  end

  local triggerDefaults = self:CreateDefaultTrigger()
  local i
  for i = 1, table.getn(aura.triggers) do
    local trigger = CopyDefaults(triggerDefaults, aura.triggers[i] or {})
    trigger.type = SafeLower(trigger.type or "")
    if trigger.type == "" then
      trigger.type = "none"
    end
    trigger.unit = SafeLower(trigger.unit or "player")
    if trigger.unit == "frameunit" then
      trigger.unit = "partyunit"
    end
    trigger.sourceUnit = SafeLower(trigger.sourceUnit or "player")
    trigger.sourceFilter = SafeLower(trigger.sourceFilter or "any")
    if trigger.sourceUnit ~= "player" and trigger.sourceUnit ~= "target" then
      trigger.sourceUnit = "player"
    end
    if trigger.sourceFilter ~= "any" and trigger.sourceFilter ~= "player" and trigger.sourceFilter ~= "other" then
      trigger.sourceFilter = "any"
    end
    trigger.castPhase = SafeLower(trigger.castPhase or "any")
    if trigger.castPhase ~= "any" and trigger.castPhase ~= "start" and trigger.castPhase ~= "success" then
      trigger.castPhase = "any"
    end
    trigger.castType = SafeLower(trigger.castType or "any")
    if trigger.castType ~= "any" and trigger.castType ~= "cast" and trigger.castType ~= "channel" then
      trigger.castType = "any"
    end
    trigger.powerType = SafeLower(trigger.powerType or "energy")
    trigger.cooldownState = SafeLower(trigger.cooldownState or "ready")
    if trigger.cooldownState ~= "ready"
      and trigger.cooldownState ~= "cooldown"
      and trigger.cooldownState ~= "usable"
      and trigger.cooldownState ~= "missingresource"
      and trigger.cooldownState ~= "outrange" then
      trigger.cooldownState = "ready"
    end
    trigger.tickState = SafeLower(trigger.tickState or "cooldown")
    if trigger.tickState ~= "cooldown" and trigger.tickState ~= "ready" then
      trigger.tickState = "cooldown"
    end
    trigger.ruleState = SafeLower(trigger.ruleState or "inside")
    if trigger.ruleState ~= "inside" and trigger.ruleState ~= "outside" then
      trigger.ruleState = "inside"
    end
    trigger.formName = trigger.formName or ""
    trigger.zoneName = trigger.zoneName or ""
    trigger.subZoneName = trigger.subZoneName or ""
    trigger.itemName = trigger.itemName or ""
    trigger.stateName = SafeLower(trigger.stateName or "mounted")
    if trigger.stateName ~= "mounted" and trigger.stateName ~= "stealth" and trigger.stateName ~= "resting" then
      trigger.stateName = "mounted"
    end
    trigger.groupState = SafeLower(trigger.groupState or "solo")
    if trigger.groupState ~= "solo" and trigger.groupState ~= "party" and trigger.groupState ~= "raid" and trigger.groupState ~= "grouped" then
      trigger.groupState = "solo"
    end
    trigger.weaponHand = SafeLower(trigger.weaponHand or "mainhand")
    if trigger.weaponHand ~= "mainhand" and trigger.weaponHand ~= "offhand" and trigger.weaponHand ~= "either" then
      trigger.weaponHand = "mainhand"
    end
    trigger.rangeUnit = SafeLower(trigger.rangeUnit or "target")
    trigger.rangeMode = SafeLower(trigger.rangeMode or "action")
    if trigger.rangeMode ~= "action" and trigger.rangeMode ~= "interact" then
      trigger.rangeMode = "action"
    end
    trigger.actionState = SafeLower(trigger.actionState or "usable")
    if trigger.actionState ~= "usable"
      and trigger.actionState ~= "missingresource"
      and trigger.actionState ~= "cooldown"
      and trigger.actionState ~= "outrange" then
      trigger.actionState = "usable"
    end
    trigger.rangeState = SafeLower(trigger.rangeState or "inrange")
    if trigger.rangeState ~= "inrange" and trigger.rangeState ~= "outrange" then
      trigger.rangeState = "inrange"
    end
    trigger.threatState = SafeLower(trigger.threatState or "aggro")
    if trigger.threatState ~= "aggro" and trigger.threatState ~= "notaggro" then
      trigger.threatState = "aggro"
    end
    trigger.combatLogEvent = string.upper(trigger.combatLogEvent or "ANY")
    trigger.operator = trigger.operator ~= "" and trigger.operator or ">="
    trigger.threshold = tonumber(trigger.threshold) or 0
    trigger.duration = tonumber(trigger.duration) or 0
    trigger.interactDistance = tonumber(trigger.interactDistance) or 3
    if trigger.interactDistance < 1 or trigger.interactDistance > 4 then
      trigger.interactDistance = 3
    end
    trigger.itemSlot = tonumber(trigger.itemSlot) or 13
    trigger.actionSlot = tonumber(trigger.actionSlot) or 1
    trigger.minCharges = tonumber(trigger.minCharges) or 0
    trigger.invert = NormalizeBool(trigger.invert)
    trigger.trackMissing = NormalizeBool(trigger.trackMissing)
    trigger.useTrackedTimer = NormalizeBool(trigger.useTrackedTimer ~= false)
    trigger.valueMode = SafeLower(trigger.valueMode or "absolute")
    if trigger.valueMode ~= "absolute" and trigger.valueMode ~= "percent" then
      trigger.valueMode = "absolute"
    end
    trigger.matchSubZone = NormalizeBool(trigger.matchSubZone)
    trigger.requireReady = NormalizeBool(trigger.requireReady ~= false)
    trigger.__index = i
    aura.triggers[i] = trigger
  end

  for i = 1, table.getn(aura.conditions) do
    local condition = CopyDefaults(self:CreateDefaultCondition(), aura.conditions[i] or {})
    condition.enabled = NormalizeBool(condition.enabled ~= false)
    condition.check = SafeLower(condition.check or "active")
    condition.operator = condition.operator ~= "" and condition.operator or "="
    condition.threshold = tonumber(condition.threshold) or 0
    condition.useAlpha = NormalizeBool(condition.useAlpha)
    condition.alpha = tonumber(condition.alpha) or 1
    condition.useColor = NormalizeBool(condition.useColor)
    condition.useTextColor = NormalizeBool(condition.useTextColor)
    condition.useBgColor = NormalizeBool(condition.useBgColor)
    condition.useGlow = NormalizeBool(condition.useGlow)
    condition.glow = NormalizeBool(condition.glow)
    condition.useDesaturate = NormalizeBool(condition.useDesaturate)
    condition.desaturate = NormalizeBool(condition.desaturate)
    aura.conditions[i] = condition
  end

  aura.trigger = aura.triggers[1]

  aura.display.width = tonumber(aura.display.width) or 36
  aura.display.height = tonumber(aura.display.height) or 36
  aura.display.alpha = tonumber(aura.display.alpha) or 1
  aura.display.showIcon = aura.display.showIcon ~= false
  aura.display.showTimerText = NormalizeBool(aura.display.showTimerText)
  aura.display.showStackText = NormalizeBool(aura.display.showStackText)
  aura.display.showLabelText = NormalizeBool(aura.display.showLabelText)
  aura.display.desaturateInactive = NormalizeBool(aura.display.desaturateInactive)
  aura.display.iconDesaturate = NormalizeBool(aura.display.iconDesaturate)
  aura.display.iconHueEnabled = NormalizeBool(aura.display.iconHueEnabled)
  aura.display.iconHue = tonumber(aura.display.iconHue) or 0
  aura.display.showCooldownSwipe = NormalizeBool(aura.display.showCooldownSwipe)
  aura.display.showCooldownOverlay = NormalizeBool(aura.display.showCooldownOverlay)
  aura.display.timerFormat = SafeLower(aura.display.timerFormat or "smart")
  if aura.display.timerFormat ~= "smart"
    and aura.display.timerFormat ~= "mmss"
    and aura.display.timerFormat ~= "seconds"
    and aura.display.timerFormat ~= "decimal" then
    aura.display.timerFormat = "smart"
  end
  aura.display.lowTimeThreshold = tonumber(aura.display.lowTimeThreshold) or 0
  aura.display.lowTimeTextColorEnabled = NormalizeBool(aura.display.lowTimeTextColorEnabled)
  aura.display.lowTimeBarColorEnabled = NormalizeBool(aura.display.lowTimeBarColorEnabled)
  aura.display.fillDirection = SafeLower(aura.display.fillDirection or "ltr")
  if aura.display.fillDirection ~= "ltr" and aura.display.fillDirection ~= "rtl" then
    aura.display.fillDirection = "ltr"
  end
  aura.display.barIconPosition = SafeLower(aura.display.barIconPosition or "front")
  if aura.display.barIconPosition ~= "front" and aura.display.barIconPosition ~= "back" then
    aura.display.barIconPosition = "front"
  end
  aura.display.strata = string.upper(aura.display.strata or "MEDIUM")
  if aura.display.strata ~= "BACKGROUND"
    and aura.display.strata ~= "LOW"
    and aura.display.strata ~= "MEDIUM"
    and aura.display.strata ~= "HIGH" then
    aura.display.strata = "MEDIUM"
  end
  if aura.display.iconHue < 0 then aura.display.iconHue = 0 end
  if aura.display.iconHue > 360 then aura.display.iconHue = 360 end
  aura.display.iconPath = aura.display.iconPath or ""
  aura.display.labelText = aura.display.labelText or ""
  aura.display.timerText = aura.display.timerText or ""
  aura.display.valueText = aura.display.valueText or ""
  aura.display.fontSize = tonumber(aura.display.fontSize) or 12
  aura.display.fontOutline = aura.display.fontOutline or ""
  aura.display.labelAnchor = string.upper(aura.display.labelAnchor or "BOTTOM")
  aura.display.timerAnchor = string.upper(aura.display.timerAnchor or "TOP")
  aura.display.valueAnchor = string.upper(aura.display.valueAnchor or "RIGHT")
  aura.display.textAnchor = string.upper(aura.display.textAnchor or "CENTER")
  aura.display.frameScope = SafeLower(aura.display.frameScope or "party")
  if aura.display.frameScope ~= "party"
    and aura.display.frameScope ~= "raid"
    and aura.display.frameScope ~= "both" then
    aura.display.frameScope = "party"
  end
  aura.display.overlayStyle = SafeLower(aura.display.overlayStyle or "icon")
  if aura.display.overlayStyle ~= "icon" and aura.display.overlayStyle ~= "glow" then
    aura.display.overlayStyle = "icon"
  end
  aura.display.frameAnchor = string.upper(aura.display.frameAnchor or "TOPLEFT")
  if aura.display.frameAnchor ~= "TOPLEFT"
    and aura.display.frameAnchor ~= "TOP"
    and aura.display.frameAnchor ~= "TOPRIGHT" then
    aura.display.frameAnchor = "TOPLEFT"
  end
  aura.display.frameYOffset = tonumber(aura.display.frameYOffset) or 0
  aura.soundActions.startSound = aura.soundActions.startSound or ""
  aura.soundActions.activeSound = aura.soundActions.activeSound or ""
  aura.soundActions.stopSound = aura.soundActions.stopSound or ""
  aura.soundActions.activeInterval = tonumber(aura.soundActions.activeInterval) or 2
  if aura.soundActions.activeInterval < 0.2 then
    aura.soundActions.activeInterval = 0.2
  end
end

-- Instance context is normalized here so load checks can stay old-client-safe and readable.
function TwAuras:GetCurrentInstanceType()
  if type(IsInInstance) == "function" then
    local isInInstance, instanceType = IsInInstance()
    if not isInInstance then
      return "none"
    end
    instanceType = SafeLower(instanceType or "")
    if instanceType == "party" or instanceType == "raid" or instanceType == "pvp" or instanceType == "arena" then
      return instanceType
    end
  end
  return "none"
end

-- Location-based load filters all depend on the same zone or instance context.
function TwAuras:LoadUsesZoneContext(cfg)
  if not cfg then
    return false
  end
  if (cfg.zoneText or "") ~= "" then
    return true
  end
  if cfg.allowWorld == false or cfg.allowDungeon == false or cfg.allowRaid == false or cfg.allowPvp == false or cfg.allowArena == false then
    return true
  end
  return false
end

-- Trigger handlers can return sparse data; the core fills the common state shape.
function TwAuras:NormalizeState(aura, state)
  if type(state) ~= "table" then
    state = {}
  end

  state.active = state.active and true or false
  state.name = state.name or aura.name
  state.label = state.label or aura.name
  state.icon = state.icon or aura.display.iconPath
  state.stacks = tonumber(state.stacks) or 0
  state.value = state.value ~= nil and state.value or 0
  state.maxValue = state.maxValue ~= nil and state.maxValue or 0
  state.percent = tonumber(state.percent) or 0
  state.startTime = tonumber(state.startTime) or nil
  state.duration = tonumber(state.duration) or nil
  state.expirationTime = tonumber(state.expirationTime) or nil
  state.remaining = state.expirationTime and math.max(state.expirationTime - GetTime(), 0) or 0
  state.unit = state.unit or (aura and aura.trigger and aura.trigger.unit) or nil

  return state
end

-- Frame-unit triggers are evaluated per unit, so they need special handling outside normal aura flow.
function TwAuras:IsFrameUnitTrigger(trigger)
  return trigger and SafeLower(trigger.unit or "") == "partyunit"
end

function TwAuras:AuraUsesFrameUnits(aura)
  local i
  for i = 1, table.getn(aura and aura.triggers or {}) do
    if self:IsFrameUnitTrigger(aura.triggers[i]) then
      return true
    end
  end
  return false
end

-- Scope helpers translate party/raid/both into the concrete unit ids the runtime can scan.
function TwAuras:GetGroupUnitsForScope(scope)
  local units = {}
  local normalized = SafeLower(scope or "party")
  local i
  if normalized == "party" or normalized == "both" then
    for i = 1, (GetNumPartyMembers and (GetNumPartyMembers() or 0) or 0) do
      if UnitExists("party" .. i) then
        table.insert(units, "party" .. i)
      end
    end
  end
  if normalized == "raid" or normalized == "both" then
    for i = 1, (GetNumRaidMembers and (GetNumRaidMembers() or 0) or 0) do
      if UnitExists("raid" .. i) then
        table.insert(units, "raid" .. i)
      end
    end
  end
  return units
end

-- Effective triggers are shallow trigger copies with the current per-unit override applied.
function TwAuras:GetEffectiveTrigger(trigger, unitOverride)
  local copy
  local key
  if not unitOverride or not self:IsFrameUnitTrigger(trigger) then
    return trigger
  end
  copy = {}
  for key in pairs(trigger) do
    copy[key] = trigger[key]
  end
  copy.unit = unitOverride
  return copy
end

-- Per-unit trigger evaluation is what lets one aura paint multiple party or raid overlays.
function TwAuras:EvaluateTriggerForUnit(aura, unit)
  local triggers = aura and aura.triggers or nil
  local mode
  local aggregateState = nil
  local activeCount = 0
  local relevantCount = 0
  local firstActiveState = nil
  local i
  if not triggers or table.getn(triggers) == 0 then
    return { active = false, unit = unit }
  end

  mode = aura.triggerMode or "all"
  for i = 1, table.getn(triggers) do
    local trigger = triggers[i]
    if trigger and trigger.type ~= "none" then
      local effectiveTrigger = self:GetEffectiveTrigger(trigger, unit)
      local state
      relevantCount = relevantCount + 1
      aura.trigger = effectiveTrigger
      state = self:EvaluateSingleTrigger(aura, effectiveTrigger)
      if state then
        state.unit = state.unit or unit
      end
      if state and state.active then
        activeCount = activeCount + 1
        if not firstActiveState then
          firstActiveState = state
        end
      elseif not aggregateState then
        aggregateState = state
      end
    end
  end

  aura.trigger = triggers[1]
  if relevantCount == 0 then
    return { active = false, unit = unit }
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

  aggregateState.unit = aggregateState.unit or unit
  return aggregateState
end

-- Unitframe states return both the per-unit active list and a first-active aggregate summary.
function TwAuras:BuildUnitFrameStates(aura)
  local units = self:GetGroupUnitsForScope(aura and aura.display and aura.display.frameScope or "party")
  local states = {}
  local firstActive = nil
  local i
  for i = 1, table.getn(units) do
    local unit = units[i]
    local normalized = self:ResolveConditionalState(aura, self:NormalizeState(aura, self:EvaluateTriggerForUnit(aura, unit)))
    normalized.unit = unit
    if normalized.active then
      table.insert(states, normalized)
      if not firstActive then
        firstActive = normalized
      end
    end
  end
  if self:IsAuraDebugEnabled(aura, "unitframes") then
    self:DebugLog(aura, "unitframes", "built " .. tostring(table.getn(states)) .. " active unit frame state(s)")
  end
  return states, firstActive or { active = false }
end

function TwAuras:BuildPreviewUnitFrameStates(aura)
  local units = self:GetGroupUnitsForScope(aura and aura.display and aura.display.frameScope or "party")
  local states = {}
  local i
  for i = 1, table.getn(units) do
    local preview = self:BuildPreviewState(aura)
    preview.unit = units[i]
    table.insert(states, preview)
  end
  return states
end

-- Tracking keys prefer GUIDs when available, then fall back to names for Vanilla-safe identity.
function TwAuras:GetUnitTrackingKey(unit)
  local guid = UnitGUID and UnitGUID(unit)
  if guid and guid ~= "" then
    return tostring(guid)
  end
  local name = UnitName and UnitName(unit)
  if name and name ~= "" then
    return SafeLower(name)
  end
  return nil
end

function TwAuras:GetTargetNameTrackingKey(targetName)
  if not targetName or targetName == "" then
    return nil
  end
  return SafeLower(targetName)
end

-- Health estimate entries accumulate damage observations until enough data exists for a max-HP guess.
function TwAuras:GetTargetHealthEstimateEntryByKey(key, displayName)
  if not key or key == "" then
    return nil
  end
  self.runtime.targetHealthEstimates = self.runtime.targetHealthEstimates or {}
  if not self.runtime.targetHealthEstimates[key] then
    self.runtime.targetHealthEstimates[key] = {
      key = key,
      name = displayName or "",
      damageBucket = 0,
      lastPercent = nil,
      estimatedMaxHp = nil,
      estimatedCurrentHp = nil,
      lastSeen = 0,
    }
  end
  if displayName and displayName ~= "" then
    self.runtime.targetHealthEstimates[key].name = displayName
  end
  return self.runtime.targetHealthEstimates[key]
end

-- Observed damage is bucketed between percent changes so estimates only update when there is signal.
function TwAuras:AddObservedDamageToTarget(targetName, amount)
  local numericAmount = tonumber(amount) or 0
  local key = self:GetTargetNameTrackingKey(targetName)
  local entry
  if numericAmount <= 0 or not key then
    return nil
  end
  entry = self:GetTargetHealthEstimateEntryByKey(key, targetName)
  entry.damageBucket = (entry.damageBucket or 0) + numericAmount
  entry.lastSeen = GetTime()
  return entry
end

-- Health estimates combine percent drops and observed damage into a rolling best-fit max health.
function TwAuras:UpdateEstimatedHealthForUnit(unit)
  local key = self:GetUnitTrackingKey(unit)
  local name = UnitName and UnitName(unit) or ""
  local health
  local maxHealth
  local percent
  local entry
  local deltaPercent
  local observedMax
  if not key or not UnitExists or not UnitExists(unit) then
    return nil
  end

  health = UnitHealth(unit) or 0
  maxHealth = UnitHealthMax(unit) or 1
  if maxHealth <= 0 then
    maxHealth = 1
  end
  percent = math.floor((health / maxHealth) * 100)
  entry = self:GetTargetHealthEstimateEntryByKey(key, name)

  if entry.lastPercent ~= nil then
    if percent < entry.lastPercent and (entry.damageBucket or 0) > 0 then
      deltaPercent = entry.lastPercent - percent
      if deltaPercent > 0 then
        observedMax = math.floor(((entry.damageBucket or 0) * 100 / deltaPercent) + 0.5)
        if observedMax > 0 then
          if entry.estimatedMaxHp and entry.estimatedMaxHp > 0 then
            entry.estimatedMaxHp = math.floor(((entry.estimatedMaxHp * 2) + observedMax) / 3 + 0.5)
          else
            entry.estimatedMaxHp = observedMax
          end
        end
      end
      entry.damageBucket = 0
    elseif percent > entry.lastPercent then
      entry.damageBucket = 0
    end
  end

  entry.lastPercent = percent
  entry.lastSeen = GetTime()
  if entry.estimatedMaxHp and entry.estimatedMaxHp > 0 then
    entry.estimatedCurrentHp = math.floor((entry.estimatedMaxHp * percent / 100) + 0.5)
  end
  return entry
end

function TwAuras:GetEstimatedHealthForUnit(unit)
  local key = self:GetUnitTrackingKey(unit)
  local entry
  local health
  local maxHealth
  local percent
  if not key then
    return nil
  end
  entry = self.runtime.targetHealthEstimates and self.runtime.targetHealthEstimates[key] or nil
  if not entry or not entry.estimatedMaxHp or entry.estimatedMaxHp <= 0 then
    return nil
  end
  if UnitExists and UnitExists(unit) then
    health = UnitHealth(unit) or 0
    maxHealth = UnitHealthMax(unit) or 1
    if maxHealth <= 0 then
      maxHealth = 1
    end
    percent = math.floor((health / maxHealth) * 100)
    entry.estimatedCurrentHp = math.floor((entry.estimatedMaxHp * percent / 100) + 0.5)
    entry.lastPercent = percent
  end
  return entry
end

function TwAuras:GetTargetManaEstimateEntryByKey(key, displayName)
  if not key or key == "" then
    return nil
  end
  self.runtime.targetManaEstimates = self.runtime.targetManaEstimates or {}
  if not self.runtime.targetManaEstimates[key] then
    self.runtime.targetManaEstimates[key] = {
      key = key,
      name = displayName or "",
      drainBucket = 0,
      lastPercent = nil,
      estimatedMaxMana = nil,
      estimatedCurrentMana = nil,
      lastSeen = 0,
    }
  end
  if displayName and displayName ~= "" then
    self.runtime.targetManaEstimates[key].name = displayName
  end
  return self.runtime.targetManaEstimates[key]
end

function TwAuras:AddObservedManaChangeToTarget(targetName, amount)
  local numericAmount = tonumber(amount) or 0
  local key = self:GetTargetNameTrackingKey(targetName)
  local entry
  if numericAmount <= 0 or not key then
    return nil
  end
  entry = self:GetTargetManaEstimateEntryByKey(key, targetName)
  entry.drainBucket = (entry.drainBucket or 0) + numericAmount
  entry.lastSeen = GetTime()
  return entry
end

function TwAuras:UpdateEstimatedManaForUnit(unit)
  local key = self:GetUnitTrackingKey(unit)
  local name = UnitName and UnitName(unit) or ""
  local value
  local maxValue
  local percent
  local entry
  local deltaPercent
  local observedMax
  if not key or not UnitExists or not UnitExists(unit) then
    return nil
  end

  value = UnitMana(unit) or 0
  maxValue = UnitManaMax(unit) or 0
  if maxValue <= 0 then
    return nil
  end
  percent = math.floor((value / maxValue) * 100)
  entry = self:GetTargetManaEstimateEntryByKey(key, name)

  if entry.lastPercent ~= nil then
    if percent < entry.lastPercent and (entry.drainBucket or 0) > 0 then
      deltaPercent = entry.lastPercent - percent
      if deltaPercent > 0 then
        observedMax = math.floor(((entry.drainBucket or 0) * 100 / deltaPercent) + 0.5)
        if observedMax > 0 then
          if entry.estimatedMaxMana and entry.estimatedMaxMana > 0 then
            entry.estimatedMaxMana = math.floor(((entry.estimatedMaxMana * 2) + observedMax) / 3 + 0.5)
          else
            entry.estimatedMaxMana = observedMax
          end
        end
      end
      entry.drainBucket = 0
    elseif percent > entry.lastPercent then
      entry.drainBucket = 0
    end
  end

  entry.lastPercent = percent
  entry.lastSeen = GetTime()
  if entry.estimatedMaxMana and entry.estimatedMaxMana > 0 then
    entry.estimatedCurrentMana = math.floor((entry.estimatedMaxMana * percent / 100) + 0.5)
  end
  return entry
end

function TwAuras:GetEstimatedManaForUnit(unit)
  local key = self:GetUnitTrackingKey(unit)
  local entry
  local value
  local maxValue
  local percent
  if not key then
    return nil
  end
  entry = self.runtime.targetManaEstimates and self.runtime.targetManaEstimates[key] or nil
  if not entry or not entry.estimatedMaxMana or entry.estimatedMaxMana <= 0 then
    return nil
  end
  if UnitExists and UnitExists(unit) then
    value = UnitMana(unit) or 0
    maxValue = UnitManaMax(unit) or 0
    if maxValue > 0 then
      percent = math.floor((value / maxValue) * 100)
      entry.estimatedCurrentMana = math.floor((entry.estimatedMaxMana * percent / 100) + 0.5)
      entry.lastPercent = percent
    end
  end
  return entry
end

function TwAuras:ContainsEstimatedHealthToken(text)
  local value = text or ""
  return string.find(value, "%realhp", 1, true) ~= nil
    or string.find(value, "%realmaxhp", 1, true) ~= nil
    or string.find(value, "%realhpdeficit", 1, true) ~= nil
end

function TwAuras:ContainsEstimatedManaToken(text)
  local value = text or ""
  return string.find(value, "%realmana", 1, true) ~= nil
    or string.find(value, "%realmaxmana", 1, true) ~= nil
    or string.find(value, "%realmanadeficit", 1, true) ~= nil
end

function TwAuras:AuraUsesEstimatedHealthTokens(aura)
  local display = aura and aura.display or nil
  if not display then
    return false
  end
  return self:ContainsEstimatedHealthToken(display.labelText)
    or self:ContainsEstimatedHealthToken(display.timerText)
    or self:ContainsEstimatedHealthToken(display.valueText)
end

function TwAuras:AnyAuraUsesEstimatedHealthTokens()
  local auras = self:GetAuraList()
  local i
  for i = 1, table.getn(auras) do
    if self:AuraUsesEstimatedHealthTokens(auras[i]) then
      return true
    end
  end
  return false
end

function TwAuras:AuraUsesEstimatedManaTokens(aura)
  local display = aura and aura.display or nil
  if not display then
    return false
  end
  return self:ContainsEstimatedManaToken(display.labelText)
    or self:ContainsEstimatedManaToken(display.timerText)
    or self:ContainsEstimatedManaToken(display.valueText)
end

function TwAuras:AnyAuraUsesEstimatedManaTokens()
  local auras = self:GetAuraList()
  local i
  for i = 1, table.getn(auras) do
    if self:AuraUsesEstimatedManaTokens(auras[i]) then
      return true
    end
  end
  return false
end

-- Preferred real health values use exact client data first and fall back to the estimate system.
function TwAuras:GetPreferredRealHealthValues(unit)
  local current = UnitHealth and UnitHealth(unit) or nil
  local maxValue = UnitHealthMax and UnitHealthMax(unit) or nil
  local estimated

  if current and maxValue and maxValue > 100 then
    return {
      current = current,
      maxValue = maxValue,
      deficit = math.max(maxValue - current, 0),
      source = "exact",
    }
  end

  estimated = self:GetEstimatedHealthForUnit(unit)
  if estimated and estimated.estimatedMaxHp and estimated.estimatedCurrentHp then
    return {
      current = estimated.estimatedCurrentHp,
      maxValue = estimated.estimatedMaxHp,
      deficit = math.max(estimated.estimatedMaxHp - estimated.estimatedCurrentHp, 0),
      source = "estimate",
    }
  end

  return nil
end

function TwAuras:GetPreferredRealManaValues(unit)
  local current = UnitMana and UnitMana(unit) or nil
  local maxValue = UnitManaMax and UnitManaMax(unit) or nil
  local estimated

  if current and maxValue and maxValue > 100 then
    return {
      current = current,
      maxValue = maxValue,
      deficit = math.max(maxValue - current, 0),
      source = "exact",
    }
  end

  estimated = self:GetEstimatedManaForUnit(unit)
  if estimated and estimated.estimatedMaxMana and estimated.estimatedCurrentMana then
    return {
      current = estimated.estimatedCurrentMana,
      maxValue = estimated.estimatedMaxMana,
      deficit = math.max(estimated.estimatedMaxMana - estimated.estimatedCurrentMana, 0),
      source = "estimate",
    }
  end

  return nil
end

-- Conditions turn raw trigger state into display overrides without mutating the saved base config.
function TwAuras:EvaluateCondition(condition, state)
  local value = 0
  local check = condition and condition.check or "active"
  if not condition or not condition.enabled then
    return false
  end

  if check == "active" then
    value = state.active and 1 or 0
  elseif check == "remaining" then
    value = state.remaining or 0
  elseif check == "stacks" then
    value = state.stacks or 0
  elseif check == "value" then
    value = state.value or 0
  elseif check == "percent" then
    value = state.percent or 0
  else
    value = 0
  end

  return CompareConditionValue(value, condition.operator or "=", condition.threshold or 0)
end

-- Conditional resolution builds a temporary display snapshot for this refresh only.
function TwAuras:ResolveConditionalState(aura, state)
  -- Conditions build a resolved display snapshot for the current state instead of mutating the
  -- saved display config. That makes conditional styling temporary and deterministic.
  local resolvedDisplay = CopyDefaults(aura.display or {}, {})
  local i
  local matchedCount = 0
  for i = 1, table.getn(aura.conditions or {}) do
    local condition = aura.conditions[i]
    local ok, matched = pcall(self.EvaluateCondition, self, condition, state)
    if not ok then
      local err = matched
      matched = false
      if self:IsAuraDebugEnabled(aura, "conditions") then
        self:DebugLog(aura, "conditions", "condition " .. tostring(i) .. " error: " .. tostring(err))
      end
    end
    if matched then
      matchedCount = matchedCount + 1
      if condition.useAlpha then
        resolvedDisplay.alpha = condition.alpha
      end
      if condition.useColor then
        resolvedDisplay.color = CopyDefaults(condition.color or {}, {})
      end
      if condition.useTextColor then
        resolvedDisplay.textColor = CopyDefaults(condition.textColor or {}, {})
      end
      if condition.useBgColor then
        resolvedDisplay.bgColor = CopyDefaults(condition.bgColor or {}, {})
      end
      if condition.useGlow then
        resolvedDisplay.glow = condition.glow and true or false
        resolvedDisplay.glowColor = CopyDefaults(condition.glowColor or {}, {})
      end
      if condition.useDesaturate then
        resolvedDisplay.iconDesaturate = condition.desaturate and true or false
      end
    end
  end
  state.display = resolvedDisplay
  if self:IsAuraDebugEnabled(aura, "conditions") then
    self:DebugLog(aura, "conditions", tostring(matchedCount) .. " condition(s) matched; active=" .. tostring(state.active and true or false))
  end
  return state
end

-- Display text is resolved late from runtime state so one region can show names, timers,
-- resources, or stacks without knowing which trigger type produced the state.
-- Dynamic text formatting is the final token expansion step before text hits a live region.
function TwAuras:FormatDynamicDisplayText(template, aura, state, now)
  local text = template or ""
  local display = state.display or aura.display or {}
  local label = state.label or aura.name or ""
  local value = state.value ~= nil and tostring(state.value) or ""
  local maxValue = ""
  local percent = state.percent ~= nil and tostring(state.percent) or ""
  local stacks = state.stacks ~= nil and tostring(state.stacks) or ""
  local timeText = state.expirationTime and self:FormatRemainingTime(state.expirationTime, now or GetTime(), display.timerFormat) or ""
  local name = state.name or aura.name or ""
  local unitText = state.unit or (aura and aura.trigger and aura.trigger.unit) or ""
  local realHealth = nil
  local realHp = ""
  local realMaxHp = ""
  local realHpDeficit = ""
  local realMana = nil
  local realManaValue = ""
  local realMaxMana = ""
  local realManaDeficit = ""
  local source = state.source or self:GetPreferredSourceText(aura, state) or ""

  if state.maxValue ~= nil then
    maxValue = tostring(state.maxValue)
  elseif state.duration ~= nil then
    -- Timer-style triggers can reuse %max as their total duration for simpler templates.
    maxValue = tostring(state.duration)
  end

  if self:ContainsEstimatedHealthToken(text) then
    realHealth = self:GetPreferredRealHealthValues(state.unit or "target")
    realHp = realHealth and tostring(realHealth.current or "") or ""
    realMaxHp = realHealth and tostring(realHealth.maxValue or "") or ""
    realHpDeficit = realHealth and tostring(realHealth.deficit or "") or ""
  end
  if self:ContainsEstimatedManaToken(text) then
    realMana = self:GetPreferredRealManaValues(state.unit or "target")
    realManaValue = realMana and tostring(realMana.current or "") or ""
    realMaxMana = realMana and tostring(realMana.maxValue or "") or ""
    realManaDeficit = realMana and tostring(realMana.deficit or "") or ""
  end

  text = string.gsub(text, "%%label", label)
  text = string.gsub(text, "%%name", name)
  text = string.gsub(text, "%%source", source)
  text = string.gsub(text, "%%unit", unitText)
  text = string.gsub(text, "%%value", value)
  text = string.gsub(text, "%%max", maxValue)
  text = string.gsub(text, "%%percent", percent)
  text = string.gsub(text, "%%stacks", stacks)
  text = string.gsub(text, "%%time", timeText)
  text = string.gsub(text, "%%realhpdeficit", realHpDeficit)
  text = string.gsub(text, "%%realmaxhp", realMaxHp)
  text = string.gsub(text, "%%realhp", realHp)
  text = string.gsub(text, "%%realmanadeficit", realManaDeficit)
  text = string.gsub(text, "%%realmaxmana", realMaxMana)
  text = string.gsub(text, "%%realmana", realManaValue)

  return text
end

-- Source text prefers the first active combat-log-like trigger so multi-trigger auras stay readable.
function TwAuras:GetPreferredSourceText(aura, state)
  local triggerStates = aura and aura.__triggerStates or nil
  local i
  if state and state.source and state.source ~= "" then
    return state.source
  end
  if not triggerStates then
    return ""
  end
  for i = 1, table.getn(triggerStates) do
    local trigger = aura and aura.triggers and aura.triggers[i] or nil
    local triggerState = triggerStates[i]
    if trigger
      and triggerState
      and triggerState.active
      and triggerState.source
      and triggerState.source ~= ""
      and (trigger.type == "combatlog" or trigger.type == "spellcast" or trigger.type == "internalcooldown") then
      return triggerState.source
    end
  end
  return ""
end

-- Runtime keys isolate per-trigger timers inside a shared aura without collisions.
function TwAuras:GetTriggerRuntimeKey(aura, trigger)
  local index = trigger and trigger.__index or 1
  return tostring(aura.id) .. ":" .. tostring(index)
end

-- Aura list order always follows the persistent auraStore order array.
function TwAuras:GetAuraList()
  local store = self:GetAuraStore()
  local auras = {}
  local i
  if not store then
    return auras
  end
  for i = 1, table.getn(store.order) do
    local aura = store.items[tostring(store.order[i])]
    if aura then
      table.insert(auras, aura)
    end
  end
  return auras
end

function TwAuras:GetPlayerClass()
  local _, class = UnitClass("player")
  return class
end

-- Trigger summaries feed the aura list summary line and other human-readable descriptions.
function TwAuras:SummarizeTrigger(trigger)
  local unit = trigger and trigger.unit or "player"
  local op = trigger and trigger.operator or ">="
  local threshold = trigger and trigger.threshold or 0
  local valueMode = trigger and trigger.valueMode or "absolute"
  local suffix = valueMode == "percent" and "%" or ""
  if not trigger or not trigger.type or trigger.type == "none" then
    return ""
  end

  if unit == "partyunit" then
    unit = "party / raid unit"
  end

  if trigger.type == "buff" then
    local ownershipText = trigger.sourceFilter == "player" and "my " or ""
    if trigger.trackMissing then
      return unit .. " missing " .. ownershipText .. "buff " .. (trigger.auraName or "")
    end
    return unit .. " has " .. ownershipText .. "buff " .. (trigger.auraName or "")
  elseif trigger.type == "debuff" then
    local ownershipText = trigger.sourceFilter == "player" and "my " or ""
    if trigger.trackMissing then
      return unit .. " missing " .. ownershipText .. "debuff " .. (trigger.auraName or "")
    end
    return unit .. " has " .. ownershipText .. "debuff " .. (trigger.auraName or "")
  elseif trigger.type == "power" then
    return unit .. " " .. (trigger.powerType or "power") .. " " .. op .. " " .. tostring(threshold) .. suffix
  elseif trigger.type == "combo" then
    return "combo points " .. op .. " " .. tostring(threshold)
  elseif trigger.type == "health" then
    return unit .. " health " .. op .. " " .. tostring(threshold) .. suffix
  elseif trigger.type == "combat" then
    return "player in combat"
  elseif trigger.type == "targetexists" then
    return (trigger.unit or "target") .. " exists"
  elseif trigger.type == "targethostile" then
    return (trigger.unit or "target") .. " is hostile"
  elseif trigger.type == "combatlog" then
    return "combat log " .. (trigger.combatLogEvent or "ANY") .. " matches \"" .. (trigger.combatLogPattern or "") .. "\""
  elseif trigger.type == "spellcast" then
    return (trigger.sourceUnit or "player") .. " spell " .. (trigger.spellName or "") .. " (" .. (trigger.castPhase or "any") .. ")"
  elseif trigger.type == "internalcooldown" then
    if trigger.cooldownState == "ready" then
      return (trigger.procName or "proc") .. " internal cooldown ready"
    end
    return (trigger.procName or "proc") .. " internal cooldown running"
  elseif trigger.type == "cooldown" then
    if trigger.cooldownState == "cooldown" then
      return (trigger.spellName or "") .. " cooldown " .. op .. " " .. tostring(threshold) .. "s"
    end
    return (trigger.spellName or "") .. " ready"
  elseif trigger.type == "spellusable" then
    if trigger.cooldownState == "missingresource" then
      return (trigger.spellName or "") .. " missing resource"
    elseif trigger.cooldownState == "cooldown" then
      return (trigger.spellName or "") .. " on cooldown"
    elseif trigger.cooldownState == "outrange" then
      return (trigger.spellName or "") .. " out of range"
    end
    return (trigger.spellName or "") .. " usable"
  elseif trigger.type == "itemcooldown" then
    if trigger.cooldownState == "cooldown" then
      return "item slot " .. tostring(trigger.itemSlot or 13) .. " cooldown " .. op .. " " .. tostring(threshold) .. "s"
    end
    return "item slot " .. tostring(trigger.itemSlot or 13) .. " ready"
  elseif trigger.type == "form" then
    if trigger.formName and trigger.formName ~= "" then
      return "form is " .. trigger.formName
    end
    return "any active form"
  elseif trigger.type == "casting" then
    local castType = trigger.castType or "any"
    if trigger.spellName and trigger.spellName ~= "" then
      return unit .. " " .. castType .. " " .. trigger.spellName
    end
    return unit .. " " .. castType .. "ing"
  elseif trigger.type == "pet" then
    return "pet exists"
  elseif trigger.type == "zone" then
    if trigger.subZoneName and trigger.subZoneName ~= "" then
      return "sub zone is " .. trigger.subZoneName
    end
    return "zone is " .. (trigger.zoneName or "")
  elseif trigger.type == "spellknown" then
    return "spell known " .. (trigger.spellName or "")
  elseif trigger.type == "actionusable" then
    if trigger.actionState == "missingresource" then
      return "action slot " .. tostring(trigger.actionSlot or 1) .. " missing resource"
    elseif trigger.actionState == "cooldown" then
      return "action slot " .. tostring(trigger.actionSlot or 1) .. " on cooldown"
    elseif trigger.actionState == "outrange" then
      return "action slot " .. tostring(trigger.actionSlot or 1) .. " out of range"
    elseif trigger.requireReady then
      return "action slot " .. tostring(trigger.actionSlot or 1) .. " usable and ready"
    end
    return "action slot " .. tostring(trigger.actionSlot or 1) .. " usable"
  elseif trigger.type == "weaponenchant" then
    if trigger.enchantState == "inactive" then
      return (trigger.weaponHand or "mainhand") .. " weapon not enchanted"
    elseif (trigger.threshold or 0) > 0 then
      return (trigger.weaponHand or "mainhand") .. " weapon enchant " .. op .. " " .. tostring(threshold) .. "s"
    end
    return (trigger.weaponHand or "mainhand") .. " weapon enchanted"
  elseif trigger.type == "itemequipped" then
    return (trigger.itemName or "item") .. " equipped"
  elseif trigger.type == "itemcount" then
    return (trigger.itemName or "item") .. " count " .. op .. " " .. tostring(threshold)
  elseif trigger.type == "range" then
    return (trigger.rangeUnit or "target") .. " " .. ((trigger.rangeState == "outrange" and "out of range") or "in range")
  elseif trigger.type == "threat" then
    return "player " .. ((trigger.threatState == "notaggro" and "does not have") or "has") .. " aggro"
  elseif trigger.type == "playerstate" then
    return "player " .. (trigger.stateName or "mounted")
  elseif trigger.type == "groupstate" then
    return "player in " .. (trigger.groupState or "solo")
  elseif trigger.type == "energytick" then
    if trigger.tickState == "ready" then
      return "energy tick ready"
    end
    return "next energy tick " .. op .. " " .. tostring(threshold) .. "s"
  elseif trigger.type == "manaregen" then
    if trigger.ruleState == "outside" then
      return "outside five second rule"
    end
    return "inside five second rule"
  elseif trigger.type == "always" then
    return "always"
  end

  return trigger.type
end

-- Aura summaries compress display, trigger, and load intent into one short sentence for the editor.
function TwAuras:GetAuraSummary(aura, maxLength)
  local relevant = {}
  local i
  local modeText = " and "
  local displayPart
  local triggerPart
  local loadParts = {}
  local summary

  if not aura then
    return ""
  end

  if aura.triggerMode == "any" then
    modeText = " or "
  elseif aura.triggerMode == "priority" then
    modeText = " then "
  end

  for i = 1, table.getn(aura.triggers or {}) do
    if aura.triggers[i] and aura.triggers[i].type ~= "none" then
      table.insert(relevant, self:SummarizeTrigger(aura.triggers[i]))
    end
  end

  if aura.regionType == "unitframes" then
    displayPart = "Show on party / raid frames"
  else
    displayPart = "Show as " .. (aura.regionType or "icon")
  end
  if table.getn(relevant) > 0 then
    triggerPart = table.concat(relevant, modeText)
    summary = displayPart .. " when " .. triggerPart
  else
    summary = displayPart
  end

  if aura.load then
    if aura.load.class and aura.load.class ~= "" then
      table.insert(loadParts, string.lower(aura.load.class))
    end
    if aura.load.inCombat then
      table.insert(loadParts, "in combat")
    end
    if aura.load.requireTarget then
      table.insert(loadParts, "target required")
    end
    if self:LoadUsesZoneContext(aura.load) then
      local locations = {}
      if aura.load.allowWorld then
        table.insert(locations, "world")
      end
      if aura.load.allowDungeon then
        table.insert(locations, "dungeon")
      end
      if aura.load.allowRaid then
        table.insert(locations, "raid")
      end
      if aura.load.allowPvp then
        table.insert(locations, "battleground")
      end
      if aura.load.allowArena then
        table.insert(locations, "arena")
      end
      if table.getn(locations) == 1 then
        table.insert(loadParts, locations[1] .. " only")
      elseif table.getn(locations) > 1 and table.getn(locations) < 5 then
        table.insert(loadParts, "locations: " .. table.concat(locations, "/"))
      end
      if aura.load.zoneText and aura.load.zoneText ~= "" then
        table.insert(loadParts, "zone contains " .. aura.load.zoneText)
      end
    end
  end

  if table.getn(loadParts) > 0 then
    summary = summary .. ". Load: " .. table.concat(loadParts, ", ")
  end

  return TruncateText(summary, maxLength or 252)
end

-- Load conditions are intentionally simple for the first feature set.
-- Load rules are checked before expensive trigger work whenever possible.
function TwAuras:PassesLoad(cfg)
  if not cfg then
    return true
  end
  local instanceType = self:GetCurrentInstanceType()
  if cfg.inCombat and not UnitAffectingCombat("player") then
    return false
  end
  if cfg.class and cfg.class ~= "" and cfg.class ~= self:GetPlayerClass() then
    return false
  end
  if cfg.requireTarget and not UnitExists("target") then
    return false
  end
  if instanceType == "none" and cfg.allowWorld == false then
    return false
  end
  if instanceType == "party" and cfg.allowDungeon == false then
    return false
  end
  if instanceType == "raid" and cfg.allowRaid == false then
    return false
  end
  if instanceType == "pvp" and cfg.allowPvp == false then
    return false
  end
  if instanceType == "arena" and cfg.allowArena == false then
    return false
  end
  if cfg.zoneText and cfg.zoneText ~= "" then
    local info = self.GetZoneInfo and self:GetZoneInfo() or {
      zoneName = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or "",
      subZoneName = (GetSubZoneText and GetSubZoneText()) or "",
    }
    local wanted = SafeLower(cfg.zoneText)
    if not string.find(SafeLower(info.zoneName), wanted, 1, true) and not string.find(SafeLower(info.subZoneName), wanted, 1, true) then
      return false
    end
  end
  return true
end

-- Debug output is throttled per aura and subsystem so frequent refreshes stay readable.
function TwAuras:DebugLog(aura, area, message)
  local now = GetTime()
  local id = aura and aura.id or "global"
  local key
  local entry
  if not area or area == "" or not message or message == "" then
    return
  end
  self.runtime.debugLog = self.runtime.debugLog or {}
  key = tostring(id) .. ":" .. tostring(area)
  entry = self.runtime.debugLog[key]
  if entry and (now - (entry.lastAt or 0)) < 10 then
    return
  end
  self.runtime.debugLog[key] = {
    lastAt = now,
    message = message,
  }
  self:Print("[" .. string.upper(area) .. "] " .. (aura and aura.name or "TwAuras") .. ": " .. message)
end

function TwAuras:IsAuraDebugEnabled(aura, area)
  return aura and aura.debug and aura.debug[area] and true or false
end

function TwAuras:GetLoadFailureReason(cfg)
  local instanceType = self:GetCurrentInstanceType()
  if cfg.inCombat and not UnitAffectingCombat("player") then
    return "waiting for combat"
  end
  if cfg.class and cfg.class ~= "" and cfg.class ~= self:GetPlayerClass() then
    return "class mismatch"
  end
  if cfg.requireTarget and not UnitExists("target") then
    return "target missing"
  end
  if instanceType == "none" and cfg.allowWorld == false then
    return "world disabled"
  end
  if instanceType == "party" and cfg.allowDungeon == false then
    return "dungeon disabled"
  end
  if instanceType == "raid" and cfg.allowRaid == false then
    return "raid disabled"
  end
  if instanceType == "pvp" and cfg.allowPvp == false then
    return "battleground disabled"
  end
  if instanceType == "arena" and cfg.allowArena == false then
    return "arena disabled"
  end
  if cfg.zoneText and cfg.zoneText ~= "" then
    local info = self.GetZoneInfo and self:GetZoneInfo() or {
      zoneName = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or "",
      subZoneName = (GetSubZoneText and GetSubZoneText()) or "",
    }
    local wanted = SafeLower(cfg.zoneText)
    if not string.find(SafeLower(info.zoneName), wanted, 1, true) and not string.find(SafeLower(info.subZoneName), wanted, 1, true) then
      return "zone text mismatch"
    end
  end
  return "passed"
end

-- Event-key routing lets auras opt into only the WoW state changes they care about.
-- Aura event keys tell the refresh router which auras care about which raw events.
function TwAuras:GetAuraEventKeys(aura)
  -- Event keys may come from explicit user text or from the trigger definitions themselves.
  -- This keeps the default refresh path cheap while still giving advanced users an override.
  local keys = {}
  local explicitKeys = self:SplitList(aura and aura.load and aura.load.updateEvents or "")
  local i

  self:AddEventKey(keys, "world")

  if table.getn(explicitKeys) > 0 then
    for i = 1, table.getn(explicitKeys) do
      self:AddEventKey(keys, explicitKeys[i])
    end
    return keys
  end

  if aura and aura.load then
    if aura.load.inCombat then
      self:AddEventKey(keys, "combat")
    end
    if aura.load.requireTarget then
      self:AddEventKey(keys, "target")
    end
    if self:LoadUsesZoneContext(aura.load) then
      self:AddEventKey(keys, "zone")
    end
  end

  for i = 1, table.getn(aura and aura.triggers or {}) do
    local trigger = aura.triggers[i]
    local triggerKeys = self:GetTriggerEventKeys(trigger)
    local j
    for j = 1, table.getn(triggerKeys or {}) do
      self:AddEventKey(keys, triggerKeys[j])
    end
  end

  if aura and aura.regionType == "unitframes" and self:AuraUsesFrameUnits(aura) then
    self:AddEventKey(keys, "group")
    self:AddEventKey(keys, "combatlog")
  end

  return keys
end

function TwAuras:AuraMatchesEvent(aura, eventName)
  local eventKey = self:NormalizeEventKey(eventName)
  if eventKey == "combatlog" then
    return false
  end
  local keys = self:GetAuraEventKeys(aura)
  return keys[eventKey] and true or false
end

-- This is the main event-side optimization: only matching auras are reevaluated per event.
-- Event routing keeps broad event registration from turning into full-aura refresh spam.
function TwAuras:RefreshAurasForEvent(eventName)
  local auras = self:GetAuraList()
  local i
  for i = 1, table.getn(auras) do
    if self:AuraMatchesEvent(auras[i], eventName) then
      self:RefreshAura(auras[i])
    end
  end
end

-- Runtime timers back estimated durations and combat-log based countdowns.
-- Runtime timer records are created lazily so untimed auras do not accumulate timer tables.
function TwAuras:GetAuraRuntime(id)
  if not self.runtime.timers[id] then
    self.runtime.timers[id] = {}
  end
  return self.runtime.timers[id]
end

-- Aura timers provide a consistent timer source for estimated durations and combat-log states.
function TwAuras:StartAuraTimer(id, duration, icon, label, source, aura)
  local timer = self:GetAuraRuntime(id)
  local now = GetTime()
  if aura then
    self.runtime.timerOwners = self.runtime.timerOwners or {}
    self.runtime.timerOwners[id] = aura
  end
  timer.startTime = now
  timer.duration = tonumber(duration) or 0
  timer.expirationTime = now + timer.duration
  timer.icon = icon
  timer.label = label
  timer.source = source or ""
  aura = aura or (self.runtime.timerOwners and self.runtime.timerOwners[id]) or nil
  if self:IsAuraDebugEnabled(aura, "timer") then
    self:DebugLog(aura, "timer", "started \"" .. tostring(label or id) .. "\" for " .. tostring(timer.duration or 0) .. "s")
  end
end

function TwAuras:StopAuraTimer(id, aura)
  aura = aura or (self.runtime.timerOwners and self.runtime.timerOwners[id]) or nil
  if self:IsAuraDebugEnabled(aura, "timer") then
    self:DebugLog(aura, "timer", "stopped \"" .. tostring((self.runtime.timers[id] and self.runtime.timers[id].label) or id) .. "\"")
  end
  self.runtime.timers[id] = {}
end

function TwAuras:StopAuraTimersForAura(aura)
  if not aura or not aura.triggers then
    return
  end
  local i
  for i = 1, table.getn(aura.triggers) do
    self:StopAuraTimer(self:GetTriggerRuntimeKey(aura, aura.triggers[i]))
  end
  self:ClearAuraAudioState(aura)
end

-- Vanilla APIs do not expose aura names directly, so the tooltip becomes the source of truth.
-- Tooltip extraction is the core Vanilla-compatible aura-name lookup fallback.
function TwAuras:ExtractTooltipAuraName(setter, unit, index)
  if not GameTooltip or not setter then
    return nil
  end
  GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  setter(GameTooltip, unit, index)
  local left = getglobal("GameTooltipTextLeft1")
  local name = left and left:GetText() or nil
  GameTooltip:Hide()
  return name
end

-- Player aura extraction prefers the old GetPlayerBuff/SetPlayerBuff path when available.
function TwAuras:ExtractPlayerBuffAuraName(index, filter)
  local buffIndex
  local left
  local name
  if not GameTooltip or not GameTooltip.SetPlayerBuff or not GetPlayerBuff then
    return nil
  end
  buffIndex = GetPlayerBuff(index, filter or "HELPFUL")
  if buffIndex == nil or buffIndex < 0 then
    return nil
  end
  GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  GameTooltip:SetPlayerBuff(buffIndex)
  left = getglobal("GameTooltipTextLeft1")
  name = left and left:GetText() or nil
  GameTooltip:Hide()
  return name, buffIndex
end


-- Region lifecycle helpers bridge saved aura configs and live frame instances.
-- Region initialization creates one root region per saved aura and keeps them addressable by id.
function TwAuras:InitializeRegions()
  self.regions = {}
  local auras = self:GetAuraList()
  local i
  for i = 1, table.getn(auras) do
    self:NormalizeAuraConfig(auras[i])
    self.regions[auras[i].id] = self:CreateRegion(auras[i])
  end
end

-- A full refresh is used after edits, migrations, and broad state transitions.
function TwAuras:RefreshAll()
  local auras = self:GetAuraList()
  local i
  for i = 1, table.getn(auras) do
    self:RefreshAura(auras[i])
  end
end

-- RefreshAura is the main bridge from saved config to visible output:
-- 1. normalize config
-- 2. enforce load rules
-- 3. evaluate triggers
-- 4. normalize state
-- 5. show, desaturate, or hide the region
function TwAuras:RefreshAura(aura)
  -- This is the main runtime pipeline:
  -- normalize -> load checks -> trigger eval -> state normalize -> condition resolve -> region apply.
  local region = self.regions[aura.id]
  if not region then
    return
  end

  self:NormalizeAuraConfig(aura)

  if region.ApplyUnitStates then
    if self:IsAuraPreviewing(aura.id) then
      aura.__unitStates = self:BuildPreviewUnitFrameStates(aura)
      aura.__state = aura.__unitStates[1] or self:BuildPreviewState(aura)
      self:ClearAuraAudioState(aura)
      local ok, err = pcall(region.ApplyUnitStates, region, aura, aura.__unitStates)
      if not ok then
        if self:IsAuraDebugEnabled(aura, "display") then
          self:DebugLog(aura, "display", "unit frame preview apply error: " .. tostring(err))
        end
        region:Hide()
        self:RefreshDebugObjectDisplays()
        return
      end
      region:Show()
      if self:IsAuraDebugEnabled(aura, "display") then
        self:DebugLog(aura, "display", "previewing " .. tostring(table.getn(aura.__unitStates or {})) .. " unit frame state(s)")
      end
      self:RefreshDebugObjectDisplays()
      return
    end

    if not aura.enabled or not self:PassesLoad(aura.load) then
      aura.__unitStates = {}
      aura.__state = self:NormalizeState(aura, { active = false })
      region:SetInactive(aura)
      region:Hide()
      if self:IsAuraDebugEnabled(aura, "load") then
        self:DebugLog(aura, "load", self:GetLoadFailureReason(aura.load))
      end
      self:RefreshDebugObjectDisplays()
      return
    end
    if self:IsAuraDebugEnabled(aura, "load") then
      self:DebugLog(aura, "load", "passed")
    end

    aura.__unitStates, aura.__state = self:BuildUnitFrameStates(aura)
    self:HandleAuraSoundState(aura, aura.__state)
    if table.getn(aura.__unitStates or {}) > 0 then
      local ok, err = pcall(region.ApplyUnitStates, region, aura, aura.__unitStates)
      if not ok then
        if self:IsAuraDebugEnabled(aura, "display") then
          self:DebugLog(aura, "display", "unit frame apply error: " .. tostring(err))
        end
        region:Hide()
        self:RefreshDebugObjectDisplays()
        return
      end
      region:Show()
      if self:IsAuraDebugEnabled(aura, "display") then
        self:DebugLog(aura, "display", "showing " .. tostring(table.getn(aura.__unitStates or {})) .. " unit frame state(s)")
      end
    else
      region:SetInactive(aura)
      region:Hide()
      if self:IsAuraDebugEnabled(aura, "display") then
        self:DebugLog(aura, "display", "no active unit frame states")
      end
    end
    self:RefreshDebugObjectDisplays()
    return
  end

  if self:IsAuraPreviewing(aura.id) then
    aura.__state = self:BuildPreviewState(aura)
    self:ClearAuraAudioState(aura)
    local ok, err = pcall(region.ApplyState, region, aura, aura.__state)
    if not ok then
      if self:IsAuraDebugEnabled(aura, "display") then
        self:DebugLog(aura, "display", "preview apply error: " .. tostring(err))
      end
      region:Hide()
      self:RefreshDebugObjectDisplays()
      return
    end
    region:Show()
    if self:IsAuraDebugEnabled(aura, "display") then
      self:DebugLog(aura, "display", "preview state active")
    end
    self:RefreshDebugObjectDisplays()
    return
  end

  if not aura.enabled or not self:PassesLoad(aura.load) then
    aura.__state = self:NormalizeState(aura, { active = false })
    region:Hide()
    if self:IsAuraDebugEnabled(aura, "load") then
      self:DebugLog(aura, "load", self:GetLoadFailureReason(aura.load))
    end
    self:RefreshDebugObjectDisplays()
    return
  end
  if self:IsAuraDebugEnabled(aura, "load") then
    self:DebugLog(aura, "load", "passed")
  end

  local state = self:EvaluateTrigger(aura)
  aura.__state = self:ResolveConditionalState(aura, self:NormalizeState(aura, state))
  self:HandleAuraSoundState(aura, aura.__state)

  if aura.__state and aura.__state.active then
    local ok, err = pcall(region.ApplyState, region, aura, aura.__state)
    if not ok then
      if self:IsAuraDebugEnabled(aura, "display") then
        self:DebugLog(aura, "display", "apply error: " .. tostring(err))
      end
      region:Hide()
      self:RefreshDebugObjectDisplays()
      return
    end
    region:Show()
    if self:IsAuraDebugEnabled(aura, "display") then
      self:DebugLog(aura, "display", "showing active " .. tostring(aura.regionType or "icon") .. " region")
    end
  else
    if aura.display.desaturateInactive and region.SetInactive then
      region:SetInactive(aura)
      region:Show()
      if self:IsAuraDebugEnabled(aura, "display") then
        self:DebugLog(aura, "display", "inactive display shown with desaturation")
      end
    else
      region:Hide()
      if self:IsAuraDebugEnabled(aura, "display") then
        self:DebugLog(aura, "display", "hidden because state is inactive")
      end
    end
  end
  self:RefreshDebugObjectDisplays()
end

-- Timed refresh helpers keep countdowns smooth without reevaluating every aura each frame.
-- Dynamic text updates are lightweight compared to full trigger evaluation, so they run separately.
function TwAuras:RefreshDynamicTexts(now)
  local auras = self:GetAuraList()
  local i
  for i = 1, table.getn(auras) do
    local aura = auras[i]
    local region = self.regions[aura.id]
    if region and region:IsShown() and region.RefreshTimeText then
      region:RefreshTimeText(aura, aura.__state, now)
    end
  end
end

-- Timed aura refreshes keep countdown displays responsive even when no new event fires.
function TwAuras:RefreshTimedAuras()
  local auras = self:GetAuraList()
  local i
  for i = 1, table.getn(auras) do
    local aura = auras[i]
    if aura.__state and aura.__state.active and aura.__state.expirationTime then
      self:RefreshAura(aura)
    end
  end
end

-- Audio state is kept per aura so start/loop/stop sounds only fire on state transitions.
function TwAuras:GetAuraAudioState(aura)
  if not aura or not aura.id then
    return {}
  end
  self.runtime.auraAudio = self.runtime.auraAudio or {}
  if not self.runtime.auraAudio[aura.id] then
    self.runtime.auraAudio[aura.id] = {
      wasActive = false,
      nextActiveAt = 0,
    }
  end
  return self.runtime.auraAudio[aura.id]
end

-- Preview state is editor-only and must never leak into saved runtime behavior or audio triggers.
function TwAuras:IsAuraPreviewing(auraId)
  return self.runtime and self.runtime.previewAuras and self.runtime.previewAuras[auraId] and true or false
end

function TwAuras:SetAuraPreviewState(auraId, enabled)
  self.runtime.previewAuras = self.runtime.previewAuras or {}
  if enabled then
    self.runtime.previewAuras[auraId] = true
  else
    self.runtime.previewAuras[auraId] = nil
  end
end

function TwAuras:ClearAuraPreviews()
  self.runtime.previewAuras = {}
end

-- Preview state synthesizes a visible example so users can place and style regions safely.
function TwAuras:BuildPreviewState(aura)
  local previewUnit = aura and aura.trigger and aura.trigger.unit or "player"
  local state = self:NormalizeState(aura, {
    active = true,
    name = aura.name,
    label = aura.name,
    icon = aura.display and aura.display.iconPath or nil,
    unit = previewUnit,
    value = 75,
    maxValue = 100,
    percent = 75,
    stacks = 3,
    duration = 12,
    expirationTime = GetTime() + 12,
  })
  return self:ResolveConditionalState(aura, state)
end

-- Energy tick tracking predicts the next rogue/druid tick from observed resource gains.
function TwAuras:UpdateEnergyTickTracking()
  local now = GetTime()
  local info = self.runtime.energyTick or {}
  local current = UnitMana and UnitMana("player") or 0
  if info.lastValue ~= nil and current > info.lastValue then
    info.lastTickAt = now
    info.nextTickAt = now + 2
  elseif not info.nextTickAt then
    info.nextTickAt = now + 2
  elseif info.nextTickAt < (now - 4) then
    info.nextTickAt = now + 2
  end
  info.lastValue = current
  self.runtime.energyTick = info
end

function TwAuras:GetEnergyTickInfo()
  local info = self.runtime.energyTick or {}
  local now = GetTime()
  if not info.nextTickAt then
    self:UpdateEnergyTickTracking()
    info = self.runtime.energyTick or {}
  end
  return {
    lastValue = info.lastValue or 0,
    lastTickAt = info.lastTickAt,
    nextTickAt = info.nextTickAt,
    remaining = info.nextTickAt and math.max(info.nextTickAt - now, 0) or 0,
    duration = 2,
  }
end

-- The five-second-rule tracker is a lightweight mana-spend timer for healer/caster workflows.
function TwAuras:UpdateManaFiveSecondRuleTracking()
  local now = GetTime()
  local info = self.runtime.manaFiveSecondRule or {}
  local current = UnitMana and UnitMana("player") or 0
  if info.lastValue ~= nil and current < info.lastValue then
    info.endsAt = now + 5
  end
  info.lastValue = current
  self.runtime.manaFiveSecondRule = info
end

function TwAuras:GetManaFiveSecondRuleInfo()
  local info = self.runtime.manaFiveSecondRule or {}
  local now = GetTime()
  return {
    endsAt = info.endsAt,
    remaining = info.endsAt and math.max(info.endsAt - now, 0) or 0,
    active = info.endsAt and info.endsAt > now or false,
    duration = 5,
  }
end

function TwAuras:ClearAuraAudioState(aura)
  if not aura or not aura.id then
    return
  end
  self.runtime.auraAudio = self.runtime.auraAudio or {}
  self.runtime.auraAudio[aura.id] = nil
end

-- Sound values can be ids or file paths, so playback tries both WoW-compatible forms.
function TwAuras:PlayConfiguredSound(soundValue)
  local value = soundValue or ""
  if value == "" then
    return false
  end
  if tonumber(value) and PlaySound then
    PlaySound(tonumber(value))
    return true
  end
  if PlaySoundFile then
    PlaySoundFile(value)
    return true
  end
  return false
end

-- Aura sound handling converts active/inactive transitions into one-shot and looping audio behavior.
function TwAuras:HandleAuraSoundState(aura, state)
  local soundActions = aura and aura.soundActions or nil
  local audioState
  local now
  if not aura or not soundActions then
    return
  end
  audioState = self:GetAuraAudioState(aura)
  now = GetTime()

  if state and state.active then
    if not audioState.wasActive then
      self:PlayConfiguredSound(soundActions.startSound)
      audioState.nextActiveAt = now
    end
    audioState.wasActive = true
  else
    if audioState.wasActive then
      self:PlayConfiguredSound(soundActions.stopSound)
    end
    self:ClearAuraAudioState(aura)
  end
end

-- Loop sounds are polled from OnUpdate because they are time-based rather than event-based.
function TwAuras:UpdateAuraLoopSounds(now)
  local auras = self:GetAuraList()
  local i
  for i = 1, table.getn(auras) do
    local aura = auras[i]
    local audioState = self:GetAuraAudioState(aura)
    local soundActions = aura.soundActions or nil
    if audioState.wasActive
      and aura.__state
      and aura.__state.active
      and soundActions
      and soundActions.activeSound ~= "" then
      if not audioState.nextActiveAt or now >= audioState.nextActiveAt then
        self:PlayConfiguredSound(soundActions.activeSound)
        audioState.nextActiveAt = now + (soundActions.activeInterval or 2)
      end
    end
  end
end

-- Unlocking only affects dragging and visual move handles.
-- Unlocking is a global editor convenience that toggles drag handles on every region.
function TwAuras:SetUnlocked(flag)
  self.db.unlocked = flag and true or false
  local auras = self:GetAuraList()
  local i
  for i = 1, table.getn(auras) do
    local region = self.regions[auras[i].id]
    if region and region.SetMovableState then
      region:SetMovableState(self.db.unlocked)
    end
  end
  self:Print(self.db.unlocked and "unlocked" or "locked")
end


-- Recent lines help players author combat-log triggers without guessing strings.
-- The recent combat-log dump is a live debugging aid for building string-match triggers.
function TwAuras:DebugRecentCombatLog()
  local logs = self.runtime.recentCombatLog
  if table.getn(logs) == 0 then
    self:Print("No combat log lines captured yet.")
    return
  end

  local i
  for i = 1, table.getn(logs) do
    self:Print("[" .. logs[i].time .. "] " .. logs[i].event .. ": " .. logs[i].message)
  end
end

-- Player cast tracking snapshots cast/channel state for triggers and combo-point timing.
function TwAuras:UpdatePlayerCast(eventName, spellName)
  -- Vanilla cast events are sparse, so we cache a tiny player-cast snapshot here that the
  -- generic casting trigger can query later.
  local cast = self.runtime.playerCast or {}
  if eventName == "SPELLCAST_START" or eventName == "SPELLCAST_DELAYED" then
    cast.active = true
    cast.channel = false
    cast.spellName = spellName or cast.spellName
  elseif eventName == "SPELLCAST_CHANNEL_START" or eventName == "SPELLCAST_CHANNEL_UPDATE" then
    cast.active = true
    cast.channel = true
    cast.spellName = spellName or cast.spellName
  elseif eventName == "SPELLCAST_STOP"
      or eventName == "SPELLCAST_FAILED"
      or eventName == "SPELLCAST_INTERRUPTED"
      or eventName == "SPELLCAST_CHANNEL_STOP"
      or eventName == "CURRENT_SPELL_CAST_CHANGED" then
    cast = {}
  end
  self.runtime.playerCast = cast
end

-- Event routing stays centralized so trigger-specific logic lives elsewhere.
-- OnEvent is the central bridge between raw WoW events and TwAuras' higher-level refresh systems.
function TwAuras:OnEvent(eventName, eventUnit)
  -- Event flow stays centralized here so trigger files remain declarative.
  -- Shared runtime snapshots are updated first, then only relevant auras are refreshed.
  if eventName == "PLAYER_ENTER_COMBAT" or eventName == "PLAYER_LEAVE_COMBAT" then
    self:HandleCombatConfigState(eventName)
  end
  if eventName == "VARIABLES_LOADED" then
    self:InitializeDB()
    self:ApplyCombatLogRangeDefaults()
    self:Print("Combat log range set to 200 yards.")
    self:Print("Type /twa to open the config.")
    self.runtime.lastPlayerComboPoints = GetComboPoints("player", "target") or 0
    self:UpdateEnergyTickTracking()
    self:UpdateManaFiveSecondRuleTracking()
    self:InitializeRegions()
    self:RefreshAll()
  elseif eventName == "PLAYER_ENTERING_WORLD" then
    self.runtime.lastPlayerComboPoints = GetComboPoints("player", "target") or 0
    self:UpdateEnergyTickTracking()
    self:UpdateManaFiveSecondRuleTracking()
    if self:AnyAuraUsesEstimatedHealthTokens() then
      self:UpdateEstimatedHealthForUnit("target")
    end
    if self:AnyAuraUsesEstimatedManaTokens() then
      self:UpdateEstimatedManaForUnit("target")
    end
    self:RefreshAll()
  elseif eventName == "PLAYER_AURAS_CHANGED"
      or eventName == "PLAYER_TARGET_CHANGED"
      or eventName == "PLAYER_ENTER_COMBAT"
      or eventName == "PLAYER_LEAVE_COMBAT"
      or eventName == "UNIT_COMBO_POINTS"
      or eventName == "UNIT_ENERGY"
      or eventName == "UNIT_MANA"
      or eventName == "UNIT_RAGE"
      or eventName == "UNIT_HEALTH"
      or eventName == "UNIT_MAXHEALTH"
      or eventName == "SPELLS_CHANGED"
      or eventName == "SPELL_UPDATE_COOLDOWN"
      or eventName == "ACTIONBAR_UPDATE_COOLDOWN"
      or eventName == "BAG_UPDATE_COOLDOWN"
      or eventName == "BAG_UPDATE"
      or eventName == "PLAYER_INVENTORY_CHANGED"
      or eventName == "PLAYER_UPDATE_RESTING"
      or eventName == "PARTY_MEMBERS_CHANGED"
      or eventName == "RAID_ROSTER_UPDATE"
      or eventName == "UPDATE_SHAPESHIFT_FORMS"
      or eventName == "SPELLCAST_START"
      or eventName == "SPELLCAST_STOP"
      or eventName == "SPELLCAST_FAILED"
      or eventName == "SPELLCAST_INTERRUPTED"
      or eventName == "SPELLCAST_DELAYED"
      or eventName == "SPELLCAST_CHANNEL_START"
      or eventName == "SPELLCAST_CHANNEL_STOP"
      or eventName == "SPELLCAST_CHANNEL_UPDATE"
      or eventName == "CURRENT_SPELL_CAST_CHANGED"
      or eventName == "ZONE_CHANGED"
      or eventName == "ZONE_CHANGED_INDOORS"
      or eventName == "ZONE_CHANGED_NEW_AREA"
      or eventName == "ACTIONBAR_SLOT_CHANGED"
      or eventName == "ACTIONBAR_UPDATE_USABLE"
      or eventName == "UNIT_PET" then
    if eventName == "PLAYER_TARGET_CHANGED" or eventName == "UNIT_COMBO_POINTS" then
      self.runtime.lastPlayerComboPoints = GetComboPoints("player", "target") or 0
    end
    if eventName == "UNIT_ENERGY" and eventUnit == "player" then
      self:UpdateEnergyTickTracking()
    end
    if eventName == "UNIT_MANA" and eventUnit == "player" then
      self:UpdateManaFiveSecondRuleTracking()
    end
    if eventName == "PLAYER_TARGET_CHANGED"
      or ((eventName == "UNIT_HEALTH" or eventName == "UNIT_MAXHEALTH") and eventUnit == "target") then
      if self:AnyAuraUsesEstimatedHealthTokens() then
        self:UpdateEstimatedHealthForUnit("target")
      end
    end
    if eventName == "PLAYER_TARGET_CHANGED"
      or ((eventName == "UNIT_MANA" or eventName == "UNIT_ENERGY" or eventName == "UNIT_RAGE") and eventUnit == "target") then
      if self:AnyAuraUsesEstimatedManaTokens() then
        self:UpdateEstimatedManaForUnit("target")
      end
    end
    if string.find(eventName, "SPELLCAST_", 1, true) == 1 or eventName == "CURRENT_SPELL_CAST_CHANGED" then
      self:UpdatePlayerCast(eventName, eventUnit)
    end
    if string.find(eventName, "UNIT_", 1, true) == 1 and eventUnit and eventUnit ~= "player" then
      local isHealthEvent = eventName == "UNIT_HEALTH" or eventName == "UNIT_MAXHEALTH"
      if not (isHealthEvent and eventUnit == "target") and eventName ~= "UNIT_PET" then
        return
      end
    end
    self:RefreshAurasForEvent(eventName)
  elseif string.find(eventName, "CHAT_MSG_", 1, true) == 1 then
    self:RecordCombatLog(eventName, eventUnit)
  end
end
