--!strict
-- Purse-style tool tracking: slotByTool map, ChildAdded/Removed, direct React updates.

const React = require("../../react")

const bindableEvents = script.Parent.Parent.BindableEvents

export type BackpackState = {
	items: { [number]: { item: BackpackItem, equipped: boolean } },
	onSlotActivated: (item: BackpackItem) -> (),
}

const function useBackpack(player: Player, hotbarSlotCount: number): BackpackState
	const items, setItems = React.useState(function()
		return {} :: { [number]: { item: BackpackItem, equipped: boolean } }
	end)
	const equipRef = React.useRef(nil :: ((item: BackpackItem) -> ())?)

	React.useEffect(function()
		local slots: { [number]: Tool } = {}
		local slotByTool: { [Tool]: number } = {}
		local equippedState: { [Tool]: boolean } = {}
		local connections: { RBXScriptConnection } = {}
		local character: Model? = nil
		local backpack: Backpack? = nil

		local function isEquipped(tool: Tool): boolean
			return character ~= nil and tool.Parent == character
		end

		local function sync()
			local nextItems: { [number]: { item: BackpackItem, equipped: boolean } } = {}
			for index, tool in slots do
				nextItems[index] = { item = tool, equipped = isEquipped(tool) }
			end
			setItems(nextItems)
		end

		local function lowestEmptyHotbar(): number?
			for index = 1, hotbarSlotCount do
				if not slots[index] then
					return index
				end
			end
			return nil
		end

		local function nextInventorySlot(): number
			local maxIndex = hotbarSlotCount
			for index in slots do
				maxIndex = math.max(maxIndex, index)
			end
			return maxIndex + 1
		end

		local function clearTool(tool: Tool)
			local index = slotByTool[tool]
			if index == nil then
				return
			end
			slots[index] = nil
			slotByTool[tool] = nil
			equippedState[tool] = nil
			bindableEvents.BackpackItemRemoved:Fire(tool)
		end

		local function updateEquip(tool: Tool)
			local now = isEquipped(tool)
			local was = equippedState[tool]
			if was == nil then
				equippedState[tool] = now
				if now then
					bindableEvents.BackpackItemEquipped:Fire(tool)
				end
			elseif was ~= now then
				equippedState[tool] = now
				if now then
					bindableEvents.BackpackItemEquipped:Fire(tool)
				else
					bindableEvents.BackpackItemUnequipped:Fire(tool)
				end
			end
		end

		-- Same flow as Purse OnChildAdded: existing tool updates equip, new tool fills a slot.
		local function handleTool(tool: Tool)
			if slotByTool[tool] then
				updateEquip(tool)
				return
			end
			local emptyHotbar = lowestEmptyHotbar()
			local index = if emptyHotbar then emptyHotbar else nextInventorySlot()
			slots[index] = tool
			slotByTool[tool] = index
			bindableEvents.BackpackItemAdded:Fire(tool)
			updateEquip(tool)
		end

		local function onChildAdded(child: Instance)
			if child:IsA("Tool") then
				handleTool(child)
				sync()
			end
		end

		-- Same as Purse OnChildRemoved: ignore reparents between backpack and character.
		local function onChildRemoved(child: Instance)
			if not child:IsA("Tool") then
				return
			end
			local tool = child :: Tool
			local parent = tool.Parent
			if parent == character or parent == backpack then
				return
			end
			if slotByTool[tool] then
				clearTool(tool)
				sync()
			end
		end

		local function disconnectInventory()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			table.clear(slots)
			table.clear(slotByTool)
			table.clear(equippedState)
		end

		local function onCharacterAdded(char: Model)
			disconnectInventory()
			character = char
			local pack = player:WaitForChild("Backpack") :: Backpack
			backpack = pack

			table.insert(connections, char.ChildAdded:Connect(onChildAdded))
			table.insert(connections, char.ChildRemoved:Connect(onChildRemoved))
			table.insert(connections, pack.ChildAdded:Connect(onChildAdded))
			table.insert(connections, pack.ChildRemoved:Connect(onChildRemoved))

			for _, child in pack:GetChildren() do
				if child:IsA("Tool") then
					handleTool(child)
				end
			end
			for _, child in char:GetChildren() do
				if child:IsA("Tool") then
					handleTool(child)
				end
			end
			sync()
		end

		equipRef.current = function(item: BackpackItem)
			if not item:IsA("Tool") then
				return
			end
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not humanoid then
				return
			end
			if isEquipped(item) then
				humanoid:UnequipTools()
			else
				humanoid:EquipTool(item)
			end
		end

		local characterConnection = player.CharacterAdded:Connect(onCharacterAdded)
		if player.Character then
			onCharacterAdded(player.Character)
		end

		return function()
			characterConnection:Disconnect()
			disconnectInventory()
			equipRef.current = nil
		end
	end, { player :: any, hotbarSlotCount :: any })

	const onSlotActivated = React.useCallback(function(item: BackpackItem)
		local equip = equipRef.current
		if equip then
			equip(item)
		end
	end, {})

	return {
		items = items,
		onSlotActivated = onSlotActivated,
	}
end

return useBackpack
