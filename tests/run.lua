-- TwAuras file version: 0.1.11
local function dirname(path)
  local normalized = string.gsub(path, "\\", "/")
  return string.match(normalized, "^(.*)/[^/]+$") or "."
end

local function join(a, b)
  if string.sub(a, -1) == "/" then
    return a .. b
  end
  return a .. "/" .. b
end

local testDir = dirname(arg and arg[0] or "TwAuras/tests/run.lua")
local addonDir = dirname(testDir)

local stub = dofile(join(testDir, "wow_stub.lua"))
stub.install()

dofile(join(addonDir, "TwAuras.lua"))
dofile(join(addonDir, "Core.lua"))
dofile(join(addonDir, "Triggers.lua"))

local tests = {}

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. " expected=" .. tostring(expected) .. " actual=" .. tostring(actual), 2)
  end
end

local function assert_true(value, message)
  if not value then
    error(message or "expected true", 2)
  end
end

local function add_test(name, fn)
  table.insert(tests, { name = name, fn = fn })
end

local function fresh_runtime()
  -- Tests reset runtime state between cases so timers, cast snapshots, and tracked debuffs do
  -- not leak across assertions.
  TwAuras.runtime.timers = {}
  TwAuras.runtime.recentCombatLog = {}
  TwAuras.runtime.trackedDebuffs = {}
  TwAuras.runtime.pendingDebuffCasts = {}
  TwAuras.runtime.targetHealthEstimates = {}
  TwAuras.runtime.targetManaEstimates = {}
  TwAuras.runtime.lastPlayerComboPoints = 0
  TwAuras.runtime.playerCast = {}
  TwAuras.runtime.auraAudio = {}
  stub.set_spellbook({})
  stub.set_forms({})
  stub.set_zone("Darnassus", "")
  stub.set_action(1, nil)
  stub.set_inventory_item(13, nil)
  stub.set_bag_items({})
  stub.set_weapon_enchant(nil)
  stub.set_player_state({})
  stub.set_group_state({})
  stub.clear_played_sounds()
end

add_test("rip snapshots combo points at cast start", function()
  fresh_runtime()
  stub.set_time(10)
  stub.set_unit("target", { name = "Training Dummy", exists = true })
  stub.set_combo_points(5)
  TwAuras.runtime.lastPlayerComboPoints = 5

  TwAuras:TrackPlayerDebuffsFromCombatLog("You begin to cast Rip.")
  stub.set_time(11)
  TwAuras:TrackPlayerDebuffsFromCombatLog("Training Dummy is afflicted by your Rip.")

  local tracked = TwAuras:GetTrackedDebuff("target", "Rip")
  assert_true(tracked ~= nil, "expected tracked Rip timer")
  assert_equal(tracked.comboPoints, 5, "Rip should keep snapped combo points")
  assert_equal(tracked.duration, 28, "Rip duration should use 5 combo points")
  assert_equal(math.floor(tracked.expirationTime), 39, "Rip expiration time should match snapped duration")
end)

add_test("tracked debuff ticks do not reset an active timer", function()
  fresh_runtime()
  stub.set_time(20)
  stub.set_unit("target", { name = "Target Dummy", exists = true })
  TwAuras:StartTrackedDebuff("Target Dummy", "Moonfire", false)

  local first = TwAuras:GetTrackedDebuff("target", "Moonfire")
  assert_true(first ~= nil, "expected first Moonfire timer")

  stub.advance_time(3)
  TwAuras:StartTrackedDebuff("Target Dummy", "Moonfire", true)

  local second = TwAuras:GetTrackedDebuff("target", "Moonfire")
  assert_true(second ~= nil, "expected Moonfire timer after tick")
  assert_equal(second.expirationTime, first.expirationTime, "periodic ticks should not refresh an active timer")
end)

add_test("debuff trigger reads saved target timer", function()
  fresh_runtime()
  stub.set_time(50)
  stub.set_unit("target", { name = "Raider's Training Dummy", exists = true })
  TwAuras:StartTrackedDebuff("Raider's Training Dummy", "Rupture", false)

  local aura = {
    id = 99,
    name = "Rupture Tracker",
    regionType = "icon",
    triggerMode = "all",
    triggers = {
      {
        __index = 1,
        type = "debuff",
        unit = "target",
        auraName = "Rupture",
        duration = 0,
        useTrackedTimer = true,
        trackMissing = false,
        invert = false,
      },
    },
    display = {
      iconPath = "",
    },
  }
  aura.trigger = aura.triggers[1]

  local state = TwAuras:EvaluateSingleTrigger(aura, aura.trigger)
  assert_true(state.active, "tracked debuff trigger should be active")
  assert_equal(state.duration, 8, "Rupture should use tracked duration")
  assert_true(state.expirationTime ~= nil, "tracked debuff should expose expiration")
end)

add_test("debuff trigger can require cast by player", function()
  fresh_runtime()
  stub.set_time(55)
  stub.set_unit("target", { name = "Enemy Dummy", exists = true })

  local aura = {
    id = 100,
    name = "My Rip Only",
    regionType = "icon",
    triggerMode = "all",
    triggers = {
      {
        __index = 1,
        type = "debuff",
        unit = "target",
        auraName = "Rip",
        sourceFilter = "player",
        duration = 0,
        useTrackedTimer = true,
        trackMissing = false,
        invert = false,
      },
    },
    display = {
      iconPath = "",
    },
  }
  aura.trigger = aura.triggers[1]

  local initialState = TwAuras:EvaluateSingleTrigger(aura, aura.trigger)
  assert_true(not initialState.active, "cast by player debuff should not activate without tracked player application")

  TwAuras:StartTrackedDebuff("Enemy Dummy", "Rip", false)
  local trackedState = TwAuras:EvaluateSingleTrigger(aura, aura.trigger)
  assert_true(trackedState.active, "cast by player debuff should activate from tracked player application")
end)

add_test("refresh timed auras skips expired inactive states", function()
  fresh_runtime()
  local calls = 0
  TwAuras.db = {
    auraStore = {
      version = 1,
      order = {1, 2},
      items = {
        ["1"] = { id = 1, key = "aura_1", schemaVersion = 1, __state = { active = false, expirationTime = 30 } },
        ["2"] = { id = 2, key = "aura_2", schemaVersion = 1, __state = { active = true, expirationTime = 31 } },
      },
    },
  }

  local original = TwAuras.RefreshAura
  TwAuras.RefreshAura = function(_, aura)
    calls = calls + 1
    assert_equal(aura.id, 2, "only active timed aura should be refreshed")
  end

  TwAuras:RefreshTimedAuras()
  TwAuras.RefreshAura = original

  assert_equal(calls, 1, "expected one timed aura refresh")
end)

add_test("spellcast trigger matches player cast success text", function()
  fresh_runtime()
  stub.set_time(60)
  stub.set_unit("player", { name = "Player", exists = true })

  local aura = {
    id = 101,
    name = "Moonfire Cast",
    regionType = "icon",
    triggerMode = "all",
    triggers = {
      {
        __index = 1,
        type = "spellcast",
        spellName = "Moonfire",
        sourceUnit = "player",
        castPhase = "success",
        duration = 2,
        invert = false,
      },
    },
    display = {
      iconPath = "",
    },
  }
  aura.trigger = aura.triggers[1]
  TwAuras.db = {
    auraStore = {
      version = 1,
      order = {101},
      items = {
        ["101"] = aura,
      },
    },
  }
  TwAuras.regions = {
    [101] = {
      ApplyState = function() end,
      Show = function() end,
      Hide = function() end,
    }
  }

  TwAuras:RecordCombatLog("CHAT_MSG_SPELL_SELF_DAMAGE", "You cast Moonfire on Target Dummy.")

  local state = TwAuras:EvaluateSingleTrigger(aura, aura.trigger)
  assert_true(state.active, "spellcast trigger should activate from matching cast text")
  assert_equal(state.duration, 2, "spellcast trigger should keep configured duration")
end)

add_test("target health trigger supports percent mode", function()
  fresh_runtime()
  stub.set_unit("target", {
    name = "Boss Dummy",
    exists = true,
    health = 250,
    maxHealth = 1000,
  })

  local trigger = {
    type = "health",
    unit = "target",
    operator = "<=",
    threshold = 25,
    valueMode = "percent",
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "Boss Health" }, trigger)
  assert_true(state.active, "target health percent trigger should evaluate against percent")
  assert_equal(state.percent, 25, "health percent should be calculated from target values")
end)

add_test("real hp tokens use estimated target health", function()
  fresh_runtime()
  stub.set_unit("target", {
    name = "Boss Dummy",
    exists = true,
    health = 100,
    maxHealth = 100,
  })

  TwAuras:UpdateEstimatedHealthForUnit("target")
  TwAuras:AddObservedDamageToTarget("Boss Dummy", 120)
  stub.set_unit("target", {
    name = "Boss Dummy",
    exists = true,
    health = 98,
    maxHealth = 100,
  })
  TwAuras:UpdateEstimatedHealthForUnit("target")

  local entry = TwAuras:GetEstimatedHealthForUnit("target")
  local rendered = TwAuras:FormatDynamicDisplayText("%realhp/%realmaxhp/%realhpdeficit", {
    name = "Boss HP",
    trigger = { unit = "target" },
  }, {
    unit = "target",
    name = "Boss Dummy",
    label = "Boss Dummy",
  }, GetTime())

  assert_true(entry ~= nil, "expected target health estimate entry")
  assert_equal(entry.estimatedMaxHp, 6000, "estimated max hp should infer from damage and percent drop")
  assert_equal(entry.estimatedCurrentHp, 5880, "estimated current hp should track the latest percent")
  assert_equal(rendered, "5880/6000/120", "real hp tokens should render estimated values")
end)

add_test("real hp tokens prefer exact unit health values when available", function()
  fresh_runtime()
  stub.set_unit("target", {
    name = "Exact Boss",
    exists = true,
    health = 4321,
    maxHealth = 9876,
  })

  local rendered = TwAuras:FormatDynamicDisplayText("%realhp/%realmaxhp/%realhpdeficit", {
    name = "Exact HP",
    trigger = { unit = "target" },
  }, {
    unit = "target",
    name = "Exact Boss",
    label = "Exact Boss",
  }, GetTime())

  assert_equal(rendered, "4321/9876/5555", "real hp tokens should use exact values before estimates")
end)

add_test("real mana tokens use estimated target mana", function()
  fresh_runtime()
  stub.set_unit("target", {
    name = "Mana Dummy",
    exists = true,
    mana = 100,
    maxMana = 100,
  })

  TwAuras:UpdateEstimatedManaForUnit("target")
  TwAuras:AddObservedManaChangeToTarget("Mana Dummy", 80)
  stub.set_unit("target", {
    name = "Mana Dummy",
    exists = true,
    mana = 98,
    maxMana = 100,
  })
  TwAuras:UpdateEstimatedManaForUnit("target")

  local entry = TwAuras:GetEstimatedManaForUnit("target")
  local rendered = TwAuras:FormatDynamicDisplayText("%realmana/%realmaxmana/%realmanadeficit", {
    name = "Mana",
    trigger = { unit = "target" },
  }, {
    unit = "target",
    name = "Mana Dummy",
    label = "Mana Dummy",
  }, GetTime())

  assert_true(entry ~= nil, "expected target mana estimate entry")
  assert_equal(entry.estimatedMaxMana, 4000, "estimated max mana should infer from drain and percent drop")
  assert_equal(entry.estimatedCurrentMana, 3920, "estimated current mana should track the latest percent")
  assert_equal(rendered, "3920/4000/80", "real mana tokens should render estimated values")
end)

add_test("real mana tokens prefer exact unit mana values when available", function()
  fresh_runtime()
  stub.set_unit("target", {
    name = "Exact Mana",
    exists = true,
    mana = 2222,
    maxMana = 3456,
  })

  local rendered = TwAuras:FormatDynamicDisplayText("%realmana/%realmaxmana/%realmanadeficit", {
    name = "Exact Mana",
    trigger = { unit = "target" },
  }, {
    unit = "target",
    name = "Exact Mana",
    label = "Exact Mana",
  }, GetTime())

  assert_equal(rendered, "2222/3456/1234", "real mana tokens should use exact values before estimates")
end)

add_test("normalize aura config migrates legacy single trigger", function()
  local aura = {
    id = 200,
    name = "Legacy Aura",
    enabled = true,
    regionType = "icon",
    triggerMode = "or",
    trigger = {
      type = "debuff",
      unit = "target",
      auraName = "Moonfire",
    },
    display = {},
    load = {},
    position = {},
  }

  TwAuras:NormalizeAuraConfig(aura)
  TwAuras:EnsureSingleBlankTrigger(aura)

  assert_equal(aura.triggerMode, "any", "legacy trigger mode should migrate to any")
  assert_true(aura.triggers ~= nil, "legacy aura should gain triggers table")
  assert_equal(table.getn(aura.triggers), 2, "normalized aura should include one blank trigger")
  assert_equal(aura.triggers[1].type, "debuff", "legacy trigger should become first trigger entry")
  assert_true(aura.triggers[1].useTrackedTimer, "debuff triggers should default to saved timers")
  assert_equal(aura.triggers[1].sourceFilter, "any", "debuff triggers should default to any source")
  assert_equal(aura.triggers[2].type, "none", "normalized aura should keep one trailing blank trigger")
end)

add_test("normalize aura config adds icon hue defaults", function()
  fresh_runtime()
  local aura = {
    id = 500,
    key = "aura_500",
    schemaVersion = 1,
    name = "Hue Defaults",
    regionType = "icon",
    triggers = {
      { type = "always" },
    },
    display = {},
    load = {},
    position = {},
  }

  TwAuras:NormalizeAuraConfig(aura)

  assert_true(aura.display.iconHueEnabled == false, "icon hue should default to disabled")
  assert_equal(aura.display.iconHue, 0, "icon hue should default to zero degrees")
  assert_true(aura.display.showCooldownSwipe == false, "cooldown swipe should default to disabled")
  assert_true(aura.display.showCooldownOverlay == false, "cooldown overlay should default to disabled")
end)

add_test("legacy aura array migrates into aura store", function()
  TwAuras.db = {
    nextId = 2,
    selectedAuraId = 1,
    auras = {
      {
        id = 1,
        name = "Legacy Stored Aura",
        enabled = true,
        regionType = "icon",
        triggerMode = "all",
        triggers = {
          { type = "always" },
        },
        display = {},
        load = {},
        position = {},
      },
    },
  }

  TwAuras:MigrateAuraStore()

  local auras = TwAuras:GetAuraList()
  assert_equal(table.getn(auras), 1, "expected migrated aura in ordered aura store")
  assert_equal(auras[1].id, 1, "migrated aura should keep id")
  assert_equal(auras[1].key, "aura_1", "migrated aura should gain stable backup key")
  assert_true(TwAuras.db.auras == nil, "legacy aura array should be removed after migration")
end)

add_test("aura store order drives returned aura list", function()
  TwAuras.db = {
    nextId = 4,
    selectedAuraId = 2,
    auraStore = {
      version = 1,
      order = {2, 1},
      items = {
        ["1"] = { id = 1, key = "aura_1", schemaVersion = 1, name = "First", display = {}, load = {}, position = {} },
        ["2"] = { id = 2, key = "aura_2", schemaVersion = 1, name = "Second", display = {}, load = {}, position = {} },
      },
    },
  }

  local auras = TwAuras:GetAuraList()
  assert_equal(table.getn(auras), 2, "ordered aura list should include both stored auras")
  assert_equal(auras[1].id, 2, "aura list should respect stored order")
  assert_equal(auras[2].id, 1, "aura list should respect stored order")
end)

add_test("aura summary describes triggers and load concisely", function()
  local aura = {
    id = 300,
    name = "Rip Ready",
    regionType = "icon",
    triggerMode = "all",
    triggers = {
      { type = "debuff", unit = "target", auraName = "Rip", trackMissing = true },
      { type = "power", unit = "player", powerType = "energy", operator = ">=", threshold = 30, valueMode = "absolute" },
      { type = "combo", operator = ">=", threshold = 4 },
    },
    load = {
      class = "DRUID",
      inCombat = true,
      requireTarget = true,
    },
  }

  local summary = TwAuras:GetAuraSummary(aura, 252)
  assert_true(string.find(summary, "Show as icon when", 1, true) ~= nil, "summary should describe display and trigger flow")
  assert_true(string.find(summary, "target missing debuff Rip", 1, true) ~= nil, "summary should include trigger details")
  assert_true(string.find(summary, "Load: druid, in combat, target required", 1, true) ~= nil, "summary should include load details")
end)

add_test("aura summary truncates with ellipsis at max length", function()
  local aura = {
    id = 301,
    name = "Long Summary",
    regionType = "icon",
    triggerMode = "all",
    triggers = {
      { type = "combatlog", combatLogEvent = "CHAT_MSG_SPELL_SELF_DAMAGE", combatLogPattern = "very long repeated pattern very long repeated pattern very long repeated pattern very long repeated pattern very long repeated pattern" },
      { type = "spellcast", sourceUnit = "player", spellName = "Extremely Long Spell Name For Summary Coverage", castPhase = "success" },
      { type = "zone", zoneName = "A Very Long Zone Name For Summary Coverage", subZoneName = "Another Very Long Sub Zone Name", matchSubZone = true },
    },
    load = {
      class = "DRUID",
      inCombat = true,
      requireTarget = true,
    },
  }

  local summary = TwAuras:GetAuraSummary(aura, 252)
  assert_true(string.len(summary) <= 252, "summary should respect max length")
  assert_true(string.sub(summary, -3) == "...", "truncated summary should end with ellipsis")
end)

add_test("tracked debuff fades clear saved timer", function()
  fresh_runtime()
  stub.set_time(80)
  stub.set_unit("target", { name = "Raid Boss", exists = true })

  TwAuras:StartTrackedDebuff("Raid Boss", "Moonfire", false)
  assert_true(TwAuras:GetTrackedDebuff("target", "Moonfire") ~= nil, "expected saved debuff before fade")

  TwAuras:TrackPlayerDebuffsFromCombatLog("Your Moonfire fades from Raid Boss.")
  assert_true(TwAuras:GetTrackedDebuff("target", "Moonfire") == nil, "saved debuff should clear on fade")
end)

add_test("spell cooldown trigger sees ready state", function()
  fresh_runtime()
  stub.set_spellbook({
    { name = "Rip", texture = "Interface\\Icons\\Ability_GhoulFrenzy" },
  })
  stub.set_spell_cooldown(1, { start = 0, duration = 0, enabled = 1 })

  local trigger = {
    type = "cooldown",
    spellName = "Rip",
    cooldownState = "ready",
    operator = ">=",
    threshold = 0,
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "Rip Ready" }, trigger)
  assert_true(state.active, "cooldown trigger should be active when spell is ready")
  assert_equal(state.icon, "Interface\\Icons\\Ability_GhoulFrenzy", "cooldown trigger should expose spell icon")
end)

add_test("spell cooldown trigger sees active cooldown", function()
  fresh_runtime()
  stub.set_time(100)
  stub.set_spellbook({
    { name = "Tiger's Fury", texture = "Interface\\Icons\\Ability_Mount_JungleTiger" },
  })
  stub.set_spell_cooldown(1, { start = 95, duration = 10, enabled = 1 })

  local trigger = {
    type = "cooldown",
    spellName = "Tiger's Fury",
    cooldownState = "cooldown",
    operator = ">=",
    threshold = 4,
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "Tiger's Fury CD" }, trigger)
  assert_true(state.active, "cooldown trigger should match active spell cooldown")
  assert_equal(math.floor(state.value), 5, "cooldown trigger should track remaining seconds")
end)

add_test("form trigger matches active shapeshift form", function()
  fresh_runtime()
  stub.set_forms({
    { name = "Bear Form", icon = "Interface\\Icons\\Ability_Racial_BearForm", active = true, castable = true },
  })

  local trigger = {
    type = "form",
    formName = "Bear Form",
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "Bear" }, trigger)
  assert_true(state.active, "form trigger should match active form")
  assert_equal(state.label, "Bear Form", "form trigger should use form name")
end)

add_test("zone trigger can match sub zone", function()
  fresh_runtime()
  stub.set_zone("Stormwind City", "Trade District")

  local trigger = {
    type = "zone",
    zoneName = "Trade District",
    matchSubZone = true,
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "Trade District" }, trigger)
  assert_true(state.active, "zone trigger should match sub zone when enabled")
end)

add_test("spell known trigger checks spellbook", function()
  fresh_runtime()
  stub.set_spellbook({
    { name = "Moonfire", texture = "Interface\\Icons\\Spell_Nature_StarFall" },
  })

  local trigger = {
    type = "spellknown",
    spellName = "Moonfire",
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "Moonfire Known" }, trigger)
  assert_true(state.active, "spell known trigger should match spellbook entry")
end)

add_test("action usable trigger honors ready requirement", function()
  fresh_runtime()
  stub.set_action(4, {
    usable = true,
    notEnoughMana = false,
    start = 0,
    duration = 0,
    enabled = 1,
    texture = "Interface\\Icons\\Ability_Rogue_SliceDice",
  })

  local trigger = {
    type = "actionusable",
    actionSlot = 4,
    requireReady = true,
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "Action Ready" }, trigger)
  assert_true(state.active, "action usable trigger should be active when slot is usable and ready")
  assert_equal(state.icon, "Interface\\Icons\\Ability_Rogue_SliceDice", "action trigger should expose action icon")
end)

add_test("action usable trigger can match missing resource", function()
  fresh_runtime()
  stub.set_action(2, {
    usable = false,
    notEnoughMana = true,
    start = 0,
    duration = 0,
    enabled = 1,
    texture = "Interface\\Icons\\Spell_Shadow_BurningSpirit",
  })

  local trigger = {
    type = "actionusable",
    actionSlot = 2,
    actionState = "missingresource",
    requireReady = true,
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "Missing Resource" }, trigger)
  assert_true(state.active, "action usable trigger should match missing resource state")
end)

add_test("casting trigger reads snapped player cast state", function()
  fresh_runtime()
  TwAuras.runtime.playerCast = {
    active = true,
    channel = false,
    spellName = "Healing Touch",
  }

  local trigger = {
    type = "casting",
    unit = "player",
    spellName = "Healing Touch",
    castType = "cast",
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "Casting" }, trigger)
  assert_true(state.active, "casting trigger should use player runtime cast state")
end)

add_test("weapon enchant trigger detects active main hand enchant", function()
  fresh_runtime()
  stub.set_weapon_enchant({
    hasMain = 1,
    mainExpiration = 120000,
    mainCharges = 0,
    hasOff = nil,
    offExpiration = 0,
    offCharges = 0,
  })

  local trigger = {
    type = "weaponenchant",
    weaponHand = "mainhand",
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "Poison" }, trigger)
  assert_true(state.active, "weapon enchant trigger should detect active enchant")
  assert_equal(math.floor(state.value), 120, "weapon enchant trigger should expose remaining seconds")
end)

add_test("item count trigger reads bag totals", function()
  fresh_runtime()
  stub.set_bag_items({
    [0] = {
      { name = "Flash Powder", count = 12 },
      { name = "Flash Powder", count = 8 },
    },
  })

  local trigger = {
    type = "itemcount",
    itemName = "Flash Powder",
    operator = ">=",
    threshold = 20,
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "Powder" }, trigger)
  assert_true(state.active, "item count trigger should compare inventory totals")
  assert_equal(state.value, 20, "item count trigger should sum bag stacks")
end)

add_test("range trigger can use interact distance", function()
  fresh_runtime()
  stub.set_unit("target", {
    name = "Nearby Dummy",
    exists = true,
    interactDistance = {
      [3] = true,
    },
  })

  local trigger = {
    type = "range",
    rangeUnit = "target",
    rangeMode = "interact",
    interactDistance = 3,
    rangeState = "inrange",
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "Range" }, trigger)
  assert_true(state.active, "range trigger should use interact distance checks")
end)

add_test("player state trigger detects stealth", function()
  fresh_runtime()
  stub.set_player_state({ stealthed = true })

  local trigger = {
    type = "playerstate",
    stateName = "stealth",
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "Stealth" }, trigger)
  assert_true(state.active, "player state trigger should detect stealth")
end)

add_test("group state trigger detects party membership", function()
  fresh_runtime()
  stub.set_group_state({ party = 2, raid = 0 })

  local trigger = {
    type = "groupstate",
    groupState = "party",
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "Party" }, trigger)
  assert_true(state.active, "group state trigger should detect party membership")
end)

add_test("combat log skips real hp estimation when no aura uses the tokens", function()
  fresh_runtime()
  TwAuras.db = {
    auraStore = {
      version = 1,
      order = {1},
      items = {
        ["1"] = {
          id = 1,
          key = "aura_1",
          schemaVersion = 1,
          name = "No Real HP",
          regionType = "icon",
          triggerMode = "all",
          triggers = {
            { __index = 1, type = "always" },
          },
          display = {
            labelText = "%name",
            timerText = "%time",
            valueText = "%value",
          },
          load = {},
          position = {},
        },
      },
    },
  }

  TwAuras:RecordCombatLog("CHAT_MSG_SPELL_SELF_DAMAGE", "You hit Training Dummy for 120.")
  assert_true(next(TwAuras.runtime.targetHealthEstimates) == nil, "target hp estimator should stay idle when no aura uses the tokens")
end)

add_test("combat log skips real mana estimation when no aura uses the tokens", function()
  fresh_runtime()
  TwAuras.db = {
    auraStore = {
      version = 1,
      order = {1},
      items = {
        ["1"] = {
          id = 1,
          key = "aura_1",
          schemaVersion = 1,
          name = "No Real Mana",
          regionType = "icon",
          triggerMode = "all",
          triggers = {
            { __index = 1, type = "always" },
          },
          display = {
            labelText = "%name",
            timerText = "%time",
            valueText = "%value",
          },
          load = {},
          position = {},
        },
      },
    },
  }

  TwAuras:RecordCombatLog("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Viper Sting drains 80 Mana from Mana Dummy.")
  assert_true(next(TwAuras.runtime.targetManaEstimates) == nil, "target mana estimator should stay idle when no aura uses the tokens")
end)

add_test("aura lifecycle sounds play on start loop and stop", function()
  fresh_runtime()
  stub.set_time(200)

  local aura = {
    id = 600,
    key = "aura_600",
    schemaVersion = 1,
    name = "Sound Aura",
    soundActions = {
      startSound = "Sound\\Interface\\RaidWarning.wav",
      activeSound = "567",
      activeInterval = 1,
      stopSound = "Sound\\Interface\\MapPing.wav",
    },
    __state = {
      active = false,
    },
  }
  TwAuras.db = {
    auraStore = {
      version = 1,
      order = {600},
      items = {
        ["600"] = aura,
      },
    },
  }

  TwAuras:HandleAuraSoundState(aura, { active = true })
  local played = stub.get_played_sounds()
  assert_equal(table.getn(played), 1, "start transition should play one sound")
  assert_equal(played[1], "Sound\\Interface\\RaidWarning.wav", "start transition should play configured start sound")

  stub.advance_time(1)
  TwAuras.runtime.auraAudio[aura.id] = TwAuras.runtime.auraAudio[aura.id] or { wasActive = true, nextActiveAt = GetTime() }
  aura.__state = { active = true }
  TwAuras:UpdateAuraLoopSounds(GetTime())
  played = stub.get_played_sounds()
  assert_equal(table.getn(played), 2, "active loop should add one repeated sound")
  assert_equal(played[2], "567", "numeric active sound ids should route through PlaySound")

  aura.__state = { active = false }
  TwAuras:HandleAuraSoundState(aura, { active = false })
  played = stub.get_played_sounds()
  assert_equal(table.getn(played), 3, "stop transition should add one sound")
  assert_equal(played[3], "Sound\\Interface\\MapPing.wav", "stop transition should play configured stop sound")

  stub.advance_time(2)
  TwAuras:UpdateAuraLoopSounds(GetTime())
  played = stub.get_played_sounds()
  assert_equal(table.getn(played), 3, "stop transition should also prevent any future repeat sounds")
end)

local passed = 0
local failed = 0
local i

for i = 1, table.getn(tests) do
  local ok, err = pcall(tests[i].fn)
  if ok then
    io.write("PASS  " .. tests[i].name .. "\n")
    passed = passed + 1
  else
    io.write("FAIL  " .. tests[i].name .. "\n")
    io.write("      " .. tostring(err) .. "\n")
    failed = failed + 1
  end
end

io.write("\n")
io.write("Result: " .. passed .. " passed, " .. failed .. " failed\n")

if failed > 0 then
  os.exit(1)
end
