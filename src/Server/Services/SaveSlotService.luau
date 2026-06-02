--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local DataService = require(ReplicatedStorage:WaitForChild("DataService")).server
local Packages = ReplicatedStorage:WaitForChild("Packages")
local ServerPackages = ServerScriptService:WaitForChild("ServerPackages")
local Networker = require(Packages:WaitForChild("Networker"))
local ProfileStore = require(ServerPackages:WaitForChild("ProfileStore"))

type SlotPreview = { [string]: any }
type PreviewBuilder = (slotData: any) -> SlotPreview

type SlotMetadata = {
	id: string,
	name: string,
	createdAt: number,
	updatedAt: number,
	lastPlayedAt: number,
	playtimeSeconds: number,
	schemaVersion: number,
	preview: SlotPreview,
}

type AccountData = {
	version: number,
	selectedSlotId: string?,
	slots: { [string]: SlotMetadata },
}

type SaveSlotOptions = {
	slotTemplate: any,
	accountStoreIndex: string?,
	slotStoreIndex: string?,
	accountProfileDataPrefix: string?,
	slotProfileDataPrefix: string?,
	maxSlots: number?,
	defaultSlotName: string?,
	useMock: boolean?,
	autoCreateFirstSlot: boolean?,
	autoSelectLastSlot: boolean?,
	previewBuilder: PreviewBuilder?,
}

local ACCOUNT_TEMPLATE: AccountData = {
	version = 1,
	selectedSlotId = nil,
	slots = {},
}

local DEFAULT_OPTIONS = {
	accountStoreIndex = "PlayerAccounts",
	slotStoreIndex = "PlayerSlots",
	accountProfileDataPrefix = "ACCOUNT_",
	slotProfileDataPrefix = "SLOT_",
	maxSlots = 3,
	defaultSlotName = "New Save",
	useMock = false,
	autoCreateFirstSlot = true,
	autoSelectLastSlot = false,
}

local SaveSlotService = {
	options = {} :: SaveSlotOptions & typeof(DEFAULT_OPTIONS),
	accountStore = nil :: any,
	slotStore = nil :: any,
	networker = nil :: Networker.Server?,
	_accountProfiles = {} :: { [Player]: any },
	_activeSlotIds = {} :: { [Player]: string },
	_slotSessionStartedAt = {} :: { [Player]: number },
	_slotActionLocks = {} :: { [Player]: boolean },
	_endingAccountSessions = {} :: { [Player]: boolean },
	_isShuttingDown = false,
}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in value do
		copy[key] = deepCopy(child)
	end

	return copy
end

local function storeCancel(player: Player)
	return {
		Cancel = function()
			return player.Parent ~= Players
		end,
	}
end

local function sanitizeSlotName(name: any, fallback: string): string
	local cleaned = tostring(name or "")
	cleaned = cleaned:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")

	if cleaned == "" then
		cleaned = fallback
	end

	return cleaned:sub(1, 32)
end

local function slotSortValue(slotId: string): number
	return tonumber(slotId:match("^slot_(%d+)$")) or math.huge
end

local function countSlots(slots: { [string]: SlotMetadata }): number
	local count = 0
	for _ in slots do
		count += 1
	end

	return count
end

local function makeSlotMetadata(slotId: string, name: string): SlotMetadata
	local now = os.time()
	return {
		id = slotId,
		name = name,
		createdAt = now,
		updatedAt = now,
		lastPlayedAt = 0,
		playtimeSeconds = 0,
		schemaVersion = 1,
		preview = {},
	}
end

local function makeResult(ok: boolean, message: string, state: any?)
	return {
		ok = ok,
		message = message,
		state = state,
	}
end

function SaveSlotService.init(self: typeof(SaveSlotService), options: SaveSlotOptions): ()
	assert(not self.accountStore, "SaveSlotService has already been initialized.")
	assert(options.slotTemplate, "SaveSlotService requires slotTemplate.")

	self.options = table.clone(DEFAULT_OPTIONS) :: any
	for key, value in options do
		(self.options :: any)[key] = value
	end

	self.accountStore = ProfileStore.New(self.options.accountStoreIndex, deepCopy(ACCOUNT_TEMPLATE))

	DataService:init({
		template = self.options.slotTemplate,
		profileStoreIndex = self.options.slotStoreIndex,
		useMock = self.options.useMock,
		autoLoadPlayers = false,
		autoReleasePlayers = false,
		kickOnProfileLoadFail = false,
		profileKeyResolver = function(player: Player, _userId: number | string)
			return self:_getActiveSlotProfileKey(player)
		end,
	})

	self.slotStore = DataService.playerStore
	self.networker = Networker.server.new("SaveSlots", self, {
		self.getState,
		self.createSlot,
		self.selectSlot,
		self.closeSlot,
		self.renameSlot,
		self.deleteSlot,
	})

	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:_playerAdded(player)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_playerAdded(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_playerRemoving(player)
	end)

	game:BindToClose(function()
		self:shutdown()
	end)
end

function SaveSlotService.getState(self: typeof(SaveSlotService), player: Player)
	return self:_getState(player)
end

function SaveSlotService.createSlot(self: typeof(SaveSlotService), player: Player, name: string?)
	local account = self:_getAccount(player)
	if not account then
		return makeResult(false, "Your account data is still loading.", self:_getState(player))
	end

	local slots = account.Data.slots
	if countSlots(slots) >= self.options.maxSlots then
		return makeResult(false, "You have reached the save slot limit.", self:_getState(player))
	end

	local slotId = self:_getNextSlotId(slots)
	local fallbackName = `{self.options.defaultSlotName} {slotSortValue(slotId)}`
	local metadata = makeSlotMetadata(slotId, sanitizeSlotName(name, fallbackName))
	slots[slotId] = metadata

	if not account.Data.selectedSlotId then
		account.Data.selectedSlotId = slotId
	end

	print(`[SaveSlotService] Created {slotId} for {player.Name}`)
	self:_emitState(player)
	return makeResult(true, "Save slot created.", self:_getState(player))
end

function SaveSlotService.selectSlot(self: typeof(SaveSlotService), player: Player, slotId: string)
	local account = self:_getAccount(player)
	if not account then
		return makeResult(false, "Your account data is still loading.", self:_getState(player))
	end

	local metadata = account.Data.slots[slotId]
	if not metadata then
		return makeResult(false, "That save slot does not exist.", self:_getState(player))
	end

	if self._slotActionLocks[player] then
		return makeResult(false, "A save slot action is already in progress.", self:_getState(player))
	end

	if self._activeSlotIds[player] == slotId and DataService:isPlayerLoaded(player) then
		return makeResult(true, "Save slot already loaded.", self:_getState(player))
	end

	self._slotActionLocks[player] = true

	if DataService:isPlayerLoaded(player) then
		self:_persistActiveSlotMetadata(player)
		DataService:releasePlayer(player)
	end

	self._activeSlotIds[player] = slotId
	self._slotSessionStartedAt[player] = os.time()

	print(`[SaveSlotService] Loading {slotId} for {player.Name}`)
	local ok, errorMessage = DataService:loadPlayer(player)
	if not ok then
		self._activeSlotIds[player] = nil
		self._slotSessionStartedAt[player] = nil
		self._slotActionLocks[player] = nil
		self:_emitState(player)
		return makeResult(false, errorMessage or "Unable to load that save slot.", self:_getState(player))
	end

	local now = os.time()
	metadata.lastPlayedAt = now
	metadata.updatedAt = now
	account.Data.selectedSlotId = slotId

	self._slotActionLocks[player] = nil
	print(`[SaveSlotService] Loaded {slotId} for {player.Name}`)
	self:_emitState(player)
	return makeResult(true, "Save slot loaded.", self:_getState(player))
end

function SaveSlotService.closeSlot(self: typeof(SaveSlotService), player: Player)
	local account = self:_getAccount(player)
	if not account then
		return makeResult(false, "Your account data is still loading.", self:_getState(player))
	end

	if self._slotActionLocks[player] then
		return makeResult(false, "A save slot action is already in progress.", self:_getState(player))
	end

	if not self._activeSlotIds[player] and not DataService:isPlayerLoaded(player) then
		return makeResult(true, "No save slot is currently loaded.", self:_getState(player))
	end

	self._slotActionLocks[player] = true
	self:_persistActiveSlotMetadata(player)

	if DataService:isPlayerLoaded(player) then
		DataService:releasePlayer(player)
	end

	self._activeSlotIds[player] = nil
	self._slotSessionStartedAt[player] = nil
	account:Save()

	self._slotActionLocks[player] = nil
	print(`[SaveSlotService] Closed active save slot for {player.Name}`)
	self:_emitState(player)
	return makeResult(true, "Save slot closed. Choose another slot to keep playing.", self:_getState(player))
end

function SaveSlotService.renameSlot(self: typeof(SaveSlotService), player: Player, slotId: string, name: string)
	local account = self:_getAccount(player)
	if not account then
		return makeResult(false, "Your account data is still loading.", self:_getState(player))
	end

	local metadata = account.Data.slots[slotId]
	if not metadata then
		return makeResult(false, "That save slot does not exist.", self:_getState(player))
	end

	metadata.name = sanitizeSlotName(name, metadata.name)
	metadata.updatedAt = os.time()

	print(`[SaveSlotService] Renamed {slotId} for {player.Name} to "{metadata.name}"`)
	self:_emitState(player)
	return makeResult(true, "Save slot renamed.", self:_getState(player))
end

function SaveSlotService.deleteSlot(self: typeof(SaveSlotService), player: Player, slotId: string)
	local account = self:_getAccount(player)
	if not account then
		return makeResult(false, "Your account data is still loading.", self:_getState(player))
	end

	if self._slotActionLocks[player] then
		return makeResult(false, "A save slot action is already in progress.", self:_getState(player))
	end

	local metadata = account.Data.slots[slotId]
	if not metadata then
		return makeResult(false, "That save slot does not exist.", self:_getState(player))
	end

	self._slotActionLocks[player] = true

	if self._activeSlotIds[player] == slotId and DataService:isPlayerLoaded(player) then
		self:_persistActiveSlotMetadata(player)
		DataService:releasePlayer(player)
	end

	local slotKey = self:_getSlotProfileKey(player.UserId, slotId)
	local store = self:_getSlotStore()
	local removed = store:RemoveAsync(slotKey)
	if not removed then
		self._slotActionLocks[player] = nil
		return makeResult(false, "Unable to delete that save slot right now.", self:_getState(player))
	end

	account.Data.slots[slotId] = nil
	if account.Data.selectedSlotId == slotId then
		account.Data.selectedSlotId = self:_getFirstSlotId(account.Data.slots)
	end

	self._activeSlotIds[player] = nil
	self._slotSessionStartedAt[player] = nil
	self._slotActionLocks[player] = nil

	print(`[SaveSlotService] Deleted {slotId} for {player.Name}`)
	self:_emitState(player)
	return makeResult(true, "Save slot deleted.", self:_getState(player))
end

function SaveSlotService.savePlayerNow(self: typeof(SaveSlotService), player: Player): (boolean, string)
	local account = self:_getAccount(player)
	if not account then
		return false, "Account profile is not loaded."
	end

	self:_persistActiveSlotMetadata(player)

	local slotSaved = true
	if DataService:isPlayerLoaded(player) then
		slotSaved = DataService:savePlayer(player)
	end

	account:Save()
	print(`[SaveSlotService] Force-saved account and active slot for {player.Name}`)

	if not slotSaved then
		return false, "Account saved, but no active slot was loaded."
	end

	return true, "Account and active slot saved."
end

function SaveSlotService.shutdown(self: typeof(SaveSlotService)): ()
	if self._isShuttingDown then
		return
	end

	self._isShuttingDown = true
	print("[SaveSlotService] Shutdown started. Releasing loaded save slots.")

	for _, player in Players:GetPlayers() do
		self:_playerRemoving(player)
	end
end

function SaveSlotService._playerAdded(self: typeof(SaveSlotService), player: Player): ()
	local profile = self:_startAccountProfile(player)
	if not profile then
		player:Kick("Account data failed to load. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	self:_normalizeAccount(profile.Data)

	profile.OnSessionEnd:Connect(function()
		if self._endingAccountSessions[player] then
			return
		end

		self._accountProfiles[player] = nil
		player:Kick("Account data session ended. Please rejoin.")
	end)

	if not player:IsDescendantOf(Players) then
		self._endingAccountSessions[player] = true
		profile:EndSession()
		self._endingAccountSessions[player] = nil
		return
	end

	self._accountProfiles[player] = profile
	print(`[SaveSlotService] Account metadata loaded for {player.Name}`)

	if self.options.autoCreateFirstSlot and countSlots(profile.Data.slots) == 0 then
		local slotId = self:_getNextSlotId(profile.Data.slots)
		profile.Data.slots[slotId] = makeSlotMetadata(slotId, `{self.options.defaultSlotName} 1`)
		profile.Data.selectedSlotId = slotId
		print(`[SaveSlotService] Auto-created first slot for {player.Name}`)
	end

	self:_emitState(player)

	if self.options.autoSelectLastSlot and profile.Data.selectedSlotId then
		task.spawn(function()
			self:selectSlot(player, profile.Data.selectedSlotId :: string)
		end)
	end
end

function SaveSlotService._playerRemoving(self: typeof(SaveSlotService), player: Player): ()
	self:_persistActiveSlotMetadata(player)

	if DataService:isPlayerLoaded(player) then
		DataService:releasePlayer(player)
	end

	local profile = self._accountProfiles[player]
	if profile then
		self._endingAccountSessions[player] = true
		profile:EndSession()
		self._endingAccountSessions[player] = nil
	end

	self._accountProfiles[player] = nil
	self._activeSlotIds[player] = nil
	self._slotSessionStartedAt[player] = nil
	self._slotActionLocks[player] = nil
end

function SaveSlotService._startAccountProfile(self: typeof(SaveSlotService), player: Player): any?
	local accountKey = self:_getAccountProfileKey(player.UserId)
	if self.options.useMock then
		return self.accountStore.Mock:StartSessionAsync(accountKey, storeCancel(player))
	end

	return self.accountStore:StartSessionAsync(accountKey, storeCancel(player))
end

function SaveSlotService._getAccount(self: typeof(SaveSlotService), player: Player): any?
	return self._accountProfiles[player]
end

function SaveSlotService._getState(self: typeof(SaveSlotService), player: Player)
	local account = self:_getAccount(player)
	if not account then
		return {
			status = "loading",
			maxSlots = self.options.maxSlots,
			slots = {},
			selectedSlotId = nil,
			activeSlotId = nil,
			canCreate = false,
			isSlotLoaded = false,
		}
	end

	local slots = {}
	for _, metadata in account.Data.slots do
		table.insert(slots, deepCopy(metadata))
	end

	table.sort(slots, function(left, right)
		return slotSortValue(left.id) < slotSortValue(right.id)
	end)

	return {
		status = "ready",
		maxSlots = self.options.maxSlots,
		slots = slots,
		selectedSlotId = account.Data.selectedSlotId,
		activeSlotId = self._activeSlotIds[player],
		canCreate = #slots < self.options.maxSlots,
		isSlotLoaded = DataService:isPlayerLoaded(player),
	}
end

function SaveSlotService._emitState(self: typeof(SaveSlotService), player: Player): ()
	if self.networker and player:IsDescendantOf(Players) then
		self.networker:fire(player, "setState", self:_getState(player))
	end
end

function SaveSlotService._normalizeAccount(_self: typeof(SaveSlotService), data: AccountData): ()
	data.version = data.version or ACCOUNT_TEMPLATE.version
	data.slots = data.slots or {}

	for slotId, metadata in data.slots do
		metadata.id = metadata.id or slotId
		metadata.name = sanitizeSlotName(metadata.name, slotId)
		metadata.createdAt = metadata.createdAt or os.time()
		metadata.updatedAt = metadata.updatedAt or metadata.createdAt
		metadata.lastPlayedAt = metadata.lastPlayedAt or 0
		metadata.playtimeSeconds = metadata.playtimeSeconds or 0
		metadata.schemaVersion = metadata.schemaVersion or 1
		metadata.preview = metadata.preview or {}
	end

	if data.selectedSlotId and not data.slots[data.selectedSlotId] then
		data.selectedSlotId = nil
	end
end

function SaveSlotService._persistActiveSlotMetadata(self: typeof(SaveSlotService), player: Player): ()
	local slotId = self._activeSlotIds[player]
	if not slotId then
		return
	end

	local account = self:_getAccount(player)
	if not account then
		return
	end

	local metadata = account.Data.slots[slotId]
	if not metadata then
		return
	end

	local now = os.time()
	local sessionStartedAt = self._slotSessionStartedAt[player]
	if sessionStartedAt then
		metadata.playtimeSeconds += math.max(0, now - sessionStartedAt)
		self._slotSessionStartedAt[player] = now
	end

	if DataService:isPlayerLoaded(player) and self.options.previewBuilder then
		local success, preview = pcall(function()
			return self.options.previewBuilder(DataService:getProfile(player).Data)
		end)

		if success and type(preview) == "table" then
			metadata.preview = preview
		end
	end

	metadata.lastPlayedAt = now
	metadata.updatedAt = now
end

function SaveSlotService._getNextSlotId(self: typeof(SaveSlotService), slots: { [string]: SlotMetadata }): string
	for index = 1, self.options.maxSlots do
		local slotId = `slot_{index}`
		if not slots[slotId] then
			return slotId
		end
	end

	error("No save slot ids available.")
end

function SaveSlotService._getFirstSlotId(_self: typeof(SaveSlotService), slots: { [string]: SlotMetadata }): string?
	local firstSlotId = nil :: string?
	for slotId in slots do
		if not firstSlotId or slotSortValue(slotId) < slotSortValue(firstSlotId) then
			firstSlotId = slotId
		end
	end

	return firstSlotId
end

function SaveSlotService._getAccountProfileKey(self: typeof(SaveSlotService), userId: number | string): string
	return self.options.accountProfileDataPrefix .. tostring(userId)
end

function SaveSlotService._getSlotProfileKey(self: typeof(SaveSlotService), userId: number | string, slotId: string): string
	return `{self.options.slotProfileDataPrefix}{userId}_{slotId}`
end

function SaveSlotService._getActiveSlotProfileKey(self: typeof(SaveSlotService), player: Player): string
	local slotId = self._activeSlotIds[player]
	assert(slotId, "Cannot load player data before a save slot has been selected.")

	return self:_getSlotProfileKey(player.UserId, slotId)
end

function SaveSlotService._getSlotStore(self: typeof(SaveSlotService)): any
	if self.options.useMock then
		return self.slotStore.Mock
	end

	return self.slotStore
end

return SaveSlotService
