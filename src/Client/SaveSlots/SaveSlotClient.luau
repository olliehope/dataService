--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Networker = require(Packages:WaitForChild("Networker"))
local Signal = require(Packages:WaitForChild("Signal"))

export type SaveSlotResult = {
	ok: boolean,
	message: string,
	state: any?,
}

local SaveSlotClient = {
	state = nil :: any?,
	networker = nil :: Networker.Client?,
	_stateChanged = Signal.new(),
}

function SaveSlotClient.init(self: typeof(SaveSlotClient)): any
	if self.networker then
		return self.state
	end

	self.networker = Networker.client.new("SaveSlots", self)
	self:setState(self.networker:fetch("getState"))

	return self.state
end

function SaveSlotClient.setState(self: typeof(SaveSlotClient), state: any): ()
	self.state = state
	self._stateChanged:Fire(state)
end

function SaveSlotClient.getState(self: typeof(SaveSlotClient)): any
	return self.state
end

function SaveSlotClient.onStateChanged(self: typeof(SaveSlotClient), callback: (any) -> ()): RBXScriptConnection
	return self._stateChanged:Connect(callback)
end

function SaveSlotClient.createSlot(self: typeof(SaveSlotClient), name: string?): SaveSlotResult
	return self:_request("createSlot", name)
end

function SaveSlotClient.selectSlot(self: typeof(SaveSlotClient), slotId: string): SaveSlotResult
	return self:_request("selectSlot", slotId)
end

function SaveSlotClient.closeSlot(self: typeof(SaveSlotClient)): SaveSlotResult
	return self:_request("closeSlot")
end

function SaveSlotClient.renameSlot(self: typeof(SaveSlotClient), slotId: string, name: string): SaveSlotResult
	return self:_request("renameSlot", slotId, name)
end

function SaveSlotClient.deleteSlot(self: typeof(SaveSlotClient), slotId: string): SaveSlotResult
	return self:_request("deleteSlot", slotId)
end

function SaveSlotClient._request(self: typeof(SaveSlotClient), method: string, ...: any): SaveSlotResult
	assert(self.networker, "SaveSlotClient must be initialized before requests.")

	local result = self.networker:fetch(method, ...)
	if not result then
		return {
			ok = false,
			message = "The save slot server did not respond.",
			state = self.state,
		}
	end

	if result and result.state then
		self:setState(result.state)
	end

	return result
end

return SaveSlotClient
