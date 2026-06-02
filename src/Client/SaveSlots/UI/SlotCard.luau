--!strict
local Theme = require(script.Parent.Theme)
local createElement = require(script.Parent.CreateElement)

type SlotMetadata = {
	id: string,
	name: string,
	createdAt: number,
	updatedAt: number,
	lastPlayedAt: number,
	playtimeSeconds: number,
	preview: { [string]: any },
}

type SlotCardProps = {
	slot: SlotMetadata,
	isActive: boolean,
	isLoaded: boolean,
	onPlay: (string) -> (),
	onRename: (string, string) -> (),
	onDelete: (string) -> (),
}

local SlotCard = {}

local function formatTime(timestamp: number): string
	if timestamp <= 0 then
		return "Never"
	end

	return os.date("%d %b %Y, %H:%M", timestamp)
end

local function formatPlaytime(seconds: number): string
	local minutes = math.floor(seconds / 60)
	local hours = math.floor(minutes / 60)
	minutes %= 60

	if hours > 0 then
		return `{hours}h {minutes}m`
	end

	return `{minutes}m`
end

local function formatPreview(preview: { [string]: any }): string
	local parts = {}

	for key, value in preview do
		table.insert(parts, `{key}: {value}`)
	end

	table.sort(parts)

	if #parts == 0 then
		return "No preview yet"
	end

	return table.concat(parts, "  |  ")
end

local function addCorner(parent: Instance, radius: number)
	createElement("UICorner", {
		CornerRadius = UDim.new(0, radius),
		Parent = parent,
	})
end

local function addStroke(parent: Instance, color: Color3)
	createElement("UIStroke", {
		Color = color,
		Thickness = 1,
		Transparency = 0.2,
		Parent = parent,
	})
end

function SlotCard.new(props: SlotCardProps): Frame
	local colors = Theme.colors
	local card = createElement("Frame", {
		BackgroundColor3 = if props.isActive then colors.panelRaised else colors.panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 156),
	}) :: Frame
	addCorner(card, Theme.radius.panel)
	addStroke(card, if props.isActive then colors.accent else colors.border)

	local padding = createElement("UIPadding", {
		PaddingTop = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
		Parent = card,
	})
	padding.Name = "Padding"

	local nameBox = createElement("TextBox", {
		BackgroundColor3 = colors.panelMuted,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Theme.fonts.medium,
		PlaceholderText = "Save name",
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(1, -176, 0, 34),
		Text = props.slot.name,
		TextColor3 = colors.text,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	}) :: TextBox
	addCorner(nameBox, Theme.radius.control)
	createElement("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = nameBox,
	})

	nameBox.FocusLost:Connect(function(enterPressed)
		if enterPressed and nameBox.Text ~= props.slot.name then
			props.onRename(props.slot.id, nameBox.Text)
		end
	end)

	local badgeText = if props.isLoaded then "Loaded" elseif props.isActive then "Selected" else "Available"
	local badgeColor = if props.isLoaded then colors.success elseif props.isActive then colors.accent else colors.textMuted
	createElement("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.fonts.medium,
		Position = UDim2.new(1, -160, 0, 4),
		Size = UDim2.new(0, 160, 0, 24),
		Text = badgeText,
		TextColor3 = badgeColor,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	})

	createElement("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.fonts.body,
		Position = UDim2.new(0, 0, 0, 48),
		Size = UDim2.new(1, 0, 0, 20),
		Text = `Last played: {formatTime(props.slot.lastPlayedAt)}    Playtime: {formatPlaytime(props.slot.playtimeSeconds)}`,
		TextColor3 = colors.textMuted,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	createElement("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.fonts.body,
		Position = UDim2.new(0, 0, 0, 74),
		Size = UDim2.new(1, 0, 0, 20),
		Text = formatPreview(props.slot.preview),
		TextColor3 = colors.textMuted,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	local playButton = createElement("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = colors.accent,
		BorderSizePixel = 0,
		Font = Theme.fonts.medium,
		Position = UDim2.new(1, -236, 1, -38),
		Size = UDim2.new(0, 112, 0, 34),
		Text = if props.isLoaded then "Playing" else "Play",
		TextColor3 = colors.text,
		TextSize = 14,
		Parent = card,
	}) :: TextButton
	addCorner(playButton, Theme.radius.control)
	playButton.Activated:Connect(function()
		props.onPlay(props.slot.id)
	end)

	local renameButton = createElement("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = colors.panelMuted,
		BorderSizePixel = 0,
		Font = Theme.fonts.medium,
		Position = UDim2.new(1, -118, 1, -38),
		Size = UDim2.new(0, 54, 0, 34),
		Text = "Save",
		TextColor3 = colors.text,
		TextSize = 14,
		Parent = card,
	}) :: TextButton
	addCorner(renameButton, Theme.radius.control)
	renameButton.Activated:Connect(function()
		props.onRename(props.slot.id, nameBox.Text)
	end)

	local deleteButton = createElement("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = colors.danger,
		BorderSizePixel = 0,
		Font = Theme.fonts.medium,
		Position = UDim2.new(1, -58, 1, -38),
		Size = UDim2.new(0, 58, 0, 34),
		Text = "Delete",
		TextColor3 = colors.text,
		TextSize = 14,
		Parent = card,
	}) :: TextButton
	addCorner(deleteButton, Theme.radius.control)
	deleteButton.Activated:Connect(function()
		props.onDelete(props.slot.id)
	end)

	return card
end

return SlotCard
