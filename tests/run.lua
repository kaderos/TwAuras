-- TwAuras file version: 0.1.39
-- The harness is intentionally tiny: load the addon under a stubbed WoW API and assert behavior.
local function dirname(path)
  local normalized = string.gsub(path, "\\", "/")
  return string.match(normalized, "^(.*)/[^/]+$") or "."
end

-- Path joining keeps the test runner independent of the current working directory.
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
dofile(join(addonDir, "Regions.lua"))
dofile(join(addonDir, "Config.lua"))

local tests = {}

-- Assertions stay minimal on purpose so failures read more like normal Lua errors.
local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. " expected=" .. tostring(expected) .. " actual=" .. tostring(actual), 2)
  end
end

-- Truthiness checks are split out so tests remain readable without a larger framework.
local function assert_true(value, message)
  if not value then
    error(message or "expected true", 2)
  end
end

-- Global API overrides let negative-compat tests simulate missing Turtle/Vanilla APIs safely.
local function with_global_overrides(overrides, fn)
  local previous = {}
  local key
  local ok
  local err
  for key, value in pairs(overrides or {}) do
    previous[key] = _G[key]
    _G[key] = value
  end
  ok, err = pcall(fn)
  for key, value in pairs(previous) do
    _G[key] = value
  end
  if not ok then
    error(err, 2)
  end
end

-- Replay steps keep event-ordering tests deterministic and easy to read.
local function run_replay_steps(steps)
  local i
  for i = 1, table.getn(steps or {}) do
    local step = steps[i]
    if step.at ~= nil then
      stub.set_time(step.at)
    end
    if step.run then
      step.run()
    end
  end
end

-- Tests are registered up front, then executed in order at the bottom of the file.
local function add_test(name, fn)
  table.insert(tests, { name = name, fn = fn })
end

-- Each test starts from a clean addon runtime so stateful systems do not bleed between cases.
local function fresh_runtime()
  -- Tests reset runtime state between cases so timers, cast snapshots, and tracked debuffs do
  -- not leak across assertions.
  TwAuras.runtime.timers = {}
  TwAuras.runtime.recentCombatLog = {}
  TwAuras.runtime.trackedBuffs = {}
  TwAuras.runtime.trackedDebuffs = {}
  TwAuras.runtime.pendingBuffCasts = {}
  TwAuras.runtime.pendingDebuffCasts = {}
  TwAuras.runtime.targetHealthEstimates = {}
  TwAuras.runtime.targetManaEstimates = {}
  TwAuras.runtime.lastPlayerComboPoints = 0
  TwAuras.runtime.playerCast = {}
  TwAuras.runtime.auraAudio = {}
  TwAuras.runtime.debugLog = {}
  TwAuras.runtime.previewAuras = {}
  TwAuras.runtime.previewChoices = {}
  TwAuras.runtime.energyTick = {}
  TwAuras.runtime.manaFiveSecondRule = {}
  TwAuras.regions = {}
  TwAuras.configFrame = nil
  TwAuras.objectTrackerFrame = nil
  stub.clear_messages()
  stub.set_spellbook({})
  stub.set_unit_buffs("player", {})
  stub.set_unit_debuffs("target", {})
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
  stub.set_unit("player", { name = "Tester", exists = true })

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
  assert_equal(trackedState.source, "Tester", "cast by player debuff should expose the player as source")
end)

add_test("buff trigger can require cast by player", function()
  fresh_runtime()
  stub.set_time(56)
  stub.set_unit("party1", {
    name = "Tank",
    exists = true,
    buffs = {
      { name = "Rejuvenation", texture = "Interface\\Icons\\Spell_Nature_Rejuvenation", count = 1 },
    },
  })
  stub.set_unit("player", { name = "Tester", exists = true })

  local aura = {
    id = 101,
    name = "My Rejuv Only",
    regionType = "icon",
    triggerMode = "all",
    triggers = {
      {
        __index = 1,
        type = "buff",
        unit = "party1",
        auraName = "Rejuvenation",
        sourceFilter = "player",
        duration = 0,
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
  assert_true(not initialState.active, "cast by player buff should not activate without tracked player application")

  TwAuras:StartTrackedBuff("Tank", "Rejuvenation")
  local trackedState = TwAuras:EvaluateSingleTrigger(aura, aura.trigger)
  assert_true(trackedState.active, "cast by player buff should activate from tracked player application")
  assert_equal(trackedState.source, "Tester", "cast by player buff should expose the player as source")
end)

add_test("combat log can track player-cast buffs for ownership", function()
  fresh_runtime()
  stub.set_time(57)
  stub.set_unit("player", { name = "Tester", exists = true })

  TwAuras:RecordCombatLog("CHAT_MSG_SPELL_SELF_BUFF", "You cast Rejuvenation on Tank.")
  local direct = TwAuras.runtime.trackedBuffs[TwAuras:GetTrackedBuffKey("Tank", "Rejuvenation")]
  assert_true(direct ~= nil, "combat log should create a tracked buff record for cast by player ownership")
  assert_equal(direct.source, "Tester", "tracked buff record should keep the player as source")
end)

add_test("player aura scan prefers old player buff api with fallback support", function()
  fresh_runtime()
  stub.set_unit("player", { name = "Tester", exists = true })
  stub.set_unit_buffs("player", {
    { name = "Clearcasting", texture = "Interface\\Icons\\Spell_Shadow_ManaBurn", count = 1 },
  })

  local state = TwAuras:ScanAura("player", "Clearcasting", false)
  assert_true(state.active, "player aura scan should find buffs through the old player buff api path")
  assert_equal(state.name, "Clearcasting", "player aura scan should recover the tooltip aura name")
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

add_test("internal cooldown starts from player buff gain edge", function()
  fresh_runtime()
  stub.set_time(300)
  local aura = {
    id = 700,
    key = "aura_700",
    schemaVersion = 1,
    name = "Blackout Truncheon ICD",
    regionType = "icon",
    triggerMode = "all",
    triggers = {
      {
        __index = 1,
        type = "internalcooldown",
        procName = "Blackout Truncheon",
        detectMode = "buff",
        duration = 45,
        cooldownState = "cooldown",
      },
    },
    display = {
      iconPath = "",
    },
  }
  aura.trigger = aura.triggers[1]

  stub.set_unit_buffs("player", {
    { name = "Blackout Truncheon", texture = "Interface\\Icons\\INV_Mace_13", count = 0 },
  })
  local state = TwAuras:EvaluateSingleTrigger(aura, aura.trigger)
  assert_true(state.active, "internal cooldown should start when the player gains the proc buff")
  assert_equal(state.duration, 45, "internal cooldown should keep configured duration")

  stub.advance_time(5)
  local laterState = TwAuras:EvaluateSingleTrigger(aura, aura.trigger)
  assert_true(laterState.active, "internal cooldown should remain active while the timer is running")
  assert_equal(math.floor(laterState.expirationTime - GetTime()), 40, "internal cooldown should count down over time")
end)

add_test("internal cooldown can show ready after expiry", function()
  fresh_runtime()
  stub.set_time(400)
  local aura = {
    id = 701,
    key = "aura_701",
    schemaVersion = 1,
    name = "Proc Ready",
    regionType = "icon",
    triggerMode = "all",
    triggers = {
      {
        __index = 1,
        type = "internalcooldown",
        procName = "Mystic Proc",
        detectMode = "combatlog",
        combatLogPattern = "You gain Mystic Proc.",
        duration = 10,
        cooldownState = "ready",
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
      order = {701},
      items = { ["701"] = aura },
    },
  }
  TwAuras.regions = {
    [701] = {
      ApplyState = function() end,
      Show = function() end,
      Hide = function() end,
    }
  }

  TwAuras:RecordCombatLog("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS", "You gain Mystic Proc.")
  local coolingState = TwAuras:EvaluateSingleTrigger(aura, aura.trigger)
  assert_true(not coolingState.active, "ready-mode internal cooldown should be false while cooling")

  stub.advance_time(11)
  local readyState = TwAuras:EvaluateSingleTrigger(aura, aura.trigger)
  assert_true(readyState.active, "ready-mode internal cooldown should become true after expiry")
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

add_test("split list supports clients without string.gmatch", function()
  fresh_runtime()
  local originalGmatch = string.gmatch
  local originalGfind = string.gfind
  local ok
  local err

  string.gmatch = nil
  string.gfind = originalGfind or originalGmatch

  ok, err = pcall(function()
    local items = TwAuras:SplitList(" player , target, combat ")
    assert_equal(table.getn(items), 3, "split list should still parse three comma-separated values")
    assert_equal(items[1], "player", "split list should trim leading whitespace")
    assert_equal(items[2], "target", "split list should keep middle values")
    assert_equal(items[3], "combat", "split list should trim trailing whitespace")
  end)

  string.gmatch = originalGmatch
  string.gfind = originalGfind

  if not ok then
    error(err)
  end
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

add_test("apply editor ignores re-entrant callback calls", function()
  fresh_runtime()
  local originalGetSelectedAura = TwAuras.GetSelectedAura
  local ok
  local err

  TwAuras.GetSelectedAura = function()
    return { id = 1, name = "Reentry", display = {}, load = {}, position = {}, triggers = { { type = "none" } } }
  end
  TwAuras.configFrame = {
    __applyingEditor = true,
  }

  ok, err = pcall(function()
    TwAuras:ApplyEditorToSelectedAura(true)
  end)

  TwAuras.GetSelectedAura = originalGetSelectedAura
  TwAuras.configFrame = nil

  if not ok then
    error(err)
  end
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

add_test("variables loaded applies combat log range defaults", function()
  fresh_runtime()
  local messages
  local i
  local sawRangeMessage = false
  local sawConfigMessage = false

  TwAuras:OnEvent("VARIABLES_LOADED")

  assert_equal(stub.get_cvar("CombatLogRangeParty"), "200", "party combat log range should be set to 200")
  assert_equal(stub.get_cvar("CombatLogRangePartyPet"), "200", "party pet combat log range should be set to 200")
  assert_equal(stub.get_cvar("CombatLogRangeFriendlyPlayers"), "200", "friendly player combat log range should be set to 200")
  assert_equal(stub.get_cvar("CombatLogRangeFriendlyPlayersPets"), "200", "friendly player pet combat log range should be set to 200")
  assert_equal(stub.get_cvar("CombatLogRangeHostilePlayers"), "200", "hostile player combat log range should be set to 200")
    assert_equal(stub.get_cvar("CombatLogRangeHostilePlayersPets"), "200", "hostile player pet combat log range should be set to 200")
    assert_equal(stub.get_cvar("CombatLogRangeCreature"), "200", "creature combat log range should be set to 200")
    messages = stub.get_messages()
    for i = 1, table.getn(messages) do
      if string.find(messages[i] or "", "Combat log range set to 200 yards.", 1, true) ~= nil then
        sawRangeMessage = true
      end
      if string.find(messages[i] or "", "Type /twa to open the config.", 1, true) ~= nil then
        sawConfigMessage = true
      end
    end
    assert_true(sawRangeMessage, "startup should announce the combat log range change")
    assert_true(sawConfigMessage, "startup should remind the user how to open config")
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

add_test("duplicate aura record gets a new id and numbered collision-safe name", function()
  fresh_runtime()
  TwAuras.db = {
    nextId = 3,
    auraStore = {
      version = 1,
      order = {1, 2},
      items = {
        ["1"] = { id = 1, key = "aura_1", schemaVersion = 1, name = "Rip", triggers = {}, display = {}, load = {}, position = {}, conditions = {}, soundActions = {} },
        ["2"] = { id = 2, key = "aura_2", schemaVersion = 1, name = "Rip1", triggers = {}, display = {}, load = {}, position = {}, conditions = {}, soundActions = {} },
      },
    },
  }

  local duplicate = TwAuras:DuplicateAuraRecord(TwAuras.db.auraStore.items["1"])
  assert_equal(duplicate.id, 3, "duplicate should get the next available id")
  assert_equal(duplicate.key, "aura_3", "duplicate should get a fresh storage key")
  assert_equal(duplicate.name, "Rip2", "duplicate should pick the next numbered name")
end)

add_test("create aura template picks a collision-safe new aura name", function()
  fresh_runtime()
  TwAuras.db = {
    nextId = 3,
    auraStore = {
      version = 1,
      order = {1, 2},
      items = {
        ["1"] = { id = 1, key = "aura_1", schemaVersion = 1, name = "New Aura", triggers = {}, display = {}, load = {}, position = {} },
        ["2"] = { id = 2, key = "aura_2", schemaVersion = 1, name = "New Aura1", triggers = {}, display = {}, load = {}, position = {} },
      },
    },
  }

  local aura = TwAuras:CreateAuraTemplate()
  assert_equal(aura.name, "New Aura2", "new aura creation should avoid existing display-name collisions")
end)

add_test("unique aura naming ignores the aura currently being renamed", function()
  fresh_runtime()
  TwAuras.db = {
    nextId = 3,
    auraStore = {
      version = 1,
      order = {1, 2},
      items = {
        ["1"] = {
          id = 1,
          key = "aura_1",
          schemaVersion = 1,
          name = "Rip",
          enabled = true,
          regionType = "icon",
          triggerMode = "all",
          triggers = {
            { type = "always" },
          },
          conditions = {},
          display = {},
          load = {},
          position = {},
          soundActions = {},
        },
        ["2"] = {
          id = 2,
          key = "aura_2",
          schemaVersion = 1,
          name = "Moonfire",
          enabled = true,
          regionType = "icon",
          triggerMode = "all",
          triggers = {
            { type = "always" },
          },
          conditions = {},
          display = {},
          load = {},
          position = {},
          soundActions = {},
        },
      },
    },
  }

  assert_equal(TwAuras:GetUniqueAuraName("Rip", 2), "Rip1", "renaming to an existing name should get a numbered suffix")
  assert_equal(TwAuras:GetUniqueAuraName("Rip1", 2), "Rip1", "the current aura should not collide with its own existing unique name")
end)

add_test("object summary counts saved and active runtime objects", function()
  fresh_runtime()
  stub.set_time(100)
  TwAuras.db = {
    auraStore = {
      version = 1,
      order = {1, 2},
      items = {
        ["1"] = {
          id = 1,
          key = "aura_1",
          schemaVersion = 1,
          name = "Aura One",
          triggers = {
            { type = "buff" },
            { type = "none" },
          },
          conditions = {
            { check = "active" },
          },
          display = {},
          load = {},
          position = {},
        },
        ["2"] = {
          id = 2,
          key = "aura_2",
          schemaVersion = 1,
          name = "Aura Two",
          triggers = {
            { type = "debuff" },
            { type = "power" },
          },
          conditions = {
            { check = "value" },
            { check = "percent" },
          },
          display = {},
          load = {},
          position = {},
          __unitStates = {
            { unit = "party1", active = true },
            { unit = "party2", active = true },
          },
        },
      },
    },
  }
  TwAuras.regions = {
    [1] = {},
    [2] = {},
  }
  TwAuras.runtime.timers = {
    one = { duration = 10, expirationTime = 110 },
    expired = { duration = 5, expirationTime = 99 },
  }
  TwAuras.runtime.trackedBuffs = {
    one = { name = "Rejuvenation", startTime = 100 },
  }
  TwAuras.runtime.trackedDebuffs = {
    one = { name = "Rip", expirationTime = 108 },
    expired = { name = "Moonfire", expirationTime = 99 },
  }

  local total = TwAuras:GetObjectSummaryCount()
  assert_equal(total, 15, "object summary should count auras, triggers, conditions, regions, active timers, tracked entries, and overlays")
end)

add_test("object summary decreases as runtime objects expire or clear", function()
  fresh_runtime()
  stub.set_time(200)
  TwAuras.db = {
    auraStore = {
      version = 1,
      order = {1},
      items = {
        ["1"] = {
          id = 1,
          key = "aura_1",
          schemaVersion = 1,
          name = "Aura One",
          triggers = {
            { type = "buff" },
          },
          conditions = {},
          display = {},
          load = {},
          position = {},
          __unitStates = {
            { unit = "party1", active = true },
          },
        },
      },
    },
  }
  TwAuras.regions = {
    [1] = {},
  }
  TwAuras.runtime.timers = {
    one = { duration = 10, expirationTime = 205 },
  }
  TwAuras.runtime.trackedBuffs = {
    one = { name = "Rejuvenation", startTime = 200 },
  }
  TwAuras.runtime.trackedDebuffs = {
    one = { name = "Rip", expirationTime = 204 },
  }

  assert_equal(TwAuras:GetObjectSummaryCount(), 7, "initial object summary should include active runtime state")

  stub.set_time(206)
  TwAuras.db.auraStore.items["1"].__unitStates = {}
  TwAuras.runtime.trackedBuffs = {}
  assert_equal(TwAuras:GetObjectSummaryCount(), 3, "expired timers, expired debuffs, cleared buffs, and cleared overlays should drop out of the summary")
end)

add_test("object summary load color uses green yellow and red bands", function()
  fresh_runtime()
  local r1, g1, b1 = TwAuras:GetObjectSummaryLoadColor(150)
  local r2, g2, b2 = TwAuras:GetObjectSummaryLoadColor(200)
  local r3, g3, b3 = TwAuras:GetObjectSummaryLoadColor(300)

  assert_equal(string.format("%.2f/%.2f/%.2f", r1, g1, b1), "0.25/0.95/0.35", "low object counts should be green")
  assert_equal(string.format("%.2f/%.2f/%.2f", r2, g2, b2), "1.00/0.82/0.20", "mid object counts should be yellow")
  assert_equal(string.format("%.2f/%.2f/%.2f", r3, g3, b3), "1.00/0.32/0.32", "high object counts should be red")
end)

add_test("object summary breakdown matches the total count", function()
  fresh_runtime()
  stub.set_time(100)
  TwAuras.db = {
    auraStore = {
      version = 1,
      order = {1},
      items = {
        ["1"] = {
          id = 1,
          key = "aura_1",
          schemaVersion = 1,
          name = "Aura One",
          triggers = {
            { type = "buff" },
          },
          conditions = {
            { check = "active" },
          },
          display = {},
          load = {},
          position = {},
          __unitStates = {
            { unit = "party1", active = true },
          },
        },
      },
    },
  }
  TwAuras.regions = {
    [1] = {},
  }
  TwAuras.runtime.timers = {
    ["aura_1:1"] = { duration = 5, expirationTime = 104 },
  }
  TwAuras.runtime.trackedBuffs = {
    ["Tank:Rejuvenation"] = { expirationTime = 110 },
  }
  TwAuras.runtime.trackedDebuffs = {
    ["Boss:Rip"] = { expirationTime = 108 },
  }

  local breakdown = TwAuras:GetObjectSummaryBreakdown()
  assert_equal(breakdown.auras, 1, "breakdown should count auras")
  assert_equal(breakdown.triggers, 1, "breakdown should count triggers")
  assert_equal(breakdown.conditions, 1, "breakdown should count conditions")
  assert_equal(breakdown.regions, 1, "breakdown should count regions")
  assert_equal(breakdown.timers, 1, "breakdown should count active timers")
  assert_equal(breakdown.trackedBuffs, 1, "breakdown should count tracked buffs")
  assert_equal(breakdown.trackedDebuffs, 1, "breakdown should count tracked debuffs")
  assert_equal(breakdown.overlays, 1, "breakdown should count overlays")
  assert_equal(breakdown.total, 8, "breakdown total should match the sum of its parts")
end)

add_test("active runtime timer count ignores expired empty and zero-duration timers", function()
  fresh_runtime()
  stub.set_time(300)
  TwAuras.runtime.timers = {
    active = { duration = 5, expirationTime = 306 },
    expired = { duration = 5, expirationTime = 299 },
    zero = { duration = 0, expirationTime = 310 },
    missing = {},
  }

  assert_equal(TwAuras:GetActiveRuntimeTimerCount(), 1, "only active positive-duration timers should count")
end)

add_test("tracked runtime entry count ignores expired entries but keeps timeless records", function()
  fresh_runtime()
  stub.set_time(310)

  local total = TwAuras:GetTrackedRuntimeEntryCount({
    active = { expirationTime = 315 },
    expired = { expirationTime = 309 },
    timeless = { source = "Tester" },
    empty = {},
  })

  assert_equal(total, 2, "tracked runtime counts should keep active and timeless entries only")
end)

add_test("active overlay count sums visible unit states across multiple auras", function()
  fresh_runtime()
  TwAuras.db = {
    auraStore = {
      version = 1,
      order = {1, 2},
      items = {
        ["1"] = {
          id = 1,
          key = "aura_1",
          schemaVersion = 1,
          name = "Party One",
          triggers = {},
          conditions = {},
          display = {},
          load = {},
          position = {},
          __unitStates = {
            { unit = "party1", active = true },
            { unit = "party2", active = true },
          },
        },
        ["2"] = {
          id = 2,
          key = "aura_2",
          schemaVersion = 1,
          name = "Party Two",
          triggers = {},
          conditions = {},
          display = {},
          load = {},
          position = {},
          __unitStates = {
            { unit = "party3", active = true },
          },
        },
      },
    },
  }

  assert_equal(TwAuras:GetActiveOverlayCount(), 3, "overlay count should sum per-aura unit frame states")
end)

add_test("refresh aura updates object summary text while config is open", function()
  fresh_runtime()
  local objectText = nil
  local swatchColor = nil
  local aura = {
    id = 720,
    key = "aura_720",
    schemaVersion = 1,
    name = "Summary Refresh",
    enabled = true,
    regionType = "icon",
    triggerMode = "all",
    triggers = {
      { __index = 1, type = "always" },
    },
    conditions = {},
    display = {
      width = 32,
      height = 32,
      alpha = 1,
      iconPath = "Interface\\Icons\\INV_Misc_QuestionMark",
      color = {1, 1, 1, 1},
      bgColor = {0, 0, 0, 0.5},
      textColor = {1, 1, 1, 1},
      lowTimeTextColor = {1, 0.2, 0.2, 1},
      lowTimeBarColor = {1, 0.2, 0.2, 1},
      fontSize = 12,
      outline = "NONE",
      strata = "MEDIUM",
    },
    load = {},
    position = {},
    soundActions = {},
  }

  TwAuras.db = {
    auraStore = {
      version = 1,
      order = {720},
      items = {
        ["720"] = aura,
      },
    },
  }
  TwAuras.regions = {
    [720] = {
      ApplyState = function() end,
      Show = function() end,
      Hide = function() end,
      SetInactive = function() end,
    },
  }
  local originalRefreshObjectSummary = TwAuras.RefreshObjectSummary
  TwAuras.configFrame = {
    IsShown = function()
      return true
    end,
    objectSummaryText = {
      SetText = function(_, text)
        objectText = text
      end,
      SetTextColor = function() end,
    },
    objectSummarySwatch = {
      SetBackdropColor = function(_, r, g, b, a)
        swatchColor = string.format("%.2f/%.2f/%.2f/%.2f", r, g, b, a)
      end,
    },
  }
  TwAuras.RefreshObjectSummary = function(self)
    local total = self:GetObjectSummaryCount()
    local r, g, b = self:GetObjectSummaryLoadColor(total)
    self.configFrame.objectSummaryText:SetText("Objects: " .. tostring(total))
    self.configFrame.objectSummarySwatch:SetBackdropColor(r, g, b, 1)
  end

  TwAuras:RefreshAura(aura)
  TwAuras.RefreshObjectSummary = originalRefreshObjectSummary
  assert_equal(objectText, "Objects: 3", "refreshing a visible aura should update the footer summary text")
  assert_equal(swatchColor, "0.25/0.95/0.35/1.00", "footer summary should use the green band for low object counts")
end)

add_test("disabled unitframe auras clear stale overlay objects from the summary", function()
  fresh_runtime()
  local objectText = nil
  local aura = {
    id = 721,
    key = "aura_721",
    schemaVersion = 1,
    name = "Disabled Party Overlay",
    enabled = false,
    regionType = "unitframes",
    triggerMode = "all",
    triggers = {
      { __index = 1, type = "buff", unit = "partyunit", auraName = "Rejuvenation" },
    },
    conditions = {},
    display = {
      frameScope = "party",
      overlayStyle = "icon",
      width = 16,
      height = 16,
      alpha = 1,
      color = {1, 1, 1, 1},
      bgColor = {0, 0, 0, 0.5},
      textColor = {1, 1, 1, 1},
      glowColor = {1, 0, 0, 1},
      lowTimeTextColor = {1, 0.2, 0.2, 1},
      lowTimeBarColor = {1, 0.2, 0.2, 1},
      strata = "MEDIUM",
    },
    load = {},
    position = {},
    soundActions = {},
    __unitStates = {
      { unit = "party1", active = true },
      { unit = "party2", active = true },
    },
  }

  TwAuras.db = {
    auraStore = {
      version = 1,
      order = {721},
      items = {
        ["721"] = aura,
      },
    },
  }
  TwAuras.regions = {
    [721] = {
      ApplyUnitStates = function() end,
      Show = function() end,
      Hide = function() end,
      SetInactive = function() end,
    },
  }
  local originalRefreshObjectSummary = TwAuras.RefreshObjectSummary
  TwAuras.configFrame = {
    IsShown = function()
      return true
    end,
    objectSummaryText = {
      SetText = function(_, text)
        objectText = text
      end,
    },
  }
  TwAuras.RefreshObjectSummary = function(self)
    self.configFrame.objectSummaryText:SetText("Objects: " .. tostring(self:GetObjectSummaryCount()))
  end

  TwAuras:RefreshAura(aura)
  TwAuras.RefreshObjectSummary = originalRefreshObjectSummary
  assert_equal(table.getn(aura.__unitStates), 0, "disabled unitframe auras should clear stale overlay states")
  assert_equal(objectText, "Objects: 3", "clearing stale overlays should also refresh the footer summary text")
end)

add_test("slash command toggles the object tracker instead of the config", function()
  fresh_runtime()
  local configToggles = 0
  local trackerToggles = 0
  local originalToggleConfig = TwAuras.ToggleConfig
  local originalToggleObjectTracker = TwAuras.ToggleObjectTracker

  TwAuras.ToggleConfig = function()
    configToggles = configToggles + 1
  end
  TwAuras.ToggleObjectTracker = function()
    trackerToggles = trackerToggles + 1
  end

  TwAuras:HandleSlashCommand("obj")
  TwAuras:HandleSlashCommand("")

  TwAuras.ToggleConfig = originalToggleConfig
  TwAuras.ToggleObjectTracker = originalToggleObjectTracker

  assert_equal(trackerToggles, 1, "obj slash command should toggle the tracker")
  assert_equal(configToggles, 1, "empty slash command should still open the config")
end)

add_test("object tracker toggles and refreshes visible text", function()
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
          name = "Tracker Aura",
          triggers = {
            { type = "always" },
          },
          conditions = {},
          display = {},
          load = {},
          position = {},
        },
      },
    },
  }
  TwAuras.regions = {
    [1] = {},
  }

  local shown = false
  local objectText = nil
  local objectColor = nil
  TwAuras.objectTrackerFrame = {
    text = {
      SetText = function(_, text)
        objectText = text
      end,
      SetTextColor = function(_, r, g, b)
        objectColor = string.format("%.2f/%.2f/%.2f", r, g, b)
      end,
    },
    IsShown = function()
      return shown
    end,
    Show = function()
      shown = true
    end,
    Hide = function()
      shown = false
    end,
  }

  TwAuras:ToggleObjectTracker()
  assert_true(shown, "toggling the tracker on should show the frame")
  assert_equal(objectText, "Objects: 3", "showing the tracker should immediately refresh its text")
  assert_equal(objectColor, "0.25/0.95/0.35", "low object count tracker should use the green band")

  TwAuras:ToggleObjectTracker()
  assert_true(not shown, "toggling the tracker again should hide it")
end)

add_test("refresh aura updates the floating object tracker while visible", function()
  fresh_runtime()
  local objectText = nil
  local aura = {
    id = 722,
    key = "aura_722",
    schemaVersion = 1,
    name = "Tracker Refresh",
    enabled = true,
    regionType = "icon",
    triggerMode = "all",
    triggers = {
      { __index = 1, type = "always" },
    },
    conditions = {},
    display = {
      width = 32,
      height = 32,
      alpha = 1,
      iconPath = "Interface\\Icons\\INV_Misc_QuestionMark",
      color = {1, 1, 1, 1},
      bgColor = {0, 0, 0, 0.5},
      textColor = {1, 1, 1, 1},
      lowTimeTextColor = {1, 0.2, 0.2, 1},
      lowTimeBarColor = {1, 0.2, 0.2, 1},
      fontSize = 12,
      outline = "NONE",
      strata = "MEDIUM",
    },
    load = {},
    position = {},
    soundActions = {},
  }

  TwAuras.db = {
    auraStore = {
      version = 1,
      order = {722},
      items = {
        ["722"] = aura,
      },
    },
  }
  TwAuras.regions = {
    [722] = {
      ApplyState = function() end,
      Show = function() end,
      Hide = function() end,
      SetInactive = function() end,
    },
  }
  TwAuras.objectTrackerFrame = {
    text = {
      SetText = function(_, text)
        objectText = text
      end,
    },
    IsShown = function()
      return true
    end,
  }

  TwAuras:RefreshAura(aura)
  assert_equal(objectText, "Objects: 3", "refreshing an aura should update the floating tracker text when visible")
end)

add_test("toggle config queues reopen while player is in combat", function()
  fresh_runtime()
  local buildCalls = 0
  local refreshCalls = 0
  local originalBuildConfigFrame = TwAuras.BuildConfigFrame
  local originalRefreshConfigUI = TwAuras.RefreshConfigUI
  stub.set_unit("player", { combat = true })
  TwAuras.runtime.pendingConfigOpen = nil
  TwAuras.configFrame = nil

  TwAuras.BuildConfigFrame = function()
    buildCalls = buildCalls + 1
  end
  TwAuras.RefreshConfigUI = function()
    refreshCalls = refreshCalls + 1
  end

  TwAuras:ToggleConfig()

  TwAuras.BuildConfigFrame = originalBuildConfigFrame
  TwAuras.RefreshConfigUI = originalRefreshConfigUI

  assert_true(TwAuras.runtime.pendingConfigOpen, "combat-open request should queue a reopen")
  assert_equal(buildCalls, 0, "combat-open request should not build the config immediately")
  assert_equal(refreshCalls, 0, "combat-open request should not refresh the config immediately")
end)

add_test("entering combat closes the visible config", function()
  fresh_runtime()
  local hidden = false
  TwAuras.configFrame = {
    IsShown = function()
      return true
    end,
    Hide = function()
      hidden = true
    end,
  }

  TwAuras:HandleCombatConfigState("PLAYER_ENTER_COMBAT")
  assert_true(hidden, "combat entry should hide the config frame")
  assert_true(TwAuras.runtime.pendingConfigOpen, "combat-close should queue the config to reopen afterward")
end)

add_test("leaving combat reopens a queued config request", function()
  fresh_runtime()
  local buildCalls = 0
  local shown = false
  local refreshed = false
  local originalBuildConfigFrame = TwAuras.BuildConfigFrame
  local originalRefreshConfigUI = TwAuras.RefreshConfigUI
  local originalSetConfigMinimized = TwAuras.SetConfigMinimized
  TwAuras.runtime.pendingConfigOpen = true
  TwAuras.configFrame = nil

  TwAuras.BuildConfigFrame = function(self)
    buildCalls = buildCalls + 1
    self.configFrame = {
      Show = function()
        shown = true
      end,
      IsShown = function()
        return shown
      end,
    }
  end
  TwAuras.RefreshConfigUI = function()
    refreshed = true
  end
  TwAuras.SetConfigMinimized = function() end

  TwAuras:HandleCombatConfigState("PLAYER_LEAVE_COMBAT")

  TwAuras.BuildConfigFrame = originalBuildConfigFrame
  TwAuras.RefreshConfigUI = originalRefreshConfigUI
  TwAuras.SetConfigMinimized = originalSetConfigMinimized

  assert_equal(buildCalls, 1, "leaving combat should build the queued config once")
  assert_true(shown, "queued config should show after combat")
  assert_true(refreshed, "queued config should refresh after combat")
  assert_true(not TwAuras.runtime.pendingConfigOpen, "queued config flag should clear after reopening")
end)

add_test("config minimize hides editor content but keeps the banner available", function()
  fresh_runtime()
  local frame = {
    minimized = false,
    tabButtons = {
      {
        EnableMouse = function() end,
        Show = function() end,
      },
    },
    minimizeButton = {
      Show = function() end,
      EnableMouse = function() end,
    },
    tabs = {
      display = { Hide = function() end, Show = function() end },
      trigger = { Hide = function() end, Show = function() end },
    },
    leftPanel = {
      Hide = function(self) self.hidden = true end,
      Show = function(self) self.hidden = false end,
      EnableMouse = function(self, flag) self.mouse = flag end,
    },
    rightPanel = {
      SetWidth = function(self, value) self.width = value end,
      SetHeight = function(self, value) self.height = value end,
      SetPoint = function(self, _, _, _, x, y) self.x = x self.y = y end,
      EnableMouse = function(self, flag) self.mouse = flag end,
    },
    leftBackground = {
      Hide = function(self) self.hidden = true end,
      Show = function(self) self.hidden = false end,
    },
    rightBackground = {
      Hide = function(self) self.hidden = true end,
      Show = function(self) self.hidden = false end,
    },
    title = { Hide = function(self) self.hidden = true end, Show = function(self) self.hidden = false end },
    editorTitle = { Hide = function(self) self.hidden = true end, Show = function(self) self.hidden = false end },
    summaryText = { Hide = function(self) self.hidden = true end, Show = function(self) self.hidden = false end },
    liveUpdateCheck = { Hide = function(self) self.hidden = true end, Show = function(self) self.hidden = false end },
    applyButton = { Hide = function(self) self.hidden = true end, Show = function(self) self.hidden = false end },
    closeButton = { Hide = function(self) self.hidden = true end, Show = function(self) self.hidden = false end },
    debugButton = { Hide = function(self) self.hidden = true end, Show = function(self) self.hidden = false end },
    unlockButton = { Hide = function(self) self.hidden = true end, Show = function(self) self.hidden = false end },
    lockButton = { Hide = function(self) self.hidden = true end, Show = function(self) self.hidden = false end },
    SetWidth = function(self, value) self.width = value end,
    SetHeight = function(self, value) self.height = value end,
    SetBackdropColor = function(self, _, _, _, a) self.backdropAlpha = a end,
  }
  TwAuras.configFrame = frame

  TwAuras:SetConfigMinimized(true)
  assert_true(frame.minimized, "config should enter minimized mode")
  assert_equal(frame.width, 472, "minimized config should collapse to banner width")
  assert_equal(frame.height, 82, "minimized config should collapse to banner height")
  assert_true(frame.leftPanel.hidden, "minimized config should hide the aura list")
  assert_equal(frame.backdropAlpha, 0, "minimized config should make the main window transparent")

  TwAuras:SetConfigMinimized(false)
  assert_true(not frame.minimized, "config should leave minimized mode")
  assert_equal(frame.width, 960, "restored config should use the full width again")
  assert_equal(frame.height, 620, "restored config should use the full height again")
  assert_true(frame.leftPanel.hidden == false, "restored config should show the aura list again")
end)

add_test("show config tab restores a minimized config first", function()
  fresh_runtime()
  local restored = false
  TwAuras.configFrame = {
    minimized = true,
    tabs = {
      display = { Show = function() end, Hide = function() end },
      trigger = { Show = function() end, Hide = function() end },
    },
  }
  local originalSetConfigMinimized = TwAuras.SetConfigMinimized
  TwAuras.SetConfigMinimized = function(_, flag)
    restored = (flag == false)
    TwAuras.configFrame.minimized = false
  end

  TwAuras:ShowConfigTab("trigger")
  TwAuras.SetConfigMinimized = originalSetConfigMinimized

  assert_true(restored, "switching tabs should restore the minimized config first")
  assert_equal(TwAuras.configFrame.currentTab, "trigger", "tab switch should still record the selected tab")
end)

add_test("close hides config immediately when live update is enabled", function()
  fresh_runtime()
  local hidden = false
  TwAuras.configFrame = {
    Hide = function() hidden = true end,
    liveUpdateCheck = {
      GetChecked = function()
        return true
      end,
    },
  }

  TwAuras:RequestCloseConfigWindow()
  assert_true(hidden, "close should hide the config immediately when live update is enabled")
  assert_true(TwAuras.unsavedCloseFrame == nil, "no unsaved prompt should be built when live update is enabled")
end)

add_test("close shows unsaved prompt when live update is disabled", function()
  fresh_runtime()
  local hidden = false
  local shown = false
  local originalGetSelectedAura = TwAuras.GetSelectedAura
  local originalBuildUnsavedCloseFrame = TwAuras.BuildUnsavedCloseFrame
  TwAuras.GetSelectedAura = function()
    return { id = 1, name = "Test Aura" }
  end
  TwAuras.BuildUnsavedCloseFrame = function(self)
    self.unsavedCloseFrame = {
      Show = function() shown = true end,
      Hide = function() end,
    }
  end
  TwAuras.configFrame = {
    Hide = function() hidden = true end,
    liveUpdateCheck = {
      GetChecked = function()
        return false
      end,
    },
  }

  TwAuras:RequestCloseConfigWindow()
  TwAuras.GetSelectedAura = originalGetSelectedAura
  TwAuras.BuildUnsavedCloseFrame = originalBuildUnsavedCloseFrame

  assert_true(shown, "close should show the unsaved prompt when live update is disabled")
  assert_true(not hidden, "close should not hide the config immediately when prompting")
end)

add_test("unsaved prompt apply saves and then closes", function()
  fresh_runtime()
  local applied = false
  local configHidden = false
  local promptHidden = false
  TwAuras.configFrame = {
    Hide = function() configHidden = true end,
  }
  TwAuras.unsavedCloseFrame = {
    Hide = function() promptHidden = true end,
  }
  local originalApply = TwAuras.ApplyEditorToSelectedAura
  TwAuras.ApplyEditorToSelectedAura = function(_, isLive)
    applied = (isLive == false)
  end

  local originalBuildUnsavedCloseFrame = TwAuras.BuildUnsavedCloseFrame
  TwAuras.BuildUnsavedCloseFrame = function(self)
    self.unsavedCloseFrame = TwAuras.unsavedCloseFrame
    self.unsavedCloseFrame.applyButton = {
      scripts = {
        OnClick = function()
          TwAuras:ApplyEditorToSelectedAura(false)
          TwAuras.unsavedCloseFrame:Hide()
          if TwAuras.configFrame then
            TwAuras.configFrame:Hide()
          end
        end,
      },
    }
  end

  TwAuras:BuildUnsavedCloseFrame()
  TwAuras.unsavedCloseFrame.applyButton.scripts.OnClick()
  TwAuras.ApplyEditorToSelectedAura = originalApply
  TwAuras.BuildUnsavedCloseFrame = originalBuildUnsavedCloseFrame

  assert_true(applied, "apply should save staged editor changes before closing")
  assert_true(promptHidden, "apply should hide the unsaved prompt")
  assert_true(configHidden, "apply should then close the config")
end)

add_test("unsaved prompt discard closes without applying", function()
  fresh_runtime()
  local applied = false
  local configHidden = false
  local promptHidden = false
  TwAuras.configFrame = {
    Hide = function() configHidden = true end,
  }
  TwAuras.unsavedCloseFrame = {
    Hide = function() promptHidden = true end,
  }
  local originalApply = TwAuras.ApplyEditorToSelectedAura
  TwAuras.ApplyEditorToSelectedAura = function()
    applied = true
  end

  local originalBuildUnsavedCloseFrame = TwAuras.BuildUnsavedCloseFrame
  TwAuras.BuildUnsavedCloseFrame = function(self)
    self.unsavedCloseFrame = TwAuras.unsavedCloseFrame
    self.unsavedCloseFrame.discardButton = {
      scripts = {
        OnClick = function()
          TwAuras.unsavedCloseFrame:Hide()
          if TwAuras.configFrame then
            TwAuras.configFrame:Hide()
          end
        end,
      },
    }
  end

  TwAuras:BuildUnsavedCloseFrame()
  TwAuras.unsavedCloseFrame.discardButton.scripts.OnClick()
  TwAuras.ApplyEditorToSelectedAura = originalApply
  TwAuras.BuildUnsavedCloseFrame = originalBuildUnsavedCloseFrame

  assert_true(not applied, "discard should not apply staged editor changes")
  assert_true(promptHidden, "discard should hide the unsaved prompt")
  assert_true(configHidden, "discard should close the config")
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
      allowWorld = true,
      allowDungeon = true,
      allowRaid = true,
      allowPvp = true,
      allowArena = true,
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
      allowWorld = true,
      allowDungeon = true,
      allowRaid = true,
      allowPvp = true,
      allowArena = true,
    },
  }

  local summary = TwAuras:GetAuraSummary(aura, 252)
  assert_true(string.len(summary) <= 252, "summary should respect max length")
  assert_true(string.sub(summary, -3) == "...", "truncated summary should end with ellipsis")
end)

add_test("load allows world by default and blocks world when disabled", function()
  stub.set_instance(false, "none")
  assert_true(TwAuras:PassesLoad({
    allowWorld = true,
    allowDungeon = true,
    allowRaid = true,
    allowPvp = true,
    allowArena = true,
  }), "world should pass when enabled")
  assert_true(not TwAuras:PassesLoad({
    allowWorld = false,
    allowDungeon = true,
    allowRaid = true,
    allowPvp = true,
    allowArena = true,
  }), "world should fail when the no-instance option is disabled")
end)

add_test("load instance checkboxes respect party raid pvp and arena types", function()
  stub.set_instance(true, "party")
  assert_true(TwAuras:PassesLoad({ allowWorld = true, allowDungeon = true, allowRaid = false, allowPvp = false, allowArena = false }), "party instances should use dungeon checkbox")
  assert_true(not TwAuras:PassesLoad({ allowWorld = true, allowDungeon = false, allowRaid = true, allowPvp = true, allowArena = true }), "party instances should fail when dungeon is disabled")

  stub.set_instance(true, "raid")
  assert_true(TwAuras:PassesLoad({ allowWorld = false, allowDungeon = false, allowRaid = true, allowPvp = false, allowArena = false }), "raid instances should use raid checkbox")
  assert_true(not TwAuras:PassesLoad({ allowWorld = true, allowDungeon = true, allowRaid = false, allowPvp = true, allowArena = true }), "raid instances should fail when raid is disabled")

  stub.set_instance(true, "pvp")
  assert_true(TwAuras:PassesLoad({ allowWorld = false, allowDungeon = false, allowRaid = false, allowPvp = true, allowArena = false }), "pvp instances should use battleground checkbox")
  assert_true(not TwAuras:PassesLoad({ allowWorld = true, allowDungeon = true, allowRaid = true, allowPvp = false, allowArena = true }), "pvp instances should fail when battlegrounds are disabled")

  stub.set_instance(true, "arena")
  assert_true(TwAuras:PassesLoad({ allowWorld = false, allowDungeon = false, allowRaid = false, allowPvp = false, allowArena = true }), "arena instances should use arena checkbox")
  assert_true(not TwAuras:PassesLoad({ allowWorld = true, allowDungeon = true, allowRaid = true, allowPvp = true, allowArena = false }), "arena instances should fail when arenas are disabled")
end)

add_test("load zone text matches zone or sub zone text", function()
  stub.set_instance(false, "none")
  stub.set_zone("Blackrock Mountain", "Blackrock Depths")
  assert_true(TwAuras:PassesLoad({ zoneText = "blackrock" }), "zone text should match the main zone")
  assert_true(TwAuras:PassesLoad({ zoneText = "depths" }), "zone text should match the sub zone")
  assert_true(not TwAuras:PassesLoad({ zoneText = "stormwind" }), "zone text should fail when neither zone string matches")
end)

add_test("load zone context adds zone event inference and summary text", function()
  local aura = {
    id = 305,
    regionType = "icon",
    triggers = {
      { type = "always" },
    },
    load = {
      allowWorld = true,
      allowDungeon = true,
      allowRaid = false,
      allowPvp = false,
      allowArena = false,
      zoneText = "strath",
    },
  }

  local keys = TwAuras:GetAuraEventKeys(aura)
  local summary = TwAuras:GetAuraSummary(aura, 252)
  assert_true(keys.zone and true or false, "location-based load rules should add zone refresh inference")
  assert_true(string.find(summary, "locations: world/dungeon", 1, true) ~= nil, "summary should describe restricted instance locations")
  assert_true(string.find(summary, "zone contains strath", 1, true) ~= nil, "summary should include zone text filters")
end)

add_test("source token prefers first active combat log style trigger source", function()
  local aura = {
    id = 302,
    name = "Source Test",
    triggers = {
      { type = "combatlog" },
      { type = "spellcast" },
    },
    __triggerStates = {
      { active = true, source = "Onyxia" },
      { active = true, source = "Player" },
    },
    display = {
      timerFormat = "smart",
    },
  }
  local rendered = TwAuras:FormatDynamicDisplayText("%source", aura, {
    label = "Source Test",
    name = "Source Test",
    display = aura.display,
  }, GetTime())
  assert_equal(rendered, "Onyxia", "source token should use the first active combat log related trigger source")
end)

add_test("max token falls back to timer duration when no numeric max exists", function()
  local aura = {
    id = 303,
    name = "Duration Max",
    display = { timerFormat = "seconds" },
  }
  local rendered = TwAuras:FormatDynamicDisplayText("%value/%max", aura, {
    value = 8,
    duration = 12,
    expirationTime = GetTime() + 8,
    display = aura.display,
  }, GetTime())
  assert_equal(rendered, "8/12", "max token should reuse timer duration when no numeric max is available")
end)

add_test("unit token uses the active state unit", function()
  local aura = {
    id = 304,
    name = "Unit Test",
    trigger = { unit = "target" },
    display = {},
  }
  local rendered = TwAuras:FormatDynamicDisplayText("%unit", aura, {
    unit = "targettarget",
    display = aura.display,
  }, GetTime())
  assert_equal(rendered, "targettarget", "unit token should render the current state unit")
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

add_test("spell usable trigger can match missing resource", function()
  fresh_runtime()
  stub.set_spellbook({
    { name = "Healing Touch", texture = "Interface\\Icons\\Spell_Nature_HealingTouch", usable = false, notEnoughMana = true, inRange = true },
  })

  local trigger = {
    type = "spellusable",
    spellName = "Healing Touch",
    cooldownState = "missingresource",
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "Healing Touch Usable" }, trigger)
  assert_true(state.active, "spell usable trigger should match missing resource state")
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

add_test("item equipped trigger matches equipped trinket", function()
  fresh_runtime()
  stub.set_inventory_item(13, {
    texture = "Interface\\Icons\\INV_Misc_QuestionMark",
    link = "|cffFFFFFF|Hitem:0:0:0:0|h[Hand of Justice]|h|r",
  })

  local trigger = {
    type = "itemequipped",
    itemName = "Hand of Justice",
    equipmentSlot = "13",
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "HOJ Equipped" }, trigger)
  assert_true(state.active, "item equipped trigger should detect matching inventory link")
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

add_test("bag item cooldown trigger reads bag cooldowns", function()
  fresh_runtime()
  stub.set_time(40)
  stub.set_bag_items({
    [0] = {
      {
        name = "Major Healthstone",
        count = 2,
        texture = "Interface\\Icons\\INV_Stone_04",
        start = 10,
        duration = 120,
        enabled = 1,
      },
    },
  })

  local trigger = {
    type = "bagitemcooldown",
    itemName = "Major Healthstone",
    cooldownState = "cooldown",
    operator = ">=",
    threshold = 30,
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "Stone Cooldown" }, trigger)
  assert_true(state.active, "bag item cooldown trigger should detect active bag cooldowns")
  assert_equal(state.stacks, 2, "bag item cooldown trigger should expose item count")
  assert_equal(state.icon, "Interface\\Icons\\INV_Stone_04", "bag item cooldown trigger should expose the bag item icon")
end)

add_test("bag item cooldown trigger can show ready state", function()
  fresh_runtime()
  stub.set_bag_items({
    [0] = {
      {
        name = "Healing Potion",
        count = 1,
        texture = "Interface\\Icons\\INV_Potion_54",
        start = 0,
        duration = 0,
        enabled = 1,
      },
    },
  })

  local trigger = {
    type = "bagitemcooldown",
    itemName = "Healing Potion",
    cooldownState = "ready",
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "Potion Ready" }, trigger)
  assert_true(state.active, "bag item cooldown trigger should allow ready-state tracking")
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

add_test("group unit scope lists available party members", function()
  fresh_runtime()
  stub.set_group_state({ party = 2, raid = 0 })
  stub.set_unit("party1", { name = "Tank", exists = true })
  stub.set_unit("party2", { name = "Healer", exists = true })

  local units = TwAuras:GetGroupUnitsForScope("party")
  assert_equal(table.getn(units), 2, "party scope should return visible party units")
  assert_equal(units[1], "party1", "party scope should start with party1")
  assert_equal(units[2], "party2", "party scope should include party2")
end)

add_test("unit frame states evaluate partyunit buffs per member", function()
  fresh_runtime()
  stub.set_group_state({ party = 2, raid = 0 })
  stub.set_unit("party1", {
    name = "Tank",
    exists = true,
    buffs = {
      { name = "Rejuvenation", texture = "Interface\\Icons\\Spell_Nature_Rejuvenation" },
    },
  })
  stub.set_unit("party2", {
    name = "Healer",
    exists = true,
    buffs = {},
  })

  local aura = {
    id = "unitframes-test",
    name = "Party HoTs",
    regionType = "unitframes",
    triggerMode = "all",
    triggers = {
      {
        type = "buff",
        unit = "partyunit",
        auraName = "Rejuvenation",
      },
    },
    conditions = {},
    display = {
      frameScope = "party",
      overlayStyle = "icon",
      iconPath = "",
      width = 16,
      height = 16,
      alpha = 1,
      color = {1, 1, 1, 1},
      glowColor = {1, 0, 0, 1},
    },
    load = {},
    position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
    soundActions = { startSound = "", activeSound = "", stopSound = "", activeInterval = 2 },
    enabled = true,
  }

  TwAuras:NormalizeAuraConfig(aura)
  local states, aggregate = TwAuras:BuildUnitFrameStates(aura)
  assert_equal(table.getn(states), 1, "only matching party members should create active overlay states")
  assert_equal(states[1].unit, "party1", "the matching partyunit state should belong to party1")
  assert_true(aggregate.active, "aggregate state should be active when at least one frame unit matches")
end)

add_test("unit frame top left icons expand left to right without overlap", function()
  fresh_runtime()
  _G["PartyMemberFrame1"] = CreateFrame("Frame")

  local aura1 = {
    id = 101,
    key = "aura_101",
    schemaVersion = 1,
    name = "Left A",
    enabled = true,
    regionType = "unitframes",
    triggerMode = "all",
    triggers = {
      { type = "buff", unit = "partyunit", auraName = "Rejuvenation" },
    },
    conditions = {},
    display = {
      frameScope = "party",
      overlayStyle = "icon",
      frameAnchor = "TOPLEFT",
      frameYOffset = 0,
      width = 16,
      height = 16,
      alpha = 1,
      iconPath = "",
      color = {1, 1, 1, 1},
    },
    load = {},
    position = {},
    soundActions = {},
    __unitStates = {
      { active = true, unit = "party1", icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
    },
  }
  local aura2 = {
    id = 102,
    key = "aura_102",
    schemaVersion = 1,
    name = "Left B",
    enabled = true,
    regionType = "unitframes",
    triggerMode = "all",
    triggers = {
      { type = "buff", unit = "partyunit", auraName = "Rejuvenation" },
    },
    conditions = {},
    display = {
      frameScope = "party",
      overlayStyle = "icon",
      frameAnchor = "TOPLEFT",
      frameYOffset = 0,
      width = 16,
      height = 16,
      alpha = 1,
      iconPath = "",
      color = {1, 1, 1, 1},
    },
    load = {},
    position = {},
    soundActions = {},
    __unitStates = {
      { active = true, unit = "party1", icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
    },
  }

  TwAuras.db = {
    auraStore = {
      version = 1,
      order = {101, 102},
      items = {
        ["101"] = aura1,
        ["102"] = aura2,
      },
    },
  }

  local region1 = TwAuras:CreateRegion(aura1)
  local region2 = TwAuras:CreateRegion(aura2)

  region1:ApplyUnitStates(aura1, aura1.__unitStates)
  region2:ApplyUnitStates(aura2, aura2.__unitStates)

  local _, _, _, x1 = region1.overlays[1]:GetPoint()
  local _, _, _, x2 = region2.overlays[1]:GetPoint()
  assert_equal(x1, 2, "first TOPLEFT icon should anchor with a small inset")
  assert_equal(x2, 20, "second TOPLEFT icon should expand to the right")
end)

add_test("unit frame top icons expand from center without overlap", function()
  fresh_runtime()
  _G["PartyMemberFrame1"] = CreateFrame("Frame")

  local aura1 = {
    id = 201,
    key = "aura_201",
    schemaVersion = 1,
    name = "Top A",
    enabled = true,
    regionType = "unitframes",
    triggerMode = "all",
    triggers = {
      { type = "buff", unit = "partyunit", auraName = "Rejuvenation" },
    },
    conditions = {},
    display = {
      frameScope = "party",
      overlayStyle = "icon",
      frameAnchor = "TOP",
      frameYOffset = 0,
      width = 16,
      height = 16,
      alpha = 1,
      iconPath = "",
      color = {1, 1, 1, 1},
    },
    load = {},
    position = {},
    soundActions = {},
    __unitStates = {
      { active = true, unit = "party1", icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
    },
  }
  local aura2 = {
    id = 202,
    key = "aura_202",
    schemaVersion = 1,
    name = "Top B",
    enabled = true,
    regionType = "unitframes",
    triggerMode = "all",
    triggers = {
      { type = "buff", unit = "partyunit", auraName = "Rejuvenation" },
    },
    conditions = {},
    display = {
      frameScope = "party",
      overlayStyle = "icon",
      frameAnchor = "TOP",
      frameYOffset = 0,
      width = 16,
      height = 16,
      alpha = 1,
      iconPath = "",
      color = {1, 1, 1, 1},
    },
    load = {},
    position = {},
    soundActions = {},
    __unitStates = {
      { active = true, unit = "party1", icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
    },
  }

  TwAuras.db = {
    auraStore = {
      version = 1,
      order = {201, 202},
      items = {
        ["201"] = aura1,
        ["202"] = aura2,
      },
    },
  }

  local region1 = TwAuras:CreateRegion(aura1)
  local region2 = TwAuras:CreateRegion(aura2)

  region1:ApplyUnitStates(aura1, aura1.__unitStates)
  region2:ApplyUnitStates(aura2, aura2.__unitStates)

  local _, _, _, x1 = region1.overlays[1]:GetPoint()
  local _, _, _, x2 = region2.overlays[1]:GetPoint()
  assert_equal(x1, -9, "first TOP icon should shift left of center")
  assert_equal(x2, 9, "second TOP icon should shift right of center")
end)

add_test("unit frame top right icons expand right to left without overlap", function()
  fresh_runtime()
  _G["PartyMemberFrame1"] = CreateFrame("Frame")

  local aura1 = {
    id = 301,
    key = "aura_301",
    schemaVersion = 1,
    name = "Right A",
    enabled = true,
    regionType = "unitframes",
    triggerMode = "all",
    triggers = {
      { type = "buff", unit = "partyunit", auraName = "Rejuvenation" },
    },
    conditions = {},
    display = {
      frameScope = "party",
      overlayStyle = "icon",
      frameAnchor = "TOPRIGHT",
      frameYOffset = 0,
      width = 16,
      height = 16,
      alpha = 1,
      iconPath = "",
      color = {1, 1, 1, 1},
    },
    load = {},
    position = {},
    soundActions = {},
    __unitStates = {
      { active = true, unit = "party1", icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
    },
  }
  local aura2 = {
    id = 302,
    key = "aura_302",
    schemaVersion = 1,
    name = "Right B",
    enabled = true,
    regionType = "unitframes",
    triggerMode = "all",
    triggers = {
      { type = "buff", unit = "partyunit", auraName = "Rejuvenation" },
    },
    conditions = {},
    display = {
      frameScope = "party",
      overlayStyle = "icon",
      frameAnchor = "TOPRIGHT",
      frameYOffset = 0,
      width = 16,
      height = 16,
      alpha = 1,
      iconPath = "",
      color = {1, 1, 1, 1},
    },
    load = {},
    position = {},
    soundActions = {},
    __unitStates = {
      { active = true, unit = "party1", icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
    },
  }

  TwAuras.db = {
    auraStore = {
      version = 1,
      order = {301, 302},
      items = {
        ["301"] = aura1,
        ["302"] = aura2,
      },
    },
  }

  local region1 = TwAuras:CreateRegion(aura1)
  local region2 = TwAuras:CreateRegion(aura2)

  region1:ApplyUnitStates(aura1, aura1.__unitStates)
  region2:ApplyUnitStates(aura2, aura2.__unitStates)

  local _, _, _, x1 = region1.overlays[1]:GetPoint()
  local _, _, _, x2 = region2.overlays[1]:GetPoint()
  assert_equal(x1, -2, "first TOPRIGHT icon should anchor with a small inset")
  assert_equal(x2, -20, "second TOPRIGHT icon should expand to the left")
end)

add_test("raid unit frame icons use the same non-overlap layout rules", function()
  fresh_runtime()
  _G["RaidGroupButton1"] = CreateFrame("Frame")

  local aura1 = {
    id = 401,
    key = "aura_401",
    schemaVersion = 1,
    name = "Raid Left A",
    enabled = true,
    regionType = "unitframes",
    triggerMode = "all",
    triggers = {
      { type = "buff", unit = "partyunit", auraName = "Renew" },
    },
    conditions = {},
    display = {
      frameScope = "raid",
      overlayStyle = "icon",
      frameAnchor = "TOPLEFT",
      frameYOffset = 0,
      width = 16,
      height = 16,
      alpha = 1,
      iconPath = "",
      color = {1, 1, 1, 1},
    },
    load = {},
    position = {},
    soundActions = {},
    __unitStates = {
      { active = true, unit = "raid1", icon = "Interface\\Icons\\Spell_Holy_Renew" },
    },
  }
  local aura2 = {
    id = 402,
    key = "aura_402",
    schemaVersion = 1,
    name = "Raid Left B",
    enabled = true,
    regionType = "unitframes",
    triggerMode = "all",
    triggers = {
      { type = "buff", unit = "partyunit", auraName = "Renew" },
    },
    conditions = {},
    display = {
      frameScope = "raid",
      overlayStyle = "icon",
      frameAnchor = "TOPLEFT",
      frameYOffset = 0,
      width = 16,
      height = 16,
      alpha = 1,
      iconPath = "",
      color = {1, 1, 1, 1},
    },
    load = {},
    position = {},
    soundActions = {},
    __unitStates = {
      { active = true, unit = "raid1", icon = "Interface\\Icons\\Spell_Holy_Renew" },
    },
  }

  TwAuras.db = {
    auraStore = {
      version = 1,
      order = {401, 402},
      items = {
        ["401"] = aura1,
        ["402"] = aura2,
      },
    },
  }

  local region1 = TwAuras:CreateRegion(aura1)
  local region2 = TwAuras:CreateRegion(aura2)

  region1:ApplyUnitStates(aura1, aura1.__unitStates)
  region2:ApplyUnitStates(aura2, aura2.__unitStates)

  local _, _, _, x1 = region1.overlays[1]:GetPoint()
  local _, _, _, x2 = region2.overlays[1]:GetPoint()
  assert_equal(x1, 2, "first raid TOPLEFT icon should anchor with a small inset")
  assert_equal(x2, 20, "second raid TOPLEFT icon should expand to the right")
end)

add_test("energy tick trigger tracks the next predicted tick", function()
  fresh_runtime()
  stub.set_time(100)
  stub.set_unit("player", { mana = 20, maxMana = 100 })
  TwAuras:UpdateEnergyTickTracking()

  stub.set_time(101)
  stub.set_unit("player", { mana = 40, maxMana = 100 })
  TwAuras:UpdateEnergyTickTracking()

  local trigger = {
    type = "energytick",
    tickState = "cooldown",
    operator = ">=",
    threshold = 0,
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "Energy Tick" }, trigger)
  assert_true(state.active, "energy tick trigger should be active while waiting for the next tick")
  assert_equal(state.duration, 2, "energy tick should use a 2 second cadence")
  assert_equal(state.expirationTime, 103, "energy tick should predict the next tick two seconds after the last gain")
end)

add_test("mana regen trigger tracks the five second rule after mana spend", function()
  fresh_runtime()
  stub.set_time(200)
  stub.set_unit("player", { mana = 100, maxMana = 100 })
  TwAuras:UpdateManaFiveSecondRuleTracking()

  stub.set_time(201)
  stub.set_unit("player", { mana = 80, maxMana = 100 })
  TwAuras:UpdateManaFiveSecondRuleTracking()

  local trigger = {
    type = "manaregen",
    ruleState = "inside",
  }

  local state = TwAuras:EvaluateSingleTrigger({ name = "Five Second Rule" }, trigger)
  assert_true(state.active, "mana regen trigger should be active after spending mana")
  assert_equal(state.duration, 5, "five second rule should last five seconds")
  assert_equal(state.expirationTime, 206, "five second rule should end five seconds after mana spend")
end)

add_test("timer formatting supports mmss mode", function()
  local formatted = TwAuras:FormatRemainingTime(125, 0, "mmss")
  assert_equal(formatted, "2:05", "mmss timer formatting should show minutes and padded seconds")
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

add_test("preview state forces an aura region visible for layout testing", function()
  fresh_runtime()
  stub.set_time(250)

  local shown = false
  local hidden = false
  local appliedState = nil
  local aura = {
    id = 610,
    key = "aura_610",
    schemaVersion = 1,
    name = "Preview Aura",
    enabled = false,
    regionType = "icon",
    triggerMode = "all",
    triggers = {
      { __index = 1, type = "always" },
    },
    trigger = { unit = "player" },
    display = {
      width = 36,
      height = 36,
      alpha = 1,
      iconPath = "Interface\\Icons\\INV_Misc_QuestionMark",
      color = {1, 1, 1, 1},
      bgColor = {0, 0, 0, 0.5},
      textColor = {1, 1, 1, 1},
      lowTimeTextColor = {1, 0.2, 0.2, 1},
      lowTimeBarColor = {1, 0.2, 0.2, 1},
      fontSize = 12,
      outline = "NONE",
      strata = "MEDIUM",
      timerFormat = "smart",
    },
    load = {},
    position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
    conditions = {},
    soundActions = {},
  }

  TwAuras.regions[aura.id] = {
    ApplyState = function(_, _, state) appliedState = state end,
    Show = function() shown = true end,
    Hide = function() hidden = true end,
  }

  TwAuras:SetAuraPreviewState(aura.id, true)
  TwAuras:RefreshAura(aura)

  assert_true(shown, "previewed aura should be shown even if disabled")
  assert_true(not hidden, "previewed aura should not be hidden")
  assert_true(appliedState and appliedState.active, "previewed aura should apply an active preview state")
end)

add_test("debug log is rate limited per aura and area", function()
  fresh_runtime()
  stub.set_time(10)
  local aura = { id = 900, name = "Debug Aura" }
  TwAuras:DebugLog(aura, "trigger", "first message")
  TwAuras:DebugLog(aura, "trigger", "first message")
  assert_equal(table.getn(stub.get_messages()), 1, "duplicate debug output inside the cooldown should be suppressed")

  stub.advance_time(5)
  TwAuras:DebugLog(aura, "trigger", "second message")
  assert_equal(table.getn(stub.get_messages()), 1, "different messages in the same area should still be rate limited")

  stub.advance_time(6)
  TwAuras:DebugLog(aura, "trigger", "second message")
  assert_equal(table.getn(stub.get_messages()), 2, "debug output should resume after ten seconds")
end)

add_test("trigger debug reports handler errors once and returns inactive state", function()
  fresh_runtime()
  stub.set_time(20)
  TwAuras:RegisterTriggerType("explode_test", {
    displayName = "Explode Test",
    handler = function()
      error("boom")
    end,
    fields = {},
  })

  local aura = {
    id = 901,
    name = "Exploder",
    debug = { trigger = true },
  }
  local state = TwAuras:EvaluateSingleTrigger(aura, { type = "explode_test" })
  local messages = stub.get_messages()
  assert_true(not state.active, "failing trigger handlers should resolve inactive")
  assert_true(string.find(messages[1] or "", "boom", 1, true) ~= nil, "trigger debug should surface handler errors")
end)

add_test("trigger handler errors stay quiet when trigger debug is disabled", function()
  fresh_runtime()
  stub.set_time(21)
  TwAuras:RegisterTriggerType("explode_silent_test", {
    displayName = "Explode Silent Test",
    handler = function()
      error("silent boom")
    end,
    fields = {},
  })

  local aura = {
    id = 905,
    name = "Quiet Exploder",
    debug = { trigger = false },
  }
  local state = TwAuras:EvaluateSingleTrigger(aura, { type = "explode_silent_test" })
  assert_true(not state.active, "failing trigger handlers should still resolve inactive")
  assert_equal(table.getn(stub.get_messages()), 0, "trigger errors should not print when trigger debug is disabled")
end)

add_test("condition debug reports evaluation errors when enabled", function()
  fresh_runtime()
  stub.set_time(22)
  local original = TwAuras.EvaluateCondition
  TwAuras.EvaluateCondition = function()
    error("condition boom")
  end

  local aura = {
    id = 906,
    name = "Condition Boom",
    debug = { conditions = true },
    display = { alpha = 1 },
    conditions = {
      { enabled = true, check = "active", operator = "=", threshold = 1 },
    },
  }
  local state = TwAuras:ResolveConditionalState(aura, { active = true })
  TwAuras.EvaluateCondition = original

  assert_true(state.display ~= nil, "condition resolution should still return a display table")
  assert_true(string.find(stub.get_messages()[1] or "", "condition boom", 1, true) ~= nil, "condition debug should surface evaluation errors")
end)

add_test("condition evaluation errors stay quiet when conditions debug is disabled", function()
  fresh_runtime()
  stub.set_time(23)
  local original = TwAuras.EvaluateCondition
  TwAuras.EvaluateCondition = function()
    error("quiet condition boom")
  end

  local aura = {
    id = 907,
    name = "Quiet Condition Boom",
    debug = { conditions = false },
    display = { alpha = 1 },
    conditions = {
      { enabled = true, check = "active", operator = "=", threshold = 1 },
    },
  }
  TwAuras:ResolveConditionalState(aura, { active = true })
  TwAuras.EvaluateCondition = original

  assert_equal(table.getn(stub.get_messages()), 0, "condition errors should not print when conditions debug is disabled")
end)

add_test("display debug reports apply errors when enabled", function()
  fresh_runtime()
  stub.set_time(24)
  local aura = {
    id = 908,
    name = "Display Boom",
    enabled = true,
    regionType = "icon",
    triggerMode = "all",
    debug = { display = true },
    display = { desaturateInactive = false },
    load = {},
    triggers = {
      { type = "always" },
    },
    conditions = {},
  }
  local hidden = false
  TwAuras.regions[aura.id] = {
    ApplyState = function()
      error("display boom")
    end,
    Show = function() end,
    Hide = function() hidden = true end,
  }

  TwAuras:RefreshAura(aura)
  assert_true(hidden, "display failures should hide the region")
  assert_true(string.find(stub.get_messages()[1] or "", "display boom", 1, true) ~= nil, "display debug should surface apply errors")
end)

add_test("display apply errors stay quiet when display debug is disabled", function()
  fresh_runtime()
  stub.set_time(25)
  local aura = {
    id = 909,
    name = "Quiet Display Boom",
    enabled = true,
    regionType = "icon",
    triggerMode = "all",
    debug = { display = false },
    display = { desaturateInactive = false },
    load = {},
    triggers = {
      { type = "always" },
    },
    conditions = {},
  }
  TwAuras.regions[aura.id] = {
    ApplyState = function()
      error("quiet display boom")
    end,
    Show = function() end,
    Hide = function() end,
  }

  TwAuras:RefreshAura(aura)
  assert_equal(table.getn(stub.get_messages()), 0, "display errors should not print when display debug is disabled")
end)

add_test("load debug reports failure reasons when enabled", function()
  fresh_runtime()
  stub.set_time(26)
  stub.set_unit("target", { exists = false })
  local aura = {
    id = 910,
    name = "Load Fail",
    enabled = true,
    regionType = "icon",
    triggerMode = "all",
    debug = { load = true },
    display = { desaturateInactive = false },
    load = { requireTarget = true },
    triggers = {
      { type = "always" },
    },
    conditions = {},
  }
  TwAuras.regions[aura.id] = {
    Hide = function() end,
  }

  TwAuras:RefreshAura(aura)
  assert_true(string.find(stub.get_messages()[1] or "", "target missing", 1, true) ~= nil, "load debug should report failure reasons")
end)

add_test("load passes stay quiet when load debug is disabled", function()
  fresh_runtime()
  stub.set_time(27)
  local aura = {
    id = 911,
    name = "Load Quiet",
    enabled = true,
    regionType = "icon",
    triggerMode = "all",
    debug = { load = false },
    display = { desaturateInactive = false },
    load = {},
    triggers = {
      { type = "always" },
    },
    conditions = {},
  }
  TwAuras.regions[aura.id] = {
    ApplyState = function() end,
    Show = function() end,
    Hide = function() end,
  }

  TwAuras:RefreshAura(aura)
  assert_equal(table.getn(stub.get_messages()), 0, "load passes should not print when load debug is disabled")
end)

add_test("timer debug logs start and stop through the shared throttle", function()
  fresh_runtime()
  stub.set_time(30)
  local aura = {
    id = 902,
    name = "Timer Aura",
    debug = { timer = true },
  }

  TwAuras:StartAuraTimer("timer_test", 5, nil, "Test Timer", "", aura)
  stub.advance_time(11)
  TwAuras:StopAuraTimer("timer_test", aura)

  local messages = stub.get_messages()
  assert_equal(table.getn(messages), 2, "timer debug should log both start and stop after the throttle window")
  assert_true(string.find(messages[1] or "", "started", 1, true) ~= nil, "timer start should be logged")
  assert_true(string.find(messages[2] or "", "stopped", 1, true) ~= nil, "timer stop should be logged")
end)

add_test("timer debug stays quiet when disabled", function()
  fresh_runtime()
  stub.set_time(31)
  local aura = {
    id = 912,
    name = "Quiet Timer Aura",
    debug = { timer = false },
  }

  TwAuras:StartAuraTimer("timer_quiet_test", 5, nil, "Quiet Timer", "", aura)
  stub.advance_time(11)
  TwAuras:StopAuraTimer("timer_quiet_test", aura)
  assert_equal(table.getn(stub.get_messages()), 0, "timer debug should stay quiet when disabled")
end)

add_test("combat log debug reports matched combat log triggers", function()
  fresh_runtime()
  stub.set_time(40)
  local aura = {
    id = 903,
    name = "Combat Log Aura",
    regionType = "icon",
    triggerMode = "all",
    debug = { combatlog = true },
    display = { iconPath = "" },
    load = {},
    triggers = {
      {
        type = "combatlog",
        combatLogEvent = "ANY",
        combatLogPattern = "shadow flame",
        duration = 5,
      },
    },
  }
  TwAuras.db = TwAuras.db or {}
  TwAuras.db.auraStore = { version = 1, order = { aura.id }, items = { [tostring(aura.id)] = aura } }
  TwAuras.regions[aura.id] = {
    ApplyState = function() end,
    Show = function() end,
    Hide = function() end,
  }

  TwAuras:RecordCombatLog("CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE", "Onyxia begins to cast Shadow Flame.")
  local message = stub.get_messages()[1] or ""
  assert_true(string.find(message, "combat log trigger", 1, true) ~= nil or string.find(message, "CHAT_MSG", 1, true) ~= nil, "combat log debug should report the incoming line or its trigger match")
end)

add_test("combat log debug stays quiet when disabled", function()
  fresh_runtime()
  stub.set_time(41)
  local aura = {
    id = 913,
    name = "Quiet Combat Log Aura",
    regionType = "icon",
    triggerMode = "all",
    debug = { combatlog = false },
    display = { iconPath = "" },
    load = {},
    triggers = {
      {
        type = "combatlog",
        combatLogEvent = "ANY",
        combatLogPattern = "shadow flame",
        duration = 5,
      },
    },
  }
  TwAuras.db = TwAuras.db or {}
  TwAuras.db.auraStore = { version = 1, order = { aura.id }, items = { [tostring(aura.id)] = aura } }
  TwAuras.regions[aura.id] = {
    ApplyState = function() end,
    Show = function() end,
    Hide = function() end,
  }

  TwAuras:RecordCombatLog("CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE", "Onyxia begins to cast Shadow Flame.")
  assert_equal(table.getn(stub.get_messages()), 0, "combat log debug should stay quiet when disabled")
end)

add_test("unit frame debug reports built active states", function()
  fresh_runtime()
  stub.set_time(50)
  stub.set_group_state({ party = 2 })
  stub.set_unit("party1", { name = "Party One", exists = true })
  stub.set_unit("party2", { name = "Party Two", exists = true })
  stub.set_unit_buffs("party1", {
    { name = "Rejuvenation", texture = "Interface\\Icons\\Spell_Nature_Rejuvenation" },
  })
  stub.set_unit_buffs("party2", {})

  local aura = {
    id = 904,
    name = "Party Rejuv",
    regionType = "unitframes",
    debug = { unitframes = true },
    display = { frameScope = "party" },
    triggers = {
      { type = "buff", unit = "partyunit", auraName = "Rejuvenation", sourceFilter = "any" },
    },
    conditions = {},
  }

  local states = TwAuras:BuildUnitFrameStates(aura)
  local message = stub.get_messages()[1] or ""
  assert_equal(table.getn(states), 1, "one party member should have an active unit frame state")
  assert_true(string.find(message, "built 1 active unit frame state", 1, true) ~= nil, "unit frame debug should report the built state count")
end)

add_test("unit frame debug stays quiet when disabled", function()
  fresh_runtime()
  stub.set_time(51)
  stub.set_group_state({ party = 2 })
  stub.set_unit("party1", { name = "Party One", exists = true })
  stub.set_unit("party2", { name = "Party Two", exists = true })
  stub.set_unit_buffs("party1", {
    { name = "Rejuvenation", texture = "Interface\\Icons\\Spell_Nature_Rejuvenation" },
  })
  stub.set_unit_buffs("party2", {})

  local aura = {
    id = 914,
    name = "Quiet Party Rejuv",
    regionType = "unitframes",
    debug = { unitframes = false },
    display = { frameScope = "party" },
    triggers = {
      { type = "buff", unit = "partyunit", auraName = "Rejuvenation", sourceFilter = "any" },
    },
    conditions = {},
  }

  TwAuras:BuildUnitFrameStates(aura)
  assert_equal(table.getn(stub.get_messages()), 0, "unit frame debug should stay quiet when disabled")
end)

add_test("player aura scan falls back when legacy player buff api is missing", function()
  fresh_runtime()
  stub.set_unit("player", { name = "Fallback Tester", exists = true })
  stub.set_unit_buffs("player", {
    { name = "Clearcasting", texture = "Interface\\Icons\\Spell_Shadow_ManaBurn", count = 1 },
  })

  local originalSetPlayerBuff = GameTooltip.SetPlayerBuff
  local ok
  local err
  GameTooltip.SetPlayerBuff = nil
  ok, err = pcall(function()
    with_global_overrides({
      GetPlayerBuff = nil,
    }, function()
      local state = TwAuras:ScanAura("player", "Clearcasting", false)
      assert_true(state.active, "player aura scan should still succeed without GetPlayerBuff/SetPlayerBuff")
      assert_equal(state.name, "Clearcasting", "fallback player aura scan should recover aura name")
    end)
  end)
  GameTooltip.SetPlayerBuff = originalSetPlayerBuff
  if not ok then
    error(err, 2)
  end
end)

add_test("bag count falls back to manual scan when GetItemCount is unavailable", function()
  fresh_runtime()
  stub.set_bag_items({
    [0] = {
      { name = "Major Mana Potion", count = 4 },
      { name = "Runecloth Bandage", count = 2 },
    },
    [1] = {
      { name = "Major Mana Potion", count = 3 },
    },
  })

  with_global_overrides({
    GetItemCount = nil,
  }, function()
    local total = TwAuras:GetBagItemCountByName("Major Mana Potion")
    assert_equal(total, 7, "manual bag scan fallback should total item counts across bags")
  end)
end)

add_test("threat detection falls back when threat apis are unavailable", function()
  fresh_runtime()
  stub.set_unit("player", { name = "Tank", exists = true })
  stub.set_unit("targettarget", { name = "Tank", exists = true })

  with_global_overrides({
    UnitThreatSituation = nil,
    UnitDetailedThreatSituation = nil,
  }, function()
    assert_true(TwAuras:PlayerHasAggro(), "threat fallback should match targettarget to player")
  end)
end)

add_test("range info falls back to action slot when interact api is unavailable", function()
  fresh_runtime()
  stub.set_unit("target", {
    name = "Range Dummy",
    exists = true,
  })
  stub.set_action(7, {
    inRange = true,
  })

  with_global_overrides({
    CheckInteractDistance = nil,
  }, function()
    local info = TwAuras:GetRangeInfo({
      rangeUnit = "target",
      rangeMode = "action",
      actionSlot = 7,
    })
    assert_true(info and info.inRange, "range fallback should use action slot range when interact api is missing")
  end)
end)

add_test("replay keeps finisher snapshot through cast and apply jitter", function()
  fresh_runtime()
  stub.set_unit("target", { name = "Replay Dummy", exists = true })
  stub.set_combo_points(4)
  TwAuras.runtime.lastPlayerComboPoints = 4

  run_replay_steps({
    {
      at = 100,
      run = function()
        TwAuras:TrackPlayerDebuffsFromCombatLog("You begin to cast Rip.")
      end,
    },
    {
      at = 100.2,
      run = function()
        TwAuras:RecordCombatLog("CHAT_MSG_SPELL_SELF_DAMAGE", "You hit Replay Dummy for 42.")
      end,
    },
    {
      at = 101,
      run = function()
        TwAuras:TrackPlayerDebuffsFromCombatLog("Replay Dummy is afflicted by your Rip.")
      end,
    },
  })

  local tracked = TwAuras:GetTrackedDebuff("target", "Rip")
  assert_true(tracked ~= nil, "replay should produce a tracked Rip timer")
  assert_equal(tracked.comboPoints, 4, "replay should preserve combo points from cast start")
end)

add_test("replay keeps only newest combat log lines under heavy volume", function()
  fresh_runtime()
  TwAuras.db = {
    auraStore = {
      version = 1,
      order = {},
      items = {},
    },
  }

  local i
  for i = 1, 25 do
    stub.set_time(200 + i)
    TwAuras:RecordCombatLog("CHAT_MSG_SPELL_SELF_DAMAGE", "Replay line " .. tostring(i))
  end

  assert_equal(table.getn(TwAuras.runtime.recentCombatLog), 8, "recent combat log should keep the newest eight lines")
  assert_equal(TwAuras.runtime.recentCombatLog[1].message, "Replay line 25", "newest replay line should be first")
  assert_equal(TwAuras.runtime.recentCombatLog[8].message, "Replay line 18", "oldest retained replay line should be eighth")
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
