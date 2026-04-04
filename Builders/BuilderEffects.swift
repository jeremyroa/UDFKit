public actor BuilderEffects<State: StoreState, Action: StoreAction>: Effect {
    private typealias EffectFunction = (State, Action, ((Action) async -> Void)?) async -> Action?

    private var activeEffectTasks: [String: Task<EffectFunction, Never>]

    public init() {
        activeEffectTasks = [:]
    }

    deinit {
        for task in activeEffectTasks.values {
            task.cancel()
        }
        activeEffectTasks.removeAll()
    }

    public nonisolated func registerEffect<E: Effect>(
        _ keyPath: KeyPath<State, E.State>,
        _ effect: E
    ) where E.Action: StoreAction {
        Task { [weak self] in
            await self?.addEffect(effect, keyPath: keyPath)
        }
    }

    public func process(state: State, with action: Action, dispatch: ((Action) async -> Void)?) async -> Action? {
        await processEffectsInParallel(state: state, action: action, dispatch: dispatch)
    }

    private func addEffect<E: Effect>(
        _ effect: E,
        keyPath: KeyPath<State, E.State>
    ) where E.Action: StoreAction {
        let effectID = "\(type(of: effect))_\(keyPath)"

        guard activeEffectTasks[effectID] == nil else {
            return
        }

        let effectTask = createEffectTask(for: effect, keyPath: keyPath)
        activeEffectTasks[effectID] = effectTask
    }

    private func createEffectTask<E: Effect>(
        for effect: E,
        keyPath: KeyPath<State, E.State>
    ) -> Task<EffectFunction, Never> where E.Action: StoreAction {
        Task<EffectFunction, Never> {
            { [weak self] state, action, mainDispatcher in
                guard !Task.isCancelled else {
                    return nil
                }
                return await self?.processAction(
                    action,
                    withEffect: effect,
                    state: state,
                    keyPath: keyPath,
                    mainStoreDispatch: mainDispatcher
                )
            }
        }
    }

    private func processAction<E: Effect>(
        _ mainAction: Action,
        withEffect effect: E,
        state: State,
        keyPath: KeyPath<State, E.State>,
        mainStoreDispatch: ((Action) async -> Void)?
    ) async -> Action? where E.Action: StoreAction {
        let mainActionWrapperType = mainAction is any StoreActionWrapper ? type(of: mainAction) : nil

        let actionToProcessForSubEffect: E.Action? = switch mainAction {
        case let wrappedAction as any StoreActionWrapper:
            wrappedAction.unwrapAs()
        case let directAction as E.Action:
            directAction
        default:
            nil
        }

        guard let actionToProcessForSubEffect else {
            return nil
        }

        let dispatcherForSubEffect: ((E.Action) async -> Void)?
        if let mainStoreDispatch = mainStoreDispatch {
            dispatcherForSubEffect = { [mainActionWrapperType] subEffectActionToDispatch in
                let mainActionToDispatchViaStore: Action?
                if let wrapperType = mainActionWrapperType as? any StoreActionWrapper.Type {
                    mainActionToDispatchViaStore = wrapperType.wrap(subEffectActionToDispatch) as? Action
                } else {
                    mainActionToDispatchViaStore = subEffectActionToDispatch as? Action
                }

                if let finalAction = mainActionToDispatchViaStore {
                    await mainStoreDispatch(finalAction)
                }
            }
        } else {
            dispatcherForSubEffect = nil
        }

        let subState = state[keyPath: keyPath]

        let effectResultFromSubEffect = await effect.process(
            state: subState,
            with: actionToProcessForSubEffect,
            dispatch: dispatcherForSubEffect
        )

        guard let effectResultFromSubEffect else {
            return nil
        }

        if let wrapperType = mainActionWrapperType as? any StoreActionWrapper.Type {
            return wrapperType.wrap(effectResultFromSubEffect) as? Action
        }
        return effectResultFromSubEffect as? Action
    }

    private func processEffectsInParallel(
        state: State,
        action: Action,
        dispatch: ((Action) async -> Void)?
    ) async -> Action? {
        await withTaskGroup(of: Action?.self) { group in
            for task in activeEffectTasks.values {
                group.addTask {
                    let taskEffect = await task.value
                    return await taskEffect(state, action, dispatch)
                }
            }

            for await result in group {
                if let action = result {
                    return action
                }
            }
            return nil
        }
    }
}
