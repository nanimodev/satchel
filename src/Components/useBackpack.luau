--!strict

-- TODO: Refactor to be more clean

const React = require("../../react")

const BackpackController = require("../Controllers/BackpackController")

export type SlotItem = BackpackController.SlotItem

export type BackpackState = {
	items: { [number]: SlotItem },
	onSlotActivated: (item: BackpackItem) -> (),
}

const function useBackpack(player: Player, bindableEvents: Folder, hotbarSlotCount: number): BackpackState
	const snapshot, setSnapshot = React.useState(function()
		return { items = {} :: { [number]: SlotItem } }
	end)

	const controllerRef = React.useRef(nil :: BackpackController.Controller?)

	React.useEffect(function()
		const controller = BackpackController.create(player, bindableEvents)

		controllerRef.current = controller
		controller.setHotbarSlotCount(hotbarSlotCount)

		const function sync()
			setSnapshot(controller.getSnapshot())
		end

		sync()

		const unsubscribe = controller.subscribe(sync)

		return function()
			unsubscribe()
			controller.destroy()
			controllerRef.current = nil
		end
	end, { player, bindableEvents })

	React.useEffect(function()
		const controller = controllerRef.current
		if controller then
			controller.setHotbarSlotCount(hotbarSlotCount)
		end
	end, { hotbarSlotCount })

	const onSlotActivated = React.useCallback(function(item: BackpackItem)
		const controller = controllerRef.current
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
