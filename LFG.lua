BINDING_HEADER_LFG = "Looking For Group"
BINDING_NAME_LFG = "Toggle Looking For Group"

local _G, _ = _G or getfenv()

local LFG = CreateFrame("Frame")
local me = UnitName('player')
-- Protocol version is independent of addonVer. Increment this (not addonVer)
-- when chat message formats change (e.g. new fields in goingWith/LFG: strings).
-- Players on different protocol versions cannot communicate correctly.
local LFG_PROTOCOL_VERSION = 3  -- v2: added LFT| group/queue protocol; v3: class field + :cr flag + CR election
local addonVer = GetAddOnMetadata("LFG", "Version")
local LFG_ADDON_CHANNEL = 'LFG'
local groupsFormedThisSession = 0

ROLE_TANK_TOOLTIP = 'Indicates that you are willing to\nprotect allies from harm by\nensuring that enemies are\nattacking you instead of them.'
ROLE_HEALER_TOOLTIP = 'Indicates that you are willing to\nheal your allies when they take\ndamage.'
ROLE_DAMAGE_TOOLTIP = 'Indicates that you are willing to\ntake on the role of dealing\ndamage to enemies.'
ROLE_BAD_TOOLTIP = 'Your class may not perform this role.'

LFG.tab = 1
LFG.WarnedPlayers = LFG.WarnedPlayers or {}
LFG.dungeonsSpam = {}
LFG.dungeonsSpamDisplay = {}
LFG.dungeonsSpamDisplayLFM = {}
LFG.browseFrames = {}
LFG.showedUpdateNotification = false
LFG.maxDungeonsInQueue = 5
LFG.groupSizeMax = 5
LFG.class = ''
LFG.channel = LFG_ADDON_CHANNEL
LFG.channelIndex = 0
LFG.level = UnitLevel('player')
LFG.findingGroup = false
LFG.findingMore = false
LFG:RegisterEvent("ADDON_LOADED")
LFG:RegisterEvent("PLAYER_ENTERING_WORLD")
LFG:RegisterEvent("PLAYER_LOGOUT")
LFG:RegisterEvent("PARTY_MEMBERS_CHANGED")
LFG:RegisterEvent("PARTY_LEADER_CHANGED")
LFG:RegisterEvent("PLAYER_LEVEL_UP")
LFG:RegisterEvent("PLAYER_TARGET_CHANGED")
LFG.availableDungeons = {}
LFG.group = {}
LFG.oneGroupFull = false
LFG.groupFullCode = ''
LFG.acceptNextInvite = false
LFG.onlyAcceptFrom = ''
LFG.queueStartTime = 0
LFG.averageWaitTime = 0
LFG.types = {
    [1] = 'Suggested Dungeons',
    [2] = 'Elite Encounters',
    [3] = 'All Available Dungeons',
}
LFG.maxDungeonsList = 11
LFG.minimapFrames = {}
LFG.myRandomTime = 0
LFG.random_min = 0
LFG.random_max = 5

LFG.RESET_TIME = 0
LFG.TANK_TIME = 2
LFG.HEALER_TIME = 10
LFG.DAMAGE_TIME = 18
LFG.FULLCHECK_TIME = 26 --time when checkGroupFull is called, has to wait for goingWith messages
LFG.TIME_MARGIN = 30

LFG.ROLE_CHECK_TIME = 50

LFG.foundGroup = false
LFG.inGroup = false
LFG.isLeader = false
LFG.LFMGroup = {}
LFG.LFMDungeonCode = ''
LFG.classRun = false          -- opt-in: only match one player per class
LFG.seenClasses = {}          -- [dungeonCode][playerName] = {class, cr}
LFG.crLeader = false          -- true when self-elected as CR leader (distinct from IsPartyLeader)
LFG.crCandidates = {}         -- [dungeonCode][playerName] = time()
LFG.crElectionTime = {}       -- [dungeonCode] = time() when election clock started
LFG.CR_ELECTION_WAIT = 35     -- seconds to wait for a natural LFM before self-electing
LFG.CR_LEADER_TIMEOUT = 65    -- seconds of silence before re-running election
LFG.currentGroupSize = 1

LFG.objectivesFrames = {}
LFG.peopleLookingForGroups = 0
LFG.peopleLookingForGroupsDisplay = 0

LFG.currentGroupRoles = {}

LFG.supress = {}

LFG.classColors = {
    ["warrior"] = { r = 0.78, g = 0.61, b = 0.43, c = "|cffc79c6e" },
    ["mage"] = { r = 0.41, g = 0.8, b = 0.94, c = "|cff69ccf0" },
    ["rogue"] = { r = 1, g = 0.96, b = 0.41, c = "|cfffff569" },
    ["druid"] = { r = 1, g = 0.49, b = 0.04, c = "|cffff7d0a" },
    ["hunter"] = { r = 0.67, g = 0.83, b = 0.45, c = "|cffabd473" },
    ["shaman"] = { r = 0.14, g = 0.35, b = 1.0, c = "|cff0070de" },
    ["priest"] = { r = 1, g = 1, b = 1, c = "|cffffffff" },
    ["warlock"] = { r = 0.58, g = 0.51, b = 0.79, c = "|cff9482c9" },
    ["paladin"] = { r = 0.96, g = 0.55, b = 0.73, c = "|cfff58cba" }
}

-- delay leave queue, to check if im really ungrouped
local LFGDelayLeaveQueue = CreateFrame("Frame")
LFGDelayLeaveQueue:Hide()
LFGDelayLeaveQueue.reason = ''
LFGDelayLeaveQueue:SetScript("OnShow", function()
    this.startTime = GetTime()
end)
LFGDelayLeaveQueue:SetScript("OnUpdate", function()
    local plus = 2 --seconds
    local gt = GetTime() * 1000
    local st = (this.startTime + plus) * 1000
    if gt >= st then
        LFG.inGroup = GetNumRaidMembers() == 0 and GetNumPartyMembers() > 0
        if not LFG.inGroup then
            leaveQueue(LFGDelayLeaveQueue.reason)
            LFGDelayLeaveQueue.reason = ''
            LFG.hidePartyRoleIcons()
        end
        LFGDelayLeaveQueue:Hide()
    end
end)

local LFGMinimapAnimation = CreateFrame("Frame")
LFGMinimapAnimation:Hide()

LFGMinimapAnimation:SetScript("OnShow", function()
    this.startTime = GetTime()
    this.frameIndex = 0
end)
LFGMinimapAnimation:SetScript("OnHide", function()
    _G['LFG_MinimapEye']:SetTexture('Interface\\Addons\\LFG\\images\\eye\\battlenetworking0')
end)

LFGMinimapAnimation:SetScript("OnUpdate", function()
    local plus = 0.10 --seconds
    local gt = GetTime() * 1000
    local st = (this.startTime + plus) * 1000
    if gt >= st then

        if this.frameIndex < 28 then
            this.frameIndex = this.frameIndex + 1
        else
            this.frameIndex = 0
        end

        _G['LFG_MinimapEye']:SetTexture('Interface\\Addons\\LFG\\images\\eye\\battlenetworking' .. this.frameIndex)

        this.startTime = GetTime()

    end
end)

local LFGTime = CreateFrame("Frame")
LFGTime:Hide()
LFGTime.second = -1
LFGTime.diff = 0

LFGTime:SetScript("OnShow", function()
    lfdebug('lfgtime SHOW call LFGTime.second = ' .. LFGTime.second .. ' my:' .. tonumber(date("%S", time())))
    lfdebug('diff = ' .. LFGTime.diff)
    this.startTime = GetTime()
    this.execAt = {}
    this.resetAt = {}
end)

LFGTime:SetScript("OnUpdate", function()
    local plus = 0.5 --seconds
    local gt = GetTime() * 1000
    local st = (this.startTime + plus) * 1000
    if gt >= st then

        this.startTime = GetTime()

        LFGTime.second = tonumber(date("%S", time())) + LFGTime.diff
        if LFGTime.second < 0 then
            LFGTime.second = LFGTime.second + 60
        end
        if LFGTime.second >= 60 then
            LFGTime.second = LFGTime.second - 60
        end

        if LFGTime.second == LFG.RESET_TIME or LFGTime.second == LFG.TIME_MARGIN then

            if not this.resetAt[LFGTime.second] then

                this.resetAt[LFGTime.second] = true

                if LFG.peopleLookingForGroupsDisplay < LFG.peopleLookingForGroups or LFG.peopleLookingForGroups == 0 then
                    LFG.peopleLookingForGroupsDisplay = LFG.peopleLookingForGroups
                end

                LFG.peopleLookingForGroups = 0

                LFG.browseNames = {}

                lfdebug("RESET --- TIME IS 0 OR 30")

                for dungeon, data in next, LFG.dungeons do
                    --reset dungeon spam
                    LFG.dungeonsSpam[data.code] = { tank = 0, healer = 0, damage = 0 }
                    --reset myRole
                    if LFG.groupFullCode == '' and not LFG.inGroup then
                        LFG.dungeons[dungeon].myRole = ''
                    end
                end
                this.execAt = {}

            end
        end

        if (LFGTime.second > 2 and LFGTime.second < 27) or
                (LFGTime.second > 32 and LFGTime.second < 57) then

            this.resetAt = {}

            if not this.execAt[LFGTime.second] then
                BrowseDungeonListFrame_Update()
                this.execAt[LFGTime.second] = true
            end

        end

        if LFGTime.second == 28 or LFGTime.second == 58 then
            --check for 0 at 28 and 58
            for dungeon, data in next, LFG.dungeons do
                if LFG.dungeonsSpam[data.code].tank == 0 then
                    LFG.dungeonsSpamDisplay[data.code].tank = LFG.dungeonsSpam[data.code].tank
                end
                if LFG.dungeonsSpam[data.code].healer == 0 then
                    LFG.dungeonsSpamDisplay[data.code].healer = LFG.dungeonsSpam[data.code].healer
                end
                if LFG.dungeonsSpam[data.code].damage == 0 then
                    LFG.dungeonsSpamDisplay[data.code].damage = LFG.dungeonsSpam[data.code].damage
                end
                LFG.dungeonsSpamDisplayLFM[data.code] = 0
            end
        end


    end
end)

local LFGGoingWithPicker = CreateFrame("Frame")
LFGGoingWithPicker:Hide()
LFGGoingWithPicker.candidate = ''
LFGGoingWithPicker.priority = 0
LFGGoingWithPicker.dungeon = ''
LFGGoingWithPicker.myRole = ''

LFGGoingWithPicker:SetScript("OnShow", function()
    this.startTime = GetTime()
end)

LFGGoingWithPicker:SetScript("OnHide", function()
end)

LFGGoingWithPicker:SetScript("OnUpdate", function()
    local plus = 1 --seconds
    local gt = GetTime() * 1000
    local st = (this.startTime + plus) * 1000
    if gt >= st then

        local dungeonName = LFG.dungeonNameFromCode(LFGGoingWithPicker.dungeon)
        if LFG.dungeons[dungeonName] then
            LFG.dungeons[dungeonName].myRole = LFGGoingWithPicker.myRole
        end

        SendChatMessage('goingWith:' .. LFGGoingWithPicker.candidate .. ':' .. LFGGoingWithPicker.dungeon .. ':' .. LFGGoingWithPicker.myRole, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))

        LFG.foundGroup = true

        LFGGoingWithPicker.candidate = ''
        LFGGoingWithPicker.myRole = ''
        LFGGoingWithPicker.priority = 0
        LFGGoingWithPicker.dungeon = ''
        LFGGoingWithPicker:Hide()
    end
end)

local COLOR_RED = '|cffff222a'
local COLOR_ORANGE = '|cffff8000'
local COLOR_GREEN = '|cff1fba1f'
local COLOR_HUNTER = '|cffabd473'
local COLOR_YELLOW = '|cffffff00'
local COLOR_WHITE = '|cffffffff'
local COLOR_DISABLED = '|cffaaaaaa'
local COLOR_DISABLED2 = '|cff666666'
local COLOR_TANK = '|cff0070de'
local COLOR_HEALER = COLOR_GREEN
local COLOR_DAMAGE = COLOR_RED

-- dungeon complete animation
local LFGDungeonComplete = CreateFrame("Frame")
LFGDungeonComplete:Hide()
LFGDungeonComplete.frameIndex = 0
LFGDungeonComplete.dungeonInProgress = false

LFGDungeonComplete:SetScript("OnShow", function()
    this.startTime = GetTime()
    LFGDungeonComplete.frameIndex = 0
    _G['LFGDungeonComplete']:SetAlpha(0)
    _G['LFGDungeonComplete']:Show()
end)

LFGDungeonComplete:SetScript("OnHide", function()
    --    this.startTime = GetTime()
end)

LFGDungeonComplete:SetScript("OnUpdate", function()
    local plus = 0.03 --seconds
    local gt = GetTime() * 1000
    local st = (this.startTime + plus) * 1000
    if gt >= st then
        this.startTime = GetTime()
        local frame = ''
        if LFGDungeonComplete.frameIndex < 10 then
            frame = frame .. '0' .. LFGDungeonComplete.frameIndex
        else
            frame = frame .. LFGDungeonComplete.frameIndex
        end
        _G['LFGDungeonCompleteFrame']:SetTexture('Interface\\addons\\LFG\\images\\dungeon_complete\\dungeon_complete_' .. frame)
        if LFGDungeonComplete.frameIndex < 35 then
            _G['LFGDungeonComplete']:SetAlpha(_G['LFGDungeonComplete']:GetAlpha() + 0.03)
        end
        if LFGDungeonComplete.frameIndex > 119 then
            _G['LFGDungeonComplete']:SetAlpha(_G['LFGDungeonComplete']:GetAlpha() - 0.03)
        end
        if LFGDungeonComplete.frameIndex >= 150 then
            _G['LFGDungeonComplete']:Hide()
            _G['LFGDungeonStatus']:Hide()
            _G['LFGDungeonCompleteFrame']:SetTexture('Interface\\addons\\LFG\\images\\dungeon_complete\\dungeon_complete_00')
            LFGDungeonComplete:Hide()

            local index = 0
            if LFG.bosses[LFG.groupFullCode] then
                for _, boss in next, LFG.bosses[LFG.groupFullCode] do
                    index = index + 1
                    LFG.objectivesFrames[index]:Hide()
                    LFG.objectivesFrames[index].completed = false
                    _G["LFGObjective" .. index .. 'ObjectiveComplete']:Hide()
                    _G["LFGObjective" .. index .. 'ObjectivePending']:Hide()
                    _G["LFGObjective" .. index .. 'Objective']:SetText('')
                end
            end
            --LFG.objectivesFrames = {}
        end
        LFGDungeonComplete.frameIndex = LFGDungeonComplete.frameIndex + 1
    end
end)

-- objectives
local LFGObjectives = CreateFrame("Frame")
LFGObjectives:Hide()
LFGObjectives:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
LFGObjectives.collapsed = false
LFGObjectives.closedByUser = false
LFGObjectives.lastObjective = 0
LFGObjectives.leftOffset = -80
LFGObjectives.frameIndex = 0
LFGObjectives.objectivesComplete = 0

function close_lfg_objectives()
    LFGObjectives.closedByUser = true
    _G['LFGDungeonStatus']:Hide()
end

-- swoooooooosh

LFGObjectives:SetScript("OnShow", function()
    LFGObjectives.leftOffset = -80
    LFGObjectives.frameIndex = 0
    this.startTime = GetTime()
end)

LFGObjectives:SetScript("OnHide", function()
    --    this.startTime = GetTime()
end)

LFGObjectives:SetScript("OnUpdate", function()
    local plus = 0.001 --seconds
    local gt = GetTime() * 1000
    local st = (this.startTime + plus) * 1000
    if gt >= st then
        this.startTime = GetTime()
        LFGObjectives.frameIndex = LFGObjectives.frameIndex + 1
        LFGObjectives.leftOffset = LFGObjectives.leftOffset + 5
        _G["LFGObjective" .. LFGObjectives.lastObjective .. 'Swoosh']:SetPoint("TOPLEFT", _G["LFGObjective" .. LFGObjectives.lastObjective], "TOPLEFT", LFGObjectives.leftOffset, 5)
        if LFGObjectives.frameIndex <= 10 then
            _G["LFGObjective" .. LFGObjectives.lastObjective .. 'Swoosh']:SetAlpha(LFGObjectives.frameIndex / 10)
        end
        if LFGObjectives.frameIndex >= 30 then
            _G["LFGObjective" .. LFGObjectives.lastObjective .. 'Swoosh']:SetAlpha(1 - LFGObjectives.frameIndex / 40)
        end
        if LFGObjectives.leftOffset >= 120 then
            LFGObjectives:Hide()
            _G["LFGObjective" .. LFGObjectives.lastObjective .. 'Swoosh']:SetAlpha(0)
        end
    end
end)

LFGObjectives:SetScript("OnEvent", function()
    if event then
        if event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
            local creatureDied = arg1
            lfdebug(creatureDied)
            if LFG.bosses[LFG.groupFullCode] then
                for _, boss in next, LFG.bosses[LFG.groupFullCode] do
                    --creatureDied == 'You have slain ' .. boss .. '!'
                    if creatureDied == boss .. ' dies.' then
                        LFGObjectives.objectiveComplete(boss)
                        return true
                    end
                end
            end
        end
    end
end)

-- fill available dungeons delayer because UnitLevel(member who just joined) returns 0
local LFGFillAvailableDungeonsDelay = CreateFrame("Frame")
LFGFillAvailableDungeonsDelay.triggers = 0
LFGFillAvailableDungeonsDelay.queueAfterIfPossible = false
LFGFillAvailableDungeonsDelay:Hide()
LFGFillAvailableDungeonsDelay:SetScript("OnShow", function()
    this.startTime = GetTime()
end)

LFGFillAvailableDungeonsDelay:SetScript("OnHide", function()
    if LFGFillAvailableDungeonsDelay.triggers < 10 then
        LFG.fillAvailableDungeons(LFGFillAvailableDungeonsDelay.queueAfterIfPossible)
        LFGFillAvailableDungeonsDelay.triggers = LFGFillAvailableDungeonsDelay.triggers + 1
    else
        --lferror('Error occurred at LFGFillAvailableDungeonsDelay triggers = 10. Please report this to Bennylava.')
    end
end)
LFGFillAvailableDungeonsDelay:SetScript("OnUpdate", function()
    local plus = 0.1 --seconds
    local gt = GetTime() * 1000
    local st = (this.startTime + plus) * 1000
    if gt >= st then
        LFGFillAvailableDungeonsDelay:Hide()
    end
end)

-- channel join delayer

local LFGChannelJoinDelay = CreateFrame("Frame")
LFGChannelJoinDelay:Hide()

LFGChannelJoinDelay:SetScript("OnShow", function()
    this.startTime = GetTime()
end)

LFGChannelJoinDelay:SetScript("OnHide", function()
    LFG.checkLFGChannel()
end)

LFGChannelJoinDelay:SetScript("OnUpdate", function()
    local plus = 15 --seconds
    local gt = GetTime() * 1000
    local st = (this.startTime + plus) * 1000
    if gt >= st then
        LFGChannelJoinDelay:Hide()
    end
end)

local LFGQueue = CreateFrame("Frame")
LFGQueue:Hide()

-- group invite timer

local LFGInvite = CreateFrame("Frame")
LFGInvite:Hide()
LFGInvite.inviteIndex = 1
LFGInvite:SetScript("OnShow", function()
    this.startTime = GetTime()
    LFGInvite.inviteIndex = 1
    local awesomeButton = _G['LFGGroupReadyAwesome']
    awesomeButton:SetText('Waiting Players (' .. LFG.groupSizeMax - GetNumPartyMembers() - 1 .. ')')
    awesomeButton:Disable()
end)

LFGInvite:SetScript("OnUpdate", function()
    local plus = 0.5 --seconds
    local gt = GetTime() * 1000
    local st = (this.startTime + plus) * 1000
    if gt >= st then
        this.startTime = GetTime()

        LFGInvite.inviteIndex = this.inviteIndex + 1

        if not LFG.group[LFG.groupFullCode] then
            LFGInvite:Hide()
            LFGInvite.inviteIndex = 1
            return
        end

        if LFGInvite.inviteIndex == 2 then
            if LFG.group[LFG.groupFullCode].healer ~= '' then
                InviteUnit(LFG.group[LFG.groupFullCode].healer)
            end
        end
        if LFGInvite.inviteIndex == 3 then
            if LFG.group[LFG.groupFullCode].damage1 ~= '' then
                InviteUnit(LFG.group[LFG.groupFullCode].damage1)
            end
        end
        if LFGInvite.inviteIndex == 4 and LFGInvite.inviteIndex <= LFG.groupSizeMax then
            if LFG.group[LFG.groupFullCode].damage2 ~= '' then
                InviteUnit(LFG.group[LFG.groupFullCode].damage2)
            end
        end
        if LFGInvite.inviteIndex == 5 and LFGInvite.inviteIndex <= LFG.groupSizeMax then
            if LFG.group[LFG.groupFullCode].damage3 ~= '' then
                InviteUnit(LFG.group[LFG.groupFullCode].damage3)
                LFGInvite:Hide()
                LFGInvite.inviteIndex = 1
            end
        end
    end
end)

-- role check timer

local LFGRoleCheck = CreateFrame("Frame")
LFGRoleCheck:Hide()

LFGRoleCheck:SetScript("OnShow", function()
    this.startTime = GetTime()
end)

LFGRoleCheck:SetScript("OnHide", function()
    if LFG.isLeader then
        if LFG.findingMore then
        else
            lfprint('A member of your group has not confirmed his role.')
            PlaySoundFile("Interface\\Addons\\LFG\\sound\\lfg_denied.ogg")
            _G['findMoreButton']:Enable()
        end
    end
    _G['LFGRoleCheck']:Hide()
end)

LFGRoleCheck:SetScript("OnUpdate", function()
    local plus = LFG.ROLE_CHECK_TIME --seconds
    if LFG.isLeader then
        plus = plus + 2 --leader waits 2 more second to hide
    end
    local gt = GetTime() * 1000
    local st = (this.startTime + plus) * 1000
    if gt >= st then
        LFGRoleCheck:Hide()

        if LFG.isLeader then
            lfprint('A member of your group does not have the ' .. COLOR_HUNTER .. '[LFG] ' .. COLOR_WHITE ..
                    'addon. Looking for more is disabled. (Type ' .. COLOR_HUNTER .. '/lfg advertise ' .. COLOR_WHITE .. ' to send them a link)')
            _G['findMoreButton']:Disable()

        else
            declineRole()
        end
    end
end)

-- who counter timer

local LFGWhoCounter = CreateFrame("Frame")
LFGWhoCounter:Hide()
LFGWhoCounter.people = 0
LFGWhoCounter.listening = false
LFGWhoCounter:SetScript("OnShow", function()
    this.startTime = GetTime()
    LFGWhoCounter.people = 0
    LFGWhoCounter.listening = true
    lfprint('Checking people online with the addon (5secs)...')
end)

LFGWhoCounter:SetScript("OnHide", function()
    LFGWhoCounter.people = LFGWhoCounter.people + 1 -- + me
    lfprint('Found ' .. COLOR_GREEN .. LFGWhoCounter.people .. COLOR_WHITE .. ' online using LFG addon.')
    LFGWhoCounter.listening = false
end)

LFGWhoCounter:SetScript("OnUpdate", function()
    local plus = 5 --seconds
    local gt = GetTime() * 1000
    local st = (this.startTime + plus) * 1000
    if gt >= st then
        LFGWhoCounter:Hide()
    end
end)

--closes the group ready frame when someone leaves queue from the button
local LFGGroupReadyFrameCloser = CreateFrame("Frame")
LFGGroupReadyFrameCloser:Hide()
LFGGroupReadyFrameCloser.response = ''
LFGGroupReadyFrameCloser:SetScript("OnShow", function()
    this.startTime = GetTime()
end)

LFGGroupReadyFrameCloser:SetScript("OnHide", function()
end)
LFGGroupReadyFrameCloser:SetScript("OnUpdate", function()
    local plus = LFG.ROLE_CHECK_TIME --time after i click leave queue, afk
    local plus2 = LFG.ROLE_CHECK_TIME + 5 --time after i close the window
    local gt = GetTime() * 1000
    local st = (this.startTime + plus) * 1000
    local st2 = (this.startTime + plus2) * 1000
    if gt >= st then
        if LFGGroupReadyFrameCloser.response == '' then
            sayNotReady()
        end
    end
    if gt >= st2 then
        _G['LFGReadyStatus']:Hide()
        lfprint('A member of your group has not accepted the invitation. You are rejoining the queue.')
        if LFG.isLeader then
            leaveQueue('LFGGroupReadyFrameCloser isleader = true')
            LFG.fillAvailableDungeons(true) -- queueAfter = true
        end
        if LFGGroupReadyFrameCloser.response == 'notReady' then
            --doesnt trigger for leader, cause it leaves queue
            --which resets response to ''
            --LeaveParty()
            LFGGroupReadyFrameCloser.response = ''
        end
        LFGGroupReadyFrameCloser:Hide()
    end
end)

-- communication

local LFGComms = CreateFrame("Frame")
LFGComms:Hide()
LFGComms:RegisterEvent("CHAT_MSG_CHANNEL")
LFGComms:RegisterEvent("CHAT_MSG_WHISPER")
LFGComms:RegisterEvent("CHAT_MSG_CHANNEL_LEAVE")
LFGComms:RegisterEvent("PARTY_INVITE_REQUEST")
LFGComms:RegisterEvent("CHAT_MSG_ADDON")
LFGComms:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
LFGComms:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE_USER")
LFGComms:RegisterEvent("CHAT_MSG_SYSTEM")
--"CHAT_MSG_CHANNEL_NOTICE_USER"
--Category: Communication
--
--Fired when something changes in the channel like moderation enabled, user is kicked, announcements changed and so on. CHAT_*_NOTICE in GlobalStrings.lua has a full list of available types.
--
--arg1
--type ("ANNOUNCEMENTS_OFF", "ANNOUNCEMENTS_ON", "BANNED", "OWNER_CHANGED", "INVALID_NAME", "INVITE", "MODERATION_OFF", "MODERATION_ON", "MUTED", "NOT_MEMBER", "NOT_MODERATED", "SET_MODERATOR", "UNSET_MODERATOR" )
--arg2
--If arg5 has a value then this is the user affected ( eg: "Player Foo has been kicked by Bar" ), if arg5 has no value then it's the person who caused the event ( eg: "Channel Moderation has been enabled by Bar" )
--arg4
--Channel name with number
--arg5
--Player that caused the event (eg "Player Foo has been kicked by Bar" )

LFGComms:SetScript("OnEvent", function()
    if event then
        if event == 'CHAT_MSG_CHANNEL_NOTICE_USER' then

            if arg1 == 'PLAYER_ALREADY_MEMBER' then
                -- probably only used when reloadui
                LFG.checkLFGChannel()
            end
            lfdebug('CHAT_MSG_CHANNEL_NOTICE_USER')
            lfdebug(arg1) --event,
            lfdebug(arg2) -- somename
            lfdebug(arg3) -- blank
            lfdebug(arg4) -- 6.Lft
            lfdebug(arg5) -- blank
            lfdebug('channel index = ' .. LFG.channelIndex) -- blank
        end
        -- NOTE: CHAT_MSG_CHANNEL_NOTICE handled only in channelMonitorFrame below.

        if event == 'CHAT_MSG_ADDON' and arg1 == LFG_ADDON_CHANNEL then
            lfdebug(arg4 .. ' says : ' .. arg2)
            -- Fix :danage typo from old clients
            if string.find(arg2, ":danage") then
                arg2 = string.gsub(arg2, ":danage", ":damage")
                if not LFG.WarnedPlayers[arg4] then
                    SendChatMessage("LFG Alert: Your version has a typo (danage). Please update to fix your icons!", "WHISPER", nil, arg4)
                    LFG.WarnedPlayers[arg4] = true
                end
            end
            -- groups v2: whisper/party/raid messages
            if arg4 ~= me then
                LFG.Grp_HandleAddonMsg(arg1, arg2, arg3, arg4)
            end
            if string.sub(arg2, 1, 11) == 'objectives:' and arg4 ~= me then
                local objEx = StringSplit(arg2, ':')
                if LFG.groupFullCode ~= objEx[2] then
                    LFG.groupFullCode = objEx[2]
                end

                local objectivesString = StringSplit(objEx[3], '-')

                local complete = 0

                for stringIndex, s in next, objectivesString do
                    if s then
                        if s == '1' then
                            complete = complete + 1
                            local index = 0
                            if LFG.bosses[LFG.groupFullCode] then
                                for _, boss in next, LFG.bosses[LFG.groupFullCode] do
                                    index = index + 1
                                    if index == stringIndex then
                                        LFGObjectives.objectiveComplete(boss, true)
                                    end
                                end
                            end
                        end
                    end
                end

                if not LFGObjectives.closedByUser and not _G["LFGDungeonStatus"]:IsVisible() then
                    LFG.showDungeonObjectives('code_for_debug_only', complete)
                end
            end
            if string.sub(arg2, 1, 11) == 'notReadyAs:' then

                PlaySoundFile("Interface\\Addons\\LFG\\sound\\lfg_denied.ogg")

                local readyEx = StringSplit(arg2, ':')
                local role = readyEx[2]
                if role == 'tank' then
                    _G['LFGReadyStatusReadyTank']:SetTexture('Interface\\addons\\LFG\\images\\readycheck-notready')
                end
                if role == 'healer' then
                    _G['LFGReadyStatusReadyHealer']:SetTexture('Interface\\addons\\LFG\\images\\readycheck-notready')
                end
                if role == 'damage' then
                    if _G['LFGReadyStatusReadyDamage1']:GetTexture() == 'Interface\\addons\\LFG\\images\\readycheck-waiting' then
                        _G['LFGReadyStatusReadyDamage1']:SetTexture('Interface\\addons\\LFG\\images\\readycheck-notready')
                    elseif _G['LFGReadyStatusReadyDamage2']:GetTexture() == 'Interface\\addons\\LFG\\images\\readycheck-waiting' then
                        _G['LFGReadyStatusReadyDamage2']:SetTexture('Interface\\addons\\LFG\\images\\readycheck-notready')
                    elseif _G['LFGReadyStatusReadyDamage3']:GetTexture() == 'Interface\\addons\\LFG\\images\\readycheck-waiting' then
                        _G['LFGReadyStatusReadyDamage3']:SetTexture('Interface\\addons\\LFG\\images\\readycheck-notready')
                    end
                end
            end
            if string.sub(arg2, 1, 8) == 'readyAs:' then
                local readyEx = StringSplit(arg2, ':')
                local role = readyEx[2]

                LFG.showPartyRoleIcons(role, arg4)

                if role == 'tank' then
                    _G['LFGReadyStatusReadyTank']:SetTexture('Interface\\addons\\LFG\\images\\readycheck-ready')
                end
                if role == 'healer' then
                    _G['LFGReadyStatusReadyHealer']:SetTexture('Interface\\addons\\LFG\\images\\readycheck-ready')
                end
                if role == 'damage' then
                    if _G['LFGReadyStatusReadyDamage1']:GetTexture() == 'Interface\\addons\\LFG\\images\\readycheck-waiting' then
                        _G['LFGReadyStatusReadyDamage1']:SetTexture('Interface\\addons\\LFG\\images\\readycheck-ready')
                    elseif _G['LFGReadyStatusReadyDamage2']:GetTexture() == 'Interface\\addons\\LFG\\images\\readycheck-waiting' then
                        _G['LFGReadyStatusReadyDamage2']:SetTexture('Interface\\addons\\LFG\\images\\readycheck-ready')
                    elseif _G['LFGReadyStatusReadyDamage3']:GetTexture() == 'Interface\\addons\\LFG\\images\\readycheck-waiting' then
                        _G['LFGReadyStatusReadyDamage3']:SetTexture('Interface\\addons\\LFG\\images\\readycheck-ready')
                    end
                end
                if _G['LFGReadyStatusReadyTank']:GetTexture() == 'Interface\\addons\\LFG\\images\\readycheck-ready' and
                        _G['LFGReadyStatusReadyHealer']:GetTexture() == 'Interface\\addons\\LFG\\images\\readycheck-ready' and
                        _G['LFGReadyStatusReadyDamage1']:GetTexture() == 'Interface\\addons\\LFG\\images\\readycheck-ready' and
                        _G['LFGReadyStatusReadyDamage2']:GetTexture() == 'Interface\\addons\\LFG\\images\\readycheck-ready' and
                        _G['LFGReadyStatusReadyDamage3']:GetTexture() == 'Interface\\addons\\LFG\\images\\readycheck-ready' then
                    _G['LFGReadyStatus']:Hide()
                    LFGGroupReadyFrameCloser:Hide()
                    local _, numCompletedObjectives = LFG.getDungeonCompletion()
                    LFG.showDungeonObjectives('dummy', numCompletedObjectives)
                    --promote the tank to leader
                end
                if LFG.isLeader and role == 'tank' and arg4 ~= me then
                    PromoteToLeader(arg4)
                end
            end
            if string.sub(arg2, 1, 11) == 'LFGVersion:' and arg4 ~= me then
                if not LFG.showedUpdateNotification then
                    local verEx = StringSplit(arg2, ':')
                    if LFG.ver(verEx[2]) > LFG.ver(addonVer) then
                        lfprint(COLOR_HUNTER .. 'Looking For Group ' .. COLOR_WHITE .. ' - new version available ' ..
                                COLOR_GREEN .. 'v' .. verEx[2] .. COLOR_WHITE .. ' (current version ' ..
                                COLOR_ORANGE .. 'v' .. addonVer .. COLOR_WHITE .. ')')
                        lfprint('Update yours at ' .. COLOR_HUNTER .. 'https://github.com/thezephyrsong/LFG')
                        LFG.showedUpdateNotification = true
                    end
                end
            end

            if string.sub(arg2, 1, 11) == 'leaveQueue:' and arg4 ~= me then
                leaveQueue('leaveQueue: addon party')
            end

            if string.sub(arg2, 1, 8) == 'minimap:' then
                if not LFG.isLeader then
                    local miniEx = StringSplit(arg2, ':')
                    local code = miniEx[2]
                    local tank = tonumber(miniEx[3])
                    local healer = tonumber(miniEx[4])
                    local damage = tonumber(miniEx[5])

                    LFG.LFMDungeonCode = code

                    LFG.group = {} --reset old entries
                    LFG.group[code] = {
                        tank = '',
                        healer = '',
                        damage1 = '',
                        damage2 = '',
                        damage3 = ''
                    }
                    if tank == 1 then
                        LFG.group[code].tank = 'DummyTank'
                    end
                    if healer == 1 then
                        LFG.group[code].healer = 'DummyHealer'
                    end
                    if damage > 0 then
                        LFG.group[code].damage1 = 'DummyDamage1'
                    end
                    if damage > 1 then
                        LFG.group[code].damage2 = 'DummyDamage2'
                    end
                    if damage > 2 then
                        LFG.group[code].damage3 = 'DummyDamage3'
                    end
                end
            end
            if string.sub(arg2, 1, 14) == 'LFMPartyReady:' then

                local queueEx = StringSplit(arg2, ':')
                local mCode = queueEx[2]
                local objectivesCompleted = queueEx[3]
                local objectivesTotal = queueEx[4]

                LFG.groupFullCode = mCode
                LFG.LFMDungeonCode = mCode

                --uncheck everything
                _G['Dungeon_' .. LFG.groupFullCode .. '_CheckButton']:SetChecked(false)
                LFG.findingGroup = false
                LFG.findingMore = false
                local background = ''
                local dungeonName = 'unknown'
                for d, data in next, LFG.dungeons do
                    if data.code == mCode then
                        background = data.background
                        dungeonName = d
                    end
                end

                local dungeonEntry = LFG.dungeonFromCode(mCode)
                local myRole = (dungeonEntry and dungeonEntry.myRole ~= '') and dungeonEntry.myRole or (LFG_ROLE or 'damage')

                LFG.SetSingleRole(myRole)

                _G['LFGGroupReadyBackground']:SetTexture('Interface\\addons\\LFG\\images\\background\\ui-lfg-background-' .. background)
                _G['LFGGroupReadyRole']:SetTexture('Interface\\addons\\LFG\\images\\' .. myRole .. '2')
                _G['LFGGroupReadyMyRole']:SetText(LFG.ucFirst(myRole))
                _G['LFGGroupReadyDungeonName']:SetText(dungeonName)
                _G['LFGGroupReadyObjectivesCompleted']:SetText(objectivesCompleted .. '/' .. objectivesTotal .. ' Bosses Defeated')

                LFG.readyStatusReset()
                _G['LFGGroupReady']:Show()
                LFGGroupReadyFrameCloser:Show()

                LFG.fixMainButton()
                _G['LFGlfg']:Hide()

                PlaySoundFile("Interface\\Addons\\LFG\\sound\\levelup2.ogg")
                LFGQueue:Hide()

                if LFG.isLeader then
                    SendChatMessage("[LFG]:lfg_group_formed:" .. mCode .. ":" .. time() - LFG.queueStartTime, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
                end
            end
            if string.sub(arg2, 1, 10) == 'weInQueue:' then
                local queueEx = StringSplit(arg2, ':')
                LFG.weInQueue(queueEx[2])
            end
            if string.sub(arg2, 1, 10) == 'roleCheck:' then
                -- Force clean the LFMGroup before starting role check to prevent stale data
                LFG.LFMGroup = {
                    tank = '',
                    healer = '',
                    damage1 = '',
                    damage2 = '',
                    damage3 = '',
                }

                if arg4 ~= me then
                    PlaySoundFile("Interface\\AddOns\\LFG\\sound\\lfg_rolecheck.ogg")
                end
                lfprint('A role check has been initiated. Your group will be queued when all members have selected a role.')
                UIErrorsFrame:AddMessage("|cff69ccf0[LFG] |cffffff00A role check has been initiated. Your group will be queued when all members have selected a role.")

                local argEx = StringSplit(arg2, ':')
                local mCode = argEx[2]
                LFG.LFMDungeonCode = mCode
                LFG.resetGroup()

                lfdebug('my role is : ' .. (LFG.dungeons[LFG.dungeonNameFromCode(LFG.LFMDungeonCode)] and LFG.dungeons[LFG.dungeonNameFromCode(LFG.LFMDungeonCode)].myRole or 'unknown'))

                local lfmdName = LFG.dungeonNameFromCode(LFG.LFMDungeonCode)
                local lfmdEntry = LFG.dungeons[lfmdName]

                --if we dont know my prev role
                if lfmdEntry and lfmdEntry.myRole == '' then

                    if _G['RoleTank']:GetChecked() then
                        lfmdEntry.myRole = 'tank'
                    elseif _G['RoleHealer']:GetChecked() then
                        lfmdEntry.myRole = 'healer'
                    elseif _G['RoleDamage']:GetChecked() then
                        lfmdEntry.myRole = 'damage'
                    else
                        lfmdEntry.myRole = LFG.GetPossibleRoles()
                    end
                end

                local lfmdRole = (lfmdEntry and lfmdEntry.myRole) or ''
                _G['roleCheckTank']:SetChecked(lfmdRole == 'tank')
                _G['roleCheckHealer']:SetChecked(lfmdRole == 'healer')
                _G['roleCheckDamage']:SetChecked(lfmdRole == 'damage')

                lfdebug(' my  role after checks : ' .. lfmdRole)

                _G['LFGRoleCheckAcceptRole']:Enable()

                _G['LFGRoleCheckQForText']:SetText(COLOR_WHITE .. "Queued for " .. COLOR_YELLOW .. LFG.dungeonNameFromCode(mCode))
                _G['LFGRoleCheck']:Show()
                _G['LFGGroupReady']:Hide()
                LFGRoleCheck:Show()
            end

            if string.sub(arg2, 1, 11) == 'acceptRole:' then
                local roleEx = StringSplit(arg2, ':')
                local roleColor = ''

                if arg4 == me and not LFG.isLeader then
                    LFGRoleCheck:Hide()
                end

                LFG.showPartyRoleIcons(roleEx[2], arg4)

                if roleEx[2] == 'tank' then
                    roleColor = COLOR_TANK
                end
                if roleEx[2] == 'healer' then
                    roleColor = COLOR_HEALER
                end
                if roleEx[2] == 'damage' then
                    roleColor = COLOR_DAMAGE
                end
                if arg4 == me then
                    lfprint('You have chosen: ' .. roleColor .. LFG.ucFirst(roleEx[2]))
                end

                -- Check if this is an Elite Encounter for flexible role assignment
                if LFG.isEliteEncounter(LFG.LFMDungeonCode) then
                    if roleEx[2] == 'tank' then
                        LFG.LFMGroup.tank = arg4
                    end
                    if roleEx[2] == 'healer' then
                        LFG.LFMGroup.healer = arg4
                    end
                    if roleEx[2] == 'damage' then
                        if LFG.LFMGroup.damage1 == '' then
                            LFG.LFMGroup.damage1 = arg4
                        elseif LFG.LFMGroup.damage2 == '' then
                            LFG.LFMGroup.damage2 = arg4
                        elseif LFG.LFMGroup.damage3 == '' then
                            LFG.LFMGroup.damage3 = arg4
                        end
                    end
                else
                    if roleEx[2] == 'tank' then

                        _G['roleCheckTank']:SetChecked(false)
                        _G['roleCheckTank']:Disable()
                        _G['LFGRoleCheckRoleTank']:SetDesaturated(1)

                        if _G['LFGRoleCheck']:IsVisible() and LFG_ROLE == 'tank' then
                            _G['LFGRoleCheckAcceptRole']:Disable()
                        end

                        if LFG_ROLE == 'tank' then
                            if _G['LFGRoleCheck']:IsVisible() then
                                _G['LFGRoleCheckAcceptRole']:Disable()
                                _G['roleCheckTank']:SetChecked(false)
                                _G['roleCheckTank']:Disable()
                            else
                                --not visible means confirmed by me
                                --for me
                                --should not get here i think, button will be disabled
                                if LFG.isLeader then
                                    if arg4 ~= me then
                                        lfprint(LFG.classColors[LFG.playerClass(arg4)].c .. arg4 .. COLOR_WHITE .. ' has chosen '
                                                .. COLOR_TANK .. 'Tank' .. COLOR_WHITE .. ' but you already confirmed this role.')
                                        lfprint('Queueing aborted.')
                                        leaveQueue(' two tanks')
                                        return false
                                    end
                                else
                                    --for other tank
                                    if LFG.LFMGroup.tank ~= '' and LFG.LFMGroup.tank ~= me then
                                        lfprint(COLOR_TANK .. 'Tank ' .. COLOR_WHITE .. 'role has already been filled by ' .. LFG.classColors[LFG.playerClass(LFG.LFMGroup.tank)].c .. LFG.LFMGroup.tank
                                                .. COLOR_WHITE .. '. Please select a different role to rejoin the queue.')
                                        return false
                                    end
                                end
                            end
                        end
                        LFG.LFMGroup.tank = arg4
                    end

                    if roleEx[2] == 'healer' then

                        _G['roleCheckHealer']:SetChecked(false)
                        _G['roleCheckHealer']:Disable()
                        _G['LFGRoleCheckRoleHealer']:SetDesaturated(1)

                        if _G['LFGRoleCheck']:IsVisible() and LFG_ROLE == 'healer' then
                            _G['LFGRoleCheckAcceptRole']:Disable()
                        end

                        if LFG_ROLE == 'healer' then
                            if _G['LFGRoleCheck']:IsVisible() then
                                _G['LFGRoleCheckAcceptRole']:Disable()
                                _G['roleCheckHealer']:SetChecked(false)
                                _G['roleCheckHealer']:Disable()
                            else
                                --not visible means confirmed by me
                                --for me
                                --should not get here i think, button will be disabled
                                if LFG.isLeader then
                                    if arg4 ~= me then
                                        lfprint(LFG.classColors[LFG.playerClass(arg4)].c .. arg4 .. COLOR_WHITE .. ' has chosen '
                                                .. COLOR_HEALER .. 'Healer' .. COLOR_WHITE .. ' but you already confirmed this role.')
                                        lfprint('Queueing aborted.')
                                        leaveQueue('two healers')
                                        return false
                                    end
                                else
                                    --for other healer
                                    if LFG.LFMGroup.healer ~= '' then
                                        lfprint(COLOR_HEALER .. 'Healer ' .. COLOR_WHITE .. 'role has already been filled by ' .. LFG.classColors[LFG.playerClass(LFG.LFMGroup.healer)].c .. LFG.LFMGroup.healer
                                                .. COLOR_WHITE .. '. Please select a different role to rejoin the queue.')
                                        return false
                                    end
                                end
                            end
                        end
                        LFG.LFMGroup.healer = arg4
                    end

                    if roleEx[2] == 'damage' then

                        local dpsFilled = false

                        if LFG.LFMGroup.damage1 == '' then
                            LFG.LFMGroup.damage1 = arg4
                        elseif LFG.LFMGroup.damage2 == '' then
                            LFG.LFMGroup.damage2 = arg4
                        elseif LFG.LFMGroup.damage3 == '' then
                            LFG.LFMGroup.damage3 = arg4

                            dpsFilled = true
                            _G['roleCheckDamage']:SetChecked(false)
                            _G['roleCheckDamage']:Disable()
                            _G['LFGRoleCheckRoleDamage']:SetDesaturated(1)

                            if _G['LFGRoleCheck']:IsVisible() and LFG_ROLE == 'damage' then
                                _G['LFGRoleCheckAcceptRole']:Disable()
                            end

                        end

                        if LFG_ROLE == 'damage' or dpsFilled then

                            if _G['LFGRoleCheck']:IsVisible() then

                                -- lock accept buttons if we have 3 dps already
                                if LFG.LFMGroup.damage1 ~= '' and
                                        LFG.LFMGroup.damage2 ~= '' and
                                        LFG.LFMGroup.damage3 ~= '' then
                                    --_G['LFGRoleCheckAcceptRole']:Disable()
                                    _G['roleCheckDamage']:SetChecked(false)
                                    _G['roleCheckDamage']:Disable()
                                    _G['LFGRoleCheckRoleDamage']:SetDesaturated(1)
                                end

                            else
                                if dpsFilled then
                                    if LFG.isLeader then
                                        if arg4 ~= me then
                                            -- Only prevent 4th DPS, not the 3rd one completing the group
                                            if LFG.LFMGroup.damage1 ~= '' and LFG.LFMGroup.damage2 ~= '' and LFG.LFMGroup.damage3 ~= '' and arg4 ~= LFG.LFMGroup.damage1 and arg4 ~= LFG.LFMGroup.damage2 and arg4 ~= LFG.LFMGroup.damage3 then
                                                lfprint(LFG.classColors[LFG.playerClass(arg4)].c .. arg4 .. COLOR_WHITE .. ' has chosen ' .. COLOR_DAMAGE .. 'Damage' .. COLOR_WHITE
                                                        .. ' but the group already has ' .. COLOR_DAMAGE .. '3' .. COLOR_WHITE .. ' confirmed ' .. COLOR_DAMAGE .. 'Damage' .. COLOR_WHITE .. ' members.')
                                                lfprint('Queueing aborted.')
                                                leaveQueue('4 dps')
                                                return false
                                            end
                                        end
                                    else
                                        -- Only prevent 4th DPS, not the 3rd one completing the group
                                        if LFG.LFMGroup.damage1 ~= '' and LFG.LFMGroup.damage2 ~= '' and LFG.LFMGroup.damage3 ~= '' and arg4 ~= LFG.LFMGroup.damage1 and arg4 ~= LFG.LFMGroup.damage2 and arg4 ~= LFG.LFMGroup.damage3 then
                                            lfprint(COLOR_DAMAGE .. 'Damage ' .. COLOR_WHITE .. 'role has already been filled by ' .. COLOR_DAMAGE .. '3' .. COLOR_WHITE .. ' members. Please select a different role to rejoin the queue.')
                                            return false
                                        end
                                    end
                                end
                            end
                        end

                    end
                end

                if arg4 ~= me then
                    lfprint(LFG.classColors[LFG.playerClass(arg4)].c .. arg4 .. COLOR_WHITE .. ' has chosen: ' .. roleColor .. LFG.ucFirst(roleEx[2]))
                end
                LFG.checkLFMgroup()
            end
            if string.sub(arg2, 1, 12) == 'declineRole:' then
                PlaySoundFile("Interface\\Addons\\LFG\\sound\\lfg_denied.ogg")
                LFG.checkLFMgroup(arg4)
            end
        end
        if event == 'CHAT_MSG_WHISPER' then
            -- Groups v2: whisper signups are handled via addon messages (GS)
            -- Legacy !signup plain-text fallback removed
        end
        if event == 'PARTY_INVITE_REQUEST' then
            if LFG.acceptNextInvite then
                if arg1 == LFG.onlyAcceptFrom then
                    LFG.AcceptGroupInvite()
                    LFG.acceptNextInvite = false
                else
                    LFG.DeclineGroupInvite()
                end
            end
            if not LFG.foundGroup then
                leaveQueue('PARTY_INVITE_REQUEST')
            end
        end
        if event == 'CHAT_MSG_CHANNEL_LEAVE' then
            LFG.removePlayerFromVirtualParty(arg2, false) --unknown role
        end
        if event == 'CHAT_MSG_CHANNEL' and string.find(arg1, '[LFG]', 1, true) and arg8 == LFG.channelIndex and arg2 ~= me and --for lfm
                string.find(arg1, '(LFM)', 1, true) then
            --[LFG]:stratlive:(LFM):name
            local mEx = StringSplit(arg1, ':')
            if mEx[4] == me then
                LFG.onlyAcceptFrom = arg2
                LFG.acceptNextInvite = true
            end
        end
        if event == 'CHAT_MSG_CHANNEL' and arg8 == LFG.channelIndex and string.find(arg1, 'lfg_group_formed', 1, true) then
            local gfEx = StringSplit(arg1, ':')
            local code = gfEx[3]
            local time = tonumber(gfEx[4])
            groupsFormedThisSession = groupsFormedThisSession + 1
            if LFG_CONFIG['spamChat'] then
                lfnotice(LFG.dungeonNameFromCode(code) .. ' group just formed. (type "/lfg spam" to disable this message)')
            end
            if me == 'Bennylava' then
                local totalGroups = 0
                for _, number in next, LFG_FORMED_GROUPS do
                    if number ~= 0 then
                        totalGroups = totalGroups + number
                    end
                end
                lfprint(groupsFormedThisSession .. ' this session, ' .. totalGroups .. ' total recorded.')
            end
            if not time then
                return false
            end
            if LFG.averageWaitTime == 0 then
                LFG.averageWaitTime = time
            else
                LFG.averageWaitTime = math.floor((LFG.averageWaitTime + time) / 2)
            end
            if not LFG_FORMED_GROUPS[code] then
                LFG_FORMED_GROUPS[code] = 0
            end
            LFG_FORMED_GROUPS[code] = LFG_FORMED_GROUPS[code] + 1
        end
        if event == 'CHAT_MSG_CHANNEL' and string.find(arg1, '[LFG]', 1, true) and arg8 == LFG.channelIndex and arg2 ~= me and --for lfg
                string.find(arg1, 'party:ready', 1, true) then
            local mEx = StringSplit(arg1, ':')
            LFG.groupFullCode = mEx[2] --code

            local healer = mEx[5]
            local damage1 = mEx[6]
            local damage2 = mEx[7]
            local damage3 = mEx[8]

            --check if party ready message is for me
            if me ~= healer and me ~= damage1 and me ~= damage2 and me ~= damage3 then
                return
            end

            if me == healer then
                local gfcName = LFG.dungeonNameFromCode(LFG.groupFullCode)
                if LFG.dungeons[gfcName] then LFG.dungeons[gfcName].myRole = 'healer' end
                LFG.SetSingleRole('healer')
            end
            if me == damage1 or me == damage2 or me == damage3 then
                local gfcName = LFG.dungeonNameFromCode(LFG.groupFullCode)
                if LFG.dungeons[gfcName] then LFG.dungeons[gfcName].myRole = 'damage' end
                LFG.SetSingleRole('damage')
            end

            LFG.onlyAcceptFrom = arg2
            LFG.acceptNextInvite = true

            local background = ''
            local dungeonName = 'unknown'
            for d, data in next, LFG.dungeons do
                if data.code == mEx[2] then
                    background = data.background
                    dungeonName = d
                end
            end

            local gfcEntry = LFG.dungeonFromCode(LFG.groupFullCode)
            local myRole = (gfcEntry and gfcEntry.myRole ~= '') and gfcEntry.myRole or (LFG_ROLE or 'damage')

            _G['LFGGroupReadyBackground']:SetTexture('Interface\\addons\\LFG\\images\\background\\ui-lfg-background-' .. background)
            _G['LFGGroupReadyRole']:SetTexture('Interface\\addons\\LFG\\images\\' .. myRole .. '2')
            _G['LFGGroupReadyMyRole']:SetText(LFG.ucFirst(myRole))
            _G['LFGGroupReadyDungeonName']:SetText(dungeonName)

            LFG.readyStatusReset()
            local bossCount = LFG.bosses[LFG.groupFullCode] and LFG.tableSize(LFG.bosses[LFG.groupFullCode]) or 0
            _G['LFGGroupReadyObjectivesCompleted']:SetText('0/' .. bossCount .. ' Bosses Defeated')
            _G['LFGGroupReady']:Show()
            LFGGroupReadyFrameCloser:Show()
            _G['LFGRoleCheck']:Hide()

            PlaySoundFile("Interface\\Addons\\LFG\\sound\\levelup2.ogg")
            LFGQueue:Hide()

            LFG.findingGroup = false
            LFG.findingMore = false
            _G['LFGlfg']:Hide()

            LFG.fixMainButton()
        end

        if event == 'CHAT_MSG_CHANNEL' and arg8 == LFG.channelIndex and arg2 ~= me then
            -- groups v2: LFT| prefixed messages
            if string.sub(arg1, 1, 4) == 'LFT|' then
                LFG.Grp_HandleChannelMsg(arg1, arg2)
            end
            if string.sub(arg1, 1, 7) == 'whoLFG:' then
                -- Include protocol version so receivers can detect incompatibility.
                -- Format: meLFG:<addonVer>:<protocolVer>
                SendChatMessage('meLFG:' .. addonVer .. ':' .. LFG_PROTOCOL_VERSION, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            if string.sub(arg1, 1, 6) == 'meLFG:' then
                lfdebug(arg1)
                local verEx = StringSplit(arg1, ':')
                local ver = verEx[2]
                local theirProtocol = tonumber(verEx[3])  -- nil if they are on an old version
                -- Warn once if protocol versions differ (message formats may be incompatible).
                if not LFG.warnedProtocolMismatch and theirProtocol ~= LFG_PROTOCOL_VERSION then
                    LFG.warnedProtocolMismatch = true
                    if theirProtocol then
                        lfprint(COLOR_RED .. '[LFG] Warning: ' .. arg2 .. ' is using protocol v' ..
                                theirProtocol .. ' (you are on v' .. LFG_PROTOCOL_VERSION ..
                                '). Some features may not work correctly between you.')
                    else
                        lfprint(COLOR_RED .. '[LFG] Warning: ' .. arg2 ..
                                ' is using an older version of LFG that may be protocol-incompatible with yours.' ..
                                ' Ask them to update at ' .. COLOR_HUNTER .. 'https://github.com/thezephyrsong/LFG')
                    end
                end
                if LFGWhoCounter.listening then
                    LFGWhoCounter.people = LFGWhoCounter.people + 1
                    if me == 'Bennylava' then
                        local color = COLOR_GREEN
                        if LFG.ver(ver) < LFG.ver(addonVer) then
                            color = COLOR_ORANGE
                        end
                        lfprint('[' .. LFGWhoCounter.people .. '] ' .. arg2 .. ' - ' .. color .. 'v' .. ver)
                    end
                end
            end
        end

        if event == 'CHAT_MSG_CHANNEL' and arg8 == LFG.channelIndex then
            if string.sub(arg1, 1, 4) == 'LFG:' then
                LFG.peopleLookingForGroups = LFG.peopleLookingForGroups + 1
                if LFG.peopleLookingForGroupsDisplay < LFG.peopleLookingForGroups then
                    LFG.peopleLookingForGroupsDisplay = LFG.peopleLookingForGroups
                end

                local lfgEx = StringSplit(arg1, ' ')

                for _, lfg in ipairs(lfgEx) do
                    local spamSplit = StringSplit(lfg, ':')
                    local mDungeonCode = spamSplit[2]
                    local mRole = spamSplit[3] --other's role

                    if mDungeonCode and mRole then

                        if not LFG.browseNames[mDungeonCode] then
                            LFG.browseNames[mDungeonCode] = {}
                        end
                        if not LFG.browseNames[mDungeonCode][mRole] then
                            LFG.browseNames[mDungeonCode][mRole] = ''
                        end

                        if LFG.browseNames[mDungeonCode][mRole] == '' then
                            LFG.browseNames[mDungeonCode][mRole] = arg2
                        else
                            LFG.browseNames[mDungeonCode][mRole] = LFG.browseNames[mDungeonCode][mRole] .. "\n" .. arg2
                        end

                        LFG.incDungeonssSpamRole(mDungeonCode, mRole)
                        LFG.updateDungeonsSpamDisplay(mDungeonCode)
                    end
                end
            end
        end
        if event == 'CHAT_MSG_CHANNEL' and arg8 == LFG.channelIndex then
            if string.sub(arg1, 1, 4) == 'LFM:' then

                local lfmEx = StringSplit(arg1, ':')
                local mDungeonCode = lfmEx[2] or false
                local lfmTank = tonumber(lfmEx[3]) or 0
                local lfmHealer = tonumber(lfmEx[4]) or 0
                local lfmDamage = tonumber(lfmEx[5]) or 0
                local lfmCR = lfmEx[6] == 'cr'

                if mDungeonCode then

                    LFG.peopleLookingForGroups = LFG.peopleLookingForGroups + lfmTank + lfmHealer + lfmDamage
                    if LFG.peopleLookingForGroupsDisplay < LFG.peopleLookingForGroups then
                        LFG.peopleLookingForGroupsDisplay = LFG.peopleLookingForGroups
                    end

                    LFG.incDungeonssSpamRole(mDungeonCode, 'tank', lfmTank)
                    LFG.incDungeonssSpamRole(mDungeonCode, 'healer', lfmHealer)
                    LFG.incDungeonssSpamRole(mDungeonCode, 'damage', lfmDamage)
                    LFG.updateDungeonsSpamDisplay(mDungeonCode, true, lfmTank + lfmHealer + lfmDamage)

                    -- CR step-down: yield to alphabetically earlier CR leader
                    if lfmCR and LFG.crLeader and LFG.LFMDungeonCode == mDungeonCode then
                        if arg2 < me then LFG.crStepDown(mDungeonCode, arg2) end
                    end
                    -- CR seeker: reset election clock while a CR LFM is active
                    if lfmCR and LFG.classRun and LFG.classRunEligible(mDungeonCode) then
                        LFG.crElectionTime[mDungeonCode] = nil
                    end
                end
            end
        end

        if event == 'CHAT_MSG_CHANNEL' and arg8 == LFG.channelIndex and not LFG.oneGroupFull and (LFG.findingGroup or LFG.findingMore) and arg2 ~= me then

            if string.sub(arg1, 1, 6) == 'found:' then
                local foundLongEx = StringSplit(arg1, ' ')

                for i, found in ipairs(foundLongEx) do
                    if string.len(found) > 0 and string.sub(found, 1, 6) == 'found:' then
                        local foundEx = StringSplit(found, ':')
                        local mRole = foundEx[2]
                        local mDungeon = foundEx[3]
                        local name = foundEx[4]
                        local prio = nil
                        if foundEx[5] then
                            if tonumber(foundEx[5]) then
                                prio = tonumber(foundEx[5])
                            end
                        end

                        if string.find(LFG_ROLE, mRole, 1, true) and not LFG.foundGroup and name == me then
                            -- CR guard: ignore found: from non-CR leaders for eligible dungeons
                            if LFG.classRun and LFG.classRunEligible(mDungeon) then
                                local senderIsCR = LFG.crCandidates[mDungeon] and
                                                   LFG.crCandidates[mDungeon][arg2] ~= nil
                                if not senderIsCR then
                                    lfdebug('CR guard: ignoring found: from non-CR leader ' .. arg2 .. ' for ' .. mDungeon)
                                else
                                    local fdName = LFG.dungeonNameFromCode(mDungeon)
                                    if LFG.dungeons[fdName] then LFG.dungeons[fdName].myRole = mRole end
                                    lfdebug('myRole for ' .. mDungeon .. ' set to ' .. mRole)
                                    SendChatMessage('goingWith:' .. arg2 .. ':' .. mDungeon .. ':' .. mRole, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
                                    LFG.foundGroup = true
                                end
                            else
                                local fdName = LFG.dungeonNameFromCode(mDungeon)
                                if LFG.dungeons[fdName] then LFG.dungeons[fdName].myRole = mRole end
                                lfdebug('myRole for ' .. mDungeon .. ' set to ' .. mRole)
                                SendChatMessage('goingWith:' .. arg2 .. ':' .. mDungeon .. ':' .. mRole, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
                                LFG.foundGroup = true
                            end
                        end
                    end
                end
            end

            if string.sub(arg1, 1, 10) == 'leftQueue:' then
                local leftEx = StringSplit(arg1, ':')
                local mRole = leftEx[2]
                LFG.removePlayerFromVirtualParty(arg2, mRole)
            end

            if string.sub(arg1, 1, 10) == 'goingWith:' and
                    (string.find(LFG_ROLE, 'tank', 1, true) or LFG.isLeader) then

                local withEx = StringSplit(arg1, ':')
                local leader = withEx[2]
                local mDungeon = withEx[3]
                local mRole = withEx[4]

                --check if im queued for mDungeon
                for dungeon, _ in next, LFG.group do
                    if dungeon == mDungeon then
                        if leader ~= me then
                            -- only healers and damages respond with goingwith
                            LFG.remHealerOrDamage(mDungeon, arg2)
                        end
                    end
                    -- otherwise, dont care
                end

                -- lfm, leader should invite this guy now
                if LFG.isLeader then
                    lfdebug('im leader')
                else
                    lfdebug('im not leader')
                end
                if LFG.isLeader and leader == me then
                    if LFG.isNeededInLFMGroup(mRole, arg2, mDungeon) then
                        if mRole == 'tank' then
                            LFG.addTank(mDungeon, arg2, true, true)
                        end
                        if mRole == 'healer' then
                            LFG.addHealer(mDungeon, arg2, true, true)
                        end
                        if mRole == 'damage' then
                            LFG.addDamage(mDungeon, arg2, true, true)
                        end
                        LFG.inviteInLFMGroup(arg2)
                    end
                end
            end

            -- LFG
            if string.sub(arg1, 1, 4) == 'LFG:' then

                local lfgEx = StringSplit(arg1, ' ')
                local foundMessage = ''
                local prioMembers = GetNumPartyMembers() + 1
                local prioObjectives = LFG.getDungeonCompletion()

                for _, lfg in ipairs(lfgEx) do
                    local spamSplit = StringSplit(lfg, ':')
                    local mDungeonCode = spamSplit[2]
                    local mRole = spamSplit[3] --other's role
                    local mClass = spamSplit[4] -- nil on old clients (protocol v1/v2)
                    local mClassRun = spamSplit[5] == 'cr'

                    -- Store class and cr preference (protocol v3+)
                    if mClass and mClass ~= '' and mDungeonCode then
                        if not LFG.seenClasses[mDungeonCode] then
                            LFG.seenClasses[mDungeonCode] = {}
                        end
                        LFG.seenClasses[mDungeonCode][arg2] = { class = mClass, cr = mClassRun }
                    end

                    -- Track CR candidates for leader election
                    if mClassRun and mDungeonCode and LFG.classRunEligible(mDungeonCode) then
                        if not LFG.crCandidates[mDungeonCode] then
                            LFG.crCandidates[mDungeonCode] = {}
                        end
                        LFG.crCandidates[mDungeonCode][arg2] = time()
                    end

                    if mDungeonCode and mRole then

                        for _, data in next, LFG.dungeons do
                            if data.queued and data.code == mDungeonCode then

                                --LFM forming
                                if LFG.isLeader or LFG.crLeader then
                                    -- CR leaders only slot applicants who flagged :cr
                                    if LFG.classRun and LFG.classRunEligible(mDungeonCode) and not mClassRun then
                                        lfdebug('classRun: skipping ' .. arg2 .. ' - no cr flag')
                                    else
                                        if mRole == 'tank' then
                                            if LFG.addTank(mDungeonCode, arg2) then
                                                foundMessage = foundMessage .. 'found:tank:' .. mDungeonCode .. ':' .. arg2 .. ':' .. prioMembers .. ':' .. prioObjectives .. ' '
                                            end
                                        end
                                        if mRole == 'healer' then
                                            if LFG.addHealer(mDungeonCode, arg2) then
                                                foundMessage = foundMessage .. 'found:healer:' .. mDungeonCode .. ':' .. arg2 .. ':' .. prioMembers .. ':' .. prioObjectives .. ' '
                                            end
                                        end
                                        if mRole == 'damage' then
                                            if LFG.addDamage(mDungeonCode, arg2) then
                                                foundMessage = foundMessage .. 'found:damage:' .. mDungeonCode .. ':' .. arg2 .. ':' .. prioMembers .. ':' .. prioObjectives .. ' '
                                            end
                                        end
                                        if foundMessage ~= '' then
                                            SendChatMessage(foundMessage, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
                                        end
                                        return false
                                    end
                                end

                                -- LFG forming
                                if not LFG.inGroup then
                                    if string.find(LFG_ROLE, 'tank', 1, true) then
                                        LFG.group[mDungeonCode].tank = me

                                        -- if im tank looking for x and i see a different tank looking for x first
                                        -- then supress my next lfg:x:tank
                                        if mRole == 'tank' then
                                            LFG.supress[mDungeonCode] = 'tank'
                                        end

                                        if mRole == 'healer' then
                                            if LFG.addHealer(mDungeonCode, arg2, false, true) then
                                                foundMessage = foundMessage .. 'found:healer:' .. mDungeonCode .. ':' .. arg2 .. ':0:0 '
                                            end
                                        end
                                        if mRole == 'damage' then
                                            if LFG.addDamage(mDungeonCode, arg2, false, true) then
                                                foundMessage = foundMessage .. 'found:damage:' .. mDungeonCode .. ':' .. arg2 .. ':0:0 '
                                            end
                                        end
                                        --end

                                        --pseudo fill group for tooltip display
                                    elseif string.find(LFG_ROLE, 'healer', 1, true) then
                                        LFG.addHealer(mDungeonCode, me, true, true) --faux, me

                                        if mRole == 'tank' then
                                            LFG.addTank(mDungeonCode, arg2, true, true) --faux, tank
                                        end
                                        if mRole == 'damage' then
                                            LFG.addDamage(mDungeonCode, arg2, true, true) --faux, dps
                                        end
                                        --end

                                    elseif string.find(LFG_ROLE, 'damage', 1, true) then
                                        LFG.addDamage(mDungeonCode, me, true, true) --faux

                                        if mRole == 'tank' and LFG.group[mDungeonCode].tank == '' then
                                            LFG.addTank(mDungeonCode, arg2, true, true) --faux, tank
                                        end
                                        if mRole == 'healer' and LFG.group[mDungeonCode].healer == '' then
                                            LFG.addHealer(mDungeonCode, arg2, true, true) -- fause healer
                                        end
                                        if mRole == 'damage' then
                                            LFG.addDamage(mDungeonCode, arg2, true, true) --faux, dps
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                SendChatMessage(foundMessage, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))

            end
        end
    end
end)

-- debug and print functions

function lfprint(a)
    if a == nil then
        DEFAULT_CHAT_FRAME:AddMessage(COLOR_HUNTER .. '[LFG]|cff0070de:' .. time() .. '|cffffffff attempt to print a nil value.')
        return false
    end
    DEFAULT_CHAT_FRAME:AddMessage(COLOR_HUNTER .. "[LFG] |cffffffff" .. a)
end

function lfnotice(a)
    DEFAULT_CHAT_FRAME:AddMessage(COLOR_HUNTER .. "[LFG] " .. COLOR_ORANGE .. a)
end

function lferror(a)
    DEFAULT_CHAT_FRAME:AddMessage('|cff69ccf0[LFGError]|cff0070de:' .. time() .. '|cffffffff[' .. a .. ']')
end

function lfdebug(a)
    if not LFG_CONFIG['debug'] then
        return false
    end
    if type(a) == 'boolean' then
        if a then
            lfprint('|cff0070de[LFGDEBUG:' .. time() .. ']|cffffffff[true]')
        else
            lfprint('|cff0070de[LFGDEBUG:' .. time() .. ']|cffffffff[false]')
        end
        return true
    end
    --lfprint('|cff0070de[LFGDEBUG:' .. time() .. ']|cffffffff[' .. a .. ']')
end

local hookChatFrame = function(frame)
    lfdebug('chat frame hook - syncing timer to current local second')
    LFGTime.second = tonumber(date("%S", time()))
    LFGTime.diff = 0
    LFGTime:Hide()
    LFGTime:Show()
    lfdebug('Timer seeded at local second: ' .. LFGTime.second)
end


LFG:SetScript("OnEvent", function()
    if event then
        if event == "ADDON_LOADED" and arg1 == 'LFG' then
            LFG.init()
        end
        if event == "PLAYER_LOGOUT" then
            LFG.onPlayerLogout()
        end
        if event == "PLAYER_TARGET_CHANGED" and LFG.inGroup then
            if _G['TargetFrame']:IsVisible() then
                if LFG.currentGroupRoles[UnitName('target')] then
                    _G['LFGPartyRoleIconsTarget']:SetTexture('Interface\\addons\\LFG\\images\\' .. LFG.currentGroupRoles[UnitName('target')] .. '_small')
                    _G['LFGPartyRoleIconsTarget']:Show()
                end
            else
                _G['LFGPartyRoleIconsTarget']:Hide()
            end
        end
        if event == "PLAYER_ENTERING_WORLD" then
            LFG.level = UnitLevel('player')
            LFG.sendMyVersion()
            lfdebug('PLAYER_ENTERING_WORLD')
            hookChatFrame(ChatFrame1);
            lfdebug(arg1)
            lfdebug(arg2)
        end
        if event == "PARTY_LEADER_CHANGED" then

            BrowseDungeonListFrame_Update()

            if LFG.isLeader and IsPartyLeader() then
                lfdebug('end PARTY_LEADER_CHANGED - missfire ?')
                return false
            end

            LFG.isLeader = IsPartyLeader()
            if GetNumPartyMembers() + 1 == LFG.groupSizeMax then
            else
                -- only leave queue if im in queue
                if LFG.isLeader and (LFG.findingGroup or LFG.findingMore) then
                    leaveQueue('party leader changed group < 5 ')
                end
            end
        end
        if event == "PARTY_MEMBERS_CHANGED" then
            lfdebug('PARTY_MEMBERS_CHANGED') --check -- triggers in raids too
            DungeonListFrame_Update()

            if not LFG.inGroup then
                LFG.currentGroupSize = 1
            end
            lfdebug('joineed' .. GetNumPartyMembers() + 1 .. ' > ' .. LFG.currentGroupSize)
            lfdebug('left' .. GetNumPartyMembers() + 1 .. ' < ' .. LFG.currentGroupSize)

            local someoneJoined = GetNumPartyMembers() + 1 > LFG.currentGroupSize
            local someoneLeft = GetNumPartyMembers() + 1 < LFG.currentGroupSize

            LFG.currentGroupSize = GetNumPartyMembers() + 1
            LFG.inGroup = GetNumRaidMembers() == 0 and GetNumPartyMembers() > 0

            BrowseDungeonListFrame_Update()

            if not someoneLeft and not someoneJoined then
                lfdebug('end PARTY_MEMBERS_CHANGED - missfire ?')

                if not LFG.inGroup then
                    LFGDelayLeaveQueue.reason = 'i left grou --- i think'
                    LFGDelayLeaveQueue:Show()
                end

                return false
            end

            if LFG.inGroup then
                if LFG.isLeader then
                else
                    _G['LFGlfg']:Hide()
                end
            else
                -- i left the group OR everybody left
                lfdebug('LFGInvite.inviteIndex = ' .. LFGInvite.inviteIndex)
                LFG.GetPossibleRoles()
                LFG.hidePartyRoleIcons()

                _G['LFGDungeonStatus']:Hide()
                _G['LFGRoleCheck']:Hide()

                -- i left when there was a dungeon in progress
                if LFGDungeonComplete.dungeonInProgress then
                    -- todo: ban player for 5 minutes
                    LFGDungeonComplete.dungeonInProgress = false
                end

                if LFGInvite.inviteIndex == 1 then
                    return false
                end
                if LFG.findingGroup or LFG.findingMore then
                    leaveQueue('not group and finding group/more')
                end

                return false
            end

            if someoneJoined then

                if LFG.findingMore then
                    -- send him objectives
                    local objectivesString = ''
                    for index, _ in next, LFG.objectivesFrames do
                        if LFG.objectivesFrames[index].completed then
                            objectivesString = objectivesString .. '1-'
                        else
                            objectivesString = objectivesString .. '0-'
                        end
                    end
                    SendAddonMessage(LFG_ADDON_CHANNEL, "objectives:" .. LFG.LFMDungeonCode .. ":" .. objectivesString, "PARTY")
                    -- end send objectives
                    if LFG.isLeader then

                        local newName = ''
                        local joinedManually = false
                        for i = 1, GetNumPartyMembers() do
                            local name = UnitName('party' .. i)
                            local fromQueue = name == LFG.group[LFG.LFMDungeonCode].tank or
                                    name == LFG.group[LFG.LFMDungeonCode].healer or
                                    name == LFG.group[LFG.LFMDungeonCode].damage1 or
                                    name == LFG.group[LFG.LFMDungeonCode].damage2 or
                                    name == LFG.group[LFG.LFMDungeonCode].damage3

                            if not fromQueue then
                                newName = name
                                joinedManually = true
                            end
                        end
                        if joinedManually then
                            --joined manually, dont know his role

                            LFGFillAvailableDungeonsDelay.queueAfterIfPossible = GetNumPartyMembers() < (LFG.groupSizeMax - 1)

                            if not LFGFillAvailableDungeonsDelay.queueAfterIfPossible then
                                --group full
                                local lfmBossCount = LFG.bosses[LFG.LFMDungeonCode] and LFG.tableSize(LFG.bosses[LFG.LFMDungeonCode]) or 0
                                SendAddonMessage(LFG_ADDON_CHANNEL, "LFMPartyReady:" .. LFG.LFMDungeonCode .. ":" .. LFGObjectives.objectivesComplete .. ":" .. lfmBossCount, "PARTY")
                                return false -- so it goes into check full in timer
                            end
                            leaveQueue(' someone joined manually')
                            findMore()
                        else
                            --joined from the queue, we know his role, check if group is full
                            --  lfdebug('player ' .. newName .. ' joined from queue')
                            local lfmBossCount = LFG.bosses[LFG.LFMDungeonCode] and LFG.tableSize(LFG.bosses[LFG.LFMDungeonCode]) or 0
                            if LFG.checkLFMGroupReady(LFG.LFMDungeonCode) then
                                SendAddonMessage(LFG_ADDON_CHANNEL, "LFMPartyReady:" .. LFG.LFMDungeonCode .. ":" .. LFGObjectives.objectivesComplete .. ":" .. lfmBossCount, "PARTY")
                            else
                                SendAddonMessage(LFG_ADDON_CHANNEL, "weInQueue:" .. LFG.LFMDungeonCode, "PARTY")
                            end
                        end
                    end

                else
                    -- disable dungeon checks if i have more than one and i join a party
                    for _, data in next, LFG.dungeons do
                        data.queued = false
                        if _G["Dungeon_" .. data.code .. '_CheckButton'] then
                            _G["Dungeon_" .. data.code .. '_CheckButton']:SetChecked(false)
                        end
                    end
                    DungeonListFrame_Update()
                end

            end
            if someoneLeft then
                LFG.showPartyRoleIcons()
                _G['LFGReadyStatus']:Hide()
                _G['LFGGroupReady']:Hide()
                -- find who left and update virtual group
                if LFG.findingMore --then
                        and LFG.isLeader then

                    --inc some getto code
                    lfdebug('someone left')
                    local leftName = ''
                    local stillInParty = false
                    if LFG.group[LFG.LFMDungeonCode].tank ~= '' and LFG.group[LFG.LFMDungeonCode].tank ~= me then
                        leftName = LFG.group[LFG.LFMDungeonCode].tank
                        stillInParty = false
                        for i = 1, GetNumPartyMembers() do
                            local name = UnitName('party' .. i)
                            if leftName == name then
                                stillInParty = true
                                break
                            end
                        end
                        if not stillInParty then
                            LFG.group[LFG.LFMDungeonCode].tank = ''
                            LFG.LFMGroup.tank = ''
                            lfprint(leftName .. ' (' .. COLOR_TANK .. 'Tank' .. COLOR_WHITE .. ') has been removed from the queue group.')
                        end
                    end
                    --
                    if LFG.group[LFG.LFMDungeonCode].healer ~= '' and LFG.group[LFG.LFMDungeonCode].healer ~= me then
                        leftName = LFG.group[LFG.LFMDungeonCode].healer
                        stillInParty = false
                        for i = 1, GetNumPartyMembers() do
                            local name = UnitName('party' .. i)
                            if leftName == name then
                                stillInParty = true
                                break
                            end
                        end
                        if not stillInParty then
                            LFG.group[LFG.LFMDungeonCode].healer = ''
                            LFG.LFMGroup.healer = ''
                            lfprint(leftName .. ' (' .. COLOR_HEALER .. 'Healer' .. COLOR_WHITE .. ') has been removed from the queue group.')
                        end
                    end
                    --
                    if LFG.group[LFG.LFMDungeonCode].damage1 ~= '' and LFG.group[LFG.LFMDungeonCode].damage1 ~= me then
                        leftName = LFG.group[LFG.LFMDungeonCode].damage1
                        stillInParty = false
                        for i = 1, GetNumPartyMembers() do
                            local name = UnitName('party' .. i)
                            if leftName == name then
                                stillInParty = true
                                break
                            end
                        end
                        if not stillInParty then
                            LFG.group[LFG.LFMDungeonCode].damage1 = ''
                            LFG.LFMGroup.damage1 = ''
                            lfprint(leftName .. ' (' .. COLOR_DAMAGE .. 'Damage' .. COLOR_WHITE .. ') has been removed from the queue group.')
                        end
                    end
                    --
                    if LFG.group[LFG.LFMDungeonCode].damage2 ~= '' and LFG.group[LFG.LFMDungeonCode].damage2 ~= me then
                        leftName = LFG.group[LFG.LFMDungeonCode].damage2
                        stillInParty = false
                        for i = 1, GetNumPartyMembers() do
                            local name = UnitName('party' .. i)
                            if leftName == name then
                                stillInParty = true
                                break
                            end
                        end
                        if not stillInParty then
                            LFG.group[LFG.LFMDungeonCode].damage2 = ''
                            LFG.LFMGroup.damage2 = ''
                            lfprint(leftName .. ' (' .. COLOR_DAMAGE .. 'Damage' .. COLOR_WHITE .. ') has been removed from the queue group.')
                        end
                    end
                    --
                    if LFG.group[LFG.LFMDungeonCode].damage3 ~= '' and LFG.group[LFG.LFMDungeonCode].damage3 ~= me then
                        leftName = LFG.group[LFG.LFMDungeonCode].damage3
                        stillInParty = false
                        for i = 1, GetNumPartyMembers() do
                            local name = UnitName('party' .. i)
                            if leftName == name then
                                stillInParty = true
                                break
                            end
                        end
                        if not stillInParty then
                            LFG.group[LFG.LFMDungeonCode].damage3 = ''
                            LFG.LFMGroup.damage3 = ''
                            lfprint(leftName .. ' (' .. COLOR_DAMAGE .. 'Damage' .. COLOR_WHITE .. ') has been remove from the queue group.')
                        end
                    end
                end
            end
            lfdebug('ajunge aici ??')
            if LFG.isLeader then
                LFG.sendMinimapDataToParty(LFG.LFMDungeonCode)
            end
            -- update awesome button enabled if 5/5 disabled + text if not
            local awesomeButton = _G['LFGGroupReadyAwesome']
            awesomeButton:SetText('Waiting Players (' .. LFG.groupSizeMax - GetNumPartyMembers() - 1 .. ')')
            awesomeButton:Disable()

            if GetNumPartyMembers() == LFG.groupSizeMax - 1 then
                awesomeButton:SetText('Let\'s do this!')
                awesomeButton:Enable()
            end
            lfdebug(' end PARTY_MEMBERS_CHANGED')
        end
        if event == 'PLAYER_LEVEL_UP' then
            LFG.level = arg1
            LFG.fillAvailableDungeons()
        end
    end
end)

function LFG.hideButtonTextures(buttonName)
    local button = _G[buttonName]
    if button then
        lfdebug("Hiding textures for button: " .. buttonName)
        button:SetNormalTexture("")
        button:SetPushedTexture("")
        button:SetHighlightTexture("")
        button:SetDisabledTexture("")
        -- Do NOT call button:SetAlpha(0) – makes button invisible and unclickable
    else
        lfdebug("Button not found: " .. buttonName)
    end
end

function LFG.hideAllAddonButtonTextures()
    -- Hide role tooltip buttons
    LFG.hideButtonTextures("RoleCheckRoleDamageTooltipButton")
    LFG.hideButtonTextures("RoleCheckRoleTankTooltipButton") 
    LFG.hideButtonTextures("RoleCheckRoleHealerTooltipButton")
    LFG.hideButtonTextures("RoleTankTooltipButton")
    LFG.hideButtonTextures("RoleHealerTooltipButton")
    LFG.hideButtonTextures("RoleDamageTooltipButton")
    
    -- Hide tab buttons
    LFG.hideButtonTextures("LFGBrowseButton")
    LFG.hideButtonTextures("LFGDungeonsButton")
    
    -- Hide dungeon list buttons
    for code, frame in next, LFG.availableDungeons do
        if frame then
            LFG.hideButtonTextures("Dungeon_" .. code .. "_Button")
        end
    end
    
    -- Hide browse buttons
    for code, frame in next, LFG.browseFrames do
        if frame then
            LFG.hideButtonTextures("BrowseFrame_" .. code .. "_JoinAs")
        end
    end
end

function LFG.init()

    if not LFG_CONFIG then
        LFG_CONFIG = {}
        LFG_CONFIG['debug'] = false
        LFG_CONFIG['spamChat'] = true
    end

    if LFG_CONFIG['debug'] then
        _G['LFGTitleTime']:Show()
    else
        _G['LFGTitleTime']:Hide()
    end
    local _, uClass = UnitClass('player')
    LFG.class = string.lower(uClass)

    if not LFG_TYPE then
        LFG_TYPE = 1
    end

    UIDropDownMenu_SetText(_G['LFGTypeSelect'], LFG.types[LFG_TYPE]);

        _G['LFGMainDungeonsText']:SetText('Dungeons')
        _G['LFGBrowseDungeonsText']:SetText('Dungeons')

    _G['LFGDungeonsText']:SetText(LFG.types[LFG_TYPE])
    if not LFG_ROLE then
        LFG.SetSingleRole('tank')
        LFG.SetSingleRole(LFG.GetPossibleRoles())
    else
        LFG.GetPossibleRoles()
        LFGsetRole(LFG_ROLE)
    end

    if not LFG_FORMED_GROUPS then
        LFG.resetFormedGroups()
    else
        --check if formed groups include maybe new dungeon codes
        for _, data in next, LFG.dungeons do
            if not LFG_FORMED_GROUPS[data.code] then
                LFG_FORMED_GROUPS[data.code] = 0
            end
        end
    end

    LFG.channelIndex = 0
    LFG.level = UnitLevel('player')
    LFG.findingGroup = false
    LFG.findingMore = false
    LFG.availableDungeons = {}
    LFG.group = {}
    LFG.oneGroupFull = false
    LFG.groupFullCode = ''
    LFG.acceptNextInvite = false
    LFG.currentGroupSize = GetNumPartyMembers() + 1
    LFG.classRun = _G['ClassRunCheckButton'] and _G['ClassRunCheckButton']:GetChecked() or false
    LFG.seenClasses = {}
    LFG.crLeader = false
    LFG.crCandidates = {}
    LFG.crElectionTime = {}

    LFG.isLeader = IsPartyLeader() or false

    LFG.inGroup = GetNumRaidMembers() == 0 and GetNumPartyMembers() > 0
    LFG.fixMainButton()

    LFG.fillAvailableDungeons()

    LFGChannelJoinDelay:Show()

    LFG.objectivesFrames = {}
    LFGDungeonComplete.dungeonInProgress = false

    _G['LFGGroupReadyAwesome']:Disable()

    --lfprint(COLOR_HUNTER .. 'Looking For Group v' .. addonVer .. COLOR_WHITE .. ' - LFG Addon for Project Epoch loaded.')

    local dungeonsButton = _G['LFGBrowseButton']

    dungeonsButton:SetScript("OnEnter", function()
        _G['LFGBrowseButtonHighlight']:Show()
    end)
    dungeonsButton:SetScript("OnLeave", function()
        _G['LFGBrowseButtonHighlight']:Hide()
    end)

    local dungeonsButton = _G['LFGDungeonsButton']

    dungeonsButton:SetScript("OnEnter", function()
        _G['LFGDungeonsButtonHighlight']:Show()
    end)
    dungeonsButton:SetScript("OnLeave", function()
        _G['LFGDungeonsButtonHighlight']:Hide()
    end)

    if LFG.shouldHideButtonTextures() then
	    LFG.hideButtonTextures("RoleCheckRoleDamageTooltipButton")
	    LFG.hideButtonTextures("RoleCheckRoleTankTooltipButton")
	    LFG.hideButtonTextures("RoleCheckRoleHealerTooltipButton")
	    LFG.hideButtonTextures("RoleTankTooltipButton")
	    LFG.hideButtonTextures("RoleHealerTooltipButton")
	    LFG.hideButtonTextures("RoleDamageTooltipButton")
	end

    for dungeon, data in next, LFG.dungeons do
        if not LFG.dungeonsSpam[data.code] then
            LFG.dungeonsSpam[data.code] = {
                tank = 0,
                healer = 0,
                damage = 0
            }
        end
        if not LFG.dungeonsSpamDisplay[data.code] then
            LFG.dungeonsSpamDisplay[data.code] = {
                tank = 0,
                healer = 0,
                damage = 0
            }
            LFG.dungeonsSpamDisplayLFM[data.code] = 0
        end
    end
end

LFGQueue:SetScript("OnShow", function()
    this.startTime = GetTime()
    this.spammed = {
        tank = false,
        damage = false,
        heal = false,
        reset = false,
        lfm = false,
        checkGroupFull = false
    }
end)

LFGQueue:SetScript("OnHide", function()
    LFGMinimapAnimation:Hide()
end)

LFGQueue:SetScript("OnUpdate", function()
    local plus = 1 --seconds
    local gt = GetTime() * 1000
    local st = (this.startTime + plus) * 1000
    if gt >= st and LFG.findingGroup then
        this.startTime = GetTime()

        if LFGTime.second == -1 then
            return false
        end

        _G['LFGTitleTime']:SetText(LFGTime.second)
        _G['LFGGroupStatusTimeInQueue']:SetText('Time in Queue: ' .. SecondsToTime(time() - LFG.queueStartTime))
        if LFG.averageWaitTime == 0 then
            _G['LFGGroupStatusAverageWaitTime']:SetText('Average Wait Time: Unavailable')
        else
            _G['LFGGroupStatusAverageWaitTime']:SetText('Average Wait Time: ' .. SecondsToTimeAbbrev(LFG.averageWaitTime))
        end

        if (LFGTime.second == LFG.RESET_TIME or LFGTime.second == LFG.RESET_TIME + LFG.TIME_MARGIN) and not this.spammed.reset then
            lfdebug('reset -- call -- spam')
            this.spammed = {
                tank = false,
                damage = false,
                heal = false,
                reset = false,
                lfm = false,
                checkGroupFull = false
            }
            if not LFG.inGroup then
                LFG.resetGroup()
            end
        end

        if (LFGTime.second == LFG.RESET_TIME + 2 or LFGTime.second == LFG.RESET_TIME + 2 + LFG.TIME_MARGIN) and not this.spammed.lfm then
            if LFG.isLeader then
                LFG.sendLFMStats(LFG.LFMDungeonCode)
                this.spammed.lfm = true
            elseif LFG.crLeader then
                LFG.sendLFMStats(LFG.LFMDungeonCode)
                this.spammed.lfm = true
            else
                LFG.crCheckElection()
            end
        end

        if (LFGTime.second == LFG.TANK_TIME + LFG.myRandomTime or LFGTime.second == LFG.TANK_TIME + LFG.TIME_MARGIN + LFG.myRandomTime) and
                string.find(LFG_ROLE, 'tank', 1, true) and not this.spammed.tank then
            this.spammed.tank = true
            if not LFG.inGroup then
                -- only start forming group if im not already grouped
                for _, data in next, LFG.dungeons do
                    if data.queued then
                        LFG.group[data.code].tank = me
                    end
                end
                --new: but do send lfg message if im a tank, to be picked up by LFM party leader
                LFG.sendLFGMessage('tank')
            end
        end

        if (LFGTime.second == LFG.HEALER_TIME + LFG.myRandomTime or LFGTime.second == LFG.HEALER_TIME + LFG.TIME_MARGIN + LFG.myRandomTime) and
                string.find(LFG_ROLE, 'healer', 1, true) and not this.spammed.heal then
            this.spammed.heal = true
            if not LFG.inGroup then
                -- dont spam lfm if im already in a group, because leader will pick up new players
                LFG.sendLFGMessage('healer')
            end
        end

        if (LFGTime.second == LFG.DAMAGE_TIME + LFG.myRandomTime or LFGTime.second == LFG.DAMAGE_TIME + LFG.TIME_MARGIN + LFG.myRandomTime) and
                string.find(LFG_ROLE, 'damage', 1, true) and not this.spammed.damage then
            this.spammed.damage = true
            if not LFG.inGroup then
                -- dont spam lfm if im already in a group, because leader will pick up new players
                LFG.sendLFGMessage('damage')
            end
        end

        if (LFGTime.second == LFG.FULLCHECK_TIME or LFGTime.second == LFG.FULLCHECK_TIME + LFG.TIME_MARGIN) and
                string.find(LFG_ROLE, 'tank', 1, true) and not this.spammed.checkGroupFull then
            this.spammed.checkGroupFull = true
            if not LFG.inGroup then

                local groupFull, code, healer, damage1, damage2, damage3 = LFG.checkGroupFull()

                if groupFull then
                    LFG.groupFullCode = code

                    local gfcName = LFG.dungeonNameFromCode(LFG.groupFullCode)
                    if LFG.dungeons[gfcName] then LFG.dungeons[gfcName].myRole = 'tank' end

                    LFG.SetSingleRole('tank')

                    SendChatMessage("[LFG]:" .. code .. ":party:ready:" .. healer .. ":" .. damage1 .. ":" .. damage2 .. ":" .. damage3, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))

                    SendChatMessage("[LFG]:lfg_group_formed:" .. code .. ":" .. time() - LFG.queueStartTime, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))

                    --untick everything
                    for dungeon, data in next, LFG.dungeons do
                        if _G["Dungeon_" .. data.code .. '_CheckButton'] then
                            _G["Dungeon_" .. data.code .. '_CheckButton']:SetChecked(false)
                        end
                        LFG.dungeons[dungeon].queued = false
                    end

                    LFG.findingGroup = false
                    LFG.findingMore = false

                    local background = ''
                    local dungeonName = 'unknown'
                    for d, data in next, LFG.dungeons do
                        if data.code == code then
                            background = data.background
                            dungeonName = d
                        end
                    end

                    _G['LFGGroupReadyBackground']:SetTexture('Interface\\addons\\LFG\\images\\background\\ui-lfg-background-' .. background)
                    _G['LFGGroupReadyRole']:SetTexture('Interface\\addons\\LFG\\images\\' .. LFG_ROLE .. '2')
                    _G['LFGGroupReadyMyRole']:SetText(LFG.ucFirst(LFG_ROLE))
                    _G['LFGGroupReadyDungeonName']:SetText(dungeonName)
                    LFG.readyStatusReset()
                    _G['LFGGroupReady']:Show()
                    LFGGroupReadyFrameCloser:Show()

                    _G['LFGRoleCheck']:Hide()

                    PlaySoundFile("Interface\\Addons\\LFG\\sound\\levelup2.ogg")
                    LFGQueue:Hide()

                    LFG.fixMainButton()
                    _G['LFGlfg']:Hide()
                    LFGInvite:Show()
                end
            end

        end

    end
end)

function LFG.shouldHideButtonTextures()
    return IsAddOnLoaded("pretty_patchkit")
end

function LFG.checkLFGChannel()
    lfdebug('check LFG channel call - after 15s')

    local chanList = { GetChannelList() }
    LFG.channelIndex = 0

    for i = 1, #chanList, 2 do
        local channelIndex = chanList[i]
        local channelName = chanList[i + 1]

        if channelName == LFG.channel then
            LFG.channelIndex = channelIndex
            lfdebug('Found LFG channel at index: ' .. LFG.channelIndex)

            if LFG.channelIndex == 1 then
                lfprint('WARNING: LFG channel in slot 1, leaving and rejoining...')
                LeaveChannelByName(LFG.channel)
                LFG.channelIndex = 0
                local retryFrame = CreateFrame("Frame")
                retryFrame.elapsed = 0
                retryFrame:SetScript("OnUpdate", function(self, elapsed)
                    self.elapsed = self.elapsed + elapsed
                    if self.elapsed >= 3 then
                        JoinChannelByName(LFG.channel)
                        self:SetScript("OnUpdate", nil)
                    end
                end)
                return
            end
            break
        end
    end

    if LFG.channelIndex == 0 then
        lfdebug('not in chan, joining')
        JoinChannelByName(LFG.channel)
    else
        lfdebug('in chan, chilling LFG.channelIndex = ' .. LFG.channelIndex)
    end
end

function LFG.joinLFGChannelSafely()
    local generalIndex = GetChannelName("General")
    if generalIndex ~= 1 then
        lfdebug('General channel moved, aborting LFG join')
        local retryFrame = CreateFrame("Frame")
        retryFrame.elapsed = 0
        retryFrame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = self.elapsed + elapsed
            if self.elapsed >= 3 then
                LFG.checkLFGChannel()
                self:SetScript("OnUpdate", nil)
            end
        end)
        return
    end

    JoinChannelByName(LFG.channel)

    local verifyFrame = CreateFrame("Frame")
    verifyFrame.elapsed = 0
    verifyFrame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= 1 then
            local lfgIndex = GetChannelName(LFG.channel)
            if lfgIndex == 1 then
                -- Only fix if General channel is not in slot 1, otherwise it might be fine
                local generalIndex = GetChannelName("General")
                if generalIndex ~= 1 then
                    lfprint('ERROR: LFG channel took channel 1! Fixing immediately...')
                    LFG.fixChannelConflict()
                else
                    lfdebug('LFG channel in slot 1 but General is also in slot 1, accepting this state')
                    LFG.channelIndex = lfgIndex
                end
            else
                LFG.channelIndex = lfgIndex
                lfdebug('LFG channel safely joined at index: ' .. LFG.channelIndex)
            end
            self:SetScript("OnUpdate", nil)
        end
    end)
end

function LFG.fixChannelConflict()
    lfdebug('Attempting to fix channel 1 conflict')

    LeaveChannelByName(LFG.channel)
    LFG.channelIndex = 0

    local fixFrame = CreateFrame("Frame")
    fixFrame.elapsed = 0
    fixFrame.attempts = 0
    fixFrame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= 3 then
            self.elapsed = 0
            self.attempts = self.attempts + 1

            local generalIndex = GetChannelName("General")
            if generalIndex == 1 then
                lfdebug('General restored to channel 1, rejoining LFG')
                LFG.joinLFGChannelSafely()
                self:SetScript("OnUpdate", nil)
            elseif self.attempts >= 5 then
                -- Reduced attempts from 10 to 5 and made it less aggressive
                lfdebug('Channel order restoration taking longer than expected, but continuing...')
                if self.attempts >= 8 then
                    lfprint('Channel order may be affected. If you experience issues, please /reload.')
                    self:SetScript("OnUpdate", nil)
                end
            else
                lfdebug('General still not in channel 1, attempt: ' .. self.attempts)
            end
        end
    end)
end

function LFG.GetPossibleRoles()

    local tankCheck = _G['RoleTank']
    local healerCheck = _G['RoleHealer']
    local damageCheck = _G['RoleDamage']

    --ready check window
    local readyCheckTank = _G['roleCheckTank']
    local readyCheckHealer = _G['roleCheckHealer']
    local readyCheckDamage = _G['roleCheckDamage']

    tankCheck:Disable()
    tankCheck:Hide()
    tankCheck:SetChecked(false)
    healerCheck:Disable()
    healerCheck:Hide()
    healerCheck:SetChecked(false)
    damageCheck:Disable()
    damageCheck:Hide()
    damageCheck:SetChecked(false)

    readyCheckTank:Disable()
    readyCheckTank:Hide()
    readyCheckTank:SetChecked(false)
    readyCheckHealer:Disable()
    readyCheckHealer:Hide()
    readyCheckHealer:SetChecked(false)
    readyCheckDamage:Disable()
    readyCheckDamage:Hide()
    readyCheckDamage:SetChecked(false)

    _G['LFGTankBackground2']:SetDesaturated(1)
    _G['LFGHealerBackground2']:SetDesaturated(1)
    _G['LFGDamageBackground2']:SetDesaturated(1)

    _G['LFGRoleCheckRoleTank']:SetDesaturated(1)
    _G['LFGRoleCheckRoleHealer']:SetDesaturated(1)
    _G['LFGRoleCheckRoleDamage']:SetDesaturated(1)

    if LFG.class == 'warrior' then

        tankCheck:Enable()
        tankCheck:Show()

        readyCheckTank:Enable()
        readyCheckTank:Show()
        readyCheckTank:SetChecked(true)

        damageCheck:Enable()
        damageCheck:Show()

        readyCheckDamage:Enable()
        readyCheckDamage:Show()
        readyCheckDamage:SetChecked(false)

        tankCheck:SetChecked(string.find(LFG_ROLE, 'tank', 1, true))
        healerCheck:SetChecked(false)
        damageCheck:SetChecked(string.find(LFG_ROLE, 'damage', 1, true))

        _G['LFGTankBackground2']:SetDesaturated(0)
        _G['LFGDamageBackground2']:SetDesaturated(0)

        _G['LFGRoleCheckRoleTank']:SetDesaturated(0)
        _G['LFGRoleCheckRoleDamage']:SetDesaturated(0)

        return 'tank'
    end
    if LFG.class == 'paladin' or LFG.class == 'druid' or LFG.class == 'shaman' then

        tankCheck:Enable()
        tankCheck:Show()

        readyCheckTank:Enable()
        readyCheckTank:Show()
        readyCheckTank:SetChecked(false)

        healerCheck:Enable()
        healerCheck:Show()

        readyCheckHealer:Enable()
        readyCheckHealer:Show()
        readyCheckHealer:SetChecked(true)

        damageCheck:Enable()
        damageCheck:Show()

        readyCheckDamage:Enable()
        readyCheckDamage:Show()
        readyCheckDamage:SetChecked(false)

        tankCheck:SetChecked(string.find(LFG_ROLE, 'tank', 1, true))
        healerCheck:SetChecked(string.find(LFG_ROLE, 'healer', 1, true))
        damageCheck:SetChecked(string.find(LFG_ROLE, 'damage', 1, true))

        _G['LFGTankBackground2']:SetDesaturated(0)
        _G['LFGHealerBackground2']:SetDesaturated(0)
        _G['LFGDamageBackground2']:SetDesaturated(0)

        _G['LFGRoleCheckRoleTank']:SetDesaturated(0)
        _G['LFGRoleCheckRoleHealer']:SetDesaturated(0)
        _G['LFGRoleCheckRoleDamage']:SetDesaturated(0)

        return 'healer'
    end
    if LFG.class == 'priest' then

        healerCheck:Enable()
        healerCheck:Show()
        readyCheckHealer:Enable()
        readyCheckHealer:Show()
        readyCheckHealer:SetChecked(true)

        damageCheck:Enable()
        damageCheck:Show()
        readyCheckDamage:Enable()
        readyCheckDamage:Show()
        readyCheckDamage:SetChecked(false)

        tankCheck:SetChecked(false)
        healerCheck:SetChecked(string.find(LFG_ROLE, 'healer', 1, true))
        damageCheck:SetChecked(string.find(LFG_ROLE, 'damage', 1, true))

        _G['LFGHealerBackground2']:SetDesaturated(0)
        _G['LFGDamageBackground2']:SetDesaturated(0)

        _G['LFGRoleCheckRoleHealer']:SetDesaturated(0)
        _G['LFGRoleCheckRoleDamage']:SetDesaturated(0)

        return 'healer'
    end
    if LFG.class == 'warlock' or LFG.class == 'hunter' or LFG.class == 'mage' or LFG.class == 'rogue' then

        damageCheck:Enable()
        damageCheck:Show()

        readyCheckDamage:Enable()
        readyCheckDamage:Show()
        readyCheckDamage:SetChecked(true)

        tankCheck:SetChecked(false)
        healerCheck:SetChecked(false)
        damageCheck:SetChecked(string.find(LFG_ROLE, 'damage', 1, true))

        _G['LFGDamageBackground2']:SetDesaturated(0)
        _G['LFGRoleCheckRoleDamage']:SetDesaturated(0)

        return 'damage'
    end

    tankCheck:SetChecked(string.find(LFG_ROLE, 'tank', 1, true))
    healerCheck:SetChecked(string.find(LFG_ROLE, 'healer', 1, true))
    damageCheck:SetChecked(string.find(LFG_ROLE, 'damage', 1, true))

    return 'damage'
end

function LFG.getAvailableDungeons(level, type, mine, partyIndex)
    if level == 0 then
        return {}
    end
    local dungeons = {}

    local sourceData
    if type == 2 then
        sourceData = LFG.eliteEncounters
    else
        sourceData = LFG.allDungeons
    end

    for _, data in next, sourceData do
        if level >= data.minLevel and (level <= data.maxLevel or (not mine)) and type ~= 3 then
            dungeons[data.code] = true
        end
        if level >= data.minLevel and type == 3 then
            --all available
            dungeons[data.code] = true
        end
    end
    return dungeons
end

function LFG.fillAvailableDungeons(queueAfter, dont_scroll)

    if LFG_TYPE == 2 then
        -- Elite Encounters
        LFG.dungeons = LFG.eliteEncounters
    else
        -- Regular dungeons
        LFG.dungeons = LFG.allDungeons
    end

    --unqueue queued
    for dungeon, data in next, LFG.dungeons do
        LFG.dungeons[dungeon].canQueue = true
        if data.queued and LFG.level < data.minLevel then
            LFG.dungeons[dungeon].queued = false
        end
    end

    --hide all
    for _, frame in next, LFG.availableDungeons do
        _G["Dungeon_" .. frame.code]:Hide()
    end

    -- if grouped fill only dungeons that can be joined by EVERYONE
    if LFG.inGroup then

        local party = {
            [0] = {
                level = LFG.level,
                name = UnitName('player'),
                dungeons = LFG.getAvailableDungeons(LFG.level, LFG_TYPE, true)
            }
        }
        for i = 1, GetNumPartyMembers() do
            party[i] = {
                level = UnitLevel('party' .. i),
                name = UnitName('party' .. i),
                dungeons = LFG.getAvailableDungeons(UnitLevel('party' .. i), LFG_TYPE, false, i)
            }

            if party[i].level == 0 and UnitIsConnected('party' .. i) then
                LFGFillAvailableDungeonsDelay:Show()
                return false
            end
        end

        LFGFillAvailableDungeonsDelay.triggers = 0

        for dungeonCode in next, LFG.getAvailableDungeons(LFG.level, LFG_TYPE, true) do
            local canAdd = {
                [1] = UnitLevel('party1') == 0,
                [2] = UnitLevel('party2') == 0,
                [3] = UnitLevel('party3') == 0,
                [4] = UnitLevel('party4') == 0
            }

            for i = 1, GetNumPartyMembers() do
                for code in next, party[i].dungeons do
                    if dungeonCode == code then
                        canAdd[i] = true
                    end
                end
            end
            if canAdd[1] and canAdd[2] and canAdd[3] and canAdd[4] then
            else
                local cqName = LFG.dungeonNameFromCode(dungeonCode)
                if LFG.dungeons[cqName] then LFG.dungeons[cqName].canQueue = false end
            end
        end
    end

    local dungeonIndex = 0
    for dungeon, data in LFG.fuckingSortAlready(LFG.dungeons) do
        --    for dungeon, data in next, LFG.dungeons do
        if LFG.level >= data.minLevel and LFG.level <= data.maxLevel and LFG_TYPE ~= 3 then

            dungeonIndex = dungeonIndex + 1

            if not LFG.availableDungeons[data.code] then
                LFG.availableDungeons[data.code] = CreateFrame("Frame", "Dungeon_" .. data.code, _G["DungeonListScrollFrameChildren"], "LFG_DungeonItemTemplate")
            end

            if LFG.shouldHideButtonTextures() then
	            -- Hide button textures for the newly created dungeon item
			    LFG.hideButtonTextures("Dungeon_" .. data.code .. "_Button")
			end

            LFG.availableDungeons[data.code]:Show()

            local color = COLOR_GREEN
            if LFG.level == data.minLevel or LFG.level == data.minLevel + 1 then
                color = COLOR_RED
            end
            if LFG.level == data.minLevel + 2 or LFG.level == data.minLevel + 3 then
                color = COLOR_ORANGE
            end
            if LFG.level == data.minLevel + 4 or LFG.level == data.minLevel + 5 then
                color = COLOR_GREEN
            end

            if LFG.level > data.maxLevel then
                color = COLOR_GREEN
            end

            _G['Dungeon_' .. data.code .. '_CheckButton']:Enable()

            if data.canQueue then
                LFG.removeOnEnterTooltip(_G['Dungeon_' .. data.code .. '_Button'])
            else
                color = COLOR_DISABLED
                data.queued = false
                LFG.addOnEnterTooltip(_G['Dungeon_' .. data.code .. '_Button'], dungeon .. ' is unavailable',
                        'A member of your group does not meet', 'the suggested minimum level requirement (' .. data.minLevel .. ').')
                _G['Dungeon_' .. data.code .. '_CheckButton']:Disable()
            end

            _G['Dungeon_' .. data.code .. 'Text']:SetText(color .. dungeon)

            _G['Dungeon_' .. data.code .. 'Levels']:SetText(color .. '(' .. data.minLevel .. ' - ' .. data.maxLevel .. ')')

            _G['Dungeon_' .. data.code .. '_Button']:SetID(dungeonIndex)

            LFG.availableDungeons[data.code]:SetPoint("TOPLEFT", _G["DungeonListScrollFrameChildren"], "TOPLEFT", 5, 20 - 20 * (dungeonIndex))
            LFG.availableDungeons[data.code].code = data.code
            LFG.availableDungeons[data.code].background = data.background
            LFG.availableDungeons[data.code].minLevel = data.minLevel
            LFG.availableDungeons[data.code].maxLevel = data.maxLevel

            LFG.dungeons[dungeon].queued = data.queued
            _G['Dungeon_' .. data.code .. '_CheckButton']:SetChecked(data.queued)

        end

        if LFG.level >= data.minLevel and LFG_TYPE == 3 then
            --all available

            dungeonIndex = dungeonIndex + 1

            if not LFG.availableDungeons[data.code] then
                LFG.availableDungeons[data.code] = CreateFrame("Frame", "Dungeon_" .. data.code, _G["DungeonListScrollFrameChildren"], "LFG_DungeonItemTemplate")
            end

            LFG.availableDungeons[data.code]:Show()

            local color = COLOR_GREEN
            if LFG.level == data.minLevel or LFG.level == data.minLevel + 1 then
                color = COLOR_RED
            end
            if LFG.level == data.minLevel + 2 or LFG.level == data.minLevel + 3 then
                color = COLOR_ORANGE
            end
            if LFG.level == data.minLevel + 4 or LFG.level == data.minLevel + 5 then
                color = COLOR_GREEN
            end

            if LFG.level > data.maxLevel then
                color = COLOR_GREEN
            end

            _G['Dungeon_' .. data.code .. '_CheckButton']:Enable()

            if data.canQueue then
                LFG.removeOnEnterTooltip(_G['Dungeon_' .. data.code .. '_Button'])
            else
                color = COLOR_DISABLED
                data.queued = false
                LFG.addOnEnterTooltip(_G['Dungeon_' .. data.code .. '_Button'], dungeon .. ' is unavailable',
                        'A member of your group does not meet', 'the suggested minimum level requirement (' .. data.minLevel .. ').')
                _G['Dungeon_' .. data.code .. '_CheckButton']:Disable()
            end

            _G['Dungeon_' .. data.code .. 'Text']:SetText(color .. dungeon)
            _G['Dungeon_' .. data.code .. 'Levels']:SetText(color .. '(' .. data.minLevel .. ' - ' .. data.maxLevel .. ')')
            _G['Dungeon_' .. data.code .. '_Button']:SetID(dungeonIndex)

            LFG.availableDungeons[data.code]:SetPoint("TOPLEFT", _G["DungeonListScrollFrameChildren"], "TOPLEFT", 5, 20 - 20 * (dungeonIndex))
            LFG.availableDungeons[data.code].code = data.code
            LFG.availableDungeons[data.code].background = data.background
            LFG.availableDungeons[data.code].minLevel = data.minLevel
            LFG.availableDungeons[data.code].maxLevel = data.maxLevel

        end

        if LFG.findingGroup then
            if _G['Dungeon_' .. data.code .. '_CheckButton'] then
                _G['Dungeon_' .. data.code .. '_CheckButton']:Disable()
            end
        end

        if LFG.findingMore then
            if _G['Dungeon_' .. data.code .. '_CheckButton'] then
                _G['Dungeon_' .. data.code .. '_CheckButton']:Disable()
                _G['Dungeon_' .. data.code .. '_CheckButton']:SetChecked(false)
            end
            if data.code == LFG.LFMDungeonCode then
                if _G['Dungeon_' .. data.code .. '_CheckButton'] then
                    _G['Dungeon_' .. data.code .. '_CheckButton']:SetChecked(true)
                end
                LFG.dungeons[dungeon].queued = true
            end
        end
        if _G['Dungeon_' .. data.code .. '_CheckButton'] then
            if _G['Dungeon_' .. data.code .. '_CheckButton']:GetChecked() then
                LFG.dungeons[dungeon].queued = true
            end
        end
    end

    -- gray out the rest if there are 5 already checked
    local queues = 0
    for _, d in next, LFG.dungeons do
        if d.queued then
            queues = queues + 1
        end
    end
    if queues >= LFG.maxDungeonsInQueue then

        for _, frame in next, LFG.availableDungeons do
            local dungeonName = LFG.dungeonNameFromCode(frame.code)
            if not LFG.dungeons[dungeonName].queued then
                _G["Dungeon_" .. frame.code .. '_CheckButton']:Disable()
                _G['Dungeon_' .. frame.code .. 'Text']:SetText(COLOR_DISABLED .. dungeonName)
                _G['Dungeon_' .. frame.code .. 'Levels']:SetText(COLOR_DISABLED .. '(' .. frame.minLevel .. ' - ' .. frame.maxLevel .. ')')

                local q = 'dungeons'
                LFG.addOnEnterTooltip(_G['Dungeon_' .. frame.code .. '_Button'], 'Queueing for ' .. dungeonName .. ' is unavailable', 'Maximum allowed queued ' .. q .. ' at a time is ' .. LFG.maxDungeonsInQueue .. '.')
            end
        end
    end
    -- end gray

    LFG.fixMainButton()

    if queueAfter then
        LFGFillAvailableDungeonsDelay.queueAfterIfPossible = false

        --find checked dungeon
        local qDungeon = ''
        local dungeonName = ''
        for _, frame in next, LFG.availableDungeons do
            if _G["Dungeon_" .. frame.code .. '_CheckButton']:GetChecked() then
                qDungeon = frame.code
            end
        end
        if qDungeon == '' then
            return false --do nothing
        end

        dungeonName = LFG.dungeonNameFromCode(qDungeon)

        if LFG.dungeons[dungeonName].canQueue then
            findMore()
        else
            lfprint('A member of your group does not meet the suggested minimum level requirement for |cff69ccf0' .. dungeonName)
        end
    end

    if dont_scroll then
        return
    end
    _G['DungeonListScrollFrame']:SetVerticalScroll(0)
    _G['DungeonListScrollFrame']:UpdateScrollChildRect()

    if LFG.shouldHideButtonTextures() then
	    for code, frame in next, LFG.availableDungeons do
	        if frame then
	            LFG.hideButtonTextures("Dungeon_" .. code .. "_Button")
	        end
	    end

	    LFG.hideButtonTextures("LFGBrowseButton")
	    LFG.hideButtonTextures("LFGDungeonsButton")
	end
end

function LFG.enableDungeonCheckButtons()
    for _, frame in next, LFG.availableDungeons do
        _G["Dungeon_" .. frame.code .. '_CheckButton']:Enable()
    end
    DungeonListFrame_Update()
end

function LFG.disableDungeonCheckButtons(except)
    for _, frame in next, LFG.availableDungeons do
        if except and except == frame.code then
            --dont disable
        else
            _G["Dungeon_" .. frame.code .. '_CheckButton']:Disable()
        end
    end
end

function LFG.resetGroup()
    LFG.group = {};
    if not LFG.oneGroupFull then
        LFG.groupFullCode = ''
    end
    LFG.acceptNextInvite = false
    LFG.onlyAcceptFrom = ''
    LFG.foundGroup = false

    LFG.currentGroupRoles = {}

    LFG.isLeader = IsPartyLeader()
    LFG.inGroup = GetNumRaidMembers() == 0 and GetNumPartyMembers() > 0

    LFGGroupReadyFrameCloser.response = ''

    for dungeon, data in next, LFG.dungeons do

        LFG.dungeons[dungeon].myRole = ''

        if data.queued then
            local tank = ''
            if string.find(LFG_ROLE, 'tank', 1, true) then
                tank = me
            end
            LFG.group[data.code] = {
                tank = tank,
                healer = '',
                damage1 = '',
                damage2 = '',
                damage3 = '',
            }
        end
    end
    LFG.myRandomTime = math.random(LFG.random_min, LFG.random_max)
    LFG.LFMGroup = {
        tank = '',
        healer = '',
        damage1 = '',
        damage2 = '',
        damage3 = '',
    }
end

function LFG.addTank(dungeon, name, faux, add)
    -- Prevent adding same person twice, for both elite and regular dungeons
    if LFG.group[dungeon].tank == name or
            LFG.group[dungeon].healer == name or
            LFG.group[dungeon].damage1 == name or
            LFG.group[dungeon].damage2 == name or
            LFG.group[dungeon].damage3 == name then
        return false
    end

    if LFG.classRun and not faux and LFG.classRunEligible(dungeon) then
        local class = LFG.playerClass(name)
        if LFG.classConflictsInGroup(dungeon, class) then
            lfdebug('classRun: rejecting ' .. name .. ' (' .. class .. ') - class already in group for ' .. dungeon)
            return false
        end
    end

    if LFG.isEliteEncounter(dungeon) then
        -- For Elite Encounters, allow any role to fill any slot
        if LFG.group[dungeon].tank == '' then
            if add then LFG.group[dungeon].tank = name end
            if not faux then
                --SendChatMessage('found:tank:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        elseif LFG.group[dungeon].healer == '' then
            if add then LFG.group[dungeon].healer = name end
            if not faux then
                --SendChatMessage('found:tank:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        elseif LFG.group[dungeon].damage1 == '' then
            if add then LFG.group[dungeon].damage1 = name end
            if not faux then
                --SendChatMessage('found:tank:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        elseif LFG.group[dungeon].damage2 == '' then
            if add then LFG.group[dungeon].damage2 = name end
            if not faux then
                --SendChatMessage('found:tank:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        elseif LFG.group[dungeon].damage3 == '' then
            if add then LFG.group[dungeon].damage3 = name end
            if not faux then
                --SendChatMessage('found:tank:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        end
        return false -- Group is full
    else
        -- Regular dungeons: strict tank role validation
        if LFG.group[dungeon].tank == '' then
            if add then
                LFG.group[dungeon].tank = name
            end
            if not faux then
                --SendChatMessage('found:tank:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        end
        return false
    end
end

function LFG.addHealer(dungeon, name, faux, add)
    -- Prevent adding same person twice, for both elite and regular dungeons
    if LFG.group[dungeon].healer == name or
            LFG.group[dungeon].damage1 == name or
            LFG.group[dungeon].damage2 == name or
            LFG.group[dungeon].damage3 == name or
            LFG.group[dungeon].tank == name then
        return false
    end

    if LFG.classRun and not faux and LFG.classRunEligible(dungeon) then
        local class = LFG.playerClass(name)
        if LFG.classConflictsInGroup(dungeon, class) then
            lfdebug('classRun: rejecting ' .. name .. ' (' .. class .. ') - class already in group for ' .. dungeon)
            return false
        end
    end

    if LFG.isEliteEncounter(dungeon) then
        -- For Elite Encounters, allow any role to fill any slot
        if LFG.group[dungeon].tank == '' then
            if add then LFG.group[dungeon].tank = name end
            if not faux then
                --SendChatMessage('found:healer:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        elseif LFG.group[dungeon].healer == '' then
            if add then LFG.group[dungeon].healer = name end
            if not faux then
                --SendChatMessage('found:healer:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        elseif LFG.group[dungeon].damage1 == '' then
            if add then LFG.group[dungeon].damage1 = name end
            if not faux then
                --SendChatMessage('found:healer:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        elseif LFG.group[dungeon].damage2 == '' then
            if add then LFG.group[dungeon].damage2 = name end
            if not faux then
                --SendChatMessage('found:healer:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        elseif LFG.group[dungeon].damage3 == '' then
            if add then LFG.group[dungeon].damage3 = name end
            if not faux then
                --SendChatMessage('found:healer:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        end
        return false -- Group is full
    else
        -- Regular dungeons: strict healer role validation
        if LFG.group[dungeon].healer == '' then
            if add then
                LFG.group[dungeon].healer = name
            end
            if not faux then
                --SendChatMessage('found:healer:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        end
        return false
    end
end

function LFG.remHealerOrDamage(dungeon, name)
    if LFG.isEliteEncounter(dungeon) then
        -- For Elite Encounters, check all slots since any role can be in any slot
        if LFG.group[dungeon].tank == name then
            LFG.group[dungeon].tank = ''
        end
    end

    if LFG.group[dungeon].healer == name then
        LFG.group[dungeon].healer = ''
    end
    if LFG.group[dungeon].damage1 == name then
        LFG.group[dungeon].damage1 = ''
    end
    if LFG.group[dungeon].damage2 == name then
        LFG.group[dungeon].damage2 = ''
    end
    if LFG.group[dungeon].damage3 == name then
        LFG.group[dungeon].damage3 = ''
    end
end

function LFG.addDamage(dungeon, name, faux, add)
    if not LFG.group[dungeon] then
        LFG.group[dungeon] = {
            tank = '',
            healer = '',
            damage1 = '',
            damage2 = '',
            damage3 = ''
        }
    end

    -- Prevent adding same person twice, for both elite and regular dungeons
    if LFG.group[dungeon].tank == name or
            LFG.group[dungeon].healer == name or
            LFG.group[dungeon].damage1 == name or
            LFG.group[dungeon].damage2 == name or
            LFG.group[dungeon].damage3 == name then
        return false
    end

    if LFG.classRun and not faux and LFG.classRunEligible(dungeon) then
        local class = LFG.playerClass(name)
        if LFG.classConflictsInGroup(dungeon, class) then
            lfdebug('classRun: rejecting ' .. name .. ' (' .. class .. ') - class already in group for ' .. dungeon)
            return false
        end
    end

    if LFG.isEliteEncounter(dungeon) then
        -- For Elite Encounters, allow any role to fill any slot
        if LFG.group[dungeon].tank == '' then
            if add then LFG.group[dungeon].tank = name end
            if not faux then
                --SendChatMessage('found:damage:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        elseif LFG.group[dungeon].healer == '' then
            if add then LFG.group[dungeon].healer = name end
            if not faux then
                --SendChatMessage('found:damage:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        elseif LFG.group[dungeon].damage1 == '' then
            if add then LFG.group[dungeon].damage1 = name end
            if not faux then
                --SendChatMessage('found:damage:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        elseif LFG.group[dungeon].damage2 == '' then
            if add then LFG.group[dungeon].damage2 = name end
            if not faux then
                --SendChatMessage('found:damage:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        elseif LFG.group[dungeon].damage3 == '' then
            if add then LFG.group[dungeon].damage3 = name end
            if not faux then
                --SendChatMessage('found:damage:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        end
        return false -- Group is full
    else
        -- Regular dungeons: strict damage role validation (up to 3 damage slots)
        if LFG.group[dungeon].damage1 == '' then
            if add then LFG.group[dungeon].damage1 = name end
            if not faux then
                --SendChatMessage('found:damage:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        elseif LFG.group[dungeon].damage2 == '' then
            if add then LFG.group[dungeon].damage2 = name end
            if not faux then
                --SendChatMessage('found:damage:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        elseif LFG.group[dungeon].damage3 == '' then
            if add then LFG.group[dungeon].damage3 = name end
            if not faux then
                --SendChatMessage('found:damage:' .. dungeon .. ':' .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
            end
            return true
        end
        return false -- Group full on damage
    end
end

function LFG.checkGroupFull()

    for _, data in next, LFG.dungeons do
        if data.queued then
            local members = 0
            if LFG.group[data.code].tank ~= '' then
                members = members + 1
            end
            if LFG.group[data.code].healer ~= '' then
                members = members + 1
            end
            if LFG.group[data.code].damage1 ~= '' then
                members = members + 1
            end
            if LFG.group[data.code].damage2 ~= '' then
                members = members + 1
            end
            if LFG.group[data.code].damage3 ~= '' then
                members = members + 1
            end
            lfdebug('members = ' .. members .. ' (' .. LFG.group[data.code].tank ..
                    ',' .. LFG.group[data.code].healer .. ',' .. LFG.group[data.code].damage1 ..
                    ',' .. LFG.group[data.code].damage2 .. ',' .. LFG.group[data.code].damage3 .. ')')
            if members == LFG.groupSizeMax then
                LFG.oneGroupFull = true
                LFG.group[data.code].full = true

                return true, data.code, LFG.group[data.code].healer, LFG.group[data.code].damage1, LFG.group[data.code].damage2, LFG.group[data.code].damage3
            else
                LFG.group[data.code].full = false
                LFG.oneGroupFull = false
            end
        end
    end

    return false, false, nil, nil, nil, nil
end

function LFG.showMyRoleIcon(myRole)
    if _G['PlayerPortrait']:IsVisible() then
        _G['LFGPartyRoleIconsPlayer']:SetTexture('Interface\\addons\\LFG\\images\\' .. myRole .. '_small')
        _G['LFGPartyRoleIconsPlayer']:Show()
    else
        _G['LFGPartyRoleIconsPlayer']:Hide()
    end
end

function LFG.showPartyRoleIcons(role, name)
    if not role and not name then
        for i = 1, 4 do
            if _G['PartyMemberFrame' .. i .. 'Portrait']:IsVisible() then
                if LFG.currentGroupRoles[UnitName('party' .. i)] then
                    _G['LFGPartyRoleIconsParty' .. i]:SetTexture('Interface\\addons\\LFG\\images\\' .. LFG.currentGroupRoles[UnitName('party' .. i)] .. '_small')
                    _G['LFGPartyRoleIconsParty' .. i]:Show()
                end
            else
                _G['LFGPartyRoleIconsParty' .. i]:Hide()
            end
        end
        return true
    end
    LFG.currentGroupRoles[name] = role
    for i = 1, GetNumPartyMembers() do
        if UnitName('party' .. i) == name then
            if _G['PartyMemberFrame' .. i .. 'Portrait']:IsVisible() then
                _G['LFGPartyRoleIconsParty' .. i]:SetTexture('Interface\\addons\\LFG\\images\\' .. role .. '_small')
                _G['LFGPartyRoleIconsParty' .. i]:Show()
            else
                _G['LFGPartyRoleIconsParty' .. i]:Hide()
            end
        end
    end
end

function LFG.hideMyRoleIcon()
    _G['LFGPartyRoleIconsPlayer']:Hide()
end

function LFG.hidePartyRoleIcons()
    LFG.hideMyRoleIcon()
    _G['LFGPartyRoleIconsParty1']:Hide()
    _G['LFGPartyRoleIconsParty2']:Hide()
    _G['LFGPartyRoleIconsParty3']:Hide()
    _G['LFGPartyRoleIconsParty4']:Hide()
end

function LFG.dungeonNameFromCode(code)
    for name, data in next, LFG.dungeons do
        if data.code == code then
            return name, data.background
        end
    end

    for name, data in next, LFG.allDungeons do
        if data.code == code then
            return name, data.background
        end
    end

    for name, data in next, LFG.eliteEncounters do
        if data.code == code then
            return name, data.background
        end
    end

    return 'Unknown', 'UnknownBackground'
end

function LFG.dungeonFromCode(code)
    -- Use dungeonNameFromCode (which already searches all tables) to get the
    -- name key, then do a single O(1) hash lookup instead of three O(n) loops.
    local name = LFG.dungeonNameFromCode(code)
    if not name or name == 'Unknown' then return false end
    return LFG.allDungeons[name] or LFG.eliteEncounters[name] or false
end

function LFG.AcceptGroupInvite()
    AcceptGroup()
    StaticPopup_Hide("PARTY_INVITE")
    PlaySoundFile("Sound\\Doodad\\BellTollNightElf.wav")
    UIErrorsFrame:AddMessage("[LFG] Group Auto Accept")
end

function LFG.DeclineGroupInvite()
    DeclineGroup()
    StaticPopup_Hide("PARTY_INVITE")
end

function LFG.fuckingSortAlready(t, reverse)
    local a = {}
    for n, l in pairs(t) do
        table.insert(a, { ['code'] = l.code, ['minLevel'] = l.minLevel, ['name'] = n })
    end
    if reverse then
        table.sort(a, function(a, b)
            return a['minLevel'] > b['minLevel']
        end)
    else
        table.sort(a, function(a, b)
            return a['minLevel'] < b['minLevel']
        end)
    end

    local i = 0 -- iterator variable
    local iter = function()
        -- iterator function
        i = i + 1
        if a[i] == nil then
            return nil
            --        else return a[i]['code'], t[a[i]['name']]
        else
            return a[i]['name'], t[a[i]['name']]
        end
    end
    return iter
end

function LFG.tableSize(t)
    local size = 0
    for _, _ in next, t do
        size = size + 1
    end
    return size
end

function LFG.checkLFMgroup(someoneDeclined)

    if someoneDeclined then
        if someoneDeclined ~= me then
            lfprint(LFG.classColors[LFG.playerClass(someoneDeclined)].c .. someoneDeclined .. COLOR_WHITE .. ' declined role check.')
            lfdebug('LFGRoleCheck:Hide() in checkLFMgroup someone declined')
            LFGRoleCheck:Hide()
        end
        return false
    end

    if not LFG.isLeader then
        return
    end

    local currentGroupSize = GetNumPartyMembers() + 1
    local readyNumber = 0
    if LFG.LFMGroup.tank ~= '' then
        readyNumber = readyNumber + 1
    end
    if LFG.LFMGroup.healer ~= '' then
        readyNumber = readyNumber + 1
    end
    if LFG.LFMGroup.damage1 ~= '' then
        readyNumber = readyNumber + 1
    end
    if LFG.LFMGroup.damage2 ~= '' then
        readyNumber = readyNumber + 1
    end
    if LFG.LFMGroup.damage3 ~= '' then
        readyNumber = readyNumber + 1
    end

    if currentGroupSize == readyNumber then
        LFG.findingMore = true
        lfdebug('group ready ? ' .. currentGroupSize .. ' = ' .. readyNumber)
        lfdebug(LFG.LFMGroup.tank)
        lfdebug(LFG.LFMGroup.healer)
        lfdebug(LFG.LFMGroup.damage1)
        lfdebug(LFG.LFMGroup.damage2)
        lfdebug(LFG.LFMGroup.damage3)
        --everyone is ready / confirmed roles

        LFG.group[LFG.LFMDungeonCode] = {
            tank = LFG.LFMGroup.tank,
            healer = LFG.LFMGroup.healer,
            damage1 = LFG.LFMGroup.damage1,
            damage2 = LFG.LFMGroup.damage2,
            damage3 = LFG.LFMGroup.damage3,
        }
        SendAddonMessage(LFG_ADDON_CHANNEL, "weInQueue:" .. LFG.LFMDungeonCode, "PARTY")
        lfdebug('LFGRoleCheck:Hide() in checkLFMGROUP we ready')
        LFGRoleCheck:Hide()
    end
end

function LFG.weInQueue(code)

    local dungeonName = LFG.dungeonNameFromCode(code)
    if LFG.dungeons[dungeonName] then
        LFG.dungeons[dungeonName].queued = true
    end

    lfprint('Your group is in the queue for |cff69ccf0' .. dungeonName)

    LFG.findingGroup = true
    LFG.findingMore = true
    LFG.disableDungeonCheckButtons()

    _G['RoleTank']:Disable()
    _G['RoleHealer']:Disable()
    _G['RoleDamage']:Disable()

    PlaySound('PvpEnterQueue')

    if LFG.isLeader then
        LFG.sendMinimapDataToParty(code)
    else
        LFG.group[code] = {
            tank = '',
            healer = '',
            damage1 = '',
            damage2 = '',
            damage3 = ''
        }
    end

    LFG.oneGroupFull = false
    LFG.queueStartTime = time()
    LFGQueue:Show()
    LFGMinimapAnimation:Show()
    _G['LFGlfg']:Hide()
    LFG.fixMainButton()
end

function LFG.fixMainButton()

    local lfgButton = _G['findGroupButton']
    local lfmButton = _G['findMoreButton']
    local leaveQueueButton = _G['leaveQueueButton']

    lfgButton:Hide()
    lfmButton:Hide()
    leaveQueueButton:Hide()

    lfgButton:Disable()
    lfmButton:Disable()
    leaveQueueButton:Disable()

    LFG.inGroup = GetNumRaidMembers() == 0 and GetNumPartyMembers() > 0

    local queues = 0
    for _, data in next, LFG.dungeons do
        if data.queued then
            queues = queues + 1
        end
    end

    if queues > 0 then
        lfgButton:Enable()
    end

    if LFG.inGroup then
        lfmButton:Show()
        --GetNumPartyMembers() returns party size-1, doesnt count myself
        if GetNumPartyMembers() < (LFG.groupSizeMax - 1) and LFG.isLeader and queues > 0 then
            lfmButton:Enable()
            if LFG.LFMDungeonCode ~= '' then
                LFG.disableDungeonCheckButtons(LFG.LFMDungeonCode)
            end
        end
        if GetNumPartyMembers() == (LFG.groupSizeMax - 1) and LFG.isLeader then
            --group full
            lfmButton:Disable()
            LFG.disableDungeonCheckButtons()
        end
        if not LFG.isLeader then
            lfmButton:Disable()
            LFG.disableDungeonCheckButtons()
        end
    else
        lfgButton:Show()
    end

    if LFG.findingGroup then
        leaveQueueButton:Show()
        leaveQueueButton:Enable()
        if LFG.inGroup then
            if not LFG.isLeader then
                leaveQueueButton:Disable()
            end
        end
        lfgButton:Hide()
        lfmButton:Hide()
    end

    if GetNumRaidMembers() > 0 then
        lfgButton:Disable()
        lfmButton:Disable()
        leaveQueueButton:Disable()
    end

    -- todo replace this with LFG_ROLE == ''
    local tankCheck = _G['RoleTank']
    local healerCheck = _G['RoleHealer']
    local damageCheck = _G['RoleDamage']
    local newRole = ''
    if tankCheck:GetChecked() then
        newRole = newRole .. 'tank'
    end
    if healerCheck:GetChecked() then
        newRole = newRole .. 'healer'
    end
    if damageCheck:GetChecked() then
        newRole = newRole .. 'damage'
    end

    if newRole == '' then
        lfgButton:Disable()
        lfmButton:Disable()
    end
end

function LFG.sendCancelMeMessage()
    if string.find(LFG_ROLE, 'tank', 1, true) then
        SendChatMessage('leftQueue:tank', "CHANNEL",DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))

    end
    if string.find(LFG_ROLE, 'healer', 1, true) then
        SendChatMessage('leftQueue:healer', "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))

    end
    if string.find(LFG_ROLE, 'damage', 1, true) then
        SendChatMessage('leftQueue:damage', "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))

    end
end

function LFG.sendLFGMessage(role)

    local myClass = LFG.class ~= '' and LFG.class or LFG.playerClass(me)
    local crFlag = LFG.classRun and ':cr' or ''
    local lfg_text = ''
    for code, _ in pairs(LFG.group) do
        if LFG.supress[code] == role then
            LFG.supress[code] = ''
        else
            -- Format: LFG:<dungeonCode>:<role>:<class>[:<cr>]
            -- class field read by protocol v3+ leaders for class run matching.
            -- :cr flag signals the player wants a class run group.
            -- Old clients ignore extra fields safely.
            lfg_text = 'LFG:' .. code .. ':' .. role .. ':' .. myClass .. crFlag .. ' ' .. lfg_text
        end
    end
    lfg_text = string.sub(lfg_text, 1, string.len(lfg_text) - 1)

    -- Guard: all codes were suppressed → nothing to send
    if lfg_text == '' then
        lfdebug('sendLFGMessage: all codes suppressed for role ' .. role .. ', skipping send')
        return
    end

    SendChatMessage(lfg_text, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
end

function LFG.sendLFMStats(code)

    if code == '' then
        lfdebug('cant send lfm stats, code = blank')
        return false
    end
    if not LFG.group[code] then
        return false
    end
    local tank, healer, damage = 0, 0, 0
    if LFG.group[code].tank ~= '' then
        tank = tank + 1
    end
    if LFG.group[code].healer ~= '' then
        healer = healer + 1
    end
    if LFG.group[code].damage1 ~= '' then
        damage = damage + 1
    end
    if LFG.group[code].damage2 ~= '' then
        damage = damage + 1
    end
    if LFG.group[code].damage3 ~= '' then
        damage = damage + 1
    end

    local crSuffix = LFG.crLeader and ':cr' or ''
    SendChatMessage("LFM:" .. code .. ":" .. tank .. ":" .. healer .. ":" .. damage .. crSuffix, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
    if LFG.crLeader then LFG.crLastLFMTime = time() end
end

function LFG.isNeededInLFMGroup(role, name, code)

    if role == 'tank' and LFG.group[code].tank == '' then
        --        LFG.group[code].tank = name
        return true
    end
    if role == 'healer' and LFG.group[code].healer == '' then
        --        LFG.group[code].healer = name
        return true
    end
    if role == 'damage' then
        if LFG.group[code].damage1 == '' then
            --            LFG.group[code].damage1 = name
            return true
        end
        if LFG.group[code].damage2 == '' then
            --            LFG.group[code].damage2 = name
            return true
        end
        if LFG.group[code].damage3 == '' then
            --            LFG.group[code].damage3 = name
            return true
        end
    end
    return false
end

function LFG.inviteInLFMGroup(name)
    SendChatMessage("[LFG]:" .. LFG.LFMDungeonCode .. ":(LFM):" .. name, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
    InviteUnit(name)
end

function LFG.checkLFMGroupReady(code)
    if not LFG.isLeader then
        return
    end

    local members = 0

    if LFG.group[code].tank ~= '' then
        members = members + 1
    end
    if LFG.group[code].healer ~= '' then
        members = members + 1
    end
    if LFG.group[code].damage1 ~= '' then
        members = members + 1
    end
    if LFG.group[code].damage2 ~= '' then
        members = members + 1
    end
    if LFG.group[code].damage3 ~= '' then
        members = members + 1
    end

    return members == LFG.groupSizeMax
end

function LFG.sendMinimapDataToParty(code)
    lfdebug('send minimap data to party code = ' .. code)
    if code == '' then
        return false
    end
    if not LFG.group[code] then
        return false
    end
    local tank, healer, damage = 0, 0, 0
    if LFG.group[code].tank ~= '' then
        tank = tank + 1
    end
    if LFG.group[code].healer ~= '' then
        healer = healer + 1
    end
    if LFG.group[code].damage1 ~= '' then
        damage = damage + 1
    end
    if LFG.group[code].damage2 ~= '' then
        damage = damage + 1
    end
    if LFG.group[code].damage3 ~= '' then
        damage = damage + 1
    end
    SendAddonMessage(LFG_ADDON_CHANNEL, "minimap:" .. code .. ":" .. tank .. ":" .. healer .. ":" .. damage, "PARTY")
end

function LFG.addOnEnterTooltip(frame, title, text1, text2, x, y)
    frame:SetScript("OnEnter", function()
        if x and y then
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT", x, y)
        else
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT", -200, -5)
        end
        GameTooltip:AddLine(title)
        if text1 then
            GameTooltip:AddLine(text1, 1, 1, 1)
        end
        if text2 then
            GameTooltip:AddLine(text2, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

function LFG.removeOnEnterTooltip(frame)
    frame:SetScript("OnEnter", function()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

function LFG.sendMyVersion()
    SendAddonMessage(LFG_ADDON_CHANNEL, "LFGVersion:" .. addonVer, "PARTY")
    SendAddonMessage(LFG_ADDON_CHANNEL, "LFGVersion:" .. addonVer, "GUILD")
    SendAddonMessage(LFG_ADDON_CHANNEL, "LFGVersion:" .. addonVer, "RAID")
    SendAddonMessage(LFG_ADDON_CHANNEL, "LFGVersion:" .. addonVer, "BATTLEGROUND")
end

function LFG.removePlayerFromVirtualParty(name, mRole)
    if not mRole then
        mRole = 'unknown'
    end
    for dungeonCode, data in next, LFG.group do
        if data.tank == name and (mRole == 'tank' or mRole == 'unknown') then
            LFG.group[dungeonCode].tank = ''
        end
        if data.healer == name and (mRole == 'healer' or mRole == 'unknown') then
            LFG.group[dungeonCode].healer = ''
        end
        if data.damage1 == name and (mRole == 'damage' or mRole == 'unknown') then
            LFG.group[dungeonCode].damage1 = ''
        end
        if data.damage2 == name and (mRole == 'damage' or mRole == 'unknown') then
            LFG.group[dungeonCode].damage2 = ''
        end
        if data.damage3 == name and (mRole == 'damage' or mRole == 'unknown') then
            LFG.group[dungeonCode].damage3 = ''
        end
    end
    -- Clear stale class data so a returning player isn't falsely rejected
    for dungeonCode, _ in next, LFG.seenClasses do
        if LFG.seenClasses[dungeonCode] then
            LFG.seenClasses[dungeonCode][name] = nil
        end
    end
    -- Clear stale CR candidate entry and re-run election in case they were leader
    for dungeonCode, _ in next, LFG.crCandidates do
        if LFG.crCandidates[dungeonCode] then
            LFG.crCandidates[dungeonCode][name] = nil
        end
    end
    LFG.crCheckElection()
end

function LFG.deQueueAll()
    for dungeon, data in next, LFG.dungeons do
        if data.queued then
            LFG.dungeons[dungeon].queued = false
        end
    end
end

function LFG.resetFormedGroups()
    LFG_FORMED_GROUPS = {}
    for _, data in next, LFG.dungeons do
        LFG_FORMED_GROUPS[data.code] = 0
    end
end

function LFG.readyStatusReset()
    _G['LFGReadyStatusReadyTank']:SetTexture('Interface\\addons\\LFG\\images\\readycheck-waiting')
    _G['LFGReadyStatusReadyHealer']:SetTexture('Interface\\addons\\LFG\\images\\readycheck-waiting')
    _G['LFGReadyStatusReadyDamage1']:SetTexture('Interface\\addons\\LFG\\images\\readycheck-waiting')
    _G['LFGReadyStatusReadyDamage2']:SetTexture('Interface\\addons\\LFG\\images\\readycheck-waiting')
    _G['LFGReadyStatusReadyDamage3']:SetTexture('Interface\\addons\\LFG\\images\\readycheck-waiting')
end

function test_dung_ob(code)
    LFG.showDungeonObjectives(code)
end

function LFG.showDungeonObjectives(code, numObjectivesComplete)

    local dungeonName = LFG.dungeonNameFromCode(LFG.groupFullCode)
    if numObjectivesComplete then
        lfdebug('showdungeons obj call with numObjectivesComplete = ' .. numObjectivesComplete)
        LFGObjectives.objectivesComplete = numObjectivesComplete
    else
        lfdebug('showdungeons obj call without numObjectivesComplete')
        LFGObjectives.objectivesComplete = 0
    end

    lfdebug('LFGObjectives.objectivesComplete = ' .. LFGObjectives.objectivesComplete)

    --hideall
    for index, _ in next, LFG.objectivesFrames do
        if _G["LFGObjective" .. index] then
            _G["LFGObjective" .. index]:Hide()
        end
    end

    if LFG.dungeons[dungeonName] then
        if LFG.bosses[LFG.groupFullCode] then
            _G['LFGDungeonStatusDungeonName']:SetText(dungeonName)

            local index = 0
            for _, boss in next, LFG.bosses[LFG.groupFullCode] do
                index = index + 1
                if not LFG.objectivesFrames[index] then
                    LFG.objectivesFrames[index] = CreateFrame("Frame", "LFGObjective" .. index, _G['LFGDungeonStatus'], "LFGObjectiveBossTemplate")
                end
                LFG.objectivesFrames[index]:Show()
                LFG.objectivesFrames[index].name = boss
                LFG.objectivesFrames[index].code = LFG.groupFullCode

                if LFG.objectivesFrames[index].completed == nil then
                    LFG.objectivesFrames[index].completed = false
                end

                _G["LFGObjective" .. index .. 'Swoosh']:SetAlpha(0)
                _G["LFGObjective" .. index .. 'ObjectiveComplete']:Hide()
                _G["LFGObjective" .. index .. 'ObjectivePending']:Show()

                if LFG.objectivesFrames[index].completed then
                    _G["LFGObjective" .. index .. 'ObjectiveComplete']:Show()
                    _G["LFGObjective" .. index .. 'ObjectivePending']:Hide()
                else
                    -- _G["LFGObjective" .. index .. 'Objective']:SetText(COLOR_DISABLED .. '0/1 ' .. boss .. ' defeated')
                    _G["LFGObjective" .. index .. 'Objective']:SetText(COLOR_DISABLED .. '' .. boss .. '')
                end

                LFG.objectivesFrames[index]:SetPoint("TOPLEFT", _G["LFGDungeonStatus"], "TOPLEFT", 10, -110 - 20 * (index))
            end

            _G["LFGDungeonStatusCollapseButton"]:Show()
            _G["LFGDungeonStatusExpandButton"]:Hide()
            _G["LFGDungeonStatus"]:Show()
        else
            _G["LFGDungeonStatus"]:Hide()
        end
    else
        _G["LFGDungeonStatus"]:Hide()
    end
end

function LFG.getDungeonCompletion()
    local completed = 0
    local total = 0
    for index, _ in next, LFG.objectivesFrames do
        if LFG.objectivesFrames[index].completed then
            completed = completed + 1
        end
        total = total + 1
    end
    if completed == 0 then
        return 0, 0
    end
    return math.floor((completed * 100) / total), completed
end

LFG.browseNames = {}

function LFG.LFGBrowse_Update()
    lfdebug('LFGBrowse_Update time is ' .. LFGTime.second)

    -- Show Class Run checkbox if any eligible dungeon is in level range
    local showClassRun = false
    for _, data in next, LFG.dungeons do
        if LFG.classRunEligible(data.code) and LFG.level >= data.minLevel then
            showClassRun = true
            break
        end
    end
    if _G['ClassRunCheckButton'] then
        if showClassRun then _G['ClassRunCheckButton']:Show() else _G['ClassRunCheckButton']:Hide() end
    end
    if _G['ClassRunLabel'] then
        if showClassRun then _G['ClassRunLabel']:Show() else _G['ClassRunLabel']:Hide() end
    end

    --hide all
    for _, frame in next, LFG.browseFrames do
        _G["BrowseFrame_" .. frame.code]:Hide()
    end

    local dungeonIndex = 0

    -- Fix: Use a regular for loop instead of relying on fuckingSortAlready
    local sortedDungeons = {}
    for dungeon, data in next, LFG.dungeons do
        table.insert(sortedDungeons, {name = dungeon, data = data})
    end

    -- Sort dungeons by minLevel in descending order
    table.sort(sortedDungeons, function(a, b)
        return a.data.minLevel > b.data.minLevel
    end)

    -- Now iterate through the sorted table
    for _, dungeonData in ipairs(sortedDungeons) do
        local dungeon = dungeonData.name
        local data = dungeonData.data

        if LFG.dungeonsSpam[data.code] and LFG.level >= data.minLevel then

            if LFG.dungeonsSpamDisplay[data.code].tank > 0 or LFG.dungeonsSpamDisplay[data.code].healer > 0 or LFG.dungeonsSpamDisplay[data.code].damage > 0 then

                dungeonIndex = dungeonIndex + 1

                if not LFG.browseFrames[data.code] then
                    LFG.browseFrames[data.code] = CreateFrame("Frame", "BrowseFrame_" .. data.code, _G["BrowseScrollFrameChildren"], "LFGBrowseDungeonTemplate")
                end

                _G['BrowseFrame_' .. data.code .. 'Background']:SetTexture('Interface\\addons\\LFG\\images\\background\\ui-lfg-background-' .. data.background)
                _G['BrowseFrame_' .. data.code .. 'Background']:SetAlpha(0.7)

                LFG.browseFrames[data.code]:Show()

                local color = COLOR_GREEN
                if LFG.level == data.minLevel or LFG.level == data.minLevel + 1 then
                    color = COLOR_RED
                end
                if LFG.level == data.minLevel + 2 or LFG.level == data.minLevel + 3 then
                    color = COLOR_ORANGE
                end
                if LFG.level == data.minLevel + 4 or LFG.level == data.minLevel + 5 then
                    color = COLOR_GREEN
                end

                if LFG.level > data.maxLevel then
                    color = COLOR_GREEN
                end

                _G["BrowseFrame_" .. data.code .. "DungeonName"]:SetText(color .. dungeon)
                _G["BrowseFrame_" .. data.code .. "IconLeader"]:Hide()

                if LFG.dungeonsSpamDisplayLFM[data.code] > 0 then
                    _G["BrowseFrame_" .. data.code .. "DungeonName"]:SetText(color .. dungeon .. " (" .. LFG.dungeonsSpamDisplayLFM[data.code] .. "/5)")
                    _G["BrowseFrame_" .. data.code .. "IconLeader"]:Show()
                end

                local tank_color = ''
                local healer_color = ''
                local damage_color = ''

                _G["BrowseFrame_" .. data.code .. "TankButtonTexture"]:SetDesaturated(0)
                if LFG.dungeonsSpamDisplay[data.code].tank == 0 then
                    tank_color = COLOR_DISABLED2
                    _G["BrowseFrame_" .. data.code .. "TankButtonTexture"]:SetDesaturated(1)
                    LFG.removeOnEnterTooltip(_G["BrowseFrame_" .. data.code .. "TankButton"])
                else
                    if LFG.browseNames[data.code] and LFG.browseNames[data.code]['tank'] then
                        LFG.addOnEnterTooltip(_G["BrowseFrame_" .. data.code .. "TankButton"], COLOR_TANK .. "Tank\n" .. COLOR_WHITE .. LFG.browseNames[data.code]['tank'], nil, nil, 15, 0)
                    end
                end

                _G["BrowseFrame_" .. data.code .. "HealerButtonTexture"]:SetDesaturated(0)
                if LFG.dungeonsSpamDisplay[data.code].healer == 0 then
                    healer_color = COLOR_DISABLED2
                    _G["BrowseFrame_" .. data.code .. "HealerButtonTexture"]:SetDesaturated(1)
                    LFG.removeOnEnterTooltip(_G["BrowseFrame_" .. data.code .. "HealerButton"])
                else
                    if LFG.browseNames[data.code] and LFG.browseNames[data.code]['healer'] then
                        LFG.addOnEnterTooltip(_G["BrowseFrame_" .. data.code .. "HealerButton"], COLOR_HEALER .. "Healer\n" .. COLOR_WHITE .. LFG.browseNames[data.code]['healer'], nil, nil, 15, 0)
                    end
                end

                _G["BrowseFrame_" .. data.code .. "DamageButtonTexture"]:SetDesaturated(0)
                if LFG.dungeonsSpamDisplay[data.code].damage == 0 then
                    damage_color = COLOR_DISABLED2
                    _G["BrowseFrame_" .. data.code .. "DamageButtonTexture"]:SetDesaturated(1)
                    LFG.removeOnEnterTooltip(_G["BrowseFrame_" .. data.code .. "DamageButton"])
                else
                    if LFG.browseNames[data.code] and LFG.browseNames[data.code]['damage'] then
                        LFG.addOnEnterTooltip(_G["BrowseFrame_" .. data.code .. "DamageButton"], COLOR_DAMAGE .. "Damage\n" .. COLOR_WHITE .. LFG.browseNames[data.code]['damage'], nil, nil, 15, 0)
                    end
                end

                _G["BrowseFrame_" .. data.code .. "NrTank"]:SetText(tank_color .. LFG.dungeonsSpamDisplay[data.code].tank)
                _G["BrowseFrame_" .. data.code .. "NrHealer"]:SetText(healer_color .. LFG.dungeonsSpamDisplay[data.code].healer)
                _G["BrowseFrame_" .. data.code .. "NrDamage"]:SetText(damage_color .. LFG.dungeonsSpamDisplay[data.code].damage)

                _G["BrowseFrame_" .. data.code .. "_JoinAs"]:Hide()

                if data.queued and (LFG.findingMore or LFG.findingGroup) then
                    _G["BrowseFrame_" .. data.code .. "InQueue"]:Show()
                else
                    _G["BrowseFrame_" .. data.code .. "InQueue"]:Hide()

                    local queues = 0
                    for dungeon, data in next, LFG.dungeons do
                        if data.queued then
                            queues = queues + 1
                        end
                    end

                    if not LFG.inGroup and queues < 5 then

                        if LFG.dungeonsSpamDisplay[data.code].tank == 0 and string.find(LFG_ROLE, 'tank', 1, true) then
                            _G["BrowseFrame_" .. data.code .. "_JoinAs"]:SetID(1)
                            _G["BrowseFrame_" .. data.code .. "_JoinAs"]:SetText('Join as Tank')
                            _G["BrowseFrame_" .. data.code .. "_JoinAs"]:Show()
                        elseif LFG.dungeonsSpamDisplay[data.code].healer == 0 and string.find(LFG_ROLE, 'healer', 1, true) then
                            _G["BrowseFrame_" .. data.code .. "_JoinAs"]:SetID(2)
                            _G["BrowseFrame_" .. data.code .. "_JoinAs"]:SetText('Join as Healer')
                            _G["BrowseFrame_" .. data.code .. "_JoinAs"]:Show()
                        elseif LFG.dungeonsSpamDisplay[data.code].damage < 3 and string.find(LFG_ROLE, 'damage', 1, true) then
                            _G["BrowseFrame_" .. data.code .. "_JoinAs"]:SetID(3)
                            _G["BrowseFrame_" .. data.code .. "_JoinAs"]:SetText('Join as Damage')
                            _G["BrowseFrame_" .. data.code .. "_JoinAs"]:Show()
                        end
                    end
                end

                LFG.browseFrames[data.code]:SetPoint("TOPLEFT", _G["BrowseScrollFrameChildren"], "TOPLEFT", 0, 41 - 41 * (dungeonIndex))
                LFG.browseFrames[data.code].code = data.code
            end
        end
    end

    if dungeonIndex > 0 then
        _G['LFGBrowseNoPeople']:Hide()
        _G['LFGBrowseBrowseText']:SetText('Browse (' .. dungeonIndex .. ')')
        _G['LFGMainBrowseText']:SetText('Browse (' .. dungeonIndex .. ')')
    else
        _G['LFGBrowseNoPeople']:Show()
        _G['LFGBrowseBrowseText']:SetText('Browse')
        _G['LFGMainBrowseText']:SetText('Browse')
    end

    _G['BrowseDungeonListScrollFrame']:UpdateScrollChildRect()
end

-- XML called methods and public functions

function checkRoleCompatibility(role)
    if role == 'tank' and (LFG.class == 'priest' or LFG.class == 'mage' or LFG.class == 'warlock' or LFG.class == 'hunter' or LFG.class == 'rogue') then
        GameTooltip:AddLine(ROLE_BAD_TOOLTIP, 1, 0, 0);
    end
    if role == 'healer' and (LFG.class == 'warrior' or LFG.class == 'mage' or LFG.class == 'warlock' or LFG.class == 'hunter' or LFG.class == 'rogue') then
        GameTooltip:AddLine(ROLE_BAD_TOOLTIP, 1, 0, 0);
    end
end

function lfg_replace(s, c, cc)
    return (string.gsub(s, c, cc))
end

function acceptRole()

    local myRole = ''
    if _G['roleCheckTank']:GetChecked() then
        myRole = 'tank'
    end
    if _G['roleCheckHealer']:GetChecked() then
        myRole = 'healer'
    end
    if _G['roleCheckDamage']:GetChecked() then
        myRole = 'damage'
    end
    local arName = LFG.dungeonNameFromCode(LFG.LFMDungeonCode)
    if LFG.dungeons[arName] then LFG.dungeons[arName].myRole = myRole end

    SendAddonMessage(LFG_ADDON_CHANNEL, "acceptRole:" .. myRole, "PARTY")
    LFG.showMyRoleIcon(myRole)
    --LFGRoleCheck:Hide()
    _G['LFGRoleCheck']:Hide()
end

function declineRole()
    local myRole = ''
    if _G['roleCheckTank']:GetChecked() then
        myRole = 'tank'
    end
    if _G['roleCheckHealer']:GetChecked() then
        myRole = 'healer'
    end
    if _G['roleCheckDamage']:GetChecked() then
        myRole = 'damage'
    end
    local drName = LFG.dungeonNameFromCode(LFG.LFMDungeonCode)
    if LFG.dungeons[drName] then LFG.dungeons[drName].myRole = myRole end
    SendAddonMessage(LFG_ADDON_CHANNEL, "declineRole:" .. myRole, "PARTY")

    --LFGRoleCheck:Hide()
    _G['LFGRoleCheck']:Hide()
end

function LFG_Toggle()

    -- remove channel from every chat frame
    LFG.removeChannelFromWindows()

    if LFG.level == 0 then
        LFG.level = UnitLevel('player')
    end

    for dungeon, data in next, LFG.dungeons do
        if not LFG.dungeonsSpam[data.code] then
            LFG.dungeonsSpam[data.code] = { tank = 0, healer = 0, damage = 0 }
        end
        if not LFG.dungeonsSpamDisplay[data.code] then
            LFG.dungeonsSpamDisplay[data.code] = { tank = 0, healer = 0, damage = 0 }
        end
        if not LFG.dungeonsSpamDisplayLFM[data.code] then
            LFG.dungeonsSpamDisplayLFM[data.code] = 0
        end
        if not LFG.supress[data.code] then
            LFG.supress[data.code] = ''
        end
    end

    if _G['LFGlfg']:IsVisible() then
        PlaySound("igCharacterInfoClose")
        _G['LFGlfg']:Hide()
    else
        PlaySound("igCharacterInfoOpen")
        _G['LFGlfg']:Show()

        if LFG.tab == 1 then

            LFG.checkLFGChannel()
            if not LFG.findingGroup then
                LFG.fillAvailableDungeons()
            end

            DungeonListFrame_Update()

        elseif LFG.tab == 2 then
            BrowseDungeonListFrame_Update()
        elseif LFG.tab == 3 then
            LFG.Grp_Init()
        end
    end

end

function sayReady()
    if LFG.inGroup and GetNumPartyMembers() + 1 == LFG.groupSizeMax then
        _G['LFGGroupReady']:Hide()
        -- Use the helper to find data across all tables
        local dungeonData = LFG.dungeonFromCode(LFG.groupFullCode)
        
        if not dungeonData then return end

        local myRole = dungeonData.myRole
        SendAddonMessage(LFG_ADDON_CHANNEL, "readyAs:" .. myRole, "PARTY")
        LFG.SetSingleRole(myRole)
        LFG.GetPossibleRoles()
        LFG.showMyRoleIcon(myRole)
        LFGMinimapAnimation:Hide()
        _G['LFGReadyStatus']:Show()
        LFGGroupReadyFrameCloser.response = 'ready'
        _G['LFGGroupReadyAwesome']:Disable()
    end
end

function sayNotReady()
    if LFG.inGroup and GetNumPartyMembers() + 1 == LFG.groupSizeMax then
        _G['LFGGroupReady']:Hide()

        -- Use the helper to find data across all tables
        local dungeonData = LFG.dungeonFromCode(LFG.groupFullCode)

        if not dungeonData then
            -- Fallback: if we can't find the role data, just send the global LFG_ROLE
            SendAddonMessage(LFG_ADDON_CHANNEL, "notReadyAs:" .. (LFG_ROLE or "damage"), "PARTY")
        else
            SendAddonMessage(LFG_ADDON_CHANNEL, "notReadyAs:" .. dungeonData.myRole, "PARTY")
        end

        LFG.GetPossibleRoles()
        LFGMinimapAnimation:Hide()
        _G['LFGReadyStatus']:Show()
        LFGGroupReadyFrameCloser.response = 'notReady'
        _G['LFGGroupReadyAwesome']:Disable()
    end
end

function LFG.SetSingleRole(role)

    _G['RoleTank']:SetChecked(role == 'tank')
    _G['roleCheckTank']:SetChecked(role == 'tank')

    _G['RoleHealer']:SetChecked(role == 'healer')
    _G['roleCheckHealer']:SetChecked(role == 'healer')

    _G['RoleDamage']:SetChecked(role == 'damage')
    _G['roleCheckDamage']:SetChecked(role == 'damage')

    LFG_ROLE = role

end

function LFGsetRole(role, status, readyCheck)

    local tankCheck = _G['RoleTank']
    local healerCheck = _G['RoleHealer']
    local damageCheck = _G['RoleDamage']

    --ready check window
    local readyCheckTank = _G['roleCheckTank']
    local readyCheckHealer = _G['roleCheckHealer']
    local readyCheckDamage = _G['roleCheckDamage']

    if readyCheck then
        _G['LFGRoleCheckAcceptRole']:Enable()

        if not readyCheckTank:GetChecked() and
                not readyCheckHealer:GetChecked() and
                not readyCheckDamage:GetChecked() then
            _G['LFGRoleCheckAcceptRole']:Disable()
        end

        readyCheckHealer:SetChecked(role == 'healer')
        readyCheckDamage:SetChecked(role == 'damage')
        readyCheckTank:SetChecked(role == 'tank')

        LFG_ROLE = role
        return true
    end

    local newRole = ''

    if LFG.inGroup then
        tankCheck:SetChecked(role == 'tank')
        healerCheck:SetChecked(role == 'healer')
        damageCheck:SetChecked(role == 'damage')
        newRole = role
    else
        if tankCheck:GetChecked() then
            newRole = newRole .. 'tank'
        end
        if healerCheck:GetChecked() then
            newRole = newRole .. 'healer'
        end
        if damageCheck:GetChecked() then
            newRole = newRole .. 'damage'
        end
    end

    LFG_ROLE = newRole

    LFG.fixMainButton()
    lfdebug('newRole = ' .. newRole)
    BrowseDungeonListFrame_Update()
end

function DungeonListFrame_Update(dont_scroll)
    LFG.fillAvailableDungeons(false, dont_scroll)
end

function BrowseDungeonListFrame_Update()
    LFG.LFGBrowse_Update()
end

function DungeonType_OnLoad()
    UIDropDownMenu_Initialize(this, DungeonType_Initialize);
    UIDropDownMenu_SetWidth(LFGTypeSelect, 160);
end

function DungeonType_OnClick(self, arg1)
    LFG_TYPE = arg1
    UIDropDownMenu_SetText(_G['LFGTypeSelect'], LFG.types[LFG_TYPE])

    _G['LFGMainDungeonsText']:SetText('Dungeons')
    _G['LFGBrowseDungeonsText']:SetText('Dungeons')

    _G['LFGDungeonsText']:SetText(LFG.types[LFG_TYPE])

    -- dequeue everything from before
    for dungeon, data in next, LFG.dungeons do
        if _G["Dungeon_" .. data.code .. '_CheckButton'] then
            _G["Dungeon_" .. data.code .. '_CheckButton']:SetChecked(false)
        end
        LFG.dungeons[dungeon].queued = false
    end

    -- dequeue everything after too
    for dungeon, data in next, LFG.dungeons do
        if data.queued then
            if _G["Dungeon_" .. data.code .. '_CheckButton'] then
                _G["Dungeon_" .. data.code .. '_CheckButton']:SetChecked(false)
            end
            LFG.dungeons[dungeon].queued = false
        end
    end

    if LFG_TYPE == 2 then
        LFG.dungeons = LFG.eliteEncounters
    else
        LFG.dungeons = LFG.allDungeons
    end

    for dungeon, data in next, LFG.dungeons do
        if not LFG.dungeonsSpam[data.code] then
            LFG.dungeonsSpam[data.code] = {
                tank = 0,
                healer = 0,
                damage = 0
            }
        end
        if not LFG.dungeonsSpamDisplay[data.code] then
            LFG.dungeonsSpamDisplay[data.code] = {
                tank = 0,
                healer = 0,
                damage = 0
            }
            LFG.dungeonsSpamDisplayLFM[data.code] = 0
        end
        if not LFG.supress[data.code] then
            LFG.supress[data.code] = ''
        end
    end

    LFG.fillAvailableDungeons()

    -- ADD THIS LINE - Hide button textures for newly created dungeon buttons
    if LFG.shouldHideButtonTextures() then
    	LFG.hideAllAddonButtonTextures()
    end
end

function DungeonType_Initialize()
    for id, type in pairs(LFG.types) do
        local info = {}
        info.text = type
        info.value = id
        info.arg1 = id
        info.checked = LFG_TYPE == id
        info.func = DungeonType_OnClick
        if not LFG.findingGroup then
            UIDropDownMenu_AddButton(info)
        end
    end
end

function LFG_HideMinimap()
    for i, frame in pairs(LFG.minimapFrames) do
        if frame and type(frame) == "table" and frame.Hide then
            frame:Hide()
        end
    end
    _G['LFGGroupStatus']:Hide()
end

function LFG_ShowMinimap()

    if LFG.findingGroup or LFG.findingMore then
        local dungeonIndex = 0
        for dungeonCode, _ in next, LFG.group do
            local tank = 0
            local healer = 0
            local damage = 0

            if LFG.group[dungeonCode].tank ~= '' or (not LFG.inGroup and string.find(LFG_ROLE, 'tank', 1, true)) then
                tank = tank + 1
            end
            if LFG.group[dungeonCode].healer ~= '' or (not LFG.inGroup and string.find(LFG_ROLE, 'healer', 1, true)) then
                healer = healer + 1
            end
            if LFG.group[dungeonCode].damage1 ~= '' or (not LFG.inGroup and string.find(LFG_ROLE, 'damage', 1, true)) then
                damage = damage + 1
            end
            if LFG.group[dungeonCode].damage2 ~= '' then
                damage = damage + 1
            end
            if LFG.group[dungeonCode].damage3 ~= '' then
                damage = damage + 1
            end

            if not LFG.minimapFrames[dungeonCode] then
                LFG.minimapFrames[dungeonCode] = CreateFrame('Frame', "LFGMinimap_" .. dungeonCode, UIParent, "LFGMinimapDungeonTemplate")
            end

            local background = ''
            local dungeonName = 'unknown'
            for d, data2 in next, LFG.dungeons do
                if data2.code == dungeonCode then
                    background = data2.background
                    dungeonName = d
                end
            end

            LFG.minimapFrames[dungeonCode]:Show()
            LFG.minimapFrames[dungeonCode]:SetPoint("TOP", _G["LFGGroupStatus"], "TOP", 0, -25 - 46 * (dungeonIndex))
            _G['LFGMinimap_' .. dungeonCode .. 'Background']:SetTexture('Interface\\addons\\LFG\\images\\background\\ui-lfg-background-' .. background)
            _G['LFGMinimap_' .. dungeonCode .. 'DungeonName']:SetText(dungeonName)

            --_G['LFGMinimap_' .. dungeonCode .. 'MyRole']:SetTexture('Interface\\addons\\LFG\\images\\ready_' .. LFG_ROLE)
            _G['LFGMinimap_' .. dungeonCode .. 'MyRole']:Hide() -- hide for now  - dev

            if tank == 0 then
                _G['LFGMinimap_' .. dungeonCode .. 'ReadyIconTank']:SetDesaturated(1)
            end
            if healer == 0 then
                _G['LFGMinimap_' .. dungeonCode .. 'ReadyIconHealer']:SetDesaturated(1)
            end
            if damage == 0 then
                _G['LFGMinimap_' .. dungeonCode .. 'ReadyIconDamage']:SetDesaturated(1)
            end
            _G['LFGMinimap_' .. dungeonCode .. 'NrTank']:SetText(tank .. '/1')
            _G['LFGMinimap_' .. dungeonCode .. 'NrHealer']:SetText(healer .. '/1')
            _G['LFGMinimap_' .. dungeonCode .. 'NrDamage']:SetText(damage .. '/3')

            dungeonIndex = dungeonIndex + 1
        end

        _G['LFGGroupStatus']:SetHeight(dungeonIndex * 46 + 95)
        _G['LFGGroupStatusTimeInQueue']:SetText('Time in Queue: ' .. SecondsToTime(time() - LFG.queueStartTime))
        if LFG.averageWaitTime == 0 then
            _G['LFGGroupStatusAverageWaitTime']:SetText('Average Wait Time: Unavailable')
        else
            _G['LFGGroupStatusAverageWaitTime']:SetText('Average Wait Time: ' .. SecondsToTimeAbbrev(LFG.averageWaitTime))
        end

        local x, y = GetCursorPosition()

        if x < 800 and y > 300 then
            _G['LFGGroupStatus']:SetPoint("TOPLEFT", _G["LFG_Minimap"], "BOTTOMRIGHT", 0, 0)
        elseif x < 800 and y < 300 then
            _G['LFGGroupStatus']:SetPoint("TOPLEFT", _G["LFG_Minimap"], "TOPRIGHT", 0, _G['LFGGroupStatus']:GetHeight())
        elseif x > 800 and y > 300 then
            _G['LFGGroupStatus']:SetPoint("TOPLEFT", _G["LFG_Minimap"], "TOPRIGHT", -_G['LFGGroupStatus']:GetWidth() - 40, -20)
        else
            _G['LFGGroupStatus']:SetPoint("TOPLEFT", _G["LFG_Minimap"], "TOPRIGHT", -_G['LFGGroupStatus']:GetWidth() - 40, _G['LFGGroupStatus']:GetHeight())
        end

        _G['LFGGroupStatus']:Show()
    else
        GameTooltip:SetOwner(_G['LFG_Minimap'], "ANCHOR_LEFT", 0, -110)
        GameTooltip:AddLine('Looking For Group', 1, 1, 1)
        GameTooltip:AddLine('Left-click to open LFG.')
        GameTooltip:AddLine('Drag to move.')
        GameTooltip:AddLine('You are not queued for any dungeons.')
        if LFG.peopleLookingForGroupsDisplay == 0 then
            GameTooltip:AddLine('No players are looking for groups at the moment.')
        elseif LFG.peopleLookingForGroupsDisplay == 1 then
            GameTooltip:AddLine(LFG.peopleLookingForGroupsDisplay .. ' player is looking for groups at the moment.')
        else
            GameTooltip:AddLine(LFG.peopleLookingForGroupsDisplay .. ' players are looking for groups at the moment.')
        end
        GameTooltip:Show()
    end
end

function queueForFromButton(bCode)

    local codeEx = StringSplit(bCode, '_')
    local qCode = codeEx[2]

    if _G['Dungeon_' .. qCode .. '_CheckButton']:IsEnabled() == 0 then
        return false
    end

    for code, data in next, LFG.availableDungeons do
        if code == qCode and not LFG.findingGroup then
            _G['Dungeon_' .. data.code .. '_CheckButton']:SetChecked(not _G['Dungeon_' .. data.code .. '_CheckButton']:GetChecked())
            queueFor(bCode, _G['Dungeon_' .. data.code .. '_CheckButton']:GetChecked())
        end
    end
end

function queueFor(name, status)

    lfdebug('queue for call ' .. name)

    local dungeonCode = ''
    local dung = StringSplit(name, '_')
    dungeonCode = dung[2]
    for dungeon, data in next, LFG.dungeons do
        if tonumber(dungeonCode) then
            dungeonCode = tonumber(dungeonCode)
        end
        if dungeonCode == data.code then
            if status then
                LFG.dungeons[dungeon].queued = true
            else
                LFG.dungeons[dungeon].queued = false
            end
        end
    end

    local queues = 0
    for _, data in next, LFG.dungeons do
        if data.queued then
            queues = queues + 1
        end
    end

    lfdebug(queues .. ' queues in queuefor')

    LFG.inGroup = GetNumRaidMembers() == 0 and GetNumPartyMembers() > 0

    lfdebug('queues: ' .. queues)
    lfdebug(LFG.inGroup)

    if LFG.inGroup then
        if queues == 1 then
            LFG.LFMDungeonCode = dungeonCode
            LFG.disableDungeonCheckButtons(dungeonCode)
        end
    else
        if queues < LFG.maxDungeonsInQueue then
            --LFG.enableDungeonCheckButtons()
        else
            for _, frame in next, LFG.availableDungeons do
                local dungeonName = LFG.dungeonNameFromCode(frame.code)
                lfdebug('dungeonName in queuefor = ' .. dungeonName)
                lfdebug('frame.code in queuefor = ' .. frame.code)
                lfdebug('frame.background in queuefor = ' .. frame.background)
                if not LFG.dungeons[dungeonName].queued then
                    _G["Dungeon_" .. frame.code .. '_CheckButton']:Disable()
                    _G['Dungeon_' .. frame.code .. 'Text']:SetText(COLOR_DISABLED .. dungeonName)
                    _G['Dungeon_' .. frame.code .. 'Levels']:SetText(COLOR_DISABLED .. '(' .. frame.minLevel .. ' - ' .. frame.maxLevel .. ')')

                    local q = 'dungeons'

                    LFG.addOnEnterTooltip(_G['Dungeon_' .. frame.code .. '_Button'], 'Queueing for ' .. dungeonName .. ' is unavailable', 'Maximum allowed queued ' .. q .. ' at a time is ' .. LFG.maxDungeonsInQueue .. '.')
                end
            end
        end
    end
    DungeonListFrame_Update(true)
    LFG.fixMainButton()
end

function findMore()

    --LFGsetRole('tank', true, true)

    -- find queueing dungeon
    local qDungeon = ''
    for _, frame in next, LFG.availableDungeons do
        if _G["Dungeon_" .. frame.code .. '_CheckButton']:GetChecked() then
            qDungeon = frame.code
        end
    end

    LFG.LFMDungeonCode = qDungeon

    local tankCheck = _G['RoleTank']
    local healerCheck = _G['RoleHealer']
    local damageCheck = _G['RoleDamage']

    if tankCheck:GetChecked() then
        LFGsetRole('tank', true, true)
    elseif healerCheck:GetChecked() then
        LFGsetRole('healer', true, true)
    elseif damageCheck:GetChecked() then
        LFGsetRole('damage', true, true)
    end

    SendAddonMessage(LFG_ADDON_CHANNEL, "roleCheck:" .. qDungeon, "PARTY")

    LFG.fixMainButton()

    -- disable the button disable spam clicking it
    _G['findMoreButton']:Disable()

    BrowseDungeonListFrame_Update()
end

function joinQueue(roleID, name)

    lfdebug('join queue call ' .. name)
    lfdebug('join queue call role ' .. roleID)

    local nameEx = StringSplit(name, '_')
    local mCode = nameEx[2]

    --leaveQueue('from join queue')

    if _G['Dungeon_' .. mCode .. '_CheckButton'] ~= nil then
        _G['Dungeon_' .. mCode .. '_CheckButton']:SetChecked(true)
    end

    queueFor(name, true)

    findGroup()
end

function findGroup()

    LFG.resetGroup()

    _G['RoleTank']:Disable()
    _G['RoleHealer']:Disable()
    _G['RoleDamage']:Disable()

    PlaySound('PvpEnterQueue')

    local roleText = ''
    if string.find(LFG_ROLE, 'tank', 1, true) then
        roleText = roleText .. COLOR_TANK .. 'Tank'
    end
    if string.find(LFG_ROLE, 'healer', 1, true) then
        local orText = ''
        if roleText ~= '' then
            orText = COLOR_WHITE .. ', '
        end
        roleText = roleText .. orText .. COLOR_HEALER .. 'Healer'
    end
    if string.find(LFG_ROLE, 'damage', 1, true) then
        local orText = ''
        if roleText ~= '' then
            orText = COLOR_WHITE .. ', '
        end
        roleText = roleText .. orText .. COLOR_DAMAGE .. 'Damage'
    end

    local dungeonsText = ''
    for dungeon, data in next, LFG.dungeons do
        if data.queued then
            lfdebug('in find group queued for : ' .. dungeon)
            dungeonsText = dungeonsText .. dungeon .. ', '
            --lfg_text = 'LFG:' .. data.code .. ':' .. LFG_ROLE .. ' ' .. lfg_text
        end
    end

    dungeonsText = string.sub(dungeonsText, 1, string.len(dungeonsText) - 2)
    lfprint('You are in the queue for |cff69ccf0' .. dungeonsText .. COLOR_WHITE .. ' as: ' .. roleText)

    LFG.findingGroup = true
    LFGQueue:Show()
    LFGMinimapAnimation:Show()

    LFG.disableDungeonCheckButtons()
    LFG.oneGroupFull = false
    LFG.queueStartTime = time()

    LFG.fixMainButton()

    BrowseDungeonListFrame_Update()
end

function leaveQueue(callData)

    if callData then
        lfdebug('-------- leaveQueue(' .. callData .. ')')
    else
        lfdebug('-------- leaveQueue(no-callData)')
    end
    lfdebug('_G[LFGGroupReady]:Hide()')
    _G['LFGGroupReady']:Hide()
    _G["LFGDungeonStatus"]:Hide()
    _G['LFGRoleCheck']:Hide()

    LFGGroupReadyFrameCloser:Hide()
    LFGGroupReadyFrameCloser.response = ''

    -- Clear CR election state
    LFG.crLeader = false
    LFG.crCandidates = {}
    LFG.crElectionTime = {}

    LFGQueue:Hide()
    LFGRoleCheck:Hide()
    lfdebug('LFGRoleCheck:Hide() in leaveQueue')

    LFG.hidePartyRoleIcons()
    LFG.hideMyRoleIcon()

    local dungeonsText = ''

    for dungeon, data in next, LFG.dungeons do
        if data.queued then
            if callData ~= 'from join queue' then
                if _G["Dungeon_" .. data.code .. '_CheckButton'] then
                    _G["Dungeon_" .. data.code .. '_CheckButton']:SetChecked(false)
                end
                LFG.dungeons[dungeon].queued = false
            end
            dungeonsText = dungeonsText .. dungeon .. ', '
        end
    end

    dungeonsText = string.sub(dungeonsText, 1, string.len(dungeonsText) - 2)
    if dungeonsText == '' then
        dungeonsText = LFG.dungeonNameFromCode(LFG.LFMDungeonCode)
    end
    if LFG.findingGroup or LFG.findingMore then
        if LFG.inGroup then
            if LFG.isLeader then
                SendAddonMessage(LFG_ADDON_CHANNEL, "leaveQueue:now", "PARTY")
            end
            lfprint('Your group has left the queue for |cff69ccf0' .. dungeonsText .. COLOR_WHITE .. '.')
        else
            if callData ~= 'from join queue' then
                lfprint('You have left the queue for |cff69ccf0' .. dungeonsText .. COLOR_WHITE .. '.')
            end
        end

        LFG.sendCancelMeMessage()
        LFG.findingGroup = false
        LFG.findingMore = false
    end

    LFG.enableDungeonCheckButtons()

    LFG.GetPossibleRoles()
    --LFGsetRole(LFG_ROLE)

    if LFG.LFMDungeonCode ~= '' then
        if _G["Dungeon_" .. LFG.LFMDungeonCode .. '_CheckButton'] then
            _G["Dungeon_" .. LFG.LFMDungeonCode .. '_CheckButton']:SetChecked(true)
            local lqName = LFG.dungeonNameFromCode(LFG.LFMDungeonCode)
            if LFG.dungeons[lqName] then LFG.dungeons[lqName].queued = true end
        end
    end

    local tankCheck = _G['RoleTank']
    local healerCheck = _G['RoleHealer']
    local damageCheck = _G['RoleDamage']

    DungeonListFrame_Update()
    BrowseDungeonListFrame_Update()
end

function LFGObjectives.objectiveComplete(bossName, dontSendToAll)
    local code = ''
    local objectivesString = ''
    for index, _ in next, LFG.objectivesFrames do
        if LFG.objectivesFrames[index].name == bossName then
            if not LFG.objectivesFrames[index].completed then
                LFG.objectivesFrames[index].completed = true

                LFGObjectives.objectivesComplete = LFGObjectives.objectivesComplete + 1

                _G["LFGObjective" .. index .. 'ObjectiveComplete']:Show()
                _G["LFGObjective" .. index .. 'ObjectivePending']:Hide()
                -- _G["LFGObjective" .. index .. 'Objective']:SetText(COLOR_WHITE .. '1/1 ' .. bossName .. ' defeated')
                _G["LFGObjective" .. index .. 'Objective']:SetText(COLOR_WHITE .. '' .. bossName .. '')

                LFGObjectives.lastObjective = index
                LFGObjectives:Show()
                code = LFG.objectivesFrames[index].code

            else
            end
        end
        if LFG.objectivesFrames[index].completed then
            objectivesString = objectivesString .. '1-'
        else
            objectivesString = objectivesString .. '0-'
        end
    end

    if code ~= '' then
        if not dontSendToAll then
            lfdebug("send " .. "objectives:" .. code .. ":" .. objectivesString)
            SendAddonMessage(LFG_ADDON_CHANNEL, "objectives:" .. code .. ":" .. objectivesString, "PARTY")
        end

        --dungeon complete ?
        local dungeonName, iconCode = LFG.dungeonNameFromCode(code)
        if LFGObjectives.objectivesComplete == LFG.tableSize(LFG.objectivesFrames) or
                (code == 'brdarena' and LFGObjectives.objectivesComplete == 1) then
            _G['LFGDungeonCompleteIcon']:SetTexture('Interface\\addons\\LFG\\images\\icon\\lfgicon-' .. iconCode)
            _G['LFGDungeonCompleteDungeonName']:SetText(dungeonName)
            LFGDungeonComplete.dungeonInProgress = false
            LFGDungeonComplete:Show()
            LFGObjectives.closedByUser = false
        else
            LFGDungeonComplete.dungeonInProgress = true
        end
    end
end

function toggleDungeonStatus_OnClick()
    LFGObjectives.collapsed = not LFGObjectives.collapsed
    if LFGObjectives.collapsed then
        _G["LFGDungeonStatusCollapseButton"]:Hide()
        _G["LFGDungeonStatusExpandButton"]:Show()
    else
        _G["LFGDungeonStatusCollapseButton"]:Show()
        _G["LFGDungeonStatusExpandButton"]:Hide()
    end
    for index, _ in next, LFG.objectivesFrames do
        if LFGObjectives.collapsed then
            _G["LFGObjective" .. index]:Hide()
        else
            _G["LFGObjective" .. index]:Show()
        end
    end
end

function lfg_switch_tab(t)
    LFG.tab = t
    PlaySound("igCharacterInfoTab");
    if t == 1 then
        _G['LFGBrowse']:Hide()
        _G['LFGMain']:Show()
    elseif t == 2 then
        _G['LFGMain']:Hide()
        _G['LFGBrowse']:Show()
    end
end

-- slash commands
SLASH_LFG1 = "/lfgaddon"
SLASH_LFG2 = "/lfg"
SlashCmdList["LFG"] = function(cmd)
    if cmd then
        if string.sub(cmd, 1, 4) == 'spam' then
            LFG_CONFIG['spamChat'] = not LFG_CONFIG['spamChat']
            if LFG_CONFIG['spamChat'] then
                lfnotice('Groups formed spam is on')
            else
                lfnotice('Groups formed spam is off')
            end
        end
        if string.sub(cmd, 1, 3) == 'who' then
            if me ~= 'Bennylava' then
                return false
            end
            if LFG.channelIndex == 0 then
                lfprint('LFG.channelIndex = 0, please try again in 10 seconds')
                return false
            end
            LFGWhoCounter:Show()
            SendChatMessage('whoLFG:' .. addonVer, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, GetChannelName(LFG.channel))
        end
        if string.sub(cmd, 1, 17) == 'resetformedgroups' then
            LFG.resetFormedGroups()
            lfprint('Formed groups history reset.')
        end
        if string.sub(cmd, 1, 12) == 'formedgroups' then
            lfprint('Listing formed groups history')
            local totalGroups = 0
            for code, number in next, LFG_FORMED_GROUPS do
                if number ~= 0 then
                    totalGroups = totalGroups + number
                    lfprint(number .. ' - ' .. LFG.dungeonNameFromCode(code))
                end
            end
            if totalGroups == 0 then
                lfprint('There are no recorded formed groups.')
            else
                lfprint('There are ' .. totalGroups .. ' recorded formed groups.')
            end
        end
        if string.sub(cmd, 1, 5) == 'debug' then
            LFG_CONFIG['debug'] = not LFG_CONFIG['debug']
            if LFG_CONFIG['debug'] then
                lfprint('debug enabled')
                _G['LFGTitleTime']:Show()
            else
                lfprint('debug disabled')
                _G['LFGTitleTime']:Hide()
            end
        end
        if string.sub(cmd, 1, 9) == 'advertise' then
            LFG.sendAdvertisement("PARTY")
        end
        if string.sub(cmd, 1, 8) == 'sayguild' then
            LFG.sendAdvertisement("GUILD")
        end
        if string.sub(cmd, 1, 6) == 'groups' then
            lfg_switch_tab(3)
            LFG_Toggle()
        end
        if string.sub(cmd, 1, 11) == 'cancelgroup' then
            LFG.Grp_DeleteGroup()
        end
    end
end

function LFG.sendAdvertisement(chan)
    SendChatMessage('I am using Looking For Group - LFG Addon for Project Epoch v' .. addonVer, chan, DEFAULT_CHAT_FRAME.editBox.languageID)
    SendChatMessage('Get it at: https://github.com/thezephyrsong/LFG', chan, DEFAULT_CHAT_FRAME.editBox.languageID)
end

function LFG.removeChannelFromWindows()
    if LFG_CONFIG and LFG_CONFIG['debug'] then
        return false
    end
    if me == 'Bennylava' then
        return false
    end

    if LFG.channelIndex == 1 then
        lfdebug('Not removing LFG from windows - channel conflict detected')
        return false
    end

    for windowIndex = 1, 9 do
        local channels = { GetChatWindowChannels(windowIndex) }
        for i = 1, #channels, 2 do
            local channelName = channels[i]
            local channelIndex = channels[i + 1]

            if channelName == LFG.channel and channelIndex == LFG.channelIndex then
                local chatFrame = _G["ChatFrame" .. windowIndex]
                if chatFrame then
                    ChatFrame_RemoveChannel(chatFrame, LFG.channel)
                    lfdebug('LFG channel removed from window ' .. windowIndex)
                end
            end
        end
    end
end

function LFG.incDungeonssSpamRole(dungeon, role, nrInc)

    if not nrInc then
        nrInc = 1
    end

    if not role then
        role = LFG_ROLE
    end

    if not LFG.dungeonsSpam[dungeon] then
        lfdebug('error in incDugeon, ' .. dungeon .. ' not init')
        return false
    end

    if role == 'tank' then
        LFG.dungeonsSpam[dungeon].tank = LFG.dungeonsSpam[dungeon].tank + nrInc
    end
    if role == 'healer' then
        LFG.dungeonsSpam[dungeon].healer = LFG.dungeonsSpam[dungeon].healer + nrInc
    end
    if role == 'damage' then
        LFG.dungeonsSpam[dungeon].damage = LFG.dungeonsSpam[dungeon].damage + nrInc
    end
end

function LFG.updateDungeonsSpamDisplay(code, lfm, numLFM)

    if not LFG.dungeonsSpam[code] then
        lfdebug('error in updateDungeons, ' .. code .. ' not init')
        return false
    end

    if not LFG.dungeonsSpamDisplay[code] then
        lfdebug('error in updateDungeons, ' .. code .. ' not init, display')
        return false
    end

    if LFG.dungeonsSpam[code].tank ~= 0 then
        LFG.dungeonsSpamDisplay[code].tank = LFG.dungeonsSpam[code].tank
    end

    if LFG.dungeonsSpam[code].healer ~= 0 then
        LFG.dungeonsSpamDisplay[code].healer = LFG.dungeonsSpam[code].healer
    end

    if LFG.dungeonsSpam[code].damage ~= 0 then
        LFG.dungeonsSpamDisplay[code].damage = LFG.dungeonsSpam[code].damage
    end

    if lfm then
        if LFG.dungeonsSpamDisplayLFM[code] == 0 then
            LFG.dungeonsSpamDisplayLFM[code] = numLFM
        else
            if numLFM > LFG.dungeonsSpamDisplayLFM[code] then
                LFG.dungeonsSpamDisplayLFM[code] = numLFM
            end
        end
    end

end

-- dungeons

LFG.dungeons = {}

LFG.allDungeons = {
    ['Ragefire Chasm'] = { minLevel = 13, maxLevel = 18, code = 'rfc', queued = false, canQueue = true, background = 'ragefirechasm', myRole = '' },
    ['Wailing Caverns'] = { minLevel = 17, maxLevel = 24, code = 'wc', queued = false, canQueue = true, background = 'wailingcaverns', myRole = '' },
    ['The Deadmines'] = { minLevel = 17, maxLevel = 24, code = 'dm', queued = false, canQueue = true, background = 'deadmines', myRole = '' },
    ['Shadowfang Keep'] = { minLevel = 22, maxLevel = 30, code = 'sfk', queued = false, canQueue = true, background = 'shadowfangkeep', myRole = '' },
    ['The Stockade'] = { minLevel = 22, maxLevel = 30, code = 'stocks', queued = false, canQueue = true, background = 'stormwindstockades', myRole = '' },
    ['Blackfathom Deeps'] = { minLevel = 23, maxLevel = 32, code = 'bfd', queued = false, canQueue = true, background = 'blackfathomdeeps', myRole = '' },
    ['Scarlet Monastery Graveyard'] = { minLevel = 28, maxLevel = 36, code = 'smgy', queued = false, canQueue = true, background = 'scarletmonastery', myRole = '' },
    ['Scarlet Monastery Library'] = { minLevel = 32, maxLevel = 39, code = 'smlib', queued = false, canQueue = true, background = 'scarletmonastery', myRole = '' },
    ['Gnomeregan'] = { minLevel = 29, maxLevel = 38, code = 'gnomer', queued = false, canQueue = true, background = 'gnomeregan', myRole = '' },
    ['Razorfen Kraul'] = { minLevel = 29, maxLevel = 38, code = 'rfk', queued = false, canQueue = true, background = 'razorfenkraul', myRole = '' },
    ['Scarlet Monastery Armory'] = { minLevel = 34, maxLevel = 41, code = 'smarmory', queued = false, canQueue = true, background = 'scarletmonastery', myRole = '' },
    ['Scarlet Monastery Cathedral'] = { minLevel = 37, maxLevel = 45, code = 'smcath', queued = false, canQueue = true, background = 'scarletmonastery', myRole = '' },
    ['Razorfen Downs'] = { minLevel = 36, maxLevel = 46, code = 'rfd', queued = false, canQueue = true, background = 'razorfendowns', myRole = '' },
    ['Glittermurk Mines'] = { minLevel = 39, maxLevel = 44, code = 'ggm', queued = false, canQueue = true, background = 'tcg', myRole = '' }, -- Glittermurk
    ['Uldaman'] = { minLevel = 40, maxLevel = 51, code = 'ulda', queued = false, canQueue = true, background = 'uldaman', myRole = '' },
    ['Zul\'Farrak'] = { minLevel = 44, maxLevel = 54, code = 'zf', queued = false, canQueue = true, background = 'zulfarak', myRole = '' },
    ['Maraudon Orange'] = { minLevel = 47, maxLevel = 55, code = 'maraorange', queued = false, canQueue = true, background = 'maraudon', myRole = '' },
    ['Maraudon Purple'] = { minLevel = 45, maxLevel = 55, code = 'marapurple', queued = false, canQueue = true, background = 'maraudon', myRole = '' },
    ['Maraudon Princess'] = { minLevel = 47, maxLevel = 55, code = 'maraprincess', queued = false, canQueue = true, background = 'maraudon', myRole = '' },
    ['Temple of Atal\'Hakkar'] = { minLevel = 50, maxLevel = 60, code = 'st', queued = false, canQueue = true, background = 'sunkentemple', myRole = '' },
    ['Blackrock Depths'] = { minLevel = 52, maxLevel = 60, code = 'brd', queued = false, canQueue = true, background = 'blackrockdepths', myRole = '' },
    ['Blackrock Depths Arena'] = { minLevel = 52, maxLevel = 60, code = 'brdarena', queued = false, canQueue = true, background = 'blackrockdepths', myRole = '' },
    ['Blackrock Depths Emperor'] = { minLevel = 54, maxLevel = 60, code = 'brdemp', queued = false, canQueue = true, background = 'blackrockdepths', myRole = '' },
    ['Lower Blackrock Spire'] = { minLevel = 55, maxLevel = 60, code = 'lbrs', queued = false, canQueue = true, background = 'blackrockspire', myRole = '' },
    ['Baradin Hold'] = { minLevel = 57, maxLevel = 60, code = 'bh', queued = false, canQueue = true, background = 'kc', myRole = '' }, --Baradin Hold
    -- ['Stonetalon Peaks'] = { minLevel = 57, maxLevel = 60, code = 'stp', queued = false, canQueue = true, background = 'hfq', myRole = '' }, --Stonetalon Peaks
    ['Scholomance'] = { minLevel = 58, maxLevel = 60, code = 'scholo', queued = false, canQueue = true, background = 'scholomance', myRole = '' },
    ['Stratholme: Undead District'] = { minLevel = 58, maxLevel = 60, code = 'stratud', queued = false, canQueue = true, background = 'stratholme', myRole = '' },
    ['Stratholme: Scarlet Bastion'] = { minLevel = 58, maxLevel = 60, code = 'stratlive', queued = false, canQueue = true, background = 'stratholme', myRole = '' },
    ['Upper Blackrock Spire'] = { minLevel = 58, maxLevel = 60, code = 'ubrs', queued = false, canQueue = true, background = 'blackrockspire', myRole = '' },

}

LFG.eliteEncounters = {
    ['Jintha\'Alor'] = { minLevel = 45, maxLevel = 60, code = 'ja', queued = false, canQueue = true, background = 'jinthaalor', myRole = '' },
    ['Felstone Fortress'] = { minLevel = 50, maxLevel = 60, code = 'ff', queued = false, canQueue = true, background = 'felstonefort', myRole = '' },
    ['Silithus Dailies'] = { minLevel = 60, maxLevel = 60, code = 'silithusd', queued = false, canQueue = true, background = 'silithusdailies', myRole = '' },
    ['Arena of Blood'] = { minLevel = 38, maxLevel = 45, code = 'aob', queued = false, canQueue = true, background = 'arenaofblood', myRole = '' },
    ['Stonewatch Keep'] = { minLevel = 20, maxLevel = 30, code = 'swk', queued = false, canQueue = true, background = 'stonewatchkeep', myRole = '' },
    ['Mosh\'ogg Ogres'] = { minLevel = 30, maxLevel = 40, code = 'moshogg', queued = false, canQueue = true, background = 'moshoggogres', myRole = '' },
    ['Durnholde Keep'] = { minLevel = 35, maxLevel = 45, code = 'durnholde', queued = false, canQueue = true, background = 'durnholdekeep', myRole = '' },
    ['Stromgarde Keep'] = { minLevel = 35, maxLevel = 45, code = 'stromgarde', queued = false, canQueue = true, background = 'stromgardekeep', myRole = '' },
    ['Lake Mennar'] = { minLevel = 48, maxLevel = 56, code = 'lmennar', queued = false, canQueue = true, background = 'lakemennar', myRole = '' },
}

LFG.bosses = {
    ['rfc'] = {
        'Oggleflint',
        'Taragaman the Hungerer',
        'Jergosh the Invoker',
        'Bazzalan'
    },
    ['wc'] = {
        'Lord Cobrahn',
        'Lady Anacondra',
        'Kresh',
        'Lord Pythas',
        'Skum',
        'Nyx',
        'Lord Serpentis',
        'Verdan the Everliving',
        'Mutanus the Devourer'
    },
    ['dm'] = {
        'Rhahk\'zor',
        'Sneed',
        'Gilnid',
        'Mr. Smite',
        'Cookie',
        'Captain Greenskin',
        'Edwin VanCleef'
    },
    ['sfk'] = {
        'Rethilgore',
        'Razorclaw the Butcher',
        'Baron Silverlaine',
        'Commander Springvale',
        'Odo the Blindwatcher',
        'Steward Graves',
        'Fenrus the Devourer',
        'Wolf Master Nandos',
        'Archmage Arugal'
    },
    ['bfd'] = {
        'Ghamoo-ra',
        'Lady Sarevess',
        'Gelihast',
        'Lorgus Jett',
        'Baron Aquanis',
        'Twilight Lord Kelris',
        'Old Serra\'kis',
        'Aku\'mai'
    },
    ['stocks'] = {
        'Targorr the Dread',
        'Kam Deepfury',
        'Hamhock',
        'Bazil Thredd',
        'Dextren Ward'
    },
    ['gnomer'] = {
        'Grubbis',
        'Viscous Fallout',
        'Electrocutioner 6000',
        'Crowd Pummeler 9-60',
        'Mekgineer Thermaplugg'
    },
    ['rfk'] = {
        'Roogug',
        'Aggem Thorncurse',
        'Death Speaker Jargba',
        'Overlord Ramtusk',
        'Agathelos the Raging',
        'Charlga Razorflank'
    },
    ['smgy'] = {
        'Interrogator Vishas',
        'Bloodmage Thalnos'
    },
    ['smarmory'] = {
        'Herod'
    },
    ['smcath'] = {
        'High Inquisitor Fairbanks',
        'Scarlet Commander Mograine',
        'High Inquisitor Whitemane'
    },
    ['smlib'] = {
        'Houndmaster Loksey',
        'Arcanist Doan'
    },
    ['rfd'] = {
        'Tuten\'kash',
        'Mordresh Fire Eye',
        'Glutton',
        'Plaguemaw the Rotting',
        'Amnennar the Coldbringer'
    },
    ['ggm'] = { -- Glittermurk
        'Supervisor Grimgash',
        'Foreman Sprocket',
        'Krakken',
        'Primscale',
        'Murklurk',
        'Gnash'
    },
    ['ulda'] = {
        'Revelosh',
        'The Lost Dwarves',
        'Ironaya',
        'Obsidian Sentinel',
        'Ancient Stone Keeper',
        'Galgann Firehammer',
        'Grimlok',
        'Sentinel of Archaedas'
    },
    ['zf'] = {
        'Antu\'sul',
        'Theka the Martyr',
        'Witch Doctor Zum\'rah',
        'Sandfury Executioner',
        'Nekrum Gutchewer',
        'Shadowpriest Sezz\'ziz',
        'Sergeant Bly',
        'Hydromancer Velratha',
        'Ruuzlu',
        'Chief Ukorz Sandscalp'
    },
    ['maraorange'] = {
        'Noxxion',
        'Razorlash'
    },
    ['marapurple'] = {
        'Lord Vyletongue',
        'Celebras the Cursed'
    },
    ['maraprincess'] = {
        'Tinkerer Gizlock',
        'Landslide',
        'Rotgrip',
        'Princess Theradras'
    },
    ['st'] = {
        'Gasher',
        'Atal\'alarion',
        'Dreamscythe',
        'Weaver',
        'Jammal\'an the Prophet',
        'Ogom the Wretched',
        'Morphaz',
        'Hazzas',
        '???',
        'Shade of Eranikus'
    },
    ['brd'] = {
        'Lord Roccor',
        'Bael\'Gar',
        'Houndmaster Grebmar',
        'High Interrogator Gerstahn',
        'High Justice Grimstone',
        'Pyromancer Loregrain',
        'General Angerforge',
        'Verek',
        'Golem Lord Argelmach',
        'Ribbly Screwspigot',
        'Hurley Blackbreath',
        'Plugger Spazzring',
        'Phalanx',
        'Lord Incendius',
        'Fineous Darkvire',
        'Warder Stilgiss',
        'Watchman Doomgrip',
        'Ambassador Flamelash',
        'Magmus',
        'Emperor Dagran Thaurissan'
    },
    ['brdemp'] = {
        'General Angerforge',
        'Golem Lord Argelmach',
        'Emperor Dagran Thaurissan',
        'Magmus',
        'Ambassador Flamelash'
    },
    ['brdarena'] = {
        'Anub\'shiah-s', --summoned
        'Eviscerator-s', --summoned
        'Gorosh the Dervish-s', --summoned
        'Grizzle-s', --summoned
        'Hedrum the Creeper-s', --summoned
        'Ok\'thor the Breaker-s' --summoned
    },
    ['lbrs'] = {
        'Highlord Omokk',
        'Shadow Hunter Vosh\'gajin',
        'War Master Voone',
        'Mother Smolderweb',
        '???',
        'Quartermaster Zigris',
        'Halycon',
        'Gizrul the Slavener',
        'Overlord Wyrmthalak'
    },
    ['bh'] = { --Baradin Hold
        'Morrumus',
        'Millhouse Manastorm',
        'Astilos the Hollow',
        'Calypso',
        'Dak\'mal',
        'Glagut',
        'Nazrasash',
        'Pirate Lord Blackstone'
    },
    -- ['stp'] = { --Stonetalon Peaks
        -- '',
        -- '',
        -- '',
        -- '',
        -- ''
    -- },
    ['scholo'] = {
        'Kirtonos the Herald',
        'Jandice Barov',
        'Rattlegore',
        'Marduk Blackpool',
        'Vectus',
        'Ras Frostwhisper',
        'Instructor Malicia',
        '???',
        'Doctor Theolen Krastinov',
        'Lorekeeper Polkelt',
        'The Ravenian',
        'Lord Alexei Barov',
        'Lady Illucia Barov',
        'Darkmaster Gandling'
    },
    ['stratlive'] = {
        'Fras Siabi',
        'Hearthsinger Forresten',
        'The Unforgiven',
        'Postmaster Malown',
        'Timmy the Cruel',
        'Malor the Zealous',
        'Cannon Master Willey',
        'Crimson Hammersmith',
        'Archivist Galford',
        'Balnazzar'
    },
    ['stratud'] = {
        'Magistrate Barthilas',
        'Stonespine',
        'Nerub\'enkan',
        'Black Guard Swordsmith',
        'Maleki the Pallid',
        'Baroness Anastari',
        'Ramstein the Gorger',
        'Baron Rivendare'
    },
    ['ubrs'] = {
        'Pyroguard Emberseer',
        'Solakar Flamewreath',
        'Warchief Rend Blackhand',
        'Gyth',
        'The Beast',
        'General Drakkisath'
    },
    ['ja'] = {
        'Vile Priestess Hexx',
    },
    ['ff'] = {
        --'',
    },
    ['silithusd'] = {
        --'',
    },
    ['aob'] = {
        --'',
    },
    ['swk'] = {
        --'Tharil\'zun',
        --'Darkmaster Gandogar',
    },
    ['moshogg'] = {
        --'Kor\'gresh Coldrage',
    },
    ['durnholde'] = {
        --'Shuja Grimtotem',
        --'Drudge',
        --'Skullbreaker',
    },
    ['stromgarde'] = {
        --'Lord Falconcrest',
        --'Boulderfist Lord',
        --'Syndicate Assassin',
    },
    ['lmennar'] = {
        --'Azrathus',
    },
};

-- utils

function LFG.isEliteEncounter(dungeonCode)
    for _, data in next, LFG.eliteEncounters do
        if data.code == dungeonCode then
            return true
        end
    end
    return false
end

local CLASS_RUN_ELIGIBLE = {
    bh        = true,
    lbrs      = true,
    ubrs      = true,
    scholo    = true,
    stratud   = true,
    stratlive = true,
}
function LFG.classRunEligible(dungeonCode)
    return CLASS_RUN_ELIGIBLE[dungeonCode] == true
end

function LFG.classConflictsInGroup(dungeonCode, class)
    local g = LFG.group[dungeonCode]
    if not g then return false end
    local slots = { g.tank, g.healer, g.damage1, g.damage2, g.damage3 }
    for _, name in ipairs(slots) do
        if name and name ~= '' then
            local knownClass = LFG.playerClass(name)
            if knownClass == 'priest' and
               LFG.seenClasses[dungeonCode] and
               LFG.seenClasses[dungeonCode][name] then
                knownClass = LFG.seenClasses[dungeonCode][name].class or knownClass
            end
            if knownClass == class then return true end
        end
    end
    return false
end

function LFG.crElectLeader(dungeonCode)
    local candidates = {}
    if LFG.crCandidates[dungeonCode] then
        for name, _ in pairs(LFG.crCandidates[dungeonCode]) do
            table.insert(candidates, name)
        end
    end
    local selfIncluded = false
    for _, n in ipairs(candidates) do
        if n == me then selfIncluded = true break end
    end
    if not selfIncluded and LFG.classRun then
        table.insert(candidates, me)
    end
    if #candidates == 0 then return nil end
    table.sort(candidates)
    return candidates[1]
end

function LFG.crBecomeLeader(dungeonCode)
    if LFG.crLeader then return end
    LFG.crLeader = true
    LFG.LFMDungeonCode = dungeonCode
    if not LFG.group[dungeonCode] then
        LFG.group[dungeonCode] = { tank = '', healer = '', damage1 = '', damage2 = '', damage3 = '' }
    end
    if string.find(LFG_ROLE, 'tank', 1, true) then
        LFG.group[dungeonCode].tank = me
    elseif string.find(LFG_ROLE, 'healer', 1, true) then
        LFG.group[dungeonCode].healer = me
    elseif string.find(LFG_ROLE, 'damage', 1, true) then
        if LFG.group[dungeonCode].damage1 == '' then
            LFG.group[dungeonCode].damage1 = me
        end
    end
    LFG.crLastLFMTime = time()
    lfdebug('crBecomeLeader: elected for ' .. dungeonCode)
    lfprint('[LFG] Class Run: you have been elected leader for ' .. LFG.dungeonNameFromCode(dungeonCode) .. '. Forming group...')
    LFG.sendLFMStats(dungeonCode)
end

function LFG.crStepDown(dungeonCode, newLeaderName)
    if not LFG.crLeader then return end
    lfdebug('crStepDown: ' .. newLeaderName .. ' takes over for ' .. dungeonCode)
    lfprint('[LFG] Class Run: ' .. newLeaderName .. ' is now leading. Switching to applicant mode.')
    LFG.crLeader = false
    LFG.LFMDungeonCode = ''
    LFG.group[dungeonCode] = { tank = '', healer = '', damage1 = '', damage2 = '', damage3 = '' }
    if string.find(LFG_ROLE, 'tank', 1, true) then
        LFG.group[dungeonCode].tank = me
    end
end

function LFG.crCheckElection()
    if not LFG.classRun or LFG.inGroup or LFG.isLeader then return end
    for _, data in next, LFG.dungeons do
        if data.queued and LFG.classRunEligible(data.code) then
            local code = data.code
            local elected = LFG.crElectLeader(code)
            if elected == me then
                if not LFG.crElectionTime[code] then
                    LFG.crElectionTime[code] = time()
                    lfdebug('crCheckElection: starting election clock for ' .. code)
                end
                local waited = time() - LFG.crElectionTime[code]
                if waited >= LFG.CR_ELECTION_WAIT and not LFG.crLeader then
                    LFG.crBecomeLeader(code)
                end
            else
                LFG.crElectionTime[code] = nil
            end
            if LFG.crLeader and LFG.LFMDungeonCode == code then
                if LFG.crLastLFMTime and (time() - LFG.crLastLFMTime) > LFG.CR_LEADER_TIMEOUT then
                    lfdebug('crCheckElection: leader timeout, stepping down for re-election')
                    LFG.crLeader = false
                    LFG.crElectionTime[code] = nil
                    LFG.crCandidates[code] = nil
                end
            end
        end
    end
end

function LFGsetClassRun(checked)
    LFG.classRun = checked and true or false
    lfdebug('classRun = ' .. tostring(LFG.classRun))
end

function LFG.playerClass(name)
    if name == me then
        local _, unitClass = UnitClass('player')
        return string.lower(unitClass)
    end
    for i = 1, GetNumPartyMembers() do
        if UnitName('party' .. i) then
            if name == UnitName('party' .. i) then
                local _, unitClass = UnitClass('party' .. i)
                return string.lower(unitClass)
            end
        end
    end
    return 'priest'
end

function LFG.ver(ver)
    return (tonumber(string.sub(ver, 1, 1)) or 0) * 1000 +
            (tonumber(string.sub(ver, 3, 3)) or 0) * 100 +
            (tonumber(string.sub(ver, 5, 5)) or 0) * 10 +
            (tonumber(string.sub(ver, 7, 7)) or 0)
end

function LFG.ucFirst(a)
    return string.upper(string.sub(a, 1, 1)) .. string.lower(string.sub(a, 2, string.len(a)))
end

function StringSplit(str, delimiter)
    local result = {}
    local from = 1
    local delim_from, delim_to = string.find(str, delimiter, from)
    while delim_from do
        table.insert(result, string.sub(str, from, delim_from - 1))
        from = delim_to + 1
        delim_from, delim_to = string.find(str, delimiter, from)
    end
    table.insert(result, string.sub(str, from))
    return result
end

local channelMonitorFrame = CreateFrame("Frame")
channelMonitorFrame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
channelMonitorFrame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE_USER")
channelMonitorFrame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_CHANNEL_NOTICE" then
        if arg1 == "YOU_JOINED" and arg9 == LFG.channel then
            local channelIndex = arg8
            if channelIndex == 1 then
                -- Only fix if General channel is not in slot 1
                local generalIndex = GetChannelName("General")
                if generalIndex ~= 1 then
                    lfprint('LFG joined in channel 1! Auto-fixing...')
                    LFG.fixChannelConflict()
                else
                    lfdebug('LFG joined in slot 1 but General is also in slot 1, accepting this state')
                    LFG.channelIndex = channelIndex
                end
            else
                LFG.channelIndex = channelIndex
                lfdebug('LFG properly joined in channel: ' .. channelIndex)
            end
        end
    elseif event == "CHAT_MSG_CHANNEL_NOTICE_USER" then
        if LFG.channelIndex > 0 then
            local checkFrame = CreateFrame("Frame")
            checkFrame.elapsed = 0
            checkFrame:SetScript("OnUpdate", function(self, elapsed)
                self.elapsed = self.elapsed + elapsed
                if self.elapsed >= 0.5 then
                    local currentIndex = GetChannelName(LFG.channel)
                    if currentIndex == 1 and LFG.channelIndex ~= 1 then
                        -- Only fix if General channel is not in slot 1
                        local generalIndex = GetChannelName("General")
                        if generalIndex ~= 1 then
                            lfprint('Channel conflict detected! Fixing...')
                            LFG.fixChannelConflict()
                        else
                            lfdebug('LFG moved to slot 1 but General is also in slot 1, accepting this state')
                            LFG.channelIndex = currentIndex
                        end
                    end
                    self:SetScript("OnUpdate", nil)
                end
            end
        end
    end)

-- ============================================================
-- CUSTOM GROUPS SYSTEM v2  (tab 3)
-- Full port of LFT2 protocol into LFG.
--
-- BROWSE sub-tab:  listed groups (GN/GU/GD) + queue rows merged
-- QUEUE  sub-tab:  instance checklist + role selection + Find Group
--
-- Channel protocol (plain chat on LFG channel, prefix LFT|):
--   LFT|Q|<instCSV>|<roles>|<lvl>|<class>|<partyInfo>   queue ping
--   LFT|L|<name>                                          queue leave
--   LFT|GN|<json>                                         new group
--   LFT|GU|<json>                                         update group
--   LFT|GD|<id>                                           delete group
--
-- Whisper addon messages (SendAddonMessage prefix LFG_ADDON_CHANNEL):
--   OFFER|<inst>|<leader>|<role>   leader -> member
--   ACCEPT|<inst>|<role>           member -> leader
--   DECLINE|<inst>                 member -> leader
--   CANCEL|<inst>                  leader -> member (abort)
--   GS|<id>|<role>                 player -> leader (signup)
--   GS_OK|<id>                     leader -> player (accepted)
--   GS_DENY|<id>                   leader -> player (full)
-- ============================================================

-- ---- Timing constants ----
local GRP_QUEUE_BROADCAST  = 25    -- seconds between queue pings
local GRP_GROUP_BROADCAST  = 60    -- seconds between group heartbeats
local GRP_QUEUE_TTL        = 90    -- drop remote queue entry after N sec
local GRP_GROUP_TTL        = 180   -- drop remote group listing after N sec
local GRP_MATCH_SCAN       = 8     -- scan for match every N sec
local GRP_PRUNE_INTERVAL   = 30    -- prune stale entries every N sec
local GRP_CMSG_PREFIX      = "LFT|"

-- ---- Category filter labels ----
LFG.grp_categories = { "Dungeons", "Raids", "PvP", "Other" }

-- ---- Class role table (tank/healer/damage) ----
LFG.grp_classRoles = {
    ["DRUID"]     = { true,  true,  true  },
    ["HUNTER"]    = { false, false, true  },
    ["MAGE"]      = { false, false, true  },
    ["PALADIN"]   = { true,  true,  true  },
    ["PRIEST"]    = { false, true,  true  },
    ["ROGUE"]     = { false, false, true  },
    ["SHAMAN"]    = { true,  true,  true  },
    ["WARLOCK"]   = { false, false, true  },
    ["WARRIOR"]   = { true,  false, true  },
    ["DEATHKNIGHT"] = { true, false, true },
}

-- ---- State ----
LFG.grp_groups          = {}   -- [id] listed groups (browse)
LFG.grp_queueEntries    = {}   -- [name] remote queue entries
LFG.grp_queueCache      = {}   -- [name] synthesised browse rows for queued players
LFG.grp_listedGroup     = nil  -- our own posted group
LFG.grp_selectedGroup   = nil  -- selected row in browse list
LFG.grp_queueStatus     = nil  -- nil | "queued"
LFG.grp_pendingOffer    = nil  -- { instance, role, leader, match, time, acks }
LFG.grp_roleCheck       = {}   -- pending rolecheck responses [name]=-1/roleIdx
LFG.grp_selectedRoles   = { false, false, true }  -- tank, healer, damage
LFG.grp_selectedInst    = {}   -- [instCode] = true
LFG.grp_nextGroupId     = 1
LFG.grp_currentTab      = 1   -- 1=browse, 2=queue
LFG.grp_categoryFilter  = 1   -- dropdown selection
LFG.grp_searchText      = ""
LFG.grp_presets         = LFG_GRP_PRESETS or {}
LFG.grp_currentPreset   = nil
LFG.grp_ticker          = { lastQueue=0, lastGroup=0, lastScan=0, lastPrune=0 }

-- Scroll offsets
LFG.grp_browseOffset = 0
LFG.grp_queueOffset  = 0

-- Dynamic frame pools
LFG.grp_groupRows  = {}
LFG.grp_instRows   = {}

local GRP_GROUPS_SHOWN = 8
local GRP_INST_SHOWN   = 12
local GRP_ROW_H        = 31
local GRP_INST_H       = 21

-- ============================================================
-- JSON (identical to LFT2, self-contained)
-- ============================================================
local grp_json = {}

local function grp_jsonEncVal(v)
    local t = type(v)
    if t == "string" then
        local s = string.gsub(v, "\\", "\\\\")
        s = string.gsub(s, "\"", "\\\"")
        s = string.gsub(s, "\n", "\\n")
        s = string.gsub(s, "\r", "\\r")
        s = string.gsub(s, "\t", "\\t")
        return "\"" .. s .. "\""
    elseif t == "number"  then return tostring(v)
    elseif t == "boolean" then return v and "true" or "false"
    elseif t == "table" then
        local isArr, n = true, 0
        for k in pairs(v) do n=n+1; if type(k)~="number" then isArr=false; break end end
        if isArr and n > 0 then
            local p = {}
            for i = 1, n do p[i] = grp_jsonEncVal(v[i]) end
            return "[" .. table.concat(p, ",") .. "]"
        else
            local p = {}
            for k, val in pairs(v) do
                table.insert(p, "\"" .. tostring(k) .. "\":" .. grp_jsonEncVal(val))
            end
            return "{" .. table.concat(p, ",") .. "}"
        end
    end
    return "null"
end

function grp_json.encode(v) return grp_jsonEncVal(v) end

local grp_jsonDecVal
local function grp_skipWs(s, i)
    while i <= #s do
        local c = string.sub(s,i,i)
        if c~=" " and c~="\t" and c~="\n" and c~="\r" then break end
        i=i+1
    end
    return i
end
local function grp_decStr(s, i)
    local out, idx = "", i+1
    while idx <= #s do
        local c = string.sub(s,idx,idx)
        if c == "\\" then
            local nc = string.sub(s,idx+1,idx+1)
            out = out .. (nc=="n" and "\n" or nc=="r" and "\r" or nc=="t" and "\t" or nc)
            idx = idx+2
        elseif c == "\"" then return out, idx+1
        else out=out..c; idx=idx+1 end
    end
    return nil
end
local function grp_decNum(s, i)
    local j = i
    while j <= #s do
        local c = string.sub(s,j,j)
        if not (c=="-" or c=="+" or c=="." or c=="e" or c=="E" or (c>="0" and c<="9")) then break end
        j=j+1
    end
    return tonumber(string.sub(s,i,j-1)), j
end
local function grp_decArr(s, i)
    local out = {}; i = grp_skipWs(s, i+1)
    if string.sub(s,i,i) == "]" then return out, i+1 end
    while i <= #s do
        local v; v, i = grp_jsonDecVal(s, i)
        table.insert(out, v); i = grp_skipWs(s, i)
        local c = string.sub(s,i,i)
        if c == "," then i = grp_skipWs(s, i+1)
        elseif c == "]" then return out, i+1 else return nil end
    end
    return nil
end
local function grp_decObj(s, i)
    local out = {}; i = grp_skipWs(s, i+1)
    if string.sub(s,i,i) == "}" then return out, i+1 end
    while i <= #s do
        i = grp_skipWs(s, i)
        local key; key, i = grp_decStr(s, i)
        if not key then return nil end
        i = grp_skipWs(s, i)
        if string.sub(s,i,i) ~= ":" then return nil end
        i = grp_skipWs(s, i+1)
        local v; v, i = grp_jsonDecVal(s, i)
        local nk = tonumber(key); if nk then out[nk]=v else out[key]=v end
        i = grp_skipWs(s, i)
        local c = string.sub(s,i,i)
        if c == "," then i = grp_skipWs(s, i+1)
        elseif c == "}" then return out, i+1 else return nil end
    end
    return nil
end
grp_jsonDecVal = function(s, i)
    i = grp_skipWs(s, i or 1)
    local c = string.sub(s,i,i)
    if c=="\"" then return grp_decStr(s,i)
    elseif c=="{" then return grp_decObj(s,i)
    elseif c=="[" then return grp_decArr(s,i)
    elseif c=="t" then return true, i+4
    elseif c=="f" then return false, i+5
    elseif c=="n" then return nil, i+4
    else return grp_decNum(s,i) end
end
function grp_json.decode(s)
    if type(s)~="string" or s=="" then return nil end
    local ok, r = pcall(function() local v,_=grp_jsonDecVal(s,1); return v end)
    return ok and r or nil
end

-- ============================================================
-- Utility helpers
-- ============================================================
local function grp_explode(str, sep)
    if not str then return {} end
    local out, idx = {}, 1
    while true do
        local s, e = string.find(str, sep, idx, true)
        if not s then table.insert(out, string.sub(str, idx)); break end
        table.insert(out, string.sub(str, idx, s-1)); idx = e+1
    end
    return out
end

local function grp_trim(s)
    if not s then return "" end
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local function grp_isGroupUsingRoles(g)
    return g and g.limit and (g.limit[1]>0 or g.limit[2]>0 or g.limit[3]>0)
end

local function grp_inGroupOrRaid()
    return (GetNumPartyMembers() + GetNumRaidMembers()) > 0
end

local function grp_getPartyLeader()
    if GetNumRaidMembers() > 0 then
        for i = 1, MAX_RAID_MEMBERS do
            local name, rank = GetRaidRosterInfo(i)
            if name and rank == 2 then return name end
        end
    elseif GetNumPartyMembers() > 0 then
        if IsPartyLeader() then return UnitName("player") end
        for i = 1, 4 do
            if UnitIsPartyLeader("party"..i) then return UnitName("party"..i) end
        end
    end
    return UnitName("player")
end

local function grp_roleCode(idx)
    return idx==1 and "t" or idx==2 and "h" or idx==3 and "d" or ""
end
local function grp_roleLabel(code)
    return code=="t" and "Tank" or code=="h" and "Healer" or code=="d" and "Damage" or ""
end
local function grp_unescapePipes(s)
    if not s then return s end
    return (string.gsub(s, "||", "|"))
end

-- ============================================================
-- Channel send (using existing LFG channel infrastructure)
-- ============================================================
local function grp_CSend(payload)
    if LFG.channelIndex == 0 then return end
    local chanName = GetChannelName(LFG.channel)
    if not chanName or chanName == "" then return end
    -- Double any | so WoW colour codes don't eat them; receiver calls grp_unescapePipes
    local escaped = string.gsub(GRP_CMSG_PREFIX .. payload, "|", "||")
    SendChatMessage(escaped, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID, chanName)
end

local GRP_WHISPER_PREFIX = "GRP:"

local function grp_AddonSend(msg, where, target)
    SendAddonMessage(LFG_ADDON_CHANNEL, GRP_WHISPER_PREFIX .. msg, where, target)
end

local function grp_SendWhisper(msg, target)
    grp_AddonSend(msg, "WHISPER", target)
end

local function grp_SendRaid(msg)
    if grp_inGroupOrRaid() then
        -- Party/raid messages use GRP: prefix too (via grp_AddonSend)
        grp_AddonSend(msg, GetNumRaidMembers()>0 and "RAID" or "PARTY")
    end
end

-- ============================================================
-- Group-listing protocol
-- ============================================================
local function grp_findGroupByID(id)
    for i, g in ipairs(LFG.grp_groups) do
        if g.id == id then return g, i end
    end
    return nil
end

local function grp_broadcastMyGroup(eventCode)
    if not LFG.grp_listedGroup then return end
    local g = LFG.grp_listedGroup
    local blob = {
        id           = g.id,
        creator      = g.creator,
        class        = g.class,
        title        = g.title,
        description  = g.description,
        category     = g.category or 1,
        limit        = g.limit,
        numConfirmed = g.numConfirmed,
    }
    grp_CSend(eventCode .. "|" .. grp_json.encode(blob))
end

local function grp_handleRemoteGroup(eventCode, sender, payload)
    if sender == me then return end
    if eventCode == "GD" then
        local id = sender .. ":" .. tostring(tonumber(payload) or payload)
        local g, idx = grp_findGroupByID(id)
        if g and g.creator == sender then
            table.remove(LFG.grp_groups, idx)
            if LFG.grp_selectedGroup and LFG.grp_selectedGroup.id == id then
                LFG.grp_selectedGroup = nil
            end
            if LFG.tab == 3 then LFG.Grp_UpdateBrowse() end
        end
        return
    end
    local data = grp_json.decode(payload)
    if type(data) ~= "table" or not data.id then return end
    data.creator   = sender
    data.signups   = { {}, {}, {} }
    data._lastSeen = GetTime()
    if not data.numConfirmed then data.numConfirmed = {0,0,0} end
    if not data.limit        then data.limit        = {0,0,0} end
    data.id = sender .. ":" .. tostring(data.id)
    local existing, idx = grp_findGroupByID(data.id)
    if existing then LFG.grp_groups[idx] = data
    else table.insert(LFG.grp_groups, data) end
    if LFG.tab == 3 and LFG.grp_currentTab == 1 then
        LFG.Grp_UpdateBrowse()
    end
end

-- ============================================================
-- Queue protocol
-- ============================================================
local function grp_buildPartyInfo()
    local n = GetNumPartyMembers()
    if n == 0 then return "" end
    local out = {}
    local _, myClass = UnitClass("player")
    table.insert(out, (UnitName("player") or "?") .. "," .. (myClass or ""))
    for i = 1, n do
        local unit = "party"..i
        if UnitExists(unit) then
            local _, c = UnitClass(unit)
            table.insert(out, (UnitName(unit) or "?") .. "," .. (c or ""))
        end
    end
    return table.concat(out, "/")
end

local function grp_buildQueueBroadcast()
    local instStr, roleStr = "", ""
    for code in pairs(LFG.grp_selectedInst) do instStr = instStr .. code .. "," end
    if LFG.grp_selectedRoles[1] then roleStr = roleStr .. "t" end
    if LFG.grp_selectedRoles[2] then roleStr = roleStr .. "h" end
    if LFG.grp_selectedRoles[3] then roleStr = roleStr .. "d" end
    if instStr == "" or roleStr == "" then return nil end
    instStr = string.sub(instStr, 1, -2)
    local _, class = UnitClass("player")
    local lvl = UnitLevel("player") or 1
    return "Q|" .. instStr .. "|" .. roleStr .. "|" .. lvl .. "|" .. (class or "") .. "|" .. grp_buildPartyInfo()
end

local function grp_broadcastQueue()
    if LFG.grp_queueStatus ~= "queued" then return end
    local payload = grp_buildQueueBroadcast()
    if payload then grp_CSend(payload) end
end

local function grp_broadcastQueueLeave()
    grp_CSend("L|" .. (UnitName("player") or ""))
end

local function grp_pruneQueue()
    local now = GetTime()
    for name, entry in pairs(LFG.grp_queueEntries) do
        if (now - (entry.time or 0)) > GRP_QUEUE_TTL then
            LFG.grp_queueEntries[name] = nil
            LFG.grp_queueCache[name]   = nil
        end
    end
end

local function grp_pruneGroups()
    local now = GetTime()
    for i = #LFG.grp_groups, 1, -1 do
        local g = LFG.grp_groups[i]
        if g and g.creator and g.creator ~= me
           and g._lastSeen and (now - g._lastSeen) > GRP_GROUP_TTL then
            if LFG.grp_selectedGroup and LFG.grp_selectedGroup.id == g.id then
                LFG.grp_selectedGroup = nil
            end
            table.remove(LFG.grp_groups, i)
        end
    end
end

local function grp_handleRemoteQueue(sender, instCsv, roleStr, lvl, class, partyInfo)
    if sender == me then return end
    local entry = LFG.grp_queueEntries[sender] or {}
    entry.instances = {}
    for _, code in ipairs(grp_explode(instCsv, ",")) do
        if code ~= "" then entry.instances[code] = true end
    end
    entry.roles = roleStr or ""
    entry.level = tonumber(lvl) or 0
    entry.class = class or ""
    entry.time  = GetTime()
    entry.party = {}
    if partyInfo and partyInfo ~= "" then
        for _, member in ipairs(grp_explode(partyInfo, "/")) do
            local parts = grp_explode(member, ",")
            if parts[1] and parts[1] ~= "" then
                table.insert(entry.party, { name=parts[1], class=parts[2] or "" })
            end
        end
    end
    LFG.grp_queueEntries[sender] = entry
    -- mirror leader's queue to non-leader party members
    if GetNumPartyMembers() > 0 and not IsPartyLeader() then
        if grp_getPartyLeader() == sender then
            LFG.grp_queueStatus = "queued"
            for k in pairs(LFG.grp_selectedInst) do LFG.grp_selectedInst[k] = nil end
            for code in pairs(entry.instances) do LFG.grp_selectedInst[code] = true end
        end
    end
    if LFG.tab == 3 and LFG.grp_currentTab == 1 then LFG.Grp_UpdateBrowse() end
end

local function grp_handleRemoteQueueLeave(sender)
    LFG.grp_queueEntries[sender] = nil
    LFG.grp_queueCache[sender]   = nil
    if GetNumPartyMembers() > 0 and not IsPartyLeader() then
        if grp_getPartyLeader() == sender and LFG.grp_queueStatus == "queued" then
            LFG.grp_queueStatus = nil
        end
    end
    if LFG.tab == 3 and LFG.grp_currentTab == 1 then LFG.Grp_UpdateBrowse() end
end

-- ============================================================
-- Match-making
-- ============================================================
local function grp_findMatchForDungeon(code)
    local pool = { tanks={}, healers={}, damage={} }
    if LFG.grp_selectedInst[code] then
        if LFG.grp_selectedRoles[1] then table.insert(pool.tanks,   me) end
        if LFG.grp_selectedRoles[2] then table.insert(pool.healers, me) end
        if LFG.grp_selectedRoles[3] then table.insert(pool.damage,  me) end
    end
    for name, entry in pairs(LFG.grp_queueEntries) do
        if entry.instances and entry.instances[code] then
            if string.find(entry.roles,"t",1,true) then table.insert(pool.tanks,   name) end
            if string.find(entry.roles,"h",1,true) then table.insert(pool.healers, name) end
            if string.find(entry.roles,"d",1,true) then table.insert(pool.damage,  name) end
        end
    end
    if #pool.tanks==0 or #pool.healers==0 or #pool.damage<3 then return nil end
    local seen = {}
    local function pick(list)
        for _, n in ipairs(list) do
            if not seen[n] then seen[n]=true; return n end
        end
    end
    local t=pick(pool.tanks); local h=pick(pool.healers)
    local d1=pick(pool.damage); local d2=pick(pool.damage); local d3=pick(pool.damage)
    if not (t and h and d1 and d2 and d3) then return nil end
    return { tank=t, healer=h, damage={d1,d2,d3} }
end

local function grp_scanForMatch()
    if LFG.grp_queueStatus ~= "queued" then return end
    if grp_inGroupOrRaid() then return end
    if LFG.grp_pendingOffer then return end
    for code in pairs(LFG.grp_selectedInst) do
        local match = grp_findMatchForDungeon(code)
        if match then
            local myRole
            if match.tank == me then myRole = "t"
            elseif match.healer == me then myRole = "h"
            elseif match.damage[1]==me or match.damage[2]==me or match.damage[3]==me then myRole = "d"
            end
            if myRole then
                LFG.grp_pendingOffer = {
                    instance=code, role=myRole, leader=me,
                    match=match, time=GetTime(), acks={},
                }
                LFG.Grp_ShowReadyFrame(code, myRole)
                local payload = "OFFER|" .. code .. "|" .. me
                if match.tank   ~= me then grp_SendWhisper(payload.."|t", match.tank) end
                if match.healer ~= me then grp_SendWhisper(payload.."|h", match.healer) end
                for _, d in ipairs(match.damage) do
                    if d ~= me then grp_SendWhisper(payload.."|d", d) end
                end
                return
            end
        end
    end
end

-- ============================================================
-- Ready frame / offer handling
-- ============================================================
function LFG.Grp_ShowReadyFrame(instCode, role)
    local inst = LFG_GRP_INSTANCES_MAP and LFG_GRP_INSTANCES_MAP[instCode]
    local name = inst and inst.name or instCode
    local bg   = inst and inst.background or "dungeonwall"
    if _G["LFGGrpReadyInstance"] then
        _G["LFGGrpReadyInstance"]:SetText(name)
    end
    if _G["LFGGrpReadyBG"] then
        _G["LFGGrpReadyBG"]:SetTexture("Interface\\AddOns\\LFG\\images\\background\\ui-lfg-background-" .. bg)
    end
    if _G["LFGGrpReadyRoleTex"] then
        local roleName = grp_roleLabel(role)
        _G["LFGGrpReadyRoleTex"]:SetTexture("Interface\\AddOns\\LFG\\images\\" .. string.lower(roleName) .. "2")
    end
    if _G["LFGGrpReadyRoleText"] then
        _G["LFGGrpReadyRoleText"]:SetText(grp_roleLabel(role))
    end
    if _G["LFGGrpReadyFrame"] then _G["LFGGrpReadyFrame"]:Show() end
    PlaySoundFile("Interface\\AddOns\\LFG\\sound\\levelup2.ogg")
end

function LFG.Grp_ReadyClick(confirm)
    local pending = LFG.grp_pendingOffer
    if confirm then
        if pending then
            if _G["LFGGrpReadyStatusFrame"] then _G["LFGGrpReadyStatusFrame"]:Show() end
            if pending.leader == me then
                pending.acks[me] = pending.role
                LFG.Grp_MarkSlotReady(pending.role)
            else
                grp_SendWhisper("ACCEPT|" .. pending.instance .. "|" .. pending.role, pending.leader)
            end
        end
    else
        if pending then
            if pending.leader == me then
                local match = pending.match
                if match then
                    if match.tank   ~= me then grp_SendWhisper("CANCEL|"..pending.instance, match.tank)   end
                    if match.healer ~= me then grp_SendWhisper("CANCEL|"..pending.instance, match.healer) end
                    for _, d in ipairs(match.damage) do
                        if d ~= me then grp_SendWhisper("CANCEL|"..pending.instance, d) end
                    end
                end
            else
                grp_SendWhisper("DECLINE|"..pending.instance, pending.leader)
            end
        end
        LFG.grp_pendingOffer = nil
        LFG.grp_queueStatus  = nil
        grp_broadcastQueueLeave()
        lfprint(COLOR_YELLOW .. "Group offer declined.")
        LFG.Grp_UpdateQueue()
    end
    if _G["LFGGrpReadyFrame"] then _G["LFGGrpReadyFrame"]:Hide() end
end

function LFG.Grp_MarkSlotReady(role)
    local checks = { t="LFGGrpStatusTank", h="LFGGrpStatusHealer" }
    if checks[role] and _G[checks[role]] then
        _G[checks[role]]:SetTexture("Interface\\AddOns\\LFG\\images\\readycheck-ready")
        return
    end
    if role == "d" then
        for i = 1, 3 do
            local tex = _G["LFGGrpStatusDamage"..i]
            if tex and tex:GetTexture() and string.find(tex:GetTexture(), "waiting", 1, true) then
                tex:SetTexture("Interface\\AddOns\\LFG\\images\\readycheck-ready")
                return
            end
        end
    end
end

local function grp_checkOfferComplete()
    local pending = LFG.grp_pendingOffer
    if not pending or not pending.acks or not pending.match then return end
    local match = pending.match
    if not match.tank or not match.healer or not match.damage then return end
    local needed = { match.tank, match.healer, match.damage[1], match.damage[2], match.damage[3] }
    for _, n in ipairs(needed) do
        if not pending.acks[n] then return end
    end
    -- all ready
    if pending.leader == me then
        for _, n in ipairs(needed) do
            if n ~= me then InviteUnit(n) end
        end
        lfprint(COLOR_HUNTER .. "All members confirmed! Group forming for " .. (pending.instance) .. ".")
    end
    LFG.grp_queueStatus  = nil
    LFG.grp_pendingOffer = nil
    if _G["LFGGrpReadyStatusFrame"] then _G["LFGGrpReadyStatusFrame"]:Hide() end
    grp_broadcastQueueLeave()
    -- also remove our listing if we had one
    if LFG.grp_listedGroup then
        grp_CSend("GD|" .. tostring(LFG.grp_listedGroup.id))
        local _, idx = grp_findGroupByID(me .. ":" .. tostring(LFG.grp_listedGroup.id))
        if idx then table.remove(LFG.grp_groups, idx) end
        LFG.grp_listedGroup = nil
    end
    LFG.Grp_UpdateQueue()
end

-- ============================================================
-- Whisper / addon message handling
-- ============================================================
local function grp_handleOfferMsg(eventCode, sender, payload)
    local parts = grp_explode(payload, "|")
    if eventCode == "OFFER" then
        local inst, leader, role = parts[1], parts[2], parts[3]
        if LFG.grp_queueStatus ~= "queued" or LFG.grp_pendingOffer then return end
        LFG.grp_pendingOffer = { instance=inst, leader=leader, role=role, time=GetTime() }
        LFG.Grp_ShowReadyFrame(inst, role)
    elseif eventCode == "ACCEPT" then
        local pending = LFG.grp_pendingOffer
        if not pending or pending.leader ~= me then return end
        local inst, role = parts[1], parts[2]
        if pending.instance ~= inst then return end
        pending.acks = pending.acks or {}
        pending.acks[sender] = role
        LFG.Grp_MarkSlotReady(role)
        grp_checkOfferComplete()
    elseif eventCode == "DECLINE" then
        local pending = LFG.grp_pendingOffer
        if not pending or pending.leader ~= me then return end
        if pending.match then
            for _, n in ipairs({pending.match.tank, pending.match.healer,
                                 pending.match.damage[1], pending.match.damage[2], pending.match.damage[3]}) do
                if n ~= me and n ~= sender then grp_SendWhisper("CANCEL|"..pending.instance, n) end
            end
        end
        LFG.grp_pendingOffer = nil
        if _G["LFGGrpReadyFrame"] then _G["LFGGrpReadyFrame"]:Hide() end
        if _G["LFGGrpReadyStatusFrame"] then _G["LFGGrpReadyStatusFrame"]:Hide() end
        lfprint(sender .. " declined the group.")
    elseif eventCode == "CANCEL" then
        LFG.grp_pendingOffer = nil
        if _G["LFGGrpReadyFrame"] then _G["LFGGrpReadyFrame"]:Hide() end
        if _G["LFGGrpReadyStatusFrame"] then _G["LFGGrpReadyStatusFrame"]:Hide() end
    elseif eventCode == "GS" then
        -- signup: GS|<id>|<role>
        local id, role = parts[1], parts[2]
        if not LFG.grp_listedGroup then return end
        if LFG.grp_listedGroup.id ~= (me..":"..tostring(id)) then return end
        local roleIdx = role=="t" and 1 or role=="h" and 2 or role=="d" and 3 or 0
        if roleIdx == 0 then return end
        local lim  = LFG.grp_listedGroup.limit or {0,0,0}
        local conf = LFG.grp_listedGroup.numConfirmed or {0,0,0}
        if (lim[roleIdx] or 0) == 0 or conf[roleIdx] >= lim[roleIdx] then
            grp_SendWhisper("GS_DENY|"..tostring(id), sender); return
        end
        table.insert(LFG.grp_listedGroup.signups[roleIdx], { name=sender })
        conf[roleIdx] = conf[roleIdx] + 1
        grp_broadcastMyGroup("GU")
        grp_SendWhisper("GS_OK|"..tostring(id), sender)
        lfprint(sender .. " signed up as " .. grp_roleLabel(role) .. " for your group.")
        if LFG.tab == 3 then LFG.Grp_UpdateBrowse() end
    elseif eventCode == "GS_OK" then
        lfprint(COLOR_GREEN .. "Signup accepted! The leader will invite you.")
    elseif eventCode == "GS_DENY" then
        lfprint(COLOR_RED .. "Signup denied — that role is already full.")
    end
end

local function grp_handlePartyMsg(msg, sender)
    if string.find(msg, "C2C_ROLECHECK_RESPONSE", 1, true) then
        local parts = StringSplit(msg, ";")
        local role = parts[2] or ""
        local roleIdx = role=="t" and 1 or role=="h" and 2 or role=="d" and 3 or 0
        lfprint(sender .. " selected role: " .. (grp_roleLabel(role) ~= "" and grp_roleLabel(role) or "unknown"))
        if not LFG.grp_listedGroup then return end
        if LFG.grp_roleCheck[sender] then LFG.grp_roleCheck[sender] = roleIdx end
        for _, status in pairs(LFG.grp_roleCheck) do
            if status == -1 then return end
        end
        LFG.grp_listedGroup.signups = { {}, {}, {} }
        for name, ridx in pairs(LFG.grp_roleCheck) do
            if ridx > 0 then
                table.insert(LFG.grp_listedGroup.signups[ridx], { name=name })
            end
        end
        for k in pairs(LFG.grp_roleCheck) do LFG.grp_roleCheck[k] = nil end
        grp_broadcastMyGroup("GU")
        if LFG.tab == 3 then LFG.Grp_UpdateBrowse() end
        return
    end
    if string.find(msg, "C2C_ROLECHECK_START", 1, true) then
        local parts = StringSplit(msg, ";")
        lfdebug("GRP rolecheck start from " .. sender .. " for group " .. (parts[2] or "?"))
        LFG.Grp_ShowRoleCheckFrame()
        return
    end
    if msg == "C2C_ROLECHECK_STOP" then
        if _G["LFGGrpRoleCheckFrame"] then _G["LFGGrpRoleCheckFrame"]:Hide() end
        for k in pairs(LFG.grp_roleCheck) do LFG.grp_roleCheck[k] = nil end
    end
end

-- Called from LFGComms OnEvent for CHAT_MSG_ADDON
function LFG.Grp_HandleAddonMsg(prefix, msg, channel, sender)
    if prefix ~= LFG_ADDON_CHANNEL then return end
    if channel == "PARTY" or channel == "RAID" then
        if string.sub(msg, 1, 4) ~= GRP_WHISPER_PREFIX then return end
        local body = string.sub(msg, 5)
        grp_handlePartyMsg(body, sender)
        return
    end
    if channel == "WHISPER" then
        if string.sub(msg, 1, 4) ~= GRP_WHISPER_PREFIX then return end
        local body = string.sub(msg, 5)
        local pipePos = string.find(body, "|", 1, true)
        if not pipePos then return end
        local code = string.sub(body, 1, pipePos-1)
        local rest = string.sub(body, pipePos+1)
        grp_handleOfferMsg(code, sender, rest)
    end
end

-- Called from the channel message handler
function LFG.Grp_HandleChannelMsg(text, sender)
    text = grp_unescapePipes(text)
    if string.sub(text, 1, #GRP_CMSG_PREFIX) ~= GRP_CMSG_PREFIX then return end
    if sender == me then return end
    local body = string.sub(text, #GRP_CMSG_PREFIX + 1)
    local pipePos = string.find(body, "|", 1, true)
    if not pipePos then return end
    local code = string.sub(body, 1, pipePos-1)
    local rest = string.sub(body, pipePos+1)

    if code == "Q" then
        local parts = grp_explode(rest, "|")
        grp_handleRemoteQueue(sender, parts[1] or "", parts[2] or "",
                              parts[3] or 0,   parts[4] or "", parts[5] or "")
    elseif code == "L" then
        grp_handleRemoteQueueLeave(sender)
    elseif code == "GN" or code == "GU" or code == "GD" then
        grp_handleRemoteGroup(code, sender, rest)
    end
end

-- ============================================================
-- Role check frame (party/raid)
-- ============================================================
function LFG.Grp_StartRoleCheck()
    if not LFG.grp_listedGroup then return end
    for k in pairs(LFG.grp_roleCheck) do LFG.grp_roleCheck[k] = nil end
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
            if name and online then LFG.grp_roleCheck[name] = -1 end
        end
    else
        LFG.grp_roleCheck[me] = -1
        for i = 1, GetNumPartyMembers() do
            if UnitIsConnected("party"..i) then
                LFG.grp_roleCheck[UnitName("party"..i)] = -1
            end
        end
    end
    grp_SendRaid("C2C_ROLECHECK_START;" .. tostring(LFG.grp_listedGroup.id))
    LFG.Grp_ShowRoleCheckFrame()
end

function LFG.Grp_ShowRoleCheckFrame()
    if _G["LFGGrpRoleCheckFrame"] then _G["LFGGrpRoleCheckFrame"]:Show() end
    PlaySoundFile("Interface\\AddOns\\LFG\\sound\\lfg_rolecheck.ogg")
end

function LFG.Grp_RoleCheckConfirm()
    local role = "0"
    if _G["LFGGrpRCTank"]   and _G["LFGGrpRCTank"]:GetChecked()   then role = "t"
    elseif _G["LFGGrpRCHealer"] and _G["LFGGrpRCHealer"]:GetChecked() then role = "h"
    elseif _G["LFGGrpRCDamage"] and _G["LFGGrpRCDamage"]:GetChecked() then role = "d"
    end
    grp_SendRaid("C2C_ROLECHECK_RESPONSE;" .. role)
    if _G["LFGGrpRoleCheckFrame"] then _G["LFGGrpRoleCheckFrame"]:Hide() end
end

function LFG.Grp_RoleCheckDecline()
    grp_SendRaid("C2C_ROLECHECK_RESPONSE;0")
    PlaySoundFile("Interface\\AddOns\\LFG\\sound\\lfg_denied.ogg")
    if _G["LFGGrpRoleCheckFrame"] then _G["LFGGrpRoleCheckFrame"]:Hide() end
end

-- ============================================================
-- Instance data for queue tab  (Epoch / WotLK dungeons)
-- pulled from LFG's own dungeon table so no duplication needed
-- ============================================================
local function grp_buildInstTable()
    local t = {}
    for name, data in pairs(LFG.allDungeons or {}) do
        if data.code then
            table.insert(t, {
                code      = data.code,
                name      = name,
                minLevel  = data.minLevel or 1,
                maxLevel  = data.maxLevel or 80,
                background= data.background or "dungeonwall",
            })
        end
    end
    -- also include eliteEncounters
    for name, data in pairs(LFG.eliteEncounters or {}) do
        if data.code then
            table.insert(t, {
                code      = data.code,
                name      = name,
                minLevel  = data.minLevel or 1,
                maxLevel  = data.maxLevel or 80,
                background= data.background or "dungeonwall",
                isElite   = true,
            })
        end
    end
    table.sort(t, function(a,b)
        if a.minLevel == b.minLevel then return a.maxLevel > b.maxLevel end
        return a.minLevel > b.minLevel
    end)
    return t
end

LFG_GRP_INSTANCES     = nil  -- sorted array, built lazily
LFG_GRP_INSTANCES_MAP = nil  -- code→entry dict, built alongside array

local function grp_getInstTable()
    if not LFG_GRP_INSTANCES then
        LFG_GRP_INSTANCES     = grp_buildInstTable()
        LFG_GRP_INSTANCES_MAP = {}
        for _, entry in ipairs(LFG_GRP_INSTANCES) do
            LFG_GRP_INSTANCES_MAP[entry.code] = entry
        end
    end
    return LFG_GRP_INSTANCES
end

-- ============================================================
-- UI: Browse tab
-- ============================================================
local function grp_syntheticEntry(name, qe)
    local dungeonNames = {}
    local instTable = grp_getInstTable()
    for _, inst in ipairs(instTable) do
        if qe.instances and qe.instances[inst.code] then
            table.insert(dungeonNames, inst.name)
        end
    end
    table.sort(dungeonNames)
    local roleList = {}
    local roles = qe.roles or ""
    if string.find(roles,"t",1,true) then table.insert(roleList,"Tank")   end
    if string.find(roles,"h",1,true) then table.insert(roleList,"Healer") end
    if string.find(roles,"d",1,true) then table.insert(roleList,"Damage") end
    local partyDesc = ""
    if qe.party and #qe.party > 0 then
        local memNames = {}
        for _, m in ipairs(qe.party) do table.insert(memNames, m.name) end
        partyDesc = " | Party: " .. table.concat(memNames, ", ")
    end
    local entry = LFG.grp_queueCache[name] or {}
    entry.creator      = name
    entry.class        = qe.class
    entry.title        = #dungeonNames > 0 and table.concat(dungeonNames,", ") or "(queued)"
    entry.description  = "Lvl " .. (qe.level or "?") .. " | " .. table.concat(roleList,"/") .. partyDesc
    entry.category     = 1
    entry.limit        = {
        string.find(qe.roles or "","t",1,true) and 1 or 0,
        string.find(qe.roles or "","h",1,true) and 1 or 0,
        string.find(qe.roles or "","d",1,true) and 1 or 0,
    }
    entry.numConfirmed = { 0, 0, 0 }
    entry._isQueue     = true
    entry._lastSeen    = qe.time
    entry.id           = "queue:" .. name
    LFG.grp_queueCache[name] = entry
    return entry
end

local function grp_buildMergedList()
    -- purge stale cache
    for name in pairs(LFG.grp_queueCache) do
        if not LFG.grp_queueEntries[name] then LFG.grp_queueCache[name] = nil end
    end
    local merged = {}
    local search = string.lower(LFG.grp_searchText or "")
    for _, g in ipairs(LFG.grp_groups) do
        local match = search == ""
            or string.find(string.lower(g.title or ""), search, 1, true)
            or string.find(string.lower(g.description or ""), search, 1, true)
        if match then table.insert(merged, g) end
    end
    for name, qe in pairs(LFG.grp_queueEntries) do
        if name ~= me and qe.instances and next(qe.instances) then
            local syn = grp_syntheticEntry(name, qe)
            if search == ""
               or string.find(string.lower(syn.title or ""), search, 1, true) then
                table.insert(merged, syn)
            end
        end
    end
    -- filter by category
    local filtered = {}
    for _, g in ipairs(merged) do
        if (g.category or 1) == LFG.grp_categoryFilter then
            table.insert(filtered, g)
        end
    end
    return filtered
end

function LFG.Grp_UpdateBrowse()
    if LFG.tab ~= 3 or LFG.grp_currentTab ~= 1 then return end

    local data = grp_buildMergedList()
    local offset = LFG.grp_browseOffset

    -- hide all rows first
    for _, row in ipairs(LFG.grp_groupRows) do row:Hide() end

    for i = 1, GRP_GROUPS_SHOWN do
        local entry = data[i + offset]
        local row = LFG.grp_groupRows[i]
        if not row then break end
        if entry then
            local cc = RAID_CLASS_COLORS and entry.class and RAID_CLASS_COLORS[entry.class]
            local rowName    = row:GetName()
            local leaderText = rowName and _G[rowName .. "LeaderText"]
            local titleText  = rowName and _G[rowName .. "Text"]
            local subText    = rowName and _G[rowName .. "SubText"]
            if titleText  then titleText:SetText(entry.title or "") end
            if subText    then subText:SetText(entry.description or "") end
            if leaderText then
                leaderText:SetText(entry.creator or "")
                if cc then leaderText:SetTextColor(cc.r, cc.g, cc.b)
                else leaderText:SetTextColor(0.8, 0.8, 0.8) end
            end
            for role = 1, 3 do
                local icon   = rowName and _G[rowName .. "Role" .. role .. "Icon"]
                local number = rowName and _G[rowName .. "Role" .. role .. "Number"]
                if entry.limit and entry.limit[role] and entry.limit[role] > 0 then
                    if icon   then icon:SetAlpha(1) end
                    if number then
                        number:SetText(entry._isQueue and "" or
                            ((entry.numConfirmed and entry.numConfirmed[role] or 0)
                             .. "/" .. entry.limit[role]))
                    end
                else
                    if icon   then icon:SetAlpha(0) end
                    if number then number:SetText("") end
                end
            end
            row.data = entry
            row.title = entry.title
            row.creator = entry.creator
            row.description = entry.description
            local isSelected = LFG.grp_selectedGroup and
                                entry.id and
                                LFG.grp_selectedGroup.id == entry.id
            if isSelected then
                row:LockHighlight()
                local hl = rowName and _G[rowName.."Highlight"]
                if hl then hl:Show() end
            else
                row:UnlockHighlight()
                local hl = rowName and _G[rowName.."Highlight"]
                if hl then hl:Hide() end
            end
            row:Show()
        end
    end

    -- scroll bar
    local scrollFrame = _G["LFGGrpBrowseScroll"]
    if scrollFrame then
        FauxScrollFrame_Update(scrollFrame, #data, GRP_GROUPS_SHOWN, GRP_ROW_H)
    end

    -- new / edit / unlist button label
    local btn = _G["LFGGrpNewGroupBtn"]
    if btn then
        btn:SetText(LFG.grp_listedGroup and "Edit Group" or "New Group")
    end

    -- whisper button
    local wBtn = _G["LFGGrpWhisperBtn"]
    if wBtn then
        if LFG.grp_selectedGroup and LFG.grp_selectedGroup.creator ~= me then
            wBtn:Enable()
        else
            wBtn:Disable()
        end
    end

    -- category dropdown label
    local dd = _G["LFGGrpCategoryDropDown"]
    if dd then
        UIDropDownMenu_SetText(dd, LFG.grp_categories[LFG.grp_categoryFilter] or "Dungeons")
    end
end

-- ============================================================
-- UI: Queue tab
-- ============================================================
function LFG.Grp_UpdateQueue()
    if LFG.tab ~= 3 or LFG.grp_currentTab ~= 2 then return end

    local inRaid = GetNumRaidMembers() > 0
    local isLeader = IsPartyLeader() or GetNumPartyMembers() == 0
    local queued = LFG.grp_queueStatus == "queued"

    -- main button
    local mainBtn = _G["LFGGrpMainBtn"]
    if mainBtn then
        if queued then
            mainBtn:SetText("Leave Queue")
        elseif GetNumPartyMembers() > 0 then
            mainBtn:SetText("Find More")
        else
            mainBtn:SetText("Find Group")
        end
        if isLeader and not inRaid then mainBtn:Enable()
        else mainBtn:Disable() end
    end

    local instTable = grp_getInstTable()
    local playerLevel = UnitLevel("player") or 1
    local offset = LFG.grp_queueOffset

    for _, row in ipairs(LFG.grp_instRows) do row:Hide() end

    local shown = 0
    for i = 1, GRP_INST_SHOWN do
        local inst = instTable[i + offset]
        if not inst then break end
        local row = LFG.grp_instRows[i]
        if not row then break end

        local nameText = _G[row:GetName() .. "Name"]
        local levText  = _G[row:GetName() .. "Levels"]
        local cb       = _G[row:GetName() .. "CheckButton"]

        if nameText then nameText:SetText(inst.name) end
        if levText  then levText:SetText("("..inst.minLevel.."-"..inst.maxLevel..")") end

        -- colour by level diff
        local avg = math.floor((inst.maxLevel - inst.minLevel) / 2) + inst.minLevel
        local diff = avg - playerLevel
        local r, g, b
        if diff > 4 then r,g,b = 1,0,0
        elseif diff > 2 then r,g,b = 1,0.5,0.25
        elseif diff > -3 then r,g,b = 1,1,0
        elseif diff > -12 then r,g,b = 0.25,0.75,0.25
        else r,g,b = 0.5,0.5,0.5 end
        if nameText then nameText:SetTextColor(r,g,b) end
        if levText  then levText:SetTextColor(r,g,b) end

        row.r, row.g, row.b = r, g, b
        row.instance = inst.code

        if cb then
            cb:SetChecked(LFG.grp_selectedInst[inst.code] and true or false)
            if queued or inRaid or not isLeader then cb:Disable()
            else cb:Enable() end
        end

        row:Show()
        shown = shown + 1
    end

    local scrollFrame = _G["LFGGrpQueueScroll"]
    if scrollFrame then
        FauxScrollFrame_Update(scrollFrame, #instTable, GRP_INST_SHOWN, GRP_INST_H)
    end

    -- role checkboxes
    for i = 1, 3 do
        local rb = _G["LFGGrpRole"..i.."Check"]
        if rb then
            rb:SetChecked(LFG.grp_selectedRoles[i])
            local _, class = UnitClass("player")
            local roles = LFG.grp_classRoles[class] or {false,false,true}
            if queued or inRaid or not isLeader or not roles[i] then rb:Disable()
            else rb:Enable() end
        end
    end

    -- can-queue check
    local canQueue = next(LFG.grp_selectedInst) ~= nil
                  and (LFG.grp_selectedRoles[1] or LFG.grp_selectedRoles[2] or LFG.grp_selectedRoles[3])
    if mainBtn then
        if not queued and not canQueue then mainBtn:Disable() end
    end
end

-- ============================================================
-- UI: New Group form
-- ============================================================
function LFG.Grp_OpenNewGroupForm()
    local frame = _G["LFGGrpNewGroupForm"]
    if not frame then return end
    if LFG.grp_listedGroup then
        -- edit mode
        local g = LFG.grp_listedGroup
        local titleEB = _G["LFGGrpFormTitle"]
        local descEB  = _G["LFGGrpFormDesc"]
        if titleEB then titleEB:SetText(g.title or "") end
        if descEB  then descEB:SetText(g.description or "") end
        local useRoles = _G["LFGGrpFormUseRoles"]
        if useRoles then useRoles:SetChecked(grp_isGroupUsingRoles(g)) end
        if _G["LFGGrpFormT"] then _G["LFGGrpFormT"]:SetText(tostring(g.limit[1])) end
        if _G["LFGGrpFormH"] then _G["LFGGrpFormH"]:SetText(tostring(g.limit[2])) end
        if _G["LFGGrpFormD"] then _G["LFGGrpFormD"]:SetText(tostring(g.limit[3])) end
        local delBtn = _G["LFGGrpFormDeleteBtn"]
        if delBtn then delBtn:Show() end
    else
        -- new mode
        local titleEB = _G["LFGGrpFormTitle"]
        local descEB  = _G["LFGGrpFormDesc"]
        if titleEB then titleEB:SetText("") end
        if descEB  then descEB:SetText("") end
        if _G["LFGGrpFormT"] then _G["LFGGrpFormT"]:SetText("1") end
        if _G["LFGGrpFormH"] then _G["LFGGrpFormH"]:SetText("1") end
        if _G["LFGGrpFormD"] then _G["LFGGrpFormD"]:SetText("3") end
        local delBtn = _G["LFGGrpFormDeleteBtn"]
        if delBtn then delBtn:Hide() end
    end
    frame:Show()
end

function LFG.Grp_SubmitGroupForm()
    local titleEB = _G["LFGGrpFormTitle"]
    local descEB  = _G["LFGGrpFormDesc"]
    local title = titleEB and grp_trim(titleEB:GetText()) or ""
    if title == "" then
        lfprint("Please enter a group title."); return
    end
    local desc  = descEB and descEB:GetText() or ""
    local useRoles = _G["LFGGrpFormUseRoles"]
    local tanks, healers, damage = 0, 0, 0
    if useRoles and useRoles:GetChecked() then
        tanks   = tonumber(_G["LFGGrpFormT"] and _G["LFGGrpFormT"]:GetText()) or 0
        healers = tonumber(_G["LFGGrpFormH"] and _G["LFGGrpFormH"]:GetText()) or 0
        damage  = tonumber(_G["LFGGrpFormD"] and _G["LFGGrpFormD"]:GetText()) or 0
    end
    local _, class = UnitClass("player")
    if LFG.grp_listedGroup then
        -- update
        local g = LFG.grp_listedGroup
        g.title = title; g.description = desc
        g.limit = { tanks, healers, damage }
        grp_broadcastMyGroup("GU")
        lfprint("Group listing updated.")
    else
        -- new
        local g = {
            id           = LFG.grp_nextGroupId,
            creator      = me,
            class        = class,
            title        = title,
            description  = desc,
            category     = LFG.grp_categoryFilter,
            limit        = { tanks, healers, damage },
            numConfirmed = { 0, 0, 0 },
            signups      = { {}, {}, {} },
        }
        LFG.grp_nextGroupId = LFG.grp_nextGroupId + 1
        LFG.grp_listedGroup = g
        local stored = {}
        for k, v in pairs(g) do stored[k] = v end
        stored.id = me .. ":" .. tostring(g.id)
        stored._lastSeen = GetTime()
        table.insert(LFG.grp_groups, 1, stored)
        grp_broadcastMyGroup("GN")
        lfprint(COLOR_HUNTER .. "Group listed: " .. COLOR_WHITE .. title)
    end
    if _G["LFGGrpNewGroupForm"] then _G["LFGGrpNewGroupForm"]:Hide() end
    LFG.Grp_UpdateBrowse()
end

function LFG.Grp_DeleteGroup()
    if not LFG.grp_listedGroup then return end
    local g = LFG.grp_listedGroup
    grp_CSend("GD|" .. tostring(g.id))
    local _, idx = grp_findGroupByID(me .. ":" .. tostring(g.id))
    if idx then table.remove(LFG.grp_groups, idx) end
    LFG.grp_listedGroup = nil
    LFG.grp_selectedGroup = nil
    if _G["LFGGrpNewGroupForm"] then _G["LFGGrpNewGroupForm"]:Hide() end
    lfprint("Group listing removed.")
    LFG.Grp_UpdateBrowse()
end

-- ============================================================
-- UI: Queue main button
-- ============================================================
function LFG.Grp_MainButtonClick()
    if LFG.grp_queueStatus == "queued" then
        LFG.grp_queueStatus = nil
        grp_broadcastQueueLeave()
        if _G["LFGGrpReadyFrame"]       then _G["LFGGrpReadyFrame"]:Hide() end
        if _G["LFGGrpReadyStatusFrame"] then _G["LFGGrpReadyStatusFrame"]:Hide() end
        LFG.grp_pendingOffer = nil
        lfprint("Left the queue.")
    else
        if not next(LFG.grp_selectedInst) then
            lfprint(COLOR_RED .. "Select at least one dungeon first."); return
        end
        if not (LFG.grp_selectedRoles[1] or LFG.grp_selectedRoles[2] or LFG.grp_selectedRoles[3]) then
            lfprint(COLOR_RED .. "Select at least one role first."); return
        end
        LFG.grp_queueStatus = "queued"
        grp_broadcastQueue()
        local instNames = {}
        local instTable = grp_getInstTable()
        for _, inst in ipairs(instTable) do
            if LFG.grp_selectedInst[inst.code] then
                table.insert(instNames, inst.name)
            end
        end
        lfprint(COLOR_HUNTER .. "Joined queue for: " .. COLOR_WHITE .. table.concat(instNames, ", "))
        PlaySound("PvpEnterQueue")
    end
    LFG.Grp_UpdateQueue()
end

-- ============================================================
-- UI: sub-tab switch (browse / queue)
-- ============================================================
function LFG.Grp_SwitchSubTab(t)
    LFG.grp_currentTab = t
    local browseContent = _G["LFGGrpBrowseContent"]
    local queueContent  = _G["LFGGrpQueueContent"]
    if browseContent then browseContent:SetShown(t == 1) end
    if queueContent  then queueContent:SetShown(t == 2) end
    if t == 1 then LFG.Grp_UpdateBrowse()
    else            LFG.Grp_UpdateQueue() end
end

-- ============================================================
-- UI: whisper selected group leader
-- ============================================================
function LFG.Grp_WhisperSelected()
    if not LFG.grp_selectedGroup then return end
    local leader = LFG.grp_selectedGroup.creator
    if leader and leader ~= me then
        if ChatFrame_OpenChat then
            ChatFrame_OpenChat("/w " .. leader .. " ")
        else
            local eb = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox
            if eb then eb:SetText("/w " .. leader .. " "); eb:Show(); eb:SetFocus() end
        end
    end
end

-- ============================================================
-- UI: signup for selected group
-- ============================================================
function LFG.Grp_SignupSelected()
    local g = LFG.grp_selectedGroup
    if not g or g._isQueue then return end
    -- determine our best role
    local role = "d"
    if LFG.grp_selectedRoles[1] then role = "t"
    elseif LFG.grp_selectedRoles[2] then role = "h" end
    -- extract plain numeric id from namespaced id  "leadername:123"
    local parts = grp_explode(g.id, ":")
    local plainId = parts[2] or parts[1]
    grp_SendWhisper("GS|" .. plainId .. "|" .. role, g.creator)
    lfprint("Signup sent to " .. g.creator .. " as " .. grp_roleLabel(role) .. ".")
end

-- ============================================================
-- UI: category dropdown
-- ============================================================
function LFG.Grp_InitCategoryDropDown()
    for i, label in ipairs(LFG.grp_categories) do
        local id = i
        -- UIDropDownMenu_CreateInfo does not exist in 3.3.5a; populate a plain table
        local info = {}
        info.text = label
        info.func = function()
            LFG.grp_categoryFilter = id
            UIDropDownMenu_SetSelectedID(_G["LFGGrpCategoryDropDown"], id)
            UIDropDownMenu_SetText(_G["LFGGrpCategoryDropDown"], label)
            LFG.Grp_UpdateBrowse()
        end
        info.checked = LFG.grp_categoryFilter == i
        UIDropDownMenu_AddButton(info)
    end
end

-- ============================================================
-- Row OnClick
-- ============================================================
function LFG.Grp_GroupRowClick()
    -- 'this' is the row frame
    local entry = this.data
    if not entry then return end
    if LFG.grp_selectedGroup == entry then
        LFG.grp_selectedGroup = nil
    else
        LFG.grp_selectedGroup = entry
    end
    LFG.Grp_UpdateBrowse()
end

function LFG.Grp_InstCheckClick()
    local inst = this:GetParent().instance
    if inst then
        LFG.grp_selectedInst[inst] = this:GetChecked() and true or nil
    end
    LFG.Grp_UpdateQueue()
end

function LFG.Grp_RoleClick(roleIdx)
    LFG.grp_selectedRoles[roleIdx] = not LFG.grp_selectedRoles[roleIdx]
    local _, class = UnitClass("player")
    local roles = LFG.grp_classRoles[class] or {false,false,true}
    if not roles[roleIdx] then LFG.grp_selectedRoles[roleIdx] = false end
    LFG.Grp_UpdateQueue()
end

-- ============================================================
-- Frame init (called once from Groups tab OnLoad or first Show)
-- ============================================================
function LFG.Grp_Init()
    -- Invalidate instance table cache so it rebuilds against current dungeon data
    if not LFG_GRP_INSTANCES then
        LFG_GRP_INSTANCES     = nil
        LFG_GRP_INSTANCES_MAP = nil
    end
    -- Build group rows using LFTGroupEntryTemplate if available,
    -- otherwise use plain Buttons (fallback)
    local parent = _G["LFGGrpBrowseContent"]
    if parent and #LFG.grp_groupRows == 0 then
        for i = 1, GRP_GROUPS_SHOWN do
            local fname = "LFGGrpGroupRow" .. i
            local f
            if _G["LFTGroupEntryTemplate"] then
                f = CreateFrame("Button", fname, parent, "LFTGroupEntryTemplate")
            else
                f = CreateFrame("Button", fname, parent)
                f:SetWidth(285); f:SetHeight(GRP_ROW_H)
                -- minimal sub-widgets
                local title = f:CreateFontString(fname.."Text","OVERLAY","GameFontNormal")
                title:SetPoint("TOPLEFT",f,"TOPLEFT",-2,2); title:SetWidth(132); title:SetHeight(22)
                local sub   = f:CreateFontString(fname.."SubText","OVERLAY","GameFontDisableSmall")
                sub:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",-2,-4); sub:SetWidth(200); sub:SetHeight(20)
                local lead  = f:CreateFontString(fname.."LeaderText","OVERLAY","GameFontHighlightSmall")
                lead:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",0,0); lead:SetJustifyH("RIGHT")
                local hl    = f:CreateTexture(fname.."Highlight","BACKGROUND")
                hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                hl:SetBlendMode("ADD"); hl:SetAllPoints(f); hl:Hide()
                -- role icons + numbers
                for role = 1, 3 do
                    local icon = f:CreateTexture(fname.."Role"..role.."Icon","ARTWORK")
                    icon:SetWidth(12); icon:SetHeight(12); icon:SetAlpha(0)
                    local roleTex = role==1 and "ready_tank" or role==2 and "ready_healer" or "ready_damage"
                    icon:SetTexture("Interface\\AddOns\\LFG\\images\\"..roleTex)
                    local num = f:CreateFontString(fname.."Role"..role.."Number","ARTWORK","GameFontNormalSmall")
                    num:SetHeight(24)
                    if role == 3 then
                        icon:SetPoint("RIGHT",f,"RIGHT",0,0)
                        num:SetPoint("RIGHT",icon,"LEFT",-2,0)
                    elseif role == 2 then
                        icon:SetPoint("RIGHT",fname.."Role3Icon","LEFT",-1,0)
                        num:SetPoint("RIGHT",icon,"LEFT",-2,0)
                    else
                        icon:SetPoint("RIGHT",fname.."Role2Icon","LEFT",-1,0)
                        num:SetPoint("RIGHT",icon,"LEFT",-2,0)
                    end
                end
            end
            f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -GRP_ROW_H * (i-1))
            f:RegisterForClicks("LeftButtonUp","RightButtonUp")
            f:SetScript("OnClick", LFG.Grp_GroupRowClick)
            f:SetScript("OnEnter", function()
                _G[this:GetName().."Highlight"]:Show()
                if this.title then
                    GameTooltip:SetOwner(this, "ANCHOR_TOPRIGHT")
                    GameTooltip:SetText(this.title, 1,1,1,1,true)
                    if this.description and this.description ~= "" then
                        GameTooltip:AddLine(this.description, 1,0.82,0,1,true)
                    end
                    GameTooltip:Show()
                end
            end)
            f:SetScript("OnLeave", function()
                if not this.selected then
                    local hl = _G[this:GetName().."Highlight"]
                    if hl then hl:Hide() end
                end
                GameTooltip:Hide()
            end)
            f:Hide()
            table.insert(LFG.grp_groupRows, f)
        end
    end

    -- Build instance rows
    local qparent = _G["LFGGrpQueueContent"]
    if qparent and #LFG.grp_instRows == 0 then
        for i = 1, GRP_INST_SHOWN do
            local fname = "LFGGrpInstRow" .. i
            local f
            if _G["LFTInstanceEntryTemplate"] then
                f = CreateFrame("Frame", fname, qparent, "LFTInstanceEntryTemplate")
            else
                f = CreateFrame("Frame", fname, qparent)
                f:SetWidth(293); f:SetHeight(GRP_INST_H)
                local cb = CreateFrame("CheckButton", fname.."CheckButton", f, "UICheckButtonTemplate")
                cb:SetWidth(20); cb:SetHeight(20); cb:SetPoint("TOPLEFT",f,"TOPLEFT",0,0)
                cb:HitRectInsets(0,-280,0,0)
                cb:SetScript("OnClick", LFG.Grp_InstCheckClick)
                local nameFS = f:CreateFontString(fname.."Name","OVERLAY","GameFontNormal")
                nameFS:SetPoint("LEFT",f,"LEFT",22,0); nameFS:SetWidth(200); nameFS:SetHeight(24)
                nameFS:SetJustifyH("LEFT")
                local levFS = f:CreateFontString(fname.."Levels","OVERLAY","GameFontNormal")
                levFS:SetPoint("RIGHT",f,"RIGHT",-6,0); levFS:SetWidth(72); levFS:SetHeight(24)
                levFS:SetJustifyH("RIGHT")
                local hl = f:CreateTexture(fname.."Highlight","BACKGROUND")
                hl:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
                hl:SetAllPoints(f); hl:Hide()
                f.name = nameFS; f.levels = levFS
                f.highlight = hl; f.checkButton = cb
            end
            f:SetPoint("TOPLEFT", qparent, "TOPLEFT", 0, -GRP_INST_H * (i-1))
            f:Hide()
            table.insert(LFG.grp_instRows, f)
        end
    end

    -- Category dropdown
    local dd = _G["LFGGrpCategoryDropDown"]
    if dd and not dd._initialized then
        UIDropDownMenu_Initialize(dd, LFG.Grp_InitCategoryDropDown)
        UIDropDownMenu_SetWidth(dd, 120)
        UIDropDownMenu_SetSelectedID(dd, LFG.grp_categoryFilter)
        UIDropDownMenu_SetText(dd, LFG.grp_categories[LFG.grp_categoryFilter])
        dd._initialized = true
    end

    -- Role buttons: disable unavailable roles for this class
    local _, class = UnitClass("player")
    local classRoles = LFG.grp_classRoles[class] or {false,false,true}
    for i = 1, 3 do
        if not classRoles[i] then LFG.grp_selectedRoles[i] = false end
        local rb = _G["LFGGrpRole"..i.."Check"]
        if rb then
            rb:SetChecked(LFG.grp_selectedRoles[i])
            if not classRoles[i] then rb:Disable() end
        end
    end

    LFG.Grp_SwitchSubTab(LFG.grp_currentTab)
end

-- ============================================================
-- Ticker (periodic broadcasts, match scans, prune)
-- ============================================================
local LFGGrpTicker = CreateFrame("Frame")
LFGGrpTicker:SetScript("OnUpdate", function()
    local now = GetTime()
    local t = LFG.grp_ticker
    if LFG.grp_queueStatus == "queued" and (now - t.lastQueue) > GRP_QUEUE_BROADCAST then
        t.lastQueue = now
        grp_broadcastQueue()
    end
    if LFG.grp_listedGroup and (now - t.lastGroup) > GRP_GROUP_BROADCAST then
        t.lastGroup = now
        grp_broadcastMyGroup("GU")
    end
    if (now - t.lastScan) > GRP_MATCH_SCAN then
        t.lastScan = now
        grp_scanForMatch()
    end
    if (now - t.lastPrune) > GRP_PRUNE_INTERVAL then
        t.lastPrune = now
        grp_pruneQueue()
        grp_pruneGroups()
        if LFG.tab == 3 and LFG.grp_currentTab == 1 then
            LFG.Grp_UpdateBrowse()
        end
    end
end)

-- ============================================================
-- Hook into existing LFGComms event handler
-- Additions to CHAT_MSG_CHANNEL and CHAT_MSG_ADDON
-- ============================================================
-- These are called from the hook we already added in the base code.
-- LFG.Grp_HandleChannelMsg  -- called from CHAT_MSG_CHANNEL block
-- LFG.Grp_HandleAddonMsg    -- called from CHAT_MSG_ADDON block

-- ============================================================
-- Logout: cancel group + leave queue
-- ============================================================
local _grp_origLogout = LFG.onPlayerLogout
function LFG.onPlayerLogout()
    if LFG.grp_listedGroup then
        local g = LFG.grp_listedGroup
        local msg = string.gsub(GRP_CMSG_PREFIX .. "GD|" .. tostring(g.id), "|", "||")
        SendChatMessage(msg, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID,
                        GetChannelName(LFG.channel))
        LFG.grp_listedGroup = nil
    end
    if LFG.grp_queueStatus == "queued" then
        local msg = string.gsub(GRP_CMSG_PREFIX .. "L|" .. me, "|", "||")
        SendChatMessage(msg, "CHANNEL", DEFAULT_CHAT_FRAME.editBox.languageID,
                        GetChannelName(LFG.channel))
        LFG.grp_queueStatus = nil
    end
    if _grp_origLogout then _grp_origLogout() end
end

