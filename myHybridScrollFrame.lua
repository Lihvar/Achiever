--[[-----------------------------------------------------------------------------------------------

-----------------------------------------------------------------------------------------------]]--

local function debug(msg)
	    -- DEFAULT_CHAT_FRAME:AddMessage('|cffc663fcDEBUG: |cffff55ff'.. (msg or 'nil'))
end
local function warn(msg)
	DEFAULT_CHAT_FRAME:AddMessage('|cf3f3f66cWARN: |cffff55ff'.. (msg or 'nil'))
end

local round = function (num) return math.floor(num + .5); end

function myHybridScrollFrame_OnLoad (self)
	self:EnableMouse(true);
end

function myHybridScrollFrame_OnValueChanged (self, value)
	myHybridScrollFrame_SetOffset(self, value);
	myHybridScrollFrame_UpdateButtonStates(self, value);
end

function myHybridScrollFrame_UpdateButtonStates(self, currValue)
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

function myHybridScrollFrame_OnMouseWheel (self, delta, stepSize)
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

function myHybridScrollFrameScrollButton_OnUpdate (self, elapsed)
	self.timeSinceLast = self.timeSinceLast + elapsed;
	if ( self.timeSinceLast >= ( self.updateInterval or 0.08 ) ) then
		if ( not IsMouseButtonDown("LeftButton") ) then
			self:SetScript("OnUpdate", nil);
		elseif ( self:IsMouseOver() ) then
			local parent = self.parent or self:GetParent():GetParent();
			myHybridScrollFrame_OnMouseWheel (parent, self.direction, (self.stepSize or parent.buttonHeight/3));
			self.timeSinceLast = 0;
		end
	end
end

function myHybridScrollFrameScrollButton_OnClick (self, button, down)
	local parent = self.parent or self:GetParent():GetParent();

	if ( down ) then
		self.timeSinceLast = (self.timeToStart or -0.2);
		self:SetScript("OnUpdate", myHybridScrollFrameScrollButton_OnUpdate);
		myHybridScrollFrame_OnMouseWheel (parent, self.direction);
		Achiever_PlaySound("UChatScrollButton");
	else
		self:SetScript("OnUpdate", nil);
	end
end

function myHybridScrollFrame_Update (self, totalHeight, displayedHeight)
	local range = totalHeight - self:GetHeight();
	if ( range > 0 and self.scrollBar ) then
		local minVal, maxVal = self.scrollBar:GetMinMaxValues();
		if ( math.floor(self.scrollBar:GetValue()) >= math.floor(maxVal) ) then
			self.scrollBar:SetMinMaxValues(0, range)
			if ( math.floor(self.scrollBar:GetValue()) ~= math.floor(range) ) then
				self.scrollBar:SetValue(range);
			else
				myHybridScrollFrame_SetOffset(self, range); -- If we've scrolled to the bottom, we need to recalculate the offset.
			end
		else
			self.scrollBar:SetMinMaxValues(0, range)
		end

		-- warn('myHybridScrollFrame_Update Enable no working')
		-- self.scrollBar:Enable();

		myHybridScrollFrame_UpdateButtonStates(self);
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

function myHybridScrollFrame_GetOffset (self)
	return math.floor(self.offset or 0), (self.offset or 0);
end

function myHybridScrollFrameScrollChild_OnLoad (self)
	self:GetParent().scrollChild = self;
end

function myHybridScrollFrame_ExpandButton (self, offset, height)
	self.largeButtonTop = round(offset);
	self.largeButtonHeight = round(height)
	myHybridScrollFrame_SetOffset(self, self.scrollBar:GetValue());
end

function myHybridScrollFrame_CollapseButton (self)
	self.largeButtonTop = nil;
	self.largeButtonHeight = nil;
end

function myHybridScrollFrame_SetOffset (self, offset)
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

	if ( math.floor(self.offset or 0) ~= math.floor(element) and self.update ) then
		self.offset = element;
		self.update();
	else
		self.offset = element;
	end

	self:SetVerticalScroll(scrollHeight);
end

function myHybridScrollFrame_CreateButtons (self, buttonTemplate, initialOffsetX, initialOffsetY, initialPoint, initialRelative, offsetX, offsetY, point, relativePoint)
	debug('myHybridScrollFrame_CreateButtons' .. self:GetName() .. ' ' .. buttonTemplate .. ' ')
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

	local numButtons = math.ceil(self:GetHeight() / buttonHeight) + 1;

	local buttonCount = #buttons
	for i = buttonCount + 1, numButtons do
		button = CreateFrame("BUTTON", buttonName .. i, scrollChild, buttonTemplate);
		button:SetPoint(point, buttons[i-1], relativePoint, offsetX, offsetY);
		tinsert(buttons, button);
	end

	scrollChild:SetWidth(self:GetWidth())
	scrollChild:SetHeight(numButtons * buttonHeight);
	self:SetVerticalScroll(0);
	self:UpdateScrollChildRect();

	self.buttons = buttons;
	local scrollBar = self.scrollBar;
	scrollBar:SetMinMaxValues(0, numButtons * buttonHeight)
	scrollBar:SetValueStep(.005);
	scrollBar:SetValue(0);
end
