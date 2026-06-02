--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(ReplicatedStorage:WaitForChild("DataService")).client
local DataDebugClient = require(script.Parent.DataDebugClient)
local SaveSlotUi = ReplicatedStorage:WaitForChild("Client"):WaitForChild("SaveSlots"):WaitForChild("UI")
local Theme = require(SaveSlotUi:WaitForChild("Theme"))
local createElement = require(SaveSlotUi:WaitForChild("CreateElement"))

local DataDebugPanel = {}
DataDebugPanel.__index = DataDebugPanel

type DataDebugPanelOptions = {
	onSwitchSlot: (() -> ())?,
}

local function addCorner(parent: Instance, radius: number)
	createElement("UICorner", {
		CornerRadius = UDim.new(0, radius),
		Parent = parent,
	})
end

local function makeButton(text: string, color: Color3, parent: Instance): TextButton
	local button = createElement("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Font = Theme.fonts.medium,
		Size = UDim2.new(1, 0, 0, 34),
		Text = text,
		TextColor3 = Theme.colors.text,
		TextSize = 14,
		Parent = parent,
	}) :: TextButton
	addCorner(button, Theme.radius.control)
	return button
end

local function summarize(data: any): string
	if type(data) ~= "table" then
		return "No data loaded"
	end

	local inventory = data.inventory
	local stats = data.stats or {}
	local settings = data.settings or {}
	local itemCount = if type(inventory) == "table" then #inventory else 0

	return `Currency: {data.currency or 0} | Level: {stats.level or 1} | Items: {itemCount} | Music: {settings.music or 0}`
end

function DataDebugPanel.new(options: DataDebugPanelOptions?)
	return setmetatable({
		gui = nil :: ScreenGui?,
		summaryLabel = nil :: TextLabel?,
		logLabel = nil :: TextLabel?,
		onSwitchSlot = if options then options.onSwitchSlot else nil,
		connections = {} :: { RBXScriptConnection },
		dataConnections = {} :: { RBXScriptConnection },
	}, DataDebugPanel)
end

function DataDebugPanel.mount(self: any): ()
	DataDebugClient:init()

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local colors = Theme.colors

	local gui = createElement("ScreenGui", {
		Name = "DataDebugPanel",
		IgnoreGuiInset = false,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui

	local panel = createElement("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = colors.panel,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -18, 1, -18),
		Size = UDim2.new(0, 360, 0, 480),
		Parent = gui,
	})
	addCorner(panel, Theme.radius.panel)
	createElement("UIStroke", {
		Color = colors.border,
		Thickness = 1,
		Transparency = 0.2,
		Parent = panel,
	})

	createElement("UIPadding", {
		PaddingTop = UDim.new(0, 16),
		PaddingBottom = UDim.new(0, 16),
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
		Parent = panel,
	})

	createElement("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.fonts.title,
		Size = UDim2.new(1, 0, 0, 28),
		Text = "DataService Debug",
		TextColor3 = colors.text,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})

	local summaryLabel = createElement("TextLabel", {
		BackgroundColor3 = colors.panelRaised,
		BorderSizePixel = 0,
		Font = Theme.fonts.body,
		Position = UDim2.new(0, 0, 0, 42),
		Size = UDim2.new(1, 0, 0, 52),
		Text = summarize(DataService:get()),
		TextColor3 = colors.text,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = panel,
	}) :: TextLabel
	addCorner(summaryLabel, Theme.radius.control)
	createElement("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = summaryLabel,
	})

	local buttonList = createElement("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 108),
		Size = UDim2.new(1, 0, 0, 300),
		Parent = panel,
	})

	createElement("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = buttonList,
	})

	local logLabel = createElement("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.fonts.body,
		Position = UDim2.new(0, 0, 1, -24),
		Size = UDim2.new(1, 0, 0, 22),
		Text = "Ready. Watch Output for debug prints.",
		TextColor3 = colors.textMuted,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	}) :: TextLabel

	self.gui = gui
	self.summaryLabel = summaryLabel
	self.logLabel = logLabel

	table.insert(
		self.connections,
		DataService:onDataChanged(function()
			self:_wireDataSignals()
			self:_refresh()
		end)
	)
	self:_wireDataSignals()

	makeButton("+25 Currency", colors.accent, buttonList).Activated:Connect(function()
		self:_runAction("addCurrency", function()
			return DataDebugClient:addCurrency(25)
		end)
	end)

	makeButton("Add Debug Item", colors.accent, buttonList).Activated:Connect(function()
		self:_runAction("addItem", function()
			return DataDebugClient:addItem()
		end)
	end)

	makeButton("Level Up", colors.accent, buttonList).Activated:Connect(function()
		self:_runAction("levelUp", function()
			return DataDebugClient:levelUp()
		end)
	end)

	makeButton("Set Music 50", colors.panelMuted, buttonList).Activated:Connect(function()
		self:_runAction("setMusic", function()
			return DataDebugClient:setMusic(50)
		end)
	end)

	makeButton("Force Save Now", colors.success, buttonList).Activated:Connect(function()
		self:_runAction("saveNow", function()
			return DataDebugClient:saveNow()
		end)
	end)

	makeButton("Switch Slot", colors.panelMuted, buttonList).Activated:Connect(function()
		self:_setLog("Opening save slot picker...")
		print("[DataDebugPanel] Button pressed: switchSlot")

		if self.onSwitchSlot then
			self.onSwitchSlot()
		end
	end)

	makeButton("Print Snapshot", colors.panelMuted, buttonList).Activated:Connect(function()
		self:_runAction("printSnapshot", function()
			return DataDebugClient:printSnapshot()
		end)
	end)

	print("[DataDebugPanel] Mounted. Client data snapshot:", DataService:get())
end

function DataDebugPanel._wireDataSignals(self: any): ()
	self:_disconnectDataSignals()

	if not DataService:hasData() then
		return
	end

	table.insert(
		self.dataConnections,
		DataService:getChangedSignal({ "currency" }):Connect(function(value, previous)
			print(`[DataDebugPanel] Currency changed from {previous} to {value}`)
			self:_refresh()
		end)
	)

	table.insert(
		self.dataConnections,
		DataService:getChangedSignal({ "stats", "level" }):Connect(function(value, previous)
			print(`[DataDebugPanel] Level changed from {previous} to {value}`)
			self:_refresh()
		end)
	)

	table.insert(
		self.dataConnections,
		DataService:getArrayInsertedSignal({ "inventory" }):Connect(function(index, value)
			print(`[DataDebugPanel] Inventory item inserted at {index}:`, value)
			self:_refresh()
		end)
	)

	table.insert(
		self.dataConnections,
		DataService:getChangedSignal({ "settings", "music" }):Connect(function(value, previous)
			print(`[DataDebugPanel] Music changed from {previous} to {value}`)
			self:_refresh()
		end)
	)
end

function DataDebugPanel._disconnectDataSignals(self: any): ()
	for _, connection in self.dataConnections do
		connection:Disconnect()
	end

	table.clear(self.dataConnections)
end

function DataDebugPanel._runAction(self: any, actionName: string, callback: () -> any): ()
	self:_setLog(`Running {actionName}...`)
	print(`[DataDebugPanel] Button pressed: {actionName}`)

	local result = callback()
	if result and result.loaded then
		self:_setLog(`Completed {actionName}`)
		self:_refresh(result.data)
	else
		self:_setLog(`No loaded slot for {actionName}`)
	end
end

function DataDebugPanel._refresh(self: any, data: any?): ()
	local currentData = data
	if currentData == nil and DataService:hasData() then
		currentData = DataService:get()
	end

	if self.summaryLabel then
		self.summaryLabel.Text = summarize(currentData)
	end
end

function DataDebugPanel._setLog(self: any, message: string): ()
	if self.logLabel then
		self.logLabel.Text = message
	end
end

return DataDebugPanel
