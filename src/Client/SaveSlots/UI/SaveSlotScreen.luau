--!strict
local Players = game:GetService("Players")

local SlotCard = require(script.Parent.SlotCard)
local Theme = require(script.Parent.Theme)
local createElement = require(script.Parent.CreateElement)

type SaveSlotClient = {
	state: any?,
	onStateChanged: (self: any, callback: (any) -> ()) -> RBXScriptConnection,
	createSlot: (self: any, name: string?) -> any,
	selectSlot: (self: any, slotId: string) -> any,
	closeSlot: (self: any) -> any,
	renameSlot: (self: any, slotId: string, name: string) -> any,
	deleteSlot: (self: any, slotId: string) -> any,
}

local SaveSlotScreen = {}
SaveSlotScreen.__index = SaveSlotScreen

local function addCorner(parent: Instance, radius: number)
	createElement("UICorner", {
		CornerRadius = UDim.new(0, radius),
		Parent = parent,
	})
end

local function makeButton(text: string, color: Color3): TextButton
	local button = createElement("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Font = Theme.fonts.medium,
		Size = UDim2.new(0, 132, 0, 38),
		Text = text,
		TextColor3 = Theme.colors.text,
		TextSize = 14,
	}) :: TextButton
	addCorner(button, Theme.radius.control)
	return button
end

function SaveSlotScreen.new(saveSlots: SaveSlotClient)
	return setmetatable({
		saveSlots = saveSlots,
		gui = nil :: ScreenGui?,
		list = nil :: ScrollingFrame?,
		message = nil :: TextLabel?,
		titleLabel = nil :: TextLabel?,
		subtitleLabel = nil :: TextLabel?,
		createNameBox = nil :: TextBox?,
		closeButton = nil :: TextButton?,
		closeSlotButton = nil :: TextButton?,
		connection = nil :: RBXScriptConnection?,
		pendingDeleteSlotId = nil :: string?,
		isOpen = false,
	}, SaveSlotScreen)
end

function SaveSlotScreen.mount(self: any): ()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local colors = Theme.colors

	local gui = createElement("ScreenGui", {
		Name = "SaveSlotScreen",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui

	local backdrop = createElement("Frame", {
		BackgroundColor3 = colors.background,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})

	local panel = createElement("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = colors.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 720, 0, 560),
		Parent = backdrop,
	})
	addCorner(panel, Theme.radius.panel)
	createElement("UIStroke", {
		Color = colors.border,
		Thickness = 1,
		Transparency = 0.25,
		Parent = panel,
	})

	local titleLabel = createElement("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.fonts.title,
		Position = UDim2.new(0, 28, 0, 22),
		Size = UDim2.new(1, -220, 0, 34),
		Text = "Choose Save Slot",
		TextColor3 = colors.text,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	}) :: TextLabel

	local closeButton = makeButton("Back to Game", colors.panelMuted)
	closeButton.Position = UDim2.new(1, -160, 0, 22)
	closeButton.Visible = false
	closeButton.Parent = panel

	local subtitleLabel = createElement("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.fonts.body,
		Position = UDim2.new(0, 28, 0, 58),
		Size = UDim2.new(1, -220, 0, 40),
		Text = "Account metadata loads first. Gameplay data loads only after you press Play.",
		TextColor3 = colors.textMuted,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = panel,
	}) :: TextLabel

	local closeSlotButton = makeButton("Close Slot", colors.danger)
	closeSlotButton.Position = UDim2.new(1, -160, 0, 66)
	closeSlotButton.Visible = false
	closeSlotButton.Parent = panel

	local list = createElement("ScrollingFrame", {
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		Position = UDim2.new(0, 28, 0, 116),
		ScrollBarImageColor3 = colors.border,
		ScrollBarThickness = 5,
		Size = UDim2.new(1, -56, 1, -216),
		Parent = panel,
	}) :: ScrollingFrame

	createElement("UIListLayout", {
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})

	local createNameBox = createElement("TextBox", {
		BackgroundColor3 = colors.panelMuted,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Theme.fonts.body,
		PlaceholderText = "New slot name",
		Position = UDim2.new(0, 28, 1, -76),
		Size = UDim2.new(1, -208, 0, 38),
		Text = "",
		TextColor3 = colors.text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	}) :: TextBox
	addCorner(createNameBox, Theme.radius.control)
	createElement("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = createNameBox,
	})

	local createButton = makeButton("Create Slot", colors.accent)
	createButton.Position = UDim2.new(1, -160, 1, -76)
	createButton.Parent = panel

	local message = createElement("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.fonts.body,
		Position = UDim2.new(0, 28, 1, -32),
		Size = UDim2.new(1, -56, 0, 20),
		Text = "",
		TextColor3 = colors.textMuted,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	}) :: TextLabel

	self.gui = gui
	self.list = list
	self.message = message
	self.titleLabel = titleLabel
	self.subtitleLabel = subtitleLabel
	self.createNameBox = createNameBox
	self.closeButton = closeButton
	self.closeSlotButton = closeSlotButton

	createButton.Activated:Connect(function()
		local result = self.saveSlots:createSlot(createNameBox.Text)
		self:_showResult(result)
		if result.ok then
			createNameBox.Text = ""
		end
	end)

	closeButton.Activated:Connect(function()
		self:hide()
	end)

	closeSlotButton.Activated:Connect(function()
		self.isOpen = true
		self.pendingDeleteSlotId = nil
		self:_showResult(self.saveSlots:closeSlot())
	end)

	self.connection = self.saveSlots:onStateChanged(function(state)
		self:render(state)
	end)

	self:render(self.saveSlots.state)
end

function SaveSlotScreen.open(self: any): ()
	self.isOpen = true
	self:render(self.saveSlots.state)
end

function SaveSlotScreen.hide(self: any): ()
	self.isOpen = false
	self:render(self.saveSlots.state)
end

function SaveSlotScreen.render(self: any, state: any?): ()
	if not self.gui or not self.list then
		return
	end

	local shouldShow = not state or state.status == "loading" or not state.isSlotLoaded or self.isOpen
	self.gui.Enabled = shouldShow
	if not shouldShow then
		return
	end

	self:_clearList()

	if not state or state.status == "loading" then
		self:_syncHeader(nil)
		self:_setMessage("Loading account saves...")
		return
	end

	self:_syncHeader(state)

	for _, slot in state.slots do
		local card = SlotCard.new({
			slot = slot,
			isActive = state.activeSlotId == slot.id,
			isLoaded = state.isSlotLoaded and state.activeSlotId == slot.id,
			onPlay = function(slotId)
				self.pendingDeleteSlotId = nil
				local result = self.saveSlots:selectSlot(slotId)
				self:_showResult(result)

				if result.ok and result.state and result.state.isSlotLoaded then
					self.isOpen = false
					self:render(result.state)
				end
			end,
			onRename = function(slotId, name)
				self.pendingDeleteSlotId = nil
				self:_showResult(self.saveSlots:renameSlot(slotId, name))
			end,
			onDelete = function(slotId)
				if self.pendingDeleteSlotId ~= slotId then
					self.pendingDeleteSlotId = slotId
					self:_setMessage("Press Delete again to permanently remove this slot.")
					return
				end

				self.pendingDeleteSlotId = nil
				self:_showResult(self.saveSlots:deleteSlot(slotId))
			end,
		})
		card.Parent = self.list
	end

	if state.isSlotLoaded and self.isOpen then
		self:_setMessage("Pick another slot to save and switch, or close the current slot first.")
	elseif #state.slots == 0 then
		self:_setMessage("Create a slot to start playing.")
	elseif state.canCreate then
		self:_setMessage(`You can create {state.maxSlots - #state.slots} more slot(s).`)
	else
		self:_setMessage("All save slots are in use.")
	end
end

function SaveSlotScreen._syncHeader(self: any, state: any?): ()
	local isLoaded = state and state.isSlotLoaded
	if self.titleLabel then
		self.titleLabel.Text = if isLoaded then "Switch Save Slot" else "Choose Save Slot"
	end

	if self.subtitleLabel then
		self.subtitleLabel.Text = if isLoaded
			then "Your current slot stays loaded until you close it or press Play on another slot."
			else "Account metadata loads first. Gameplay data loads only after you press Play."
	end

	if self.closeButton then
		self.closeButton.Visible = isLoaded == true
	end

	if self.closeSlotButton then
		self.closeSlotButton.Visible = isLoaded == true
	end
end

function SaveSlotScreen._clearList(self: any): ()
	for _, child in self.list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function SaveSlotScreen._showResult(self: any, result: any): ()
	if result and result.message then
		self:_setMessage(result.message)
	end
end

function SaveSlotScreen._setMessage(self: any, text: string): ()
	if self.message then
		self.message.Text = text
	end
end

return SaveSlotScreen
