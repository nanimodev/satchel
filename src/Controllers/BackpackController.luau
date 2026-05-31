--!strict

-- TODO: Refactor to be more clean

export type SlotItem = {
	item: BackpackItem,
	equipped: boolean,
}

export type Snapshot = {
	items: { [number]: SlotItem },
}

export type Controller = {
	getSnapshot: () -> Snapshot,
	activateItem: (item: BackpackItem) -> (),
	setHotbarSlotCount: (count: number) -> (),
	subscribe: (listener: () -> ()) -> () -> (),
	destroy: () -> (),
}

const DEFAULT_HOTBAR_SLOT_COUNT = 10

const function isInventoryItem(item: Instance, backpack: Backpack?, character: Model?): boolean
	local parent = item.Parent
	return parent == backpack or parent == character
end

const function create(player: Player, bindableEvents: Folder): Controller
	const backpackItemAdded = bindableEvents.BackpackItemAdded
	const backpackItemRemoved = bindableEvents.BackpackItemRemoved
	const backpackItemEquipped = bindableEvents.BackpackItemEquipped
	const backpackItemUnequipped = bindableEvents.BackpackItemUnequipped

	local hotbarSlotCount = DEFAULT_HOTBAR_SLOT_COUNT
	local items: { [number]: BackpackItem } = {}
	local itemToSlot: { [BackpackItem]: number } = {}
	local trackedItems: { [BackpackItem]: { state: string, connection: RBXScriptConnection? } } = {}
	local listeners: { () -> () } = {}
	local connections: { RBXScriptConnection } = {}

	local character: Model? = nil
	local backpack: Backpack? = nil

	const function notify()
		for _, listener in listeners do
			listener()
		end
	end

	const function isEquipped(item: BackpackItem): boolean
		if item:IsA("HopperBin") then
			return item.Active
		end
		if item:IsA("Tool") then
			return character ~= nil and item.Parent == character
		end
		return false
	end

	const function findLowestEmptySlot(): number
		for index = 1, hotbarSlotCount do
			if items[index] == nil then
				return index
			end
		end
		local maxIndex = hotbarSlotCount
		for index in items do
			if index > maxIndex then
				maxIndex = index
			end
		end
		return maxIndex + 1
	end

	const function removeFromSlots(item: BackpackItem)
		local slotIndex = itemToSlot[item]
		if slotIndex then
			items[slotIndex] = nil
			itemToSlot[item] = nil
		end
	end

	const function handleItemState(item: BackpackItem)
		const equipped = isEquipped(item)
		const currentState = if equipped then "Equipped" else "Unequipped"

		const record = trackedItems[item]
		if not record then
			if not isInventoryItem(item, backpack, character) then
				return
			end

			const slotIndex = findLowestEmptySlot()
			items[slotIndex] = item
			itemToSlot[item] = slotIndex

			trackedItems[item] = {
				state = currentState,
				connection = nil,
			}

			backpackItemAdded:Fire(item)

			if item:IsA("HopperBin") then
				trackedItems[item].connection = item:GetPropertyChangedSignal("Active"):Connect(function()
					handleItemState(item)
				end)
			end

			if equipped then
				backpackItemEquipped:Fire(item)
			end
		elseif record.state ~= currentState then
			record.state = currentState
			if equipped then
				backpackItemEquipped:Fire(item)
			else
				backpackItemUnequipped:Fire(item)
			end
		end

		notify()
	end

	const function handleItemRemoval(item: BackpackItem)
		task.defer(function()
			if isInventoryItem(item, backpack, character) then
				handleItemState(item)
				return
			end

			const record = trackedItems[item]
			if not record then
				return
			end

			if record.connection then
				record.connection:Disconnect()
			end
			trackedItems[item] = nil

			removeFromSlots(item)
			backpackItemRemoved:Fire(item)
			notify()
		end)
	end

	const function onChildAdded(child: Instance)
		if child:IsA("Tool") or child:IsA("HopperBin") then
			handleItemState(child :: BackpackItem)
		end
	end

	const function onChildRemoved(child: Instance)
		if child:IsA("Tool") or child:IsA("HopperBin") then
			handleItemRemoval(child :: BackpackItem)
		end
	end

	const function clearTracked()
		for item, record in trackedItems do
			if record.connection then
				record.connection:Disconnect()
			end
		end
		table.clear(trackedItems)
		table.clear(items)
		table.clear(itemToSlot)
	end

	const function monitorInventory(char: Model, pack: Backpack)
		character = char
		backpack = pack

		table.insert(connections, char.ChildAdded:Connect(onChildAdded))
		table.insert(connections, char.ChildRemoved:Connect(onChildRemoved))
		table.insert(connections, pack.ChildAdded:Connect(onChildAdded))
		table.insert(connections, pack.ChildRemoved:Connect(onChildRemoved))

		for _, child in pack:GetChildren() do
			onChildAdded(child)
		end
		for _, child in char:GetChildren() do
			onChildAdded(child)
		end

		notify()
	end

	const function onCharacterAdded(char: Model)
		for _, conn in connections do
			conn:Disconnect()
		end
		table.clear(connections)
		clearTracked()

		const pack = player:WaitForChild("Backpack") :: Backpack
		monitorInventory(char, pack)
	end

	table.insert(connections, player.CharacterAdded:Connect(onCharacterAdded))
	if player.Character then
		onCharacterAdded(player.Character)
	end

	const function getSnapshot(): Snapshot
		const snapshotItems: { [number]: SlotItem } = {}
		for index, item in items do
			snapshotItems[index] = {
				item = item,
				equipped = isEquipped(item),
			}
		end
		return { items = snapshotItems }
	end

	const function activateItem(item: BackpackItem)
		if item:IsA("HopperBin") then
			warn(`[Satchel] Cannot select '{item}' hopper. HopperBin is deprecated and not supported.`)
			return
		end

		const char = character
		if not char then
			return
		end

		const humanoid = char:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		if isEquipped(item) then
			humanoid:UnequipTools()
		else
			humanoid:EquipTool(item)
		end
	end

	const function setHotbarSlotCount(count: number)
		hotbarSlotCount = count
		notify()
	end

	const function subscribe(listener: () -> ()): () -> ()
		table.insert(listeners, listener)
		return function()
			const index = table.find(listeners, listener)
			if index then
				table.remove(listeners, index)
			end
		end
	end

	const function destroy()
		for _, conn in connections do
			conn:Disconnect()
		end
		table.clear(connections)
		clearTracked()
		table.clear(listeners)
		character = nil
		backpack = nil
	end

	return {
		getSnapshot = getSnapshot,
		activateItem = activateItem,
		setHotbarSlotCount = setHotbarSlotCount,
		subscribe = subscribe,
		destroy = destroy,
	}
end

return {
	create = create,
}
