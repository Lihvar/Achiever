local function warn(msg)
	DEFAULT_CHAT_FRAME:AddMessage('|cf3f3f66cWARN: |cffff55ff'.. (msg or 'nil'))
end

SLASH_ACHIEVERALERT1 = "/acal"
SlashCmdList.ACHIEVERALERT = function(id)
	myAlertFrame_ShowAchievementEarned(tonumber(id))
end

local config = {}

-- original values
-- config.alert = {}
-- config.alert.anchor = {}
-- config.alert.anchor.parentSide = 'BOTTOM'
-- config.alert.anchor.x = 0
-- config.alert.anchor.y = 128
-- config.alert.growUp = true
-- config.alert.max = 2
-- config.alert.tryAttachToRollFrame = true


-- my values
config.alert = {}
config.alert.anchor = {}
config.alert.anchor.parentSide = 'BOTTOM'
config.alert.anchor.x = 0
config.alert.anchor.y = 100 ---68 ---216
config.alert.growUp = true
config.alert.max = 5
config.alert.tryAttachToRollFrame = false

MAX_ACHIEVEMENT_ALERTS = config.alert.max;

function myAlertFrame_ShowAchievementEarned(id)
	if (id == nil) then
        warn('provide an achievement id')
        return
    end
    local x = achieverDB.achievements.data[tonumber(id)]
    if (x == nil) then
        warn('no achievement with id ' .. id)
        return
    end
	-- if ( not AchievementFrame ) then
	-- 	AchievementFrame_LoadUI();
	-- end
	AchieverAlertFrame_ShowAlert(tonumber(id))
end

function myAlertFrame_FixAnchors()
	AchieverAlertFrame_FixAnchors();
end

function myAlertFrame_AnimateIn(frame)
	frame:SetScript("OnUpdate", AchieverAlertFrame_OnUpdate);
	frame.oldFrameTime = GetTime()
	frame.elapsed = 0
	frame.fadeinDuration = 0.2;
	frame.flashDuration = 0.5;
	frame.shineStartTime = 0.3;
	frame.shineDuration = 0.85;
	frame.holdDuration = 3;
	frame.fadeoutDuration = 1.5;
	frame.wait = false
	frame:Show();
end

function myAlertFrame_StopOutAnimation(frame)
	frame.wait = true
	frame:SetAlpha(1);
	frame.elapsed = 0;
	-- frame.waitAndAnimOut:Stop();
	-- frame.waitAndAnimOut.animOut:SetStartDelay(1);
end

function myAlertFrame_ResumeOutAnimation(frame)
	frame.wait = false
	-- frame.waitAndAnimOut:Play();
end

-- [[ AchieverAlertFrame ]] --
function AchieverAlertFrame_OnLoad (self)
	self.glow = _G[self:GetName() .. "Glow"];
	self.shine = _G[self:GetName() .. "Shine"];
	self:RegisterForClicks("LeftButtonUp");
end

function AchieverAlertFrame_FixAnchors ()
	-- Temporary (here's hoping) workaround so that achievement alerts are anchored to loot roll windows. Eventually we want one system to handle placement for both alerts.
	if ( not AchieverAlertFrame1 ) then
		-- We haven't displayed any achievement alerts yet, so there's nothing to reanchor (read: this got called by LootFrame.lua)
		return;
	end
	if (not config.alert.tryAttachToRollFrame) then return end

	for i=NUM_GROUP_LOOT_FRAMES, 1, -1  do
		local frame = _G["GroupLootFrame"..i];
		if ( frame and frame:IsShown() ) then
			AchieverAlertFrame1:SetPoint("BOTTOM", frame, "TOP", 0, 10);
			return;
		end
	end

	AchieverAlertFrame1:SetPoint("BOTTOM", UIParent, config.alert.anchor.parentSide, config.alert.anchor.x, config.alert.anchor.y);
end

function AchieverAlertFrame_ShowAlert (achievementID)
	PlaySoundFile([[Interface\AddOns\Achiever\sounds\AchievementEarned.mp3]], 'SFX');
	local frame = AchieverAlertFrame_GetAlertFrame();
	local _, name, points, completed, month, day, year, description, flags, icon = GetAchievementInfo(achievementID);
	if ( not frame ) then
		-- We ran out of frames! Bail!
		return;
	end

	local nameString = _G[frame:GetName() .. "Name"];
	if ( not nameString ) then
		warn("alert frame template is incomplete (" .. frame:GetName() .. "Name is missing)");
		return;
	end
	nameString:SetText(name);

	local shield = _G[frame:GetName() .. "Shield"];
	AchievementShield_SetPoints(points, shield.points, GameFontNormal, GameFontNormalSmall);
	if ( points == 0 ) then
		shield.icon:SetTexture([[Interface\AddOns\Achiever\textures\UI-Achievement-Shields-NoPoints]]);
	else
		shield.icon:SetTexture([[Interface\AddOns\Achiever\textures\UI-Achievement-Shields]]);
	end

	if (icon) then
		local iconFromTable = iconTable[icon]
		if (iconFromTable) then
			_G[frame:GetName() .. "IconTexture"]:SetTexture(iconFromTable);
			_G[frame:GetName() .. "IconTexture"]:SetTexture([[Interface\AddOns\Achiever\textures\]] .. iconFromTable);
		end
	end

	frame.id = achievementID;

	myAlertFrame_AnimateIn(frame);

	myAlertFrame_FixAnchors();

	if ( SetButtonPulse and AchievementsMicroButton and not AchievementFrame:IsShown() ) then
		SetButtonPulse(AchievementsMicroButton, 60, 1)
	end
end

function AchieverAlertFrame_GetAlertFrame()
	local name, frame, previousFrame;
	for i=1, config.alert.max do
		name = "AchieverAlertFrame"..i;
		frame = _G[name];
		if ( frame ) then
			if ( not frame:IsShown() ) then
				return frame;
			end
		else
			frame = CreateFrame("Button", name, UIParent, "AchieverAlertTemplate");
			if ( not previousFrame ) then
				frame:SetPoint("BOTTOM", UIParent, config.alert.anchor.parentSide, config.alert.anchor.x, config.alert.anchor.y);
			else
				if (config.alert.growUp) then
					frame:SetPoint("BOTTOM", previousFrame, "TOP", 0, -10);
				else
					frame:SetPoint("BOTTOM", previousFrame, "BOTTOM", 0, -88);
				end
			end
			return frame;
		end
		previousFrame = frame;
	end
	return nil;
end

function AchieverAlertFrame_OnClick (self)
	local id = self.id;
	if ( not id ) then
		return;
	end

	CloseAllWindows();
	Achiever_ShowPanel(AchievementFrame);

	local _, _, _, achCompleted = GetAchievementInfo(id);
	if ( achCompleted and (ACHIEVEMENTUI_SELECTEDFILTER == AchievementFrameFilters[ACHIEVEMENT_FILTER_INCOMPLETE].func) ) then
		AchievementFrame_SetFilter(ACHIEVEMENT_FILTER_ALL);
	elseif ( (not achCompleted) and (ACHIEVEMENTUI_SELECTEDFILTER == AchievementFrameFilters[ACHIEVEMENT_FILTER_COMPLETE].func) ) then
		AchievementFrame_SetFilter(ACHIEVEMENT_FILTER_ALL);
	end

	AchievementFrame_SelectAchievement(id)
end

function AchieverAlertFrame_OnHide (self)
	myAlertFrame_FixAnchors();
end

function AchieverAlertFrame_OnUpdate(self)
	local newFrameTime = GetTime()
	local elapsed = newFrameTime - self.oldFrameTime
	self.oldFrameTime = newFrameTime

	local state = self.state;
	local alpha;
	local deltaTime = elapsed;
	--initialize
	if ( not state ) then
		state = "fadein";
		self.glow:Show();
		self.glow:SetAlpha(0);
		self.totalElapsed = 0;
	end
	self.totalElapsed = self.totalElapsed+elapsed;
	elapsed = self.elapsed + elapsed;
	if ( state == "fadein" ) then
		if ( elapsed >= self.fadeinDuration ) then
			state = "flash";
			elapsed = 0;
			self:SetAlpha(1);
			self.glow:Show();
		else
			self:SetAlpha(elapsed/self.fadeinDuration);
			self.glow:SetAlpha(elapsed/self.fadeinDuration);
		end
	elseif ( state == "flash" ) then
		if ( elapsed >= self.flashDuration ) then
			state = "hold";
			elapsed = 0;
			self.glow:Hide();
		else
			self.glow:SetAlpha(1-(elapsed/self.flashDuration));
		end
	elseif ( state == "hold" and not self.wait) then
		if ( elapsed >= self.holdDuration ) then
			state = "fadeout";
			elapsed = 0;
		end
	elseif ( state == "fadeout" and not self.wait) then
		if ( elapsed >= self.fadeoutDuration ) then
			state = nil;
			self:SetScript("OnUpdate", nil);
			self:Hide();
			self.id = nil;
		else
			self:SetAlpha(1-(elapsed/self.fadeoutDuration));
		end
	end

	--Handle shine
	local normalizedTime = self.totalElapsed - self.shineStartTime;
	if ( normalizedTime >= 0 and normalizedTime <= self.shineDuration ) then
		if ( not self.shine:IsShown() ) then
			self.shine:Show();
			self.shine:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -8);
			self.shine:SetAlpha(1);
		end
		local target = 239;
		local _,_,_,x = self.shine:GetPoint();
		if ( x ~= target ) then
			x = x +(target-x)*(deltaTime/(self.shineDuration/3));
			if ( floor(abs(target - x)) == 0 ) then
				x = target;
			end
		end

		self.shine:SetPoint("TOPLEFT", self, "TOPLEFT", x, -8);
		self.shine:SetAlpha(1);
		local startShineFade = 0.8*self.shineDuration;
		if ( normalizedTime >= startShineFade ) then
			self.shine:SetAlpha(1-((normalizedTime-startShineFade)/(self.shineDuration-startShineFade)));
		end
	else
		if ( self.shine:IsShown() ) then
			self.shine:Hide();
			self.vel = nil;
		end
	end

	self.state = state;
	self.elapsed = elapsed;
end
