--!strict

const React = require("../../react")

const bindableEvents = script.Parent.Parent.BindableEvents
const itemAdded = bindableEvents.BackpackItemAdded
const itemRemoved = bindableEvents.BackpackItemRemoved
const itemEquipped = bindableEvents.BackpackItemEquipped
const itemUnequipped = bindableEvents.BackpackItemUnequipped

export type SlotItem = {
	item: BackpackItem,
	equipped: boolean,
}

export type BackpackState = {
	items: { [number]: SlotItem },
	onSlotActivated: (item: BackpackItem) -> (),
}

const function inInventory(tool: Tool, backpack: Backpack?, character: Model?): boolean
	local parent = tool.Parent
	return parent == backpack or parent == character
end

const function equipped(tool: Tool, character: Model?): boolean
	return character ~= nil and tool.Parent == character
end

type Store = {
	getSnapshot: () -> { items: { [number]: SlotItem } },
	activateItem: (item: BackpackItem) -> (),
	subscribe: (listener: () -> ()) -> () -> (),
	destroy: () -> (),
}

const function createStore(player: Player, hotbarSlots: number): Store
	local slots: { [number]: Tool } = {}
	local itemToSlot: { [Tool]: number } = {}
	local equippedState: { [Tool]: boolean } = {}
	local listeners: { () -> () } = {}
	local connections: { RBXScriptConnection } = {}
	local character: Model? = nil
	local backpack: Backpack? = nil

	const function notify()
		for _, listener in listeners do
			listener()
		end
	end

	const function nextSlot(): number
		for index = 1, hotbarSlots do
			if slots[index] == nil then
				return index
			end
		end
		local maxIndex = hotbarSlots
		for index in slots do
			maxIndex = math.max(maxIndex, index)
		end
		return maxIndex + 1
	end

	const function remove(tool: Tool): boolean
		local index = itemToSlot[tool]
		if index then
			slots[index] = nil
			itemToSlot[tool] = nil
			equippedState[tool] = nil
			itemRemoved:Fire(tool)
			return true
		end
		return false
	end

	const function onToolChanged(tool: Tool)
		if not inInventory(tool, backpack, character) then
			if remove(tool) then
				notify()
			end
			return
		end

		local slot = itemToSlot[tool]
		if slot == nil then
			slot = nextSlot()
			slots[slot] = tool
			itemToSlot[tool] = slot
			itemAdded:Fire(tool)
		end

		local isEquipped = equipped(tool, character)
		local wasEquipped = equippedState[tool]
		if wasEquipped == nil then
			equippedState[tool] = isEquipped
			if isEquipped then
				itemEquipped:Fire(tool)
			end
		elseif wasEquipped ~= isEquipped then
			equippedState[tool] = isEquipped
			if isEquipped then
				itemEquipped:Fire(tool)
			else
				itemUnequipped:Fire(tool)
			end
		end

		notify()
	end

	const function onChildAdded(child: Instance)
		if child:IsA("Tool") then
			onToolChanged(child)
		end
	end

	const function onChildRemoved(child: Instance)
		if not child:IsA("Tool") then
			return
		end
		local tool = child :: Tool
		task.defer(function()
			if inInventory(tool, backpack, character) then
				onToolChanged(tool)
				return
			end
			if remove(tool) then
				notify()
			end
		end)
	end

	const function resetInventory()
		for _, conn in connections do
			conn:Disconnect()
		end
		table.clear(connections)
		table.clear(slots)
		table.clear(itemToSlot)
		table.clear(equippedState)
	end

	const function onCharacterAdded(char: Model)
		resetInventory()
		character = char
		backpack = player:WaitForChild("Backpack") :: Backpack
		table.insert(connections, char.ChildAdded:Connect(onChildAdded))
		table.insert(connections, char.ChildRemoved:Connect(onChildRemoved))
		table.insert(connections, backpack.ChildAdded:Connect(onChildAdded))
		table.insert(connections, backpack.ChildRemoved:Connect(onChildRemoved))
		for _, child in backpack:GetChildren() do
			onChildAdded(child)
		end
		for _, child in char:GetChildren() do
			onChildAdded(child)
		end
		notify()
	end

	local characterConnection = player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end

	return {
		getSnapshot = function()
			local items: { [number]: SlotItem } = {}
			for index, item in slots do
				items[index] = { item = item, equipped = equipped(item, character) }
			end
			return { items = items }
		end,
		activateItem = function(item: BackpackItem)
			if not item:IsA("Tool") then
				return
			end
			local char = character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if not humanoid then
				return
			end
			if equipped(item, char) then
				humanoid:UnequipTools()
			else
				humanoid:EquipTool(item)
			end
		end,
		subscribe = function(listener: () -> ())
			table.insert(listeners, listener)
			return function()
				local index = table.find(listeners, listener)
				if index then
					table.remove(listeners, index)
				end
			end
		end,
		destroy = function()
			characterConnection:Disconnect()
			resetInventory()
			table.clear(listeners)
			character = nil
			backpack = nil
		end,
	}
end

const function useBackpack(player: Player, hotbarSlotCount: number): BackpackState
	const snapshot, setSnapshot = React.useState(function()
		return { items = {} :: { [number]: SlotItem } }
	end)
	const activateRef = React.useRef(nil :: ((item: BackpackItem) -> ())?)

	React.useEffect(function()
		local store = createStore(player, hotbarSlotCount)
		activateRef.current = store.activateItem
		local function sync()
			setSnapshot(store.getSnapshot())
		end
		sync()
		local unsubscribe = store.subscribe(sync)
		return function()
			unsubscribe()
			store.destroy()
			activateRef.current = nil
		end
	end, { player, hotbarSlotCount })

	const onSlotActivated = React.useCallback(function(item: BackpackItem)
		local activate = activateRef.current
		if activate then
			activate(item)
		end
	end, {})

	return {
		items = snapshot.items,
		onSlotActivated = onSlotActivated,
	}
end

return useBackpack
