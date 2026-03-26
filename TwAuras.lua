-- TwAuras file version: 0.1.27
-- Addon bootstrap, defaults, and frame event wiring.
local addonName = "TwAuras"

-- TwAuras is a shared runtime table extended across multiple files.
-- This file mostly establishes the baseline state and event subscriptions that the other
-- modules build on top of.
TwAuras = {
  frame = CreateFrame("Frame"),
  auras = {},
  regions = {},
  Private = {
    triggerTypes = {},
    regionTypes = {},
  },
  runtime = {
    timers = {},
    recentCombatLog = {},
    trackedBuffs = {},
    trackedDebuffs = {},
    pendingBuffCasts = {},
    pendingDebuffCasts = {},
    targetHealthEstimates = {},
    targetManaEstimates = {},
    auraAudio = {},
    debugLog = {},
    timerOwners = {},
    energyTick = {},
    manaFiveSecondRule = {},
    lastPlayerComboPoints = 0,
    playerCast = {},
  },
  defaults = {
    profile = {
      unlocked = false,
      nextId = 3,
      selectedAuraId = 1,
      auraStore = {
        version = 1,
        order = {},
        items = {},
      },
      auras = {
        {
          id = 1,
          key = "aura_1",
          schemaVersion = 1,
          name = "Slice and Dice",
          enabled = true,
          regionType = "icon",
          triggerMode = "all",
          triggers = {
            {
              type = "buff",
              unit = "player",
              auraName = "Slice and Dice",
              spellName = "",
              sourceUnit = "player",
              castPhase = "any",
              operator = ">=",
              threshold = 1,
              duration = 0,
              powerType = "energy",
              combatLogEvent = "ANY",
              combatLogPattern = "",
              invert = false,
              trackMissing = false,
              useTrackedTimer = true,
              valueMode = "absolute",
            },
            {
              type = "none",
              unit = "player",
              auraName = "",
              spellName = "",
              sourceUnit = "player",
              castPhase = "any",
              operator = ">=",
              threshold = 0,
              duration = 0,
              powerType = "energy",
              combatLogEvent = "ANY",
              combatLogPattern = "",
              invert = false,
              trackMissing = false,
              useTrackedTimer = true,
              valueMode = "absolute",
            },
          },
          display = {
            width = 36,
            height = 36,
            alpha = 1,
            color = {1, 1, 1, 1},
            bgColor = {0, 0, 0, 0.45},
            textColor = {1, 1, 1, 1},
            showIcon = true,
            showTimerText = true,
            showStackText = true,
            showLabelText = false,
            desaturateInactive = false,
            label = "",
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
          position = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = 0,
          },
        },
        {
          id = 2,
          key = "aura_2",
          schemaVersion = 1,
          name = "Energy Low",
          enabled = true,
          regionType = "bar",
          triggerMode = "all",
          triggers = {
            {
              type = "power",
              unit = "player",
              spellName = "",
              sourceUnit = "player",
              castPhase = "any",
              powerType = "energy",
              operator = "<=",
              threshold = 40,
              duration = 0,
              auraName = "",
              combatLogEvent = "ANY",
              combatLogPattern = "",
              invert = false,
              trackMissing = false,
              useTrackedTimer = true,
              valueMode = "absolute",
            },
            {
              type = "none",
              unit = "player",
              spellName = "",
              sourceUnit = "player",
              castPhase = "any",
              powerType = "energy",
              operator = ">=",
              threshold = 0,
              duration = 0,
              auraName = "",
              combatLogEvent = "ANY",
              combatLogPattern = "",
              invert = false,
              trackMissing = false,
              useTrackedTimer = true,
              valueMode = "absolute",
            },
          },
          display = {
            width = 180,
            height = 18,
            alpha = 1,
            color = {1, 0.8, 0, 1},
            bgColor = {0, 0, 0, 0.5},
            textColor = {1, 1, 1, 1},
            showIcon = false,
            showTimerText = false,
            showStackText = false,
            showLabelText = true,
            desaturateInactive = false,
            label = "Energy Low",
            iconPath = "",
            iconDesaturate = false,
            iconHueEnabled = false,
            iconHue = 0,
            showCooldownSwipe = false,
            showCooldownOverlay = false,
            labelText = "%label",
            timerText = "%time",
            valueText = "%value/%max",
            fontSize = 12,
            fontOutline = "",
            labelAnchor = "LEFT",
            timerAnchor = "RIGHT",
            valueAnchor = "RIGHT",
            textAnchor = "CENTER",
          },
          load = {
            inCombat = false,
            class = "ROGUE",
            requireTarget = false,
            allowWorld = true,
            allowDungeon = true,
            allowRaid = true,
            allowPvp = true,
            allowArena = true,
            zoneText = "",
            updateEvents = "",
          },
          position = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = -60,
          },
        },
      },
    },
  },
}

-- These default auras also serve as concrete examples of the saved-data format that the editor
-- and runtime normalize around.
-- Slash commands open the main tabbed editor directly so users land in the real aura-building UI.
-- The floating object tracker reuses the same summary logic as the config footer so the
-- debugging numbers stay identical in and out of the editor.
function TwAuras:RefreshObjectTracker()
  if not self.objectTrackerFrame or not self.objectTrackerFrame:IsShown() then
    return
  end
  local total = self:GetObjectSummaryCount()
  local r, g, b = self:GetObjectSummaryLoadColor(total)
  if self.objectTrackerFrame.text then
    self.objectTrackerFrame.text:SetText("Objects: " .. tostring(total))
    if self.objectTrackerFrame.text.SetTextColor then
      self.objectTrackerFrame.text:SetTextColor(r, g, b)
    end
  end
  if self.objectTrackerFrame.SetBackdropColor then
    self.objectTrackerFrame:SetBackdropColor(0, 0, 0, 0.85)
  end
  if self.objectTrackerFrame.SetBackdropBorderColor then
    self.objectTrackerFrame:SetBackdropBorderColor(r, g, b, 1)
  end
end

-- Combat log range defaults improve the reliability of combat-log-driven triggers on TurtleWoW.
function TwAuras:ApplyCombatLogRangeDefaults()
  local rangeTargets = {
    "Party",
    "PartyPet",
    "FriendlyPlayers",
    "FriendlyPlayersPets",
    "HostilePlayers",
    "HostilePlayersPets",
    "Creature",
  }
  local i
  if not SetCVar then
    return
  end
  for i = 1, table.getn(rangeTargets) do
    SetCVar("CombatLogRange" .. rangeTargets[i], 200)
  end
end

-- The tracker frame is created lazily so normal users do not pay for extra UI until they ask for it.
function TwAuras:EnsureObjectTrackerFrame()
  if self.objectTrackerFrame then
    return self.objectTrackerFrame
  end

  local frame = CreateFrame("Frame", nil, UIParent)
  frame:SetWidth(132)
  frame:SetHeight(28)
  frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
  frame:SetFrameStrata("MEDIUM")
  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  frame:SetBackdropColor(0, 0, 0, 0.85)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function()
    this:StartMoving()
  end)
  frame:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
  end)
  frame:SetScript("OnEnter", function()
    if not GameTooltip then
      return
    end
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(TwAuras:GetObjectSummaryTooltipText(), 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)

  frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
  frame.text:SetJustifyH("CENTER")
  frame.text:SetText("Objects: 0")
  frame:Hide()

  self.objectTrackerFrame = frame
  return frame
end

-- Toggling keeps the slash command simple and lets the same frame be reused for the whole session.
function TwAuras:ToggleObjectTracker()
  local frame = self:EnsureObjectTrackerFrame()
  if frame:IsShown() then
    frame:Hide()
    return
  end
  frame:Show()
  self:RefreshObjectTracker()
end

-- Slash parsing stays intentionally tiny: either toggle the object tracker or open the config.
function TwAuras:HandleSlashCommand(msg)
  local trimmed = string.lower(string.gsub(msg or "", "^%s*(.-)%s*$", "%1"))
  if trimmed == "obj" then
    self:ToggleObjectTracker()
    return
  end
  if type(self.ToggleConfig) == "function" then
    self:ToggleConfig()
    return
  end
  if type(self.OpenConfigWindow) == "function" then
    self:OpenConfigWindow()
    return
  end
  self:Print("Config module not ready. Use /reload. If it persists, run /console scriptErrors 1 and reload to capture the first load error.")
end

SLASH_TWAURAS1 = "/twa"
SLASH_TWAURAS2 = "/twauras"

SlashCmdList["TWAURAS"] = function(msg)
  TwAuras:HandleSlashCommand(msg)
end

TwAuras.frame:SetScript("OnEvent", function()
  TwAuras:OnEvent(event, arg1)
end)

-- The frame intentionally registers more events than any one aura needs.
-- Core.lua translates these raw events into higher-level event keys and refreshes only the
-- auras whose triggers or load settings declared interest in those keys.
-- The frame subscribes broadly, while Core.lua decides which auras actually care about each event.
TwAuras.frame:RegisterEvent("VARIABLES_LOADED")
TwAuras.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
TwAuras.frame:RegisterEvent("PLAYER_AURAS_CHANGED")
TwAuras.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
TwAuras.frame:RegisterEvent("PLAYER_ENTER_COMBAT")
TwAuras.frame:RegisterEvent("PLAYER_LEAVE_COMBAT")
TwAuras.frame:RegisterEvent("UNIT_COMBO_POINTS")
TwAuras.frame:RegisterEvent("UNIT_ENERGY")
TwAuras.frame:RegisterEvent("UNIT_MANA")
TwAuras.frame:RegisterEvent("UNIT_RAGE")
TwAuras.frame:RegisterEvent("UNIT_HEALTH")
TwAuras.frame:RegisterEvent("UNIT_MAXHEALTH")
TwAuras.frame:RegisterEvent("SPELLS_CHANGED")
TwAuras.frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
TwAuras.frame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
TwAuras.frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
TwAuras.frame:RegisterEvent("BAG_UPDATE")
TwAuras.frame:RegisterEvent("PLAYER_INVENTORY_CHANGED")
TwAuras.frame:RegisterEvent("PLAYER_UPDATE_RESTING")
TwAuras.frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
TwAuras.frame:RegisterEvent("RAID_ROSTER_UPDATE")
TwAuras.frame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
TwAuras.frame:RegisterEvent("SPELLCAST_START")
TwAuras.frame:RegisterEvent("SPELLCAST_STOP")
TwAuras.frame:RegisterEvent("SPELLCAST_FAILED")
TwAuras.frame:RegisterEvent("SPELLCAST_INTERRUPTED")
TwAuras.frame:RegisterEvent("SPELLCAST_DELAYED")
TwAuras.frame:RegisterEvent("SPELLCAST_CHANNEL_START")
TwAuras.frame:RegisterEvent("SPELLCAST_CHANNEL_STOP")
TwAuras.frame:RegisterEvent("SPELLCAST_CHANNEL_UPDATE")
TwAuras.frame:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
TwAuras.frame:RegisterEvent("ZONE_CHANGED")
TwAuras.frame:RegisterEvent("ZONE_CHANGED_INDOORS")
TwAuras.frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
TwAuras.frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
TwAuras.frame:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
TwAuras.frame:RegisterEvent("UNIT_PET")
TwAuras.frame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
TwAuras.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
TwAuras.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
TwAuras.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE")
TwAuras.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE")
TwAuras.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
TwAuras.frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
TwAuras.frame:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
TwAuras.frame:RegisterEvent("CHAT_MSG_SPELL_PARTY_DAMAGE")
TwAuras.frame:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE")
TwAuras.frame:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
TwAuras.frame:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE")
TwAuras.frame:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE")
TwAuras.frame:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
TwAuras.frame:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF")
TwAuras.frame:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF")
TwAuras.frame:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_SELF")
TwAuras.frame:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_OTHER")

-- Timer text still needs periodic updates on the old client, but the expensive part is kept
-- narrow by only reevaluating timed auras instead of refreshing the entire addon every tick.
-- Timers and dynamic text still need polling, but only timed auras are refreshed here.
TwAuras.frame:SetScript("OnUpdate", function()
  if not TwAuras.lastUpdate then
    TwAuras.lastUpdate = 0
  end
  local now = GetTime()
    if now - TwAuras.lastUpdate >= 0.10 then
      TwAuras.lastUpdate = now
      TwAuras:RefreshDynamicTexts(now)
      TwAuras:RefreshTimedAuras()
      TwAuras:UpdateAuraLoopSounds(now)
      TwAuras:RefreshObjectTracker()
    end
  end)
