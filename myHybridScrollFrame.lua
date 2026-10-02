local _G = _G
--[[-----------------------------------------------------------------------------------------------

-----------------------------------------------------------------------------------------------]]--

local function debug(msg)
	    -- DEFAULT_CHAT_FRAME:AddMessage('|cffc663fcDEBUG: |cffff55ff'.. (msg or 'nil'))
end
local function warn(msg)
	DEFAULT_CHAT_FRAME:AddMessage('|cf3f3f66cWARN: |cffff55ff'.. (msg or 'nil'))
end

local round = function (num) return math.floor(num + .5); end

function HybridScrollFrame_OnLoad (self)
	self:EnableMouse(true);
end

function HybridScrollFrame_OnValueChanged (self, value)
	HybridScrollFrame_SetOffset(self, value);
	HybridScrollFrame_UpdateButtonStates(self, value);
end

function HybridScrollFrame_UpdateButtonStates(self, currValue)
	if ( not currValue ) then
		currValue = self.scrollBar:GetValue();
	end

	self.scrollUp:Enable();
	self.scrollDown:Enable();

	local minVal, maxVal = self.scrollBar:GetMinMaxValues();

	if (not self.scrollBar.thumbTexture) then
		local thumbTextureName = self.scrollBar:GetName() .. 'ThumbTexture'
		self.scrollBar.thumbTexture = _G[thumbTextureName]
	end

	if ( currValue >= maxVal ) then
		self.scrollBar.thumbTexture:Show();
		if ( self.scrollDown ) then
			self.scrollDown:Disable()
		end
	end
	if ( currValue <= minVal ) then
		self.scrollBar.thumbTexture:Show();
		if ( self.scrollUp ) then
			self.scrollUp:Disable();
		end
	end
end

function HybridScrollFrame_OnMouseWheel (self, delta, stepSize)
	if ( not self.scrollBar:IsVisible() ) then
		return;
	end

	local minVal, maxVal = 0, self.range;
	stepSize = stepSize or self.stepSize or self.buttonHeight;
	if ( delta == 1 ) then
		self.scrollBar:SetValue(max(minVal, self.scrollBar:GetValue() - stepSize));
	else
		self.scrollBar:SetValue(min(maxVal, self.scrollBar:GetValue() + stepSize));
	end
end

function HybridScrollFrameScrollButton_OnUpdate (self, elapsed)
	self.timeSinceLast = self.timeSinceLast + elapsed;
	if ( self.timeSinceLast >= ( self.updateInterval or 0.08 ) ) then
		if ( not IsMouseButtonDown("LeftButton") ) then
			self:SetScript("OnUpdate", nil);
		elseif ( self:IsMouseOver() ) then
			local parent = self.parent or self:GetParent():GetParent();
			HybridScrollFrame_OnMouseWheel (parent, self.direction, (self.stepSize or parent.buttonHeight/3));
			self.timeSinceLast = 0;
		end
	end
end

function HybridScrollFrameScrollButton_OnClick (self, button, down)
	local parent = self.parent or self:GetParent():GetParent();

	if ( down ) then
		self.timeSinceLast = (self.timeToStart or -0.2);
		self:SetScript("OnUpdate", HybridScrollFrameScrollButton_OnUpdate);
		HybridScrollFrame_OnMouseWheel (parent, self.direction);
		PlaySound("UChatScrollButton");
	else
		self:SetScript("OnUpdate", nil);
	end
end

function HybridScrollFrame_Update (self, totalHeight, displayedHeight)
	-- Guard against invalid measurements (nil / NaN / <= 0). Feeding these into
	-- SetVerticalScroll/UpdateScrollChildRect on modern clients breaks clipping
	-- and makes rows render outside the scroll frame bounds.
	if ( type(totalHeight) ~= "number" or totalHeight ~= totalHeight ) then totalHeight = 0; end
	if ( type(displayedHeight) ~= "number" or displayedHeight ~= displayedHeight or displayedHeight <= 0 ) then
		displayedHeight = self:GetHeight();
	end
	local range = totalHeight - self:GetHeight();
	if ( range > 0 and self.scrollBar ) then
		local minVal, maxVal = self.scrollBar:GetMinMaxValues();
		if ( math.floor(self.scrollBar:GetValue()) >= math.floor(maxVal) ) then
			self.scrollBar:SetMinMaxValues(0, range)
			if ( math.floor(self.scrollBar:GetValue()) ~= math.floor(range) ) then
				self.scrollBar:SetValue(range);
			else
				HybridScrollFrame_SetOffset(self, range); -- If we've scrolled to the bottom, we need to recalculate the offset.
			end
		else
			self.scrollBar:SetMinMaxValues(0, range)
		end

		-- warn('HybridScrollFrame_Update Enable no working')
		-- self.scrollBar:Enable();

		HybridScrollFrame_UpdateButtonStates(self);
		self.scrollBar:Show();
	elseif ( self.scrollBar ) then
		self.scrollBar:SetValue(0);
		if ( self.scrollBar.doNotHide ) then
			self.scrollBar:Disable();
			self.scrollUp:Disable();
			self.scrollDown:Disable();
			self.scrollBar.thumbTexture:Hide();
		else
			self.scrollBar:Hide();
		end
	end

	self.range = range;
	self.scrollChild:SetHeight(displayedHeight);
	self:UpdateScrollChildRect();
end

-- WoW 1.14.x regression fix: in vanilla the hybrid scroller only ever called
-- UpdateScrollChildRect() from CreateButtons and Update(). On Classic (42597)
-- SetVerticalScroll() no longer refreshes the child clip region as a side
-- effect, so after the first programmatic scroll the child stays clipped to
-- its stale rect -- rows appear to ignore the parent's clipping bounds and
-- overflow down the screen. Re-clamp the scrollbar value here and always
-- refresh the scroll child rect after changing the vertical offset.
local originalSetOffset = HybridScrollFrame_SetOffset
function HybridScrollFrame_SetOffset (self, offset)
	originalSetOffset(self, offset);
	local scrollBar = self.scrollBar;
	if ( scrollBar ) then
		local minVal, maxVal = scrollBar:GetMinMaxValues();
		if ( type(minVal) ~= "number" or type(maxVal) ~= "number" or maxVal < 0 ) then
			scrollBar:SetMinMaxValues(0, math.max((self.range or 0), 0));
		elseif ( scrollBar:GetValue() > maxVal ) then
			scrollBar:SetValue(maxVal);
		end
	end
	self:UpdateScrollChildRect();
end

function HybridScrollFrame_GetOffset (self)
	return math.floor(self.offset or 0), (self.offset or 0);
end

function HybridScrollFrameScrollChild_OnLoad (self)
	self:GetParent().scrollChild = self;
end

function HybridScrollFrame_ExpandButton (self, offset, height)
	self.largeButtonTop = round(offset);
	self.largeButtonHeight = round(height)
	HybridScrollFrame_SetOffset(self, self.scrollBar:GetValue());
end

function HybridScrollFrame_CollapseButton (self)
	self.largeButtonTop = nil;
	self.largeButtonHeight = nil;
end

function HybridScrollFrame_SetOffset (self, offset)
	local buttons = self.buttons
	local buttonHeight = self.buttonHeight;
	local element, overflow;

	local scrollHeight = 0;

	local largeButtonTop = self.largeButtonTop
	if ( largeButtonTop and offset >= largeButtonTop ) then
		local largeButtonHeight = self.largeButtonHeight;
		-- Initial offset...
		element = largeButtonTop / buttonHeight;

		if ( offset >= (largeButtonTop + largeButtonHeight) ) then
			element = element + 1;

			local leftovers = (offset - (largeButtonTop + largeButtonHeight) );

			element = element + ( leftovers / buttonHeight );
			overflow = element - math.floor(element);
			scrollHeight = overflow * buttonHeight;
		else
			scrollHeight = math.abs(offset - largeButtonTop);
		end
	else
		element = offset / buttonHeight;
		overflow = element - math.floor(element);
		scrollHeight = overflow * buttonHeight;
	end

	-- Only re-run the update function when the whole-row offset actually
	-- changed, and never re-enter it while it is already running (the update
	-- function calls back into HybridScrollFrame_Update -> SetOffset). Without
	-- this guard, expanding/collapsing rows can trigger an infinite recursion
	-- that spawns frames endlessly on top of each other.
	if ( math.floor(self.offset or 0) ~= math.floor(element) and self.update and not self.updating ) then
		self.offset = element;
		self.updating = true;
		self.update();
		self.updating = nil;
	else
		self.offset = element;
	end

	self:SetVerticalScroll(scrollHeight);
end

function HybridScrollFrame_CreateButtons (self, buttonTemplate, initialOffsetX, initialOffsetY, initialPoint, initialRelative, offsetX, offsetY, point, relativePoint)
	debug('HybridScrollFrame_CreateButtons' .. self:GetName() .. ' ' .. buttonTemplate .. ' ')
	local scrollChild = self.scrollChild;
	local button, buttonHeight, buttons, numButtons;

	local buttonName = self:GetName() .. "Button";

	initialPoint = initialPoint or "TOPLEFT";
	initialRelative = initialRelative or "TOPLEFT";
	point = point or "TOPLEFT";
	relativePoint = relativePoint or "BOTTOMLEFT";
	offsetX = offsetX or 0;
	offsetY = offsetY or 0;

	if ( self.buttons ) then
		buttons = self.buttons;
		buttonHeight = buttons[1]:GetHeight();
	else
		button = CreateFrame("BUTTON", buttonName .. 1, scrollChild, buttonTemplate);
		buttonHeight = button:GetHeight();
		button:SetPoint(initialPoint, scrollChild, initialRelative, initialOffsetX, initialOffsetY);
		buttons = {}
		tinsert(buttons, button);
	end

	self.buttonHeight = round(buttonHeight);

	numButtons = math.ceil(self:GetHeight() / buttonHeight) + 1;

	-- Recycle existing pooled buttons; only create the ones we are missing.
	local buttonCount = table.getn(buttons)
	for i = buttonCount + 1, numButtons do
		button = CreateFrame("BUTTON", buttonName .. i, scrollChild, buttonTemplate);
		button:SetPoint(point, buttons[i-1], relativePoint, offsetX, offsetY);
		tinsert(buttons, button);
	end

	-- Reset every pooled button: clear leftover anchors (so vertically stacked
	-- rows can't overlap after a re-create), uncollapse/hide them and drop any
	-- stale id/index bindings from a previous session.
	for i = 1, numButtons do
		button = buttons[i];
		button:ClearAllPoints();
		if ( i == 1 ) then
			button:SetPoint(initialPoint, scrollChild, initialRelative, initialOffsetX, initialOffsetY);
		else
			button:SetPoint(point, buttons[i-1], relativePoint, offsetX, offsetY);
		end
		button.id = nil;
		button.element = nil;
		if ( button.Collapse ) then button:Collapse(); end
		button:Hide();
	end

	scrollChild:SetWidth(self:GetWidth())
	scrollChild:SetHeight(numButtons * buttonHeight);
	self.largeButtonTop = nil;
	self.largeButtonHeight = nil;
	self.offset = 0;
	self:SetVerticalScroll(0);
	self:UpdateScrollChildRect();

	self.buttons = buttons;
	local scrollBar = self.scrollBar;
	if ( scrollBar ) then
		scrollBar:SetMinMaxValues(0, math.max((numButtons * buttonHeight) - self:GetHeight(), 0))
		scrollBar:SetValueStep(.005);
		scrollBar:SetValue(0);
	end
end
