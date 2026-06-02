--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Networker = require(Packages:WaitForChild("Networker"))

local DataDebugClient = {
	networker = nil :: Networker.Client?,
}

function DataDebugClient.init(self: typeof(DataDebugClient)): ()
	if self.networker then
		return
	end

	self.networker = Networker.client.new("DataDebug", self)
	print("[DataDebugClient] Connected to server debug service.")
end

function DataDebugClient.getSnapshot(self: typeof(DataDebugClient))
	return self:_fetch("getSnapshot")
end

function DataDebugClient.addCurrency(self: typeof(DataDebugClient), amount: number)
	return self:_fetch("addCurrency", amount)
end

function DataDebugClient.addItem(self: typeof(DataDebugClient), itemName: string?)
	return self:_fetch("addItem", itemName)
end

function DataDebugClient.levelUp(self: typeof(DataDebugClient))
	return self:_fetch("levelUp")
end

function DataDebugClient.setMusic(self: typeof(DataDebugClient), value: number)
	return self:_fetch("setMusic", value)
end

function DataDebugClient.saveNow(self: typeof(DataDebugClient))
	return self:_fetch("saveNow")
end

function DataDebugClient.printSnapshot(self: typeof(DataDebugClient))
	return self:_fetch("printSnapshot")
end

function DataDebugClient._fetch(self: typeof(DataDebugClient), method: string, ...: any)
	assert(self.networker, "DataDebugClient must be initialized before use.")
	print(`[DataDebugClient] Calling server method: {method}`)

	local result = self.networker:fetch(method, ...)
	print(`[DataDebugClient] Server method completed: {method}`)

	return result
end

return DataDebugClient
