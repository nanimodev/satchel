--!strict

const React = require("../../react")

const BackpackController = require("../Controllers/BackpackController")

export type SlotItem = BackpackController.SlotItem

export type BackpackState = {

	items: { [number]: SlotItem },

	onSlotActivated: (item: Tool | HopperBin) -> (),
}

local function useBackpack(player: Player, bindableEvents: Folder, hotbarSlotCount: number): BackpackState
	local snapshot, setSnapshot = React.useState(function()
		return { items = {} :: { [number]: SlotItem } }
	end)

	local controllerRef = React.useRef(nil :: BackpackController.Controller?)

	React.useEffect(function()
		local controller = BackpackController.create(player, bindableEvents)

		controllerRef.current = controller

		controller.setHotbarSlotCount(hotbarSlotCount)

		local function sync()
			setSnapshot(controller.getSnapshot())
		end

		sync()

		local unsubscribe = controller.subscribe(sync)

		return function()
			unsubscribe()

			controller.destroy()

			controllerRef.current = nil
		end
	end, { player, bindableEvents })

	React.useEffect(function()
		local controller = controllerRef.current

		if controller then
			controller.setHotbarSlotCount(hotbarSlotCount)
		end
	end, { hotbarSlotCount })

	local onSlotActivated = React.useCallback(function(item: Tool | HopperBin)
		local controller = controllerRef.current

		if controller then
			controller.activateItem(item)
		end
	end, {})

	return {

		items = snapshot.items,

		onSlotActivated = onSlotActivated,
	}
end

return useBackpack
