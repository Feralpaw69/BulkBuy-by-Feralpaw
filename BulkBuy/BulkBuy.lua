-- BulkBuy (WoW 3.3.5a)
-- Shift-click a vendor item -> type any amount -> it is bought stack by stack.

local INTERVAL = 0.15 -- seconds between purchases

local job -- { index, name, remaining, maxStack, unitPrice }
local runner = CreateFrame("Frame")
runner:Hide()

local function Stop(msg)
	job = nil
	runner:Hide()
	if msg then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99BulkBuy:|r " .. msg)
	end
end

local timer = 0
runner:SetScript("OnUpdate", function(self, elapsed)
	timer = timer + elapsed
	if timer < INTERVAL then return end
	timer = 0

	if not job then self:Hide() return end
	if not MerchantFrame:IsShown() then
		return Stop("vendor closed, " .. job.remaining .. " not bought.")
	end
	-- make sure the slot still holds the same item
	if GetMerchantItemInfo(job.index) ~= job.name then
		return Stop("vendor list changed, stopped.")
	end

	local n = math.min(job.remaining, job.maxStack)
	if GetMoney() < job.unitPrice * n then
		return Stop("not enough money, " .. job.remaining .. " not bought.")
	end

	BuyMerchantItem(job.index, n)
	job.remaining = job.remaining - n
	if job.remaining <= 0 then
		Stop()
	end
end)

-- stop when bags are full
runner:RegisterEvent("UI_ERROR_MESSAGE")
runner:RegisterEvent("MERCHANT_CLOSED")
runner:SetScript("OnEvent", function(self, event, msg)
	if not job then return end
	if event == "MERCHANT_CLOSED" then
		Stop("vendor closed, " .. job.remaining .. " not bought.")
	elseif msg == ERR_INV_FULL or msg == INVENTORY_FULL then
		Stop("bags are full, stopped.")
	end
end)

local function StartBuying(index, amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount < 1 then return end

	local name, _, price, batch, numAvailable = GetMerchantItemInfo(index)
	if not name then return end
	batch = (batch and batch > 0) and batch or 1

	-- limited stock: never try to buy more than the vendor has
	if numAvailable and numAvailable >= 0 and amount > numAvailable then
		amount = numAvailable
	end
	if amount < 1 then return end

	local maxStack = GetMerchantItemMaxStack(index) or 1
	if maxStack < 1 then maxStack = 1 end

	job = {
		index = index,
		name = name,
		remaining = amount,
		maxStack = maxStack,
		unitPrice = (price or 0) / batch,
	}
	timer = INTERVAL -- first purchase immediately
	runner:Show()
end

StaticPopupDialogs["BULKBUY_AMOUNT"] = {
	text = "How many %s do you want to buy?",
	button1 = OKAY,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 5,
	OnShow = function(self)
		self.editBox:SetNumeric(true)
		self.editBox:SetText("")
		self.editBox:SetFocus()
	end,
	OnHide = function(self)
		self.editBox:SetNumeric(false)
		self.editBox:SetText("")
	end,
	OnAccept = function(self, data)
		StartBuying(data, self.editBox:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		StartBuying(parent.data, self:GetText())
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

-- Replace the default shift-click behaviour on the vendor's buy tab
local Orig_OnModifiedClick = MerchantItemButton_OnModifiedClick

function MerchantItemButton_OnModifiedClick(self, button, ...)
	if MerchantFrame.selectedTab == 1 and IsModifiedClick("SPLITSTACK") and not self.extendedCost then
		local index = self:GetID()
		local link = GetMerchantItemLink(index)
		-- keep shift-click linking into an open chat box working
		if link and HandleModifiedItemClick(link) then
			return
		end
		local name = GetMerchantItemInfo(index)
		if name then
			local dialog = StaticPopup_Show("BULKBUY_AMOUNT", link or name)
			if dialog then
				dialog.data = index
			end
			return
		end
	end
	return Orig_OnModifiedClick(self, button, ...)
end
