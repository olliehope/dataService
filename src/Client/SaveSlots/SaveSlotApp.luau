--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(ReplicatedStorage:WaitForChild("DataService")).client
local Client = ReplicatedStorage:WaitForChild("Client")
local DataDebugPanel = require(Client:WaitForChild("Debug"):WaitForChild("DataDebugPanel"))
local SaveSlotClient = require(script.Parent.SaveSlotClient)
local SaveSlotScreen = require(script.Parent.UI.SaveSlotScreen)

local SaveSlotApp = {}

function SaveSlotApp.start(): ()
	SaveSlotClient:init()

	local screen = SaveSlotScreen.new(SaveSlotClient)
	screen:mount()

	task.spawn(function()
		DataService:init()
		print("[Client Test] Slot data received from server.")
		print("[Client Test] Initial client data:", DataService:get())

		local debugPanel = DataDebugPanel.new({
			onSwitchSlot = function()
				screen:open()
			end,
		})
		debugPanel:mount()
	end)
end

return SaveSlotApp
