local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(ReplicatedStorage:WaitForChild("DataService")).server
local DataDebugService = require(script.Services.DataDebugService)
local SaveSlotService = require(script.Services.SaveSlotService)

local USE_MOCK_DATA = false

if RunService:IsStudio() and not USE_MOCK_DATA then
	print("[Server Test] Live DataStore saving is enabled in Studio.")
	print("[Server Test] Make sure the place is published and Studio API Services are enabled.")
end

local slotTemplate = {
	currency = 0,
	inventory = {},
	settings = {
		music = 100,
	},
	stats = {
		level = 1,
		xp = 0,
	},
}

SaveSlotService:init({
	slotTemplate = slotTemplate,
	maxSlots = 3,
	accountStoreIndex = "PlayerAccounts",
	slotStoreIndex = "PlayerSlots",
	useMock = USE_MOCK_DATA,
	autoCreateFirstSlot = true,
	autoSelectLastSlot = false,
	previewBuilder = function(data)
		return {
			currency = data.currency,
			level = data.stats.level,
			items = #data.inventory,
		}
	end,
})

function DataService:onPlayerInit(player, data)
	print(`[Server Test] Slot data initialized for {player.Name}`)
	print(`[Server Test] Starting data: currency={data.currency}, level={data.stats.level}, items={#data.inventory}`)
end

DataService:addPlayerRemovingCallback(function(player, data)
	print(`[Server Test] Releasing slot for {player.Name}`)
	print(`[Server Test] Final data: currency={data.currency}, level={data.stats.level}, items={#data.inventory}`)
end)

DataDebugService:init()

print("[Server Test] Save slot test server is running.")
