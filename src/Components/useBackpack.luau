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

const function inInventory(item: Instance, backpack: Backpack?, character: Model?): boolean
	local parent = item.Parent
	return parent == backpack or parent == character
end

const function equipped(item: BackpackItem, character: Model?): boolean
	if item:IsA("HopperBin") then
		return item.Active
	end
	return item:IsA("Tool") and character ~= nil and item.Parent == character
end

type Store = {
	getSnapshot: () -> { items: { [number]: SlotItem } },
	activateItem: (item: BackpackItem) -> (),
	subscribe: (listener: () -> ()) -> () -> (),
	destroy: () -> (),
}

const function createStore(player: Player, hotbarSlots: number): Store
	local slots: { [number]: BackpackItem } = {}
	local itemToSlot: { [BackpackItem]: number } = {}
	local tracked: { [BackpackItem]: { state: string, connection: RBXScriptConnection? } } = {}
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

	const function untrack(item: BackpackItem)
		local record = tracked[item]
		if not record then
			return
		end
		if record.connection then
			record.connection:Disconnect()
		end
		tracked[item] = nil
		local index = itemToSlot[item]
		if index then
			slots[index] = nil
			itemToSlot[item] = nil
		end
		itemRemoved:Fire(item)
	end

	const function onItemChanged(item: BackpackItem)
		local isEquipped = equipped(item, character)
		local state = if isEquipped then "Equipped" else "Unequipped"

		local record = tracked[item]
		if not record then
			if not inInventory(item, backpack, character) then
				return
			end
			local index = nextSlot()
			slots[index] = item
			itemToSlot[item] = index
			tracked[item] = { state = state, connection = nil }
			itemAdded:Fire(item)
			if item:IsA("HopperBin") then
				tracked[item].connection = item:GetPropertyChangedSignal("Active"):Connect(function()
					onItemChanged(item)
				end)
			end
			if isEquipped then
				itemEquipped:Fire(item)
			end
		elseif record.state ~= state then
			record.state = state
			if isEquipped then
				itemEquipped:Fire(item)
			else
				itemUnequipped:Fire(item)
			end
		end
		notify()
	end

	const function onChildAdded(child: Instance)
		if child:IsA("BackpackItem") then
			onItemChanged(child :: BackpackItem)
		end
	end

	const function onChildRemoved(child: Instance)
		if not child:IsA("BackpackItem") then
			return
		end
		local item = child :: BackpackItem
		task.defer(function()
			if inInventory(item, backpack, character) then
				onItemChanged(item)
				return
			end
			if tracked[item] then
				untrack(item)
				notify()
			end
		end)
	end

	const function resetInventory()
		for _, conn in connections do
			conn:Disconnect()
		end
		table.clear(connections)
		for _, record in tracked do
			if record.connection then
				record.connection:Disconnect()
			end
		end
		table.clear(tracked)
		table.clear(slots)
		table.clear(itemToSlot)
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
			if item:IsA("HopperBin") then
				warn(`[Satchel] Cannot select '{item}' hopper. HopperBin is deprecated and not supported.`)
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
