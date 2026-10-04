
ACHIEVER_ADDON_NAME = 'Achiever'
local ACHIEVER_ADDON_VERSION = '0.0.2.0'
local ACHIEVER_ADDON_CHANNEL = 'ACHIEVER_CHANNEL'
local ACHIEVER_REQUESTED_DATA = false
local ACHIEVER_STARTED = false

local function debug(msg)
    if achieverDBpc.debug == "enabled" then
	    DEFAULT_CHAT_FRAME:AddMessage('|cffc663fcDEBUG: |cffff55ff'.. (msg or 'nil'))
    end
end
local function warn(msg)
	DEFAULT_CHAT_FRAME:AddMessage('|cf3f3f66cWARN: |cffff55ff'.. (msg or 'nil'))
end

local function toggleDebug()
    if achieverDBpc.debug == "enabled" then
        achieverDBpc.debug = "disabled"
        DEFAULT_CHAT_FRAME:AddMessage('Achiever DEBUG mode disabled')
    else
        achieverDBpc.debug = "enabled"
        DEFAULT_CHAT_FRAME:AddMessage('Achiever DEBUG mode enabled')
    end
end

SLASH_ACHIEVERDEBUG1 = "/acdebug"
SlashCmdList.ACHIEVERDEBUG = function()
    toggleDebug()
end

Achiever = CreateFrame("Frame")
achieverDBpc = {
    criteria = {},
    achievements = {}
}
SLASH_RELOADUI1 = "/rl"
SlashCmdList.RELOADUI = ReloadUI

local function split(str, sep)
    if sep == nil then
        sep = '%s'
    end

    local res = {}
    local func = function(w)
        table.insert(res, w)
    end

    string.gsub(str, '[^'..sep..']+', func)
    return res
end

Achiever:RegisterEvent("ADDON_LOADED")
Achiever:RegisterEvent("PLAYER_ENTERING_WORLD")


Achiever.version = ACHIEVER_ADDON_VERSION
Achiever.channel = ACHIEVER_ADDON_CHANNEL
Achiever.channelIndex = nil

-- How server data reaches the addon -----------------------------------------------------------
-- The server answers the dot-commands below with system chat lines that start with "ACHI#".
-- 1.12 let us override ChatFrame1.AddMessage to catch them. On 1.14 that is fragile (chat addons /
-- custom UIs replace or bypass ChatFrame1), so the primary path is a CHAT_MSG_SYSTEM message filter,
-- which Blizzard runs before any chat frame sees the line. The AddMessage hook stays as a fallback.
Achiever.stats = { received = 0, viaFilter = 0, viaHook = 0, errors = 0, lastType = nil, lastError = nil, systemSeen = 0 }
Achiever.recentSystem = {}   -- last few CHAT_MSG_SYSTEM lines (for /acstatus)

local function stripColor(message)
    -- tolerate "|cffRRGGBB" prefixes and leading whitespace that some servers / chat addons add
    message = string.gsub(message, '^%s+', '')
    message = string.gsub(message, '^|c%x%x%x%x%x%x%x%x', '')
    message = string.gsub(message, '^%s+', '')
    return message
end

local function isServerMessage(message)
    return type(message) == 'string' and string.sub(stripColor(message), 1, 5) == 'ACHI#'
end

Achiever.isServerMessage = isServerMessage

-- Entry point for every ACHI# line, whatever path it arrived on. Never throws: an error in here
-- would otherwise propagate into Blizzard's chat code and break the chat frame.
Achiever.handleServerMessage = function(self, message)
    local ok, err = pcall(function()
        message = stripColor(message)
        for line in string.gmatch(message, '[^\r\n]+') do
            if (string.sub(line, 1, 5) == 'ACHI#') then
                self:processServerMessage(line)
            end
        end
    end)
    if (ok and self.scheduleUIRefresh) then self:scheduleUIRefresh() end
    if (not ok) then
        self.stats.errors = self.stats.errors + 1
        self.stats.lastError = tostring(err)
        if (self.stats.errors <= 5) then
            warn('Achiever failed to process a server message: ' .. tostring(err))
        end
    end
end

-- Every line can reach us through several paths (filter on each chat frame, raw event, hook): process it once.
Achiever.seenLines = {}
Achiever.seenOrder = {}
Achiever.markLineSeen = function(self, lineID)
    if (self.seenLines[lineID]) then return false end
    self.seenLines[lineID] = true
    self.seenOrder[#self.seenOrder + 1] = lineID
    if (#self.seenOrder > 200) then self.seenLines[table.remove(self.seenOrder, 1)] = nil end
    return true
end

Achiever.chatFilter = function(chatFrame, event, message, ...)
    if (not isServerMessage(message)) then
        -- remember what else the server says (e.g. "no such command"), shown by /acstatus
        if (type(message) == 'string' and chatFrame == (ChatFrame1 or chatFrame)) then
            local stats = Achiever.stats
            stats.systemSeen = stats.systemSeen + 1
            local recent = Achiever.recentSystem
            recent[#recent + 1] = string.sub(message, 1, 90)
            if (#recent > 6) then table.remove(recent, 1) end
        end
        return false
    end
    -- the filter runs once per chat frame that shows the event: process each line only once
    local lineID = select(10, ...)
    local first
    if (lineID ~= nil) then
        first = Achiever:markLineSeen(lineID)
    else
        first = (chatFrame == nil or chatFrame == ChatFrame1 or chatFrame == DEFAULT_CHAT_FRAME)
    end
    if (first) then
        Achiever.stats.viaFilter = Achiever.stats.viaFilter + 1
        Achiever:handleServerMessage(message)
    end
    return true -- hide the line from chat
end

Achiever.rawStats = { events = 0, achi = 0 }
Achiever.recentRaw = {}
Achiever.blocked = {}
Achiever.installRawListener = function(self)
    if (self.rawInstalled) then return end
    self.rawInstalled = true
    local f = CreateFrame('Frame')
    for _, ev in ipairs({ 'CHAT_MSG_SYSTEM', 'CHAT_MSG_SAY', 'CHAT_MSG_YELL', 'CHAT_MSG_WHISPER', 'CHAT_MSG_CHANNEL',
                          'CHAT_MSG_EMOTE', 'CHAT_MSG_MONSTER_SAY', 'CHAT_MSG_MONSTER_WHISPER', 'CHAT_MSG_RAID_WARNING',
                          'CHAT_MSG_ADDON', 'ADDON_ACTION_BLOCKED', 'ADDON_ACTION_FORBIDDEN' }) do
        pcall(f.RegisterEvent, f, ev)
    end
    f:SetScript('OnEvent', function(_, event, a1, a2, ...)
        if (event == 'ADDON_ACTION_BLOCKED' or event == 'ADDON_ACTION_FORBIDDEN') then
            local list = Achiever.blocked
            list[#list + 1] = tostring(a1) .. ':' .. tostring(a2)
            if (#list > 4) then table.remove(list, 1) end
            return
        end
        local text = a1
        if (event == 'CHAT_MSG_ADDON') then text = a2 end
        if (type(text) ~= 'string') then return end
        local rs = Achiever.rawStats
        rs.events = rs.events + 1
        local recent = Achiever.recentRaw
        recent[#recent + 1] = string.sub(string.gsub(event, 'CHAT_MSG_', '') .. ': ' .. text, 1, 90)
        if (#recent > 6) then table.remove(recent, 1) end
        if (isServerMessage(text)) then
            -- args after text: author, language, channel, target, flags, zoneChannelID, channelIndex, channelBaseName, unused, lineID
            local lineID = select(9, ...)
            if (lineID == nil or Achiever:markLineSeen(lineID)) then
                rs.achi = rs.achi + 1
                Achiever:handleServerMessage(text)
            end
        end
    end)
end

Achiever.installChatFilter = function(self)
    self:installRawListener()
    if (self.filterInstalled) then return end
    if (ChatFrame_AddMessageEventFilter) then
        ChatFrame_AddMessageEventFilter('CHAT_MSG_SYSTEM', Achiever.chatFilter)
        self.filterInstalled = true
    else
        warn('ChatFrame_AddMessageEventFilter is missing; relying on the chat frame hook only')
    end
end

Achiever.hookChatFrame = function(self, frame)
    if (not frame) then
        warn('Achiever failed to hook chat frame')
        return
    end
    if (frame.achieverHooked) then return end

    local original = frame.AddMessage
    if (original) then
        frame.achieverHooked = true
        frame.AddMessage = function(t, message, ...)
            if (isServerMessage(message)) then
                Achiever.stats.viaHook = Achiever.stats.viaHook + 1
                self:handleServerMessage(message)
                return false --hide this message
            end
            return original(t, message, ...)
        end
    else
        warn('failed to hook non-chat frame.')
    end
end

Achiever.achievementFrameSummaryCategorySubscribers = {}

local function achievementName(id)
    local a = achieverDB.achievements.data[id]
    return (a and a.name) or ('#' .. tostring(id))
end

local function criteriaName(id)
    local c = achieverDB.criteria.data[id]
    return (c and c.name) or ('#' .. tostring(id))
end

Achiever.processServerMessage = function(self, message)

    -- "ACHI#<TYPE>#<payload>"; the payload may itself contain '#', so do not split on it
    local msgType, payload = string.match(message, '^ACHI#([^#]*)#?(.*)$')
    local params = { 'ACHI', msgType, payload }
    if (self.stagedReset) then
        self.stagedReset = false
        self.resetDatabases()
        achieverDBpc.achievements = {}
        achieverDBpc.criteria = {}
    end
    self.stats.received = self.stats.received + 1
    self.stats.lastType = msgType
    if (achieverDB and achieverDB.complete and not self.loadedFromSaved) then achieverDB.complete = nil end
    if (params[1] == 'ACHI') then
        if (params[2] == 'AC') then
            --debug('server response: new achievement entry ')
            local a = split(params[3], ';')
            local id = tonumber(a[1])
            local previous = achieverDB.achievements.data[id]
            if (previous) then
                -- the same achievement can be sent again (retry / refresh): do not count its points twice
                achieverDB.achievements.totalPoints = achieverDB.achievements.totalPoints - (previous.points or 0)
            end
            achieverDB.achievements.data[id] = {}
            achieverDB.achievements.data[id].id = tonumber(id)
            achieverDB.achievements.data[id].faction = tonumber(a[2])
            achieverDB.achievements.data[id].previousId = tonumber(a[3])
            local name = ''
            if (a[4] ~= '_') then name = a[4] end
            achieverDB.achievements.data[id].name = name
            local description = ''
            if (a[5] ~= '_') then description = a[5] end
            achieverDB.achievements.data[id].description = description
            achieverDB.achievements.data[id].categoryId = tonumber(a[6])
            achieverDB.achievements.data[id].points = tonumber(a[7])
            achieverDB.achievements.data[id].order = tonumber(a[8])
            achieverDB.achievements.data[id].flags = tonumber(a[9])
            achieverDB.achievements.data[id].icon = tonumber(a[10])
            local titleReward = ''
            if (a[11] ~= '_') then titleReward = a[11] end
            achieverDB.achievements.data[id].titleReward = titleReward
            achieverDB.achievements.data[id].count = tonumber(a[12])
            achieverDB.achievements.data[id].refAchievement = tonumber(a[13])
            achieverDB.achievements.totalPoints = achieverDB.achievements.totalPoints + tonumber(a[7])

            local n = tonumber(a[14])
            local c = tonumber(a[15])

            local categoryId = tonumber(a[6])
            if (achieverDB.achievements.byCategory[categoryId] == nil) then
                achieverDB.achievements.byCategory[categoryId] = {}
            end
            -- table.insert(achieverDB.achievements.byCategory[categoryId], id)
            achieverDB.achievements.byCategory[categoryId][tonumber(a[8])] = id

            local previousId = tonumber(a[3])
            if (previousId == 0) then previousId = nil end
            if (previousId) then
                achieverDB.achievements.previousById[id] = previousId
                achieverDB.achievements.nextById[previousId] = id
            end

            ACHIEVER_STARTED = true
            
            if (n == c) then
                --debug('loaded achievements from server')
            end

        elseif (params[2] == 'ACV') then
            debug('server response: achievement data version')
            achieverDB.achievements.version = tonumber(params[3])
            ACHIEVER_STARTED = true
        elseif (params[2] == 'CA') then
            --debug('server response: get all categories')
            local a = split(params[3], ";")
            local id = tonumber(a[1])
            achieverDB.categories.data[id] = {}
            achieverDB.categories.data[id].id = tonumber(id)
            achieverDB.categories.data[id].parentId = tonumber(a[2])
            local name = ''
            if (a[3] ~= '_') then name = a[3] end
            achieverDB.categories.data[id].name = name
            achieverDB.categories.data[id].order = tonumber(a[4])
            local n = tonumber(a[5])
            local c = tonumber(a[6])

            local parentId = a[2]
            if (achieverDB.categories.byParent[parentId] == nil) then
                achieverDB.categories.byParent[parentId] = {}
            end
            -- table.insert(achieverDB.categories.byParent[parentId], id)
            achieverDB.categories.byParent[parentId][tonumber(a[4])] = id
            ACHIEVER_STARTED = true

            if (n == c) then
                debug('loaded categories from server')
            end
        elseif (params[2] == 'CAV') then
            debug('server response: criteria data version')
            achieverDB.categories.version = tonumber(params[3])
            ACHIEVER_STARTED = true
        elseif (params[2] == 'CR') then
            --debug('server response: get all criteria')
            local a = split(params[3], ";")
            local id = tonumber(a[1])
            achieverDB.criteria.data[id] = {}
            achieverDB.criteria.data[id].id = tonumber(id)
            achieverDB.criteria.data[id].achievementId = tonumber(a[2])
            achieverDB.criteria.data[id].type = tonumber(a[3])
            achieverDB.criteria.data[id].assetId = tonumber(a[4])
            achieverDB.criteria.data[id].count = tonumber(a[5])
            achieverDB.criteria.data[id].assetId1 = tonumber(a[6])
            achieverDB.criteria.data[id].count1 = tonumber(a[7])
            achieverDB.criteria.data[id].assetId2 = tonumber(a[8])
            achieverDB.criteria.data[id].count2 = tonumber(a[9])
            local name = ''
            if (a[10] ~= '_') then name = a[10] end
            achieverDB.criteria.data[id].name = name
            achieverDB.criteria.data[id].flags = tonumber(a[11])
            achieverDB.criteria.data[id].timedType = tonumber(a[12])
            achieverDB.criteria.data[id].timerStartEvent = tonumber(a[13])
            achieverDB.criteria.data[id].timeLimit = tonumber(a[14])
            achieverDB.criteria.data[id].order = tonumber(a[15])
            local n = tonumber(a[16])
            local c = tonumber(a[17])

            local achievementId = tonumber(a[2])
            if (achieverDB.criteria.byAchievement[achievementId] == nil) then
                achieverDB.criteria.byAchievement[achievementId] = {}
            end
            achieverDB.criteria.byAchievement[achievementId][tonumber(a[15])] = id
            -- table.insert(achieverDB.criteria.byAchievement[achievementId], id)
            ACHIEVER_STARTED = true

            if (n == c) then
                --debug('loaded criteria from server')
            end
        elseif (params[2] == 'CRV') then
            debug('server response: criteria data version')
            achieverDB.criteria.version = tonumber(params[3])
            ACHIEVER_STARTED = true
        elseif (params[2] == 'CH_AC') then
            --debug('server response: char achievements')
            local a = split(params[3], ";")
            local id = tonumber(a[1])
            achieverDBpc.achievements[id] = {}
            achieverDBpc.achievements[id].date = tonumber(a[2])
            ACHIEVER_STARTED = true
        elseif (params[2] == 'CH_CR') then
            --debug('server response: char criteria')
            local a = split(params[3], ";")
            local id = tonumber(a[1])
            achieverDBpc.criteria[id] = {}
            achieverDBpc.criteria[id].counter = tonumber(a[2])
            achieverDBpc.criteria[id].date = tonumber(a[3])
            ACHIEVER_STARTED = true
        elseif (params[2] == 'AE') then
            local a = split(params[3], ";")
            local id = tonumber(a[1])
            if (not achieverDBpc.achievements) then achieverDBpc.achievements = {} end
            achieverDBpc.achievements[id] = {}
            achieverDBpc.achievements[id].date = tonumber(a[2])
            if (_G['AchievementFrameAchievements'] and AchievementFrameAchievements_OnEvent) then
                AchievementFrameAchievements_OnEvent(_G['AchievementFrameAchievements'], 'ACHIEVEMENT_EARNED', id)
            end
            for k, v in pairs(self.achievementFrameSummaryCategorySubscribers) do
                AchievementFrameSummaryCategory_OnEvent(v, 'ACHIEVEMENT_EARNED', id)
            end
            if (AchievementFrameSummary_Update) then AchievementFrameSummary_Update() end
            -- AchievementFrameComparison_OnEvent(_G['AchievementFrameComparison'], 'ACHIEVEMENT_EARNED', id)
            debug("ACHIEVEMENT EARNED " .. achievementName(id))
            if (myAlertFrame_ShowAchievementEarned) then myAlertFrame_ShowAchievementEarned(id) end
            ACHIEVER_STARTED = true
        elseif (params[2] == 'ACU') then
            local a = split(params[3], ";")
            local id = tonumber(a[1])
            if (not achieverDBpc.criteria) then achieverDBpc.criteria = {} end
            achieverDBpc.criteria[id] = {}
            achieverDBpc.criteria[id].achievementId = tonumber(a[2])
            achieverDBpc.criteria[id].counter = tonumber(a[3])
            achieverDBpc.criteria[id].date = tonumber(a[4])
            if (_G['AchievementFrameAchievements'] and AchievementFrameAchievements_OnEvent) then
                AchievementFrameAchievements_OnEvent(_G['AchievementFrameAchievements'], 'CRITERIA_UPDATE', id)
            end
            if (_G['AchievementFrameStats'] and AchievementFrameStats_OnEvent) then
                AchievementFrameStats_OnEvent(_G['AchievementFrameStats'], 'CRITERIA_UPDATE', id)
            end
            debug("ACHIEVEMENT CRITERIA UPDATE " .. achievementName(tonumber(a[2])) .. '[' .. criteriaName(id) .. ']')
            ACHIEVER_STARTED = true
        else
            warn('server response: unhandled ' .. tostring(params[2]))
        end
    end
end

Achiever.apiEnableDataSend = function(self, version)

    debug('request to enable sending achievement info, ' .. version)
    self.lastSent = '.achievements enableAchiever ' .. version
    self.lastSentAt = GetTime()
    SendChatMessage(self.lastSent)
    --SendChatMessage('!achievements getCategoties ' .. version, 'CHANNEL', nil, Achiever.channelIndex)
end
Achiever.apiRequestCategoryInfo = function(self, version)

    --debug('requested information about categories from server, ' .. version)
    SendChatMessage('.achievements getCategories ' .. version)
    --SendChatMessage('!achievements getCategoties ' .. version, 'CHANNEL', nil, Achiever.channelIndex)
end
Achiever.apiRequestAchievementInfo = function(self, version)

    --debug('requested information about achievements from server, ' .. version)
    SendChatMessage('.achievements getAchievements ' .. version)
    --SendChatMessage('!achievements getAchievements ' .. version, 'CHANNEL', nil, Achiever.channelIndex)
end
Achiever.apiRequestCriteriaInfo = function(self, version)

    --debug('requested information about criteria from server, ' .. version)
    SendChatMessage('.achievements getCriteria ' .. version)
    --SendChatMessage('!achievements getCriteria ' .. version, 'CHANNEL', nil, Achiever.channelIndex)
end
Achiever.apiRequestCharacterCriteria = function(self)
    debug('requested character criteria progress from server')
    achieverDBpc.criteria = {}
    SendChatMessage('.achievements getCharacterCriteria')
    --SendChatMessage('!achievements getCharacterCriteria', 'CHANNEL', nil, Achiever.channelIndex)
end
Achiever.apiRequestCharacterAchievements = function(self)
    debug('requested character achievements from server')
    achieverDBpc.achievements = {}
    SendChatMessage('.achievements getCharacterAchievements')
    --SendChatMessage('.achievements getCharacterAchievements', 'CHANNEL', nil, Achiever.channelIndex)
end

Achiever.getChannelIndex = function(self, channelName)
    local lastVal = 0
    local chanList = { GetChannelList() }
    local result = nil
    for _, value in next, chanList do
        if value == channelName then
            result = lastVal
            break
        end
        lastVal = value
    end
    return result
end

Achiever.joinChannel = function(self)
    self.channelIndex = self:getChannelIndex(self.channel)
    if (self.channelIndex == nil) then
        JoinChannelByName(self.channel)
    else
        --self:startup()
    end
end

Achiever.applyDefaults = function(self)
    if (not achieverDBpc) then achieverDBpc = {} end
    if (not achieverDBpc.criteria) then achieverDBpc.criteria = {} end
    if (not achieverDBpc.achievements) then achieverDBpc.achievements = {} end
    if (not achieverDBpc.debug) then achieverDBpc.debug = "disabled" end
    if (not achieverDBpc.buttonsmall) then achieverDBpc.buttonsmall = "disabled"; if (Achiever_Minimap) then Achiever_Minimap:Hide() end end
    if (not achieverDBpc.buttonmain) then achieverDBpc.buttonmain = "enabled" end
    if (not achieverDBpc.version) then achieverDBpc.version = 0 end
end

local STARTUP_RETRY_DELAY = 6   -- seconds to wait for the first ACHI# reply before asking again
local STARTUP_MAX_ATTEMPTS = 3

local function after(seconds, func)
    if (C_Timer and C_Timer.After) then
        C_Timer.After(seconds, func)
    else
        func()
    end
end

local function resetDatabases()
    achieverDB = {}
    achieverDB.categories = { version = achieverDBpc.version }
    achieverDB.categories.data = {}
    achieverDB.categories.byParent = {}
    achieverDB.achievements = { version = achieverDBpc.version }
    achieverDB.achievements.totalPoints = 0
    achieverDB.achievements.data = {}
    achieverDB.achievements.byCategory = {}
    achieverDB.achievements.nextById = {}
    achieverDB.achievements.previousById = {}
    achieverDB.criteria = { version = achieverDBpc.version }
    achieverDB.criteria.data = {}
    achieverDB.criteria.byAchievement = {}
end

Achiever.startupAttempts = 0
Achiever.pendingRequest = false
Achiever.resetDatabases = resetDatabases

-- The server only sends the full data once per session (a /reload keeps the same session), so a finished
-- transfer is kept in the SavedVariables and reused after /reload.
local function nonEmpty(t) return type(t) == 'table' and next(t) ~= nil end
local function savedDataUsable()
    local db = achieverDB
    return type(db) == 'table' and db.complete == true and db.addonVersion == ACHIEVER_ADDON_VERSION
        and type(db.categories) == 'table' and nonEmpty(db.categories.data) and type(db.categories.byParent) == 'table'
        and type(db.achievements) == 'table' and nonEmpty(db.achievements.data) and type(db.achievements.byCategory) == 'table'
        and type(db.achievements.nextById) == 'table' and type(db.achievements.previousById) == 'table'
        and type(db.criteria) == 'table' and nonEmpty(db.criteria.data) and type(db.criteria.byAchievement) == 'table'
        and type(achieverDBpc) == 'table' and type(achieverDBpc.achievements) == 'table' and type(achieverDBpc.criteria) == 'table'
end

-- Classic 1.14 only lets addons call SendChatMessage from a hardware event (click / key press); calling it
-- from a login timer raises ADDON_ACTION_BLOCKED. So startup() only *arms* the request, and it is actually
-- sent from the first hardware event afterwards (world click, key press, opening the window, a slash command).
Achiever.startup = function(self)
    if (ACHIEVER_STARTED == true) then
        return
    end

    self:applyDefaults()
    self:installChatFilter()
    self:hookChatFrame(ChatFrame1)
    if (DEFAULT_CHAT_FRAME ~= ChatFrame1) then self:hookChatFrame(DEFAULT_CHAT_FRAME) end

    if (self.isReload and not self.forceReload and savedDataUsable()) then
        ACHIEVER_STARTED = true
        self.loadedFromSaved = true
        self.databasesReady = true
        debug('/reload: using the saved achievement data')
        return
    end

    -- fresh login (or no usable saved data): load everything from the server
    if (not self.databasesReady) then
        if (savedDataUsable()) then
            -- keep showing the saved data until the first fresh line arrives from the server
            self.stagedReset = true
        else
            resetDatabases()
        end
        self.databasesReady = true
    end

    self.armed = true
    self.pendingRequest = true
    debug('armed: data request goes out on the next click or key press')
end

-- Called from every hardware-event hook below.
Achiever.onHardwareEvent = function(self)
    if (not self.armed or not self.pendingRequest or ACHIEVER_STARTED == true) then return end
    self.pendingRequest = false
    self.startupAttempts = self.startupAttempts + 1
    debug('request data to UI (attempt ' .. self.startupAttempts .. ') ' .. achieverDBpc.version)
    self:apiEnableDataSend(achieverDBpc.version)

    -- No reply (server busy / command dropped)? Allow another try on a later click, a few times.
    after(STARTUP_RETRY_DELAY, function()
        if (ACHIEVER_STARTED == true) then return end
        if (self.startupAttempts < STARTUP_MAX_ATTEMPTS + 2) then
            self.pendingRequest = true
        else
            warn('no reply from the server to ".achievements enableAchiever". Is the Achiever server module enabled? (/acstatus)')
        end
    end)
end

Achiever.installHardwareEventHooks = function(self)
    if (self.hardwareHooksInstalled) then return end
    self.hardwareHooksInstalled = true
    local function fire() Achiever:onHardwareEvent() end
    -- clicking in the 3D world
    if (WorldFrame and WorldFrame.HookScript) then pcall(WorldFrame.HookScript, WorldFrame, 'OnMouseDown', fire) end
    -- any key press (listener only; the key is passed on to the game)
    local keys = CreateFrame('Frame', 'AchieverKeyListener', UIParent)
    keys:EnableKeyboard(true)
    if (keys.SetPropagateKeyboardInput) then keys:SetPropagateKeyboardInput(true) end
    keys:SetScript('OnKeyDown', function(_, key)
        if (keys.SetPropagateKeyboardInput) then keys:SetPropagateKeyboardInput(true) end
        fire()
    end)
    -- opening the window (button, binding, /achiever)
    if (AchievementFrame_ToggleAchievementFrame) then hooksecurefunc('AchievementFrame_ToggleAchievementFrame', fire) end
end

-- Redraw the open window shortly after the last server line arrived (debounced).
Achiever.scheduleUIRefresh = function(self)
    -- 2 s without any new server line: the transfer is finished, remember that for the next /reload
    self.completeToken = (self.completeToken or 0) + 1
    local completeToken = self.completeToken
    after(2, function()
        if (completeToken ~= self.completeToken) then return end
        if (type(achieverDB) == 'table' and nonEmpty(achieverDB.achievements and achieverDB.achievements.data)
            and nonEmpty(achieverDB.categories and achieverDB.categories.data)) then
            achieverDB.complete = true
            achieverDB.addonVersion = ACHIEVER_ADDON_VERSION
        end
    end)
    self.refreshToken = (self.refreshToken or 0) + 1
    local token = self.refreshToken
    after(0.5, function()
        if (token ~= self.refreshToken) then return end
        if (not (AchievementFrame and AchievementFrame:IsShown())) then return end
        pcall(function()
            if (AchievementFrameCategories_Update) then AchievementFrameCategories_Update() end
            if (AchievementFrameSummary and AchievementFrameSummary:IsShown()) then
                AchievementFrameSummary:Hide()
                AchievementFrameSummary:Show()
            end
            if (AchievementFrameAchievements and AchievementFrameAchievements:IsShown() and AchievementFrameAchievements_Update) then
                AchievementFrameAchievements_Update()
            end
            if (AchievementFrameStats and AchievementFrameStats:IsShown() and AchievementFrameStats_Update) then
                AchievementFrameStats_Update()
            end
        end)
    end)
end

-- Forget everything and ask the server again (/acrefresh). A slash command is a hardware event.
Achiever.refresh = function(self)
    ACHIEVER_STARTED = false
    self.startupAttempts = 0
    self.stats.received = 0
    achieverDBpc.criteria = {}
    achieverDBpc.achievements = {}
    self.databasesReady = false
    self.forceReload = true
    self.loadedFromSaved = false
    if (achieverDB) then achieverDB.complete = nil end
    self:startup()
    self:onHardwareEvent()
end

Achiever.printStatus = function(self)
    local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
    local function out(msg) DEFAULT_CHAT_FRAME:AddMessage('|cff66ccffAchiever:|r ' .. msg) end
    out('client build ' .. tostring((select(4, GetBuildInfo()))) .. ', addon ' .. self.version)
    if (self.loadedFromSaved) then out('using saved data from before the /reload (no server request needed)') end
    out('data received: ' .. (ACHIEVER_STARTED and 'yes' or 'NO') .. ' (' .. self.stats.received .. ' ACHI# lines, last type ' .. tostring(self.stats.lastType) .. ')')
    out('raw chat events seen: ' .. self.rawStats.events .. ', ACHI# lines via raw events: ' .. self.rawStats.achi)
    out('last sent: ' .. tostring(self.lastSent) .. (self.lastSentAt and (' (' .. math.floor(GetTime() - self.lastSentAt) .. 's ago)') or ''))
    if (#self.blocked > 0) then out('BLOCKED actions: ' .. table.concat(self.blocked, ', ')) end
    out('system lines seen by the filter: ' .. self.stats.systemSeen)
    out('via chat filter: ' .. self.stats.viaFilter .. ', via AddMessage hook: ' .. self.stats.viaHook .. ', processing errors: ' .. self.stats.errors)
    if (self.stats.lastError) then out('last error: ' .. self.stats.lastError) end
    out('categories ' .. count(achieverDB.categories.data) .. ', achievements ' .. count(achieverDB.achievements.data) ..
        ', criteria ' .. count(achieverDB.criteria.data))
    out('character: ' .. count(achieverDBpc.achievements) .. ' achievements, ' .. count(achieverDBpc.criteria) .. ' criteria')
    out('requests sent: ' .. self.startupAttempts .. ' (waiting for a click/key: ' .. tostring(self.pendingRequest == true) .. '); filter installed: ' .. tostring(self.filterInstalled == true))
    if (#self.recentSystem > 0) then
        out('last system messages seen:')
        for _, m in ipairs(self.recentSystem) do out('   ' .. string.gsub(m, '|', '||')) end
    end
    if (#self.recentRaw > 0) then
        out('last chat lines seen by the raw listener:')
        for _, m in ipairs(self.recentRaw) do out('   ' .. string.gsub(m, '|', '||')) end
    end
    if (self.stats.received == 0) then
        out('Nothing arrived from the server yet. The request is sent on your first click/key press; or type ".achievements enableAchiever 0" yourself.')
    end
end

SLASH_ACHIEVERSTATUS1 = "/acstatus"
SlashCmdList.ACHIEVERSTATUS = function()
    -- a slash command is a hardware event: send the pending request now, then report once a reply had time to arrive
    local sent = Achiever.pendingRequest and Achiever.armed and ACHIEVER_STARTED ~= true
    Achiever:onHardwareEvent()
    if (sent) then
        DEFAULT_CHAT_FRAME:AddMessage('|cff66ccffAchiever:|r request sent, status in 2 seconds...')
        after(2, function() Achiever:printStatus() end)
    else
        Achiever:printStatus()
    end
end

SLASH_ACHIEVERREFRESH1 = "/acrefresh"
SlashCmdList.ACHIEVERREFRESH = function() Achiever:refresh() end

Achiever:SetScript("OnEvent", function(self, event, arg1, arg2)
    if (event == "ADDON_LOADED" and arg1 == ACHIEVER_ADDON_NAME) then
        debug('ADDON_LOADED')
        Achiever:applyDefaults()
        Achiever:installChatFilter()
        Achiever:hookChatFrame(ChatFrame1)
    elseif (event == 'PLAYER_ENTERING_WORLD') then
        Achiever:installChatFilter()
        Achiever:hookChatFrame(ChatFrame1)
        Achiever:installHardwareEventHooks()
        if (not Achiever.startupScheduled) then Achiever.isReload = (arg2 == true) end
        -- PLAYER_ENTERING_WORLD also fires on every loading screen: only the first one starts the request
        if (not Achiever.startupScheduled) then
            Achiever.startupScheduled = true
            -- give the client a moment to finish logging in before talking to the server
            after(1, function() Achiever:startup() end)
        end
    end
end)

NEWBIE_TOOLTIP_ACHIEVEMENT = "View information about your achievements and statistics.";
TOGGLEACHIEVEMENTS = 'Open Achievements';
BINDING_HEADER_ACHIEVER = "Achiever";
BINDING_NAME_TOGGLEACHIEVEMENTS = "Show Achievements";

local function updateMicroButtonTooltip(button)
    local key = GetBindingKey("TOGGLEACHIEVEMENTS")
    if (key) then
        button.tooltipText = "Achievements" .. " " .. NORMAL_FONT_COLOR_CODE .. "(" .. key .. ")" .. FONT_COLOR_CODE_CLOSE
    else
        button.tooltipText = "Achievements"
    end
end

-- The icon is drawn from the shield art that ships with the addon (the 1.12-era micro button textures are not
-- loadable on 1.14: a missing texture renders as a solid green square).
function Achiever_UpdateMicroIcon(button, pressed)
    if (not button.icon) then return end
    button.icon:ClearAllPoints()
    if (pressed) then
        button.icon:SetPoint("BOTTOM", button, "BOTTOM", 1, 3)
        button.icon:SetAlpha(0.75)
    else
        button.icon:SetPoint("BOTTOM", button, "BOTTOM", 0, 4)
        button.icon:SetAlpha(1)
    end
end

function AchievementsMicroButton_OnLoad(self)
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    self:RegisterEvent("UPDATE_BINDINGS")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.icon = self:CreateTexture(nil, "ARTWORK")
    self.icon:SetSize(26, 26)
    self.icon:SetTexture("Interface\\AddOns\\Achiever\\textures\\UI-Achievement-Shields")
    self.icon:SetTexCoord(0, 0.5, 0, 1)
    Achiever_UpdateMicroIcon(self, false)
    self:SetHighlightTexture("Interface\\Buttons\\UI-MicroButton-Hilight")
    self:HookScript("OnMouseDown", function(btn) Achiever_UpdateMicroIcon(btn, true) end)
    self:HookScript("OnMouseUp", function(btn) Achiever_UpdateMicroIcon(btn, AchievementFrame and AchievementFrame:IsShown()) end)
    updateMicroButtonTooltip(self)
    self.newbieText = NEWBIE_TOOLTIP_ACHIEVEMENT
end

function AchievementsMicroButton_OnEvent(self, event, ...)
    if (event == "UPDATE_BINDINGS") then
        updateMicroButtonTooltip(self)
    elseif (event == "PLAYER_ENTERING_WORLD") then
        UpdateAchievementsButton()
    end
end

function AchievementsMicroButton_OnEnter(self)
    if (self.tooltipText) then
        Achiever_AddNewbieTip(self, self.tooltipText, 1.0, 1.0, 1.0, self.newbieText)
    end
end

-- The 1.14 micro menu has no free slot, so the Achievements button takes the place of the
-- Help button (hidden, like in the original addon) and copies its anchor.
local function placeMicroButton(button)
    if (button.achieverPlaced) then return end
    local parent = (CharacterMicroButton and CharacterMicroButton:GetParent()) or UIParent
    button:SetParent(parent)
    button:ClearAllPoints()
    if (HelpMicroButton and HelpMicroButton:GetNumPoints() > 0) then
        local point, relativeTo, relativePoint, x, y = HelpMicroButton:GetPoint(1)
        button:SetPoint(point, relativeTo, relativePoint, x, y)
    elseif (MainMenuMicroButton) then
        button:SetPoint("BOTTOMLEFT", MainMenuMicroButton, "BOTTOMRIGHT", -2, 0)
    else
        button:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    button.achieverPlaced = true
end

function UpdateAchievementsButton()
    local button = AchievementsMicroButton
    if (not button) then return end
    local db = achieverDBpc or {}

    if ((db.buttonmain or "enabled") == "enabled") then
        placeMicroButton(button)
        if (HelpMicroButton) then HelpMicroButton:Hide() end
        button:Show()
        Achiever_UpdateMicroIcon(button, AchievementFrame and AchievementFrame:IsShown())
        if (AchievementFrame and AchievementFrame:IsShown()) then
            button:SetButtonState("PUSHED", 1)
            if (SetButtonPulse) then SetButtonPulse(button, 0, 1) end
        else
            button:SetButtonState("NORMAL")
        end
    else
        button:Hide()
        if (HelpMicroButton) then HelpMicroButton:Show() end
    end

    if (Achiever_Minimap and (db.buttonsmall or "disabled") == "disabled") then
        Achiever_Minimap:Hide()
    end
end

local function toggleMainButton()
    if (achieverDBpc.buttonmain == "enabled") then
        achieverDBpc.buttonmain = "disabled"
        DEFAULT_CHAT_FRAME:AddMessage('Achiever main bar button disabled')
    else
        achieverDBpc.buttonmain = "enabled"
        DEFAULT_CHAT_FRAME:AddMessage('Achiever main bar button enabled')
    end
    UpdateAchievementsButton()
end

local function toggleSmallButton()
    if (achieverDBpc.buttonsmall == "enabled") then
        achieverDBpc.buttonsmall = "disabled"
        Achiever_Minimap:Hide();
        DEFAULT_CHAT_FRAME:AddMessage('Achiever movable button disabled')
    else
        achieverDBpc.buttonsmall = "enabled"
        Achiever_Minimap:Show();
        DEFAULT_CHAT_FRAME:AddMessage('Achiever movable button enabled')
    end
end

SLASH_ACHIEVERBUTTONMAIN1 = "/acbuttonmain"
SlashCmdList.ACHIEVERBUTTONMAIN = function()
    toggleMainButton()
end

SLASH_ACHIEVERBUTTONSMALL1 = "/acbuttonsmall"
SlashCmdList.ACHIEVERBUTTONSMALL = function()
    toggleSmallButton()
end
